part of 'main.dart';

String decimal2(int a, int b) {
  final n = (200 * a + b) ~/ (2 * b);
  return '${n ~/ 100}.${(n % 100).toString().padLeft(2, '0')}';
}

(String, String) subpixel(List<int> cost, int d, Params p) {
  var a = 0, b = 1;
  final index = d - p.min;
  if (d > p.min &&
      d < p.max &&
      cost[index - 1] > cost[index] &&
      cost[index + 1] >= cost[index]) {
    a = cost[index - 1] - cost[index + 1];
    b = 2 * (cost[index - 1] - 2 * cost[index] + cost[index + 1]);
  }
  final q = (200 * (d * b + a) + b) ~/ (2 * b);
  return (
    '${q ~/ 100}.${(q % 100).toString().padLeft(2, '0')}',
    decimal2(100 * p.focal * p.baseline, q),
  );
}

int depthHundred(int d, Params p) =>
    (200 * p.focal * p.baseline + d) ~/ (2 * d);
