part of 'main.dart';

const rackSize = 7, bingoBonus = 50;

class PlacedTile {
  final int row, col;
  final String letter;
  PlacedTile(this.row, this.col, this.letter);
}

class ScoredWord {
  final BoardWord boardWord;
  final int score;
  ScoredWord(this.boardWord, this.score);
}

class Move {
  final RawMove raw;
  int score = 0, tiles = 0, leaveValue = 0, rank = 0;
  String leave = '';
  final List<ScoredWord> words = [];
  final List<PlacedTile> placed = [];
  Move(this.raw);
}

List<(int, int)> moveSquares(RawMove move) {
  final (dr, dc) = directions(move.direction);
  return [
    for (var i = 0; i < move.word.length; i++)
      (move.row + i * dr, move.col + i * dc),
  ];
}

int wordScore(BoardWord word, Set<(int, int)> newTiles, Tiles tiles) {
  final (dr, dc) = directions(word.direction);
  var sum = 0, multiplier = 1;
  for (var i = 0; i < word.word.length; i++) {
    final r = word.row + i * dr,
        c = word.col + i * dc,
        code = word.word.codeUnitAt(i);
    var value = code >= 65 && code <= 90 ? tiles.value[code - 65] : 0;
    if (newTiles.contains((r, c))) {
      switch (premiums[r][c]) {
        case '+':
          value *= 2;
          break;
        case '^':
          value *= 3;
          break;
        case '*':
          multiplier *= 2;
          break;
        case '#':
          multiplier *= 3;
          break;
      }
    }
    sum += value;
  }
  return sum * multiplier;
}

Move evaluateMove(Board board, String rack, RawMove raw, Tiles tiles) {
  final m = Move(raw),
      after = board.copy(),
      newTiles = <(int, int)>{},
      counts = collectionCounts(rack),
      squares = moveSquares(raw);
  for (var i = 0; i < squares.length; i++) {
    final (r, c) = squares[i];
    if (board.cells[r][c] == '.') {
      final letter = raw.word[i];
      m.placed.add(PlacedTile(r, c, letter));
      newTiles.add((r, c));
      after.cells[r][c] = letter;
      counts[tileIndex(letter)]--;
    }
  }
  final words = [BoardWord(raw.row, raw.col, raw.direction, raw.word)];
  for (final tile in m.placed) {
    final word = wordAt(after, tile.row, tile.col, 1 - raw.direction);
    if (word.word.length >= 2) words.add(word);
  }
  for (final word in words) {
    final score = wordScore(word, newTiles, tiles);
    m.score += score;
    m.words.add(ScoredWord(word, score));
  }
  m.tiles = m.placed.length;
  if (m.tiles == rackSize) m.score += bingoBonus;
  m.leave = countsString(counts);
  return m;
}

void play(Board board, Move move) {
  for (final tile in move.placed) {
    board.cells[tile.row][tile.col] = tile.letter;
  }
}

String wordList(Move move) =>
    move.words.map((w) => '${w.boardWord.word}:${w.score}').join(',');
