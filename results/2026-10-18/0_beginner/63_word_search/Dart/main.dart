void main() {
  const board = [
    'MMONKENBIR',
    'PMTIGERJPL',
    'TGREJEDUZI',
    'SPYUTEJDEC',
    'WKAPSIDLBN',
    'KUVNGSBPRO',
    'RIBSDACBAM',
    'YWVAUAPKAH',
    'KYCGTHHESR',
    'OCCALAOKKR',
  ];
  const directions = [
    (0, 1),
    (1, 1),
    (1, 0),
    (1, -1),
    (0, -1),
    (-1, -1),
    (-1, 0),
    (-1, 1),
  ];
  const names = ['E', 'SE', 'S', 'SW', 'W', 'NW', 'N', 'NE'];
  for (final word in ['TIGER', 'ZEBRA', 'MONKEY', 'PANDA', 'KOALA', 'RABBIT']) {
    var found = false;
    search:
    for (var r = 0; r < 10; r++) {
      for (var c = 0; c < 10; c++) {
        for (var d = 0; d < 8; d++) {
          var matches = true;
          for (var k = 0; k < word.length; k++) {
            final rr = r + directions[d].$1 * k, cc = c + directions[d].$2 * k;
            if (rr < 0 ||
                rr >= 10 ||
                cc < 0 ||
                cc >= 10 ||
                board[rr][cc] != word[k]) {
              matches = false;
              break;
            }
          }
          if (matches) {
            print('$word: ($r, $c) ${names[d]}');
            found = true;
            break search;
          }
        }
      }
    }
    if (!found) print('$word: not found');
  }
}
