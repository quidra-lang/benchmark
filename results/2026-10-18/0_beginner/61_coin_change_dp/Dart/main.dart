import 'dart:io';
import 'dart:math' as math;

void main() {
    final out = StringBuffer();
    const coins = [1, 5, 6, 9];
    for (final target in [8, 11, 15, 22, 33, 40]) {
        final minimum = List.filled(target + 1, 1000);
        minimum[0] = 0;
        for (var amount = 1; amount <= target; amount++) {
            for (final coin in coins) {
                if (coin <= amount)
                    minimum[amount] = math.min(minimum[amount], minimum[amount - coin] + 1);
            }
        }
        final ways = List.filled(target + 1, 0);
        ways[0] = 1;
        for (final coin in coins) {
            for (var amount = coin; amount <= target; amount++)
                ways[amount] += ways[amount - coin];
        }
        var remaining = target, greedy = 0;
        for (final coin in coins.reversed) {
            greedy += remaining ~/ coin;
            remaining %= coin;
        }
        out.writeln('$target: min=${minimum[target]} greedy=$greedy ways=${ways[target]}');
    }
    stdout.write(out);
}
