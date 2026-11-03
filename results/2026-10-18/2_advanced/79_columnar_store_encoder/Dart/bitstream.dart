part of 'main.dart';

class Reader {
  final List<int> data;
  int position;
  Reader(this.data, [this.position = 0]);
  int byte() => data[position++];
  List<int> take(int n) {
    final v = data.sublist(position, position + n);
    position += n;
    return v;
  }

  int uleb() {
    var value = 0, shift = 0;
    while (true) {
      final b = byte();
      value |= (b & 127) << shift;
      if (b < 128) return value;
      shift += 7;
    }
  }

  int zigzag() {
    final v = uleb();
    return v % 2 == 0 ? v ~/ 2 : -(v + 1) ~/ 2;
  }

  int u32() {
    final a = take(4);
    return a[0] | (a[1] << 8) | (a[2] << 16) | (a[3] << 24);
  }
}

void appendULEB(List<int> out, int n) {
  while (n >= 128) {
    out.add(n % 128 + 128);
    n ~/= 128;
  }
  out.add(n);
}

void appendZigzag(List<int> out, int x) {
  appendULEB(out, x >= 0 ? 2 * x : -2 * x - 1);
}

void appendU32(List<int> out, int n) {
  for (var i = 0; i < 4; i++) {
    out.add((n >> (8 * i)) & 255);
  }
}

List<int> pack(List<int> a, int w) {
  final out = List.filled(a.length * w ~/ 8, 0);
  for (var i = 0; i < a.length; i++) {
    for (var j = 0; j < w; j++) {
      if (((a[i] >> j) & 1) != 0) {
        final k = i * w + j;
        out[k ~/ 8] |= 1 << (k % 8);
      }
    }
  }
  return out;
}

List<int> unpack(Reader r, int count, int w) {
  final data = r.take(count * w ~/ 8), out = List.filled(count, 0);
  for (var i = 0; i < count; i++) {
    for (var j = 0; j < w; j++) {
      final k = i * w + j;
      out[i] |= ((data[k ~/ 8] >> (k % 8)) & 1) << j;
    }
  }
  return out;
}

int adler(List<int> data) {
  var a = 1, b = 0;
  for (final v in data) {
    a = (a + v) % 65521;
    b = (b + a) % 65521;
  }
  return b * 65536 + a;
}

List<int> encodeHybrid(List<int> a, int w) {
  final out = <int>[];
  int run(int i) {
    var j = i + 1;
    while (j < a.length && a[j] == a[i]) {
      j++;
    }
    return j - i;
  }

  var i = 0;
  while (i < a.length) {
    final length = run(i);
    if (length >= 8) {
      appendULEB(out, 2 * length);
      for (var j = 0; j < (w + 7) ~/ 8; j++) {
        out.add((a[i] >> (8 * j)) & 255);
      }
      i += length;
    } else {
      var j = i, g = 0;
      do {
        j += 8;
        g++;
      } while (j < a.length && g < 63 && run(j) < 8);
      appendULEB(out, 2 * g + 1);
      final values = List.filled(8 * g, 0);
      values.setRange(0, min(j, a.length) - i, a.skip(i));
      out.addAll(pack(values, w));
      i = j;
    }
  }
  return out;
}

List<int> decodeHybrid(Reader r, int count, int w) {
  final out = <int>[];
  while (out.length < count) {
    final header = r.uleb();
    if (header % 2 == 0) {
      var value = 0;
      for (var j = 0; j < (w + 7) ~/ 8; j++) {
        value |= r.byte() << (8 * j);
      }
      out.addAll(List.filled(header ~/ 2, value));
    } else {
      out.addAll(unpack(r, 8 * ((header - 1) ~/ 2), w));
    }
  }
  return out.sublist(0, count);
}
