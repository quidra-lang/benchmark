part of 'main.dart';

int floorDiv(int a, int b) => a ~/ b - (a < 0 && a.remainder(b) != 0 ? 1 : 0);
int rdiv(int a, int b) => floorDiv(2 * a + b, 2 * b);
int isqrt(int n) {
  var lo = 0, hi = n;
  while (lo < hi) {
    final mid = lo + (hi - lo) ~/ 2 + 1;
    if (mid <= n ~/ mid) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return lo;
}

int root(int p, int q) => (isqrt(40000 * p ~/ q) + 1) ~/ 2;
String two(int v) =>
    '${v < 0 ? '-' : ''}${v.abs() ~/ 100}.${(v.abs() % 100).toString().padLeft(2, '0')}';
String four(int v) => '${v ~/ 10000}.${(v % 10000).toString().padLeft(4, '0')}';
String fraction(int a, int b) {
  final divisor = a.gcd(b);
  return '${a ~/ divisor}/${b ~/ divisor}';
}

String ratio(int a, int b) => b == 0
    ? '$a/0 none'
    : '$a/$b reduced=${fraction(a, b)} percent=${two(rdiv(10000 * a, b))}';
String maybeTwo(int? value) => value == null ? 'none' : two(value);
String optional(int value) => value == 0 ? '-' : '$value';
