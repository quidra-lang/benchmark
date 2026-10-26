import 'dart:math' as math;

void main() {
  final prime = List.filled(201, true);
  prime[0] = false;
  prime[1] = false;
  for (var p = 2; p <= 200; p++) {
    if (prime[p]) {
      for (var m = 2 * p; m <= 200; m += p) {
        prime[m] = false;
      }
    }
  }
  final values = [
    for (var p = 2; p <= 200; p++)
      if (prime[p]) p,
  ];
  print('count: ${values.length}');
  for (var i = 0; i < values.length; i += 10) {
    print(values.sublist(i, math.min(i + 10, values.length)).join(' '));
  }
}
