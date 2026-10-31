void main() {
  const boards = [
    ['XXX', 'OO.', 'O.X'],
    ['X.O', '.X.', 'O..'],
    ['XO.', '.OX', 'XO.'],
    ['XOX', 'XOO', 'OXX'],
    ['X.O', 'XO.', 'O.X'],
    ['XOX', 'OXO', 'OXX'],
  ];
  const lines = [
    [0, 1, 2],
    [3, 4, 5],
    [6, 7, 8],
    [0, 3, 6],
    [1, 4, 7],
    [2, 5, 8],
    [0, 4, 8],
    [2, 4, 6],
  ];
  for (var i = 0; i < boards.length; i++) {
    final cells = boards[i].join();
    var winner = '.';
    for (final line in lines) {
      final mark = cells[line[0]];
      if (mark != '.' && mark == cells[line[1]] && mark == cells[line[2]]) {
        winner = mark;
        break;
      }
    }
    final result = winner == 'X'
        ? 'X wins'
        : winner == 'O'
        ? 'O wins'
        : cells.contains('.')
        ? 'in progress'
        : 'draw';
    print('board ${i + 1}: $result');
  }
}
