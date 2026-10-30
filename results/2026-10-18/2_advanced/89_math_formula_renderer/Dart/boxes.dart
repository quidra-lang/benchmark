part of 'main.dart';

class Placement {
  final Box box;
  final int x, y;
  final String role;
  Placement(this.box, this.x, this.y, [this.role = '']);
}

class Drawn {
  final String text;
  final int x, y;
  Drawn(this.text, this.x, this.y);
}

class Box {
  final int width, height, baseline;
  final String description;
  final List<Placement> children = [];
  final List<Drawn> drawn = [];
  Box(this.width, this.height, this.baseline, this.description);
  int get descent => height - 1 - baseline;
  void add(Box box, int x, int y, [String role = '']) =>
      children.add(Placement(box, x, y, role));
  void draw(String text, int x, int y) => drawn.add(Drawn(text, x, y));
}

const largeGlyphs = {
  r'\sum': [r'\--', ' > ', '/--'],
  r'\prod': ['___', '| |', '| |'],
  r'\int': [' /', ' |', '/ '],
};
const symbolTypes = {
  '+': 'binary',
  '-': 'binary',
  '*': 'binary',
  '=': 'relation',
  '<': 'relation',
  '>': 'relation',
  ':': 'relation',
  '(': 'open',
  '[': 'open',
  ')': 'close',
  ']': 'close',
  '!': 'close',
  ',': 'punctuation',
  ';': 'punctuation',
};
List<String> delimiterGlyph(String value, int height) {
  if (value == '.') return [];
  final actual = value[value.length - 1], glyph = List.filled(height, actual);
  if (height >= 2 && '(){}'.contains(actual)) {
    glyph.fillRange(0, height, '|');
    if (actual == '(' || actual == '{') {
      glyph[0] = '/';
      glyph[height - 1] = '\\';
    } else {
      glyph[0] = '\\';
      glyph[height - 1] = '/';
    }
    if (height >= 3) {
      if (actual == '{') glyph[(height - 1) ~/ 2] = '<';
      if (actual == '}') glyph[(height - 1) ~/ 2] = '>';
    }
  }
  return glyph;
}

void drawDelimiter(Box box, String value, int x, int height) {
  final glyph = delimiterGlyph(value, height);
  for (var y = 0; y < glyph.length; y++) {
    box.draw(glyph[y], x, y);
  }
}

String delimiterString(String value) =>
    value == '.' ? '' : value[value.length - 1];
int center(Box box, int width) => (width - box.width) ~/ 2;
Box delimit(Box body, String left, String right) {
  final wl = left == '.' ? 0 : 1,
      wr = right == '.' ? 0 : 1,
      out = Box(
        wl + body.width + wr,
        body.height,
        body.baseline,
        'delim $left $right',
      );
  out.add(body, wl, 0);
  drawDelimiter(out, left, 0, body.height);
  drawDelimiter(out, right, wl + body.width, body.height);
  return out;
}

Box atomBox(Node n, bool script, Map<String, String> references) {
  var display = n.value, description = 'atom "${n.value}"';
  if (n.kind == 'text') description = 'text "${n.value}"';
  if (n.kind == 'reference') {
    description = 'eqref "${n.value}"';
    display = references[n.value] ?? '(??)';
  }
  if (n.kind == 'command') {
    display = symbolCommands[n.value]!.display;
    final glyph = largeGlyphs[n.value];
    if (glyph != null && !script) {
      final out = Box(glyph.first.length, 3, 1, description);
      for (var y = 0; y < glyph.length; y++) {
        out.draw(glyph[y], 0, y);
      }
      return out;
    }
  }
  final out = Box(display.length, 1, 0, description);
  out.draw(display, 0, 0);
  return out;
}

String repeated(String c, int count) => List.filled(count, c).join();
