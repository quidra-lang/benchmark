part of 'main.dart';

const dnsTypeNames = {
  1: 'A',
  2: 'NS',
  5: 'CNAME',
  6: 'SOA',
  12: 'PTR',
  15: 'MX',
  16: 'TXT',
  28: 'AAAA',
};
String typeName(int type) => dnsTypeNames[type] ?? 'TYPE$type';
String rcodeName(int code) {
  const names = [
    'NoError',
    'FormErr',
    'ServFail',
    'NXDomain',
    'NotImp',
    'Refused',
  ];
  return code < names.length ? names[code] : 'RCODE$code';
}

String className(int type) => type == 1 ? 'IN' : 'CLASS$type';
String labelText(List<int> bytes) => bytes
    .map(
      (byte) => byte >= 33 && byte <= 126 && byte != 46 && byte != 92
          ? String.fromCharCode(byte)
          : '\\${byte.toString().padLeft(3, '0')}',
    )
    .join();
String ipv6Notation(List<int> bytes) {
  final groups = [for (var i = 0; i < 16; i += 2) readInt(bytes, i, 2)],
      texts = [
        for (var i = 0; i < 16; i += 2) readInt(bytes, i, 2).toRadixString(16),
      ];
  var bestStart = -1, bestLength = 1;
  for (var i = 0; i < groups.length;) {
    if (groups[i] != 0) {
      i++;
      continue;
    }
    var end = i;
    while (end < groups.length && groups[end] == 0) {
      end++;
    }
    if (end - i > bestLength) {
      bestStart = i;
      bestLength = end - i;
    }
    i = end;
  }
  return bestStart < 0
      ? texts.join(':')
      : '${texts.take(bestStart).join(':')}::${texts.skip(bestStart + bestLength).join(':')}';
}

class DNSReader {
  final List<int> message;
  DNSReader(this.message);
  List<int> chunk(int position, int size) {
    if (position + size > message.length) throw Malformed('dns: truncated');
    return message.sublist(position, position + size);
  }

  int integer(int position, int size) =>
      readInt(chunk(position, size), 0, size);
  (String, int) name(int position) {
    final labels = <String>[];
    var pointers = 0;
    int? after;
    while (true) {
      final length = integer(position, 1);
      if (length == 0) {
        after ??= position + 1;
        break;
      }
      if (length >= 192) {
        final low = integer(position + 1, 1);
        after ??= position + 2;
        pointers++;
        if (pointers > 16) throw Malformed('dns: compression loop');
        final target = (length - 192) * 256 + low;
        if (target >= message.length)
          throw Malformed('dns: pointer out of range');
        position = target;
      } else if (length >= 64) {
        throw Malformed('dns: bad label type');
      } else {
        labels.add(labelText(chunk(position + 1, length)));
        position += length + 1;
      }
    }
    return (labels.isEmpty ? '<root>' : labels.join('.'), after!);
  }

  (String, int) rdata(int type, int start, int length) {
    switch (type) {
      case 1:
        return (ipv4Notation(integer(start, 4)), start + 4);
      case 28:
        return (ipv6Notation(chunk(start, 16)), start + 16);
      case 2 || 5 || 12:
        return name(start);
      case 15:
        final preference = integer(start, 2);
        final (exchange, end) = name(start + 2);
        return ('$preference $exchange', end);
      case 6:
        final (primary, first) = name(start);
        final (mailbox, second) = name(first);
        final parts = [primary, mailbox];
        var position = second;
        for (var i = 0; i < 5; i++) {
          parts.add('${integer(position, 4)}');
          position += 4;
        }
        return (parts.join(' '), position);
      default:
        return ('$length bytes', start + length);
    }
  }

  int record(int position, String section, Layer layer) {
    final (recordName, pos) = name(position);
    final fixed = chunk(pos, 10),
        type = integer(pos, 2),
        recordClass = integer(pos + 2, 2),
        ttl = integer(pos + 4, 4),
        length = integer(pos + 8, 2),
        start = pos + 10;
    chunk(start, length);
    final (data, end) = rdata(type, start, length);
    if (end != start + length) throw Malformed('dns: bad rdata length');
    layer.add(
      section,
      '$recordName ${typeName(type)} ${className(recordClass)} $ttl $data',
    );
    if (section == 'dns.answer' && type == 1)
      layer.add('dns.a', readInt(message, start, 4));
    return start + length;
  }
}

Layer dissectDNS(List<int> message) {
  final reader = DNSReader(message), layer = Layer();
  final header = reader.chunk(0, 12),
      flags = reader.integer(2, 2),
      counts = [for (var i = 4; i < 12; i += 2) reader.integer(i, 2)];
  layer.set('dns.id', readInt(header, 0, 2));
  layer.set('dns.flags', flags);
  layer.set('dns.flags.response', flags ~/ 32768 % 2);
  layer.set('dns.flags.opcode', flags ~/ 2048 % 16);
  layer.set('dns.flags.rcode', flags % 16);
  final names = [
    'dns.count.queries',
    'dns.count.answers',
    'dns.count.auth_rr',
    'dns.count.add_rr',
  ];
  for (var i = 0; i < counts.length; i++) {
    layer.set(names[i], counts[i]);
  }
  var position = 12;
  for (var i = 0; i < counts[0]; i++) {
    final (name, end) = reader.name(position);
    final tail = reader.chunk(end, 4);
    layer.add('dns.qry.name', name);
    layer.add('dns.qry.type', readInt(tail, 0, 2));
    position = end + 4;
  }
  final sections = ['dns.answer', 'dns.authority', 'dns.additional'];
  for (var i = 0; i < sections.length; i++) {
    for (var j = 0; j < counts[i + 1]; j++) {
      position = reader.record(position, sections[i], layer);
    }
  }
  return layer;
}
