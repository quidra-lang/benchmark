func queens(_ positions: inout [Int], _ row: Int, _ first: inout [Int], _ found: inout Bool) -> Int {
    if row == positions.count {
        if !found { first = positions }
        found = true
        return 1
    }
    var count = 0
    for column in positions.indices {
        let safe = (0..<row).allSatisfy { previous in
            positions[previous] != column && abs(positions[previous] - column) != row - previous
        }
        if safe {
            positions[row] = column
            count += queens(&positions,row + 1,&first,&found)
        }
    }
    return count
}
var firstEight = [Int](repeating: 0, count: 8)
for n in 4...8 {
    var positions = [Int](repeating: 0, count: n), first = positions, found = false
    let solutions = queens(&positions,0,&first,&found)
    print("N=\(n): \(solutions) solutions")
    if n == 8 { firstEight = first }
}
for column in firstEight {
    print(String(repeating: ".", count: column) + "Q" + String(repeating: ".", count: 7 - column))
}
