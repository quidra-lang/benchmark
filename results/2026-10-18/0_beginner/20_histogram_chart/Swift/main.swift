import Foundation


let days = ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"], counts = [7,12,4,15,9,18,11]
for i in days.indices { print("\(days[i]) | \(String(repeating: "*", count: counts[i])) \(counts[i])") }
