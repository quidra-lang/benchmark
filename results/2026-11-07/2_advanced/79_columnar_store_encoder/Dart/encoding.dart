part of 'main.dart';

const methodNames = [
  'PLAIN',
  'DICTIONARY',
  'RLE',
  'DELTA_BINARY_PACKED',
  'DELTA_LENGTH_BYTE_ARRAY',
];
List<int> candidates(String kind) => switch (kind) {
  'BOOL' => [0, 2],
  'STRING' => [0, 1, 4],
  _ => [0, 1, 3],
};
List<int> encodeDelta(List<int> a) {
  final out = <int>[];
  appendULEB(out, 128);
  appendULEB(out, 4);
  appendULEB(out, a.length);
  appendZigzag(out, a.isEmpty ? 0 : a[0]);
  for (var start = 1; start < a.length; start += 128) {
    final end = min(start + 128, a.length),
        deltas = [for (var i = start; i < end; i++) a[i] - a[i - 1]],
        minimum = deltas.reduce(min);
    appendZigzag(out, minimum);
    final widths = <int>[];
    for (var t = 0; t < 4; t++) {
      var maximum = 0;
      for (var i = t * 32; i < min((t + 1) * 32, deltas.length); i++) {
        maximum = max(maximum, deltas[i] - minimum);
      }
      widths.add(maximum.bitLength);
      out.add(maximum.bitLength);
    }
    for (var t = 0; t < 4 && t * 32 < deltas.length; t++) {
      final values = List.filled(32, 0);
      for (var i = t * 32; i < min((t + 1) * 32, deltas.length); i++) {
        values[i - t * 32] = deltas[i] - minimum;
      }
      out.addAll(pack(values, widths[t]));
    }
  }
  return out;
}

List<int> decodeDelta(Reader r) {
  r.uleb();
  r.uleb();
  final n = r.uleb(), first = r.zigzag();
  if (n == 0) return [];
  final out = [first];
  while (out.length < n) {
    final minimum = r.zigzag(), widths = r.take(4);
    for (var t = 0; t < 4 && out.length < n; t++) {
      final values = unpack(r, 32, widths[t]), count = min(32, n - out.length);
      for (final v in values.take(count)) {
        out.add(out.last + minimum + v);
      }
    }
  }
  return out;
}

String dictionaryKey(Value v, String kind) =>
    kind == 'STRING' ? v.text : '${v.number}';
List<int> encodeValues(
  List<Value> a,
  String kind,
  int method,
  List<Value> dictionary,
) {
  final out = <int>[];
  switch (method) {
    case 0:
      if (kind == 'BOOL') {
        final values = List.filled((a.length + 7) ~/ 8 * 8, 0);
        for (var i = 0; i < a.length; i++) {
          values[i] = a[i].number;
        }
        return pack(values, 1);
      }
      for (final v in a) {
        if (kind == 'STRING') {
          appendU32(out, v.text.length);
          out.addAll(v.text.codeUnits);
        } else {
          appendU32(out, v.number);
        }
      }
      break;
    case 1:
      final w = max(0, dictionary.length - 1).bitLength,
          indices = {
            for (var i = 0; i < dictionary.length; i++)
              dictionaryKey(dictionary[i], kind): i,
          };
      out.add(w);
      out.addAll(
        encodeHybrid([for (final v in a) indices[dictionaryKey(v, kind)]!], w),
      );
      break;
    case 2:
      final data = encodeHybrid([for (final v in a) v.number], 1);
      appendU32(out, data.length);
      out.addAll(data);
      break;
    case 3:
      out.addAll(encodeDelta([for (final v in a) v.number]));
      break;
    case 4:
      out.addAll(encodeDelta([for (final v in a) v.text.length]));
      for (final v in a) {
        out.addAll(v.text.codeUnits);
      }
      break;
  }
  return out;
}

List<Value> decodeValues(
  Reader r,
  int count,
  String kind,
  int method,
  List<Value> dictionary,
) {
  switch (method) {
    case 0:
      if (kind == 'BOOL')
        return [
          for (final n in unpack(r, (count + 7) ~/ 8 * 8, 1).take(count))
            Value(number: n),
        ];
      final out = <Value>[];
      for (var i = 0; i < count; i++) {
        if (kind == 'STRING') {
          out.add(Value(text: String.fromCharCodes(r.take(r.u32()))));
        } else {
          var n = r.u32();
          if (n >= 1 << 31) n -= 1 << 32;
          out.add(Value(number: n));
        }
      }
      return out;
    case 1:
      final w = r.byte();
      return [for (final index in decodeHybrid(r, count, w)) dictionary[index]];
    case 2:
      final reader = Reader(r.take(r.u32()));
      return [for (final v in decodeHybrid(reader, count, 1)) Value(number: v)];
    case 3:
      return [for (final v in decodeDelta(r)) Value(number: v)];
    default:
      return [
        for (final n in decodeDelta(r))
          Value(text: String.fromCharCodes(r.take(n))),
      ];
  }
}

void writeStatValue(List<int> out, Value v, String kind) {
  switch (kind) {
    case 'STRING':
      appendULEB(out, v.text.length);
      out.addAll(v.text.codeUnits);
      break;
    case 'BOOL':
      out.add(v.number);
      break;
    default:
      appendZigzag(out, v.number);
  }
}

Value readStatValue(Reader r, String kind) => switch (kind) {
  'STRING' => Value(text: String.fromCharCodes(r.take(r.uleb()))),
  'BOOL' => Value(number: r.byte()),
  _ => Value(number: r.zigzag()),
};
