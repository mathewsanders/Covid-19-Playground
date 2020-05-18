import SwiftUI
import PlaygroundSupport

struct Covid19Model {
    
    typealias InputCsvInfo = (
        fatalityDataFileName: String,
        hospitalizationDataFileName: String,
        dateFormat: String
    )
    
    typealias SmoothingFactors = (inputSmoothing: Int, inputDrop: Int,  r0Smoothing: Int)

    let estimatedNewCasesByFatalityRate: [Date: Double]
    let estimatedNewCasesByHospitalizationsRate: [Date: Double]
    let estimatedNewCasesByAverage: [Date: Double]
    
    let estimatedR0ByFatalityRate: [Date: Double]
    let estimatedR0ByHospitalizationsRate: [Date: Double]
    let estimatedR0ByAverage: [Date: Double]
    
    let r0: [Date: Double]
    let newCases: [Date: Double]
    let cumulativeCases: [Date: Double]
    let fatalities: [Date: Double]
    let hospitalizations: [Date: Double]
    
    let smoothing: SmoothingFactors
    
    private let dateFormatter: DateFormatter
    
    // number of seconds in a day
    static let daysRatio: TimeInterval = 24*60*60
    
    /**
     Creates a model for Covid-19 based on confimred fatalities and other variables.
     
     - Parameters:
        - unreportedFatalities: The percentage of fatalities that are not reported  (for example NY State currently reports only confirmed cases from hospitals and nursing homes. Fatalities that occur at home, or for people with symptoms that were not tested and diagnosed are not counted as confirmed cases). This value is used when the input CSV does not contain a value of probable deaths for a day
        - fatalityRate: The percentage cases that will lead to fatality.
        - incubationPeriod: The mean number of days from becoming infected to onset of symptoms.
        - serialInterval: The number of days between successive cases in a chain of transmission.
        - projectionTarget: The number of days to project forward using most recent R0 values.
        - inputCSVInfo: information about the csv file that contains infomration on confirmed and probable deaths.
        - smoothing: information about moving average periods to apply to smooth estimates
     
     The Playground resources folder should contain a csv file with two columns
     - First column: date of death
     - Second column: number of confirmed deaths
     - Third column: number of probable deaths (optional)
     If a value for probable deaths is not provided, then a value is cacluated using unreportedFatalities.
     */
    init(unreportedFatalities: Double = 50.0,
         serialInterval: Int = 4,
         incubationPeriod: Int = 4,
         hospitalizationPeriod: Int = 5,
         hospitalizationRate: Double = 1.0,
         fatalityPeriod: Int = 13,
         fatalityRate: Double = 1.4,
         projectionTarget: Int = 30,
         inputCSVInfo: InputCsvInfo = (
            fatalityDataFileName: "fatality-data",
            hospitalizationDataFileName: "hospitalization-data",
            dateFormat: "MM/dd/yy"
        ),
         smoothing: SmoothingFactors = (inputSmoothing: 7, inputDrop: 5, r0Smoothing: 7)) {
        
        assert((0.0...100).contains(unreportedFatalities), "Percentage of unreported fatalities must be between 0 and 100%")
        assert((1...30).contains(incubationPeriod), "Incubation period must be beween 1 and 30 days")
        assert((1...30).contains(fatalityPeriod), "Fatality period must be beween 1 and 30 days")
        assert((0.1...10).contains(fatalityRate), "Fatality rate must be beween 0.1 and 10")
        assert(projectionTarget >= 0, "Number of days to project model forward must be 0 or above")
        assert((0...14).contains(smoothing.inputSmoothing), "Input smoothing must be between 1 and 7")
        assert((0...14).contains(smoothing.r0Smoothing), "R0 smoothing must be between 1 and 7")
        
        self.smoothing = smoothing
        
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX") // set locale to reliable US_POSIX
        dateFormatter.dateFormat = inputCSVInfo.dateFormat // expected date format in CSV file
        self.dateFormatter = dateFormatter
        
        let fatalityDataFileURL = Bundle.main.url(forResource: inputCSVInfo.fatalityDataFileName, withExtension: "csv")!
        let fatalityDataContent = try! String(contentsOf: fatalityDataFileURL, encoding: String.Encoding.utf8)
        
        let hospitalizationDataFileURL = Bundle.main.url(forResource: inputCSVInfo.hospitalizationDataFileName, withExtension: "csv")!
        let hospitalizationDataContent = try! String(contentsOf: hospitalizationDataFileURL, encoding: String.Encoding.utf8)

        // expected format from https://raw.githubusercontent.com/nychealth/coronavirus-data/master/Deaths/probable-confirmed-dod.csv
        // components[0] -> date_of_death
        // components[1] -> CONFIRMED_COUNT
        // components[2] -> PROBABLE_COUNT
        let parsedFatalityCSV: [(Date, Double)] = fatalityDataContent.components(separatedBy: "\n")
            .compactMap({ line in
                let components = line.components(separatedBy: ",")
                if let date = dateFormatter.date(from: components[0]),
                    let confirmedFatalities = Int(components[1].trimmingCharacters(in: .whitespacesAndNewlines)) {
                    
                    let probableFatalities = Double(components[2].trimmingCharacters(in: .whitespacesAndNewlines)) ?? Double(confirmedFatalities) * (Double(unreportedFatalities)/100.0)
                    
                    let totalFatalities = Double(confirmedFatalities) + probableFatalities
                                        
                    return (date, totalFatalities)
                }
                return nil
            })
            .dropLast(smoothing.inputDrop)
                
        let reportedFatalities: [Date: Double] = Dictionary(uniqueKeysWithValues:  parsedFatalityCSV.map({ ($0.0, $0.1) }))
                                                    .movingAverage(period: smoothing.inputSmoothing)
        
        // expected format from https://raw.githubusercontent.com/nychealth/coronavirus-data/master/case-hosp-death.csv
        // components[0] -> DATE_OF_INTEREST
        // components[1] -> CASE_COUNT
        // components[2] -> HOSPITALIZED_COUNT
        // components[3] -> DEATH_COUNT
        let parsedHospitalizationCSV: [(Date, Double)] = hospitalizationDataContent.components(separatedBy: "\n")
            .compactMap({ line in
                let components = line.components(separatedBy: ",")
                if let date = dateFormatter.date(from: components[0]),
                    let confirmedHospitalization = Int(components[2].trimmingCharacters(in: .whitespacesAndNewlines)) {
                                        
                    return (date, Double(confirmedHospitalization))
                }
                return nil
            })
            .dropLast(smoothing.inputDrop)
        
        let reportedHospitalizations: [Date: Double] = Dictionary(uniqueKeysWithValues:  parsedHospitalizationCSV.map({ ($0.0, $0.1) }))
                                                        .movingAverage(period: smoothing.inputSmoothing)
        
        self.estimatedNewCasesByFatalityRate = reportedFatalities.temporalMap(dateOffset: -(incubationPeriod + fatalityPeriod), transformer: { _, newFatalities, infectionDate, _ in
            let newCases = newFatalities / (fatalityRate/100.0)
            return (infectionDate, newCases)
        })
        
        self.estimatedNewCasesByHospitalizationsRate = reportedHospitalizations.temporalMap(dateOffset: -(hospitalizationPeriod), transformer: { _, newHospitalizations, infectionDate, _ in
            let newCases = newHospitalizations / (hospitalizationRate/100.0)
            return (infectionDate, newCases)
        })
        
        self.estimatedNewCasesByAverage = temporalMerger(first: self.estimatedNewCasesByFatalityRate, second: self.estimatedNewCasesByHospitalizationsRate, merger: doubleDoubleMerger)//.movingAverage(period: 3)
                
        self.estimatedR0ByFatalityRate = estimatedNewCasesByFatalityRate.temporalMap(
            dateOffset: serialInterval,
            transformer: { dateToday, newCasesToday, dateFuture, newCasesFuture in
                if newCasesToday.isZero || newCasesFuture == nil {
                    return nil
                }
                let r0 = newCasesFuture! / newCasesToday
                return (dateToday, r0)
            }
        ).movingAverage(period: smoothing.r0Smoothing)
        
        self.estimatedR0ByHospitalizationsRate = estimatedNewCasesByHospitalizationsRate.temporalMap(
            dateOffset: serialInterval,
            transformer: { dateToday, newCasesToday, dateFuture, newCasesFuture in
                if newCasesToday.isZero || newCasesFuture == nil {
                    return nil
                }
                let r0 = newCasesFuture! / newCasesToday
                return (dateToday, r0)
            }
        ).movingAverage(period: smoothing.r0Smoothing)
        
        self.estimatedR0ByAverage = estimatedNewCasesByAverage.temporalMap(
            dateOffset: serialInterval,
            transformer: { dateToday, newCasesToday, dateFuture, newCasesFuture in
                if newCasesToday.isZero || newCasesFuture == nil {
                    return nil
                }
                let r0 = newCasesFuture! / newCasesToday
                return (dateToday, r0)
            }
        ).movingAverage(period: smoothing.r0Smoothing)
                
        self.r0 = self.estimatedR0ByAverage
        
        let lastR0 = self.r0.sorted().last!
        let averageR0 = lastR0.value
        let lastDate = lastR0.date
        
        print("Average R0 from \(smoothing.r0Smoothing) days ending \(self.dateFormatter.string(from: lastDate))")
        print(" - ", Double(Int(averageR0*100))/100)
        
        let projectedDates: [Date] = (0..<projectionTarget).map{ offset in
            let date = lastDate.advanced(by: Covid19Model.daysRatio * TimeInterval(offset))
            return date
        }
        
        self.newCases = projectedDates.reduce(estimatedNewCasesByAverage, { cases, newDate in
            let previousDate = newDate.advanced(by: Covid19Model.daysRatio * TimeInterval(-serialInterval))
            let previousCases = cases[previousDate] ?? 0
            let newCases = previousCases * averageR0
            return cases.merging([newDate: newCases], uniquingKeysWith: { _, new in new })
        })
        
        self.cumulativeCases = newCases.sorted().reduce(Dictionary<Date,Double>(), {cumulatedCases, newCases in
            let previousDate = newCases.date.advanced(by: -Covid19Model.daysRatio)
            let previousCumulated = cumulatedCases[previousDate] ?? 0
            let newCumulated = previousCumulated + newCases.value
            return cumulatedCases.merging([newCases.date: newCumulated], uniquingKeysWith: { _, new in new })
        })
        
        self.fatalities = self.newCases.temporalMap(
            dateOffset: incubationPeriod + fatalityPeriod,
            transformer: { _, newCases, fatalityDate, _ in
                let estimatedFatalities = newCases * (fatalityRate/100)
                return (fatalityDate, estimatedFatalities)
        })
        
        self.hospitalizations = self.newCases.temporalMap(dateOffset: incubationPeriod, transformer: { _, newCases, hospitalizationDate, _ in
            let estimatedHospitalizations = newCases * (hospitalizationRate/100)
            return (hospitalizationDate, estimatedHospitalizations)
        })
    }
    
    func printSummary() {
        if let earliestDate = self.newCases.sorted().first?.date {
            
            let daysBetweenEarliestDateAndToday = (earliestDate
                .distance(to: Date())/Covid19Model.daysRatio)
                    .rounded(.down) * Covid19Model.daysRatio
            
            let dateToday = earliestDate.addingTimeInterval(daysBetweenEarliestDateAndToday)
            
            print("Estimated values for today \(dateFormatter.string(from: dateToday))")
            
            dump(fatalities.sorted())
            
            if let fatalitiesToday = self.fatalities[dateToday] {
                print(" - fatalities:", Int(fatalitiesToday))
            }
            
            if let newCasesToday = self.newCases[dateToday] {
                print(" - new cases:", Int(newCasesToday))
            }
            
            if let cumulativeCasesToday = self.cumulativeCases[dateToday] {
                print(" - cumulative cases:", Int(cumulativeCasesToday))
            }
            
            if let newHospitalizations = self.hospitalizations[dateToday] {
                print(" - new hospitalizations:", Int(newHospitalizations))
            }
        }
    }
    
    func saveOutput() {
        print("...Saving case data to output.csv in your documents folder")
        
        let fileName = "output"
        let dir = try? FileManager.default.url(for: .documentDirectory,
              in: .userDomainMask, appropriateFor: nil, create: true)
        
        let merged = self.newCases.temporalMerge(other: self.cumulativeCases, merger: { new, cumulative in
            (new: new, cumulative: cumulative)
        })
        .temporalMerge(other: self.r0, merger: { cases, r0 in
            (new: cases?.new, cumulative: cases?.cumulative, r0: r0)
        })
        .temporalMerge(other: self.fatalities, merger: { cases, fatalities in
            (new: cases?.new, cumulative: cases?.cumulative, r0: cases?.r0, fatalities: fatalities)
        })
        let sorted = merged.sorted()
        
        // If the directory was found, we write a file to it and read it back
        if let fileURL = dir?.appendingPathComponent(fileName).appendingPathExtension("csv") {
            
            let outString = sorted.reduce("Date, Estimated New Cases, Estimated Cumulative Cases, Estimated Estimated R0, Estimated Fatalities\n") { text, item in
                let components: [String] = [
                    item.date.description,
                    item.value.new?.description ?? "",
                    item.value.cumulative?.description ?? "",
                    item.value.r0?.description ?? "",
                    item.value.fatalities?.description ?? ""
                ]
                return text + components.joined(separator: ",") + "\n"
            }
            
            do {
                try outString.write(to: fileURL, atomically: true, encoding: .utf8)
            } catch {
                print("Failed writing to URL: \(fileURL), Error: " + error.localizedDescription)
            }
        }
    }
}

///Create a model with estimates on variables for Covid-19
let model = Covid19Model(
                unreportedFatalities: 50,
                serialInterval: 5,
                incubationPeriod: 4,
                hospitalizationRate: 3.0,
                fatalityPeriod: 13,
                fatalityRate: 1.4,
                projectionTarget: 60,
                inputCSVInfo: (
                    fatalityDataFileName: "fatality-data",
                    hospitalizationDataFileName: "hospitalization-data",
                    dateFormat: "MM/dd/yyyy"
                ),
                smoothing: (
                    inputSmoothing: 0,
                    inputDrop: 7,
                    r0Smoothing: 0
                )
            )

model.printSummary()
//model.saveOutput()

struct Charts: View {
    var body: some View {
        VStack {
            
            Chart(data: model.estimatedNewCasesByFatalityRate.sorted(), title: "model.estimatedNewCasesByFatalityRate")
            .frame(width: 600, height: 250)
            .background(Color.green)
            
            Chart(data: model.estimatedNewCasesByHospitalizationsRate.sorted(), title: "model.estimatedNewCasesByHospitalizationsRate")
            .frame(width: 600, height: 250)
            .background(Color.green)
            
            Chart(data: model.estimatedR0ByFatalityRate.sorted(), title: "estimatedR0ByFatalityRate", forceMaxValue: 1.0)
            .frame(width: 600, height: 250)
            .background(Color.blue)
            
            Chart(data: model.estimatedR0ByHospitalizationsRate.sorted(), title: "estimatedR0ByHospitalizationsRate", forceMaxValue: 1.0)
            .frame(width: 600, height: 250)
            .background(Color.blue)
            
            Chart(data: model.estimatedR0ByAverage.sorted(), title: "estimatedR0ByAverage", forceMaxValue: 1.0)
            .frame(width: 600, height: 250)
            .background(Color.blue)
            
            Chart(data: model.newCases.sorted(), title: "New Cases")
                .frame(width: 600, height: 250)
                .background(Color.yellow)

            Chart(data: model.cumulativeCases.sorted(), title: "Cumulative Cases")
                .frame(width: 600, height: 250)
                .background(Color.yellow)
            
            Chart(data: model.fatalities.sorted(), title: "Fatalities")
                .frame(width: 600, height: 250)
                .background(Color.gray)
            
            Chart(data: model.hospitalizations.sorted(), title: "New Hospitalizations")
                .frame(width: 600, height: 250)
                .background(Color.green)
            

            
            Chart(data: model.estimatedNewCasesByAverage.sorted(), title: "model.estimatedNewCasesByAverage")
            .frame(width: 600, height: 250)
            .background(Color.green)
        }
    }
}

PlaygroundPage.current.setLiveView(Charts())
