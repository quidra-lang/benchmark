void main() {
    final counts = List.filled(5, 0);
    const letters = 'ABCDF';
    for (final score in [78, 90, 100, 59, 80, 85, 89, 70, 45, 93]) {
        final grade = score >= 90 ? 0 : score >= 80 ? 1 : score >= 70 ? 2 : score >= 60 ? 3 : 4;
        counts[grade]++;
        print('$score: ${letters[grade]}');
    }
    for (var i = 0; i < 5; i++)
        print('${letters[i]}: ${counts[i]}');
}
