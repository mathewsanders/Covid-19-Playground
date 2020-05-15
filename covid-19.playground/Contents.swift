import SwiftUI
import PlaygroundSupport

struct Covid19Model {
    
    typealias ProjectionTarget = (newCases: Int, days: Int)
    typealias InputCsvInfo = (fileName: String, dateFormat: String)
    typealias SmoothingFactors = (fatalitySmoothing: Int, r0Smoothing: Int)

    let r0: [Date: Double?]
    let newCases: [Date: Double]
    let cumulatedCases: [Date: Double]
    let fatalities: [Date: Double]
    
    /**
     Creates a model for Covid-19 based on confimred fatalities and other variables.
     
     - Parameters:
        - unreportedFatalities: The percentage of fatalities that are not reported  (for example NY State currently reports only confirmed cases from hospitals and nursing homes. Fatalities that occur at home, or for people with symptoms that were not tested and diagnosed are not counted as confirmed cases). This value is used when the input CSV does not contain a value of probable deaths for a day
        - fatalityRate: The percentage cases that will lead to fatality.
        - incubationPeriod: The mean number of days from becoming infected to onset of symptoms.
        - serialInterval: The number of days between successive cases in a chain of transmission.
        - projectionTarget: Targets used to determine how far ahead to project estimates.
        - inputCSVInfo: information about the csv file that contains infomration on confirmed and probable deaths.
        - smoothing: information about moving average periods to apply to smooth estimates
        
     When projecting forward into the future, this value is used to determine how far in advance to project. for example setting this value to `(newCases: 0, days: 90)` will attempt to project forward to the day where the number of new cases is zero, or 90 days - which ever occurs first.
     Note: If recent average for R0 is not less than 1, then the target for new cases will never be met because new cases will continue to increase.
     
     The Playground resources folder should contain a csv file with two columns
     - First column: date of confirmed fatalties
     - Second column: number of confirmed deaths
     - Third column: number of probably deaths (optional)
     If a value for probable deaths is not provided, then a value is cacluated using unreportedFatalities.
     */
    init(unreportedFatalities: Double = 50.0,
         serialInterval: Int = 4,
         incubationPeriod: Int = 4,
         fatalityPeriod: Int = 13,
         fatalityRate: Double = 1.4,
         projectionTarget: ProjectionTarget = (newCases: 0, days: 1),
         inputCSVInfo: InputCsvInfo = (fileName: "data", dateFormat: "MM/dd/yyyy"),
         smoothing: SmoothingFactors = (fatalitySmoothing: 7, r0Smoothing: 7)) {
        
        assert((0.0...100).contains(unreportedFatalities), "Percentage of unreported fatalities must be between 0 and 100%")
        assert((1...30).contains(incubationPeriod), "Incubation period must be beween 1 and 30 days")
        assert((1...30).contains(fatalityPeriod), "Fatality period must be beween 1 and 30 days")
        assert((0.1...10).contains(fatalityRate), "Fatality rate must be beween 0.1 and 10")
        assert(projectionTarget.newCases >= 0, "target for new cases must be 0 or above")
        assert((1...7).contains(smoothing.fatalitySmoothing), "Fatality smoothing must be between 1 and 7")
        assert((1...7).contains(smoothing.r0Smoothing), "R0 smoothing must be between 1 and 7")
        
        let daysRatio: TimeInterval = 24*60*60
        let fileURL = Bundle.main.url(forResource: inputCSVInfo.fileName, withExtension: "csv")!
        let content = try! String(contentsOf: fileURL, encoding: String.Encoding.utf8)

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX") // set locale to reliable US_POSIX
        dateFormatter.dateFormat = inputCSVInfo.dateFormat // expected date format in CSV file
        
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
            }).dropLast(5)
        
        let cumulativeFatalities = parsedCSV.reduce(Array<(Date, Double)>(), { cumulativeFatalities, newFatalities in
            if let previousDay = cumulativeFatalities.last {
                return cumulativeFatalities + [(newFatalities.0, newFatalities.1 + previousDay.1)]
            }
            return [newFatalities]
        })
        
        let fatalityDates = cumulativeFatalities.map({ return $0.0})
        let fatalityCounts = cumulativeFatalities.map({ return $0.1})
        
        let fatalitiesMovingAverages = fatalityCounts.indices.map({ index -> Double in
            let possibleMinOffset = index-(smoothing.fatalitySmoothing-1)
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
        
        print("averageR0", averageR0)
        
        let lastDate = sortedR0.last!.0
        
        let projectedDates: [Date] = (0..<projectionTarget.days).map{ offset in
            let date = lastDate.advanced(by: daysRatio * TimeInterval(offset))
            return date
        }
        
        self.newCases = projectedDates.reduce(estimatedNewCases, { cases, newDate in
            let previousDate = newDate.advanced(by: daysRatio * TimeInterval(-serialInterval))
            let previousCases = cases[previousDate] ?? 0
            let newCases = previousCases * averageR0
            return cases.merging([newDate: newCases], uniquingKeysWith: { _, new in new })
        })
        
        self.cumulatedCases = newCases.sorted().reduce(Dictionary<Date,Double>(), {cumulatedCases, newCases in
            let previousDate = newCases.date.advanced(by: -daysRatio)
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
}

///Create a model with estimates on variables for Covid-19
let model = Covid19Model(
                unreportedFatalities: 50,
                serialInterval: 4,
                incubationPeriod: 4,
                fatalityPeriod: 13,
                fatalityRate: 1.4,
                projectionTarget: (newCases: 0, days: 90),
                inputCSVInfo: (fileName: "data", dateFormat: "MM/dd/yyyy"),
                smoothing: (fatalitySmoothing: 7, r0Smoothing: 1)
            )

struct Charts: View {
    var body: some View {
        VStack {
            Chart(data: model.estimatedR0Data,
                  title: "R0", forceMaxValue: 1.0)
                .frame(width: 600, height: 250)
                .background(Color.blue)

            Chart(data: model.cumulatedCases.sorted(),
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
