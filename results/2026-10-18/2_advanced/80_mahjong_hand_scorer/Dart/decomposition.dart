part of 'main.dart';

class Block {
  final int kind;
  final bool sequence, kan, winning;
  final String source;
  Block(
    this.kind, {
    this.sequence = false,
    this.kan = false,
    this.source = 'concealed',
    this.winning = false,
  });
  String notation() => blockNotation(kind, kan ? 4 : 3, sequence);
  Block won() =>
      Block(kind, sequence: sequence, kan: kan, source: source, winning: true);
}

class Decomposition {
  final int pair;
  final List<Block> sets;
  Decomposition(this.pair, this.sets);
}

List<Decomposition> standardDecompositions(List<int> original, int melds) {
  final counts = List<int>.of(original),
      out = <Decomposition>[],
      seen = <String>{},
      needed = 4 - melds;
  for (var pair = 0; pair < 34; pair++) {
    if (counts[pair] < 2) continue;
    counts[pair] -= 2;
    void search(List<Block> sets) {
      final first = counts.indexWhere((c) => c > 0);
      if (first < 0) {
        if (sets.length != needed) return;
        final blocks = List<Block>.of(sets)
              ..sort((a, b) {
                final difference = a.kind.compareTo(b.kind);
                return difference != 0
                    ? difference
                    : (a.sequence ? 1 : 0).compareTo(b.sequence ? 1 : 0);
              }),
            key =
                '${tileName(pair)} ${blocks.map((b) => b.notation()).join(' ')}';
        if (seen.add(key)) out.add(Decomposition(pair, blocks));
        return;
      }
      if (sets.length >= needed) return;
      if (counts[first] >= 3) {
        counts[first] -= 3;
        search([...sets, Block(first)]);
        counts[first] += 3;
      }
      if (first < 27 &&
          first % 9 <= 6 &&
          counts[first + 1] > 0 &&
          counts[first + 2] > 0) {
        counts[first]--;
        counts[first + 1]--;
        counts[first + 2]--;
        search([...sets, Block(first, sequence: true)]);
        counts[first]++;
        counts[first + 1]++;
        counts[first + 2]++;
      }
    }

    search([]);
    counts[pair] += 2;
  }
  return out;
}

bool sevenPairs(List<int> a, int melds) =>
    melds == 0 &&
    a.where((n) => n == 2).length == 7 &&
    a.every((n) => n == 0 || n == 2);
bool thirteenOrphans(List<int> a, int melds) =>
    melds == 0 &&
    a.fold(0, (s, n) => s + n) == 14 &&
    List.generate(
      34,
      (kind) => yaochuu(kind) ? a[kind] > 0 : a[kind] == 0,
    ).every((v) => v);
bool winningForm(List<int> a, int melds) =>
    sevenPairs(a, melds) ||
    thirteenOrphans(a, melds) ||
    standardDecompositions(a, melds).isNotEmpty;
List<int> waitingTiles(Tiles hand, List<Meld> melds) {
  final counts = List<int>.of(hand.counts),
      all = combineTiles([hand, ...melds.map((m) => m.tiles)]),
      out = <int>[];
  for (var kind = 0; kind < 34; kind++) {
    if (all.counts[kind] >= 4) continue;
    counts[kind]++;
    if (winningForm(counts, melds.length)) out.add(kind);
    counts[kind]--;
  }
  return out;
}

String waitShape(Block b, int win) {
  if (!b.sequence) return 'shanpon';
  final rank = win - b.kind;
  if (rank == 1) return 'kanchan';
  if (b.kind % 9 == 0 && rank == 2 || b.kind % 9 == 6 && rank == 0)
    return 'penchan';
  return 'ryanmen';
}
