String square(String key) {
  final visited = <String>{};
  final result = StringBuffer();
  final source = key;
  final alphabet = source.toUpperCase().replaceAll('J', 'I') + 'ABCDEFGHIKLMNOPQRSTUVWXYZ';
  for (var i = 0; i < alphabet.length; i++) {
    final char = alphabet[i];
    if (visited.add(char)) result.write(char);
  }
  return result.toString();
}

bool validPlayfair(String text) {
  final normalized = text.replaceAll('J', 'I');
  if (normalized.length.isOdd) return false;
  for (var i = 0; i < normalized.length; i += 2) {
    if (normalized[i] == normalized[i + 1]) return false;
  }
  return true;
}

String preparePlayfair(String text) {
  final normalized = text.replaceAll('J', 'I');
  final result = StringBuffer();
  var index = 0;
  while (index < normalized.length) {
    final first = normalized[index];
    final String second;
    if (index + 1 < normalized.length && normalized[index + 1] != first) {
      second = normalized[index + 1];
      index += 2;
    } else {
      second = first == 'X' ? 'Q' : 'X';
      index++;
    }
    result.write(first);
    result.write(second);
  }
  return result.toString();
}

String playfair(String text, String key, bool encrypt) {
  final board = square(key);
  final input = encrypt ? preparePlayfair(text) : text.replaceAll('J', 'I');
  final distance = encrypt ? 1 : 4;
  final result = StringBuffer();
  for (var i = 0; i < input.length; i += 2) {
    final a = board.indexOf(input[i]);
    final b = board.indexOf(input[i + 1]);
    var ra = a ~/ 5;
    var rb = b ~/ 5;
    var ca = a % 5;
    var cb = b % 5;
    if (ra == rb) {
      ca = (ca + distance) % 5;
      cb = (cb + distance) % 5;
    } else if (ca == cb) {
      ra = (ra + distance) % 5;
      rb = (rb + distance) % 5;
    } else {
      final temp = ca;
      ca = cb;
      cb = temp;
    }
    result.write(board[5 * ra + ca]);
    result.write(board[5 * rb + cb]);
  }
  return result.toString();
}
