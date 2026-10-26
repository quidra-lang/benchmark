const ones = [
  'zero',
  'one',
  'two',
  'three',
  'four',
  'five',
  'six',
  'seven',
  'eight',
  'nine',
  'ten',
  'eleven',
  'twelve',
  'thirteen',
  'fourteen',
  'fifteen',
  'sixteen',
  'seventeen',
  'eighteen',
  'nineteen',
];
const tens = [
  '',
  '',
  'twenty',
  'thirty',
  'forty',
  'fifty',
  'sixty',
  'seventy',
  'eighty',
  'ninety',
];

String under(int n) {
  final parts = <String>[];
  if (n ~/ 100 > 0) parts.add('${ones[n ~/ 100]} hundred');
  final y = n % 100;
  if (y > 0) {
    parts.add(
      y < 20 ? ones[y] : tens[y ~/ 10] + (y % 10 > 0 ? '-${ones[y % 10]}' : ''),
    );
  }
  return parts.join(' ');
}

void main() {
  for (final n in [0, 13, 40, 100, 568, 71000, 300019, 999999]) {
    final parts = <String>[];
    if (n == 0) parts.add('zero');
    if (n ~/ 1000 > 0) parts.add('${under(n ~/ 1000)} thousand');
    if (n % 1000 > 0) parts.add(under(n % 1000));
    print('$n: ${parts.join(' ')}');
  }
}
