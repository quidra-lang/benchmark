part of 'main.dart';

class DecodeError implements Exception {
  final String kind;
  final int position;
  DecodeError(this.kind, this.position);
  @override
  String toString() => '$kind at $position';
}

class BitWriter {
  final data = <int>[];
  int partial = 0, used = 0, count = 0;
  void write(int value, int width) {
    for (var shift = width - 1; shift >= 0; shift--) {
      partial = (partial << 1) | ((value >> shift) & 1);
      used++;
      if (used == 8) {
        data.add(partial);
        partial = 0;
        used = 0;
      }
    }
    count += width;
  }

  List<int> finish() => [...data, if (used > 0) partial << (8 - used)];
}

class BitReader {
  final List<int> payload;
  final bool zeroFill;
  int position = 0;
  BitReader(this.payload, {this.zeroFill = false});
  int read(int width, [int outputPosition = 0]) {
    if (!zeroFill && position + width > 8 * payload.length)
      throw DecodeError('end_of_data', outputPosition);
    var value = 0;
    for (var i = 0; i < width; i++) {
      value <<= 1;
      if (position < 8 * payload.length)
        value |= (payload[position ~/ 8] >> (7 - position % 8)) & 1;
      position++;
    }
    return value;
  }
}
