import Foundation

func coerceInt(_ value: Any?) -> Int? {
    if let v = value as? Int { return v }
    if let v = value as? NSNumber { return v.intValue }
    if let v = value as? String { return Int(v) }
    return nil
}
