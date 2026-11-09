import Foundation

var state: Int64 = 42
var free = [0, 0], arrival = 0, totalWait = 0, maxWait = 0
for customer in 1...20 {
    state = state * 48271 % 2147483647
    arrival += Int(state % 5) + 1
    state = state * 48271 % 2147483647
    let service = Int(state % 7) + 2, teller = free[0] <= free[1] ? 0 : 1
    let start = max(arrival, free[teller]), end = start + service, wait = start - arrival
    free[teller] = end
    totalWait += wait
    maxWait = max(maxWait, wait)
    print("customer \(customer): arrive=\(arrival) start=\(start) end=\(end) " +
        "teller=\(teller + 1) wait=\(wait)")
}
print(String(format: "average wait: %.2f", locale: Locale(identifier: "en_US_POSIX"), Double(totalWait) / 20))
print("max wait: \(maxWait)")
print("last departure: \(free.max()!)")
