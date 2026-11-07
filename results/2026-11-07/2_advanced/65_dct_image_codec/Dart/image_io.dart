part of 'main.dart';

class Image {
  final int w, h;
  final List<int> rgb;
  Image(this.w, this.h, this.rgb);
}

class Parameters {
  final List<int> qualities, truncate;
  final String sampling, mode;
  final int restart, target, generations;
  Parameters(
    this.qualities,
    this.truncate,
    this.sampling,
    this.mode,
    this.restart,
    this.target,
    this.generations,
  );
}

class InputTables {
  final List<int> c;
  final List<List<int>> base;
  final List<Huffman> standard;
  InputTables(this.c, this.base, this.standard);
}

List<int> ints(String s) => s.split(RegExp(r'\s+')).map(int.parse).toList();
String joined(Iterable<int> a) => a.join(' ');
String readText(String p) => File(p).readAsStringSync();
void writeText(String p, String s) => File(p).writeAsStringSync(s);
Image readImage(String path) {
  final f = readText(path).trim().split(RegExp(r'\s+'));
  final w = int.parse(f[1]), h = int.parse(f[2]);
  return Image(w, h, f.skip(4).map(int.parse).toList());
}

void writeImage(String path, Image im) {
  final s = StringBuffer('P3\n${im.w} ${im.h}\n255\n');
  for (var y = 0; y < im.h; y++) {
    s.writeln(joined(im.rgb.sublist(y * 3 * im.w, (y + 1) * 3 * im.w)));
  }
  writeText(path, s.toString());
}

Parameters readParameters() {
  final l = readText(
    'input/params.txt',
  ).trim().split('\n').map((v) => v.split(' ')).toList();
  return Parameters(
    l[0].skip(1).map(int.parse).toList(),
    l[6].skip(1).map(int.parse).toList(),
    l[1][1],
    l[3][1],
    int.parse(l[2][1]),
    int.parse(l[4][1]),
    int.parse(l[5][1]),
  );
}

InputTables readTables() {
  final l = readText('input/tables.txt').trim().split('\n');
  final c = <int>[],
      base = List.generate(2, (_) => <int>[]),
      standard = <Huffman>[];
  for (var y = 0; y < 8; y++) {
    c.addAll(ints(l[y + 1]));
    for (var k = 0; k < 2; k++) {
      base[k].addAll(ints(l[10 + 9 * k + y]));
    }
  }
  for (var k = 0; k < 4; k++) {
    standard.add(Huffman([0, ...ints(l[28 + 3 * k])], ints(l[29 + 3 * k])));
  }
  return InputTables(c, base, standard);
}

List<int> readHex(String path) {
  final s = readText(path).replaceAll(RegExp(r'\s'), '');
  return [
    for (var i = 0; i < s.length; i += 2)
      int.parse(s.substring(i, i + 2), radix: 16),
  ];
}

void writeHex(String path, List<int> b) {
  final s = StringBuffer();
  for (var i = 0; i < b.length; i += 32) {
    s.writeln(
      b
          .sublist(i, min(i + 32, b.length))
          .map((v) => v.toRadixString(16).padLeft(2, '0'))
          .join(),
    );
  }
  writeText(path, s.toString());
}
