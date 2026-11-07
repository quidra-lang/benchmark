void main() {
  const initial = [
    '800025000',
    '070080005',
    '260400070',
    '000001900',
    '010000040',
    '600200000',
    '900010000',
    '700000004',
    '020000036',
  ];
  final board = initial.join().codeUnits.map((c) => c - 48).toList();
  var placements = 0;
  bool solve() {
    final cell = board.indexOf(0);
    if (cell < 0) return true;
    final r = cell ~/ 9, c = cell % 9;
    for (var digit = 1; digit <= 9; digit++) {
      var valid = true;
      for (var k = 0; k < 9; k++) {
        if (board[r * 9 + k] == digit ||
            board[k * 9 + c] == digit ||
            board[(r ~/ 3 * 3 + k ~/ 3) * 9 + c ~/ 3 * 3 + k % 3] == digit) {
          valid = false;
          break;
        }
      }
      if (valid) {
        board[cell] = digit;
        placements++;
        if (solve()) return true;
        board[cell] = 0;
      }
    }
    return false;
  }

  solve();
  for (var r = 0; r < 9; r++) {
    print(board.sublist(r * 9, r * 9 + 9).join(' '));
  }
  print('placements: $placements');
}
