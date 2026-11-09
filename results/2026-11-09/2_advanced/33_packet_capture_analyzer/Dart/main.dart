import 'dart:io';
import 'dart:math' as math;
part 'hexdump.dart';
part 'link_network.dart';
part 'transport.dart';
part 'dns_app.dart';
part 'flows.dart';

const fieldSpecs = <(String, String)>[
  ('frame.number', 'integer'),
  ('frame.time', 'integer'),
  ('frame.len', 'integer'),
  ('frame.protocols', 'string'),
  ('frame.malformed', 'string'),
  ('frame.bad_checksum', 'presence'),
  ('eth.dst', 'mac'),
  ('eth.src', 'mac'),
  ('eth.type', 'hex4'),
  ('arp.opcode', 'integer'),
  ('arp.src.hw', 'mac'),
  ('arp.src.ip', 'ipv4'),
  ('arp.dst.hw', 'mac'),
  ('arp.dst.ip', 'ipv4'),
  ('ip.hdr_len', 'integer'),
  ('ip.tos', 'hex2'),
  ('ip.len', 'integer'),
  ('ip.id', 'hex4'),
  ('ip.flags.df', 'integer'),
  ('ip.flags.mf', 'integer'),
  ('ip.frag_offset', 'integer'),
  ('ip.ttl', 'integer'),
  ('ip.proto', 'integer'),
  ('ip.checksum', 'hex4'),
  ('ip.checksum.status', 'string'),
  ('ip.src', 'ipv4'),
  ('ip.dst', 'ipv4'),
  ('ip.fragment', 'presence'),
  ('icmp.type', 'integer'),
  ('icmp.code', 'integer'),
  ('icmp.checksum', 'hex4'),
  ('icmp.checksum.status', 'string'),
  ('icmp.id', 'integer'),
  ('icmp.seq', 'integer'),
  ('udp.srcport', 'integer'),
  ('udp.dstport', 'integer'),
  ('udp.length', 'integer'),
  ('udp.checksum', 'hex4'),
  ('udp.checksum.status', 'string'),
  ('tcp.srcport', 'integer'),
  ('tcp.dstport', 'integer'),
  ('tcp.stream', 'integer'),
  ('tcp.seq', 'integer'),
  ('tcp.seq_raw', 'integer'),
  ('tcp.ack', 'integer'),
  ('tcp.ack_raw', 'integer'),
  ('tcp.hdr_len', 'integer'),
  ('tcp.flags', 'hex2'),
  ('tcp.flags.fin', 'integer'),
  ('tcp.flags.syn', 'integer'),
  ('tcp.flags.rst', 'integer'),
  ('tcp.flags.psh', 'integer'),
  ('tcp.flags.ack', 'integer'),
  ('tcp.flags.urg', 'integer'),
  ('tcp.window', 'integer'),
  ('tcp.window.calc', 'integer'),
  ('tcp.checksum', 'hex4'),
  ('tcp.checksum.status', 'string'),
  ('tcp.urgent', 'integer'),
  ('tcp.option', 'string'),
  ('tcp.options.mss', 'integer'),
  ('tcp.options.wscale', 'integer'),
  ('tcp.options.malformed', 'presence'),
  ('tcp.len', 'integer'),
  ('tcp.analysis.retransmission', 'presence'),
  ('tcp.analysis.out_of_order', 'presence'),
  ('tcp.analysis.lost_segment', 'presence'),
  ('tcp.analysis.duplicate_ack', 'presence'),
  ('dns.id', 'hex4'),
  ('dns.flags', 'hex4'),
  ('dns.flags.response', 'integer'),
  ('dns.flags.opcode', 'integer'),
  ('dns.flags.rcode', 'integer'),
  ('dns.count.queries', 'integer'),
  ('dns.count.answers', 'integer'),
  ('dns.count.auth_rr', 'integer'),
  ('dns.count.add_rr', 'integer'),
  ('dns.qry.name', 'string'),
  ('dns.qry.type', 'integer'),
  ('dns.answer', 'string'),
  ('dns.authority', 'string'),
  ('dns.additional', 'string'),
  ('dns.a', 'ipv4'),
  ('data.len', 'integer'),
];
const aliases = <String, (String, String, String)>{
  'eth.addr': ('mac', 'eth.dst', 'eth.src'),
  'ip.addr': ('ipv4', 'ip.src', 'ip.dst'),
  'udp.port': ('integer', 'udp.srcport', 'udp.dstport'),
  'tcp.port': ('integer', 'tcp.srcport', 'tcp.dstport'),
};
const protocolNames = ['eth', 'arp', 'ip', 'icmp', 'udp', 'tcp', 'dns', 'data'];
const protocolLabels = {
  'eth': 'ETH',
  'arp': 'ARP',
  'ip': 'IPv4',
  'icmp': 'ICMP',
  'udp': 'UDP',
  'tcp': 'TCP',
  'dns': 'DNS',
};
const checksumLayers = [
  ('ip', 'IPv4'),
  ('icmp', 'ICMP'),
  ('udp', 'UDP'),
  ('tcp', 'TCP'),
];
const flagNames = ['FIN', 'SYN', 'RST', 'PSH', 'ACK', 'URG', 'ECE', 'CWR'];
String fieldType(String name) {
  for (final spec in fieldSpecs) {
    if (spec.$1 == name) return spec.$2;
  }
  return aliases[name]?.$1 ?? (protocolNames.contains(name) ? 'presence' : '');
}

List<Object> fieldValues(Packet p, String name) {
  final alias = aliases[name];
  return alias == null
      ? p.values(name)
      : [...p.values(alias.$2), ...p.values(alias.$3)];
}

String seconds(int t) =>
    '${t ~/ 1000000}.${(t % 1000000).toString().padLeft(6, '0')}';
String optionalNumber(int? n) => n?.toString() ?? '-';
String notation(String kind, Object value) {
  if (kind == 'string') return value as String;
  final n = value as int;
  if (kind == 'hex2' || kind == 'hex4')
    return '0x${n.toRadixString(16).padLeft(kind == 'hex2' ? 2 : 4, '0')}';
  if (kind == 'ipv4') return ipv4Notation(n);
  if (kind == 'mac') return macNotation(n);
  return n.toString();
}

String shown(Packet p, String name) =>
    notation(fieldType(name), p.value(name)!);
String endpointText(Endpoint e) =>
    '${ipv4Notation(e.$1)}${e.$2 < 0 ? '' : ':${e.$2}'}';
Layer dissectOne(Packet p, String name, List<int> bytes) {
  switch (name) {
    case 'eth':
      return dissectEthernet(bytes);
    case 'arp':
      return dissectARP(bytes);
    case 'ip':
      return dissectIPv4(bytes);
    case 'icmp':
      return dissectICMP(bytes);
    case 'udp':
      return dissectUDP(
        bytes,
        p.numberValue('ip.src'),
        p.numberValue('ip.dst'),
      );
    case 'tcp':
      return dissectTCP(
        bytes,
        p.numberValue('ip.src'),
        p.numberValue('ip.dst'),
      );
    default:
      return dissectDNS(bytes);
  }
}

void dissect(Packet p, int base) {
  var reason = p.error;
  if (reason == null) {
    var name = 'eth', payload = p.data;
    while (true) {
      p.layers.add(name);
      Layer layer;
      try {
        layer = dissectOne(p, name, payload);
      } on Malformed catch (error) {
        reason = error.reason;
        break;
      }
      p.fields.addAll(layer.fields);
      if (layer.next == null) {
        p.remaining = layer.remaining;
        break;
      }
      name = layer.next!;
      payload = layer.payload;
    }
  }
  if (reason == null && p.remaining.isNotEmpty) {
    p.layers.add('data');
    p.set('data.len', p.remaining.length);
  }
  p.set('frame.number', p.number);
  p.set('frame.time', p.time - base);
  p.set('frame.len', p.length);
  if (p.layers.isNotEmpty) p.set('frame.protocols', p.layers.join(':'));
  if (reason != null) p.set('frame.malformed', reason);
  if (checksumLayers.any(
    (layer) => p.textValue('${layer.$1}.checksum.status') == 'bad',
  ))
    p.set('frame.bad_checksum', 1);
}

String flagNotation(int flags) {
  final names = <String>[];
  for (var bit = 0; bit < flagNames.length; bit++) {
    if (((flags >> bit) & 1) == 1) names.add(flagNames[bit]);
  }
  return names.isEmpty ? '<None>' : names.join(', ');
}

String optionSummary(List<Object> options) {
  var text = '';
  for (final option in options) {
    final words = (option as String).split(' ');
    switch (words[0]) {
      case 'MSS':
        text += ' MSS=${words[1]}';
      case 'WS':
        text += ' WS=${1 << int.parse(words[1])}';
      case 'SACK_PERM':
        text += ' SACK_PERM';
      case 'TS':
        text += ' TSval=${words[1]} TSecr=${words[2]}';
    }
  }
  return text;
}

String basicInfo(Packet p, String protocol, Map<int, (int, int)> duplicate) {
  if (p.exists('frame.malformed')) return p.textValue('frame.malformed');
  switch (protocol) {
    case 'ETH':
      return 'EtherType ${shown(p, 'eth.type')}';
    case 'ARP':
      switch (p.numberValue('arp.opcode')) {
        case 1:
          return 'Who has ${shown(p, 'arp.dst.ip')}? Tell ${shown(p, 'arp.src.ip')}';
        case 2:
          return '${shown(p, 'arp.src.ip')} is at ${shown(p, 'arp.src.hw')}';
        default:
          return 'Opcode ${p.numberValue('arp.opcode')}';
      }
    case 'IPv4':
      if (!p.exists('ip.fragment'))
        return 'Protocol ${p.numberValue('ip.proto')}';
      return 'Fragment id=${shown(p, 'ip.id')} off=${p.numberValue('ip.frag_offset')}${p.numberValue('ip.flags.mf') == 1 ? ' MF' : ''}';
    case 'ICMP':
      final type = p.numberValue('icmp.type'),
          echo =
              'id=${p.numberValue('icmp.id')} seq=${p.numberValue('icmp.seq')}';
      if (type == 8) return 'Echo request $echo';
      if (type == 0) return 'Echo reply $echo';
      return 'Type $type code ${p.numberValue('icmp.code')}';
    case 'UDP':
      return '${p.numberValue('udp.srcport')} -> ${p.numberValue('udp.dstport')} Len=${p.numberValue('udp.length') - 8}';
    case 'TCP':
      var mark = '';
      if (p.exists('tcp.analysis.duplicate_ack')) {
        final record = duplicate[p.number]!;
        mark = '[TCP Dup ACK ${record.$1}#${record.$2}] ';
      } else {
        const labels = [
          '[TCP Retransmission] ',
          '[TCP Out-Of-Order] ',
          '[TCP Previous segment not captured] ',
        ];
        for (var i = 0; i < 3; i++) {
          if (p.exists('tcp.analysis.${marks[i]}')) {
            mark = labels[i];
            break;
          }
        }
      }
      var text =
          '$mark${p.numberValue('tcp.srcport')} -> ${p.numberValue('tcp.dstport')} [${flagNotation(p.numberValue('tcp.flags'))}] Seq=${p.numberValue('tcp.seq')}';
      if (p.numberValue('tcp.flags.ack') == 1)
        text += ' Ack=${p.numberValue('tcp.ack')}';
      return '$text Win=${p.numberValue('tcp.window.calc')} Len=${p.numberValue('tcp.len')}${optionSummary(p.values('tcp.option'))}';
    default:
      final parts = [
        p.numberValue('dns.flags.response') == 1 ? 'Response' : 'Query',
        shown(p, 'dns.id'),
      ];
      final rcode = p.numberValue('dns.flags.rcode');
      if (rcode != 0) parts.add(rcodeName(rcode));
      final names = p.values('dns.qry.name'), types = p.values('dns.qry.type');
      for (var i = 0; i < names.length; i++) {
        parts.addAll([typeName(types[i] as int), names[i] as String]);
      }
      for (final record in p.values('dns.answer')) {
        final fields = (record as String).split(' ');
        parts.addAll([fields[1], fields.sublist(4).join(' ')]);
      }
      return parts.join(' ');
  }
}

String summaryLine(Packet p, Map<int, (int, int)> duplicate) {
  var source = '-', destination = '-';
  if (p.exists('ip.src')) {
    source = shown(p, 'ip.src');
    destination = shown(p, 'ip.dst');
  } else if (p.exists('eth.src')) {
    source = shown(p, 'eth.src');
    destination = shown(p, 'eth.dst');
  }
  var protocol = 'DUMP';
  for (final name in p.layers) {
    if (name != 'data') protocol = protocolLabels[name]!;
  }
  var info = basicInfo(p, protocol, duplicate);
  if (p.exists('tcp.options.malformed')) info += ' [bad TCP options]';
  for (final layer in checksumLayers) {
    if (p.textValue('${layer.$1}.checksum.status') == 'bad')
      info += ' [bad ${layer.$2} checksum]';
  }
  return '${p.number} ${seconds(p.numberValue('frame.time'))} $source -> $destination $protocol ${p.length} $info';
}

class FilterError implements Exception {
  final String message;
  FilterError(this.message);
}

Never filterFail(String message) => throw FilterError(message);

class Token {
  final String kind, text;
  final int column;
  Token(this.kind, this.text, this.column);
}

bool wordCharacter(String c) => RegExp(r'^[A-Za-z0-9._:]$').hasMatch(c);
List<Token> tokenize(String expression) {
  final tokens = <Token>[];
  var index = 0;
  while (index < expression.length) {
    final c = expression[index], column = index + 1;
    if (c == ' ') {
      index++;
      continue;
    }
    if (index + 1 < expression.length &&
        [
          '==',
          '!=',
          '<=',
          '>=',
          '&&',
          '||',
        ].contains(expression.substring(index, index + 2))) {
      final t = expression.substring(index, index + 2);
      tokens.add(Token(t, t, column));
      index += 2;
      continue;
    }
    if ('()!<>'.contains(c)) {
      tokens.add(Token(c, c, column));
      index++;
      continue;
    }
    if (c == '"') {
      final end = expression.indexOf('"', index + 1);
      if (end < 0) filterFail('unterminated string at column $column');
      tokens.add(Token('string', expression.substring(index, end + 1), column));
      index = end + 1;
      continue;
    }
    if (wordCharacter(c)) {
      var end = index;
      while (end < expression.length && wordCharacter(expression[end])) {
        end++;
      }
      final word = expression.substring(index, end),
          kind =
              {'and': '&&', 'or': '||', 'not': '!'}[expression.substring(
                index,
                end,
              )] ??
              'word';
      tokens.add(Token(kind, word, column));
      index = end;
      continue;
    }
    filterFail("invalid character '$c' at column $column");
  }
  return tokens;
}

Object? parseLiteral(String kind, Token token) {
  if (kind == 'string')
    return token.kind == 'string'
        ? token.text.substring(1, token.text.length - 1)
        : null;
  if (token.kind != 'word') return null;
  final text = token.text;
  if (['integer', 'hex2', 'hex4'].contains(kind)) {
    if (RegExp(r'^[0-9]{1,15}$').hasMatch(text)) return int.parse(text);
    if (RegExp(r'^0x[0-9a-fA-F]{1,12}$').hasMatch(text))
      return int.parse(text.substring(2), radix: 16);
    return null;
  }
  final mac = kind == 'mac', parts = text.split(kind == 'mac' ? ':' : '.');
  if (parts.length != (mac ? 6 : 4)) return null;
  var number = 0;
  for (final part in parts) {
    if (!(mac ? RegExp(r'^[0-9a-fA-F]{2}$') : RegExp(r'^[0-9]{1,3}$')).hasMatch(
      part,
    ))
      return null;
    final value = int.parse(part, radix: mac ? 16 : 10);
    if (value > 255) return null;
    number = number * 256 + value;
  }
  return number;
}

Never unexpected(Token token) =>
    filterFail("unexpected '${token.text}' at column ${token.column}");

class FilterNode {
  final String kind, field, operator;
  final Object? value;
  final FilterNode? left, right;
  FilterNode(
    this.kind, {
    this.field = '',
    this.operator = '',
    this.value,
    this.left,
    this.right,
  });
}

class FilterParser {
  final List<Token> tokens;
  int position = 0;
  FilterParser(this.tokens);
  String get next => position < tokens.length ? tokens[position].kind : '';
  Token take() {
    if (position == tokens.length) filterFail('unexpected end of filter');
    return tokens[position++];
  }

  FilterNode expression() {
    var node = product();
    while (next == '||') {
      take();
      node = FilterNode('or', left: node, right: product());
    }
    return node;
  }

  FilterNode product() {
    var node = negation();
    while (next == '&&') {
      take();
      node = FilterNode('and', left: node, right: negation());
    }
    return node;
  }

  FilterNode negation() {
    if (next == '!') {
      take();
      return FilterNode('not', left: negation());
    }
    final token = take();
    if (token.kind == '(') {
      final node = expression(), closing = take();
      if (closing.kind != ')') unexpected(closing);
      return node;
    }
    if (token.kind != 'word') unexpected(token);
    final name = token.text, kind = fieldType(token.text);
    if (kind.isEmpty) filterFail('unknown field $name');
    if (!['==', '!=', '<', '>', '<=', '>='].contains(next))
      return FilterNode('exists', field: name);
    final operator = take().kind;
    if (kind == 'presence' ||
        kind == 'string' && operator != '==' && operator != '!=')
      filterFail('operator $operator not allowed for $name');
    final literal = take();
    if (literal.kind != 'word' && literal.kind != 'string') unexpected(literal);
    final value = parseLiteral(kind, literal);
    if (value == null) filterFail('invalid value ${literal.text} for $name');
    return FilterNode('compare', field: name, operator: operator, value: value);
  }
}

bool evaluate(FilterNode node, Packet p) {
  switch (node.kind) {
    case 'or':
      return evaluate(node.left!, p) || evaluate(node.right!, p);
    case 'and':
      return evaluate(node.left!, p) && evaluate(node.right!, p);
    case 'not':
      return !evaluate(node.left!, p);
    case 'exists':
      return protocolNames.contains(node.field)
          ? p.layers.contains(node.field)
          : fieldValues(p, node.field).isNotEmpty;
  }
  final values = fieldValues(p, node.field);
  if (values.isEmpty) return false;
  if (node.operator == '!=')
    return values.every((value) => value != node.value);
  for (final value in values) {
    if (node.operator == '==' && value == node.value) return true;
    if (node.operator != '==') {
      final a = value as int, b = node.value as int;
      if (node.operator == '<' && a < b ||
          node.operator == '>' && a > b ||
          node.operator == '<=' && a <= b ||
          node.operator == '>=' && a >= b)
        return true;
    }
  }
  return false;
}

List<String> filterBlock(
  String expression,
  List<Packet> packets,
  List<String> summaries,
) {
  final lines = ['', 'filter $expression'];
  try {
    final parser = FilterParser(tokenize(expression)),
        node = parser.expression();
    if (parser.position < parser.tokens.length)
      unexpected(parser.tokens[parser.position]);
    var count = 0;
    for (final p in packets) {
      if (evaluate(node, p)) {
        lines.add(summaries[p.number - 1]);
        count++;
      }
    }
    lines.add('matched $count of ${packets.length}');
  } on FilterError catch (error) {
    lines.add('error: ${error.message}');
  }
  return lines;
}

List<String> detailLines(List<Packet> packets, int number) {
  if (number < 1 || number > packets.length)
    return ['packet $number not found'];
  final p = packets[number - 1], lines = ['packet $number'];
  for (final layer in ['frame', ...p.layers]) {
    lines.add(layer);
    for (final spec in fieldSpecs) {
      if (!spec.$1.startsWith('$layer.')) continue;
      for (final value in p.values(spec.$1)) {
        lines.add(
          '  ${spec.$1}${spec.$2 == 'presence' ? '' : ' = ${notation(spec.$2, value)}'}',
        );
      }
    }
    if (layer == 'data')
      lines.addAll(hexDumpLines(p.remaining).map((line) => '  $line'));
  }
  return lines;
}

List<String> protocolStats(List<Packet> packets) {
  final lines = [
    'packets ${packets.length}',
    'bytes ${packets.fold(0, (sum, p) => sum + p.length)}',
    'duration ${seconds(packets.last.time - packets.first.time)}',
    'hierarchy',
  ];
  for (final (name, indent) in [
    ('eth', 0),
    ('arp', 2),
    ('ip', 2),
    ('icmp', 4),
    ('udp', 4),
    ('dns', 6),
    ('tcp', 4),
  ]) {
    final members = packets.where((p) => p.layers.contains(name)).toList();
    lines.add(
      '${' ' * indent}$name ${members.length} ${members.fold(0, (sum, p) => sum + p.length)}',
    );
  }
  lines.add('checksums');
  for (final layer in checksumLayers) {
    final counts = <String, int>{};
    for (final p in packets) {
      final status = p.textValue('${layer.$1}.checksum.status');
      counts[status] = (counts[status] ?? 0) + 1;
    }
    lines.add(
      '${layer.$1} good ${counts['good'] ?? 0} bad ${counts['bad'] ?? 0}${layer.$1 == 'udp' ? ' none ${counts['none'] ?? 0}' : ''}',
    );
  }
  lines.add('malformed');
  final malformed = <String, int>{};
  for (final p in packets) {
    final name = p.error != null
        ? 'dump'
        : p.exists('frame.malformed')
        ? p.layers.last
        : '';
    if (name.isNotEmpty) malformed[name] = (malformed[name] ?? 0) + 1;
  }
  for (final name in [
    'dump',
    'eth',
    'arp',
    'ip',
    'icmp',
    'udp',
    'tcp',
    'dns',
  ]) {
    lines.add('$name ${malformed[name] ?? 0}');
  }
  lines.add('tcp analysis');
  for (final mark in marks) {
    lines.add(
      '$mark ${packets.where((p) => p.exists('tcp.analysis.$mark')).length}',
    );
  }
  final queries = <Packet>[],
      responses = <Packet>[],
      pending = <Packet>[],
      times = <int>[];
  for (final p in packets) {
    if (!p.exists('dns.id')) continue;
    if (p.numberValue('dns.flags.response') == 0) {
      queries.add(p);
      pending.add(p);
      continue;
    }
    responses.add(p);
    for (var i = 0; i < pending.length; i++) {
      final q = pending[i];
      if (q.numberValue('dns.id') == p.numberValue('dns.id') &&
          q.numberValue('ip.src') == p.numberValue('ip.dst') &&
          q.numberValue('udp.srcport') == p.numberValue('udp.dstport') &&
          q.numberValue('ip.dst') == p.numberValue('ip.src') &&
          q.numberValue('udp.dstport') == p.numberValue('udp.srcport')) {
        pending.removeAt(i);
        times.add(p.time - q.time);
        break;
      }
    }
  }
  lines.addAll([
    'dns',
    'queries ${queries.length}',
    'responses ${responses.length}',
    'transactions ${times.length}',
    'unanswered ${pending.length}',
  ]);
  lines.add(
    times.isEmpty
        ? 'response_time -'
        : 'response_time min ${seconds(times.reduce(math.min))} max ${seconds(times.reduce(math.max))}',
  );
  final rcodes = <int, int>{}, names = <String, int>{};
  for (final p in responses) {
    final code = p.numberValue('dns.flags.rcode');
    rcodes[code] = (rcodes[code] ?? 0) + 1;
  }
  for (var code = 0; code < 16; code++) {
    if (rcodes.containsKey(code))
      lines.add('rcode ${rcodeName(code)} ${rcodes[code]}');
  }
  lines.add('names');
  for (final q in queries) {
    for (final name in q.values('dns.qry.name')) {
      final text = name as String;
      names[text] = (names[text] ?? 0) + 1;
    }
  }
  final ordered = names.keys.toList()
    ..sort((a, b) {
      final order = names[b]!.compareTo(names[a]!);
      return order != 0 ? order : a.compareTo(b);
    });
  for (final name in ordered) {
    lines.add('$name ${names[name]}');
  }
  return lines;
}

List<String> conversationLines(List<Packet> packets) {
  final lines = [
    'type,endpoint_a,endpoint_b,packets,bytes,packets_a_to_b,bytes_a_to_b,packets_b_to_a,bytes_b_to_a,start,duration',
  ];
  const kinds = ['ipv4', 'tcp', 'udp'];
  for (final c in buildConversations(packets)) {
    lines.add(
      '${kinds[c.kind]},${endpointText(c.a)},${endpointText(c.b)},${c.packets},${c.bytes},${c.packetsAB},${c.bytesAB},${c.packetsBA},${c.bytesBA},${seconds(c.firstTime - packets.first.time)},${seconds(c.lastTime - c.firstTime)}',
    );
  }
  return lines;
}

List<String> endpointLines(List<Packet> packets) {
  return [
    'address,packets,bytes,tx_packets,tx_bytes,rx_packets,rx_bytes',
    for (final e in buildEndpoints(packets))
      '${ipv4Notation(e.address)},${e.packets},${e.bytes},${e.txPackets},${e.txBytes},${e.rxPackets},${e.rxBytes}',
  ];
}

String sideLine(Side side) =>
    '${side.name} packets ${side.packets} payload ${side.payload}${marks.map((mark) => ' $mark ${side.counts[mark] ?? 0}').join()}';
List<String> streamLines(Stream stream, List<Packet> packets) {
  final rtt = stream.syn != null && stream.handshakeAck != null
      ? seconds(
          packets[stream.handshakeAck! - 1].time -
              packets[stream.syn! - 1].time,
        )
      : '-';
  final client = stream.clientSide, server = stream.serverSide;
  return [
    'stream ${stream.number} ${endpointText(stream.client)} -> ${endpointText(stream.server)}',
    'packets ${stream.packets} bytes ${stream.bytes} start ${seconds(stream.start - packets.first.time)} duration ${seconds(stream.end - stream.start)}',
    'states ${stream.history.map((entry) => '${entry.$1} ${entry.$2}').join(', ')}',
    'handshake syn ${optionalNumber(stream.syn)} syn_ack ${optionalNumber(stream.synAck)} ack ${optionalNumber(stream.handshakeAck)} rtt $rtt',
    'options client mss ${optionalNumber(client.mss)} wscale ${optionalNumber(client.wscale)} server mss ${optionalNumber(server.mss)} wscale ${optionalNumber(server.wscale)}',
    sideLine(client),
    sideLine(server),
    for (final event in stream.events)
      'event ${event.$1} ${event.$2} ${event.$3} seq ${event.$4} len ${event.$5}',
  ];
}

List<String> joinedBlocks(List<List<String>> blocks) {
  final lines = <String>[];
  for (var i = 0; i < blocks.length; i++) {
    if (i > 0) lines.add('');
    lines.addAll(blocks[i]);
  }
  return lines;
}

void writeLines(String name, List<String> lines) => File(
  'output/$name',
).writeAsStringSync(lines.isEmpty ? '' : '${lines.join('\n')}\n');
void main() {
  final packets = readCapture(), base = packets.first.time;
  for (final p in packets) {
    dissect(p, base);
  }
  final tracker = StreamTracker();
  for (final p in packets) {
    if (p.exists('tcp.srcport')) tracker.track(p);
  }
  final summaries = packets
          .map((p) => summaryLine(p, tracker.duplicateAcks))
          .toList(),
      details = <List<String>>[];
  final summary = [...summaries];
  for (final request in readLines('input/filters.txt')) {
    if (request.startsWith('FILTER ')) {
      summary.addAll(filterBlock(request.substring(7), packets, summaries));
    } else if (request.startsWith('DETAIL ')) {
      details.add(detailLines(packets, int.parse(request.substring(7))));
    }
  }
  Directory('output').createSync(recursive: true);
  writeLines('summary.txt', summary);
  writeLines('details.txt', joinedBlocks(details));
  writeLines('conversations.csv', conversationLines(packets));
  writeLines('endpoints.csv', endpointLines(packets));
  writeLines('protocol_stats.txt', protocolStats(packets));
  writeLines(
    'tcp_streams.txt',
    joinedBlocks(
      tracker.streams.map((stream) => streamLines(stream, packets)).toList(),
    ),
  );
}
