import 'dart:io';

int gcd(int a, int b) {
  while (b != 0) { final r = a % b; a = b; b = r; }
  return a;
}

void main() {
  final out = StringBuffer();
  for (final p in [[48,180],[1071,462],[7,91],[13,97],[36288,98280]]) {
    final g = gcd(p[0],p[1]);
    final l = (p[0] ~/ g)*p[1];
    out.writeln('gcd(${p[0]}, ${p[1]}) = $g, lcm(${p[0]}, ${p[1]}) = $l');
  }
  stdout.write(out);
}
