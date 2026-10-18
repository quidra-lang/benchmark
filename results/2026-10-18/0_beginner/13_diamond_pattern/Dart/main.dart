import 'dart:io';


void main() {
  final out = StringBuffer();
  const n = 5;
  for (var row = 0; row < 2*n-1; row++) {
    final i = row < n ? row+1 : 2*n-1-row;
    out.writeln(' ' * (n-i) + '*' * (2*i-1));
  }
  stdout.write(out);
}
