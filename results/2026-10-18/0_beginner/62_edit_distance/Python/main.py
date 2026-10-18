pairs = [("kitten", "sitting"), ("flaw", "lawn"), ("listen", "silent"),
         ("intention", "execution"), ("algorithm", "altruistic")]
for a, b in pairs:
    dp = [[0] * (len(b) + 1) for _ in range(len(a) + 1)]
    for i in range(len(a) + 1):
        dp[i][0] = i
    for j in range(len(b) + 1):
        dp[0][j] = j
    for i in range(1, len(a) + 1):
        for j in range(1, len(b) + 1):
            cost = int(a[i - 1] != b[j - 1])
            dp[i][j] = min(dp[i - 1][j] + 1, dp[i][j - 1] + 1, dp[i - 1][j - 1] + cost)
    print(f"{a} -> {b}: {dp[-1][-1]}")
