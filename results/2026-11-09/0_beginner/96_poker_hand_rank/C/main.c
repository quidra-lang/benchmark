#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    const char *text;
    int category, key[5], length;
} Hand;

Hand evaluate(const char *text) {
    const char *ranks = "23456789TJQKA";
    int counts[15] = {0}, flush = 1;
    for (int i = 0; i < 5; i++) {
        int rank = (int)(strchr(ranks, text[i * 3]) - ranks) + 2;
        counts[rank]++;
        if (text[i * 3 + 1] != text[1])
            flush = 0;
    }
    Hand h = {text, 0, {0}, 0};
    int maximum = 0, pairs = 0;
    for (int r = 14; r >= 2; r--)
        if (counts[r]) {
            h.key[h.length++] = r;
            if (counts[r] > maximum)
                maximum = counts[r];
            if (counts[r] == 2)
                pairs++;
        }
    int wheel = h.length == 5 && counts[14] && counts[2] && counts[3] && counts[4] && counts[5];
    int straight = h.length == 5 && (h.key[0] - h.key[4] == 4 || wheel);
    h.category = straight && flush ? 8
               : maximum == 4 ? 7
               : maximum == 3 && pairs == 1 ? 6
               : flush ? 5
               : straight ? 4
               : maximum == 3 ? 3
               : pairs == 2 ? 2
               : pairs == 1 ? 1 : 0;
    h.length = 0;
    for (int count = 4; count >= 1; count--)
        for (int rank = 14; rank >= 2; rank--)
            if (counts[rank] == count)
                h.key[h.length++] = rank;
    if (wheel && straight)
        for (int i = 0; i < 5; i++)
            h.key[i] = 5 - i;
    return h;
}

int compare(const void *a, const void *b) {
    const Hand *x = a, *y = b;
    if (x->category != y->category)
        return y->category - x->category;
    for (int i = 0; i < 5; i++)
        if (x->key[i] != y->key[i])
            return y->key[i] - x->key[i];
    return 0;
}

int main(void) {
    const char *input[] = {"9C 9D 5H QH 2C", "4D AH 3C 5S 2H", "KS 8S 2S JS 6S", "7H 7D KC 7S KD",
        "3H 6C 4S 2D 5C", "JD TC 4H 8C AS", "QC 6D QS 3S 6H", "9H KH 9S 8H 3D"};
    const char *categories[] = {"high card", "one pair", "two pair", "three of a kind", "straight", "flush",
        "full house", "four of a kind", "straight flush"};
    Hand hands[8];
    for (int i = 0; i < 8; i++)
        hands[i] = evaluate(input[i]);
    qsort(hands, 8, sizeof(Hand), compare);
    for (int i = 0; i < 8; i++)
        printf("%d. %s: %s\n", i + 1, hands[i].text, categories[hands[i].category]);
    return 0;
}
