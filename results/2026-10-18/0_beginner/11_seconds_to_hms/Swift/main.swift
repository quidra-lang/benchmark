import Foundation


for seconds in [0, 59, 3725, 45296, 86400, 312047] {
    let parts = [seconds / 3600, seconds / 60 % 60, seconds % 60]
    let time = parts.map { String($0).count < 2 ? "0" + String($0) : String($0) }.joined(separator: ":")
    print("\(seconds) seconds = \(time)")
}
