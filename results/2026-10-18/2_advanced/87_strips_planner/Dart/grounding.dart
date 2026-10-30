part of 'main.dart';

typedef State = BigInt;
bool has(State state, int p) => (state & (BigInt.one << p)) != BigInt.zero;
State put(State state, int p) => state | (BigInt.one << p);
bool contains(State state, State required) => (state & required) == required;
bool intersects(State state, State other) => (state & other) != BigInt.zero;
List<int> numbers(State state) {
  final out = <int>[];
  var i = 0;
  while (state != BigInt.zero) {
    if ((state & BigInt.one) != BigInt.zero) out.add(i);
    state >>= 1;
    i++;
  }
  return out;
}

State factSet(Iterable<int> numbers) {
  var state = BigInt.zero;
  for (final p in numbers) {
    state = put(state, p);
  }
  return state;
}

bool subtype(Domain d, String type, String expected) {
  while (true) {
    if (type == expected) return true;
    if (type == 'object') return false;
    type = d.parents[type]!;
  }
}

void classify(Domain d) {
  d.fluent.clear();
  for (final schema in d.actions) {
    for (final e in schema.effects) {
      d.fluent.add(e.atom.predicate);
    }
  }
}

Atom substitute(Atom a, Map<String, String> assignment) =>
    Atom(a.predicate, [for (final t in a.terms) assignment[t]!]);

class GroundAction {
  final Schema schema;
  final List<String> arguments;
  final int cost, number;
  final State pre, neg, add, del;
  GroundAction(
    this.schema,
    this.arguments,
    this.cost,
    this.number,
    this.pre,
    this.neg,
    this.add,
    this.del,
  );
  String text() => Atom(schema.name, arguments).text();
}

class GroundCandidate {
  final Schema schema;
  final List<String> arguments;
  final Map<String, Atom> pre = {}, neg = {}, add = {}, del = {};
  bool reachable = false;
  GroundCandidate(this.schema, this.arguments);
}

class SchemaCount {
  int assignments = 1, candidates = 0, reachable = 0;
}

class GroundProblem {
  final Domain domain;
  final Problem problem;
  final List<Atom> facts = [];
  final Map<String, int> factIndex = {};
  final List<GroundAction> actions = [];
  State initial = BigInt.zero, goal = BigInt.zero;
  final List<Atom> unreachable = [];
  final Map<String, SchemaCount> counts = {};
  int candidateCount = 0, staticFacts = 0;
  final Map<State, Heuristic> cache = {};
  GroundProblem(this.domain, this.problem);
}

Map<String, String> objectTypes(Problem p) => {
  for (final o in p.objects) o.name: o.type,
};
List<String> objectsOfType(Domain d, Problem p, String type) => [
  for (final o in p.objects)
    if (subtype(d, o.type, type)) o.name,
];
bool atomsContain(Map<String, Atom> set, Map<String, Atom> required) =>
    required.keys.every(set.containsKey);
GroundProblem ground(Domain d, Problem p) {
  final g = GroundProblem(d, p),
      initial = <String, Atom>{},
      reachable = <String, Atom>{};
  for (final a in p.initial) {
    initial[a.text()] = a;
    if (d.fluent.contains(a.predicate)) {
      reachable[a.text()] = a;
    } else {
      g.staticFacts++;
    }
  }
  final candidates = <GroundCandidate>[];
  for (final schema in d.actions) {
    final count = SchemaCount();
    g.counts[schema.name] = count;
    final choices = [
      for (final param in schema.parameters) objectsOfType(d, p, param.type),
    ];
    for (final values in choices) {
      count.assignments *= values.length;
    }
    final assignment = <String, String>{},
        arguments = List.filled(schema.parameters.length, '');
    void enumerate(int at) {
      if (at < schema.parameters.length) {
        for (final object in choices[at]) {
          arguments[at] = object;
          assignment[schema.parameters[at].name] = object;
          enumerate(at + 1);
        }
        return;
      }
      final candidate = GroundCandidate(schema, List<String>.of(arguments));
      for (final literal in schema.conditions) {
        final a = substitute(literal.atom, assignment);
        if (a.predicate == '=' || !d.fluent.contains(a.predicate)) {
          final truth = a.predicate == '='
              ? a.terms[0] == a.terms[1]
              : initial.containsKey(a.text());
          if (truth == literal.negative) return;
        } else if (literal.negative) {
          candidate.neg[a.text()] = a;
        } else {
          candidate.pre[a.text()] = a;
        }
      }
      for (final literal in schema.effects) {
        final a = substitute(literal.atom, assignment);
        (literal.negative ? candidate.del : candidate.add)[a.text()] = a;
      }
      for (final key in candidate.add.keys) {
        candidate.del.remove(key);
      }
      candidates.add(candidate);
      count.candidates++;
    }

    enumerate(0);
  }
  g.candidateCount = candidates.length;
  while (true) {
    var changed = false;
    for (final candidate in candidates) {
      if (!candidate.reachable && atomsContain(reachable, candidate.pre)) {
        candidate.reachable = true;
        changed = true;
        reachable.addAll(candidate.add);
      }
    }
    if (!changed) break;
  }
  g.facts.addAll(reachable.values);
  final objectNumbers = {
    for (var i = 0; i < p.objects.length; i++) p.objects[i].name: i,
  };
  g.facts.sort((a, b) {
    final c = d.predicateIndex[a.predicate]!.compareTo(
      d.predicateIndex[b.predicate]!,
    );
    if (c != 0) return c;
    return compareInts(
      [for (final t in a.terms) objectNumbers[t]!],
      [for (final t in b.terms) objectNumbers[t]!],
    );
  });
  for (var i = 0; i < g.facts.length; i++) {
    g.factIndex[g.facts[i].text()] = i;
  }
  State toState(Map<String, Atom> atoms) => factSet([
    for (final key in atoms.keys)
      if (g.factIndex.containsKey(key)) g.factIndex[key]!,
  ]);
  g.initial = toState(initial);
  for (final c in candidates) {
    if (!c.reachable) continue;
    g.actions.add(
      GroundAction(
        c.schema,
        c.arguments,
        c.schema.cost,
        g.actions.length,
        toState(c.pre),
        toState(c.neg),
        toState(c.add),
        toState(c.del),
      ),
    );
    g.counts[c.schema.name]!.reachable++;
  }
  for (final a in p.goals) {
    final number = g.factIndex[a.text()];
    if (number != null) {
      g.goal = put(g.goal, number);
    } else if (!d.fluent.contains(a.predicate)) {
      if (!initial.containsKey(a.text())) g.unreachable.add(a);
    } else {
      g.unreachable.add(a);
    }
  }
  return g;
}
