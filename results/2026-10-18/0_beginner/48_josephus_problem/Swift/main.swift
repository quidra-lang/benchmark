for (n, k) in [(7, 3), (10, 2), (41, 3)] {
    var index = 0, people = Array(1...n), removed = [Int]()
    while !people.isEmpty {
        index = (index + k - 1) % people.count
        removed.append(people.remove(at: index))
    }
    print("n=\(n) k=\(k): \(removed.map(String.init).joined(separator: " "))")
    print("survivor: \(removed.last!)")
}
