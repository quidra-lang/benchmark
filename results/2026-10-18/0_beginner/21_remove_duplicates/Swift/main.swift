let values = [12,5,12,8,3,5,20,8,8,15,3,7,20,12,9]
var seen = Set<Int>()
let unique = values.filter { seen.insert($0).inserted }
print(unique.map(String.init).joined(separator: " "))
print("removed: \(values.count - unique.count)")
