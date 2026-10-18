let pairs = [("kitten", "sitting"), ("flaw", "lawn"), ("listen", "silent"),
    ("intention", "execution"), ("algorithm", "altruistic")]
for (first,second) in pairs {
    let a = Array(first), b = Array(second)
    var dp = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
    for i in 0...a.count { dp[i][0] = i }
    for j in 0...b.count { dp[0][j] = j }
    for i in 1...a.count {
        for j in 1...b.count {
            let cost = a[i - 1] == b[j - 1] ? 0 : 1
            dp[i][j] = min(dp[i - 1][j] + 1, min(dp[i][j - 1] + 1, dp[i - 1][j - 1] + cost))
        }
    }
    print("\(first) -> \(second): \(dp[a.count][b.count])")
}
