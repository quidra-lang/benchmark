import 'dart:io';
import 'dart:math' as math;

String yes(bool value) => value ? 'yes' : 'no';
String mark(List<int> m) => '(${m.map((v) => v < 0 ? 'w' : '$v').join(',')})';
String listed(List<String> a) => a.isEmpty ? 'none' : a.join(' ');
int? number(String s, int low, int high) {
  if (!RegExp(r'^(0|[1-9][0-9]{0,9})$').hasMatch(s)) return null;
  final value = int.parse(s);
  return value >= low && value <= high ? value : null;
}

Never bad(String reason) => throw FormatException(reason);
List<bool> visit(List<List<int>> adj, int start) {
  final seen = List.filled(adj.length, false), queue = [start];
  seen[start] = true;
  for (var i = 0; i < queue.length; ++i) {
    for (final v in adj[queue[i]]) {
      if (!seen[v]) {
        seen[v] = true;
        queue.add(v);
      }
    }
  }
  return seen;
}

int lex(List<int> a, List<int> b) {
  for (var i = 0; i < a.length; ++i) {
    if (a[i] != b[i]) return a[i].compareTo(b[i]);
  }
  return 0;
}

List<List<int>> flows(List<List<int>> a) {
  final n = a.length, m = a.first.length;
  var rows = [
    for (var i = 0; i < n; ++i)
      [...a[i], for (var j = 0; j < n; ++j) i == j ? 1 : 0],
  ];
  for (var j = 0; j < m; ++j) {
    final unique = <String, List<int>>{};
    for (final r in rows) {
      if (r[j] == 0) unique[r.join(',')] = r;
    }
    for (final r in rows) {
      if (r[j] > 0) {
        for (final s in rows) {
          if (s[j] < 0) {
            final v = [
              for (var k = 0; k < m + n; ++k) -s[j] * r[k] + r[j] * s[k],
            ];
            final d = v.fold(0, (g, x) => g.gcd(x));
            for (var k = 0; k < v.length; ++k) {
              v[k] ~/= d;
            }
            unique[v.join(',')] = v;
          }
        }
      }
    }
    final candidates = unique.values.toList();
    final supports = [
      for (final r in candidates)
        [
          for (var i = 0; i < n; ++i)
            if (r[m + i] > 0) 1 << i,
        ].fold(0, (s, v) => s | v),
    ];
    rows = [
      for (var i = 0; i < candidates.length; ++i)
        if (!supports.any((s) => s != supports[i] && (s & supports[i]) == s))
          candidates[i],
    ];
  }
  return rows.map((r) => r.sublist(m)).toList()..sort((a, b) => lex(b, a));
}

class Graph {
  final states = <List<int>>[],
      parent = <int>[],
      via = <int>[],
      edges = <List<(int, int)>>[];
  int found = -1;
  bool aborted = false;
  void add(List<int> m, int p, int t) {
    states.add(m);
    parent.add(p);
    via.add(t);
    edges.add([]);
  }
}

class Net {
  final String name;
  final places = <String>[], transitions = <String>[];
  final initial = <int>[], capacity = <int>[], priority = <int>[];
  final pre = List.generate(16, (_) => List.filled(16, 0));
  final post = List.generate(16, (_) => List.filled(16, 0));
  final inhibitor = List.generate(16, (_) => List.filled(16, 0));
  var arcs = 0, inhibitors = 0;
  List<int> current = [];
  final history = <List<int>>[];
  Net(this.name);
  void define(List<String> w) {
    final cmd = w[0], n = w.length - 1;
    if (!['place', 'transition', 'arc', 'inhibit'].contains(cmd))
      bad('unknown definition $cmd');
    if (!(cmd == 'place'
        ? n == 2 || n == 3
        : cmd == 'transition'
        ? n == 1 || n == 2
        : n == 3))
      bad('wrong number of arguments');
    final a = w[1];
    if (cmd == 'place' || cmd == 'transition') {
      if (places.contains(a) || transitions.contains(a))
        bad('duplicate name $a');
      if (cmd == 'place') {
        if (n == 3 && int.parse(w[2]) > int.parse(w[3]))
          bad('tokens exceed capacity of $a');
        places.add(a);
        initial.add(int.parse(w[2]));
        capacity.add(n == 3 ? int.parse(w[3]) : 0);
      } else {
        transitions.add(a);
        priority.add(n == 2 ? int.parse(w[2]) : 0);
      }
    } else if (cmd == 'arc') {
      final b = w[2];
      for (final x in [a, b]) {
        if (!places.contains(x) && !transitions.contains(x))
          bad('unknown node $x');
      }
      final pa = places.indexOf(a), pb = places.indexOf(b);
      if ((pa >= 0) == (pb >= 0))
        bad('arc must connect a place and a transition');
      final p = pa >= 0 ? pa : pb,
          t = transitions.indexOf(pa >= 0 ? b : a),
          matrix = pa >= 0 ? pre : post;
      if (matrix[p][t] > 0) bad('duplicate arc $a $b');
      matrix[p][t] = int.parse(w[3]);
      ++arcs;
    } else {
      final p = places.indexOf(a), t = transitions.indexOf(w[2]);
      if (p < 0) bad('unknown place $a');
      if (t < 0) bad('unknown transition ${w[2]}');
      if (inhibitor[p][t] > 0) bad('duplicate inhibitor $a ${w[2]}');
      inhibitor[p][t] = int.parse(w[3]);
      ++inhibitors;
    }
  }

  String? reason(List<int> m, int t) {
    for (var p = 0; p < places.length; ++p) {
      if (m[p] >= 0 && m[p] < pre[p][t])
        return 'insufficient tokens in ${places[p]}';
    }
    for (var p = 0; p < places.length; ++p) {
      if (inhibitor[p][t] > 0 && (m[p] < 0 || m[p] >= inhibitor[p][t]))
        return 'inhibited by ${places[p]}';
    }
    for (var p = 0; p < places.length; ++p) {
      if (capacity[p] > 0 &&
          (m[p] < 0 || m[p] - pre[p][t] + post[p][t] > capacity[p]))
        return 'capacity of ${places[p]} exceeded';
    }
    return null;
  }

  List<int> enabled(List<int> m) => [
    for (var t = 0; t < transitions.length; ++t)
      if (reason(m, t) == null) t,
  ];
  List<int> fire(List<int> m, int t) => [
    for (var p = 0; p < m.length; ++p)
      m[p] < 0 ? -1 : m[p] - pre[p][t] + post[p][t],
  ];
  void commit(int t) {
    history.add(current);
    current = fire(current, t);
  }

  List<String> names(List<int> ts) => ts.map((t) => transitions[t]).toList();
  Graph graph(List<int> start, int limit, [List<(int, int)>? target]) {
    final g = Graph()..add(List.of(start), -1, -1),
        index = <String, int>{start.join(','): 0};
    bool matches(List<int> m) =>
        target != null &&
        [
          for (var p = 0; p < m.length; ++p)
            m[p] >= target[p].$1 && (target[p].$2 < 0 || m[p] == target[p].$2),
        ].every((v) => v);
    if (matches(start)) {
      g.found = 0;
      return g;
    }
    for (var q = 0; q < g.states.length; ++q) {
      for (final t in enabled(g.states[q])) {
        final m = fire(g.states[q], t), key = m.join(',');
        var k = index[key];
        if (k == null) {
          if (g.states.length == limit) {
            g.aborted = true;
            return g;
          }
          k = g.states.length;
          index[key] = k;
          g.add(m, q, t);
          if (matches(m)) {
            g.found = k;
            return g;
          }
        }
        g.edges[q].add((t, k));
      }
    }
    return g;
  }

  List<int> path(Graph g, int k) {
    final a = <int>[];
    while (g.parent[k] >= 0) {
      a.add(g.via[k]);
      k = g.parent[k];
    }
    return a.reversed.toList();
  }

  void reach(int limit, bool display) {
    final g = graph(current, limit);
    if (g.aborted) {
      print('reachability graph limit $limit exceeded');
      return;
    }
    final n = g.states.length;
    if (display) {
      for (var i = 0; i < n; ++i) {
        final a = g.edges[i]
            .map((e) => '${transitions[e.$1]}->M${e.$2}')
            .toList();
        print('M$i ${mark(g.states[i])}: ${a.isEmpty ? 'dead' : a.join(' ')}');
      }
      return;
    }
    final adj = g.edges.map((e) => e.map((v) => v.$2).toList()).toList();
    final closure = [for (var i = 0; i < n; ++i) visit(adj, i)];
    final comp = List.filled(n, -1);
    var components = 0;
    for (var i = 0; i < n; ++i) {
      if (comp[i] < 0) {
        for (var j = i; j < n; ++j) {
          if (closure[i][j] && closure[j][i]) comp[j] = components;
        }
        ++components;
      }
    }
    final terminal = List.filled(components, true),
        home = List.filled(n, true),
        maximum = List.filled(places.length, 0),
        dead = <int>[];
    var edges = 0, persistent = true;
    for (var i = 0; i < n; ++i) {
      if (g.edges[i].isEmpty) dead.add(i);
      edges += g.edges[i].length;
      for (var p = 0; p < places.length; ++p) {
        maximum[p] = math.max(maximum[p], g.states[i][p]);
      }
      for (var j = 0; j < n; ++j) {
        home[j] = home[j] && closure[i][j];
      }
      for (final e in g.edges[i]) {
        if (comp[i] != comp[e.$2]) terminal[comp[i]] = false;
        for (final u in g.edges[i]) {
          if (e.$1 != u.$1 && reason(g.states[e.$2], u.$1) != null)
            persistent = false;
        }
      }
    }
    print(
      'reachable markings: $n\nedges: $edges\ncomponents: $components (terminal ${terminal.where((v) => v).length})\ndead markings: ${dead.length}',
    );
    for (final i in dead) {
      final a = names(path(g, i));
      print(
        '  M$i ${mark(g.states[i])} path ${a.isEmpty ? 'empty' : a.join(' ')}',
      );
    }
    final bound = maximum.reduce(math.max);
    print(
      'max tokens: ${mark(maximum)}\nbound: $bound\nsafe: ${yes(bound <= 1)}\nhome markings: ${home.where((v) => v).length}\nreversible: ${yes(home[0])}\npersistent: ${yes(persistent)}',
    );
    final levels = <String>[];
    for (var t = 0; t < transitions.length; ++t) {
      final present = List.filled(components, false);
      var used = false, cycle = false;
      for (var i = 0; i < n; ++i) {
        for (final e in g.edges[i]) {
          if (e.$1 == t) {
            used = true;
            present[comp[i]] = true;
            if (comp[i] == comp[e.$2]) cycle = true;
          }
        }
      }
      final live = [
        for (var c = 0; c < components; ++c) !terminal[c] || present[c],
      ].every((v) => v);
      levels.add(
        '${transitions[t]}=${live
            ? 'L4'
            : cycle
            ? 'L3'
            : used
            ? 'L1'
            : 'L0'}',
      );
    }
    print('liveness: ${levels.join(' ')}');
  }

  int rank(int v) => v < 0 ? 0x7fffffffffffffff : v;
  void cover(int limit) {
    final g = Graph()..add(List.of(current), -1, -1),
        old = [false],
        dead = [false],
        seen = {current.join(',')};
    for (var q = 0; q < g.states.length; ++q) {
      if (old[q]) continue;
      final es = enabled(g.states[q]);
      dead[q] = es.isEmpty;
      final ancestors = <int>[];
      for (var a = q; a >= 0; a = g.parent[a]) {
        ancestors.insert(0, a);
      }
      for (final t in es) {
        final m = fire(g.states[q], t);
        for (final a in ancestors) {
          var ge = true, gt = false;
          for (var p = 0; p < m.length; ++p) {
            ge = ge && rank(m[p]) >= rank(g.states[a][p]);
            gt = gt || rank(m[p]) > rank(g.states[a][p]);
          }
          if (ge && gt) {
            for (var p = 0; p < m.length; ++p) {
              if (capacity[p] == 0 && rank(m[p]) > rank(g.states[a][p]))
                m[p] = -1;
            }
          }
        }
        if (g.states.length == limit) {
          print('coverability tree limit $limit exceeded');
          return;
        }
        old.add(!seen.add(m.join(',')));
        dead.add(false);
        g.add(m, q, t);
      }
    }
    print('coverability tree nodes: ${g.states.length}');
    final maximum = List.filled(places.length, 0);
    for (var i = 0; i < g.states.length; ++i) {
      print(
        '  $i ${mark(g.states[i])} ${i == 0 ? 'root' : '<- ${g.parent[i]} ${transitions[g.via[i]]}'}${old[i] ? ' old' : ''}${dead[i] ? ' dead' : ''}',
      );
      for (var p = 0; p < places.length; ++p) {
        if (rank(g.states[i][p]) > rank(maximum[p]))
          maximum[p] = g.states[i][p];
      }
    }
    print(
      'bounds: ${mark(maximum)}\nunbounded: ${listed([for (var p = 0; p < places.length; ++p)
        if (maximum[p] < 0) places[p]])}',
    );
  }

  List<int> bits(int mask) => [
    for (var p = 0; p < places.length; ++p)
      if ((mask & 1 << p) != 0) p,
  ];
  List<int> sets(bool trap) {
    final found = <int>[];
    for (var mask = 1; mask < 1 << places.length; ++mask) {
      var valid = true;
      for (var t = 0; t < transitions.length; ++t) {
        final input = bits(mask).any((p) => post[p][t] > 0),
            output = bits(mask).any((p) => pre[p][t] > 0);
        if (trap ? output && !input : input && !output) {
          valid = false;
          break;
        }
      }
      if (valid) found.add(mask);
    }
    return found
        .where((m) => !found.any((s) => s != m && (s & m) == s))
        .toList()
      ..sort((a, b) {
        final x = bits(a), y = bits(b);
        return x.length != y.length ? x.length.compareTo(y.length) : lex(x, y);
      });
  }

  String setText(int mask) => '{${bits(mask).map((p) => places[p]).join(',')}}';
  List<int>? realize(List<int> counts) {
    final used = List.filled(counts.length, 0),
        stack = [current],
        choices = [0],
        path = <int>[],
        seen = <String>{},
        total = counts.fold(0, (a, b) => a + b);
    while (stack.isNotEmpty) {
      final d = path.length;
      if (d == total) return path;
      var chosen = -1;
      for (var t = choices[d]; t < counts.length; ++t) {
        choices[d] = t + 1;
        if (used[t] >= counts[t] || reason(stack[d], t) != null) continue;
        ++used[t];
        final fresh = seen.add(used.join(','));
        --used[t];
        if (fresh) {
          chosen = t;
          break;
        }
      }
      if (chosen >= 0) {
        ++used[chosen];
        path.add(chosen);
        stack.add(fire(stack[d], chosen));
        choices.add(0);
      } else {
        stack.removeLast();
        choices.removeLast();
        if (path.isNotEmpty) --used[path.removeLast()];
      }
    }
    return null;
  }

  void invariants(bool transpose) {
    final a = transpose
        ? [
            for (var t = 0; t < transitions.length; ++t)
              [for (var p = 0; p < places.length; ++p) post[p][t] - pre[p][t]],
          ]
        : [
            for (var p = 0; p < places.length; ++p)
              [
                for (var t = 0; t < transitions.length; ++t)
                  post[p][t] - pre[p][t],
              ],
          ];
    final f = flows(a),
        ns = transpose ? transitions : places,
        covered = List.filled((transpose ? transitions : places).length, false),
        bounds = List.filled((transpose ? transitions : places).length, -1);
    print('${transpose ? 'T' : 'P'}-semiflows: ${f.length}');
    for (final c in f) {
      final terms = [
        for (var i = 0; i < c.length; ++i)
          if (c[i] > 0) '${c[i] == 1 ? '' : '${c[i]}*'}${ns[i]}',
      ].join(' + ');
      for (var i = 0; i < c.length; ++i) {
        if (c[i] > 0) covered[i] = true;
      }
      if (transpose) {
        final path = realize(c);
        print(
          '  $terms: ${path == null ? 'not realizable' : 'realizable ${names(path).join(' ')}'}',
        );
      } else {
        var value = 0;
        for (var p = 0; p < c.length; ++p) {
          value += c[p] * current[p];
        }
        print('  $terms = $value');
        for (var p = 0; p < c.length; ++p) {
          if (c[p] > 0)
            bounds[p] = bounds[p] < 0
                ? value ~/ c[p]
                : math.min(bounds[p], value ~/ c[p]);
        }
      }
    }
    if (!transpose)
      print('bounds: (${bounds.map((v) => v < 0 ? '-' : '$v').join(',')})');
    print(
      '${transpose ? 'consistent' : 'conservative'}: ${yes(covered.every((v) => v))}',
    );
  }

  void classify() {
    final inputs = [
          for (var t = 0; t < transitions.length; ++t)
            [
              for (var p = 0; p < places.length; ++p)
                if (pre[p][t] > 0) p,
            ],
        ],
        outputs = [
          for (var p = 0; p < places.length; ++p)
            [
              for (var t = 0; t < transitions.length; ++t)
                if (pre[p][t] > 0) t,
            ],
        ];
    var ordinary = true, pure = true;
    for (var p = 0; p < places.length; ++p) {
      for (var t = 0; t < transitions.length; ++t) {
        ordinary = ordinary && pre[p][t] <= 1 && post[p][t] <= 1;
        pure = pure && (pre[p][t] == 0 || post[p][t] == 0);
      }
    }
    final sm =
        ordinary &&
        [
          for (var t = 0; t < transitions.length; ++t)
            inputs[t].length == 1 &&
                [
                      for (var p = 0; p < places.length; ++p)
                        if (post[p][t] > 0) p,
                    ].length ==
                    1,
        ].every((v) => v);
    final mg =
        ordinary &&
        [
          for (var p = 0; p < places.length; ++p)
            outputs[p].length == 1 &&
                [
                      for (var t = 0; t < transitions.length; ++t)
                        if (post[p][t] > 0) t,
                    ].length ==
                    1,
        ].every((v) => v);
    final fc =
            ordinary &&
            outputs.every(
              (a) => a.every((t) => a.length == 1 || inputs[t].length == 1),
            ),
        efc =
            ordinary &&
            outputs.every(
              (a) => outputs.every(
                (b) =>
                    !a.any(b.contains) ||
                    a.length == b.length && lex(a, b) == 0,
              ),
            );
    for (final (label, value) in [
      ('ordinary', ordinary),
      ('pure', pure),
      ('state machine', sm),
      ('marked graph', mg),
      ('free choice', fc),
      ('extended free choice', efc),
    ]) {
      print('$label: ${yes(value)}');
    }
    var verdict = !fc
        ? 'not applicable'
        : places.length > 12
        ? 'too many places'
        : 'holds';
    if (fc && places.length <= 12) {
      final traps = sets(true);
      for (final s in sets(false)) {
        if (!traps.any(
          (q) => (s & q) == q && bits(q).any((p) => current[p] > 0),
        )) {
          verdict = 'fails at ${setText(s)}';
          break;
        }
      }
    }
    print('commoner: $verdict');
  }

  void workflow(int limit) {
    final sources = [
          for (var p = 0; p < places.length; ++p)
            if ([for (var t = 0; t < transitions.length; ++t) post[p][t] == 0]
                .every((v) => v))
              p,
        ],
        sinks = [
          for (var p = 0; p < places.length; ++p)
            if ([for (var t = 0; t < transitions.length; ++t) pre[p][t] == 0]
                .every((v) => v))
              p,
        ];
    if (sources.length != 1) {
      print('workflow: no (${sources.length} source places)');
      return;
    }
    if (sinks.length != 1) {
      print('workflow: no (${sinks.length} sink places)');
      return;
    }
    final i = sources[0],
        o = sinks[0],
        P = places.length,
        ns = [...places, ...transitions],
        adj = List.generate(places.length + transitions.length, (_) => <int>[]),
        rev = List.generate(places.length + transitions.length, (_) => <int>[]);
    for (var p = 0; p < places.length; ++p) {
      for (var t = 0; t < transitions.length; ++t) {
        if (pre[p][t] > 0) {
          adj[p].add(P + t);
          rev[P + t].add(p);
        }
        if (post[p][t] > 0) {
          adj[P + t].add(p);
          rev[p].add(P + t);
        }
      }
    }
    final f = visit(adj, i), b = visit(rev, o);
    for (var v = 0; v < ns.length; ++v) {
      if (!f[v] || !b[v]) {
        print(
          'workflow: no (${ns[v]} is not on a path from ${places[i]} to ${places[o]})',
        );
        return;
      }
    }
    print('workflow: source ${places[i]} sink ${places[o]}');
    final start = List.filled(P, 0), goal = List.filled(P, 0);
    start[i] = 1;
    goal[o] = 1;
    final g = graph(start, limit);
    if (g.aborted) {
      print('reachability graph limit $limit exceeded');
      return;
    }
    final finish = g.states.indexWhere((m) => lex(m, goal) == 0),
        back = List.generate(g.states.length, (_) => <int>[]),
        used = List.filled(transitions.length, false);
    for (var u = 0; u < g.states.length; ++u) {
      for (final e in g.edges[u]) {
        back[e.$2].add(u);
        used[e.$1] = true;
      }
    }
    final option = finish >= 0 && visit(back, finish).every((v) => v),
        proper = g.states.every((m) => m[o] < 1 || lex(m, goal) == 0),
        live = used.every((v) => v);
    print(
      'option to complete: ${yes(option)}\nproper completion: ${yes(proper)}\nno dead transitions: ${yes(live)}\nsound: ${yes(option && proper && live)}',
    );
  }

  void execute(List<String> w) {
    const arity = {
      'MARKING': 0,
      'RESET': 0,
      'SET': 2,
      'ENABLED': 0,
      'FIRE': -1,
      'UNDO': 1,
      'SIMULATE': 3,
      'CONFLICTS': 0,
      'REACH': 1,
      'GRAPH': 1,
      'COVER': 1,
      'PATH': 2,
      'INCIDENCE': 0,
      'PINV': 0,
      'TINV': 0,
      'SIPHONS': 0,
      'TRAPS': 0,
      'CLASSIFY': 0,
      'WORKFLOW': 1,
      'SHOW': 0,
    };
    final cmd = w[0], expected = arity[w[0]];
    if (expected == null) bad('unknown command $cmd');
    if (expected < 0 ? w.length < 2 : w.length != expected + 1)
      bad('wrong number of arguments');
    final limit = ['REACH', 'GRAPH', 'COVER', 'PATH', 'WORKFLOW'].contains(cmd)
        ? number(w[1], 1, 2000) ?? bad('invalid limit ${w[1]}')
        : 0;
    switch (cmd) {
      case 'MARKING':
      case 'RESET':
        if (cmd == 'RESET') {
          current = List.of(initial);
          history.clear();
        }
        print('marking ${mark(current)}');
      case 'SET':
        final p = places.indexOf(w[1]);
        if (p < 0) bad('unknown place ${w[1]}');
        final v = number(w[2], 0, 999) ?? bad('invalid tokens ${w[2]}');
        if (capacity[p] > 0 && v > capacity[p])
          bad('tokens exceed capacity of ${w[1]}');
        current = List.of(current);
        current[p] = v;
        history.clear();
        print('marking ${mark(current)}');
      case 'ENABLED':
        print('enabled: ${listed(names(enabled(current)))}');
      case 'FIRE':
        final ts = [
          for (final name in w.skip(1))
            transitions.indexOf(name) >= 0
                ? transitions.indexOf(name)
                : bad('unknown transition $name'),
        ];
        for (var i = 0; i < ts.length; ++i) {
          final r = reason(current, ts[i]);
          if (r != null) {
            print(
              'step ${i + 1}: ${transitions[ts[i]]} not enabled ($r) at ${mark(current)}',
            );
            return;
          }
          commit(ts[i]);
        }
        print('fired ${ts.length} -> ${mark(current)}');
      case 'UNDO':
        final k = number(w[1], 1, 1000) ?? bad('invalid count ${w[1]}');
        if (k > history.length)
          bad('cannot undo $k: history size ${history.length}');
        current = history[history.length - k];
        history.removeRange(history.length - k, history.length);
        print('marking ${mark(current)}');
      case 'SIMULATE':
        final steps = number(w[1], 1, 1000) ?? bad('invalid steps ${w[1]}');
        var x = number(w[2], 1, 2147483646) ?? bad('invalid seed ${w[2]}');
        if (!['PRIORITY', 'RANDOM'].contains(w[3])) bad('invalid mode ${w[3]}');
        final counts = List.filled(transitions.length, 0);
        var done = 0;
        for (; done < steps; ++done) {
          final es = enabled(current);
          if (es.isEmpty) {
            print('dead (steps=$done)');
            break;
          }
          var t = es.first;
          if (w[3] == 'RANDOM') {
            x = x * 48271 % 2147483647;
            t = es[x % es.length];
          } else {
            for (final u in es) {
              if (priority[u] > priority[t]) t = u;
            }
          }
          commit(t);
          ++counts[t];
          print('step ${done + 1}: ${transitions[t]} -> ${mark(current)}');
        }
        if (done == steps) print('completed (steps=$steps)');
        print(
          'counts: ${[for (var t = 0; t < transitions.length; ++t) '${transitions[t]}=${counts[t]}'].join(' ')}',
        );
      case 'CONFLICTS':
        final s = <String>[], e = <String>[];
        for (var u = 0; u < transitions.length; ++u) {
          for (var v = u + 1; v < transitions.length; ++v) {
            final pair = '${transitions[u]}/${transitions[v]}';
            if ([
              for (var p = 0; p < places.length; ++p)
                pre[p][u] > 0 && pre[p][v] > 0,
            ].any((v) => v))
              s.add(pair);
            if (reason(current, u) == null &&
                reason(current, v) == null &&
                (reason(fire(current, u), v) != null ||
                    reason(fire(current, v), u) != null))
              e.add(pair);
          }
        }
        print('structural: ${listed(s)}\neffective: ${listed(e)}');
      case 'REACH':
      case 'GRAPH':
        reach(limit, cmd == 'GRAPH');
      case 'COVER':
        cover(limit);
      case 'PATH':
        final entries = w[2].split(',');
        if (entries.length != places.length)
          bad('target needs ${places.length} entries');
        final target = <(int, int)>[];
        for (final s in entries) {
          if (s == '*') {
            target.add((0, -1));
            continue;
          }
          final plus = s.endsWith('+'),
              v =
                  number(
                    plus ? s.substring(0, s.length - 1) : s,
                    0,
                    9999999999,
                  ) ??
                  bad('invalid target entry $s');
          target.add((v, plus ? -1 : v));
        }
        final g = graph(current, limit, target);
        if (g.found >= 0) {
          final a = names(path(g, g.found));
          print(
            'reached ${mark(g.states[g.found])} length=${a.length}${a.isEmpty ? '' : ': ${a.join(' ')}'}',
          );
        } else if (g.aborted) {
          print('search limit $limit exceeded');
        } else {
          print('unreachable (markings explored: ${g.states.length})');
        }
      case 'INCIDENCE':
        final rows = [
          ['', ...transitions],
          for (var p = 0; p < places.length; ++p)
            [
              places[p],
              for (var t = 0; t < transitions.length; ++t)
                '${post[p][t] - pre[p][t]}',
            ],
        ];
        final width = [
          for (var i = 0; i < rows.first.length; ++i)
            rows.map((r) => r[i].length).reduce(math.max),
        ];
        for (final r in rows) {
          print(
            [
              for (var i = 0; i < r.length; ++i)
                i == 0 ? r[i].padRight(width[i]) : r[i].padLeft(width[i]),
            ].join('  ').trimRight(),
          );
        }
      case 'PINV':
      case 'TINV':
        invariants(cmd == 'TINV');
      case 'SIPHONS':
      case 'TRAPS':
        if (places.length > 12) bad('more than 12 places');
        final ss = sets(cmd == 'TRAPS');
        print('minimal ${cmd == 'TRAPS' ? 'traps' : 'siphons'}: ${ss.length}');
        for (final s in ss) {
          print(
            '  ${setText(s)} tokens=${bits(s).fold(0, (sum, p) => sum + current[p])}',
          );
        }
      case 'CLASSIFY':
        classify();
      case 'WORKFLOW':
        workflow(limit);
      case 'SHOW':
        for (var p = 0; p < places.length; ++p) {
          print(
            'place ${places[p]} tokens=${initial[p]} capacity=${capacity[p] == 0 ? 'none' : capacity[p]}',
          );
        }
        for (var t = 0; t < transitions.length; ++t) {
          String list(List<List<int>> mat) {
            final a = [
              for (var p = 0; p < places.length; ++p)
                if (mat[p][t] > 0) '${places[p]}:${mat[p][t]}',
            ];
            return a.isEmpty ? '-' : a.join(',');
          }

          print(
            'transition ${transitions[t]} priority=${priority[t]} pre=${list(pre)} post=${list(post)} inhibit=${list(inhibitor)}',
          );
        }
    }
  }
}

void main() {
  final blocks = int.parse(stdin.readLineSync()!);
  for (var b = 0; b < blocks; ++b) {
    final n = Net(stdin.readLineSync()!.split(' ')[1]);
    while (true) {
      final line = stdin.readLineSync()!;
      if (line == 'END NET') break;
      try {
        n.define(line.split(' '));
      } on FormatException catch (e) {
        print('error: ${e.message}');
      }
    }
    n.current = List.of(n.initial);
    print(
      'net ${n.name}: places=${n.places.length} transitions=${n.transitions.length} arcs=${n.arcs} inhibitors=${n.inhibitors}',
    );
    final commands = int.parse(stdin.readLineSync()!);
    for (var i = 0; i < commands; ++i) {
      try {
        n.execute(stdin.readLineSync()!.split(' '));
      } on FormatException catch (e) {
        print('error: ${e.message}');
      }
    }
  }
}
