part of 'main.dart';

const scaleUnit = 4096;
int floorDiv(int a, int b) {
  var q = a ~/ b;
  if (a % b != 0 && ((a < 0) != (b < 0))) q--;
  return q;
}

int mul(int a, int b) => floorDiv(a * b, scaleUnit);
int isqrt(int n) {
  if (n < 2) return n;
  var lo = 1, hi = n;
  while (lo <= hi) {
    final m = (lo + hi) ~/ 2;
    if (m <= n ~/ m) {
      lo = m + 1;
    } else {
      hi = m - 1;
    }
  }
  return hi;
}
