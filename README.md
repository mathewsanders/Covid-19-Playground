# Covid-19-Playground

This playground is a starting point for modeling Covid-19 cases based on available data on confirmed deaths due to Covid-19.

⚠️ **Warning** Current version is showing results that are very optimistic and I expect that results must be too good to be true and so are probably not accurate. Please use feel free to use this as a possible starting point for your own models.

![Preview of chart output of covid-19 playground](preview.png)

## Example usage
````Swift
let model = Covid19Model(
                unreportedDeathsPercent: 50,
                mortalityRatePercent: 1.0,
                incubationToDeathDays: 17,
                serialIntervalDays: 5,
                targetNewInfections: 0
            )
````  

This creates a collection that contains the following data structure for each date:

````Swift
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
}
````  

## Default values 
The following are used as default values if not provided
- **Unreported Deaths:** As of 4/24 NYC Department of Health are reporting 10,746 confirmed deaths and 5,012 probable deaths. Estmate that unreported deaths is around 50% (source: https://www1.nyc.gov/site/doh/covid/covid-19-data.page)
- **Mortality Rate:** There is a much wider spread in estimates for mortality rates - although number of deaths can be reasonabily estimated, without widespread random testing it's hard to confirm how many cases lead to death. Recent random testing of 3,000 in across NY State suggests that 20% of NYC (~1.68 million) have antibodies suggesting exposure to Covid-19. Combining with 15,758 estimated deaths leads to estimated mortality rate of 0.94% (note this is higer than Cuomo's NY State estimate of 0.5, but he is not including probable deaths. (source: https://www.governor.ny.gov/news/audio-rush-transcript-governor-cuomo-guest-msnbcs-testing-road-reopening-nicolle-wallace)
- **Incubation to death:** Mean number of days from incubation to death combines both the mean incubation period (infection to symptoms) of 4-5 days (sournce: https://www.ncbi.nlm.nih.gov/pubmed/32150748) and mean number of days from onset of illness to death of 13 days (source: https://www.ncbi.nlm.nih.gov/pubmed/32079150)
- **Serial interval:**  Mean estimated as 4 days (source: https://www.ncbi.nlm.nih.gov/pubmed/32145466)


## Example output 
Output is divided into two *estimated* and *projected* values.
Estimated data uses the data on confirmed deaths from the CSV file and variables set on the model to make estimates for R0, cumulative deaths, and new deaths for each day.
Estimates are limited from the most recent confirmed number of deaths, and estimated mean nunmber of days from incubation to death.
Projected values assume that the current R0 value is fixed, and uses this to project forward possible future values.

````
...Loading data from csv
...Calculating the estimated number of people infected based on observed deaths, incubation period, and mortality rate
...Calculating the R0 and number of new infections for each date based on serial interval
...Sorting data by date
...Getting key R0 values
 - Good news! estimated R0 dropped below 1.0 on 2020-03-15 04:00:00 +0000. R0 = 0.992721979621543 

...Getting lowest estimate for R0 based on estimated infections
 - lowest R0 value on 2020-04-01 04:00:00 +0000. R0 = 0.21803977272727273 

...Getting most recent estimate for R0 based on estimated infections
 - Most recent date with estimated R0 is: 2020-04-02 04:00:00 +0000. R0 = 0.21965799031476999

** Warning: lastest value is increase from min R0 **

** Note: projections use fixed R0 of 0.21965799031476999 **

...Getting most recent date with estimated infections
 - Last date with estimated infections is 2020-04-07 04:00:00 +0000. Cumulative infections = 1611900.
 - Will now switch to projecting future infections based on most recent R0 value until estimated number of new infections per day drops below 0 

...Projecting future infections based on most recent R0
 - Estimate that new infections will drop to 0 on 2020-05-08 04:00:00 +0000
 - As of this date, estimate that cumulitive infections will have reached 1693592 

...Getting estimates for today
2020-04-25 04:00:00 +0000
 - as of today 2020-04-25 04:00:00 +0000
 - cumulative infected 1693138
 - new infected 133
 - r0 0.21965799031476999

...end of calculations
````

## Charting
A very bare-bones ChartView is included that provides display of estimated and projected data 

````Swift
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
````

