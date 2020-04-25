//import Foundation
import SwiftUI

struct ChartPath: ChartLayout, View {
    
    var maxDateIndex: Int
    var values: [Double?]
    var maxValue: Double
    
    public var body: some View {
        
        GeometryReader { geometry in
            Path { path in
                let firstValue = self.values.first! ?? 0
                let p1 = CGPoint(
                    x: self.getXPos(forDate: 0, withWidth: geometry.size.width),
                    y: self.getYPos(forValue: firstValue, withHeight: geometry.size.height))
                
                path.move(to: p1)
                
                for (index, value) in self.values.enumerated() {
                    if let value = value {
                        let p2 = CGPoint(
                            x: self.getXPos(forDate: index, withWidth: geometry.size.width),
                            y: self.getYPos(forValue: value, withHeight: geometry.size.height))
                        path.addLine(to: p2)
                    }
                    else {
                        let p2 = CGPoint(
                            x: self.getXPos(forDate: index, withWidth: geometry.size.width),
                            y: path.currentPoint?.y ?? 0)
                        path.move(to: p2)
                    }
                }
            }
            .stroke(Color.black ,style: StrokeStyle(lineWidth: 1, lineJoin: .bevel))
        }
    }
}

protocol ChartLayout {
    var maxValue: Double { get }
    var maxDateIndex: Int { get }
}

extension ChartLayout {
    func getYPos(forValue value: Double, withHeight height: CGFloat) -> CGFloat {
        let offset: CGFloat = 30
        let tempHeight = height - offset
        return (tempHeight - CGFloat(value/self.maxValue) * tempHeight)
    }
    
    func getXPos(forDate dateIndex: Int, withWidth width: CGFloat) -> CGFloat {
        let offset: CGFloat = 80
        let tempWidth = width - offset
        return (CGFloat(dateIndex)/CGFloat(self.maxDateIndex) * tempWidth) + offset
    }
}

extension Double {
    func string(maximumFractionDigits: Int = 2) -> String {
        let s = String(format: "%.\(maximumFractionDigits)f", self)
        for i in stride(from: 0, to: -maximumFractionDigits, by: -1) {
            if s[s.index(s.endIndex, offsetBy: i - 1)] != "0" {
                return String(s[..<s.index(s.endIndex, offsetBy: i)])
            }
        }
        return String(s[..<s.index(s.endIndex, offsetBy: -maximumFractionDigits - 1)])
    }
}

struct ChartValueAxis: ChartLayout, View {
    
    var valueGuides: [Double]
    var maxDateIndex: Int = 0
    
    var maxValue: Double {
        return valueGuides.max() ?? 0
    }
    
    func shortValueLabel(for valueGuide: Double) -> String {
        return valueGuide.string(maximumFractionDigits: 2)
    }
    
    public var body: some View {
        GeometryReader{ geometry in
            
            ForEach(self.valueGuides, id: \.self) { valueGuide in
                Group {
                    Path { path in
                        let yPos = self.getYPos(forValue: valueGuide, withHeight: geometry.size.height)
                        let startPoint = CGPoint(x: 60, y: yPos)
                        let endPoint = CGPoint(x: geometry.size.width, y: yPos)
                        path.move(to: startPoint)
                        path.addLine(to: endPoint)
                        
                    }
                    .stroke(Color.white ,style: StrokeStyle(lineWidth: 1, lineJoin: .round))
                    .opacity(0.45)
                    Text(self.shortValueLabel(for: valueGuide))
                        .font(.footnote)
                        .foregroundColor(Color.black)
                        .frame(width: 80, height: 20, alignment: .trailing)
                        .offset(x: -30, y: self.getYPos(forValue: valueGuide, withHeight: geometry.size.height)-10)
                }
            }
        }
    }
}

public extension Collection {

    /// Returns the element at the specified index if it is within bounds, otherwise nil.
    subscript (safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

struct ChartTimeAxis: ChartLayout, View {

    var dates: [Date]
    var dateGuides: [Int]
    
    var maxDateIndex: Int {
        return dates.count
    }
    
    var maxValue: Double = 0
    
    var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/dd"
        return formatter
    }()
    
    func shortDateLabel(for dateIndex: Int) -> String {
        
        if let date = self.dates[safe: dateIndex] {
            return self.dateFormatter.string(from: date)
        }
        return ""
    }
    
    public var body: some View {
        GeometryReader{ geometry in
            
            ForEach(self.dateGuides, id: \.self) { dateIndex in
                Group {
                    Path { path in
                        let xPos = self.getXPos(forDate: dateIndex, withWidth: geometry.size.width)
                        let startPoint = CGPoint(x: xPos, y: geometry.size.height)
                        let endPoint = CGPoint(x: xPos, y: 0)
                        path.move(to: startPoint)
                        path.addLine(to: endPoint)
                    }
                    .stroke(Color.white ,style: StrokeStyle(lineWidth: 1, lineJoin: .round))
                    .opacity(0.45)
                    Text("\(self.shortDateLabel(for: dateIndex))")
                        .font(.system(size: 10))
                        .foregroundColor(Color.black)
                        .frame(width: 25, height: 20)
                        .rotationEffect(.degrees(-50))
                        .offset(x: self.getXPos(forDate: dateIndex, withWidth: geometry.size.width)-25, y: geometry.size.height-20)
                }
            }
        }
    }
}

public struct Chart: View {
    
    private let title: String
    private let dates: [Date]
    private let values: [Double]
    
    private let valueGuides: [Double]
    private let dateGuides: [Int]
    private let chartHeight: Double
    
    public init(data: [(Date, Double)], title: String, forceMaxValue: Double? = nil) {
        self.title = title
        
        let sortedData = data.sorted { (left, right) -> Bool in
            left.0 < right.0
        }
        let sortedDates = sortedData.map({ $0.0 })
        let sortedValues = sortedData.map({ $0.1 })
        
        self.dates = sortedDates
        self.values = sortedValues
        
        //let minValue = self.values.min() ?? 0
        let minValue: Double = 0
        let maxValue = forceMaxValue ?? (sortedValues.max() ?? 0)
        let valueRange = maxValue - minValue
        let dateRange = sortedData.count
        
        // find the smallest stride that has around 4 strides between min and max values
        let valueStride = [0.01, 0.05, 0.1, 0.25, 0.5, 1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000, 50000, 100000, 200000, 500000, 1000000].first(where: { testStride in
            return valueRange / testStride < 12
        }) ?? 1.0
        
        let dateStride: Int = [1, 2, 7, 14, 21].first(where: { testStride in
            return dateRange / testStride < 32
        }) ?? 1
                
        self.chartHeight = valueStride * (maxValue / valueStride).rounded(.up)
        let verticalSteps = Int(chartHeight/valueStride)
        let horizontalSteps = Int(Double(dateRange/dateStride).rounded(.up))
        
        self.valueGuides = (0...verticalSteps).map({ Double($0) * valueStride })
        self.dateGuides = (0...horizontalSteps).map({ $0 * dateStride })
    }
    
    public var body: some View {
        GeometryReader{ geometry in
            VStack (alignment: .leading, spacing: 20) {
                Text(self.title)
                    .font(.headline)
                    .foregroundColor(Color.black)
                ZStack {
                    ChartTimeAxis(dates: self.dates, dateGuides: self.dateGuides)
                    ChartValueAxis(valueGuides: self.valueGuides)
                    ChartPath(maxDateIndex: self.dates.count, values: self.values, maxValue: self.chartHeight)
                }
            }
        }
        .padding(EdgeInsets(top: 15, leading: 30, bottom: 10, trailing: 30))
    }
}
