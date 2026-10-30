#include "chemistry.h"
#include <stdlib.h>
#include <string.h>

static const IntList *dense_values;
static int value_compare(const void *left, const void *right) {
    int a = *(const int *)left, b = *(const int *)right;
    const IntList *x = &dense_values[a], *y = &dense_values[b];
    int count = x->count < y->count ? x->count : y->count;
    for (int i = 0; i < count; ++i)
        if (x->items[i] != y->items[i])
            return x->items[i] < y->items[i] ? -1 : 1;
    return (x->count > y->count) - (x->count < y->count);
}
static int *dense(const IntList *values, int count) {
    int *order = allocate((size_t)count * sizeof(int)),
        *ranks = allocate((size_t)count * sizeof(int));
    for (int i = 0; i < count; ++i)
        order[i] = i;
    dense_values = values;
    qsort(order, (size_t)count, sizeof(int), value_compare);
    int rank = 0;
    for (int i = 0; i < count; ++i) {
        if (!i || value_compare(&order[i - 1], &order[i]))
            ++rank;
        ranks[order[i]] = rank;
    }
    free(order);
    return ranks;
}
static int rank_count(const int *ranks, int count) {
    int maximum = 0;
    for (int i = 0; i < count; ++i)
        if (ranks[i] > maximum)
            maximum = ranks[i];
    return maximum;
}
static void values_free(IntList *values, int count) {
    for (int i = 0; i < count; ++i)
        ints_free(&values[i]);
    free(values);
}
static int *refine(const Molecule *m, int *ranks) {
    int n = m->atom_count;
    for (;;) {
        IntList *values = allocate((size_t)n * sizeof(IntList));
        memset(values, 0, (size_t)n * sizeof(IntList));
        for (int a = 0; a < n; ++a) {
            IntList neighbors = ints_copy(&m->adjacent[a]);
            for (int i = 1; i < neighbors.count; ++i) {
                int edge = neighbors.items[i], j = i;
                Bond b = m->bonds[edge];
                while (j) {
                    Bond old = m->bonds[neighbors.items[j - 1]];
                    int x = ranks[bond_other(&b, a)], y = ranks[bond_other(&old, a)];
                    if (x > y || (x == y && b.type >= old.type))
                        break;
                    neighbors.items[j] = neighbors.items[j - 1];
                    --j;
                }
                neighbors.items[j] = edge;
            }
            ints_add(&values[a], ranks[a]);
            for (int i = 0; i < neighbors.count; ++i) {
                Bond b = m->bonds[neighbors.items[i]];
                ints_add(&values[a], ranks[bond_other(&b, a)]);
                ints_add(&values[a], b.type);
            }
            ints_free(&neighbors);
        }
        int *next = dense(values, n);
        values_free(values, n);
        bool stable = rank_count(next, n) == rank_count(ranks, n);
        free(ranks);
        ranks = next;
        if (stable)
            return ranks;
    }
}
void canonical_ranks(Molecule *m, const Elements *elements) {
    int n = m->atom_count;
    IntList *values = allocate((size_t)n * sizeof(IntList));
    memset(values, 0, (size_t)n * sizeof(IntList));
    for (int a = 0; a < n; ++a) {
        Atom atom = m->atoms[a];
        int invariant[] = {m->adjacent[a].count,
                           elements->items[atom.element].number,
                           atom.mass,
                           atom.charge,
                           atom.hydrogens,
                           atom.aromatic};
        for (int i = 0; i < 6; ++i)
            ints_add(&values[a], invariant[i]);
    }
    int *ranks = refine(m, dense(values, n));
    values_free(values, n);
    m->classes = rank_count(ranks, n);
    while (rank_count(ranks, n) < n) {
        int *counts = allocate((size_t)(n + 1) * sizeof(int));
        memset(counts, 0, (size_t)(n + 1) * sizeof(int));
        for (int a = 0; a < n; ++a)
            ++counts[ranks[a]];
        int smallest = 1;
        while (counts[smallest] < 2)
            ++smallest;
        int chosen = 0;
        while (ranks[chosen] != smallest)
            ++chosen;
        free(counts);
        values = allocate((size_t)n * sizeof(IntList));
        memset(values, 0, (size_t)n * sizeof(IntList));
        for (int a = 0; a < n; ++a)
            ints_add(&values[a], 2 * ranks[a] - (a == chosen));
        int *next = dense(values, n);
        values_free(values, n);
        free(ranks);
        ranks = refine(m, next);
    }
    m->ranks = ranks;
}
static bool symbol_in(const char *symbol, const char *const *list, int count) {
    for (int i = 0; i < count; ++i)
        if (strcmp(symbol, list[i]) == 0)
            return true;
    return false;
}
static char *atom_notation(const Molecule *m, int index, const Elements *elements) {
    Atom atom = m->atoms[index];
    const char *original = elements->items[atom.element].symbol;
    char symbol[3];
    strcpy(symbol, original);
    if (atom.aromatic)
        for (char *p = symbol; *p; ++p)
            if (*p >= 'A' && *p <= 'Z')
                *p = (char)(*p - 'A' + 'a');
    static const char *const organic[] = {"B", "C", "N", "O", "P", "S", "F", "Cl", "Br", "I"},
                             *const aromatic[] = {"B", "C", "N", "O", "P", "S"};
    int hydrogens;
    bool possible = organic_hydrogens(m, index, elements, &hydrogens);
    if (symbol_in(original, organic, 10) && (!atom.aromatic || symbol_in(original, aromatic, 6)) &&
        !atom.mass && !atom.charge &&
        (!atom.aromatic ||
         needs_pi(m, index, elements, true) == needs_pi(m, index, elements, false)) &&
        possible && hydrogens == atom.hydrogens)
        return copy_text(symbol);
    Text out = {0};
    text_add(&out, "[");
    if (atom.mass)
        text_format(&out, "%d", atom.mass);
    text_add(&out, symbol);
    if (atom.hydrogens) {
        text_add(&out, "H");
        if (atom.hydrogens >= 2)
            text_format(&out, "%d", atom.hydrogens);
    }
    if (atom.charge) {
        text_add(&out, atom.charge > 0 ? "+" : "-");
        if (abs(atom.charge) >= 2)
            text_format(&out, "%d", abs(atom.charge));
    }
    text_add(&out, "]");
    return text_take(&out);
}
static const char *bond_notation(const Molecule *m, const Bond *bond) {
    bool in_ring = m->atoms[bond->a].aromatic && m->atoms[bond->b].aromatic && bond->ring;
    if (bond->type == 1)
        return in_ring ? "-" : "";
    if (bond->type == 2)
        return "=";
    if (bond->type == 3)
        return "#";
    return in_ring ? "" : ":";
}
typedef struct {
    const Molecule *m;
    const Elements *elements;
    bool *visited, *used;
    int *visit_order, *classification, *assignments, serial;
    IntList *children;
    Text output;
} Writer;
static void visit(Writer *s, int atom, int parent) {
    s->visited[atom] = true;
    s->visit_order[atom] = ++s->serial;
    IntList neighbors = ints_copy(&s->m->adjacent[atom]);
    for (int i = 1; i < neighbors.count; ++i) {
        int edge = neighbors.items[i], j = i;
        while (j && s->m->ranks[bond_other(&s->m->bonds[neighbors.items[j - 1]], atom)] >
                        s->m->ranks[bond_other(&s->m->bonds[edge], atom)]) {
            neighbors.items[j] = neighbors.items[j - 1];
            --j;
        }
        neighbors.items[j] = edge;
    }
    for (int i = 0; i < neighbors.count; ++i) {
        int edge = neighbors.items[i];
        if (edge == parent || s->classification[edge] == 2)
            continue;
        int next = bond_other(&s->m->bonds[edge], atom);
        if (!s->visited[next]) {
            s->classification[edge] = 1;
            ints_add(&s->children[atom], edge);
            visit(s, next, edge);
        } else
            s->classification[edge] = 2;
    }
    ints_free(&neighbors);
}
static void number_text(Text *out, int number) {
    if (number < 10)
        text_format(out, "%d", number);
    else
        text_format(out, "%%%02d", number);
}
static void write_atom(Writer *s, int atom) {
    char *notation = atom_notation(s->m, atom, s->elements);
    text_add(&s->output, notation);
    free(notation);
    IntList closures = {0};
    for (int i = 0; i < s->m->adjacent[atom].count; ++i) {
        int edge = s->m->adjacent[atom].items[i];
        if (s->classification[edge] == 2)
            ints_add(&closures, edge);
    }
    for (int i = 1; i < closures.count; ++i) {
        int edge = closures.items[i], j = i;
        while (j && s->visit_order[bond_other(&s->m->bonds[closures.items[j - 1]], atom)] >
                        s->visit_order[bond_other(&s->m->bonds[edge], atom)]) {
            closures.items[j] = closures.items[j - 1];
            --j;
        }
        closures.items[j] = edge;
    }
    for (int i = 0; i < closures.count; ++i) {
        int edge = closures.items[i], number = s->assignments[edge];
        if (number) {
            number_text(&s->output, number);
            s->used[number] = false;
            s->assignments[edge] = 0;
        } else {
            number = 1;
            while (s->used[number])
                ++number;
            s->used[number] = true;
            s->assignments[edge] = number;
            text_add(&s->output, bond_notation(s->m, &s->m->bonds[edge]));
            number_text(&s->output, number);
        }
    }
    ints_free(&closures);
    for (int i = 0; i < s->children[atom].count; ++i) {
        int edge = s->children[atom].items[i];
        bool branch = i + 1 < s->children[atom].count;
        if (branch)
            text_add(&s->output, "(");
        text_add(&s->output, bond_notation(s->m, &s->m->bonds[edge]));
        write_atom(s, bond_other(&s->m->bonds[edge], atom));
        if (branch)
            text_add(&s->output, ")");
    }
}
char *canonical_smiles(const Molecule *m, const Elements *elements) {
    int n = m->atom_count, b = m->bond_count, start = 0;
    while (m->ranks[start] != 1)
        ++start;
    Writer s = {.m = m, .elements = elements};
    s.visited = allocate((size_t)n * sizeof(bool));
    memset(s.visited, 0, (size_t)n * sizeof(bool));
    s.used = allocate((size_t)(b + 2) * sizeof(bool));
    memset(s.used, 0, (size_t)(b + 2) * sizeof(bool));
    s.visit_order = allocate((size_t)n * sizeof(int));
    s.classification = allocate((size_t)b * sizeof(int));
    memset(s.classification, 0, (size_t)b * sizeof(int));
    s.assignments = allocate((size_t)b * sizeof(int));
    memset(s.assignments, 0, (size_t)b * sizeof(int));
    s.children = allocate((size_t)n * sizeof(IntList));
    memset(s.children, 0, (size_t)n * sizeof(IntList));
    visit(&s, start, -1);
    write_atom(&s, start);
    for (int i = 0; i < n; ++i)
        ints_free(&s.children[i]);
    free(s.children);
    free(s.visited);
    free(s.used);
    free(s.visit_order);
    free(s.classification);
    free(s.assignments);
    return text_take(&s.output);
}
