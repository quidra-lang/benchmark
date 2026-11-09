import 'dart:math' as math;

void main() {
  for (final p in [
    ('kitten', 'sitting'),
    ('flaw', 'lawn'),
    ('listen', 'silent'),
    ('intention', 'execution'),
    ('algorithm', 'altruistic'),
  ]) {
    final a = p.$1,
        b = p.$2,
        dp = List.generate(
          p.$1.length + 1,
          (_) => List.filled(p.$2.length + 1, 0),
        );
    for (var i = 0; i <= a.length; i++) {
      dp[i][0] = i;
    }
    for (var j = 0; j <= b.length; j++) {
      dp[0][j] = j;
    }
    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        dp[i][j] = math.min(
          math.min(dp[i - 1][j] + 1, dp[i][j - 1] + 1),
          dp[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1),
        );
      }
    }
    print('$a -> $b: ${dp[a.length][b.length]}');
  }
}
