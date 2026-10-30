#include "scrabble.h"
static int add_node(Trie *trie) {
    if (trie->count == trie->capacity) {
        trie->capacity = trie->capacity ? 2 * trie->capacity : 128;
        trie->nodes = realloc(trie->nodes, (size_t)trie->capacity * sizeof *trie->nodes);
    }
    int index = trie->count++;
    for (int i = 0; i < 26; ++i)
        trie->nodes[index].children[i] = -1;
    trie->nodes[index].terminal = false;
    return index;
}
void trie_init(Trie *trie) {
    memset(trie, 0, sizeof *trie);
    add_node(trie);
}
bool trie_add(Trie *trie, const char *word) {
    int node = 0;
    for (const char *p = word; *p; ++p) {
        int letter = *p - 'A', child = trie->nodes[node].children[letter];
        if (child < 0) {
            child = add_node(trie);
            trie->nodes[node].children[letter] = child;
        }
        node = child;
    }
    if (trie->nodes[node].terminal)
        return false;
    trie->nodes[node].terminal = true;
    ++trie->words;
    return true;
}
int trie_prefix(const Trie *trie, const char *word) {
    int node = 0;
    while (*word) {
        node = trie->nodes[node].children[*word++ - 'A'];
        if (node < 0)
            break;
    }
    return node;
}
bool trie_contains(const Trie *trie, const char *word) {
    int node = trie_prefix(trie, word);
    return node >= 0 && trie->nodes[node].terminal;
}
static void visit(const Trie *trie, int node, Counts counts, char word[16], int length,
                  Lines *out) {
    if (trie->nodes[node].terminal)
        add_line(out, "%s", word);
    for (int letter = 0; letter < 26; ++letter) {
        int child = trie->nodes[node].children[letter];
        if (child < 0)
            continue;
        int tile = counts[letter] ? letter : 26;
        if (counts[tile]) {
            --counts[tile];
            word[length] = (char)('A' + letter);
            word[length + 1] = 0;
            visit(trie, child, counts, word, length + 1, out);
            word[length] = 0;
            ++counts[tile];
        }
    }
}
Lines trie_anagrams(const Trie *trie, const char *rack) {
    Counts counts = {0};
    for (const char *p = rack; *p; ++p)
        ++counts[tile_index(*p)];
    Lines out = {0};
    char word[16] = {0};
    visit(trie, 0, counts, word, 0, &out);
    return out;
}
