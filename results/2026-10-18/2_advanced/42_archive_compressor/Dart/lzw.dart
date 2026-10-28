part of 'main.dart';

class LZWStats {
  int codes = 0, clears = 0, longest = 0;
  final widths = List.filled(4, 0);
}

Map<String, int> initialLZWDictionary() => {
  for (var k = 0; k < 256; k++) String.fromCharCode(k): k,
};
(List<int>, LZWStats) encodeLZW(List<int> data) {
  final writer = BitWriter(), stats = LZWStats();
  var dictionary = initialLZWDictionary(), next = 258, since = 0;
  void emit(int code, [int length = 0]) {
    final width = math.min(12, (258 + since).bitLength);
    writer.write(code, width);
    stats.codes++;
    stats.widths[width - 9]++;
    stats.longest = math.max(stats.longest, length);
    if (code == 256) {
      stats.clears++;
      since = 0;
    } else {
      since++;
    }
  }

  emit(256);
  var sequence = '';
  for (final x in data) {
    final single = String.fromCharCode(x), extended = sequence + single;
    if (dictionary.containsKey(extended)) {
      sequence = extended;
      continue;
    }
    emit(dictionary[sequence]!, sequence.length);
    dictionary[extended] = next;
    next++;
    if (next == 4096) {
      emit(256);
      dictionary = initialLZWDictionary();
      next = 258;
    }
    sequence = single;
  }
  if (sequence.isNotEmpty) emit(dictionary[sequence]!, sequence.length);
  emit(257);
  return (writer.finish(), stats);
}

List<int> decodeLZW(List<int> payload, int n) {
  final reader = BitReader(payload), out = <int>[];
  var dictionary = <List<int>>[];
  void reset() {
    dictionary = [
      for (var k = 0; k < 256; k++) [k],
      [],
      [],
    ];
  }

  reset();
  var previous = -1, since = 0;
  while (true) {
    final count = since,
        width = math.min(12, (258 + count).bitLength),
        code = reader.read(width, out.length);
    if (code == 256) {
      reset();
      previous = -1;
      since = 0;
      continue;
    }
    since++;
    if (code == 257) {
      if (out.length < n) throw DecodeError('early_end', out.length);
      return out;
    }
    if (count == 3838) throw DecodeError('bad_code', out.length);
    List<int> sequence;
    if (previous < 0) {
      if (code >= 256) throw DecodeError('bad_code', out.length);
      sequence = dictionary[code];
    } else if (code < dictionary.length) {
      sequence = dictionary[code];
    } else if (code == dictionary.length) {
      sequence = [...dictionary[previous], dictionary[previous].first];
    } else {
      throw DecodeError('bad_code', out.length);
    }
    if (out.length + sequence.length > n)
      throw DecodeError('overrun', out.length);
    out.addAll(sequence);
    if (previous >= 0)
      dictionary.add([...dictionary[previous], sequence.first]);
    previous = code;
  }
}
