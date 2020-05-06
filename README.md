# Covid-19-Playground

This playground is a starting point for modeling Covid-19 cases based on available data on confirmed fatalities due to Covid-19.

This model is limited in estimating values in the near past, but uses the most recent estimated values for R0 to estimate to the current date and beyond.  

Example:  
* If we have data on confirmed fatalities up to April 30, and we set the incubation period as 5 days, and fatality period as 5 days, then the model will provide estimates on the number of cases up to April 20.
* With a serial interval of 5 days, the model will provide estimates for R0 up to April 15.
* The model will use most recent R0 estimates from April 15 to project values for confimed cases for April 21 and beyond. 


![Preview of chart output of covid-19 playground](preview.png)

## Usage

The model expects a csv file in the playground resources folder with cumulative confirmed and probable deaths for each day.

The model can then be created with a range of paramaters to represent the model. These are all optional, and default values are used if custom values are not provided.

````Swift
let model = Covid19Model(
    unreportedDeaths: 50,
    serialInterval: 5,
    incubationPeriod: 4,
    fatalityPeriod: 13,
    fatalityRate: 1.4,
    projectionTarget: (newCases: 0, days: 90),
    inputCSVInfo: (fileName: "data", dateFormat: "MM/dd/yyyy"),
    smoothing: (fatalitySmoothing: 7, r0Smoothing: 3)
)
````  
The model exposes a `caseData` property that returns a dictionary with Date keys and value that contains estimated and projected values for each day.  

````Swift
let caseData: [Date: CaseData] = model.caseData
````  

The `CaseData` struct has following values:

````Swift
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
}
````  

## Default values 
The following are used as default values if not provided

### Unreported Fatalities
As of 4/24 NYC Department of Health are reporting 10,746 confirmed fatalities and 5,012 probable fatalities. Estmate that unreported fatalities is around 50%. This value is only used for days that the input csv does not contain a value for probable deaths.
Source: https://www1.nyc.gov/site/doh/covid/covid-19-data.page

### Serial interval
Mean estimated as 4 days. 
Source: https://www.ncbi.nlm.nih.gov/pubmed/32145466

### Incubation period 
Mean number of days from infection to onset of symptoms 4-5 days. 
Source: https://www.ncbi.nlm.nih.gov/pubmed/32150748

### Fatality period
Mean number of days from onset of symptoms to fatality of 13 days. 
Source: https://www.ncbi.nlm.nih.gov/pubmed/32079150

### Fatality rate  
There is a much wider spread in estimates for fatality rates - although number of fatalities can be reasonabily estimated, without widespread random testing of the general population it's hard to confirm how many cases lead to death. 

We currently have two studies to draw estimates from: supermarket testing, and first responder testing.

Supermarket testing was performed in the week starting 4/20 when confirmed and probable deaths was 13,683. In this test 20% of NYC supermaket shoppers tested positive for Covid-19 antibodies (source: https://www.governor.ny.gov/news/audio-rush-transcript-governor-cuomo-guest-msnbcs-testing-road-reopening-nicolle-wallace). If this represents wider population of NYC this suggests 1.68 million cases and fatality rate of 0.8%. This group of people is likely biased (for example people who are more strict in their self-isolation may not have been at the supermaket when people were asked to volunteer). Note that Cuomo reported a fatality rate of 0.5% from this study, but did not include probable deaths, and only counted confirmed fatalties from hospitals and nursing homes.

First-responder testing was performed in the week starting 4/27 when confirmed and probable deaths was 16,936. In this test 10-17% of first-responders tested positive for Covid-19 antibodies (source: https://twitter.com/NYGovCuomo/status/1255524216562221057). If this represents wider population of NYC this suggests 0.84 million cases and fatality rate of 2.0%. This group of people is also likely biased (for example first responders may have better access and more consistant use of PPE). 

Taking the average between the two, the default value that the model uses is a fatality rate of 1.4%.

## Example debug output 

Running the model prints progress, errors, and interesting values in the debug output.

````
...Loading data on confirmed fatalities from data.csv
...Smoothing fatality data with moving average of 7 days
...Calculating the estimated number of cases based on confirmed fatalities, incubation period, fatality period, and fatality rate
...Calculating the number of new cases for each date
...Calculating R0 for each date based on new cases for date, and new cases on future date based on serial interval
...End of estimations
...Sorting data by date
...Getting key R0 values
 - Good news! estimated R0 dropped below 1.0 on 2020-03-24 04:00:00 +0000. R0 = 0.8256786500366838 

...Getting lowest estimate for R0 based on estimated cases
 - Lowest R0 value on 2020-03-26 04:00:00 +0000. R0 = 0.6633618032931232 

...Getting average from recent R0 estimates
 - Average R0 from 2020-04-07 04:00:00 +0000 with 3 day moving average is 0.8662655171321689 

...Getting most recent date with estimated cases
 - Last date with estimated cases is 2020-04-12 04:00:00 +0000. Cumulative cases = 1213346.
 - Will now switch to projecting future cases based on most recent R0 value until estimated number of new cases per day drops below 0 

...Projecting future cases based on most recent R0
 - Estimate that new cases will drop to 21558 per day on 2020-05-12 04:00:00 +0000
 - As of this date, estimate that cumulative cases will have reached 2061675 

...Getting estimates for today
 - as of today 2020-04-29 04:00:00 +0000
 - cumulative cases 1749175
 - new cases 27114
 - r0 0.8662655171321689

...End of projections
...Saving case data to output.csv in your documents folder
````

## Charting
A very bare-bones `ChartView.swift` is included in the sources folder to display estimated and projected values.

````Swift
struct Charts: View {
    var body: some View {
        VStack {
            Chart(data: model.estimatedR0Data, title: "Estimated R0", forceMaxValue: 2.0)
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
````

## CSV output

Running the playground generates an `output.csv` file in your Documents folder. This contains the results of the model if needed for further post-processing. 

![Preview of csv file generated from covid-19 playground](output.csv-preview.png)
