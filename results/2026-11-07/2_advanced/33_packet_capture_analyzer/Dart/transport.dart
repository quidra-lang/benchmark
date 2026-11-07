part of 'main.dart';

List<int> pseudoHeader(int source, int destination, int protocol, int length) {
  final result = List.filled(12, 0);
  for (var i = 3; i >= 0; i--) {
    result[i] = source % 256;
    result[i + 4] = destination % 256;
    source ~/= 256;
    destination ~/= 256;
  }
  result[9] = protocol;
  result[10] = length ~/ 256;
  result[11] = length % 256;
  return result;
}

Layer dissectICMP(List<int> data) {
  if (data.length < 8) throw Malformed('icmp: truncated');
  final layer = Layer(), type = data[0];
  layer.set('icmp.type', type);
  layer.set('icmp.code', data[1]);
  layer.set('icmp.checksum', readInt(data, 2, 2));
  layer.set('icmp.checksum.status', checksumStatus(data));
  if (type == 0 || type == 8) {
    layer.set('icmp.id', readInt(data, 4, 2));
    layer.set('icmp.seq', readInt(data, 6, 2));
  }
  layer.remaining = data.sublist(8);
  return layer;
}

Layer dissectUDP(List<int> data, int source, int destination) {
  if (data.length < 8) throw Malformed('udp: truncated');
  final length = readInt(data, 4, 2);
  if (length < 8 || length > data.length)
    throw Malformed('udp: bad length $length');
  final src = readInt(data, 0, 2),
      dst = readInt(data, 2, 2),
      checksum = readInt(data, 6, 2),
      layer = Layer();
  final status = checksum == 0
      ? 'none'
      : checksumStatus([
          ...pseudoHeader(source, destination, 17, length),
          ...data.take(length),
        ]);
  layer.set('udp.srcport', src);
  layer.set('udp.dstport', dst);
  layer.set('udp.length', length);
  layer.set('udp.checksum', checksum);
  layer.set('udp.checksum.status', status);
  if (src == 53 || dst == 53) {
    layer.next = 'dns';
    layer.payload = data.sublist(8, length);
  } else {
    layer.remaining = data.sublist(8, length);
  }
  return layer;
}

void parseOptions(List<int> options, Layer layer) {
  final lengths = {
    2: [4],
    3: [3],
    4: [2],
    5: [10, 18, 26, 34],
    8: [10],
  };
  for (var i = 0; i < options.length;) {
    final kind = options[i];
    if (kind == 0) {
      layer.add('tcp.option', 'EOL');
      return;
    }
    if (kind == 1) {
      layer.add('tcp.option', 'NOP');
      i++;
      continue;
    }
    final length = i + 1 < options.length ? options[i + 1] : 0;
    if (length < 2 ||
        i + length > options.length ||
        lengths.containsKey(kind) && !lengths[kind]!.contains(length)) {
      layer.set('tcp.options.malformed', true);
      return;
    }
    final body = options.sublist(i + 2, i + length);
    String text;
    switch (kind) {
      case 2:
        final mss = readInt(body, 0, 2);
        layer.set('tcp.options.mss', mss);
        text = 'MSS $mss';
      case 3:
        layer.set('tcp.options.wscale', body[0]);
        text = 'WS ${body[0]}';
      case 4:
        text = 'SACK_PERM';
      case 5:
        text = [
          'SACK',
          for (var start = 0; start < body.length; start += 8)
            '${readInt(body, start, 4)}-${readInt(body, start + 4, 4)}',
        ].join(' ');
      case 8:
        text = 'TS ${readInt(body, 0, 4)} ${readInt(body, 4, 4)}';
      default:
        text = 'kind $kind len $length';
    }
    layer.add('tcp.option', text);
    i += length;
  }
}

Layer dissectTCP(List<int> data, int source, int destination) {
  if (data.length < 20) throw Malformed('tcp: truncated header');
  final h = data[12] ~/ 16 * 4;
  if (h < 20) throw Malformed('tcp: bad header length $h');
  if (h > data.length) throw Malformed('tcp: truncated header');
  final layer = Layer(), flags = data[13];
  layer.set('tcp.srcport', readInt(data, 0, 2));
  layer.set('tcp.dstport', readInt(data, 2, 2));
  layer.set('tcp.seq_raw', readInt(data, 4, 4));
  layer.set('tcp.hdr_len', h);
  layer.set('tcp.flags', flags);
  final names = ['fin', 'syn', 'rst', 'psh', 'ack', 'urg'];
  for (var bit = 0; bit < names.length; bit++) {
    layer.set('tcp.flags.${names[bit]}', flags >> bit & 1);
  }
  layer.set('tcp.window', readInt(data, 14, 2));
  layer.set('tcp.checksum', readInt(data, 16, 2));
  layer.set(
    'tcp.checksum.status',
    checksumStatus([
      ...pseudoHeader(source, destination, 6, data.length),
      ...data,
    ]),
  );
  layer.set('tcp.urgent', readInt(data, 18, 2));
  layer.set('tcp.len', data.length - h);
  if ((flags & 16) != 0) layer.set('tcp.ack_raw', readInt(data, 8, 4));
  parseOptions(data.sublist(20, h), layer);
  layer.remaining = data.sublist(h);
  return layer;
}
