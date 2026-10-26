fn main() {
    for (a, b) in [
        ("kitten", "sitting"),
        ("flaw", "lawn"),
        ("listen", "silent"),
        ("intention", "execution"),
        ("algorithm", "altruistic"),
    ] {
        let (m, n) = (a.len(), b.len());
        let mut dp = vec![vec![0; n + 1]; m + 1];
        for i in 0..=m {
            dp[i][0] = i;
        }
        for j in 0..=n {
            dp[0][j] = j;
        }
        for i in 1..=m {
            for j in 1..=n {
                let cost = usize::from(a.as_bytes()[i - 1] != b.as_bytes()[j - 1]);
                dp[i][j] = (dp[i - 1][j] + 1)
                    .min(dp[i][j - 1] + 1)
                    .min(dp[i - 1][j - 1] + cost);
            }
        }
        println!("{} -> {}: {}", a, b, dp[m][n]);
    }
}
