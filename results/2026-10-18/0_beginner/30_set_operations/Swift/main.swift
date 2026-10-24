let a: Set<Int> = [12,5,8,21,5,17,3,12,9], b: Set<Int> = [8,14,21,6,14,3,25,6]
let results = [a.union(b), a.intersection(b), a.subtracting(b), a.symmetricDifference(b)]
let labels = ["union", "intersection", "difference", "symmetric difference"]
for i in labels.indices { print("\(labels[i]): \(results[i].sorted().map(String.init).joined(separator: " "))") }
