void main() {
    const text = 'The cat sat on the mat. The dog sat on the rug, and the cat watched the dog. A bird sang on the fence, and the Dog barked at the bird. The cat slept in the sun, the bird flew away, and the dog sat by the door.';
    final counts = <String, int>{};
    for (final match in RegExp('[a-z]+').allMatches(text.toLowerCase())) {
        final word = match.group(0)!;
        counts[word] = (counts[word] ?? 0) + 1;
    }
    final words = counts.keys.toList()..sort((a, b) {
        final c = counts[b]!.compareTo(counts[a]!);
        return c != 0 ? c : a.compareTo(b);
    });
    for (final word in words.take(5))
        print('$word: ${counts[word]}');
    print('distinct words: ${counts.length}');
}
