part of 'main.dart';

class Packet {
  final int number, time, length;
  List<int> data = [], remaining = [];
  String? error;
  final layers = <String>[], fields = <String, List<Object>>{};
  Packet(this.number, this.time, this.length);
  List<Object> values(String name) => fields[name] ?? [];
  Object? value(String name) => fields[name]?.first;
  int numberValue(String name) => value(name) as int? ?? 0;
  String textValue(String name) => value(name) as String? ?? '';
  bool exists(String name) => fields.containsKey(name);
  void set(String name, Object value) {
    fields[name] = [value];
  }
}

List<String> readLines(String path) => File(path).readAsLinesSync();
List<Packet> readCapture() {
  final packets = <Packet>[],
      dumps = <List<(int, String)>>[],
      pattern = RegExp(r'^[0-9a-f]{4}  [0-9a-f]{2}( [0-9a-f]{2}){0,15}$');
  final lines = readLines('input/capture.txt');
  for (var i = 0; i < lines.length; i++) {
    final text = lines[i];
    if (text.startsWith('PACKET ')) {
      final fields = text.split(' ');
      packets.add(
        Packet(
          int.parse(fields[1]),
          int.parse(fields[2]),
          int.parse(fields[3]),
        ),
      );
      dumps.add([]);
    } else if (text.isNotEmpty) {
      dumps.last.add((i + 1, text));
    }
  }
  for (var i = 0; i < packets.length; i++) {
    final packet = packets[i], data = <int>[];
    for (final (number, text) in dumps[i]) {
      if (!pattern.hasMatch(text)) {
        packet.error = 'dump: bad line $number';
        break;
      }
      if (int.parse(text.substring(0, 4), radix: 16) != data.length) {
        packet.error = 'dump: offset mismatch at line $number';
        break;
      }
      data.addAll(
        text.substring(6).split(' ').map((byte) => int.parse(byte, radix: 16)),
      );
    }
    if (packet.error == null) {
      if (data.length != packet.length) {
        packet.error =
            'dump: length mismatch (header ${packet.length}, data ${data.length})';
      } else {
        packet.data = data;
      }
    }
  }
  return packets;
}

List<String> hexDumpLines(List<int> data) {
  final lines = <String>[];
  for (var offset = 0; offset < data.length; offset += 16) {
    final piece = data.sublist(offset, math.min(offset + 16, data.length));
    final hexPart = piece
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join(' ')
            .padRight(47),
        text = piece
            .map(
              (byte) =>
                  byte >= 32 && byte <= 126 ? String.fromCharCode(byte) : '.',
            )
            .join();
    lines.add('${offset.toRadixString(16).padLeft(4, '0')}  $hexPart  |$text|');
  }
  return lines;
}
