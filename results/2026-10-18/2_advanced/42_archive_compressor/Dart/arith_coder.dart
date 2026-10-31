part of 'main.dart';

class ArithStats {
  final int bits, contexts, rescales;
  ArithStats(this.bits, this.contexts, this.rescales);
}

class FrequencyTable {
  List<int> frequencies = List.filled(257, 1);
  int total = 257, rescales = 0;
  (int, int) interval(int symbol) {
    var sum = 0;
    for (var i = 0; i < symbol; i++) {
      sum += frequencies[i];
    }
    return (sum, frequencies[symbol]);
  }

  (int, int, int) locate(int value) {
    var sum = 0;
    for (var s = 0; s < frequencies.length; s++) {
      final f = frequencies[s];
      if (value < sum + f) return (s, sum, f);
      sum += f;
    }
    throw StateError('arithmetic interval outside model');
  }

  void update(int symbol) {
    frequencies[symbol] += 32;
    total += 32;
    if (total >= 8192) {
      frequencies = [for (final f in frequencies) (f + 1) ~/ 2];
      total = frequencies.fold(0, (a, b) => a + b);
      rescales++;
    }
  }
}

class ArithmeticModel {
  final tables = <int, FrequencyTable>{};
  FrequencyTable table(int context) =>
      tables.putIfAbsent(context, FrequencyTable.new);
}

(List<int>, ArithStats) encodeArith(List<int> data) {
  final writer = BitWriter(), model = ArithmeticModel();
  var low = 0, high = 65535, follow = 0, context = 10;
  void emit(int bit) {
    writer.write(bit, 1);
    for (var j = 0; j < follow; j++) {
      writer.write(1 - bit, 1);
    }
    follow = 0;
  }

  for (var i = 0; i <= data.length; i++) {
    final symbol = i < data.length ? data[i] : 256,
        table = model.table(context);
    final (cum, freq) = table.interval(symbol);
    final span = high - low + 1;
    high = low + span * (cum + freq) ~/ table.total - 1;
    low += span * cum ~/ table.total;
    while (true) {
      if (high < 32768) {
        emit(0);
      } else if (low >= 32768) {
        emit(1);
        low -= 32768;
        high -= 32768;
      } else if (low >= 16384 && high < 49152) {
        follow++;
        low -= 16384;
        high -= 16384;
      } else {
        break;
      }
      low *= 2;
      high = 2 * high + 1;
    }
    if (symbol != 256) {
      table.update(symbol);
      context = symbol;
    }
  }
  follow++;
  emit(low < 16384 ? 0 : 1);
  final rescales = model.tables.values.fold(0, (sum, t) => sum + t.rescales);
  return (
    writer.finish(),
    ArithStats(writer.count, model.tables.length, rescales),
  );
}

List<int> decodeArith(List<int> payload, int n) {
  final reader = BitReader(payload, zeroFill: true),
      model = ArithmeticModel(),
      out = <int>[];
  var low = 0, high = 65535, context = 10, value = reader.read(16);
  while (true) {
    final table = model.table(context),
        span = high - low + 1,
        q = ((value - low + 1) * table.total - 1) ~/ span;
    final (symbol, cum, freq) = table.locate(q);
    high = low + span * (cum + freq) ~/ table.total - 1;
    low += span * cum ~/ table.total;
    while (true) {
      if (high < 32768) {
      } else if (low >= 32768) {
        low -= 32768;
        high -= 32768;
        value -= 32768;
      } else if (low >= 16384 && high < 49152) {
        low -= 16384;
        high -= 16384;
        value -= 16384;
      } else {
        break;
      }
      low *= 2;
      high = 2 * high + 1;
      value = 2 * value + reader.read(1);
    }
    if (symbol == 256) {
      if (out.length < n) throw DecodeError('early_end', out.length);
      return out;
    }
    if (out.length == n) throw DecodeError('overrun', out.length);
    out.add(symbol);
    table.update(symbol);
    context = symbol;
  }
}
