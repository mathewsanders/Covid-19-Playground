import SwiftUI
import PlaygroundSupport

struct InfectionData: Hashable {
    /// Cumulitive number of people infected estimated by observed deaths and death rate
    let estimatedCumulativeInfected: Int?
    
    /// New people infected estimated by observed deaths and death rate
    let estimatedNewInfected: Int?
    
    /// R0 estimated by observed deaths
    let estimatedR0: Double?
    
    /// Cumulitive number of people infected projected by most recent R0 value
    let projectedCumulativeInfected: Int?
    
    /// New people infected estimated by projected by most recent R0 value
    let projectedNewInfected: Int?
    
    /// R0 estimated by most recent estimated R0
    let projectedR0: Double?
    
    var anyNewInfected: Int {
        return estimatedNewInfected ?? (projectedNewInfected ?? 0)
    }
    
    var anyCumulativeInfected: Int {
        return estimatedCumulativeInfected ?? (projectedCumulativeInfected ?? 0)
    }
    
    var anyR0: Double {
        return estimatedR0 ?? (projectedR0 ?? 0)
    }
}

struct Covid19Model {
    /// The percentage of deaths that are not reported
    private let unreportedDeathsPercent: Double
    
    /// The percentage of people who will die once infected with COVID-19
    private let mortalityRatePercent: Double
    
    /// The mean number of days from becoming infected to dying (for people who die)
    private let incubationToDeathDays: Int
    
    /// The number of days between successive cases in a chain of transmission.
    private let serialIntervalDays: Int
    
    /// When projecting forward into the future, this number is used to determine how far in advance to project.
    /// for example:
    /// - setting this value to 100 will look for the earliest future date where the number of new infections is less than 100
    /// - setting this value to 0 will look for the earlist future date where there are no new infections
    private let targetNewInfections: Int
    
    /// number of seconds in a day
    private let daysRatio: TimeInterval = 24*60*60
    
    private var data: [Date: InfectionData] = [:]
    
    init(unreportedDeathsPercent: Double = 50.0, mortalityRatePercent: Double = 1.00, incubationToDeathDays: Int = 17, serialIntervalDays: Int = 4, targetNewInfections: Int = 0, csvName: String = "data" , csvDateFormat: String = "MM/dd/yyyy") {
        
        self.unreportedDeathsPercent = unreportedDeathsPercent
        self.mortalityRatePercent = mortalityRatePercent
        self.incubationToDeathDays = incubationToDeathDays
        self.serialIntervalDays = serialIntervalDays
        self.targetNewInfections = targetNewInfections
        
        /// Resources folder should contain a csv file with two columns
        /// First column: Date in MM/dd/yyyy format
        /// Second column: number of deaths recorded on that date
        let fileURL = Bundle.main.url(forResource: csvName, withExtension: "csv")!
        let content = try! String(contentsOf: fileURL, encoding: String.Encoding.utf8)

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX") // set locale to reliable US_POSIX
        dateFormatter.dateFormat = csvDateFormat // expected date format in CSV file
        
        print("...Loading data from csv")
        
        let parsedCSV: [Date : Int] = Dictionary(uniqueKeysWithValues: content
          .components(separatedBy: "\n")
            .compactMap({ line in
                let components = line.components(separatedBy: ",")
                if let date = dateFormatter.date(from: components[0]),
                    let deaths = Int(components[1].trimmingCharacters(in: .whitespacesAndNewlines)) {
                    let unreportedDeaths = Double(deaths) * (Double(unreportedDeathsPercent)/100.0)
                    let totalDeaths = deaths + Int(unreportedDeaths)
                    
                    return (date, totalDeaths)
                }
                return nil
            }))

        print("...Calculating the estimated number of people infected based on observed deaths, incubation period, and mortality rate")
        let estimatedInfected: [Date : Int] = Dictionary(uniqueKeysWithValues: parsedCSV.map({
            let date = $0.key.advanced(by: daysRatio * TimeInterval(-incubationToDeathDays))
            let estimatedInfected = Double($0.value) * (100.0 / Double(mortalityRatePercent))
            return (date, Int(estimatedInfected))
        }))
        
        print("...Calculating the R0 and number of new infections for each date based on serial interval")
        var infectionData: [Date: InfectionData] = Dictionary(uniqueKeysWithValues: estimatedInfected.compactMap({
            let currentDate = $0.key
            let currentInfected = $0.value
            
            let futureDate = currentDate.advanced(by: daysRatio * TimeInterval(serialIntervalDays))
            
            let yesterday = currentDate.advanced(by: daysRatio * TimeInterval(-1))
            let yesterdayInfected = estimatedInfected[yesterday]
            
            let deltaInfected = yesterdayInfected != nil ? currentInfected - yesterdayInfected! : 0
            
            if let infectedOnFutureDate = estimatedInfected[futureDate] {
                let newInfected = infectedOnFutureDate - currentInfected
                let currnetR0 = Double(newInfected)/Double(currentInfected)
                return (currentDate, InfectionData(
                    estimatedCumulativeInfected: currentInfected,
                    estimatedNewInfected: deltaInfected,
                    estimatedR0: currnetR0,
                    projectedCumulativeInfected: nil,
                    projectedNewInfected: nil,
                    projectedR0: nil
                ))
            }
            else {
                return (currentDate, InfectionData(
                    estimatedCumulativeInfected: currentInfected,
                    estimatedNewInfected: deltaInfected,
                    estimatedR0: nil,
                    projectedCumulativeInfected: nil,
                    projectedNewInfected: nil,
                    projectedR0: nil
                ))
            }
        }))
             
        print("...Sorting data by date")
        let sortedData =  infectionData.sorted(by: { left, right in
            return left.key < right.key
        })
        
        print("...Getting key R0 values")
        
        if let firstR0BelowOne = sortedData.first(where: { item in
            item.value.estimatedR0 != nil && item.value.estimatedR0! < 1
        }) {
            print(" - Good news! estimated R0 dropped below 1.0 on \(firstR0BelowOne.key). R0 = \(firstR0BelowOne.value.estimatedR0!) \n")
        } else {
            print(" - Estimated R0 has not yet dropped below one \n")
        }
        
        print("...Getting lowest estimate for R0 based on estimated infections")
        guard let minR0 = infectionData.filter({ item in
            return item.value.estimatedR0 != nil
        }).min(by: { left, right -> Bool in
            return left.value.estimatedR0! < right.value.estimatedR0!
        })
        else {
            fatalError("No R0 data")
        }
        
        //guard let minR0 = infectionData.compactMap({ $0.value.estimatedR0 }).min()
        print(" - lowest R0 value on \(minR0.key). R0 = \(minR0.value.estimatedR0!) \n")
        
        print("...Getting most recent estimate for R0 based on estimated infections")
        guard let lastR0 = sortedData.last(where: { item in
            item.value.estimatedR0 != nil
        }) else {
            fatalError("Not enough datapoints to calculate last value for estimated R0")
        }
        print(" - Most recent date with estimated R0 is: \(lastR0.key). R0 = \(lastR0.value.estimatedR0!)\n")
        if minR0.value.estimatedR0! < lastR0.value.estimatedR0! {
            print("** Warning: lastest value is increase from min R0 **\n")
        }
        print("** Note: projections use fixed R0 of \(lastR0.value.estimatedR0!) **\n")
        
        print("...Getting most recent date with estimated infections")
        guard let lastDateInfectionData = sortedData.last else {
            fatalError("No dates in data")
        }
        
        print(" - Last date with estimated infections is \(lastDateInfectionData.key). Cumulative infections = \(lastDateInfectionData.value.estimatedCumulativeInfected!).")
        print(" - Will now switch to projecting future infections based on most recent R0 value until estimated number of new infections per day drops below \(self.targetNewInfections) \n")
        
        print("...Projecting future infections based on most recent R0")
        var lastDate = lastDateInfectionData.key
        repeat {
            let tomorrow = lastDate.advanced(by: daysRatio)
            let todayInfectionData = infectionData[lastDate]!
            let previousDate = tomorrow.advanced(by: daysRatio * TimeInterval(serialIntervalDays * -1))
            let previousInfectionData = infectionData[previousDate]!
            let tomorrowNewInfected = Int(Double(previousInfectionData.anyNewInfected) * lastR0.value.estimatedR0!)
            let tomorrowInfected = tomorrowNewInfected + todayInfectionData.anyCumulativeInfected
            
            infectionData[tomorrow] = InfectionData(
                estimatedCumulativeInfected: nil,
                estimatedNewInfected: nil,
                estimatedR0: nil,
                projectedCumulativeInfected: tomorrowInfected,
                projectedNewInfected: tomorrowNewInfected,
                projectedR0: lastR0.value.estimatedR0!
            )
            lastDate = tomorrow
        }
        while infectionData[lastDate]?.projectedNewInfected ?? 0 > targetNewInfections
        
        let targetDateInfectionData = infectionData[lastDate]!
        print(" - Estimate that new infections will drop to \(targetDateInfectionData.projectedNewInfected!) on \(lastDate)")
        print(" - As of this date, estimate that cumulitive infections will have reached \(targetDateInfectionData.projectedCumulativeInfected!) \n")
        
        print("...Getting estimates for today")
        
        guard let earliestDate = sortedData.first?.key else {
            fatalError("no date data")
        }
        
        let daysBetweenEarliestDateAndToday = (earliestDate.distance(to: Date())/daysRatio).rounded(.down) * daysRatio
        let todayDate = earliestDate.addingTimeInterval(daysBetweenEarliestDateAndToday)
        print(todayDate)
        guard let dataToday = infectionData[todayDate] else {
            fatalError("no data availble for today - check if target for projections occured on earlier date")
        }
        
        print(" - as of today \(todayDate)")
        print(" - cumulative infected \(dataToday.anyCumulativeInfected)")
        print(" - new infected \(dataToday.anyNewInfected)")
        print(" - r0 \(dataToday.anyR0)\n")
        
        print("...end of calculations")
        self.data = infectionData
    }
        
    var estimatedCumulitiveinfectionData: [(Date, Double)] {
        return data.compactMap({ item in
            if let estimatedCumulitiveInfected = item.value.estimatedCumulativeInfected {
                return (item.key, Double(estimatedCumulitiveInfected))
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
    
    var estimatedNewInfectedData: [(Date, Double)] {
        return data.compactMap({ item in
            if let newInfected = item.value.estimatedNewInfected {
                return (item.key, Double(newInfected))
            }
            return nil
        })
    }
    
    var projectedCumulitiveinfectionData: [(Date, Double)] {
        return data.compactMap({ item in
            if let cumulitiveInfected = item.value.projectedCumulativeInfected {
                return (item.key, Double(cumulitiveInfected))
            }
            return nil
        })
    }
    
    var projectedNewInfectedData: [(Date, Double)] {
        return data.compactMap({ item in
            if let newInfected = item.value.projectedNewInfected {
                return (item.key, Double(newInfected))
            }
            return nil
        })
    }
}

/// Create a model with estimates on variables for Covid-19
///
/// Unreported Deaths: As of 4/24 NYC Department of Health are reporting 10,746 confirmed deaths and 5,012 probable deaths. Estmate that unreported deaths is around 50% (source: https://www1.nyc.gov/site/doh/covid/covid-19-data.page)
/// 
/// Mortality Rate: There is a much wider spread in estimates for mortality rates - although number of deaths can be reasonabily estimated, without widespread random testing it's hard to confirm how many cases lead to death.
/// Recent random testing of 3,000 in across NY State suggests that 20% of NYC (~1.68 million) have antibodies suggesting exposure to Covid-19. Combining with 15,758 estimated deaths leads to estimated mortality rate of 0.94% (note this is higer than Cuomo's NY State estimate of 0.5, but he is not including probable deaths. (source: https://www.governor.ny.gov/news/audio-rush-transcript-governor-cuomo-guest-msnbcs-testing-road-reopening-nicolle-wallace)
///
/// Incubation to death: Mean number of days from incubation to death combines both the mean incubation period (infection to symptoms) of 4-5 days (sournce: https://www.ncbi.nlm.nih.gov/pubmed/32150748) and mean number of days from onset of illness to death of 13 days (source: https://www.ncbi.nlm.nih.gov/pubmed/32079150)
///
/// Serial interval: Mean estimated as 4 days (source: https://www.ncbi.nlm.nih.gov/pubmed/32145466)

let model = Covid19Model(
                unreportedDeathsPercent: 50,
                mortalityRatePercent: 1.0,
                incubationToDeathDays: 17,
                serialIntervalDays: 5,
                targetNewInfections: 0
            )

struct Wrapper: View {
    var body: some View {
        VStack {
            Chart(data: model.estimatedR0Data, title: "Estimated R0", forceMaxValue: 1.0)
                .frame(width: 600, height: 300)
                .background(Color.blue)

            Chart(data: model.estimatedCumulitiveinfectionData, title: "Estimated Infections (Cumulative)")
                .frame(width: 600, height: 300)
                .background(Color.yellow)

            Chart(data: model.projectedCumulitiveinfectionData, title: "Projected Infections (Cumulative)")
                .frame(width: 600, height: 300)
                .background(Color.yellow)

            Chart(data: model.estimatedNewInfectedData, title: "Estimated New Infected Daily")
                .frame(width: 600, height: 300)
                .background(Color.green)

            Chart(data: model.projectedNewInfectedData, title: "Projected New Infected Daily")
                .frame(width: 600, height: 300)
                .background(Color.green)
        }
    }
}

PlaygroundPage.current.setLiveView(Wrapper())
