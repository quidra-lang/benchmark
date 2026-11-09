#include "chemistry.h"
#include <stdlib.h>
#include <string.h>
typedef struct {
    uint64_t words[5];
} BondSet;
typedef struct {
    IntList atoms;
    BondSet bonds;
    int ordinal;
} Candidate;
typedef struct {
    bool occupied;
    BondSet key;
} SetSlot;
typedef struct {
    SetSlot *items;
    size_t count, capacity;
} BondSets;
static uint64_t set_hash(BondSet key) {
    uint64_t hash = UINT64_C(14695981039346656037);
    for (int i = 0; i < 5; ++i) {
        hash ^= key.words[i];
        hash *= UINT64_C(1099511628211);
    }
    return hash;
}
static void set_grow(BondSets *sets) {
    size_t old_capacity = sets->capacity;
    SetSlot *old = sets->items;
    sets->capacity = old_capacity ? 2 * old_capacity : 256;
    sets->items = allocate(sets->capacity * sizeof(SetSlot));
    memset(sets->items, 0, sets->capacity * sizeof(SetSlot));
    for (size_t i = 0; i < old_capacity; ++i)
        if (old[i].occupied) {
            size_t at = (size_t)set_hash(old[i].key) & (sets->capacity - 1);
            while (sets->items[at].occupied)
                at = (at + 1) & (sets->capacity - 1);
            sets->items[at] = old[i];
        }
    free(old);
}
static bool set_insert(BondSets *sets, BondSet key) {
    if (!sets->capacity || 2 * (sets->count + 1) > sets->capacity)
        set_grow(sets);
    size_t at = (size_t)set_hash(key) & (sets->capacity - 1);
    while (sets->items[at].occupied) {
        if (memcmp(&sets->items[at].key, &key, sizeof(key)) == 0)
            return false;
        at = (at + 1) & (sets->capacity - 1);
    }
    sets->items[at] = (SetSlot){true, key};
    ++sets->count;
    return true;
}
static IntList path_to(const int *parent, int atom) {
    IntList result = {0};
    for (; atom >= 0; atom = parent[atom])
        ints_add(&result, atom);
    return result;
}
static IntList canonical_ring(const IntList *ring) {
    int first = 0, n = ring->count;
    for (int i = 1; i < n; ++i)
        if (ring->items[i] < ring->items[first])
            first = i;
    int direction = ring->items[(first + 1) % n] < ring->items[(first + n - 1) % n] ? 1 : -1;
    IntList result = {0};
    for (int i = 0; i < n; ++i)
        ints_add(&result, ring->items[(first + direction * i + n) % n]);
    return result;
}
static int candidate_compare(const void *left, const void *right) {
    const Candidate *a = left, *b = right;
    return a->atoms.count != b->atoms.count
               ? (a->atoms.count > b->atoms.count) - (a->atoms.count < b->atoms.count)
               : (a->ordinal > b->ordinal) - (a->ordinal < b->ordinal);
}
static int ring_compare(const void *left, const void *right) {
    const IntList *a = left, *b = right;
    if (a->count != b->count)
        return (a->count > b->count) - (a->count < b->count);
    for (int i = 0; i < a->count; ++i)
        if (a->items[i] != b->items[i])
            return a->items[i] < b->items[i] ? -1 : 1;
    return 0;
}
static bool set_nonempty(BondSet set) {
    for (int i = 0; i < 5; ++i)
        if (set.words[i])
            return true;
    return false;
}
void detect_rings(Molecule *m) {
    int n = m->atom_count;
    Candidate *candidates = NULL;
    size_t count = 0, capacity = 0;
    BondSets seen = {0};
    int *parent = allocate((size_t)n * sizeof(int)), *queue = allocate((size_t)n * sizeof(int));
    int *bond_index = allocate((size_t)n * n * sizeof(int));
    for (int i = 0; i < n * n; ++i)
        bond_index[i] = -1;
    for (int e = 0; e < m->bond_count; ++e) {
        Bond b = m->bonds[e];
        bond_index[b.a * n + b.b] = bond_index[b.b * n + b.a] = e;
    }
    for (int root = 0; root < n; ++root) {
        for (int i = 0; i < n; ++i)
            parent[i] = -2;
        parent[root] = -1;
        queue[0] = root;
        int tail = 1;
        for (int head = 0; head < tail; ++head) {
            int a = queue[head];
            for (int i = 0; i < m->adjacent[a].count; ++i) {
                int next = bond_other(&m->bonds[m->adjacent[a].items[i]], a);
                if (parent[next] == -2) {
                    parent[next] = a;
                    queue[tail++] = next;
                }
            }
        }
        for (int e = 0; e < m->bond_count; ++e) {
            Bond bond = m->bonds[e];
            if (parent[bond.a] == bond.b || parent[bond.b] == bond.a)
                continue;
            IntList px = path_to(parent, bond.a), py = path_to(parent, bond.b);
            bool overlap = false;
            for (int i = 0; i + 1 < px.count; ++i)
                for (int j = 0; j + 1 < py.count; ++j)
                    if (px.items[i] == py.items[j])
                        overlap = true;
            if (overlap) {
                ints_free(&px);
                ints_free(&py);
                continue;
            }
            IntList atoms = {0};
            for (int i = px.count - 1; i >= 0; --i)
                ints_add(&atoms, px.items[i]);
            for (int i = 0; i + 1 < py.count; ++i)
                ints_add(&atoms, py.items[i]);
            ints_free(&px);
            ints_free(&py);
            BondSet vector = {{0}};
            for (int i = 0; i < atoms.count; ++i) {
                int bit = bond_index[atoms.items[i] * n + atoms.items[(i + 1) % atoms.count]];
                vector.words[bit / 64] |= UINT64_C(1) << (bit % 64);
            }
            if (set_insert(&seen, vector)) {
                if (count == capacity) {
                    capacity = capacity ? 2 * capacity : 64;
                    candidates = resize(candidates, capacity * sizeof(Candidate));
                }
                candidates[count] = (Candidate){atoms, vector, (int)count};
                ++count;
            } else
                ints_free(&atoms);
        }
    }
    if (count)
        qsort(candidates, count, sizeof(Candidate), candidate_compare);
    BondSet basis[300];
    bool present[300] = {0};
    m->ring_atoms = allocate((size_t)n * sizeof(bool));
    memset(m->ring_atoms, 0, (size_t)n * sizeof(bool));
    for (size_t i = 0; i < count; ++i) {
        Candidate *c = &candidates[i];
        BondSet reduced = c->bonds;
        while (set_nonempty(reduced)) {
            int pivot = m->bond_count - 1;
            while (!(reduced.words[pivot / 64] & (UINT64_C(1) << (pivot % 64))))
                --pivot;
            if (present[pivot])
                for (int j = 0; j < 5; ++j)
                    reduced.words[j] ^= basis[pivot].words[j];
            else {
                basis[pivot] = reduced;
                present[pivot] = true;
                if (m->ring_count == m->ring_capacity) {
                    m->ring_capacity = m->ring_capacity ? 2 * m->ring_capacity : 8;
                    m->rings = resize(m->rings, (size_t)m->ring_capacity * sizeof(IntList));
                }
                m->rings[m->ring_count++] = canonical_ring(&c->atoms);
                for (int j = 0; j < c->atoms.count; ++j)
                    m->ring_atoms[c->atoms.items[j]] = true;
                for (int e = 0; e < m->bond_count; ++e)
                    if (c->bonds.words[e / 64] & (UINT64_C(1) << (e % 64)))
                        m->bonds[e].ring = true;
                break;
            }
        }
        ints_free(&c->atoms);
    }
    if (m->ring_count)
        qsort(m->rings, (size_t)m->ring_count, sizeof(IntList), ring_compare);
    free(candidates);
    free(seen.items);
    free(parent);
    free(queue);
    free(bond_index);
}
typedef struct {
    Molecule *m;
    const IntList *system;
    bool *member;
    int *paired;
} Matching;
static bool match(Matching *s) {
    int u = -1;
    for (int i = 0; i < s->system->count; ++i)
        if (s->paired[s->system->items[i]] < 0) {
            u = s->system->items[i];
            break;
        }
    if (u < 0)
        return true;
    for (int i = 0; i < s->m->adjacent[u].count; ++i) {
        Bond *bond = &s->m->bonds[s->m->adjacent[u].items[i]];
        int v = bond_other(bond, u);
        if (bond->type != 4 || !s->member[v] || s->paired[v] >= 0)
            continue;
        s->paired[u] = v;
        s->paired[v] = u;
        if (match(s))
            return true;
        s->paired[u] = s->paired[v] = -1;
    }
    return false;
}
bool kekulize(Molecule *m, const Elements *elements, ParseError *error) {
    int n = m->atom_count;
    bool *need = allocate((size_t)n * sizeof(bool)), *seen = allocate((size_t)n * sizeof(bool)),
         *member = allocate((size_t)n * sizeof(bool));
    int *paired = allocate((size_t)n * sizeof(int));
    memset(seen, 0, (size_t)n * sizeof(bool));
    for (int i = 0; i < n; ++i) {
        need[i] = needs_pi(m, i, elements, true);
        paired[i] = -1;
    }
    bool success = true;
    for (int first = 0; first < n; ++first) {
        if (!need[first] || seen[first])
            continue;
        IntList system = {0};
        ints_add(&system, first);
        seen[first] = true;
        for (int head = 0; head < system.count; ++head) {
            int u = system.items[head];
            for (int j = 0; j < m->adjacent[u].count; ++j) {
                Bond *bond = &m->bonds[m->adjacent[u].items[j]];
                int v = bond_other(bond, u);
                if (bond->type == 4 && need[v] && !seen[v]) {
                    seen[v] = true;
                    ints_add(&system, v);
                }
            }
        }
        ints_sort(&system);
        memset(member, 0, (size_t)n * sizeof(bool));
        for (int i = 0; i < system.count; ++i)
            member[system.items[i]] = true;
        Matching matching = {m, &system, member, paired};
        if (!match(&matching)) {
            *error = (ParseError){"kekulization failed", m->atoms[first].column};
            success = false;
            ints_free(&system);
            break;
        }
        ints_free(&system);
    }
    if (success)
        for (int e = 0; e < m->bond_count; ++e) {
            Bond *b = &m->bonds[e];
            b->multiplicity = b->type == 4 ? (paired[b->a] == b->b ? 2 : 1) : b->type;
        }
    free(need);
    free(seen);
    free(member);
    free(paired);
    return success;
}
