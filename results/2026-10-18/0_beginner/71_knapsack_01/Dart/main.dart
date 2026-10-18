import 'dart:math' as math;

void main() {
    const names = ['tent', 'stove', 'lantern', 'rope', 'camera', 'blanket', 'water'], weights = [10,
        3, 2, 3, 5, 5, 6], values = [120, 65, 45, 20, 90, 85, 100];
    final dp = List.generate(8, (_) => List.filled(21, 0));
    for (var i = 1; i <= 7; i++) {
        for (var c = 0; c <= 20; c++) {
            dp[i][c] = dp[i - 1][c];
            if (weights[i - 1] <= c)
                dp[i][c] = math.max(dp[i][c], dp[i - 1][c - weights[i - 1]] + values[i - 1]);
        }
    }
    final chosen = List.filled(7, false);
    var capacity = 20;
    for (var i = 7; i > 0; i--) {
        if (dp[i][capacity] != dp[i - 1][capacity]) {
            chosen[i - 1] = true;
            capacity -= weights[i - 1];
        }
    }
    print('max value: ${dp[7][20]}\ntotal weight: ${20 - capacity}');
    print('items: ${[for(var i=0;i<7;i++) if(chosen[i])names[i]].join(' ')}');
}
