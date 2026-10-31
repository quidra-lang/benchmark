#include "chemistry.h"
#include <stdlib.h>
#include <string.h>

const char *pattern_atom(const char *source, size_t at, const Elements *elements, Atom *atom,
                         size_t *next) {
    *atom = (Atom){0};
    char c = source[at];
    if (c == '*' || c == 'A' || c == 'a') {
        atom->wildcard = c;
        *next = at + 1;
        return NULL;
    }
    if (c == '[') {
        const char *end = strchr(source + at + 1, ']');
        if (!end)
            return "unclosed bracket";
        size_t size = (size_t)(end - (source + at + 1));
        char *content = allocate(size + 1);
        memcpy(content, source + at + 1, size);
        content[size] = 0;
        Words parts = split(content, ',');
        free(content);
        for (size_t i = 0; i < parts.count; ++i) {
            Atom choice;
            size_t finish;
            if (!*parts.items[i] || !organic_atom(parts.items[i], 0, elements, &choice, &finish) ||
                finish != strlen(parts.items[i])) {
                words_free(&parts);
                return "bad bracket atom";
            }
            atom->choices =
                resize(atom->choices, (size_t)(atom->choice_count + 1) * sizeof(Choice));
            atom->choices[atom->choice_count++] = (Choice){choice.element, choice.aromatic};
        }
        words_free(&parts);
        *next = (size_t)(end - source) + 1;
        return NULL;
    }
    if (!organic_atom(source, at, elements, atom, next))
        return "unexpected character";
    atom->choices = allocate(sizeof(Choice));
    atom->choices[0] = (Choice){atom->element, atom->aromatic};
    atom->choice_count = 1;
    return NULL;
}
static bool atom_matches(const Atom *pattern, const Atom *atom) {
    if (pattern->wildcard == '*')
        return true;
    if (pattern->wildcard == 'A')
        return !atom->aromatic;
    if (pattern->wildcard == 'a')
        return atom->aromatic;
    for (int i = 0; i < pattern->choice_count; ++i)
        if (pattern->choices[i].element == atom->element &&
            pattern->choices[i].aromatic == atom->aromatic)
            return true;
    return false;
}
Molecule *molecule_pattern(const Molecule *m) {
    Molecule *pattern = molecule_new();
    for (int i = 0; i < m->atom_count; ++i) {
        Atom atom = {.choice_count = 1, .choices = allocate(sizeof(Choice))};
        atom.choices[0] = (Choice){m->atoms[i].element, m->atoms[i].aromatic};
        molecule_add_atom(pattern, atom);
    }
    for (int e = 0; e < m->bond_count; ++e) {
        Bond b = m->bonds[e];
        molecule_add_bond(pattern, (Bond){.a = b.a, .b = b.b, .match = 1 << b.type});
    }
    molecule_build(pattern);
    return pattern;
}
typedef struct {
    uint64_t words[2];
} AtomSet;
typedef struct {
    const Molecule *pattern, *molecule;
    int *mapping;
    bool *used;
    Embeddings result;
    AtomSet *sets;
    size_t count, capacity;
} Search;
static void search(Search *s, int index) {
    if (index == s->pattern->atom_count) {
        ++s->result.count;
        if (!s->result.first.count)
            for (int i = 0; i < s->pattern->atom_count; ++i)
                ints_add(&s->result.first, s->mapping[i] + 1);
        AtomSet set = {{0}};
        for (int i = 0; i < s->pattern->atom_count; ++i)
            set.words[s->mapping[i] / 64] |= UINT64_C(1) << (s->mapping[i] % 64);
        if (s->count == s->capacity) {
            s->capacity = s->capacity ? 2 * s->capacity : 64;
            s->sets = resize(s->sets, s->capacity * sizeof(AtomSet));
        }
        s->sets[s->count++] = set;
        return;
    }
    for (int candidate = 0; candidate < s->molecule->atom_count; ++candidate) {
        if (s->used[candidate] ||
            !atom_matches(&s->pattern->atoms[index], &s->molecule->atoms[candidate]))
            continue;
        bool valid = true;
        for (int i = 0; i < s->pattern->adjacent[index].count; ++i) {
            const Bond *bond = &s->pattern->bonds[s->pattern->adjacent[index].items[i]];
            int other = bond_other(bond, index);
            if (other >= index)
                continue;
            const Bond *actual = molecule_bond(s->molecule, candidate, s->mapping[other]);
            if (!actual || !(bond->match & (1 << actual->type))) {
                valid = false;
                break;
            }
        }
        if (valid) {
            s->mapping[index] = candidate;
            s->used[candidate] = true;
            search(s, index + 1);
            s->used[candidate] = false;
            s->mapping[index] = -1;
        }
    }
}
static int set_compare(const void *left, const void *right) {
    const AtomSet *a = left, *b = right;
    for (int i = 0; i < 2; ++i)
        if (a->words[i] != b->words[i])
            return a->words[i] < b->words[i] ? -1 : 1;
    return 0;
}
Embeddings embeddings(const Molecule *pattern, const Molecule *molecule) {
    if (pattern->atom_count > molecule->atom_count)
        return (Embeddings){0};
    Search s = {.pattern = pattern, .molecule = molecule};
    s.mapping = allocate((size_t)pattern->atom_count * sizeof(int));
    for (int i = 0; i < pattern->atom_count; ++i)
        s.mapping[i] = -1;
    s.used = allocate((size_t)molecule->atom_count * sizeof(bool));
    memset(s.used, 0, (size_t)molecule->atom_count * sizeof(bool));
    search(&s, 0);
    if (s.count)
        qsort(s.sets, s.count, sizeof(AtomSet), set_compare);
    for (size_t i = 0; i < s.count; ++i)
        if (!i || set_compare(&s.sets[i - 1], &s.sets[i]))
            ++s.result.unique;
    free(s.mapping);
    free(s.used);
    free(s.sets);
    return s.result;
}
typedef struct {
    Molecule *m;
    int *codes;
    bool *visited;
} Fingerprint;
static void path_visit(Fingerprint *s, int atom, int depth, int hash) {
    ++s->m->paths;
    s->m->bits[(hash % 1024) / 64] |= UINT64_C(1) << ((hash % 1024) % 64);
    if (depth == 5)
        return;
    for (int i = 0; i < s->m->adjacent[atom].count; ++i) {
        Bond bond = s->m->bonds[s->m->adjacent[atom].items[i]];
        int next = bond_other(&bond, atom);
        if (s->visited[next])
            continue;
        int value = (hash * 31 + bond.type) % 1000003;
        value = (value * 31 + s->codes[next]) % 1000003;
        s->visited[next] = true;
        path_visit(s, next, depth + 1, value);
        s->visited[next] = false;
    }
}
static int bit_count(uint64_t value) {
    int count = 0;
    while (value) {
        value &= value - 1;
        ++count;
    }
    return count;
}
void fingerprint(Molecule *m, const Elements *elements) {
    Fingerprint s = {.m = m,
                     .codes = allocate((size_t)m->atom_count * sizeof(int)),
                     .visited = allocate((size_t)m->atom_count * sizeof(bool))};
    memset(s.visited, 0, (size_t)m->atom_count * sizeof(bool));
    for (int i = 0; i < m->atom_count; ++i)
        s.codes[i] = 16 * elements->items[m->atoms[i].element].number +
                     (m->atoms[i].aromatic ? 8 : 0) + m->adjacent[i].count;
    for (int i = 0; i < m->atom_count; ++i) {
        s.visited[i] = true;
        path_visit(&s, i, 0, s.codes[i]);
        s.visited[i] = false;
    }
    for (int i = 0; i < 16; ++i)
        m->bit_count += bit_count(m->bits[i]);
    free(s.codes);
    free(s.visited);
}
Fraction fraction(int n, int d) {
    int a = n, b = d;
    while (b) {
        int remainder = a % b;
        a = b;
        b = remainder;
    }
    return (Fraction){n / a, d / a};
}
int fraction_compare(Fraction a, Fraction b) {
    int left = a.n * b.d, right = b.n * a.d;
    return (left > right) - (left < right);
}
char *fraction_text(Fraction f, char out[32]) {
    snprintf(out, 32, "%d/%d", f.n, f.d);
    return out;
}
Similarity similarity(const Molecule *a, const Molecule *b) {
    int common = 0, total = 0;
    for (int i = 0; i < 16; ++i) {
        common += bit_count(a->bits[i] & b->bits[i]);
        total += bit_count(a->bits[i] | b->bits[i]);
    }
    return (Similarity){fraction(common, total), common, total};
}
