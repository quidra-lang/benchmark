void main() {
  final counts = List.filled(5, 0);
  const letters = 'ABCDF';
  for (final score in [78, 90, 100, 59, 80, 85, 89, 70, 45, 93]) {
    final grade = switch (score) {
      >= 90 => 0,
      >= 80 => 1,
      >= 70 => 2,
      >= 60 => 3,
      _ => 4,
    };
    counts[grade]++;
    print('$score: ${letters[grade]}');
  }
  for (var i = 0; i < 5; i++) {
    print('${letters[i]}: ${counts[i]}');
  }
}
