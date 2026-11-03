part of 'main.dart';

class Tile {
  final int kind;
  final bool red;
  Tile(this.kind, [this.red = false]);
}

class Tiles {
  final List<Tile> tiles = [];
  final counts = List.filled(34, 0), reds = List.filled(3, 0);
}

(Tiles, bool) parseTiles(String s, bool allowEmpty) {
  final out = Tiles();
  if (s == '-' && allowEmpty) return (out, true);
  if (s.isEmpty || s == '-') return (out, false);
  var i = 0;
  while (i < s.length) {
    final start = i;
    while (i < s.length && s.codeUnitAt(i) >= 48 && s.codeUnitAt(i) <= 57) {
      i++;
    }
    if (i == start || i == s.length) return (out, false);
    final suit = 'mpsz'.indexOf(s[i]);
    if (suit < 0) return (out, false);
    for (final c in s.substring(start, i).codeUnits) {
      var rank = c - 48;
      final red = rank == 0;
      if (suit == 3) {
        if (rank < 1 || rank > 7) return (out, false);
      } else if (red) {
        rank = 5;
      }
      final kind = 9 * suit + rank - 1;
      out.tiles.add(Tile(kind, red));
      out.counts[kind]++;
      if (red) out.reds[suit]++;
    }
    i++;
  }
  return (out, true);
}

String tileName(int kind) => '${kind % 9 + 1}${'mpsz'[kind ~/ 9]}';
String blockNotation(int kind, int size, bool sequence) =>
    '${[for (var i = 0; i < size; i++) kind % 9 + 1 + (sequence ? i : 0)].join()}${'mpsz'[kind ~/ 9]}';
bool honor(int kind) => kind >= 27;
bool terminal(int kind) => kind < 27 && (kind % 9 == 0 || kind % 9 == 8);
bool yaochuu(int kind) => honor(kind) || terminal(kind);
int nextDora(int kind) => kind < 27
    ? kind ~/ 9 * 9 + (kind % 9 + 1) % 9
    : kind < 31
    ? 27 + (kind - 27 + 1) % 4
    : 31 + (kind - 31 + 1) % 3;
Tiles combineTiles(List<Tiles> groups) {
  final out = Tiles();
  for (final group in groups) {
    out.tiles.addAll(group.tiles);
    for (var i = 0; i < 34; i++) {
      out.counts[i] += group.counts[i];
    }
    for (var i = 0; i < 3; i++) {
      out.reds[i] += group.reds[i];
    }
  }
  return out;
}
