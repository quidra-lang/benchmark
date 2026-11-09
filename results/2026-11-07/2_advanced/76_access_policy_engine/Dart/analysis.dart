part of 'main.dart';

class Domain {
  final String attribute;
  final List<Value> values;
  Domain(this.attribute, this.values);
}

String dayNotation(Set<int> days) {
  final runs = <String>[];
  var first = 1;
  while (first <= 365) {
    if (!days.contains(first)) {
      first++;
      continue;
    }
    var last = first;
    while (last < 365 && days.contains(last + 1)) {
      last++;
    }
    runs.add('$first-$last');
    first = last + 1;
  }
  return runs.join(',');
}

void enumeratePoints(
  List<Domain> domains,
  void Function(Map<String, Value>) visit,
) {
  final point = <String, Value>{};
  void walk(int i) {
    if (i == domains.length) {
      visit(point);
      return;
    }
    for (final value in domains[i].values) {
      point[domains[i].attribute] = value;
      walk(i + 1);
    }
  }

  walk(0);
}

Element conflictWinner(Element policy, Element a, Element b) {
  if (policy.algorithm == 'first-applicable') return a;
  final effect =
      ['deny-overrides', 'permit-unless-deny'].contains(policy.algorithm)
      ? 'DENY'
      : 'PERMIT';
  return a.effect == effect ? a : b;
}

Element? blocker(Element rule, Map<Element, String> standalone) {
  for (final earlier in rule.parent!.children) {
    if (earlier == rule) break;
    if (standalone[earlier] != na) return earlier;
  }
  return null;
}
