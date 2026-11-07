part of 'main.dart';

class Ratio implements Comparable<Ratio> {
  final int n, d;
  Ratio(int numerator, int denominator)
    : n = numerator ~/ numerator.abs().gcd(denominator),
      d = denominator ~/ numerator.abs().gcd(denominator);
  @override
  int compareTo(Ratio s) => (n * s.d).compareTo(s.n * d);
  Ratio subtract(Ratio s) => Ratio(n * s.d - s.n * d, d * s.d);
  @override
  String toString() {
    final a = n.abs(), sign = n < 0 ? '-' : '';
    final t = 10000 * a ~/ d, ds = n < 0 && 10000 * a ~/ d != 0 ? '-' : '';
    return '$sign$a/$d=$ds${t ~/ 10000}.${(t % 10000).toString().padLeft(4, '0')}';
  }
}

Ratio parseRatio(String s) {
  final a = s.split('/');
  return Ratio(int.parse(a[0]), int.parse(a[1]));
}

String percent(int a, int b) {
  final t = 10000 * a ~/ b;
  return '${t ~/ 100}.${(t % 100).toString().padLeft(2, '0')}%';
}

String list(Iterable<String> a) => a.isEmpty ? '-' : a.join(',');
List<String> names(Iterable<String> a) => a.toSet().toList()..sort();
String yes(bool b) => b ? 'yes' : 'no';
void write(String path, StringBuffer s) =>
    File(path).writeAsStringSync(s.toString());
