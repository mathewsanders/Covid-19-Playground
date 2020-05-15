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
    unreportedFatalities: 50,
    serialInterval: 4,
    incubationPeriod: 4,
    fatalityPeriod: 13,
    fatalityRate: 1.4,
    projectionTarget: 90,
    inputCSVInfo: (fileName: "data", dateFormat: "MM/dd/yy"),
    smoothing: (inputSmoothing: 7, inputDrop: 5, r0Smoothing: 2)
)
````  
The model exposes a number of properties that returns a dictionary with Date keys and value that contains estimated and projected values for each day.  

````Swift
model.r0 // [Date: Double?] estimated R0 for each day
model.newCases: // [Date: Double] estimated new cases for each day
model.cumulativeCases: // [Date: Double] estimated cumulative cases as of each day
model.fatalities: // [Date: Double] estimated new fatalties for each day
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
Mean number of days from infection to onset of symptoms 4 days. 
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

### Smoothing 
By default the following smoothing factors are applied: `(inputSmoothing: 7, inputDrop: 5, r0Smoothing: 2)`
* Input smoothing applies a moving average smoothing on the input values. There seems to be weekly spikes (weekdays vs weekends) in the number of deaths that are reported. Smoothing to 7 averages out values over the last 7 days.
* Input drop indicates the number of days of records to drop. NYC department of heath a consistantly updating historic data, and at the moment, the most recent 5 days of values tend to be under reported and so leads to very optimistic R0 estimates.
* R0 smoothing determines how many days of recent R0 estimates should be used when projecting values forward.

## Example debug output 

Running the model prints progress, errors, and interesting values in the debug output.

````
// default output displays latest R0 estimates 
Average R0 from 2 days ending 04/18/20
-  0.73

// calling model.printSummary() prints estimates for today
Estimated values for today 05/15/20
 - fatalities: 95
 - new cases: 1821
 - cumulative cases: 1506202
 
````

## Charting
A very bare-bones `ChartView.swift` is included in the sources folder to display estimated and projected values.

````Swift
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
````

## CSV output

Calling the `saveOutput()` function on the model generates an `output.csv` file in your Documents folder. This contains the results of the model if needed for further post-processing. 

![Preview of csv file generated from covid-19 playground](output.csv-preview.png)
