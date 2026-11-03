part of 'main.dart';

List<String> hexLines(List<int> samples) => [
  for (var start = 0; start < samples.length; start += 32)
    samples
        .sublist(start, math.min(start + 32, samples.length))
        .map(hex2)
        .join(),
];
String adler32Text(List<int> values) {
  var a = 1, b = 0;
  for (final value in values) {
    a = (a + value) % 65521;
    b = (b + a) % 65521;
  }
  return (b * 65536 + a).toRadixString(16).toUpperCase().padLeft(8, '0');
}

int peak(List<int> values, int center) {
  var p = 0;
  for (final value in values) {
    p = math.max(p, (value - center).abs());
  }
  return p;
}

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

int rootMeanSquare(List<int> values, int center) {
  var total = 0;
  for (final value in values) {
    final d = value - center;
    total += d * d;
  }
  return isqrt(total ~/ values.length);
}

int zeroCrossings(List<int> samples) {
  var count = 0;
  for (var i = 1; i < samples.length; i++) {
    if ((samples[i - 1] < 128) != (samples[i] < 128)) count++;
  }
  return count;
}
