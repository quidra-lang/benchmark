part of 'main.dart';

Ratio dependency(Map<Pair, int> d, String a, String b) =>
    Ratio(count(d, a, b) - count(d, b, a), count(d, a, b) + count(d, b, a) + 1);
Ratio loopMeasure(int n) => Ratio(n, n + 1);
Ratio splitMeasure(Map<Pair, int> d, String a, String b, String c, bool join) =>
    Ratio(
      count(d, b, c) + count(d, c, b),
      join
          ? count(d, b, a) + count(d, c, a) + 1
          : count(d, a, b) + count(d, a, c) + 1,
    );
