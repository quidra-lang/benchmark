import 'dart:convert';
import 'dart:io';

class DnsFailure implements Exception {
  final String message;
  DnsFailure(this.message);
}

class DnsRecord {
  final String owner;
  final int ttl;
  final String type;
  List<String> data;
  int? address;
  List<int>? groups;
  int? preference;
  int? minimum;
  DnsRecord(
    this.owner,
    this.ttl,
    this.type,
    this.data, {
    this.address,
    this.groups,
    this.preference,
    this.minimum,
  });
  DnsRecord copy({String? owner, int? ttl}) => DnsRecord(
    owner ?? this.owner,
    ttl ?? this.ttl,
    type,
    data,
    address: address,
    groups: groups,
    preference: preference,
    minimum: minimum,
  );
}

class Zone {
  final String origin;
  final int server;
  final int line;
  final List<DnsRecord> records = [];
  Zone(this.origin, this.server, this.line);
}

class Reply {
  final String kind;
  final List<DnsRecord> answer;
  final List<DnsRecord> authority;
  final List<DnsRecord> additional;
  final String? cut;
  final String? reason;
  Reply(
    this.kind, {
    this.answer = const [],
    this.authority = const [],
    this.additional = const [],
    this.cut,
    this.reason,
  });
}

class CacheEntry {
  final String name;
  final String type;
  final String kind;
  final List<DnsRecord> records;
  final int expiry;
  CacheEntry(this.name, this.type, this.kind, this.records, this.expiry);
}

class Resolution {
  final String status;
  final List<DnsRecord> answer;
  Resolution(this.status, this.answer);
}

const types = ['A', 'NS', 'CNAME', 'SOA', 'PTR', 'MX', 'TXT', 'AAAA'];
const kinds = [
  'ANSWER',
  'CNAME',
  'REFERRAL',
  'NODATA',
  'NXDOMAIN',
  'LAME',
  'TIMEOUT',
];
final integerWord = RegExp(r'^(?:0|[1-9][0-9]{0,8})$');
T? find<T>(Iterable<T> items, bool Function(T) condition) {
  for (final item in items) {
    if (condition(item)) return item;
  }
  return null;
}

List<String> labels(String name) =>
    name == '.' ? [] : name.substring(0, name.length - 1).split('.');
bool below(String name, String ancestor) =>
    ancestor == '.' || name == ancestor || name.endsWith('.$ancestor');
List<String> ancestors(String name) {
  final parts = labels(name);
  return [
    ...List.generate(parts.length, (i) => '${parts.sublist(i).join('.')}.'),
    '.',
  ];
}

int nameOrder(String a, String b) {
  final left = labels(a).reversed.toList();
  final right = labels(b).reversed.toList();
  final length = left.length < right.length ? left.length : right.length;
  for (var i = 0; i < length; i++) {
    final comparison = left[i].compareTo(right[i]);
    if (comparison != 0) return comparison;
  }
  return left.length.compareTo(right.length);
}

String parseName(String word, {bool wildcard = false, String? origin}) {
  if (origin != null && word == '@') return origin;
  if (word == '.') return '.';
  final absolute = word.endsWith('.');
  final parts = (absolute ? word.substring(0, word.length - 1) : word).split(
    '.',
  );
  for (var i = 0; i < parts.length; i++) {
    if (!(wildcard && i == 0 && parts[i] == '*') &&
        !RegExp(r'^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$')
            .hasMatch(parts[i]))
      throw DnsFailure('bad name $word');
  }
  final name = '${parts.join('.').toLowerCase()}.';
  return origin != null && !absolute && origin != '.' ? name + origin : name;
}

int ipv4(String word) {
  final parts = word.split('.');
  if (parts.length != 4 ||
      parts.any(
        (part) =>
            !RegExp(r'^(?:0|[1-9][0-9]{0,2})$').hasMatch(part) ||
            int.parse(part) > 255,
      ))
    throw DnsFailure('bad address $word');
  return parts.fold<int>(0, (value, part) => value * 256 + int.parse(part));
}

String addressText(int value) =>
    [24, 16, 8, 0].map((shift) => (value >> shift) & 255).join('.');
List<int> ipv6(String word) {
  final halves = word.split('::');
  if (halves.length > 2) throw DnsFailure('bad address $word');
  final left = halves[0].isEmpty ? <String>[] : halves[0].split(':');
  final right = halves.length == 2 && halves[1].isNotEmpty
      ? halves[1].split(':')
      : <String>[];
  if ([
        ...left,
        ...right,
      ].any((group) => !RegExp(r'^[0-9A-Fa-f]{1,4}$').hasMatch(group)) ||
      (halves.length == 1 ? left.length != 8 : left.length + right.length > 7))
    throw DnsFailure('bad address $word');
  return [
    ...left.map((group) => int.parse(group, radix: 16)),
    ...List.filled(halves.length == 2 ? 8 - left.length - right.length : 0, 0),
    ...right.map((group) => int.parse(group, radix: 16)),
  ];
}

String ipv6Text(List<int> groups) {
  var best = -1;
  var length = 0;
  for (var start = 0; start < 8;) {
    if (groups[start] != 0) {
      start++;
      continue;
    }
    var end = start;
    while (end < 8 && groups[end] == 0) end++;
    if (end - start >= 2 && end - start > length) {
      best = start;
      length = end - start;
    }
    start = end;
  }
  final words = groups.map((group) => group.toRadixString(16)).toList();
  return best < 0
      ? words.join(':')
      : '${words.sublist(0, best).join(':')}::${words.sublist(best + length).join(':')}';
}

int ttl(String word) {
  var result = 0;
  if (integerWord.hasMatch(word)) {
    result = int.parse(word);
  } else {
    const units = 'wdhms';
    const seconds = [604800, 86400, 3600, 60, 1];
    var position = 0;
    var previous = -1;
    for (final match in RegExp(
      r'(0|[1-9][0-9]{0,2})([wdhms])',
      caseSensitive: false,
    ).allMatches(word)) {
      final unit = units.indexOf(match[2]!.toLowerCase());
      if (match.start != position || unit <= previous)
        throw DnsFailure('bad ttl $word');
      result += int.parse(match[1]!) * seconds[unit];
      previous = unit;
      position += match[0]!.length;
    }
    if (position != word.length || position == 0)
      throw DnsFailure('bad ttl $word');
  }
  if (result < 1 || result > 604800) throw DnsFailure('bad ttl $word');
  return result;
}

void checkType(String type) {
  if (!types.contains(type)) throw DnsFailure('bad type $type');
}

int dataOrder(DnsRecord a, DnsRecord b) {
  if (a.type == 'A') return a.address!.compareTo(b.address!);
  if (a.type == 'AAAA') {
    for (var i = 0; i < 8; i++) {
      if (a.groups![i] != b.groups![i])
        return a.groups![i].compareTo(b.groups![i]);
    }
    return 0;
  }
  if (['NS', 'CNAME', 'PTR'].contains(a.type))
    return nameOrder(a.data[0], b.data[0]);
  if (a.type == 'MX') {
    final preference = a.preference!.compareTo(b.preference!);
    return preference == 0 ? nameOrder(a.data[1], b.data[1]) : preference;
  }
  return a.data.join(' ').compareTo(b.data.join(' '));
}

int recordOrder(DnsRecord a, DnsRecord b) {
  final name = nameOrder(a.owner, b.owner);
  if (name != 0) return name;
  final type = types.indexOf(a.type).compareTo(types.indexOf(b.type));
  return type == 0 ? dataOrder(a, b) : type;
}

String recordText(DnsRecord record) =>
    '${record.owner} ${record.ttl} ${record.type} ${record.data.join(' ')}';
String replyText(Reply reply) => reply.kind == 'REFERRAL'
    ? 'REFERRAL ${reply.cut}'
    : reply.kind == 'CNAME'
    ? 'CNAME ${reply.answer[0].data[0]}'
    : reply.kind;
String cacheKey(String name, String type) => '$name $type';

class Resolver {
  final List<int> roots = [];
  List<Zone> zones = [];
  Zone? current;
  final Set<int> down = {};
  final Map<String, int> settings = {
    'MINTTL': 1,
    'MAXTTL': 86400,
    'NEGTTL': 3600,
  };
  int clock = 0;
  final Map<String, CacheEntry> cache = {};
  final Map<int, List<int>> queries = {};
  int hits = 0;
  final Map<String, int> resolutions = {
    'NOERROR': 0,
    'NODATA': 0,
    'NXDOMAIN': 0,
    'SERVFAIL': 0,
  };
  final List<String> output = [];

  void zoneLine(List<String> words, int line) {
    if (words[0] == 'ROOT') {
      final addresses = <int>[];
      for (final word in words.skip(1)) {
        final address = ipv4(word);
        if (roots.contains(address) || addresses.contains(address))
          throw DnsFailure('duplicate root $word');
        addresses.add(address);
      }
      roots.addAll(addresses);
      return;
    }
    if (words[0] == 'ZONE') {
      current = null;
      final origin = parseName(words[1]);
      final server = ipv4(words[2]);
      if (zones.any((zone) => zone.origin == origin && zone.server == server))
        throw DnsFailure('duplicate zone $origin at ${words[2]}');
      final zone = Zone(origin, server, line);
      current = zone;
      zones.add(zone);
      return;
    }
    final zone = current;
    if (zone == null) throw DnsFailure('no current zone');
    final owner = parseName(words[0], wildcard: true, origin: zone.origin);
    if (!below(owner, zone.origin)) throw DnsFailure('out of zone $owner');
    final seconds = ttl(words[1]);
    final type = words[2];
    checkType(type);
    final fields = words.sublist(3);
    final required = type == 'MX'
        ? 2
        : type == 'SOA'
        ? 7
        : 1;
    if (type != 'TXT' && fields.length != required)
      throw DnsFailure('wrong field count');
    final record = DnsRecord(owner, seconds, type, []);
    String name(String word) => parseName(word, origin: zone.origin);
    if (type == 'A') {
      record.address = ipv4(fields[0]);
      record.data = [addressText(record.address!)];
    } else if (type == 'AAAA') {
      record.groups = ipv6(fields[0]);
      record.data = [ipv6Text(record.groups!)];
    } else if (['NS', 'CNAME', 'PTR'].contains(type)) {
      record.data = [name(fields[0])];
    } else if (type == 'MX') {
      if (!integerWord.hasMatch(fields[0]) || int.parse(fields[0]) > 65535)
        throw DnsFailure('bad preference ${fields[0]}');
      record.preference = int.parse(fields[0]);
      record.data = ['${record.preference}', name(fields[1])];
    } else if (type == 'TXT') {
      final text = fields.join(' ');
      if (text.length < 2 ||
          !text.startsWith('"') ||
          !text.endsWith('"') ||
          text.substring(1, text.length - 1).contains('"'))
        throw DnsFailure('bad text $text');
      record.data = [text];
    } else {
      record.data = [name(fields[0]), name(fields[1])];
      for (final field in fields.sublist(2, 6)) {
        if (!integerWord.hasMatch(field)) throw DnsFailure('bad number $field');
        record.data.add(int.parse(field).toString());
      }
      if (!integerWord.hasMatch(fields[6]) ||
          int.parse(fields[6]) < 1 ||
          int.parse(fields[6]) > 86400)
        throw DnsFailure('bad minimum ${fields[6]}');
      record.minimum = int.parse(fields[6]);
      record.data.add('${record.minimum}');
    }
    if (type == 'NS' && owner.startsWith('*.'))
      throw DnsFailure('ns at wildcard');
    if (type == 'SOA' && owner != zone.origin)
      throw DnsFailure('soa not at origin');
    if (type == 'SOA' && zone.records.any((record) => record.type == 'SOA'))
      throw DnsFailure('duplicate soa');
    if (zone.records.any(
      (previous) =>
          previous.owner == owner &&
          previous.type == type &&
          jsonEncode(previous.data) == jsonEncode(record.data),
    ))
      throw DnsFailure('duplicate record');
    if (zone.records.any(
      (previous) =>
          previous.owner == owner &&
          (type == 'CNAME' || previous.type == 'CNAME'),
    ))
      throw DnsFailure('cname conflict $owner');
    zone.records.add(record);
  }

  void finishZones() {
    final valid = <Zone>[];
    for (final zone in zones) {
      if (!zone.records.any((record) => record.type == 'SOA')) {
        output.add(
          'error line ${zone.line}: zone ${zone.origin} at ${addressText(zone.server)} has no soa',
        );
      } else {
        valid.add(zone);
        output.add(
          'zone ${zone.origin} at ${addressText(zone.server)} records=${zone.records.length}',
        );
      }
    }
    zones = valid;
    output.add(
      'loaded roots=${roots.length} zones=${valid.length} records=${valid.fold<int>(0, (sum, zone) => sum + zone.records.length)}',
    );
  }

  Reply authoritative(int server, String name, String type, String cut) {
    if (down.contains(server) || !zones.any((zone) => zone.server == server))
      return Reply('TIMEOUT');
    final candidates =
        zones
            .where((zone) => zone.server == server && below(name, zone.origin))
            .toList()
          ..sort(
            (a, b) =>
                labels(b.origin).length.compareTo(labels(a.origin).length),
          );
    if (candidates.isEmpty ||
        labels(candidates[0].origin).length < labels(cut).length)
      return Reply('LAME');
    final zone = candidates[0];
    final soa = zone.records.firstWhere((record) => record.type == 'SOA');
    final delegation = find(
      ancestors(name).reversed,
      (ancestor) =>
          ancestor != zone.origin &&
          below(ancestor, zone.origin) &&
          zone.records.any(
            (record) => record.owner == ancestor && record.type == 'NS',
          ),
    );
    if (delegation != null) {
      final authority =
          zone.records
              .where(
                (record) => record.owner == delegation && record.type == 'NS',
              )
              .toList()
            ..sort(dataOrder);
      final additional = <DnsRecord>[];
      for (final record in authority) {
        additional.addAll(
          zone.records
              .where((glue) => glue.owner == record.data[0] && glue.type == 'A')
              .toList()
            ..sort(dataOrder),
        );
      }
      return Reply(
        'REFERRAL',
        authority: authority,
        additional: additional,
        cut: delegation,
      );
    }
    bool exists(String candidate) =>
        zone.records.any((record) => below(record.owner, candidate));
    var records = zone.records.where((record) => record.owner == name).toList();
    if (records.isEmpty) {
      if (exists(name)) return Reply('NODATA', authority: [soa]);
      final ancestor = ancestors(name).skip(1).firstWhere(exists);
      final wildcard = ancestor == '.' ? '*.' : '*.$ancestor';
      records = zone.records
          .where((record) => record.owner == wildcard)
          .toList();
      if (records.isEmpty) return Reply('NXDOMAIN', authority: [soa]);
    }
    final answers = records.where((record) => record.type == type).toList()
      ..sort(dataOrder);
    if (answers.isNotEmpty)
      return Reply(
        'ANSWER',
        answer: answers.map((record) => record.copy(owner: name)).toList(),
      );
    final cname = find(records, (record) => record.type == 'CNAME');
    if (type != 'CNAME' && cname != null)
      return Reply('CNAME', answer: [cname.copy(owner: name)]);
    return Reply('NODATA', authority: [soa]);
  }

  Reply ask(int server, String name, String type, String cut) {
    final response = authoritative(server, name, type, cut);
    final counts = queries.putIfAbsent(
      server,
      () => List.filled(kinds.length, 0),
    );
    counts[kinds.indexOf(response.kind)]++;
    return response;
  }

  List<DnsRecord> positive(List<DnsRecord> records) {
    var seconds = records
        .map((record) => record.ttl)
        .reduce((a, b) => a < b ? a : b);
    if (seconds < settings['MINTTL']!) seconds = settings['MINTTL']!;
    if (seconds > settings['MAXTTL']!) seconds = settings['MAXTTL']!;
    final ordered = records.toList()..sort(dataOrder);
    cache[cacheKey(records[0].owner, records[0].type)] = CacheEntry(
      records[0].owner,
      records[0].type,
      'POS',
      ordered,
      clock + seconds,
    );
    return records.map((record) => record.copy(ttl: seconds)).toList();
  }

  void trace(int depth, String text) {
    output.add(''.padLeft(2 * (depth + 1)) + text);
  }

  Reply? queryServers(
    String name,
    String type,
    String cut,
    List<String>? nameservers,
    int depth,
    List<String> stack,
  ) {
    Reply? query(int server) {
      final response = ask(server, name, type, cut);
      trace(
        depth,
        'ASK ${addressText(server)} $name $type -> ${replyText(response)}',
      );
      return response.kind == 'LAME' || response.kind == 'TIMEOUT'
          ? null
          : response;
    }

    if (nameservers == null) {
      for (final server in roots) {
        final response = query(server);
        if (response != null) return response;
      }
      return null;
    }
    final ordered = nameservers.toList()..sort(nameOrder);
    for (final host in ordered) {
      final cached = cache[cacheKey(host, 'A')];
      var addresses = <int>[];
      if (cached?.kind == 'POS') {
        addresses = cached!.records.map((record) => record.address!).toList();
      } else if (stack.contains(cacheKey(host, 'A'))) {
        trace(depth, 'GLUELESS $host -> LOOP');
      } else {
        trace(depth, 'GLUELESS $host');
        final resolution = resolve(host, 'A', depth: depth + 1, stack: stack);
        if (resolution.status == 'NOERROR')
          addresses = resolution.answer
              .where((record) => record.type == 'A')
              .map((record) => record.address!)
              .toList();
      }
      final unique = addresses.toSet().toList()..sort();
      for (final server in unique) {
        final response = query(server);
        if (response != null) return response;
      }
    }
    return null;
  }

  Reply lookup(String name, String type, int depth, List<String> stack) {
    Reply hit(Reply response, String text) {
      hits++;
      trace(depth, 'CACHE HIT $name $type -> $text');
      return response;
    }

    final exact = cache[cacheKey(name, type)];
    if (exact != null)
      return hit(
        exact.kind == 'POS'
            ? Reply(
                'ANSWER',
                answer: exact.records
                    .map((record) => record.copy(ttl: exact.expiry - clock))
                    .toList(),
              )
            : Reply(exact.kind),
        exact.kind == 'POS' ? 'ANSWER' : exact.kind,
      );
    if (cache.values.any(
      (entry) => entry.kind == 'NXDOMAIN' && below(name, entry.name),
    ))
      return hit(Reply('NXDOMAIN'), 'NXDOMAIN');
    final cname = cache[cacheKey(name, 'CNAME')];
    if (type != 'CNAME' && cname != null && cname.kind == 'POS')
      return hit(
        Reply(
          'CNAME',
          answer: cname.records
              .map((record) => record.copy(ttl: cname.expiry - clock))
              .toList(),
        ),
        'CNAME ${cname.records[0].data[0]}',
      );
    final ns = find(
      ancestors(name)
          .map((ancestor) => cache[cacheKey(ancestor, 'NS')])
          .whereType<CacheEntry>(),
      (entry) => entry.kind == 'POS',
    );
    var cut = ns?.name ?? '.';
    List<String>? nameservers = ns?.records
        .map((record) => record.data[0])
        .toList();
    if (ns != null) {
      hits++;
      trace(depth, 'CACHE HIT $name $type -> REFERRAL $cut');
    }
    while (true) {
      final response = queryServers(name, type, cut, nameservers, depth, stack);
      if (response == null)
        return Reply('SERVFAIL', reason: 'no server for $cut');
      if (response.kind == 'REFERRAL') {
        positive(response.authority);
        final groups = <String, List<DnsRecord>>{};
        for (final record in response.additional)
          groups.putIfAbsent(record.owner, () => []).add(record);
        for (final group in groups.values) positive(group);
        cut = response.cut!;
        nameservers = response.authority
            .map((record) => record.data[0])
            .toList();
      } else if (response.kind == 'ANSWER' || response.kind == 'CNAME') {
        return Reply(response.kind, answer: positive(response.answer));
      } else {
        final soa = response.authority[0];
        var seconds = soa.ttl;
        if (seconds > soa.minimum!) seconds = soa.minimum!;
        if (seconds > settings['NEGTTL']!) seconds = settings['NEGTTL']!;
        cache[cacheKey(name, type)] = CacheEntry(
          name,
          type,
          response.kind,
          [],
          clock + seconds,
        );
        return response;
      }
    }
  }

  Resolution resolve(
    String name,
    String type, {
    int depth = 0,
    List<String>? stack,
  }) {
    final pending = stack ?? <String>[];
    pending.add(cacheKey(name, type));
    final chain = <DnsRecord>[];
    final seen = {name};
    var current = name;
    var status = '';
    var answer = <DnsRecord>[];
    while (true) {
      final result = lookup(current, type, depth, pending);
      if (result.kind == 'CNAME') {
        final record = result.answer[0];
        chain.add(record);
        final target = record.data[0];
        if (seen.contains(target)) {
          status = 'SERVFAIL cname loop';
          break;
        }
        if (chain.length == 9) {
          status = 'SERVFAIL cname chain too long';
          break;
        }
        seen.add(target);
        current = target;
      } else {
        status = result.kind == 'ANSWER'
            ? 'NOERROR'
            : result.kind == 'SERVFAIL'
            ? 'SERVFAIL ${result.reason}'
            : result.kind;
        if (!status.startsWith('SERVFAIL'))
          answer = [...chain, if (result.kind == 'ANSWER') ...result.answer];
        break;
      }
    }
    pending.removeLast();
    final key = status.split(' ')[0];
    resolutions[key] = resolutions[key]! + 1;
    return Resolution(status, answer);
  }

  void emitResolution(Resolution result) {
    for (final record in result.answer)
      output.add('answer ${recordText(record)}');
    output.add('status ${result.status}');
  }

  String addresses(String host) {
    final a = resolve(host, 'A');
    final aaaa = resolve(host, 'AAAA');
    final addresses = [
      if (a.status == 'NOERROR')
        ...a.answer.where((record) => record.type == 'A'),
      if (aaaa.status == 'NOERROR')
        ...aaaa.answer.where((record) => record.type == 'AAAA'),
    ].map((record) => record.data[0]).toList();
    return addresses.isEmpty ? 'no address' : addresses.join(' ');
  }

  void command(List<String> words) {
    final command = words[0];
    if (command == 'RESOLVE' || command == 'MX') {
      final name = parseName(words[1], wildcard: true);
      final type = command == 'MX' ? 'MX' : words[2];
      checkType(type);
      output.add(command == 'MX' ? 'mx $name' : 'resolve $name $type');
      final result = resolve(name, type);
      emitResolution(result);
      if (command == 'MX') {
        if (result.status == 'NOERROR') {
          for (final record in result.answer.where(
            (record) => record.type == 'MX',
          )) {
            final host = record.data[1];
            output.add(
              host == '.'
                  ? 'exchange ${record.preference} . -> null'
                  : 'exchange ${record.preference} $host -> ${addresses(host)}',
            );
          }
        } else if (result.status == 'NODATA') {
          final aliases = result.answer
              .where((record) => record.type == 'CNAME')
              .toList();
          final host = aliases.isEmpty ? name : aliases.last.data[0];
          output.add('implicit $host -> ${addresses(host)}');
        }
      }
    } else if (command == 'REVERSE') {
      final String address;
      final String name;
      if (words[1].contains(':')) {
        final groups = ipv6(words[1]);
        address = ipv6Text(groups);
        name =
            '${groups.map((group) => group.toRadixString(16).padLeft(4, '0')).join().split('').reversed.join('.')}.ip6.arpa.';
      } else {
        address = addressText(ipv4(words[1]));
        name = '${address.split('.').reversed.join('.')}.in-addr.arpa.';
      }
      output.add('reverse $address $name');
      emitResolution(resolve(name, 'PTR'));
    } else if (command == 'QUERY' || command == 'DUMP') {
      final server = ipv4(words[1]);
      final name = parseName(words[2], wildcard: command == 'QUERY');
      if (command == 'QUERY') {
        checkType(words[3]);
        final result = ask(server, name, words[3], '.');
        output.add(
          'query ${addressText(server)} $name ${words[3]} -> ${replyText(result)}',
        );
        for (final record in result.answer)
          output.add('answer ${recordText(record)}');
        for (final record in result.authority)
          output.add('authority ${recordText(record)}');
        for (final record in result.additional)
          output.add('additional ${recordText(record)}');
      } else {
        final zone = find(
          zones,
          (zone) => zone.server == server && zone.origin == name,
        );
        if (down.contains(server) ||
            !zones.any((zone) => zone.server == server)) {
          output.add('dump ${addressText(server)} $name -> TIMEOUT');
        } else if (zone == null) {
          output.add('dump ${addressText(server)} $name -> REFUSED');
        } else {
          output.add(
            'dump ${addressText(server)} $name records=${zone.records.length}',
          );
          final records = zone.records.toList()..sort(recordOrder);
          for (final record in records) output.add('  ${recordText(record)}');
        }
      }
    } else if (command == 'DOWN' || command == 'UP') {
      final address = ipv4(words[1]);
      if (command == 'DOWN' && down.contains(address))
        throw DnsFailure('server ${words[1]} already down');
      if (command == 'UP' && !down.contains(address))
        throw DnsFailure('server ${words[1]} not down');
      if (command == 'DOWN') {
        down.add(address);
      } else {
        down.remove(address);
      }
      output.add('${command.toLowerCase()} ${addressText(address)}');
    } else if (command == 'SET') {
      if (!settings.containsKey(words[1]))
        throw DnsFailure('bad setting ${words[1]}');
      if (!integerWord.hasMatch(words[2]) ||
          int.parse(words[2]) < 1 ||
          int.parse(words[2]) > 604800)
        throw DnsFailure('bad value ${words[2]}');
      final value = int.parse(words[2]);
      final minimum = words[1] == 'MINTTL' ? value : settings['MINTTL']!;
      final maximum = words[1] == 'MAXTTL' ? value : settings['MAXTTL']!;
      if (minimum > maximum) throw DnsFailure('minttl above maxttl');
      settings[words[1]] = value;
      output.add('set ${words[1]}=$value');
    } else if (command == 'TIME') {
      if (!integerWord.hasMatch(words[1]) ||
          int.parse(words[1]) < 1 ||
          int.parse(words[1]) > 1000000)
        throw DnsFailure('bad time ${words[1]}');
      clock += int.parse(words[1]);
      final before = cache.length;
      cache.removeWhere((key, entry) => entry.expiry <= clock);
      output.add('time now=$clock expired=${before - cache.length}');
    } else if (command == 'CACHE' || command == 'FLUSH') {
      final name = words.length == 1 ? '.' : parseName(words[1]);
      final entries =
          cache.values.where((entry) => below(entry.name, name)).toList()
            ..sort((a, b) {
              final comparison = nameOrder(a.name, b.name);
              return comparison == 0
                  ? types.indexOf(a.type).compareTo(types.indexOf(b.type))
                  : comparison;
            });
      if (command == 'FLUSH') {
        for (final entry in entries)
          cache.remove(cacheKey(entry.name, entry.type));
        output.add('flush removed=${entries.length}');
      } else {
        output.add('cache entries=${entries.length}');
        for (final entry in entries) {
          if (entry.kind == 'POS') {
            for (final record in entry.records)
              output.add(
                '  ${recordText(record.copy(ttl: entry.expiry - clock))}',
              );
          } else {
            output.add(
              '  ${entry.name} ${entry.expiry - clock} ${entry.type} ${entry.kind}',
            );
          }
        }
      }
    } else {
      final count = queries.values.fold<int>(
        0,
        (total, counts) => total + counts.fold<int>(0, (a, b) => a + b),
      );
      output.add('stats queries=$count hits=$hits');
      final servers = queries.keys.toList()..sort();
      for (final server in servers) {
        final counts = queries[server]!;
        output.add(
          '  ${addressText(server)} sent=${counts.fold<int>(0, (a, b) => a + b)} ${List.generate(kinds.length, (i) => '${kinds[i].toLowerCase()}=${counts[i]}').join(' ')}',
        );
      }
      output.add(
        'resolutions noerror=${resolutions['NOERROR']} nodata=${resolutions['NODATA']} nxdomain=${resolutions['NXDOMAIN']} servfail=${resolutions['SERVFAIL']}',
      );
    }
  }

  void run(List<String> lines) {
    var position = 0;
    while (lines[position] != 'END ZONES') {
      try {
        zoneLine(lines[position].split(' '), position + 1);
      } on DnsFailure catch (error) {
        output.add('error line ${position + 1}: ${error.message}');
      }
      position++;
    }
    position++;
    finishZones();
    while (lines[position] != 'END') {
      try {
        command(lines[position].split(' '));
      } on DnsFailure catch (error) {
        output.add('error line ${position + 1}: ${error.message}');
      }
      position++;
    }
  }
}

Future<void> main() async {
  final resolver = Resolver();
  resolver.run((await stdin.transform(utf8.decoder).join()).split('\n'));
  stdout.write('${resolver.output.join('\n')}\n');
}
