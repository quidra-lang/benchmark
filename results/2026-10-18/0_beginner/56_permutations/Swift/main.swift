func permute(_ prefix: String, _ used: inout [Bool], _ count: inout Int) {
    if prefix.count == 4 {
        count += 1
        print("\(count): \(prefix)")
        return
    }
    let letters = Array("ABCD")
    for i in 0..<4 where !used[i] {
        used[i] = true
        permute(prefix + String(letters[i]), &used, &count)
        used[i] = false
    }
}
var used = [Bool](repeating: false,count: 4), count = 0
permute("",&used,&count)
