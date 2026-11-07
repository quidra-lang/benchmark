import Foundation

func hundredths(_ value: Int) -> String { let fraction = String(value % 100); return "\(value / 100)." + (fraction.count == 1 ? "0" : "") + fraction }
func twoDecimals(_ numerator: Int, _ denominator: Int = 1) -> String { hundredths((200 * numerator + denominator) / (2 * denominator)) }
func depthHundredths(_ disparity: Int, _ focal: Int, _ baseline: Int) -> Int { (200 * focal * baseline + disparity) / (2 * disparity) }
func subpixel(_ disparity: Int, _ costs: [Int], _ minimum: Int, _ maximum: Int, _ focal: Int, _ baseline: Int) -> (disparity: String, depth: String) { let index = disparity - minimum; var a = 0, b = 1; if disparity > minimum && disparity < maximum && costs[index - 1] > costs[index] && costs[index + 1] >= costs[index] { a = costs[index - 1] - costs[index + 1]; b = 2 * (costs[index - 1] - 2 * costs[index] + costs[index + 1]) }; let rounded = (200 * (disparity * b + a) + b) / (2 * b); return (hundredths(rounded), twoDecimals(100 * focal * baseline, rounded)) }
