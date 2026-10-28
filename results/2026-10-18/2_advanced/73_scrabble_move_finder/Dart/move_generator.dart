part of 'main.dart';

class RawMove {
  final int row, col, direction;
  final String word;
  RawMove(this.row, this.col, this.direction, this.word);
}

class Check {
  final bool isCheck;
  int letters;
  Check(this.isCheck, this.letters);
}

class CrossStats {
  int squares = 0, empty = 0, letters = 0;
}

List<List<bool>> anchors(Board b) {
  final empty = tileCount(b) == 0;
  return [
    for (var r = 0; r < 15; r++)
      [
        for (var c = 0; c < 15; c++)
          b.cells[r][c] == '.' &&
              ((empty && r == center && c == center) ||
                  (!empty && adjacent(b, r, c))),
      ],
  ];
}

(List<List<Check>>, CrossStats) crossChecks(Board b, int direction, Trie trie) {
  final checks = List.generate(
        15,
        (_) => List.generate(15, (_) => Check(false, 0)),
      ),
      stats = CrossStats(),
      perpendicular = 1 - direction;
  final (dr, dc) = directions(perpendicular);
  for (var r = 0; r < 15; r++) {
    for (var c = 0; c < 15; c++) {
      if (b.cells[r][c] != '.') continue;
      final has =
          (inside(r - dr, c - dc) && b.cells[r - dr][c - dc] != '.') ||
          (inside(r + dr, c + dc) && b.cells[r + dr][c + dc] != '.');
      checks[r][c] = Check(has, has ? 0 : (1 << 26) - 1);
      if (!has) continue;
      stats.squares++;
      for (var letter = 0; letter < 26; letter++) {
        final after = b.copy();
        after.cells[r][c] = String.fromCharCode(65 + letter);
        if (trie.contains(wordAt(after, r, c, perpendicular).word)) {
          checks[r][c].letters |= 1 << letter;
          stats.letters++;
        }
      }
      if (checks[r][c].letters == 0) stats.empty++;
    }
  }
  return (checks, stats);
}

String placementKey(Board b, RawMove move) {
  final (dr, dc) = directions(move.direction);
  final s = StringBuffer();
  for (var i = 0; i < move.word.length; i++) {
    final r = move.row + i * dr, c = move.col + i * dc;
    if (b.cells[r][c] == '.')
      s.write('${(r * 15 + c).toString().padLeft(3, '0')}${move.word[i]}');
  }
  return s.toString();
}

List<RawMove> generateMoves(Board board, String rack, Trie trie) {
  final moves = <RawMove>[], seen = <String>{};
  for (var direction = 0; direction < 2; direction++) {
    final b = direction == 0 ? board : board.transpose(), anchor = anchors(b);
    final (checks, _) = crossChecks(b, 0, trie);
    for (var row = 0; row < 15; row++) {
      for (var col = 0; col < 15; col++) {
        if (!anchor[row][col]) continue;
        final counts = collectionCounts(rack);
        void record(int start, String word, int placed) {
          if (placed == 0 || word.length < 2) return;
          final move = direction == 0
              ? RawMove(row, start, 0, word)
              : RawMove(start, row, 1, word);
          if (placed == 1 && direction == 1) {
            final after = board.copy();
            final (dr, dc) = directions(direction);
            var newRow = 0, newCol = 0;
            for (var i = 0; i < word.length; i++) {
              final r = move.row + i * dr, c = move.col + i * dc;
              if (board.cells[r][c] == '.') {
                after.cells[r][c] = word[i];
                newRow = r;
                newCol = c;
              }
            }
            if (wordAt(after, newRow, newCol, 0).word.length >= 2) return;
          }
          final key = placementKey(board, move);
          if (seen.add(key)) moves.add(move);
        }

        void extend(
          int at,
          int start,
          int node,
          String word,
          int placed,
          bool filled,
        ) {
          if (at >= 15) {
            if (trie.nodes[node].terminal && filled)
              record(start, word, placed);
            return;
          }
          final tile = b.cells[row][at];
          if (tile != '.') {
            final next = trie
                .nodes[node]
                .children[tile.toUpperCase().codeUnitAt(0) - 65];
            if (next >= 0)
              extend(at + 1, start, next, word + tile, placed, filled);
            return;
          }
          if (trie.nodes[node].terminal && filled) record(start, word, placed);
          for (var letter = 0; letter < 26; letter++) {
            final next = trie.nodes[node].children[letter];
            if (next < 0 || ((checks[row][at].letters >> letter) & 1) == 0)
              continue;
            if (counts[letter] > 0) {
              counts[letter]--;
              extend(
                at + 1,
                start,
                next,
                word + String.fromCharCode(65 + letter),
                placed + 1,
                filled || at == col,
              );
              counts[letter]++;
            }
            if (counts[26] > 0) {
              counts[26]--;
              extend(
                at + 1,
                start,
                next,
                word + String.fromCharCode(97 + letter),
                placed + 1,
                filled || at == col,
              );
              counts[26]++;
            }
          }
        }

        if (col > 0 && b.cells[row][col - 1] != '.') {
          var start = col - 1;
          while (start > 0 && b.cells[row][start - 1] != '.') {
            start--;
          }
          final prefix = b.cells[row].sublist(start, col).join(),
              node = trie.find(prefix);
          if (node >= 0) extend(col, start, node, prefix, 0, false);
        } else {
          var limit = 0;
          for (
            var c = col - 1;
            c >= 0 && b.cells[row][c] == '.' && !anchor[row][c];
            c--
          ) {
            limit++;
          }
          void left(String prefix, int node, int length) {
            extend(col, col - length, node, prefix, length, false);
            if (length == limit) return;
            for (var letter = 0; letter < 26; letter++) {
              final next = trie.nodes[node].children[letter];
              if (next < 0) continue;
              if (counts[letter] > 0) {
                counts[letter]--;
                left(
                  prefix + String.fromCharCode(65 + letter),
                  next,
                  length + 1,
                );
                counts[letter]++;
              }
              if (counts[26] > 0) {
                counts[26]--;
                left(
                  prefix + String.fromCharCode(97 + letter),
                  next,
                  length + 1,
                );
                counts[26]++;
              }
            }
          }

          left('', 0, 0);
        }
      }
    }
  }
  return moves;
}
