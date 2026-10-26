let board = ["MMONKENBIR", "PMTIGERJPL", "TGREJEDUZI", "SPYUTEJDEC", "WKAPSIDLBN",
    "KUVNGSBPRO", "RIBSDACBAM", "YWVAUAPKAH", "KYCGTHHESR", "OCCALAOKKR"].map { Array($0) }
let directions = ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
let dr = [0, 1, 1, 1, 0, -1, -1, -1], dc = [1, 1, 0, -1, -1, -1, 0, 1]
for word in ["TIGER", "ZEBRA", "MONKEY", "PANDA", "KOALA", "RABBIT"] {
    let letters = Array(word)
    var result = "not found"
    search: for r in 0..<10 {
        for c in 0..<10 {
            for d in 0..<8 {
                let match = letters.indices.allSatisfy { k in
                    let nr = r + k * dr[d], nc = c + k * dc[d]
                    return nr >= 0 && nr < 10 && nc >= 0 && nc < 10 && board[nr][nc] == letters[k]
                }
                if match {
                    result = "(\(r), \(c)) \(directions[d])"
                    break search
                }
            }
        }
    }
    print("\(word): \(result)")
}
