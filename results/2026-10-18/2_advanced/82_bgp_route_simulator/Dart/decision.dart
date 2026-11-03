part of 'main.dart';

class Attribute {
  final List<int> path, communities;
  final String origin;
  final int med;
  Attribute(List<int> path, this.origin, this.med, List<int> communities)
    : path = List.unmodifiable(path),
      communities = List.unmodifiable(communities);
}

class Route {
  final Attribute attribute;
  final bool local;
  final int lp;
  final Link? link;
  Route(this.attribute, {this.local = false, this.lp = 0, this.link});
}

bool sameInts(List<int> a, List<int> b) =>
    a.length == b.length &&
    List.generate(a.length, (i) => a[i] == b[i]).every((x) => x);
bool sameAttribute(Attribute? a, Attribute? b) => a == null || b == null
    ? a == null && b == null
    : a.origin == b.origin &&
          a.med == b.med &&
          sameInts(a.path, b.path) &&
          sameInts(a.communities, b.communities);
bool sameRoute(Route? a, Route? b) => a == null || b == null
    ? a == null && b == null
    : a.local == b.local &&
          a.lp == b.lp &&
          a.link == b.link &&
          sameAttribute(a.attribute, b.attribute);
int originRank(String s) => s == 'IGP'
    ? 0
    : s == 'EGP'
    ? 1
    : 2;
(Route, String) bestRoute(List<Route> input, Topology t) {
  var a = List<Route>.of(input);
  if (a.length == 1) return (a.first, 'ONLY');
  for (final stage in [
    'LOCALPREF',
    'ASPATH',
    'ORIGIN',
    'MED',
    'ROUTERID',
    'LINK',
  ]) {
    if (stage == 'MED') {
      final minimum = <int, int>{};
      for (final r in a) {
        final n = r.attribute.path.first;
        minimum[n] = min(minimum[n] ?? r.attribute.med, r.attribute.med);
      }
      a = a
          .where((r) => r.attribute.med == minimum[r.attribute.path.first])
          .toList();
    } else {
      int value(Route r) => switch (stage) {
        'LOCALPREF' => -r.lp,
        'ASPATH' => r.attribute.path.length,
        'ORIGIN' => originRank(r.attribute.origin),
        'ROUTERID' => t.byNumber[r.attribute.path.first]!.router,
        _ => r.link!.number,
      };
      final minimum = a.map(value).reduce(min);
      a = a.where((r) => value(r) == minimum).toList();
    }
    if (a.length == 1) return (a.first, stage);
  }
  return (a.first, 'LINK');
}
