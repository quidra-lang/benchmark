import 'dart:convert';
import 'dart:io';

class RouterFailure implements Exception {
  final String message;
  RouterFailure(this.message);
}

class Prefix {
  final int address;
  final int length;
  Prefix(this.address, this.length);
}

class PortRange {
  final int low;
  final int high;
  final bool any;
  PortRange(this.low, this.high, this.any);
}

class Rule {
  final int sequence;
  final String action;
  final String protocol;
  final Prefix source;
  final PortRange sports;
  final Prefix destination;
  final PortRange dports;
  final bool established;
  int hits = 0;
  Rule(this.sequence, this.action, this.protocol, this.source, this.sports, this.destination, this.dports, this.established);
}

class Acl {
  final List<Rule> rules = [];
  int denied = 0;
}

class Pat {
  final String protocol;
  final int inside;
  final int inport;
  final int outport;
  int used;
  Pat(this.protocol, this.inside, this.inport, this.outport, this.used);
}

class Interface extends Prefix {
  final String name;
  bool up = true;
  bool outside = false;
  int? pool;
  String rpf = 'off';
  int rx = 0;
  int tx = 0;
  int drop = 0;
  final Map<String, Acl> acl = {'in': Acl(), 'out': Acl()};
  final List<Pat> pat = [];
  Interface(this.name, super.address, super.length);
}

class Route extends Prefix {
  final String type;
  final Interface output;
  final int? hop;
  final int metric;
  final int order;
  int hits = 0;
  Route(this.type, super.address, super.length, this.output, this.hop, this.metric, this.order);
}

class StaticNat {
  final int inside;
  final int outside;
  StaticNat(this.inside, this.outside);
}

class Forward {
  final Interface output;
  final String protocol;
  final int outport;
  final int inside;
  final int inport;
  Forward(this.output, this.protocol, this.outport, this.inside, this.inport);
}

class PacketTuple {
  final String protocol;
  final int source;
  final int sport;
  final int destination;
  final int dport;
  PacketTuple(this.protocol, this.source, this.sport, this.destination, this.dport);
}

class Connection {
  final int number;
  final PacketTuple original;
  final PacketTuple reply;
  final Interface input;
  final Interface output;
  String state;
  int origPackets = 0;
  int replyPackets = 0;
  int used;
  bool origFin = false;
  bool replyFin = false;
  Connection(this.number, this.original, this.reply, this.input, this.output, this.used)
      : state = original.protocol == 'TCP' ? 'SYN_SENT' : 'UNREPLIED';
}

const dropReasons = ['down', 'martian', 'rpf', 'invalid', 'acl_in', 'ttl', 'noroute', 'acl_out', 'exhausted'];
T? find<T>(Iterable<T> items, bool Function(T) condition) {
  for (final item in items) {
    if (condition(item)) return item;
  }
  return null;
}

String addressText(int address) => [24, 16, 8, 0].map((shift) => (address >> shift) & 255).join('.');
int network(int address, int length) => (address >> (32 - length)) << (32 - length);
bool contains(Prefix prefix, int address) => network(prefix.address, prefix.length) == network(address, prefix.length);

int parseAddress(String text) {
  final fields = text.split('.');
  if (fields.length != 4 || fields.any((field) => !RegExp(r'^(?:0|[1-9][0-9]{0,2})$').hasMatch(field) || int.parse(field) > 255)) {
    throw RouterFailure('bad address $text');
  }
  return fields.fold<int>(0, (value, field) => value * 256 + int.parse(field));
}

Prefix parsePrefix(String text, {bool checkHost = true}) {
  final fields = text.split('/');
  final int address;
  try {
    if (fields.length != 2 || !RegExp(r'^(?:0|[1-9][0-9]?)$').hasMatch(fields[1]) || int.parse(fields[1]) > 32) throw RouterFailure('');
    address = parseAddress(fields[0]);
  } on RouterFailure {
    throw RouterFailure('bad prefix $text');
  }
  final length = int.parse(fields[1]);
  if (checkHost && network(address, length) != address) throw RouterFailure('host bits set in $text');
  return Prefix(address, length);
}

PortRange parsePorts(String text) {
  if (text == 'ANY') return PortRange(0, 65535, true);
  final values = text.split('-').map(int.parse).toList();
  final low = values.first;
  final high = values.last;
  if (low > 65535 || high > 65535 || low > high) throw RouterFailure('bad port range $text');
  return PortRange(low, high, false);
}

String prefixText(Prefix prefix) => prefix.length == 0 ? 'any' : '${addressText(prefix.address)}/${prefix.length}';
String portsText(PortRange ports) => ports.any ? 'any' : ports.low == ports.high ? '${ports.low}' : '${ports.low}-${ports.high}';
String routeText(Route route) => '${route.type} ${addressText(route.address)}/${route.length}${route.hop == null ? '' : ' via ${addressText(route.hop!)}'} dev ${route.output.name} metric ${route.metric}';
String tupleText(PacketTuple tuple) => '${addressText(tuple.source)}:${tuple.sport} > ${addressText(tuple.destination)}:${tuple.dport}';
bool sameTuple(PacketTuple a, PacketTuple b) => a.protocol == b.protocol && a.source == b.source && a.sport == b.sport && a.destination == b.destination && a.dport == b.dport;

class Router {
  final Map<String, Interface> interfaces = {};
  final List<Route> routes = [];
  final List<StaticNat> staticNat = [];
  final List<Forward> forwards = [];
  final List<Connection> connections = [];
  final Map<String, int> timeouts = {'TCP': 300, 'UDP': 60, 'ICMP': 30};
  int clock = 0;
  int packetNumber = 0;
  int connectionNumber = 0;
  int routeOrder = 0;
  int forwarded = 0;
  int local = 0;
  int errors = 0;
  final Map<String, int> drops = {for (final reason in dropReasons) reason: 0};
  final List<String> output = [];

  Interface iface(String name) {
    final result = interfaces[name];
    if (result == null) throw RouterFailure('no interface $name');
    return result;
  }
  Interface? localInterface(int address) => find(interfaces.values, (iface) => iface.address == address);
  List<Interface> orderedInterfaces() => interfaces.values.toList()..sort((a, b) => a.name.compareTo(b.name));

  Route? select(int address) {
    Route? best;
    for (final route in routes) {
      if (!route.output.up || !contains(route, address)) continue;
      if (best == null || route.length > best.length || route.length == best.length && route.metric < best.metric) best = route;
    }
    return best;
  }

  String? evaluateAcl(Interface iface, String direction, PacketTuple tuple, bool established) {
    final acl = iface.acl[direction]!;
    if (acl.rules.isEmpty) return null;
    final rules = acl.rules.toList()..sort((a, b) => a.sequence.compareTo(b.sequence));
    for (final rule in rules) {
      if (rule.protocol != 'ANY' && rule.protocol != tuple.protocol) continue;
      if (!contains(rule.source, tuple.source) || !contains(rule.destination, tuple.destination)) continue;
      if ((rule.protocol == 'TCP' || rule.protocol == 'UDP') && (tuple.sport < rule.sports.low || tuple.sport > rule.sports.high || tuple.dport < rule.dports.low || tuple.dport > rule.dports.high)) continue;
      if (rule.established && !established) continue;
      rule.hits++;
      if (rule.action == 'PERMIT') return null;
      final prefix = '${iface.name} $direction ${rule.sequence}';
      return rule.action == 'DENY' ? 'DROP acl $prefix' : 'REJECT acl $prefix ${tuple.protocol == 'TCP' ? 'tcp-reset' : 'icmp-prohibited'}';
    }
    acl.denied++;
    return 'DROP acl ${iface.name} $direction default';
  }

  String processPacket(Interface input, PacketTuple tuple, String flags, int ttl) {
    String finish(String verdict, String reason) {
      if (reason == 'forwarded') {
        forwarded++;
      } else if (reason == 'local') {
        local++;
      } else {
        drops[reason] = drops[reason]! + 1;
        input.drop++;
      }
      return verdict;
    }
    if (!input.up) return finish('DROP down', 'down');
    bool martian(int address) => address < 16777216 || address >> 24 == 127 || address >= 3758096384;
    if (martian(tuple.source) || martian(tuple.destination) || localInterface(tuple.source) != null) return finish('DROP martian', 'martian');
    if (input.rpf != 'off') {
      final reverse = select(tuple.source);
      if (reverse == null || input.rpf == 'strict' && reverse.output != input) return finish('DROP rpf', 'rpf');
    }
    final pureSyn = tuple.protocol == 'TCP' && flags == 'S';
    Connection? connection;
    var direction = 'new';
    for (final candidate in connections) {
      if (sameTuple(tuple, candidate.original)) {
        connection = candidate;
        direction = 'orig';
        break;
      }
      if (sameTuple(tuple, candidate.reply)) {
        connection = candidate;
        direction = 'reply';
        break;
      }
    }
    if (connection != null && connection.state == 'CLOSED' && pureSyn) {
      connections.remove(connection);
      connection = null;
      direction = 'new';
    }
    if (tuple.protocol == 'TCP' && connection == null && !pureSyn) return finish('DROP invalid', 'invalid');
    final inbound = evaluateAcl(input, 'in', tuple, connection != null);
    if (inbound != null) return finish(inbound, 'acl_in');
    var destination = tuple.destination;
    var dport = tuple.dport;
    Pat? used;
    if (input.outside) {
      final mapping = find(staticNat, (mapping) => mapping.outside == destination);
      if (mapping != null) {
        destination = mapping.inside;
      } else if (destination == input.address) {
        final forward = find(forwards, (rule) => rule.output == input && rule.protocol == tuple.protocol && rule.outport == dport);
        if (forward != null) {
          destination = forward.inside;
          dport = forward.inport;
        } else {
          used = find(input.pat, (mapping) => mapping.protocol == tuple.protocol && mapping.outport == dport);
          if (used != null) {
            destination = used.inside;
            dport = used.inport;
          }
        }
      }
    }
    final localTarget = localInterface(destination);
    if (localTarget != null) return finish('LOCAL ${localTarget.name}', 'local');
    if (ttl == 1) return finish('DROP ttl', 'ttl');
    final route = select(destination);
    if (route == null) return finish('DROP noroute', 'noroute');
    final output = route.output;
    final outbound = evaluateAcl(output, 'out', PacketTuple(tuple.protocol, tuple.source, tuple.sport, destination, dport), connection != null);
    if (outbound != null) return finish(outbound, 'acl_out');
    var source = tuple.source;
    var sport = tuple.sport;
    if (!input.outside && output.outside) {
      final mapping = find(staticNat, (mapping) => mapping.inside == source);
      if (mapping != null) {
        source = mapping.outside;
      } else {
        final forward = find(forwards, (rule) => rule.output == output && rule.protocol == tuple.protocol && rule.inside == source && rule.inport == sport);
        if (forward != null) {
          source = output.address;
          sport = forward.outport;
        } else if (output.pool != null) {
          used = find(output.pat, (mapping) => mapping.protocol == tuple.protocol && mapping.inside == source && mapping.inport == sport);
          if (used == null) {
            var port = 20000;
            while (port < 20000 + output.pool! && (output.pat.any((mapping) => mapping.outport == port) || forwards.any((rule) => rule.output == output && rule.outport == port))) port++;
            if (port == 20000 + output.pool!) return finish('DROP exhausted', 'exhausted');
            used = Pat(tuple.protocol, source, sport, port, clock);
            output.pat.add(used);
          }
          source = output.address;
          sport = used.outport;
        }
      }
    }
    if (used != null) used.used = clock;
    if (connection == null) {
      connection = Connection(++connectionNumber, tuple, PacketTuple(tuple.protocol, destination, dport, source, sport), input, output, clock);
      connections.add(connection);
      direction = 'new';
    }
    if (direction == 'reply') {
      connection.replyPackets++;
    } else {
      connection.origPackets++;
    }
    connection.used = clock;
    if (tuple.protocol != 'TCP') {
      if (direction == 'reply') connection.state = 'REPLIED';
    } else if (flags.contains('R')) {
      connection.state = 'CLOSED';
    } else {
      if (connection.state == 'SYN_SENT' && direction == 'reply' && flags.contains('S') && flags.contains('A')) connection.state = 'ESTABLISHED';
      if (flags.contains('F') && (connection.state == 'ESTABLISHED' || connection.state == 'FIN_WAIT')) {
        if (direction == 'reply') {
          connection.replyFin = true;
        } else {
          connection.origFin = true;
        }
        connection.state = connection.origFin && connection.replyFin ? 'CLOSED' : 'FIN_WAIT';
      }
    }
    output.tx++;
    route.hits++;
    var verdict = 'FORWARD ${output.name} ${route.hop == null ? 'direct' : 'via ${addressText(route.hop!)}'} ttl=${ttl - 1}';
    if (destination != tuple.destination || dport != tuple.dport) verdict += ' dnat=${addressText(destination)}:$dport';
    if (source != tuple.source || sport != tuple.sport) verdict += ' snat=${addressText(source)}:$sport';
    return finish('$verdict conn=${connection.number} $direction', 'forwarded');
  }

  void command(List<String> words) {
    final command = words[0];
    if (command == 'IFACE') {
      final name = words[1];
      final text = words[2];
      if (interfaces.containsKey(name)) throw RouterFailure('duplicate interface $name');
      final prefix = parsePrefix(text, checkHost: false);
      if (prefix.length < 8 || prefix.length > 30) throw RouterFailure('bad prefix $text');
      final net = network(prefix.address, prefix.length);
      if (prefix.address == net || prefix.address == net + (1 << (32 - prefix.length)) - 1) throw RouterFailure('bad host address $text');
      for (final iface in interfaces.values) {
        final length = prefix.length < iface.length ? prefix.length : iface.length;
        if (network(prefix.address, length) == network(iface.address, length)) throw RouterFailure('subnet overlaps ${iface.name}');
      }
      final iface = Interface(name, prefix.address, prefix.length);
      interfaces[name] = iface;
      routes.add(Route('C', net, prefix.length, iface, null, 0, routeOrder++));
      output.add('ok iface $name $text network ${addressText(net)}/${prefix.length}');
    } else if (command == 'UP' || command == 'DOWN') {
      final interface = iface(words[1]);
      final up = command == 'UP';
      if (interface.up == up) throw RouterFailure('interface ${interface.name} already ${up ? 'up' : 'down'}');
      interface.up = up;
      output.add('ok ${command.toLowerCase()} ${interface.name}');
    } else if (command == 'ROUTE') {
      final prefix = parsePrefix(words[1]);
      Interface? outputInterface;
      int? hop;
      if (words[2] == 'VIA') {
        hop = parseAddress(words[3]);
      } else {
        outputInterface = iface(words[3]);
      }
      final metric = int.parse(words[4]);
      if (metric < 1 || metric > 255) throw RouterFailure('bad metric ${words[4]}');
      if (hop != null) {
        if (localInterface(hop) != null) throw RouterFailure('nexthop ${words[3]} is local');
        outputInterface = find(interfaces.values, (interface) => contains(interface, hop!));
        if (outputInterface == null) throw RouterFailure('nexthop ${words[3]} unreachable');
      }
      if (routes.any((route) => route.type == 'S' && route.address == prefix.address && route.length == prefix.length && route.output == outputInterface && route.hop == hop)) throw RouterFailure('duplicate route ${words[1]}');
      final route = Route('S', prefix.address, prefix.length, outputInterface!, hop, metric, routeOrder++);
      routes.add(route);
      output.add('ok route ${routeText(route)}');
    } else if (command == 'NOROUTE') {
      final prefix = parsePrefix(words[1]);
      bool matches(Route route) => route.type == 'S' && route.address == prefix.address && route.length == prefix.length;
      final removed = routes.where(matches).length;
      if (removed == 0) throw RouterFailure('no static route ${words[1]}');
      routes.removeWhere(matches);
      output.add('ok noroute ${words[1]} removed=$removed');
    } else if (command == 'LOOKUP') {
      final route = select(parseAddress(words[1]));
      output.add('lookup ${words[1]} ${route == null ? 'none' : routeText(route)}');
    } else if (command == 'ACL') {
      final interface = iface(words[1]);
      final direction = words[2].toLowerCase();
      final sequence = int.parse(words[3]);
      if (sequence < 1 || sequence > 9999) throw RouterFailure('bad sequence ${words[3]}');
      final source = words[6] == 'ANY' ? Prefix(0, 0) : parsePrefix(words[6]);
      final sports = parsePorts(words[7]);
      final destination = words[8] == 'ANY' ? Prefix(0, 0) : parsePrefix(words[8]);
      final dports = parsePorts(words[9]);
      if ((words[5] == 'ICMP' || words[5] == 'ANY') && (!sports.any || !dports.any)) throw RouterFailure('ports not allowed for ${words[5]}');
      final acl = interface.acl[direction]!;
      if (acl.rules.any((rule) => rule.sequence == sequence)) throw RouterFailure('duplicate sequence ${words[3]}');
      acl.rules.add(Rule(sequence, words[4], words[5], source, sports, destination, dports, words.length == 11));
      output.add('ok acl ${interface.name} $direction ${words[3]}');
    } else if (command == 'NOACL') {
      final interface = iface(words[1]);
      final direction = words[2].toLowerCase();
      final acl = interface.acl[direction]!;
      final rule = find(acl.rules, (rule) => rule.sequence == int.parse(words[3]));
      if (rule == null) throw RouterFailure('no rule ${words[3]} on ${interface.name} $direction');
      acl.rules.remove(rule);
      output.add('ok noacl ${interface.name} $direction ${words[3]} hits=${rule.hits}');
    } else if (command == 'NAT') {
      natCommand(words);
    } else if (command == 'RPF') {
      final interface = iface(words[1]);
      interface.rpf = words[2].toLowerCase();
      output.add('ok rpf ${interface.name} ${interface.rpf}');
    } else if (command == 'TIMEOUT') {
      final seconds = int.parse(words[2]);
      if (seconds < 1 || seconds > 86400) throw RouterFailure('bad timeout ${words[2]}');
      timeouts[words[1]] = seconds;
      output.add('ok timeout ${words[1]} ${words[2]}');
    } else if (command == 'TICK') {
      final seconds = int.parse(words[1]);
      if (seconds < 1 || seconds > 86400) throw RouterFailure('bad tick ${words[1]}');
      clock += seconds;
      final before = connections.length;
      connections.removeWhere((connection) {
        final protocol = connection.original.protocol;
        final timeout = protocol != 'TCP' || connection.state == 'ESTABLISHED' ? timeouts[protocol]! : connection.state == 'CLOSED' ? 10 : 60;
        return clock - connection.used >= timeout;
      });
      var removed = 0;
      for (final interface in interfaces.values) {
        final count = interface.pat.length;
        interface.pat.removeWhere((mapping) => clock - mapping.used >= timeouts[mapping.protocol]!);
        removed += count - interface.pat.length;
      }
      output.add('ok tick time=$clock expired conns=${before - connections.length} nat=$removed');
    } else if (command == 'PACKET') {
      final interface = iface(words[1]);
      final protocol = words[2];
      final flags = words[3];
      if (protocol != 'TCP' && flags != '-') throw RouterFailure('flags not allowed for $protocol');
      if (protocol == 'TCP' && flags != '-' && (!RegExp(r'^[SAFR]+$').hasMatch(flags) || flags.split('').toSet().length != flags.length)) throw RouterFailure('bad flags $flags');
      final source = parseAddress(words[4]);
      final sport = int.parse(words[5]);
      if (sport > 65535) throw RouterFailure('bad port ${words[5]}');
      final destination = parseAddress(words[6]);
      final dport = int.parse(words[7]);
      if (dport > 65535) throw RouterFailure('bad port ${words[7]}');
      final ttl = int.parse(words[8]);
      if (ttl < 1 || ttl > 255) throw RouterFailure('bad ttl ${words[8]}');
      packetNumber++;
      interface.rx++;
      final verdict = processPacket(interface, PacketTuple(protocol, source, sport, destination, dport), flags, ttl);
      output.add('#$packetNumber $protocol $flags ${words[4]}:${words[5]} > ${words[6]}:${words[7]} $verdict');
    } else if (command == 'SHOW') {
      show(words[1]);
    } else if (command == 'CLEAR') {
      if (words[1] == 'CONNS') {
        final mappings = interfaces.values.fold<int>(0, (total, interface) => total + interface.pat.length);
        output.add('ok clear conns=${connections.length} nat=$mappings');
        connections.clear();
        for (final interface in interfaces.values) interface.pat.clear();
      } else {
        forwarded = local = errors = 0;
        for (final reason in dropReasons) drops[reason] = 0;
        for (final route in routes) route.hits = 0;
        for (final interface in interfaces.values) {
          interface.rx = interface.tx = interface.drop = 0;
          for (final acl in interface.acl.values) {
            acl.denied = 0;
            for (final rule in acl.rules) rule.hits = 0;
          }
        }
        output.add('ok clear counters');
      }
    }
  }

  void natCommand(List<String> words) {
    if (words[1] == 'STATIC') {
      final inside = parseAddress(words[2]);
      final outside = parseAddress(words[3]);
      if (localInterface(inside) != null) throw RouterFailure('address ${words[2]} is local');
      if (localInterface(outside) != null) throw RouterFailure('address ${words[3]} is local');
      if (staticNat.any((mapping) => mapping.inside == inside)) throw RouterFailure('duplicate static ${words[2]}');
      if (staticNat.any((mapping) => mapping.outside == outside)) throw RouterFailure('duplicate static ${words[3]}');
      staticNat.add(StaticNat(inside, outside));
      output.add('ok nat static ${words[2]} ${words[3]}');
      return;
    }
    final interface = iface(words[2]);
    if (words[1] == 'OUTSIDE') {
      if (interface.outside) throw RouterFailure('interface ${interface.name} already outside');
      interface.outside = true;
      output.add('ok nat outside ${interface.name}');
    } else if (words[1] == 'PAT') {
      final count = int.parse(words[3]);
      if (count < 1 || count > 1000) throw RouterFailure('bad pool size ${words[3]}');
      if (interface.pool != null) throw RouterFailure('pat already on ${interface.name}');
      interface.pool = count;
      interface.outside = true;
      output.add('ok nat pat ${interface.name} ${addressText(interface.address)} 20000-${20000 + count - 1}');
    } else {
      final protocol = words[3];
      final outport = int.parse(words[4]);
      if (outport < 1 || outport > 65535) throw RouterFailure('bad port ${words[4]}');
      final inside = parseAddress(words[5]);
      final inport = int.parse(words[6]);
      if (inport < 1 || inport > 65535) throw RouterFailure('bad port ${words[6]}');
      if (!interface.outside) throw RouterFailure('interface ${interface.name} not outside');
      if (localInterface(inside) != null) throw RouterFailure('address ${words[5]} is local');
      if (forwards.any((rule) => rule.output == interface && rule.protocol == protocol && rule.outport == outport)) throw RouterFailure('duplicate forward ${interface.name} $protocol ${words[4]}');
      forwards.add(Forward(interface, protocol, outport, inside, inport));
      output.add('ok nat forward ${interface.name} $protocol ${words[4]} ${words[5]}:${words[6]}');
    }
  }

  void show(String what) {
    final sortedInterfaces = orderedInterfaces();
    if (what == 'IFACES') {
      output.add('show ifaces count=${sortedInterfaces.length}');
      for (final interface in sortedInterfaces) output.add('${interface.name} ${addressText(interface.address)}/${interface.length} ${interface.up ? 'up' : 'down'} ${interface.outside ? 'outside' : 'inside'} rpf=${interface.rpf}${interface.pool == null ? '' : ' pat=${interface.pat.length}/${interface.pool}'}');
    } else if (what == 'ROUTES') {
      output.add('show routes count=${routes.length}');
      final sorted = routes.toList()..sort((a, b) {
        for (final comparison in [a.address.compareTo(b.address), a.length.compareTo(b.length), a.metric.compareTo(b.metric), a.order.compareTo(b.order)]) {
          if (comparison != 0) return comparison;
        }
        return 0;
      });
      for (final route in sorted) output.add('${routeText(route)} hits=${route.hits}${route.output.up ? '' : ' inactive'}');
    } else if (what == 'ACL') {
      final count = sortedInterfaces.fold<int>(0, (total, interface) => total + interface.acl['in']!.rules.length + interface.acl['out']!.rules.length);
      output.add('show acl count=$count');
      for (final interface in sortedInterfaces) {
        for (final direction in ['in', 'out']) {
          final acl = interface.acl[direction]!;
          if (acl.rules.isEmpty) continue;
          final rules = acl.rules.toList()..sort((a, b) => a.sequence.compareTo(b.sequence));
          for (final rule in rules) output.add('acl ${interface.name} $direction ${rule.sequence} ${rule.action} ${rule.protocol} ${prefixText(rule.source)} ${portsText(rule.sports)} ${prefixText(rule.destination)} ${portsText(rule.dports)}${rule.established ? ' established' : ''} hits=${rule.hits}');
          output.add('acl ${interface.name} $direction default DENY hits=${acl.denied}');
        }
      }
    } else if (what == 'NAT') {
      final count = sortedInterfaces.fold<int>(0, (total, interface) => total + interface.pat.length);
      output.add('show nat static=${staticNat.length} forward=${forwards.length} pat=$count');
      final mappings = staticNat.toList()..sort((a, b) => a.inside.compareTo(b.inside));
      for (final mapping in mappings) output.add('static ${addressText(mapping.inside)} ${addressText(mapping.outside)}');
      final rules = forwards.toList()..sort((a, b) {
        final name = a.output.name.compareTo(b.output.name);
        if (name != 0) return name;
        final port = a.outport.compareTo(b.outport);
        return port == 0 ? a.protocol.compareTo(b.protocol) : port;
      });
      for (final rule in rules) output.add('forward ${rule.output.name} ${rule.protocol} ${rule.outport} ${addressText(rule.inside)}:${rule.inport}');
      for (final interface in sortedInterfaces) {
        final pat = interface.pat.toList()..sort((a, b) => a.outport.compareTo(b.outport));
        for (final mapping in pat) output.add('pat ${interface.name} ${mapping.outport} ${mapping.protocol} ${addressText(mapping.inside)}:${mapping.inport} idle=${clock - mapping.used}');
      }
    } else if (what == 'CONNS') {
      output.add('show conns count=${connections.length}');
      for (final connection in connections) output.add('conn ${connection.number} ${connection.original.protocol} ${tupleText(connection.original)} reply ${tupleText(connection.reply)} in=${connection.input.name} out=${connection.output.name} state=${connection.state} pkts=${connection.origPackets}/${connection.replyPackets} idle=${clock - connection.used}');
    } else {
      final dropped = dropReasons.fold<int>(0, (total, reason) => total + drops[reason]!);
      output.add('show counters packets=${forwarded + local + dropped} forwarded=$forwarded local=$local dropped=$dropped errors=$errors');
      output.add('drops ${dropReasons.map((reason) => '$reason=${drops[reason]}').join(' ')}');
      for (final interface in sortedInterfaces) output.add('iface ${interface.name} rx=${interface.rx} tx=${interface.tx} drop=${interface.drop}');
    }
  }

  void run(List<String> lines) {
    final count = int.parse(lines[0]);
    for (final line in lines.skip(1).take(count)) {
      try {
        command(line.split(' '));
      } on RouterFailure catch (error) {
        errors++;
        output.add('error: ${error.message}');
      }
    }
  }
}

Future<void> main() async {
  final router = Router();
  router.run((await stdin.transform(utf8.decoder).join()).split('\n'));
  stdout.write('${router.output.join('\n')}\n');
}
