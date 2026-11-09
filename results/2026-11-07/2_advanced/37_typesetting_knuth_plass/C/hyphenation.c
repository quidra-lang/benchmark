#include "typesetting.h"
void register_word(Dictionary *dictionary, const char *word) {
    Text key = {0};
    Ints points = {0};
    for (size_t i = 0; word[i]; ++i) {
        if (word[i] == '-')
            int_add(&points, (int)key.len);
        else
            text_add(&key, "%c", word[i]);
    }
    size_t index = 0;
    while (index < dictionary->len && strcmp(dictionary->data[index].word, key.data))
        ++index;
    if (index == dictionary->len) {
        grow((void **)&dictionary->data, &dictionary->cap, dictionary->len + 1, sizeof *dictionary->data);
        ++dictionary->len;
    }
    dictionary->data[index] = (DictionaryWord){key.data, points};
}
static void point_add(SplitPoints *points, int position, bool hyphen) {
    grow((void **)&points->data, &points->cap, points->len + 1, sizeof *points->data);
    points->data[points->len++] = (SplitPoint){position, hyphen};
}
static int point_compare(const void *pa, const void *pb) {
    const SplitPoint *a = pa, *b = pb;
    return a->position < b->position ? -1 : a->position > b->position;
}
SplitPoints split_points(const Dictionary *dictionary, const char *word, const Params *p) {
    SplitPoints out = {0};
    size_t first = 0, last = strlen(word);
    while (first < last && !letter(word[first]))
        ++first;
    while (last > first && !letter(word[last - 1]))
        --last;
    bool valid = first < last;
    for (size_t i = first; i < last; ++i)
        if (!letter(word[i]))
            valid = false;
    if (valid) {
        char *core = lower(format("%.*s", (int)(last - first), word + first));
        for (size_t i = 0; i < dictionary->len; ++i)
            if (!strcmp(dictionary->data[i].word, core)) {
                Ints points = dictionary->data[i].points;
                for (size_t j = 0; j < points.len; ++j)
                    if (points.data[j] >= p->left_min &&
                        (Integer)(last - first) - points.data[j] >= p->right_min)
                        point_add(&out, (int)first + points.data[j], true);
                break;
            }
    }
    size_t length = strlen(word);
    for (size_t i = 1; i + 1 < length; ++i)
        if (word[i] == '-' && letter(word[i - 1]) && letter(word[i + 1]))
            point_add(&out, (int)i + 1, false);
    qsort(out.data, out.len, sizeof *out.data, point_compare);
    return out;
}
