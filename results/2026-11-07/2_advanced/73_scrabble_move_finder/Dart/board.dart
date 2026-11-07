part of 'main.dart';

const boardSize = 15, center = 7;
const premiums = [
  '#..+...#...+..#',
  '.*...^...^...*.',
  '..*...+.+...*..',
  '+..*...+...*..+',
  '....*.....*....',
  '.^...^...^...^.',
  '..+...+.+...+..',
  '#..+...*...+..#',
  '..+...+.+...+..',
  '.^...^...^...^.',
  '....*.....*....',
  '+..*...+...*..+',
  '..*...+.+...*..',
  '.*...^...^...*.',
  '#..+...#...+..#',
];

class Board {
  final List<List<String>> cells;
  Board(this.cells);
  Board.empty() : cells = List.generate(15, (_) => List.filled(15, '.'));
  Board copy() => Board(cells.map((row) => List<String>.of(row)).toList());
  Board transpose() => Board([
    for (var r = 0; r < 15; r++) [for (var c = 0; c < 15; c++) cells[c][r]],
  ]);
}

class BoardWord {
  final int row, col, direction;
  final String word;
  BoardWord(this.row, this.col, this.direction, this.word);
}

bool inside(int r, int c) => r >= 0 && r < 15 && c >= 0 && c < 15;
String squareName(int r, int c) => '${String.fromCharCode(65 + c)}${r + 1}';
String positionName(int r, int c, int direction) => direction == 0
    ? '${r + 1}${String.fromCharCode(65 + c)}'
    : squareName(r, c);
(int, int, int)? parsePosition(String s) {
  if (s.length < 2) return null;
  final first = s.codeUnitAt(0), last = s.codeUnitAt(s.length - 1);
  if (first >= 65 && first <= 79) {
    final row = validNumber(s.substring(1), 1, 15);
    return row == null ? null : (row - 1, first - 65, 1);
  }
  if (last < 65 || last > 79) return null;
  final row = validNumber(s.substring(0, s.length - 1), 1, 15);
  return row == null ? null : (row - 1, last - 65, 0);
}

List<(int, int)> transposeSquares(List<(int, int)> a) => [
  for (final (r, c) in a) (c, r),
];
(int, int) directions(int direction) => direction == 0 ? (0, 1) : (1, 0);
List<BoardWord> boardWords(Board b) {
  final words = <BoardWord>[];
  for (var direction = 0; direction < 2; direction++) {
    for (var fixed = 0; fixed < 15; fixed++) {
      for (var start = 0; start < 15;) {
        final r = direction == 0 ? fixed : start,
            c = direction == 0 ? start : fixed;
        if (b.cells[r][c] == '.') {
          start++;
          continue;
        }
        var end = start;
        final word = StringBuffer();
        while (end < 15) {
          final rr = direction == 0 ? fixed : end,
              cc = direction == 0 ? end : fixed;
          if (b.cells[rr][cc] == '.') break;
          word.write(b.cells[rr][cc]);
          end++;
        }
        if (end - start >= 2)
          words.add(BoardWord(r, c, direction, word.toString()));
        start = end;
      }
    }
  }
  return words;
}

BoardWord wordAt(Board b, int r, int c, int direction) {
  final (dr, dc) = directions(direction);
  while (inside(r - dr, c - dc) && b.cells[r - dr][c - dc] != '.') {
    r -= dr;
    c -= dc;
  }
  final row = r, col = c, word = StringBuffer();
  while (inside(r, c) && b.cells[r][c] != '.') {
    word.write(b.cells[r][c]);
    r += dr;
    c += dc;
  }
  return BoardWord(row, col, direction, word.toString());
}

bool adjacent(Board b, int r, int c) {
  for (final (dr, dc) in [(-1, 0), (1, 0), (0, -1), (0, 1)]) {
    final rr = r + dr, cc = c + dc;
    if (inside(rr, cc) && b.cells[rr][cc] != '.') return true;
  }
  return false;
}

int tileCount(Board b) =>
    b.cells.expand((r) => r).where((c) => c != '.').length;
bool connected(Board b) {
  final queue = <(int, int)>[];
  for (var r = 0; r < 15 && queue.isEmpty; r++) {
    for (var c = 0; c < 15; c++) {
      if (b.cells[r][c] != '.') {
        queue.add((r, c));
        break;
      }
    }
  }
  if (queue.isEmpty) return true;
  final seen = {queue[0]};
  for (var pos = 0; pos < queue.length; pos++) {
    final (r, c) = queue[pos];
    for (final (dr, dc) in [(-1, 0), (1, 0), (0, -1), (0, 1)]) {
      final q = (r + dr, c + dc);
      if (inside(q.$1, q.$2) && b.cells[q.$1][q.$2] != '.' && seen.add(q))
        queue.add(q);
    }
  }
  return seen.length == tileCount(b);
}

List<String> display(Board b) => [
  '   A B C D E F G H I J K L M N O',
  for (var r = 0; r < 15; r++)
    '${(r + 1).toString().padLeft(2)} ${[for (var c = 0; c < 15; c++) b.cells[r][c] == '.' ? premiums[r][c] : b.cells[r][c]].join(' ')}',
];
