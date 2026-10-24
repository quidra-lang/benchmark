void main() {
    final words = 'we planted beans and carrots in the garden behind our old house'.split(' ');
    final longest = words.reduce((a, b) => a.length >= b.length ? a : b);
    final shortest = words.reduce((a, b) => a.length <= b.length ? a : b);
    final total = words.fold(0, (sum, word) => sum + word.length);
    final average = total / words.length;
    print('words: ${words.length}');
    print('longest: $longest');
    print('shortest: $shortest');
    print('average length: ${average.toStringAsFixed(2)}');
}
