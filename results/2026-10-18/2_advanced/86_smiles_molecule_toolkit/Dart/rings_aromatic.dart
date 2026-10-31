part of 'main.dart';

class RingCandidate {
  final List<int> atoms;
  final BigInt bonds;
  RingCandidate(this.atoms, this.bonds);
}

List<int> canonicalRing(List<int> ring) {
  var first = 0;
  for (var i = 0; i < ring.length; i++) {
    if (ring[i] < ring[first]) first = i;
  }
  final direction =
      ring[(first + 1) % ring.length] >
          ring[(first + ring.length - 1) % ring.length]
      ? -1
      : 1;
  return [
    for (var i = 0; i < ring.length; i++)
      ring[(first + direction * i + ring.length) % ring.length],
  ];
}

void detectRings(Molecule m) {
  final n = m.atoms.length,
      candidates = <RingCandidate>[],
      seen = <BigInt>{},
      bondIndex = {
        for (var e = 0; e < m.bonds.length; e++)
          (m.bonds[e].a, m.bonds[e].b): e,
      };
  for (var root = 0; root < n; root++) {
    final parent = List.filled(n, -2), queue = [root];
    parent[root] = -1;
    for (var h = 0; h < queue.length; h++) {
      final a = queue[h];
      for (final e in m.adjacent[a]) {
        final b = m.bonds[e].other(a);
        if (parent[b] == -2) {
          parent[b] = a;
          queue.add(b);
        }
      }
    }
    List<int> path(int a) {
      final out = <int>[];
      while (a >= 0) {
        out.add(a);
        a = parent[a];
      }
      return out;
    }

    for (final bond in m.bonds) {
      if (parent[bond.a] == bond.b || parent[bond.b] == bond.a) continue;
      final px = path(bond.a),
          py = path(bond.b),
          set = px.take(px.length - 1).toSet();
      if (py.take(py.length - 1).any(set.contains)) continue;
      final atoms = [...px.reversed, ...py.take(py.length - 1)];
      var vector = BigInt.zero;
      for (var i = 0; i < atoms.length; i++) {
        final a = min(atoms[i], atoms[(i + 1) % atoms.length]),
            b = max(atoms[i], atoms[(i + 1) % atoms.length]);
        vector |= BigInt.one << bondIndex[(a, b)]!;
      }
      if (seen.add(vector)) candidates.add(RingCandidate(atoms, vector));
    }
  }
  final ordered = List.generate(candidates.length, (i) => i)
    ..sort((a, b) {
      final c = candidates[a].atoms.length.compareTo(
        candidates[b].atoms.length,
      );
      return c != 0 ? c : a.compareTo(b);
    });
  final basis = <int, BigInt>{};
  m.ringAtoms = List.filled(n, false);
  for (final i in ordered) {
    final candidate = candidates[i];
    var reduced = candidate.bonds;
    while (reduced != BigInt.zero) {
      final pivot = reduced.bitLength - 1, old = basis[reduced.bitLength - 1];
      if (old != null) {
        reduced ^= old;
      } else {
        basis[pivot] = reduced;
        m.rings.add(canonicalRing(candidate.atoms));
        for (final a in candidate.atoms) {
          m.ringAtoms[a] = true;
        }
        for (var e = 0; e < m.bonds.length; e++) {
          if ((candidate.bonds & (BigInt.one << e)) != BigInt.zero)
            m.bonds[e].ring = true;
        }
        break;
      }
    }
  }
  m.rings.sort((a, b) {
    final c = a.length.compareTo(b.length);
    return c != 0 ? c : compareInts(a, b);
  });
}

ParseError? kekulize(Molecule m, Map<String, Element> elements) {
  final need = [
        for (var i = 0; i < m.atoms.length; i++) m.needsPi(i, elements, true),
      ],
      seen = List.filled(m.atoms.length, false),
      paired = List.filled(m.atoms.length, -1);
  for (var first = 0; first < m.atoms.length; first++) {
    if (!need[first] || seen[first]) continue;
    final system = [first];
    seen[first] = true;
    for (var h = 0; h < system.length; h++) {
      final u = system[h];
      for (final e in m.adjacent[u]) {
        final b = m.bonds[e], v = b.other(u);
        if (b.type == 4 && need[v] && !seen[v]) {
          seen[v] = true;
          system.add(v);
        }
      }
    }
    system.sort();
    final member = system.toSet();
    bool match() {
      var u = -1;
      for (final a in system) {
        if (paired[a] < 0) {
          u = a;
          break;
        }
      }
      if (u < 0) return true;
      for (final e in m.adjacent[u]) {
        final bond = m.bonds[e], v = bond.other(u);
        if (bond.type != 4 || !member.contains(v) || paired[v] >= 0) continue;
        paired[u] = v;
        paired[v] = u;
        if (match()) return true;
        paired[u] = -1;
        paired[v] = -1;
      }
      return false;
    }

    if (!match())
      return ParseError('kekulization failed', m.atoms[first].column);
  }
  for (final b in m.bonds) {
    b.multiplicity = b.type == 4 ? (paired[b.a] == b.b ? 2 : 1) : b.type;
  }
  return null;
}
