part of 'main.dart';

typedef Prefix = (int, int);
int ip(String s) => s.split('.').fold(0, (a, b) => a * 256 + int.parse(b));
String ipText(int n) =>
    '${n >> 24}.${(n >> 16) & 255}.${(n >> 8) & 255}.${n & 255}';
Prefix prefix(String s) {
  final a = s.split('/');
  return (ip(a[0]), int.parse(a[1]));
}

String prefixText(Prefix p) => '${ipText(p.$1)}/${p.$2}';
bool contains(Prefix p, int address) =>
    (p.$1 >> (32 - p.$2)) == (address >> (32 - p.$2));
int prefixCompare(Prefix a, Prefix b) {
  final c = a.$1.compareTo(b.$1);
  return c == 0 ? a.$2.compareTo(b.$2) : c;
}

List<Prefix> orderedPrefixes(Iterable<Prefix> values) =>
    values.toSet().toList()..sort(prefixCompare);

class ASNode {
  final int number, router;
  final Map<Prefix, Attribute> origins = {};
  final Map<Prefix, Route> rib = {};
  final List<Session> sessions = [];
  int changes = 0;
  ASNode(this.number, this.router);
}

class Link {
  final String name, relationship;
  final ASNode a, b;
  final int delay, mrai, number;
  bool up = true;
  int downs = 0;
  final List<Session> sessions = [];
  Link(
    this.name,
    this.a,
    this.b,
    this.relationship,
    this.delay,
    this.mrai,
    this.number,
  );
  ASNode other(ASNode node) => node == a ? b : a;
  String role(ASNode node) => relationship == 'P2P'
      ? 'peer'
      : node == a
      ? 'customer'
      : 'provider';
  Session session(ASNode node) => sessions[node == a ? 0 : 1];
}

String symbol(String role) => role == 'customer'
    ? 'D'
    : role == 'provider'
    ? 'U'
    : 'P';

class Topology {
  final List<ASNode> nodes = [];
  final Map<int, ASNode> byNumber = {};
  final List<Link> links = [];
  final Map<String, Link> byName = {};
  final List<(ASNode, Prefix, Attribute)> initial = [];
  List<Session> get sessions => [for (final node in nodes) ...node.sessions];
  Link between(int a, int b) => byNumber[a]!.sessions
      .firstWhere((s) => s.link.other(s.owner).number == b)
      .link;
}

Topology readTopology() {
  final t = Topology();
  for (final line in lines('input/topology.txt')) {
    final a = line.split(' ');
    switch (a[0]) {
      case 'AS':
        final node = ASNode(int.parse(a[1]), ip(a[2]));
        t.nodes.add(node);
        t.byNumber[node.number] = node;
        break;
      case 'LINK':
        final l = Link(
          a[1],
          t.byNumber[int.parse(a[2])]!,
          t.byNumber[int.parse(a[3])]!,
          a[4],
          int.parse(a[5]),
          int.parse(a[6]),
          t.links.length,
        );
        t.links.add(l);
        t.byName[l.name] = l;
        for (final node in [l.a, l.b]) {
          final s = Session(node, l);
          l.sessions.add(s);
          node.sessions.add(s);
        }
        break;
      case 'PREFIX':
        t.initial.add((
          t.byNumber[int.parse(a[1])]!,
          prefix(a[2]),
          Attribute([], a[3], 0, communities(a.skip(4))),
        ));
        break;
    }
  }
  t.nodes.sort((a, b) => a.number.compareTo(b.number));
  return t;
}
