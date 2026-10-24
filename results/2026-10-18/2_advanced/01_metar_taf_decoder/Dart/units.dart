part of 'main.dart';
int floorDiv(int n, int d) => n >= 0 ? n ~/ d : -((-n + d - 1) ~/ d);

int knots(int v, String unit) => unit == 'MPS' ? (v * 1944 + 500) ~/ 1000 : v;

int inhg(int q) => (q * 2953 + 500) ~/ 1000;

int hpa(int a) => (a * 33864 + 50000) ~/ 100000;

const sineTable = [0, 174, 342, 500, 643, 766, 866, 940, 985, 1000];

int sine(int x) {
  final y = x % 360;
  if (y <= 90) return sineTable[y ~/ 10];
  if (y <= 180) return sineTable[(180 - y) ~/ 10];
  if (y <= 270) return -sineTable[(y - 180) ~/ 10];
  return -sineTable[(360 - y) ~/ 10];
}

int cosine(int x) => sine(x + 90);

int daysInMonth(int y, int m) {
  if (m == 2) {
    return y % 4 == 0 && (y % 100 != 0 || y % 400 == 0) ? 29 : 28;
  }
  return [1, 3, 5, 7, 8, 10, 12].contains(m) ? 31 : 30;
}

int dayMinutes(int d, int h, int m) => ((d - 1) * 24 + h) * 60 + m;

String pad(int n, int w) => n.toString().padLeft(w, '0');

class Calendar {
  final int year, month;
  Calendar(this.year, this.month);
  int get days => daysInMonth(year, month);
  int get nextYear => month == 12 ? year + 1 : year;
  int get nextMonth => month == 12 ? 1 : month + 1;
  int? forecastTime(int d, int h, int m, int issueDay) {
    final next = d < issueDay;
    if (d < 1 || d > daysInMonth(next ? nextYear : year, next ? nextMonth : month)) {
      return null;
    }
    return (next ? days * 1440 : 0) + dayMinutes(d, h, m);
  }
  String stamp(int t) {
    final next = t >= days * 1440;
    if (next) t -= days * 1440;
    final date = '${pad(next ? nextYear : year, 4)}-${pad(next ? nextMonth : month, 2)}-${pad(t ~/ 1440 + 1, 2)}';
    return '${date}T${pad(t % 1440 ~/ 60, 2)}:${pad(t % 60, 2)}Z';
  }
}

(int, int) miles(Group g) {
  if (g.visibilityKind == 'MILES') {
    return g.denominator == 0
    ? (g.whole, 1)
    : (g.whole * g.denominator + g.numerator, g.denominator);
  }
  return (1000 * g.meters, 1609344);
}

int meterValue(Group g) {
  final (n, d) = miles(g);
  return g.visibilityKind == 'MILES' ? 1609344 * n ~/ (1000 * d) : g.meters;
}

bool lessFraction((int, int) a, (int, int) b) => a.$1 * b.$2 < b.$1 * a.$2;

String fraction(int n, int d) {
  if (d == 0) return 'undefined';
  final g = n.abs().gcd(d.abs());
  if (d < 0) {
    n = -n;
    d = -d;
  }
  return '${n ~/ g}/${d ~/ g}';
}
