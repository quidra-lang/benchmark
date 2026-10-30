#include "chemistry.h"
#include <stdlib.h>
#include <string.h>
void ints_add(IntList *list, int value) {
    if (list->count == list->capacity) {
        list->capacity = list->capacity ? 2 * list->capacity : 8;
        list->items = resize(list->items, (size_t)list->capacity * sizeof(int));
    }
    list->items[list->count++] = value;
}
IntList ints_copy(const IntList *list) {
    IntList out = {0};
    if (list->count) {
        out.count = out.capacity = list->count;
        out.items = allocate((size_t)list->count * sizeof(int));
        memcpy(out.items, list->items, (size_t)list->count * sizeof(int));
    }
    return out;
}
void ints_free(IntList *list) {
    free(list->items);
    *list = (IntList){0};
}
static int int_compare(const void *left, const void *right) {
    int a = *(const int *)left, b = *(const int *)right;
    return (a > b) - (a < b);
}
void ints_sort(IntList *list) {
    if (list->count)
        qsort(list->items, (size_t)list->count, sizeof(int), int_compare);
}
bool ints_contains(const IntList *list, int value) {
    for (int i = 0; i < list->count; ++i)
        if (list->items[i] == value)
            return true;
    return false;
}
int element_index(const Elements *elements, const char *symbol) {
    for (int i = 0; i < elements->count; ++i)
        if (strcmp(elements->items[i].symbol, symbol) == 0)
            return i;
    return -1;
}
void read_elements(Elements *elements) {
    *elements = (Elements){0};
    Lines source = read_lines("input/elements.txt");
    for (size_t i = 0; i < source.count; ++i) {
        if (ignored(source.items[i]))
            continue;
        Words a = split(source.items[i], ' '), valences = split(a.items[3], ',');
        Element *element = &elements->items[elements->count++];
        strcpy(element->symbol, a.items[0]);
        element->number = atoi(a.items[1]);
        element->weight = atoi(a.items[2]);
        for (size_t j = 0; j < valences.count; ++j)
            element->valences[element->valence_count++] = atoi(valences.items[j]);
        words_free(&a);
        words_free(&valences);
    }
    lines_free(&source);
}
int bond_other(const Bond *bond, int atom) { return atom == bond->a ? bond->b : bond->a; }
Molecule *molecule_new(void) {
    Molecule *m = allocate(sizeof(*m));
    memset(m, 0, sizeof(*m));
    return m;
}
void molecule_add_atom(Molecule *m, Atom atom) {
    if (m->atom_count == m->atom_capacity) {
        m->atom_capacity = m->atom_capacity ? 2 * m->atom_capacity : 16;
        m->atoms = resize(m->atoms, (size_t)m->atom_capacity * sizeof(Atom));
    }
    m->atoms[m->atom_count++] = atom;
}
void molecule_add_bond(Molecule *m, Bond bond) {
    if (m->bond_count == m->bond_capacity) {
        m->bond_capacity = m->bond_capacity ? 2 * m->bond_capacity : 16;
        m->bonds = resize(m->bonds, (size_t)m->bond_capacity * sizeof(Bond));
    }
    m->bonds[m->bond_count++] = bond;
}
static int bond_compare(const void *left, const void *right) {
    const Bond *a = left, *b = right;
    return a->a != b->a ? (a->a > b->a) - (a->a < b->a) : (a->b > b->b) - (a->b < b->b);
}
void molecule_build(Molecule *m) {
    if (m->bond_count)
        qsort(m->bonds, (size_t)m->bond_count, sizeof(Bond), bond_compare);
    m->adjacent = allocate((size_t)m->atom_count * sizeof(IntList));
    memset(m->adjacent, 0, (size_t)m->atom_count * sizeof(IntList));
    for (int e = 0; e < m->bond_count; ++e) {
        ints_add(&m->adjacent[m->bonds[e].a], e);
        ints_add(&m->adjacent[m->bonds[e].b], e);
    }
    for (int a = 0; a < m->atom_count; ++a) {
        IntList *list = &m->adjacent[a];
        for (int i = 1; i < list->count; ++i) {
            int edge = list->items[i], j = i;
            while (j &&
                   bond_other(&m->bonds[list->items[j - 1]], a) > bond_other(&m->bonds[edge], a)) {
                list->items[j] = list->items[j - 1];
                --j;
            }
            list->items[j] = edge;
        }
    }
}
const Bond *molecule_bond(const Molecule *m, int a, int b) {
    for (int i = 0; i < m->adjacent[a].count; ++i) {
        const Bond *bond = &m->bonds[m->adjacent[a].items[i]];
        if (bond_other(bond, a) == b)
            return bond;
    }
    return NULL;
}
int atom_base(const Molecule *m, int atom) {
    int sum = 0;
    for (int i = 0; i < m->adjacent[atom].count; ++i) {
        int type = m->bonds[m->adjacent[atom].items[i]].type;
        sum += type == 4 ? 1 : type;
    }
    return sum;
}
int atom_multiplicity(const Molecule *m, int atom) {
    int sum = 0;
    for (int i = 0; i < m->adjacent[atom].count; ++i)
        sum += m->bonds[m->adjacent[atom].items[i]].multiplicity;
    return sum;
}
bool needs_pi(const Molecule *m, int atom, const Elements *elements, bool hydrogens) {
    const Atom *a = &m->atoms[atom];
    return a->aromatic && elements->items[a->element].valences[0] + a->charge >=
                              atom_base(m, atom) + (hydrogens ? a->hydrogens : 0) + 1;
}
bool organic_hydrogens(const Molecule *m, int atom, const Elements *elements, int *out) {
    int total = atom_multiplicity(m, atom);
    const Element *e = &elements->items[m->atoms[atom].element];
    for (int i = 0; i < e->valence_count; ++i)
        if (e->valences[i] >= total) {
            *out = e->valences[i] - total;
            return true;
        }
    return false;
}
void molecule_free(Molecule *m) {
    if (!m)
        return;
    for (int i = 0; i < m->atom_count; ++i) {
        free(m->atoms[i].choices);
        if (m->adjacent)
            ints_free(&m->adjacent[i]);
    }
    for (int i = 0; i < m->ring_count; ++i)
        ints_free(&m->rings[i]);
    free(m->name);
    free(m->atoms);
    free(m->bonds);
    free(m->adjacent);
    free(m->rings);
    free(m->ring_atoms);
    free(m->ranks);
    free(m->canonical);
    free(m->scaffold);
    free(m->formula);
    free(m);
}
