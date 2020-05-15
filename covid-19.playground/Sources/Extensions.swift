import Foundation

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
public typealias DateValueTransformer<T,U> = (Date,T,Date,T?) -> (Date,U)
public typealias TemporalMap<T,U> = (Date, T) -> (Date, U?)
public typealias ValueMerger<T,U,V> = (T?, U?) -> V

public extension Dictionary where Key == Date {
    func temporalMap<U>(dateTransformer: DateTransformer, valueTransformer: ValueTransformer<Value,U>) -> [Date: U] {
        return Dictionary<Date,U>(uniqueKeysWithValues:
            self.map{ date, value in
                return (dateTransformer(date), valueTransformer(value))
            }
        )
    }
    
    func temporalMap<U>(mapper: TemporalMap<Value,U>) -> [Date: U?] {
        return Dictionary<Date,U?>(uniqueKeysWithValues:
            self.map{ date, value in
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
