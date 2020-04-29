import SwiftUI
import PlaygroundSupport

struct CaseData: Hashable {
    /// Cumulative number of cases estimated by confirmed fatalities and fatality rate
    let estimatedCumulativeCases: Int?
    
    /// New cases estimated by confirmed fatalities and fatality rate
    let estimatedNewCases: Int?
    
    /// R0 estimated by estimate of new cases and serial interval
    let estimatedR0: Double?
    
    /// Cumulative number of cases estimated by using most recent R0 values
    let projectedCumulativeCases: Int?
    
    /// New cases estimated by projected by using most recent R0 values
    let projectedNewCases: Int?
    
    /// R0 estimated by average of recent R0 values
    let projectedR0: Double?
    
    var anyNewCases: Int {
        return estimatedNewCases ?? (projectedNewCases ?? 0)
    }
    
    var anyCumulativeCases: Int {
        return estimatedCumulativeCases ?? (projectedCumulativeCases ?? 0)
    }
    
    var anyR0: Double {
        return estimatedR0 ?? (projectedR0 ?? 0)
    }
}

struct Covid19Model {
    
    typealias ProjectionTarget = (newCases: Int, days: Int)
    typealias InputCsvInfo = (fileName: String, dateFormat: String)
    typealias SmoothingFactors = (fatalitySmoothing: Int, r0Smoothing: Int)

    private let unreportedFatalities: Double
    private let fatalityRate: Double
    private let incubationPeriod: Int
    private let fatalityPeriod: Int
    private let serialInterval: Int
    private let projectionTarget: ProjectionTarget
    private var data: [Date: CaseData] = [:]
    
    /**
     Creates a model for Covid-19 based on confimred fatalities and other variables.
     
     - Parameters:
        - unreportedFatalities: The percentage of fatalities that are not reported  (for example NY State currently reports only confirmed cases from hospitals and nursing homes. Fatalities that occur at home, or for people with symptoms that were not tested and diagnosed are not counted as confirmed cases).
        - fatalityRate: The percentage cases that will lead to fatality.
        - incubationPeriod: The mean number of days from becoming infected to onset of symptoms.
        - serialInterval: The number of days between successive cases in a chain of transmission.
        - projectionTarget: Targets used to determine how far ahead to project estimates.
        - inputCSVInfo: information about the csv file that contains infomration on confirmed fatalities.
        - smoothing: information about moving average periods to apply to smooth estimates
        
     When projecting forward into the future, this value is used to determine how far in advance to project. for example setting this value to `(newCases: 0, days: 90)` will attempt to project forward to the day where the number of new cases is zero, or 90 days - which ever occurs first.
     Note: If recent average for R0 is not less than 1, then the target for new cases will never be met because new cases will continue to increase.
     
     The Playground resources folder should contain a csv file with two columns
     - First column: date of confirmed fatalties
     - Second column: number of confirmed fatalities
     */
    init(unreportedFatalities: Double = 50.0,
         serialInterval: Int = 4,
         incubationPeriod: Int = 4,
         fatalityPeriod: Int = 13,
         fatalityRate: Double = 1.4,
         projectionTarget: ProjectionTarget = (newCases: 0, days: 90),
         inputCSVInfo: InputCsvInfo = (fileName: "data", dateFormat: "MM/dd/yyyy"),
         smoothing: SmoothingFactors = (fatalitySmoothing: 7, r0Smoothing: 7)) {
        
        assert((0.0...100).contains(unreportedFatalities), "Percentage of unreported fatalities must be between 0 and 100%")
        assert((1...30).contains(incubationPeriod), "Incubation period must be beween 1 and 30 days")
        assert((1...30).contains(fatalityPeriod), "Fatality period must be beween 1 and 30 days")
        assert((0.1...10).contains(fatalityRate), "Fatality rate must be beween 0.1 and 10")
        assert(projectionTarget.newCases >= 0, "target for new cases must be 0 or above")
        assert((1...7).contains(smoothing.fatalitySmoothing), "Fatality smoothing must be between 1 and 7")
        assert((1...7).contains(smoothing.r0Smoothing), "R0 smoothing must be between 1 and 7")
        
        self.serialInterval = serialInterval
        self.incubationPeriod = incubationPeriod
        self.fatalityRate = fatalityRate
        self.fatalityPeriod = fatalityPeriod
        self.unreportedFatalities = unreportedFatalities
        self.projectionTarget = projectionTarget
        
        let daysRatio: TimeInterval = 24*60*60
        let fileURL = Bundle.main.url(forResource: inputCSVInfo.fileName, withExtension: "csv")!
        let content = try! String(contentsOf: fileURL, encoding: String.Encoding.utf8)

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX") // set locale to reliable US_POSIX
        dateFormatter.dateFormat = inputCSVInfo.dateFormat // expected date format in CSV file
        
        print("...Loading data on confirmed fatalities from \(inputCSVInfo.fileName).csv")
        
        let parsedCSV: [(Date, Double)] = content.components(separatedBy: "\n")
            .compactMap({ line in
                let components = line.components(separatedBy: ",")
                if let date = dateFormatter.date(from: components[0]),
                    let confirmedFatalities = Int(components[1].trimmingCharacters(in: .whitespacesAndNewlines)) {
                    let unreportedFatalities = Double(confirmedFatalities) * (Double(unreportedFatalities)/100.0)
                    let totalFatalities = Double(confirmedFatalities) + unreportedFatalities
                    
                    return (date, totalFatalities)
                }
                return nil
            }).sorted(by: { left, right in left.0 < right.0 })
        
        print("...Smoothing fatality data with moving average of \(smoothing.fatalitySmoothing) days")
        let fatalityDates = parsedCSV.map({ return $0.0})
        let fatalityCounts = parsedCSV.map({ return $0.1})
        
        let fatalitiesMovingAverages = fatalityCounts.indices.map({ index -> Double in
            let possibleMinOffset = index-(smoothing.fatalitySmoothing-1)
            let minRange = possibleMinOffset < 0 ? 0 : possibleMinOffset
            let range = (minRange...index)
            let slice = fatalityCounts[range]
            let average = Double(slice.reduce(0, +)) / Double(range.count)
            return average
        })

        let datesFatalitiesMovingAverage = zip(fatalityDates, fatalitiesMovingAverages)
        
        print("...Calculating the estimated number of cases based on confirmed fatalities, incubation period, fatality period, and fatality rate")
        
        let estimatedCumulativeCases: [Date : Int] = Dictionary(uniqueKeysWithValues: datesFatalitiesMovingAverage.map({ tuple in
            let date = tuple.0.advanced(by: daysRatio * TimeInterval(-(incubationPeriod + fatalityPeriod)))
            let estimatedCases = tuple.1 * (100.0 / fatalityRate)
            
            return (date, Int(estimatedCases))
        }))
        
        print("...Calculating the number of new cases for each date")
        
        let estimatedCumulativeAndNewCases: [Date : (cumulative: Int, new: Int)] = Dictionary(uniqueKeysWithValues: estimatedCumulativeCases.compactMap({
            
            let dateToday = $0.key
            let cumulativeCasesToday = $0.value
            let dateYesterday = dateToday.advanced(by: daysRatio * TimeInterval(-1))
            
            if let cumulativeCasesYesterday = estimatedCumulativeCases[dateYesterday] {
                let newCasesToday = cumulativeCasesToday - cumulativeCasesYesterday
                return (dateToday, (cumulative: cumulativeCasesToday, new: newCasesToday))
            }
            return nil
        }))
        
        print("...Calculating R0 for each date based on new cases for date, and new cases on future date based on serial interval")
        var caseData: [Date: CaseData] = Dictionary(uniqueKeysWithValues: estimatedCumulativeAndNewCases.map({
            
            let dateToday = $0.key
            let cumulativeCasesToday = $0.value.cumulative
            let newCasesToday = $0.value.new
            let futureTransmissionDate = dateToday.advanced(by: daysRatio * TimeInterval(serialInterval))
            let casesOnFutureTransmissionDate = estimatedCumulativeAndNewCases[futureTransmissionDate]
            
            // if there are no new cases today, set R0 to nil rather than infinity
            let currnetR0 = casesOnFutureTransmissionDate != nil && newCasesToday != 0 ?
            Double(casesOnFutureTransmissionDate!.new) / Double(newCasesToday) : nil
            
            let caseData = CaseData(
                estimatedCumulativeCases: cumulativeCasesToday,
                estimatedNewCases: newCasesToday,
                estimatedR0: currnetR0,
                projectedCumulativeCases: nil,
                projectedNewCases: nil,
                projectedR0: nil
            )
            
            return (dateToday, caseData)
        }))
        
        print("...End of estimations")
        
        print("...Sorting data by date")
        let sortedCases = caseData.sorted(by: { left, right in
            return left.key < right.key
        })
        
        print("...Getting key R0 values")
        
        if let firstR0BelowOne = sortedCases.first(where: { item in
            item.value.estimatedR0 != nil && item.value.estimatedR0! < 1
        }) {
            print(" - Good news! estimated R0 dropped below 1.0 on \(firstR0BelowOne.key). R0 = \(firstR0BelowOne.value.estimatedR0!) \n")
        } else {
            print(" - Estimated R0 has not yet dropped below 1.0 \n")
        }
        
        print("...Getting lowest estimate for R0 based on estimated cases")
        guard let minR0 = caseData.filter({ item in
            return item.value.estimatedR0 != nil
        }).min(by: { left, right -> Bool in
            return left.value.estimatedR0! < right.value.estimatedR0!
        })
        else {
            fatalError("No R0 data")
        }
        
        print(" - Lowest R0 value on \(minR0.key). R0 = \(minR0.value.estimatedR0!) \n")
        
        print("...Getting average from recent R0 estimates")
        
        let latestR0EstimateCases = sortedCases.filter({ item in
            item.value.estimatedR0 != nil
        }).suffix(smoothing.r0Smoothing)
        
        let averageR0 = latestR0EstimateCases.compactMap({ $0.value.estimatedR0 }).reduce(0.0, +) / Double(smoothing.r0Smoothing)
        print(" - Average R0 from \(latestR0EstimateCases.last!.key) with \(smoothing.r0Smoothing) day moving average is \(averageR0) \n")
        
        print("...Getting most recent date with estimated cases")
        guard let firstDateWithEstimatedCases = sortedCases.first, let lastDateWithEstimatedCases = sortedCases.last else {
            fatalError("No dates in data")
        }
        
        print(" - Last date with estimated cases is \(lastDateWithEstimatedCases.key). Cumulative cases = \(lastDateWithEstimatedCases.value.estimatedCumulativeCases!).")
        print(" - Will now switch to projecting future cases based on most recent R0 value until estimated number of new cases per day drops below \(projectionTarget.newCases) \n")
        
        print("...Projecting future cases based on most recent R0")
        if averageR0 >= 1 {
            print("**Warning** current R0 is not below 1, projecting forward 90 days instead of using target of \(projectionTarget.newCases) new cases\n")
        }
        
        var numberOfDaysProjected = 0
        var lastDate = lastDateWithEstimatedCases.key
        
        repeat {
            
            let dateToday = lastDate.advanced(by: daysRatio)
            let caseDataYesterday = caseData[lastDate]!
            
            // the estimated new cases fluctuate a lot based on day-to-day fluctuations in confirmed deaths
            // each day which is probabl due to bias in daily reporting (e.g. reporting at different times
            // of the day). Instead use an average from 7 days prior to serial interval date
            let serialIntervalDatesSumNewCases: Int = (0..<7).compactMap({ offset -> Int? in
                let date = dateToday.advanced(by: daysRatio * TimeInterval((serialInterval + offset) * -1))
                return caseData[date]?.anyNewCases
                }).reduce(0, +)
            
            let newCasesToday = Int((Double(serialIntervalDatesSumNewCases) / 7) * averageR0)
            let cumulativeCasesToday = newCasesToday + caseDataYesterday.anyCumulativeCases
            
            let caseDataToday = CaseData(
                estimatedCumulativeCases: nil,
                estimatedNewCases: nil,
                estimatedR0: nil,
                projectedCumulativeCases: cumulativeCasesToday,
                projectedNewCases: newCasesToday,
                projectedR0: averageR0
            )
            
            caseData[dateToday] = caseDataToday
            lastDate = dateToday
            numberOfDaysProjected = numberOfDaysProjected + 1
        }
        while numberOfDaysProjected < projectionTarget.days && caseData[lastDate]?.projectedNewCases ?? 0 > projectionTarget.newCases
        
        let targetDateCaseData = caseData[lastDate]!
        print(" - Estimate that new cases will drop to \(targetDateCaseData.projectedNewCases!) per day on \(lastDate)")
        print(" - As of this date, estimate that cumulative cases will have reached \(targetDateCaseData.projectedCumulativeCases!) \n")
        
        print("...Getting estimates for today")
        let daysBetweenEarliestDateAndToday = (firstDateWithEstimatedCases.key.distance(to: Date())/daysRatio).rounded(.down) * daysRatio
        let dateToday = firstDateWithEstimatedCases.key.addingTimeInterval(daysBetweenEarliestDateAndToday)
        
        guard let casesToday = caseData[dateToday] else {
            fatalError("no data available for today - check if target for projections occurred on earlier date")
        }
        
        print(" - as of today \(dateToday)")
        print(" - cumulative cases \(casesToday.anyCumulativeCases)")
        print(" - new cases \(casesToday.anyNewCases)")
        print(" - r0 \(casesToday.anyR0)\n")
        
        print("...End of projections")
        self.data = caseData
        
        print("...Saving case data to output.csv in your documents folder")
        
        let fileName = "output"
        let dir = try? FileManager.default.url(for: .documentDirectory,
              in: .userDomainMask, appropriateFor: nil, create: true)
        
        // If the directory was found, we write a file to it and read it back
        if let fileURL = dir?.appendingPathComponent(fileName).appendingPathExtension("csv") {
            
            let outString = caseData.reduce("Date, Estimated Cumulative Cases, Estimated New Cases, Estimated R0, Projected Cumulative Cases, Projected New Cases\n") { text, item in
                let components =  [
                    item.key.description,
                    item.value.estimatedCumulativeCases?.description ?? "",
                    item.value.estimatedNewCases?.description ?? "",
                    item.value.estimatedR0?.description ?? "",
                    item.value.projectedCumulativeCases?.description ?? "",
                    item.value.projectedNewCases?.description ?? ""
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
    
    var estimatedCumulativeCasesData: [(Date, Double)] {
        return data.compactMap({ item in
            if let cumulativeCases = item.value.estimatedCumulativeCases {
                return (item.key, Double(cumulativeCases))
            }
            return nil
        })
    }
    
    var estimatedR0Data: [(Date, Double)] {
        return data.compactMap({ item in
            if let r0 = item.value.estimatedR0 {
                return (item.key, r0)
            }
            return nil
        })
    }
    
    var estimatedNewCasesData: [(Date, Double)] {
        return data.compactMap({ item in
            if let newCases = item.value.estimatedNewCases {
                return (item.key, Double(newCases))
            }
            return nil
        })
    }
    
    var projectedCumulativeCasesData: [(Date, Double)] {
        return data.compactMap({ item in
            if let cumulativeCases = item.value.projectedCumulativeCases {
                return (item.key, Double(cumulativeCases))
            }
            return nil
        })
    }
    
    var projectedNewCasesData: [(Date, Double)] {
        return data.compactMap({ item in
            if let newCases = item.value.projectedNewCases {
                return (item.key, Double(newCases))
            }
            return nil
        })
    }
    
    var caseData: [Date: CaseData] {
        return self.data
    }
}


///Create a model with estimates on variables for Covid-19
let model = Covid19Model(
                unreportedFatalities: 50,
                serialInterval: 5,
                incubationPeriod: 4,
                fatalityPeriod: 13,
                fatalityRate: 1.4,
                projectionTarget: (newCases: 0, days: 30),
                inputCSVInfo: (fileName: "data", dateFormat: "MM/dd/yyyy"),
                smoothing: (fatalitySmoothing: 7, r0Smoothing: 3)
            )

struct Charts: View {
    var body: some View {
        VStack {
            Chart(data: model.estimatedR0Data, title: "Estimated R0", forceMaxValue: 1.0)
                .frame(width: 600, height: 300)
                .background(Color.blue)

            Chart(data: model.estimatedCumulativeCasesData, title: "Estimated Cumulative Cases")
                .frame(width: 600, height: 300)
                .background(Color.yellow)

            Chart(data: model.projectedCumulativeCasesData, title: "Projected Cumulative Cases")
                .frame(width: 600, height: 300)
                .background(Color.yellow)

            Chart(data: model.estimatedNewCasesData, title: "Estimated New Cases")
                .frame(width: 600, height: 300)
                .background(Color.green)

            Chart(data: model.projectedNewCasesData, title: "Projected New Cases")
                .frame(width: 600, height: 300)
                .background(Color.green)
        }
    }
}

PlaygroundPage.current.setLiveView(Charts())
