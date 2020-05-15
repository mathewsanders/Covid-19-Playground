import SwiftUI
import PlaygroundSupport

struct Covid19Model {
    
    typealias InputCsvInfo = (fileName: String, dateFormat: String)
    typealias SmoothingFactors = (inputSmoothing: Int, inputDrop: Int,  r0Smoothing: Int)

    let r0: [Date: Double?]
    let newCases: [Date: Double]
    let cumulativeCases: [Date: Double]
    let fatalities: [Date: Double]
    
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
         fatalityPeriod: Int = 13,
         fatalityRate: Double = 1.4,
         projectionTarget: Int = 30,
         inputCSVInfo: InputCsvInfo = (fileName: "data", dateFormat: "MM/dd/yy"),
         smoothing: SmoothingFactors = (inputSmoothing: 7, inputDrop: 5, r0Smoothing: 7)) {
        
        assert((0.0...100).contains(unreportedFatalities), "Percentage of unreported fatalities must be between 0 and 100%")
        assert((1...30).contains(incubationPeriod), "Incubation period must be beween 1 and 30 days")
        assert((1...30).contains(fatalityPeriod), "Fatality period must be beween 1 and 30 days")
        assert((0.1...10).contains(fatalityRate), "Fatality rate must be beween 0.1 and 10")
        assert(projectionTarget >= 0, "Number of days to project model forward must be 0 or above")
        assert((1...7).contains(smoothing.inputSmoothing), "Input smoothing must be between 1 and 7")
        assert((1...7).contains(smoothing.r0Smoothing), "R0 smoothing must be between 1 and 7")
        
        let fileURL = Bundle.main.url(forResource: inputCSVInfo.fileName, withExtension: "csv")!
        let content = try! String(contentsOf: fileURL, encoding: String.Encoding.utf8)

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX") // set locale to reliable US_POSIX
        dateFormatter.dateFormat = inputCSVInfo.dateFormat // expected date format in CSV file
        self.dateFormatter = dateFormatter
        
        let parsedCSV: [(Date, Double)] = content.components(separatedBy: "\n")
            .compactMap({ line in
                let components = line.components(separatedBy: ",")
                if let date = dateFormatter.date(from: components[0]),
                    let confirmedFatalities = Int(components[1].trimmingCharacters(in: .whitespacesAndNewlines)) {
                    
                    let probableFatalities = Double(components[2].trimmingCharacters(in: .whitespacesAndNewlines)) ?? Double(confirmedFatalities) * (Double(unreportedFatalities)/100.0)
                    
                    let totalFatalities = Double(confirmedFatalities) + probableFatalities
                                        
                    return (date, totalFatalities)
                }
                return nil
            }).dropLast(smoothing.inputDrop)
        
        let cumulativeFatalities = parsedCSV.reduce(Array<(Date, Double)>(), { cumulativeFatalities, newFatalities in
            if let previousDay = cumulativeFatalities.last {
                return cumulativeFatalities + [(newFatalities.0, newFatalities.1 + previousDay.1)]
            }
            return [newFatalities]
        })
        
        let fatalityDates = cumulativeFatalities.map({ return $0.0})
        let fatalityCounts = cumulativeFatalities.map({ return $0.1})
        
        let fatalitiesMovingAverages = fatalityCounts.indices.map({ index -> Double in
            let possibleMinOffset = index-(smoothing.inputSmoothing-1)
            let minRange = possibleMinOffset < 0 ? 0 : possibleMinOffset
            let range = (minRange...index)
            let slice = fatalityCounts[range]
            let average = Double(slice.reduce(0, +)) / Double(range.count)
            return average
        })

        let datesFatalitiesMovingAverage = zip(fatalityDates, fatalitiesMovingAverages)
        let estimatedFatalities = Dictionary(uniqueKeysWithValues: datesFatalitiesMovingAverage)
        
        let estimatedCumulativeCases: [Date: Double] = estimatedFatalities.temporalMap(
            dateOffset: -(incubationPeriod + fatalityPeriod),
            transformer: { _ , cumulativeFatalities, infectionDate, _ in
                let cumulativeCases = cumulativeFatalities * (100.0 / fatalityRate)
                return(infectionDate, cumulativeCases)
            }
        )
        
        let estimatedNewCases: [Date: Double] = estimatedCumulativeCases.temporalMap(
            dateOffset: -1,
            transformer: { dateToday, cumulativeCasesToday, dateYesterday, cumulativeCasesYesterday in
                let newCases = cumulativeCasesToday - (cumulativeCasesYesterday ?? 0)
                return (dateToday, newCases)
            }
        )
                
        self.r0 = estimatedNewCases.temporalMap(
            dateOffset: serialInterval,
            transformer: { dateToday, newCasesToday, dateFuture, newCasesFuture in
                if newCasesToday.isZero || newCasesFuture == nil {
                    return (dateToday, nil)
                }
                let r0 = newCasesFuture! / newCasesToday
                return (dateToday, r0)
            }
        )
                
        let sortedR0 = r0.filter({ $0.value != nil }).sorted()
        let recentR0 = sortedR0.suffix(smoothing.r0Smoothing)
        
        let averageR0 = recentR0
            .compactMap({ $0.1 })
                .reduce(0.0, +)
                    / Double(smoothing.r0Smoothing)
        let lastDate = sortedR0.last!.0
        
        print("Average R0 from \(smoothing.r0Smoothing) days ending \(self.dateFormatter.string(from: lastDate))")
        print(" - ", Double(Int(averageR0*100))/100)
        
        let projectedDates: [Date] = (0..<projectionTarget).map{ offset in
            let date = lastDate.advanced(by: Covid19Model.daysRatio * TimeInterval(offset))
            return date
        }
        
        self.newCases = projectedDates.reduce(estimatedNewCases, { cases, newDate in
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
    }
    
    var estimatedR0Data: [(Date, Double)] {
        return self.r0.sorted().compactMap({
            if let value = $0.value {
                return ($0.date, value)
            }
            return nil
        })
    }
    
    func printSummary() {
        if let earliestDate = self.newCases.sorted().first?.date {
            
            let daysBetweenEarliestDateAndToday = (earliestDate
                .distance(to: Date())/Covid19Model.daysRatio)
                    .rounded(.down) * Covid19Model.daysRatio
            
            let dateToday = earliestDate.addingTimeInterval(daysBetweenEarliestDateAndToday)
            
            print("Estimated values for today \(dateFormatter.string(from: dateToday))")
            
            if let fatalitiesToday = self.fatalities[dateToday] {
                print(" - fatalities:", Int(fatalitiesToday))
            }
            
            if let newCasesToday = self.newCases[dateToday] {
                print(" - new cases:", Int(newCasesToday))
            }
            
            if let cumulativeCasesToday = self.cumulativeCases[dateToday] {
                print(" - cumulative cases:", Int(cumulativeCasesToday))
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
                    item.value.r0??.description ?? "",
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
                serialInterval: 4,
                incubationPeriod: 4,
                fatalityPeriod: 13,
                fatalityRate: 1.4,
                projectionTarget: 90,
                inputCSVInfo: (fileName: "data", dateFormat: "MM/dd/yy"),
                smoothing: (inputSmoothing: 7, inputDrop: 5, r0Smoothing: 2)
            )

model.printSummary()
model.saveOutput()

struct Charts: View {
    var body: some View {
        VStack {
            Chart(data: model.estimatedR0Data,
                  title: "R0", forceMaxValue: 1.0)
                .frame(width: 600, height: 250)
                .background(Color.blue)

            Chart(data: model.cumulativeCases.sorted(),
                  title: "Cumulative Cases")
                .frame(width: 600, height: 250)
                .background(Color.yellow)
            
            Chart(data: model.fatalities.sorted(),
                  title: "Fatalities", forceMaxValue: 10)
                .frame(width: 600, height: 250)
                .background(Color.gray)
            
            Chart(data: model.newCases.sorted(),
                  title: "New Cases", forceMaxValue: 1000)
                .frame(width: 600, height: 250)
                .background(Color.green)
        }
    }
}

PlaygroundPage.current.setLiveView(Charts())
