class Hand {
    final String original;
    final int category;
    final List<int> sequence;
    Hand(this.original, this.category, this.sequence);
}

Hand evaluate(String original) {
    final cards = original.split(' '), counts = List.filled(15, 0);
    int rank(String c) => '23456789TJQKA'.indexOf(c) + 2;
    for (final card in cards)
        counts[rank(card[0])]++;
    final flush = cards.every((c) => c[1] == cards.first[1]), ascending = [for (var r = 2; r <= 14; r++) if (counts[r] > 0) r];
    final wheel = ascending.length == 5 && [14, 2, 3, 4, 5].every((r) => counts[r] == 1), straight = ascending.length == 5
        && (wheel || ascending.last - ascending.first == 4);
    final pairs = counts.where((c) => c == 2).length, triple = counts.contains(3), four = counts.contains(4);
    final sequence = ascending..sort((a, b) {
        final c = counts[b].compareTo(counts[a]);
        return c != 0 ? c : b.compareTo(a);
    });
    if (wheel) {
        sequence.clear();
        sequence.addAll([5, 4, 3, 2, 1]);
    }
    final category = straight && flush ? 8 : four ? 7 : triple && pairs == 1 ? 6 : flush ? 5 : straight ? 4 : triple ? 3 : pairs == 2 ? 2 : pairs == 1 ? 1 : 0;
    return Hand(original, category, sequence);
}

void main() {
    final hands = ['9C 9D 5H QH 2C', '4D AH 3C 5S 2H', 'KS 8S 2S JS 6S', '7H 7D KC 7S KD', '3H 6C 4S 2D 5C',
        'JD TC 4H 8C AS', 'QC 6D QS 3S 6H', '9H KH 9S 8H 3D'].map(evaluate).toList()..sort((a, b) {
        var c = b.category.compareTo(a.category);
        if (c != 0)
            return c;
        for (var i = 0; i < a.sequence.length; i++) {
            c = b.sequence[i].compareTo(a.sequence[i]);
            if (c != 0)
                return c;
        }
        return 0;
    });
    const categories = ['high card', 'one pair', 'two pair', 'three of a kind', 'straight', 'flush',
        'full house', 'four of a kind', 'straight flush'];
    for (var i = 0; i < hands.length; i++) {
        final hand = hands[i];
        print('${i+1}. ${hand.original}: ${categories[hand.category]}');
    }
}
