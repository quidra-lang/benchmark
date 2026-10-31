import 'dart:math' as math;

void main() {
  const coins = [1, 5, 6, 9];
  final minimum = List.filled(41, 1000);
  minimum[0] = 0;
  for (var amount = 1; amount <= 40; amount++) {
    for (final coin in coins) {
      if (coin <= amount) {
        minimum[amount] = math.min(minimum[amount], minimum[amount - coin] + 1);
      }
    }
  }
  final ways = List.filled(41, 0);
  ways[0] = 1;
  for (final coin in coins) {
    for (var amount = coin; amount <= 40; amount++) {
      ways[amount] += ways[amount - coin];
    }
  }
  for (final target in [8, 11, 15, 22, 33, 40]) {
    var remaining = target, greedy = 0;
    for (final coin in coins.reversed) {
      greedy += remaining ~/ coin;
      remaining %= coin;
    }
    print(
      '$target: min=${minimum[target]} greedy=$greedy ways=${ways[target]}',
    );
  }
}
