import Foundation

nonisolated enum OfficeNumbering {
    static let formats: Set<String> = ["decimal", "decimalZero", "lowerLetter", "upperLetter", "lowerRoman", "upperRoman", "bullet", "none"]
    static func label(_ value: Int, format: String) -> String {
        switch format {
        case "none": return ""
        case "bullet": return "•"
        case "decimalZero": return value < 10 && value >= 0 ? "0\(value)" : String(value)
        case "lowerLetter", "upperLetter":
            guard value > 0, value <= 1_000_000 else { return String(value) }
            var remainder = value
            var result = ""
            while remainder > 0 {
                remainder -= 1
                result.insert(Character(UnicodeScalar(65 + remainder % 26)!), at: result.startIndex)
                remainder /= 26
            }
            return format == "lowerLetter" ? result.lowercased() : result
        case "lowerRoman", "upperRoman":
            guard (1...3999).contains(value) else { return String(value) }
            var remainder = value
            var result = ""
            for (amount, symbol) in [(1000,"M"),(900,"CM"),(500,"D"),(400,"CD"),(100,"C"),(90,"XC"),(50,"L"),(40,"XL"),(10,"X"),(9,"IX"),(5,"V"),(4,"IV"),(1,"I")] {
                while remainder >= amount { result += symbol; remainder -= amount }
            }
            return format == "lowerRoman" ? result.lowercased() : result
        default: return String(value)
        }
    }
    static func odtFormat(_ format: String?) -> String {
        switch format {
        case "a": "lowerLetter"
        case "A": "upperLetter"
        case "i": "lowerRoman"
        case "I": "upperRoman"
        case "": "none"
        default: "decimal"
        }
    }
    static func safeLink(_ value: String?) -> String? {
        guard let value, value.count <= 4096, let url = URL(string: value),
              let scheme = url.scheme?.lowercased(), ["https", "http", "mailto"].contains(scheme) else { return nil }
        return url.absoluteString
    }
}
