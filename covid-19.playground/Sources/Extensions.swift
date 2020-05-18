import Foundation

public extension Collection {
    /// Returns the element at the specified index if it is within bounds, otherwise nil.
    subscript (safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

public extension Optional where Wrapped == Int {
    static func * (lhs: Optional<Int>, rhs: Int) -> Int? {
        if let lhsWrapper = lhs {
            return lhsWrapper * rhs
        }
        return nil
    }
}

public typealias DateTransformer = (Date) -> Date
public typealias ValueTransformer<T,U> = (T) -> U
public typealias DateValueTransformer<T,U> = (Date,T,Date,T?) -> (Date,U)?
public typealias TemporalMap<T,U> = (Date, T) -> (Date, U)?
public typealias ValueMerger<T,U,V> = (T?, U?) -> V

public extension Dictionary where Key == Date {
    func temporalMap<U>(dateTransformer: DateTransformer, valueTransformer: ValueTransformer<Value,U>) -> [Date: U] {
        return Dictionary<Date,U>(uniqueKeysWithValues:
            self.map{ date, value in
                return (dateTransformer(date), valueTransformer(value))
            }
        )
    }
    
    func temporalMap<U>(mapper: TemporalMap<Value,U>) -> [Date: U] {
        return Dictionary<Date,U>(uniqueKeysWithValues:
            self.compactMap{ date, value in
                return mapper(date, value)
            }
        )
    }
    
    func temporalMap<U>(dateOffset: Int, transformer: DateValueTransformer<Value,U>) -> [Date: U] {
        let keyValues: [(Date, U)] = self.compactMap{ date, value in
            let offsetDate = date.advanced(by: TimeInterval(86_400 * dateOffset))
            let offsetValue = self[offsetDate]
            return transformer(date, value, offsetDate, offsetValue)
        }
        return Dictionary<Date,U>(uniqueKeysWithValues: keyValues)
    }
    
    func sorted() -> [(date: Date, value: Value)] {
        self.sorted(by: { $0.key < $1.key })
            .map{ (date: $0.0, value: $0.1) }
    }
    
    func temporalMerge<T,U>(other: [Date: T], merger: ValueMerger<Value,T,U>) -> [Date: U] {
        return temporalMerger(first: self, second: other, merger: merger)
    }
}

/// merges two dictionarys with date keys and merging closure
public func temporalMerger<T,U,V>(first:[Date: T], second: [Date: U], merger: ValueMerger<T,U,V>) -> [Date: V] {
    return Dictionary(uniqueKeysWithValues:
        Set(first.keys).union(Set(second.keys)).map{
            return ($0, merger(first[$0], second[$0]))
        }
    )
}

func rotate<U>(input: [[U]]) -> [[U?]] {
    if let longest = input.map({ return $0.count }).max() {
        return (0..<longest).map{ i -> [U?] in
            input.indices.map{ j -> U? in
                input[safe:j]?[safe:i]
            }
        }
    }
    return []
}

public extension Array {
    
    typealias Average = ([Element]) -> Element
    
    func movingAverage(period: Int, averager: Average) -> [Element] {
        if period < 1 {
            return self
        }
        
        let periods = (0..<period).reduce([self], {
            partial, _ in
            if let last = partial.last {
                return partial + [Array<Element>(last.dropLast())]
            }
            return partial
        }).map({
            Array<Element>($0.reversed())
        })
        
        let averages = rotate(input: periods).map({ (array: [Element?]) -> Element in
            let nonNil = array.compactMap{ return $0 }
            return averager(nonNil)
        })
        return averages.reversed()
    }
}

public extension Array where Element == Double {
    func movingAverage(period: Int) -> [Double] {
        return self.movingAverage(period: period, averager: { values in
            values.reduce(0, +) / Double(values.count)
        })
    }
}

typealias DateDouble = (Date, Double)

func dateDoubleTupleAvereger(values: [DateDouble]) -> DateDouble {
    let averageValue = values.map({ $0.1 }).reduce(0, +) / Double(values.count)
    let date = values.first!.0
    return (date, averageValue)
}

public extension Array where Element == (Date, Double) {
    func movingAverage(period: Int) -> [(Date, Double)] {
        return self.movingAverage(period: period, averager: dateDoubleTupleAvereger)
    }
    
    func toDictionary() -> [Date: Double] {
        let keys = self.map({ $0.0 })
        let values = self.map({ $0.1 })
        return Dictionary(uniqueKeysWithValues: zip(keys, values))
    }
}

public extension Dictionary where Key == Date, Value == Double {
    func movingAverage(period: Int) -> [Date: Double] {
        let sorted = self.sorted()
        let averages = sorted.movingAverage(period: period, averager: dateDoubleTupleAvereger)
        return Dictionary(uniqueKeysWithValues: averages)
    }
}
