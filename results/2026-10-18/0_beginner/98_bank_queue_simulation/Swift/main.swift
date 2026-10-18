import Foundation

func fixed(_ value: Double, _ places: Int) -> String {
    var scale = 1
    for _ in 0..<places { scale *= 10 }
    let scaled = Int((abs(value) * Double(scale)).rounded(.toNearestOrAwayFromZero))
    let fraction = String(scaled % scale)
    return "\(value < 0 ? "-" : "")\(scaled / scale).\(String(repeating: "0", count: places - fraction.count))\(fraction)"
}
var state: Int64 = 42
var free = [0,0], arrival = 0, totalWait = 0, maxWait = 0
for customer in 1...20 {
    state = state * 48271 % 2147483647
    arrival += Int(state % 5) + 1
    state = state * 48271 % 2147483647
    let service = Int(state % 7) + 2, teller = free[0] <= free[1] ? 0 : 1
    let start = max(arrival,free[teller]), end = start + service, wait = start - arrival
    free[teller] = end
    totalWait += wait
    maxWait = max(maxWait,wait)
    print("customer \(customer): arrive=\(arrival) start=\(start) end=\(end) " +
        "teller=\(teller + 1) wait=\(wait)")
}
print("average wait: \(fixed(Double(totalWait) / 20,2))")
print("max wait: \(maxWait)")
print("last departure: \(free.max()!)")
