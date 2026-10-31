part of 'main.dart';

const noExport = 0xffffff01;
int community(String s) {
  if (s == 'NO_EXPORT') return noExport;
  final a = s.split(':');
  return int.parse(a[0]) * 65536 + int.parse(a[1]);
}

String communityText(int c) =>
    c == noExport ? 'NO_EXPORT' : '${c >> 16}:${c & 65535}';
List<int> communities(Iterable<String> a) =>
    a.map(community).toSet().toList()..sort();
String communitiesText(List<int> a) =>
    a.isEmpty ? '-' : a.map(communityText).join(',');

class Rule {
  final String name, direction, target;
  final int owner;
  bool active, deny = false, allow = false;
  int? lp, med;
  int prepend = 0, hits = 0;
  final List<(String, String)> conditions = [];
  final List<(bool, int)> edits = [];
  Rule(this.name, this.active, this.owner, this.direction, this.target);
  List<int> edit(List<int> input) {
    final a = input.toSet();
    for (final e in edits) {
      if (e.$1) {
        a.add(e.$2);
      } else {
        a.remove(e.$2);
      }
    }
    return a.toList()..sort();
  }
}

class Policies {
  final Map<String, List<(bool, Prefix, int, int)>> lists = {};
  final List<Rule> rules = [];
  final Map<String, Rule> byName = {};
  bool permitted(String name, Prefix p) {
    for (final e in lists[name]!) {
      if (e.$3 <= p.$2 && p.$2 <= e.$4 && contains(e.$2, p.$1)) return e.$1;
    }
    return false;
  }

  Rule? applied(String direction, Session s, Prefix p, Attribute a) {
    for (final r in rules) {
      if (!r.active || r.owner != s.owner.number || r.direction != direction)
        continue;
      if (r.target != '*' &&
          r.target != '${s.link.other(s.owner).number}' &&
          r.target != s.link.name)
        continue;
      var match = true;
      for (final c in r.conditions) {
        switch (c.$1) {
          case 'PREFIX':
            match = permitted(c.$2, p);
            break;
          case 'CONTAINS':
            match = a.path.contains(int.parse(c.$2));
            break;
          case 'ORIGINAS':
            match =
                (a.path.isEmpty ? s.owner.number : a.path.last) ==
                int.parse(c.$2);
            break;
          case 'LENGTH':
            final v = c.$2.split('-').map(int.parse).toList();
            match = v[0] <= a.path.length && a.path.length <= v[1];
            break;
          case 'COMMUNITY':
            match = a.communities.contains(community(c.$2));
            break;
        }
        if (!match) break;
      }
      if (match) return r;
    }
    return null;
  }
}

Policies readPolicies() {
  final p = Policies();
  for (final line in lines('input/policies.txt')) {
    final a = line.split(' ');
    if (a[0] == 'PLIST') {
      final q = prefix(a[3]);
      var low = q.$2, high = q.$2, ge = false, le = false;
      for (var i = 4; i < a.length; i += 2) {
        if (a[i] == 'GE') {
          low = int.parse(a[i + 1]);
          ge = true;
        } else {
          high = int.parse(a[i + 1]);
          le = true;
        }
      }
      if (ge && !le) high = 32;
      p.lists.putIfAbsent(a[1], () => []).add((a[2] == 'PERMIT', q, low, high));
      continue;
    }
    final r = Rule(a[1], a[2] == 'ON', int.parse(a[3]), a[4], a[5]);
    var i = 6;
    while (a[i] != 'THEN') {
      r.conditions.add((a[i], a[i + 1]));
      i += 2;
    }
    i++;
    while (i < a.length) {
      final kind = a[i++];
      switch (kind) {
        case 'DENY':
          r.deny = true;
          break;
        case 'ALLOW':
          r.allow = true;
          break;
        case 'LOCALPREF':
          r.lp = int.parse(a[i++]);
          break;
        case 'MED':
          r.med = int.parse(a[i++]);
          break;
        case 'PREPEND':
          r.prepend = int.parse(a[i++]);
          break;
        case 'ADD':
        case 'REMOVE':
          r.edits.add((kind == 'ADD', community(a[i++])));
          break;
      }
    }
    p.rules.add(r);
    p.byName[r.name] = r;
  }
  return p;
}
