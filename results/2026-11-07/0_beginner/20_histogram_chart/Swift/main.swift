let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], counts = [7, 12, 4, 15, 9, 18, 11]
for i in days.indices {
    let count = counts[i]
    print("\(days[i]) | \(String(repeating: "*", count: count)) \(count)")
}
