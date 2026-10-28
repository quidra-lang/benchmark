part of 'main.dart';

const alphanumeric = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ \$%*+-./:',
    modes = ['NUMERIC', 'ALPHANUMERIC', 'BYTE'];

class Bits {
  final List<int> values;
  int position = 0;
  Bits([List<int>? values]) : values = values ?? [];
  void append(int value, int width) {
    for (var i = width - 1; i >= 0; i--) {
      values.add((value >> i) & 1);
    }
  }

  int read(int width) {
    var value = 0;
    for (var i = 0; i < width; i++) {
      value = value * 2 + values[position++];
    }
    return value;
  }
}

List<int> bitsFromWords(List<int> words) {
  final b = Bits();
  for (final w in words) {
    b.append(w, 8);
  }
  return b.values;
}

List<int> wordsFromBits(List<int> bits) {
  final b = Bits(bits), words = <int>[];
  while (b.position < bits.length) {
    words.add(b.read(8));
  }
  return words;
}

String binary(int value, int width) =>
    value.toRadixString(2).padLeft(width, '0');
String hexadecimal(List<int> words) =>
    words.map((w) => w.toRadixString(16).padLeft(2, '0')).join();
