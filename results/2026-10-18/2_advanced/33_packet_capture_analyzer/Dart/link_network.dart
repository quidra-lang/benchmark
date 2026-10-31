part of 'main.dart';

class Malformed implements Exception {
  final String reason;
  Malformed(this.reason);
}

class Layer {
  final fields = <String, List<Object>>{};
  String? next;
  List<int> payload = [], remaining = [];
  void set(String name, Object value) {
    fields[name] = [value];
  }

  void add(String name, Object value) {
    fields.putIfAbsent(name, () => []).add(value);
  }
}

int readInt(List<int> data, int index, int size) {
  var value = 0;
  for (final byte in data.sublist(index, index + size)) {
    value = value * 256 + byte;
  }
  return value;
}

String checksumStatus(List<int> data) {
  var total = 0;
  for (var i = 0; i < data.length; i += 2) {
    total += data[i] * 256 + (i + 1 < data.length ? data[i + 1] : 0);
  }
  while (total > 65535) {
    total = total % 65536 + total ~/ 65536;
  }
  return total == 65535 ? 'good' : 'bad';
}

String macNotation(int value) {
  final fields = List.filled(6, '');
  for (var i = 5; i >= 0; i--) {
    fields[i] = (value % 256).toRadixString(16).padLeft(2, '0');
    value ~/= 256;
  }
  return fields.join(':');
}

String ipv4Notation(int value) {
  final fields = List.filled(4, '');
  for (var i = 3; i >= 0; i--) {
    fields[i] = '${value % 256}';
    value ~/= 256;
  }
  return fields.join('.');
}

Layer dissectEthernet(List<int> data) {
  if (data.length < 14) throw Malformed('eth: truncated');
  final layer = Layer(), type = readInt(data, 12, 2);
  layer.set('eth.dst', readInt(data, 0, 6));
  layer.set('eth.src', readInt(data, 6, 6));
  layer.set('eth.type', type);
  layer.next = type == 2054
      ? 'arp'
      : type == 2048
      ? 'ip'
      : null;
  if (layer.next != null) {
    layer.payload = data.sublist(14);
  } else {
    layer.remaining = data.sublist(14);
  }
  return layer;
}

Layer dissectARP(List<int> data) {
  if (data.length < 28) throw Malformed('arp: truncated');
  if (readInt(data, 0, 2) != 1 ||
      readInt(data, 2, 2) != 2048 ||
      data[4] != 6 ||
      data[5] != 4)
    throw Malformed('arp: unsupported format');
  return Layer()
    ..set('arp.opcode', readInt(data, 6, 2))
    ..set('arp.src.hw', readInt(data, 8, 6))
    ..set('arp.src.ip', readInt(data, 14, 4))
    ..set('arp.dst.hw', readInt(data, 18, 6))
    ..set('arp.dst.ip', readInt(data, 24, 4));
}

Layer dissectIPv4(List<int> data) {
  if (data.length < 20) throw Malformed('ip: truncated header');
  final version = data[0] ~/ 16;
  if (version != 4) throw Malformed('ip: bad version $version');
  final h = data[0] % 16 * 4;
  if (h < 20) throw Malformed('ip: bad header length $h');
  if (data.length < h) throw Malformed('ip: truncated header');
  final length = readInt(data, 2, 2);
  if (length < h) throw Malformed('ip: bad total length $length');
  if (length > data.length)
    throw Malformed(
      'ip: truncated (total length $length, available ${data.length})',
    );
  final flags = readInt(data, 6, 2),
      mf = readInt(data, 6, 2) ~/ 8192 % 2,
      offset = readInt(data, 6, 2) % 8192 * 8,
      layer = Layer();
  layer.set('ip.hdr_len', h);
  layer.set('ip.tos', data[1]);
  layer.set('ip.len', length);
  layer.set('ip.id', readInt(data, 4, 2));
  layer.set('ip.flags.df', flags ~/ 16384 % 2);
  layer.set('ip.flags.mf', mf);
  layer.set('ip.frag_offset', offset);
  layer.set('ip.ttl', data[8]);
  layer.set('ip.proto', data[9]);
  layer.set('ip.checksum', readInt(data, 10, 2));
  layer.set('ip.checksum.status', checksumStatus(data.sublist(0, h)));
  layer.set('ip.src', readInt(data, 12, 4));
  layer.set('ip.dst', readInt(data, 16, 4));
  final payload = data.sublist(h, length);
  if (mf == 1 || offset != 0) {
    layer.set('ip.fragment', true);
    layer.remaining = payload;
  } else {
    layer.next = {1: 'icmp', 17: 'udp', 6: 'tcp'}[data[9]];
    if (layer.next == null) {
      layer.remaining = payload;
    } else {
      layer.payload = payload;
    }
  }
  return layer;
}
