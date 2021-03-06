import SwiftUI
import PlaygroundSupport

struct Covid19Model {
    
    typealias Paramaters = (
        fileName: String,
        dateFormat: String,
        inputDrop: Int,
        inputMovingAverage: Int,
        rate: Double,
        period: Int
    )

    let estimatedNewCasesByFatalityRate: [Date: Double]
    let estimatedNewCasesByHospitalizationsRate: [Date: Double]
    let estimatedNewCasesByAverage: [Date: Double]
    
    let estimatedRtByFatalityRate: [Date: Double]
    let estimatedRtByHospitalizationsRate: [Date: Double]
    let estimatedRtByAverage: [Date: Double]
    
    let rt: [Date: Double]
    let projectedNewCases: [Date: Double]
    let projectedCumulativeCases: [Date: Double]
    let projectedFatalities: [Date: Double]
    let projectedHospitalizations: [Date: Double]
    
    let fatalityParamaters: Paramaters
    let hospitalizationParamaters: Paramaters

    private let dateFormatter: DateFormatter
    
    // number of seconds in a day
    static let daysRatio: TimeInterval = 24*60*60
    
    static func rtEstimator(dateToday: Date, newCasesToday: Double, dateFuture: Date, newCasesFuture: Double?) -> (Date, Double)? {
        if let newCasesFuture = newCasesFuture, !newCasesToday.isZero {
            let rt = newCasesFuture / newCasesToday
            return (dateToday, rt)
        }
        return nil
    }
    
    static func doubleDoubleMerger(first: Double?, second: Double?) -> Double {
        switch (first, second) {
        case (let first?, let second?):
            return (first + second) / 2
        case (let first?, _):
            return first
        case (_, let second?):
            return second
        default:
            return 0
        }
    }
    
    init(serialInterval: Int = 4,
         incubationPeriod: Int = 4,
         hospitalizationParamaters: Paramaters,
         fatalityParamaters: Paramaters,
         projectionDays: Int = 30,
         projectionRtAverage: Int = 7) {
                
        self.hospitalizationParamaters = hospitalizationParamaters
        self.fatalityParamaters = fatalityParamaters
        
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX") // set locale to reliable US_POSIX
        dateFormatter.dateFormat = fatalityParamaters.dateFormat // expected date format in CSV file
        self.dateFormatter = dateFormatter
        
        let fatalityDataFileURL = Bundle.main.url(forResource: fatalityParamaters.fileName, withExtension: "csv")!
        let fatalityDataContent = try! String(contentsOf: fatalityDataFileURL, encoding: String.Encoding.utf8)
        
        let hospitalizationDataFileURL = Bundle.main.url(forResource: hospitalizationParamaters.fileName, withExtension: "csv")!
        let hospitalizationDataContent = try! String(contentsOf: hospitalizationDataFileURL, encoding: String.Encoding.utf8)

        // expected format from https://raw.githubusercontent.com/nychealth/coronavirus-data/master/Deaths/probable-confirmed-dod.csv
        // components[0] -> date_of_death
        // components[1] -> CONFIRMED_COUNT
        // components[2] -> PROBABLE_COUNT
        let parsedFatalityCSV: [(Date, Double)] = fatalityDataContent.components(separatedBy: "\n")
            .compactMap({ line in
                let components = line.components(separatedBy: ",")
                if let date = dateFormatter.date(from: components[0]) {
                    
                    let confirmedFatalities = Int(components[1].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                        
                    let probableFatalities = Double(components[2].trimmingCharacters(in: .whitespacesAndNewlines)) ?? Double(confirmedFatalities) * 0.40
                    
                    let totalFatalities = Double(confirmedFatalities) + probableFatalities
                                        
                    return (date, totalFatalities)
                }
                return nil
            })
            .dropLast(fatalityParamaters.inputDrop)
                
        let reportedFatalities: [Date: Double] = Dictionary(uniqueKeysWithValues:  parsedFatalityCSV.map({ ($0.0, $0.1) })).movingAverage(period: fatalityParamaters.inputMovingAverage)
        
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
            .dropLast(hospitalizationParamaters.inputDrop)
        
        let reportedHospitalizations: [Date: Double] = Dictionary(uniqueKeysWithValues:  parsedHospitalizationCSV.map({ ($0.0, $0.1) }))
            .movingAverage(period: hospitalizationParamaters.inputMovingAverage)
        
        self.estimatedNewCasesByFatalityRate = reportedFatalities.temporalMap(dateOffset: -(incubationPeriod + fatalityParamaters.period), transformer: { _, newFatalities, infectionDate, _ in
            let newCases = newFatalities / (fatalityParamaters.rate / 100.0)
            return (infectionDate, newCases)
        })
        
        self.estimatedNewCasesByHospitalizationsRate = reportedHospitalizations.temporalMap(dateOffset: -(hospitalizationParamaters.period), transformer: { _, newHospitalizations, infectionDate, _ in
            let newCases = newHospitalizations / (hospitalizationParamaters.rate / 100.0)
            return (infectionDate, newCases)
        })
        
        self.estimatedRtByFatalityRate = estimatedNewCasesByFatalityRate.temporalMap(
            dateOffset: serialInterval,
            transformer: Covid19Model.rtEstimator
        )
        
        self.estimatedRtByHospitalizationsRate = estimatedNewCasesByHospitalizationsRate.temporalMap(
            dateOffset: serialInterval,
            transformer: Covid19Model.rtEstimator
        )
        
        self.estimatedNewCasesByAverage = temporalMerger(first: self.estimatedNewCasesByFatalityRate, second: self.estimatedNewCasesByHospitalizationsRate, merger: Covid19Model.doubleDoubleMerger)
        
        self.estimatedRtByAverage = temporalMerger(first: self.estimatedRtByFatalityRate, second: self.estimatedRtByHospitalizationsRate, merger: Covid19Model.doubleDoubleMerger)
                
        self.rt = self.estimatedRtByAverage
        
        let recentRt = self.rt.sorted().suffix(projectionRtAverage)
        let averageRt = recentRt.map({ $0.value }).reduce(0.0, + ) / Double(projectionRtAverage)
        
        guard let lastDate = recentRt.last?.date else {
            fatalError("no recent Rt dates avaiable")
        }
        
        print("Average Rt from \(projectionRtAverage) days ending \(self.dateFormatter.string(from: lastDate))")
        print(" - ", Double(Int(averageRt*100))/100)
        
        let projectedDates: [Date] = (1..<projectionDays).map{ offset in
            let date = lastDate.advanced(by: Covid19Model.daysRatio * TimeInterval(offset))
            return date
        }
        
        self.projectedNewCases = projectedDates.reduce(estimatedNewCasesByAverage, { cases, newDate in

            let previousDate = newDate.advanced(by: Covid19Model.daysRatio * TimeInterval(-serialInterval))
            let previousCases = cases[previousDate] ?? 0
            let newCases = previousCases * averageRt
            return cases.merging([newDate: newCases], uniquingKeysWith: { _, new in new })
        })
        
        self.projectedFatalities = self.projectedNewCases.temporalMap(
            dateOffset: incubationPeriod + fatalityParamaters.period,
            transformer: { _, newCases, fatalityDate, _ in
                let estimatedFatalities = newCases * (fatalityParamaters.rate / 100)
                return (fatalityDate, estimatedFatalities)
        })
        
        self.projectedHospitalizations = self.projectedNewCases.temporalMap(dateOffset: incubationPeriod + hospitalizationParamaters.period, transformer: { _, newCases, hospitalizationDate, _ in
            let estimatedHospitalizations = newCases * (hospitalizationParamaters.rate / 100)
            return (hospitalizationDate, estimatedHospitalizations)
        })
        
        self.projectedCumulativeCases = projectedNewCases.sorted().reduce(Dictionary<Date,Double>(), {cumulatedCases, newCases in

            let previousDate = newCases.date.advanced(by: -Covid19Model.daysRatio)
            let previousCumulated = cumulatedCases[previousDate] ?? 0
            let newCumulated = previousCumulated + newCases.value
            return cumulatedCases.merging([newCases.date: newCumulated], uniquingKeysWith: { _, new in new })
        })
    }
    
    func printSummaryForToday() {
        
        let todayDate = Date()
            
        print("Estimated values for today \(dateFormatter.string(from: todayDate))")
            
        if let fatalitiesToday = self.projectedFatalities.sorted().last(where: { item in
            item.0 < todayDate
        }) {
            print(" - fatalities:", Int(fatalitiesToday.value))
        }
        
        if let newHospitalizations = self.projectedHospitalizations.sorted().last(where: { item in
            item.0 < todayDate
        }) {
            print(" - new hospitalizations:", Int(newHospitalizations.value))
        }
        
        if let newCasesToday = self.projectedNewCases.sorted().last(where: { item in
            item.0 < todayDate
        }) {
            print(" - new cases:", Int(newCasesToday.value))
        }
        
        if let cumulativeCasesToday = self.projectedCumulativeCases.sorted().last(where: { item in
            item.0 < todayDate
        }) {
            print(" - cumulative cases:", Int(cumulativeCasesToday.value))
        }
    }
    
    func saveOutput() {
        print("...Saving case data to output.csv in your documents folder")
        
        let fileName = "output"
        let dir = try? FileManager.default.url(for: .documentDirectory,
              in: .userDomainMask, appropriateFor: nil, create: true)
        
        let merged = self.projectedNewCases.temporalMerge(other: self.projectedCumulativeCases, merger: { new, cumulative in
            (new: new, cumulative: cumulative)
        })
        .temporalMerge(other: self.rt, merger: { cases, rt in
            (new: cases?.new, cumulative: cases?.cumulative, rt: rt)
        })
        .temporalMerge(other: self.projectedFatalities, merger: { cases, fatalities in
            (new: cases?.new, cumulative: cases?.cumulative, rt: cases?.rt, fatalities: fatalities)
        })
        let sorted = merged.sorted()
        
        // If the directory was found, we write a file to it and read it back
        if let fileURL = dir?.appendingPathComponent(fileName).appendingPathExtension("csv") {
            
            let outString = sorted.reduce("Date, Estimated New Cases, Estimated Cumulative Cases, Estimated Estimated Rt, Estimated Fatalities\n") { text, item in
                let components: [String] = [
                    item.date.description,
                    item.value.new?.description ?? "",
                    item.value.cumulative?.description ?? "",
                    item.value.rt?.description ?? "",
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
                serialInterval: 5, // mean number of days for infection to a new person
                incubationPeriod: 4, // mean number of days from infection to onset of symptoms
                hospitalizationParamaters: (
                    fileName: "hospitalization-data",
                    dateFormat: "MM/dd/yyyy",
                    inputDrop: 7, // ignore the most recent 7 days of values (NYC DOH seem to take up to 7 days before values for a day are stable)
                    inputMovingAverage: 0,
                    rate: 3.0, // percentage of cases that result in hospitalization
                    period: 9 // mean number of days from onset of symptoms to hospitilization
                ),
                fatalityParamaters: (
                    fileName: "fatality-data",
                    dateFormat: "MM/dd/yyyy",
                    inputDrop: 7, //(NYC DOH seem to take up to 7 days before values for a day are stable)
                    inputMovingAverage: 0,
                    rate: 1.4, // percentage of cases that result in death
                    period: 12 // mean number of days from onset of symptoms to death
                ),
                projectionDays: 51,
                projectionRtAverage: 7
            )

model.printSummaryForToday()
model.saveOutput()

let today = Date()

func isAfterToday(date: Date, value: Double) -> Bool {
    return date >= today
}

let earlyDate = Date(timeIntervalSince1970: 1583024400)

func isAfterEarlyDate(date: Date, value: Double) -> Bool {
    return date >= earlyDate
}

let projectedCases = model.projectedNewCases.sorted().suffix(51)
let projectedCasesLastRtUntilToday = projectedCases.prefix(20)
let projectedCasesTodayNext31Days = projectedCases.suffix(31).prefix(28)

struct Charts: View {
    var body: some View {
        VStack {
            
            Group{
                Chart(data: model.estimatedRtByFatalityRate.sorted().filter(isAfterEarlyDate), title: "Estimated Rt By Fatality Rate", forceMaxValue: 2.0)
                    .frame(width: 600, height: 250)
                    .background(Color.blue.opacity(0.5))
                
                Chart(data: model.estimatedRtByHospitalizationsRate.sorted().filter(isAfterEarlyDate), title: "Estimated Rt By Hospitalization Rate", forceMaxValue: 2.0)
                    .frame(width: 600, height: 250)
                    .background(Color.blue.opacity(0.5))
                
                Chart(data: model.rt.sorted().filter(isAfterEarlyDate), title: "Estimated Rt for NYC", forceMaxValue: 2.0)
                    .frame(width: 600, height: 350)
                    .padding()
                    .background(Color.blue)
                    
                
                Chart(data: model.rt.sorted().suffix(28), title: "Estimated Rt - last 28 days", forceMaxValue: 2.0)
                .frame(width: 600, height: 250)
                .background(Color.blue)
            }
            
            Group{
                Chart(data: model.estimatedNewCasesByFatalityRate.sorted(), title: "Estimated New Cases By Fatalities")
                    .frame(width: 600, height: 250)
                    .background(Color.yellow.opacity(0.5))
                
                Chart(data: model.estimatedNewCasesByHospitalizationsRate.sorted(), title: "Estimated New Cases By Hospitalizations")
                    .frame(width: 600, height: 250)
                    .background(Color.yellow.opacity(0.5))
            }
            
            Group {
               Chart(data: model.projectedCumulativeCases.sorted(), title: "Projected Cumulative Cases")
                   .frame(width: 600, height: 250)
                   .background(Color.yellow)
                
                Chart(data: Array(projectedCasesLastRtUntilToday), title: "projectedCasesLastRtUntilToday")
                    .frame(width: 600, height: 250)
                    .background(Color.yellow)
                
                Chart(data: Array(projectedCasesTodayNext31Days), title: "projectedCasesTodayNext31Days")
                .frame(width: 600, height: 250)
                .background(Color.yellow)
            }
            Chart(data: Array(model.projectedFatalities.sorted()), title: "Projected Fatalities - all time")
            .frame(width: 600, height: 250)
            .background(Color.gray)
            
            Chart(data: Array(model.projectedFatalities.sorted().suffix(47).prefix(28)), title: "Projected Fatalities - next 28 days")
                .frame(width: 600, height: 250)
                .background(Color.gray)
            
            Chart(data: Array(model.projectedHospitalizations.sorted().suffix(42).prefix(28)), title: "Projected Hospitalizations - next 28 days")
                .frame(width: 600, height: 250)
                .background(Color.green)
        }
    }
}
PlaygroundPage.current.setLiveView(Charts())

dump(model.projectedNewCases.sorted())
 
print(model.estimatedRtByAverage.sorted().last!)
