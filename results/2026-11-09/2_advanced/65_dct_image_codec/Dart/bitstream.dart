part of 'main.dart';

class BitWriter {
  final List<int> bytes;
  int value = 0, count = 0, padding = 0, stuffed = 0;
  BitWriter(List<int> header) : bytes = List.of(header);
  void write(int a, int n) {
    for (var i = n - 1; i >= 0; i--) {
      value = value * 2 + ((a >> i) & 1);
      count++;
      if (count == 8) {
        bytes.add(value);
        if (value == 255) {
          bytes.add(0);
          stuffed++;
        }
        value = 0;
        count = 0;
      }
    }
  }

  void pad() {
    if (count > 0) {
      final n = 8 - count;
      padding += n;
      write((1 << n) - 1, n);
    }
  }

  void marker(int m) {
    pad();
    bytes.addAll([255, m]);
  }
}

class DecodeError implements Exception {
  final String kind;
  DecodeError(this.kind);
}

class BitReader {
  final List<int> bytes;
  int pos, value = 0, left = 0;
  BitReader(this.bytes, this.pos);
  int read(int n) {
    var a = 0;
    for (var i = 0; i < n; i++) {
      if (left == 0) {
        if (pos >= bytes.length) throw DecodeError('marker');
        final v = bytes[pos];
        if (v == 255) {
          if (pos + 1 >= bytes.length || bytes[pos + 1] != 0)
            throw DecodeError('marker');
          pos += 2;
        } else {
          pos++;
        }
        value = v;
        left = 8;
      }
      left--;
      a = a * 2 + ((value >> left) & 1);
    }
    return a;
  }

  int symbol(Huffman t) {
    var code = 0;
    for (var l = 1; l <= 16; l++) {
      code = 2 * code + read(1);
      for (final v in t.values) {
        if (t.length[v] == l && t.code[v] == code) return v;
      }
    }
    throw DecodeError('code');
  }
}

int resync(List<int> b, int p) {
  while (p + 1 < b.length) {
    if (b[p] == 255 &&
        ((b[p + 1] >= 208 && b[p + 1] <= 215) || b[p + 1] == 217))
      return p;
    p++;
  }
  return b.length - 2;
}
