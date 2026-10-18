import 'dart:io';

void main() {
    final out = StringBuffer();
    const ranks = 'A23456789TJQK', suits = 'SHDC';
    final deck = [for (var i = 0; i < 52; i++) '${ranks[i%13]}${suits[i~/13]}'];
    var state = 2026;
    for (var i = 51; i > 0; i--) {
        state = (state * 48271) % 2147483647;
        final j = state % (i + 1), temp = deck[i];
        deck[i] = deck[j];
        deck[j] = temp;
    }
    for (var i = 0; i < 52; i += 13)
        out.writeln(deck.sublist(i, i + 13).join(' '));
    stdout.write(out);
}
