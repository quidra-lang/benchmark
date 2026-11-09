void main() {
  for (final text in [
    'AAABBBCCCD',
    'WWWWWWWWWWWWBWWWWWWWWWWWWBBB',
    'ALGORITHM',
    'MISSISSIPPI',
    'XXXXXXXXXXYYYYYYYYYYYYYYYYYYYYYZ',
  ]) {
    final encoded = RegExp(r'([A-Z])\1*')
        .allMatches(text)
        .map((run) => '${run[0]!.length}${run[1]}')
        .join();
    final decoded = RegExp(r'(\d+)([A-Z])')
        .allMatches(encoded)
        .map((run) => run[2]! * int.parse(run[1]!))
        .join();
    print('$text -> $encoded -> $decoded');
  }
}
