part of 'main.dart';

class Branch {
  final int u, v, mask;
  Branch(this.u, this.v, this.mask);
}

(int, int) merge(int a, int b) => (a & b) != 0 ? (a & b, 0) : (a | b, 1);
(Map<int, int>, int, int) provisional(
  Tree t,
  List<SequenceRecord> taxa,
  int outgroup,
  int column,
) {
  final r = rootTree(t, taxa, outgroup), sets = <int, int>{};
  var changes = 0;
  int visit(int v) {
    if (v < taxa.length) return sets[v] = baseSets[taxa[v].sequence[column]]!;
    final parts = [
      for (final c in r.children[v]!)
        if (v != r.root || c != outgroup) visit(c),
    ];
    final (s, delta) = merge(parts[0], parts[1]);
    changes += delta;
    sets[v] = s;
    return s;
  }

  final rootSet = visit(r.root);
  sets[outgroup] = baseSets[taxa[outgroup].sequence[column]]!;
  final (combined, delta) = merge(rootSet, sets[outgroup]!);
  changes += delta;
  return (sets, changes, combined);
}

int parsimonyScore(
  Tree t,
  List<SequenceRecord> taxa,
  int outgroup,
  int length,
) {
  var score = 0;
  for (var col = 0; col < length; col++) {
    score += provisional(t, taxa, outgroup, col).$2;
  }
  return score;
}

int firstBase(int mask) {
  for (var b = 1; b <= 8; b <<= 1) {
    if ((mask & b) != 0) return b;
  }
  return 1;
}

(Tree, Map<int, String>, Map<int, int>, List<int>) reconstruct(
  Tree t,
  List<SequenceRecord> taxa,
  int outgroup,
  int length,
) {
  final r = rootTree(t, taxa, outgroup),
      seq = <int, String>{},
      changes = <int, int>{},
      columns = List.filled(length, 0);
  for (var col = 0; col < length; col++) {
    final (sets, n, combined) = provisional(t, taxa, outgroup, col);
    columns[col] = n;
    final state = <int, int>{}, x0 = firstBase(combined);
    state[r.root] = (sets[r.root]! & x0) != 0 ? x0 : firstBase(sets[r.root]!);
    state[outgroup] = (sets[outgroup]! & x0) != 0
        ? x0
        : firstBase(sets[outgroup]!);
    void assign(int v) {
      for (final c in r.children[v] ?? <int>[]) {
        if (c == outgroup) continue;
        state[c] = (sets[c]! & state[v]!) != 0
            ? state[v]!
            : firstBase(sets[c]!);
        assign(c);
      }
    }

    assign(r.root);
    for (final entry in r.masks.entries) {
      final v = entry.key, mask = entry.value;
      if (v >= taxa.length) {
        final base = {1: 'A', 2: 'C', 4: 'G', 8: 'T'}[state[v]]!;
        seq[mask] = (seq[mask] ?? '') + base;
      }
      if (v != r.root) {
        final branchMask = v == outgroup ? r.all : mask;
        if (state[v] != state[r.parent[v]])
          changes[branchMask] = (changes[branchMask] ?? 0) + 1;
      }
    }
  }
  final result = t.copy();
  for (final b in branches(t, taxa, outgroup)) {
    result.adj[b.u]![b.v] = (changes[b.mask] ?? 0) / length;
    result.adj[b.v]![b.u] = result.adj[b.u]![b.v]!;
  }
  return (result, seq, changes, columns);
}

List<Branch> branches(Tree t, List<SequenceRecord> taxa, int outgroup) {
  final r = rootTree(t, taxa, outgroup);
  return [
    for (final entry in r.parent.entries)
      if (entry.key != r.root)
        Branch(
          entry.value,
          entry.key,
          entry.key == outgroup ? r.all : r.masks[entry.key]!,
        ),
  ]..sort((a, b) => a.mask.compareTo(b.mask));
}

Tree insertion(Tree t, Branch b, int x) {
  final v = t.copy(), w = t.next;
  v.next++;
  v.disconnect(b.u, b.v);
  v.connect(b.u, w, 0);
  v.connect(b.v, w, 0);
  v.connect(w, x, 0);
  return v;
}

Tree nni(Tree t, Branch b, int swap, List<SequenceRecord> taxa, int outgroup) {
  final r = rootTree(t, taxa, outgroup), u = b.u, v = b.v;
  final s = r.children[u]!.firstWhere((c) => c != v && c != outgroup),
      children = List.of(r.children[v]!)
        ..sort((a, b) => r.masks[a]!.compareTo(r.masks[b]!));
  final c = children[swap - 1], result = t.copy();
  result.disconnect(u, s);
  result.disconnect(v, c);
  result.connect(u, c, 0);
  result.connect(v, s, 0);
  return result;
}
