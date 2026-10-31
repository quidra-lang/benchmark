#include "chemistry.h"
#include <errno.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

void *resize(void *pointer, size_t size) {
    void *result = realloc(pointer, size ? size : 1);
    if (!result) {
        fputs("allocation failed\n", stderr);
        exit(EXIT_FAILURE);
    }
    return result;
}
void *allocate(size_t size) { return resize(NULL, size); }
char *copy_text(const char *value) {
    char *result = allocate(strlen(value) + 1);
    strcpy(result, value);
    return result;
}
static char *format_arguments(const char *format, va_list args) {
    va_list copy;
    va_copy(copy, args);
    int length = vsnprintf(NULL, 0, format, copy);
    va_end(copy);
    if (length < 0)
        exit(EXIT_FAILURE);
    char *result = allocate((size_t)length + 1);
    vsnprintf(result, (size_t)length + 1, format, args);
    return result;
}
char *format_text(const char *format, ...) {
    va_list args;
    va_start(args, format);
    char *result = format_arguments(format, args);
    va_end(args);
    return result;
}
void text_add(Text *text, const char *part) {
    size_t length = strlen(part), needed = text->count + length + 1;
    if (needed > text->capacity) {
        size_t capacity = text->capacity ? 2 * text->capacity : 128;
        while (capacity < needed)
            capacity *= 2;
        text->data = resize(text->data, capacity);
        text->capacity = capacity;
    }
    memcpy(text->data + text->count, part, length + 1);
    text->count += length;
}
void text_format(Text *text, const char *format, ...) {
    va_list args;
    va_start(args, format);
    char *part = format_arguments(format, args);
    va_end(args);
    text_add(text, part);
    free(part);
}
char *text_take(Text *text) {
    char *result = text->data ? text->data : copy_text("");
    *text = (Text){0};
    return result;
}
void lines_add(Lines *lines, char *value) {
    if (lines->count == lines->capacity) {
        lines->capacity = lines->capacity ? 2 * lines->capacity : 64;
        lines->items = resize(lines->items, lines->capacity * sizeof(char *));
    }
    lines->items[lines->count++] = value;
}
void line(Lines *lines, const char *format, ...) {
    va_list args;
    va_start(args, format);
    lines_add(lines, format_arguments(format, args));
    va_end(args);
}
void lines_take(Lines *out, Lines input) {
    for (size_t i = 0; i < input.count; ++i)
        lines_add(out, input.items[i]);
    free(input.items);
}
void lines_free(Lines *lines) {
    for (size_t i = 0; i < lines->count; ++i)
        free(lines->items[i]);
    free(lines->items);
    *lines = (Lines){0};
}
Words split(const char *text, char separator) {
    Words result = {.storage = copy_text(text)};
    char *part = result.storage;
    for (;;) {
        result.items = resize(result.items, (result.count + 1) * sizeof(char *));
        result.items[result.count++] = part;
        char *next = strchr(part, separator);
        if (!next)
            break;
        *next = 0;
        part = next + 1;
    }
    return result;
}
void words_free(Words *words) {
    free(words->items);
    free(words->storage);
}
static FILE *open_file(const char *path, const char *mode) {
    FILE *file = fopen(path, mode);
    if (!file) {
        perror(path);
        exit(EXIT_FAILURE);
    }
    return file;
}
Lines read_lines(const char *path) {
    Lines result = {0};
    FILE *file = open_file(path, "r");
    for (;;) {
        Text text = {0};
        int c;
        while ((c = fgetc(file)) != EOF && c != '\n') {
            char part[2] = {(char)c, 0};
            text_add(&text, part);
        }
        if (c == EOF && !text.count) {
            free(text.data);
            break;
        }
        lines_add(&result, text_take(&text));
    }
    fclose(file);
    return result;
}
void write_lines(const char *name, const Lines *lines) {
    char *path = format_text("output/%s", name);
    FILE *file = open_file(path, "w");
    free(path);
    for (size_t i = 0; i < lines->count; ++i)
        fprintf(file, "%s\n", lines->items[i]);
    fclose(file);
}
bool ignored(const char *text) { return !*text || *text == '#'; }
void paragraph_add(Paragraphs *out, Lines paragraph) {
    if (out->count == out->capacity) {
        out->capacity = out->capacity ? 2 * out->capacity : 8;
        out->items = resize(out->items, out->capacity * sizeof(Lines));
    }
    out->items[out->count++] = paragraph;
}
void paragraphs_free(Paragraphs *paragraphs) {
    for (size_t i = 0; i < paragraphs->count; ++i)
        lines_free(&paragraphs->items[i]);
    free(paragraphs->items);
}
void write_paragraphs(const char *name, const Paragraphs *paragraphs) {
    Lines out = {0};
    for (size_t i = 0; i < paragraphs->count; ++i) {
        Lines paragraph = paragraphs->items[i];
        if (!paragraph.count)
            continue;
        if (out.count)
            line(&out, "");
        for (size_t j = 0; j < paragraph.count; ++j)
            line(&out, "%s", paragraph.items[j]);
    }
    write_lines(name, &out);
    lines_free(&out);
}
static bool valid_name(const char *text) {
    size_t length = strlen(text);
    if (length < 1 || length > 32)
        return false;
    for (; *text; ++text)
        if (!((*text >= 'A' && *text <= 'Z') || (*text >= 'a' && *text <= 'z') ||
              (*text >= '0' && *text <= '9') || *text == '_' || *text == '-'))
            return false;
    return true;
}
static bool analyze(Molecule *m, const Elements *elements, ParseError *error) {
    detect_rings(m);
    for (int e = 0; e < m->bond_count; ++e) {
        Bond *b = &m->bonds[e];
        b->type = symbol_type(b->symbol);
        if (!b->type)
            b->type = b->ring && m->atoms[b->a].aromatic && m->atoms[b->b].aromatic ? 4 : 1;
    }
    if (!kekulize(m, elements, error))
        return false;
    for (int i = 0; i < m->atom_count; ++i) {
        Atom *a = &m->atoms[i];
        if (a->bracket) {
            const Element *element = &elements->items[a->element];
            if (atom_multiplicity(m, i) + a->hydrogens >
                element->valences[element->valence_count - 1] + abs(a->charge)) {
                *error = (ParseError){"bad valence", a->column};
                return false;
            }
        } else {
            int hydrogens;
            if (!organic_hydrogens(m, i, elements, &hydrogens)) {
                *error = (ParseError){"bad valence", a->column};
                return false;
            }
            a->hydrogens = hydrogens;
        }
    }
    return true;
}
static void properties(Molecule *m, const Elements *elements) {
    int counts[40] = {0}, hydrogens = 0,
        *heavy_degree = allocate((size_t)m->atom_count * sizeof(int));
    bool *triple = allocate((size_t)m->atom_count * sizeof(bool));
    memset(heavy_degree, 0, (size_t)m->atom_count * sizeof(int));
    memset(triple, 0, (size_t)m->atom_count * sizeof(bool));
    int hydrogen = element_index(elements, "H"), carbon = element_index(elements, "C");
    for (int i = 0; i < m->atom_count; ++i) {
        Atom a = m->atoms[i];
        const char *symbol = elements->items[a.element].symbol;
        ++counts[a.element];
        hydrogens += a.hydrogens;
        m->charge += a.charge;
        m->weight += a.mass ? a.mass * 1000 : elements->items[a.element].weight;
        m->heavy += strcmp(symbol, "H") != 0;
        int attached = a.hydrogens;
        for (int j = 0; j < m->adjacent[i].count; ++j) {
            Bond b = m->bonds[m->adjacent[i].items[j]];
            if (m->atoms[bond_other(&b, i)].element == hydrogen)
                ++attached;
            else
                ++heavy_degree[i];
            if (b.multiplicity == 3)
                triple[i] = true;
        }
        if (!strcmp(symbol, "N") || !strcmp(symbol, "O")) {
            ++m->acceptors;
            if (attached)
                ++m->donors;
        }
    }
    counts[hydrogen] += hydrogens;
    m->weight += hydrogens * elements->items[hydrogen].weight;
    IntList order = {0};
    for (int i = 0; i < elements->count; ++i)
        if (counts[i])
            ints_add(&order, i);
    for (int i = 1; i < order.count; ++i) {
        int element = order.items[i], j = i;
        while (j && strcmp(elements->items[order.items[j - 1]].symbol,
                           elements->items[element].symbol) > 0) {
            order.items[j] = order.items[j - 1];
            --j;
        }
        order.items[j] = element;
    }
    IntList hill = {0};
    if (counts[carbon]) {
        ints_add(&hill, carbon);
        if (counts[hydrogen])
            ints_add(&hill, hydrogen);
    }
    for (int i = 0; i < order.count; ++i)
        if (!counts[carbon] || (order.items[i] != carbon && order.items[i] != hydrogen))
            ints_add(&hill, order.items[i]);
    Text formula = {0};
    for (int i = 0; i < hill.count; ++i) {
        int element = hill.items[i];
        text_add(&formula, elements->items[element].symbol);
        if (counts[element] > 1)
            text_format(&formula, "%d", counts[element]);
    }
    m->formula = text_take(&formula);
    ints_free(&order);
    ints_free(&hill);
    for (int e = 0; e < m->bond_count; ++e) {
        Bond b = m->bonds[e];
        if (b.multiplicity == 1 && !b.ring && heavy_degree[b.a] >= 2 && heavy_degree[b.b] >= 2 &&
            !triple[b.a] && !triple[b.b])
            ++m->rotatable;
    }
    int violations = (m->weight > 500000) + (m->donors > 5) + (m->acceptors > 10);
    m->lipinski = violations < 2 ? "pass" : "fail";
    free(heavy_degree);
    free(triple);
}
static char *scaffold(const Molecule *m, const Elements *elements) {
    if (!m->ring_count)
        return copy_text("");
    bool *remaining = allocate((size_t)m->atom_count * sizeof(bool)),
         *keep = allocate((size_t)m->atom_count * sizeof(bool));
    for (int i = 0; i < m->atom_count; ++i)
        remaining[i] = true;
    for (;;) {
        int remove = -1;
        for (int a = 0; a < m->atom_count; ++a) {
            if (!remaining[a] || m->ring_atoms[a])
                continue;
            int degree = 0;
            for (int j = 0; j < m->adjacent[a].count; ++j)
                degree += remaining[bond_other(&m->bonds[m->adjacent[a].items[j]], a)];
            if (degree == 1) {
                remove = a;
                break;
            }
        }
        if (remove < 0)
            break;
        remaining[remove] = false;
    }
    memcpy(keep, remaining, (size_t)m->atom_count * sizeof(bool));
    for (int e = 0; e < m->bond_count; ++e) {
        Bond b = m->bonds[e];
        if (b.multiplicity == 2) {
            if (remaining[b.a])
                keep[b.b] = true;
            if (remaining[b.b])
                keep[b.a] = true;
        }
    }
    Molecule *s = molecule_new();
    int *renumber = allocate((size_t)m->atom_count * sizeof(int));
    for (int i = 0; i < m->atom_count; ++i) {
        renumber[i] = -1;
        if (!keep[i])
            continue;
        Atom atom = m->atoms[i];
        atom.choices = NULL;
        atom.choice_count = 0;
        for (int j = 0; j < m->adjacent[i].count; ++j) {
            Bond b = m->bonds[m->adjacent[i].items[j]];
            if (!keep[bond_other(&b, i)])
                atom.hydrogens += b.multiplicity;
        }
        renumber[i] = s->atom_count;
        molecule_add_atom(s, atom);
    }
    for (int e = 0; e < m->bond_count; ++e) {
        Bond b = m->bonds[e];
        if (keep[b.a] && keep[b.b]) {
            b.a = renumber[b.a];
            b.b = renumber[b.b];
            molecule_add_bond(s, b);
        }
    }
    molecule_build(s);
    canonical_ranks(s, elements);
    char *result = canonical_smiles(s, elements);
    molecule_free(s);
    free(remaining);
    free(keep);
    free(renumber);
    return result;
}
static int ring_relation(const Molecule *m, const IntList *a, const IntList *b) {
    int count = 0, first = -1, second = -1;
    for (int i = 0; i < a->count; ++i)
        if (ints_contains(b, a->items[i])) {
            if (!count)
                first = a->items[i];
            else if (count == 1)
                second = a->items[i];
            ++count;
        }
    if (count == 1)
        return 2;
    if (count == 2 && molecule_bond(m, first, second))
        return 1;
    return count >= 2 ? 3 : -1;
}
static const char *const system_names[] = {"isolated", "fused", "spiro", "bridged"};
typedef struct {
    IntList rings;
    int kind, atoms;
} RingSystem;
typedef struct {
    RingSystem *items;
    int count;
} RingSystems;
static RingSystems ring_systems(const Molecule *m) {
    RingSystems out = {.items = allocate((size_t)m->ring_count * sizeof(RingSystem))};
    bool *seen = allocate((size_t)m->ring_count * sizeof(bool));
    memset(seen, 0, (size_t)m->ring_count * sizeof(bool));
    for (int first = 0; first < m->ring_count; ++first) {
        if (seen[first])
            continue;
        IntList queue = {0};
        ints_add(&queue, first);
        seen[first] = true;
        for (int head = 0; head < queue.count; ++head)
            for (int next = 0; next < m->ring_count; ++next)
                if (!seen[next] &&
                    ring_relation(m, &m->rings[queue.items[head]], &m->rings[next]) >= 0) {
                    seen[next] = true;
                    ints_add(&queue, next);
                }
        ints_sort(&queue);
        bool atoms[300] = {0};
        int atom_count = 0, kind = queue.count == 1 ? 0 : 2;
        for (int i = 0; i < queue.count; ++i) {
            IntList ring = m->rings[queue.items[i]];
            for (int a = 0; a < ring.count; ++a)
                atoms[ring.items[a]] = true;
            for (int j = i + 1; j < queue.count; ++j) {
                int relation = ring_relation(m, &ring, &m->rings[queue.items[j]]);
                if (relation == 3)
                    kind = 3;
                else if (relation == 1 && kind != 3)
                    kind = 1;
            }
        }
        for (int a = 0; a < m->atom_count; ++a)
            atom_count += atoms[a];
        out.items[out.count++] = (RingSystem){queue, kind, atom_count};
    }
    free(seen);
    return out;
}
static bool ring_aromatic(const Molecule *m, const IntList *ring) {
    for (int i = 0; i < ring->count; ++i)
        if (!m->atoms[ring->items[i]].aromatic)
            return false;
    return true;
}
static char *integers(const IntList *values, const char *separator, int offset) {
    Text out = {0};
    for (int i = 0; i < values->count; ++i)
        text_format(&out, "%s%d", i ? separator : "", values->items[i] + offset);
    return text_take(&out);
}
static char *member_names(Molecule *const *molecules, const IntList *indices) {
    Text out = {0};
    for (int i = 0; i < indices->count; ++i) {
        if (i)
            text_add(&out, ",");
        text_add(&out, molecules[indices->items[i]]->name);
    }
    return text_take(&out);
}
typedef struct {
    const char *key;
    IntList members;
} KeyGroup;
static void group_add(KeyGroup groups[300], int *count, const char *key, int index) {
    for (int i = 0; i < *count; ++i)
        if (strcmp(groups[i].key, key) == 0) {
            ints_add(&groups[i].members, index);
            return;
        }
    groups[*count] = (KeyGroup){.key = key};
    ints_add(&groups[(*count)++].members, index);
}
static Paragraphs canonical_paragraphs(Molecule *const *molecules, int n) {
    KeyGroup canon[300] = {0}, formula[300] = {0}, scaffolds[300] = {0};
    int cc = 0, fc = 0, sc = 0, acyclic = 0;
    for (int i = 0; i < n; ++i) {
        Molecule *m = molecules[i];
        group_add(canon, &cc, m->canonical, i);
        group_add(formula, &fc, m->formula, i);
        if (*m->scaffold)
            group_add(scaffolds, &sc, m->scaffold, i);
        else
            ++acyclic;
    }
    Paragraphs out = {0};
    Lines canonical = {0}, duplicates = {0}, isomers = {0}, scaffold_lines = {0};
    line(&canonical, "CANONICAL molecules=%d unique=%d", n, cc);
    for (int i = 0; i < n; ++i) {
        Molecule *m = molecules[i];
        line(&canonical, "%s %s classes=%d charge=%s%d", m->name, m->canonical, m->classes,
             m->charge > 0 ? "+" : "", m->charge);
    }
    int duplicate_count = 0, duplicate_molecules = 0;
    for (int i = 0; i < cc; ++i)
        if (canon[i].members.count >= 2) {
            ++duplicate_count;
            duplicate_molecules += canon[i].members.count;
        }
    line(&duplicates, "DUPLICATES groups=%d molecules=%d", duplicate_count, duplicate_molecules);
    int serial = 0;
    for (int i = 0; i < cc; ++i)
        if (canon[i].members.count >= 2) {
            char *members = member_names(molecules, &canon[i].members);
            line(&duplicates, "group %d %s members=%s", ++serial, canon[i].key, members);
            free(members);
        }
    Lines isomer_rows = {0};
    for (int i = 0; i < fc; ++i) {
        IntList group = formula[i].members;
        int distinct = 0;
        for (int a = 0; a < group.count; ++a) {
            bool seen = false;
            for (int b = 0; b < a; ++b)
                if (strcmp(molecules[group.items[a]]->canonical,
                           molecules[group.items[b]]->canonical) == 0)
                    seen = true;
            if (!seen)
                ++distinct;
        }
        if (distinct >= 2) {
            char *members = member_names(molecules, &group);
            line(&isomer_rows, "isomer %zu %s forms=%d members=%s", isomer_rows.count + 1,
                 formula[i].key, distinct, members);
            free(members);
        }
    }
    line(&isomers, "ISOMERS groups=%zu", isomer_rows.count);
    lines_take(&isomers, isomer_rows);
    line(&scaffold_lines, "SCAFFOLDS distinct=%d acyclic=%d", sc, acyclic);
    int order[300];
    for (int i = 0; i < sc; ++i)
        order[i] = i;
    for (int i = 1; i < sc; ++i) {
        int current = order[i], j = i;
        while (j) {
            int previous = order[j - 1];
            bool less = scaffolds[current].members.count != scaffolds[previous].members.count
                            ? scaffolds[current].members.count > scaffolds[previous].members.count
                            : strcmp(scaffolds[current].key, scaffolds[previous].key) < 0;
            if (!less)
                break;
            order[j] = previous;
            --j;
        }
        order[j] = current;
    }
    for (int i = 0; i < sc; ++i) {
        KeyGroup group = scaffolds[order[i]];
        char *members = member_names(molecules, &group.members);
        line(&scaffold_lines, "scaffold %d %s count=%d members=%s", i + 1, group.key,
             group.members.count, members);
        free(members);
    }
    paragraph_add(&out, canonical);
    paragraph_add(&out, duplicates);
    paragraph_add(&out, isomers);
    paragraph_add(&out, scaffold_lines);
    for (int i = 0; i < cc; ++i)
        ints_free(&canon[i].members);
    for (int i = 0; i < fc; ++i)
        ints_free(&formula[i].members);
    for (int i = 0; i < sc; ++i)
        ints_free(&scaffolds[i].members);
    return out;
}
static Paragraphs ring_paragraphs(Molecule *const *molecules, int n, const Elements *elements) {
    Paragraphs out = {0};
    int cyclic = 0, total = 0, aromatic = 0, sizes[301] = {0}, kinds[4] = {0};
    int carbon = element_index(elements, "C");
    for (int i = 0; i < n; ++i) {
        Molecule *m = molecules[i];
        if (!m->ring_count)
            continue;
        ++cyclic;
        total += m->ring_count;
        RingSystems systems = ring_systems(m);
        int aromatic_count = 0, ring_atoms = 0, ring_bonds = 0;
        for (int a = 0; a < m->atom_count; ++a)
            ring_atoms += m->ring_atoms[a];
        for (int e = 0; e < m->bond_count; ++e)
            ring_bonds += m->bonds[e].ring;
        for (int r = 0; r < m->ring_count; ++r) {
            ++sizes[m->rings[r].count];
            aromatic_count += ring_aromatic(m, &m->rings[r]);
        }
        aromatic += aromatic_count;
        Lines paragraph = {0};
        line(
            &paragraph,
            "MOLECULE %s atoms=%d bonds=%d rings=%d aromatic=%d systems=%d ring_atoms=%d ring_bonds=%d",
            m->name, m->atom_count, m->bond_count, m->ring_count, aromatic_count, systems.count,
            ring_atoms, ring_bonds);
        for (int r = 0; r < m->ring_count; ++r) {
            IntList ring = m->rings[r];
            int hetero = 0;
            for (int a = 0; a < ring.count; ++a)
                hetero += m->atoms[ring.items[a]].element != carbon;
            char *atoms = integers(&ring, "-", 1);
            line(&paragraph, "ring %d size=%d aromatic=%s hetero=%d atoms=%s", r + 1, ring.count,
                 ring_aromatic(m, &ring) ? "yes" : "no", hetero, atoms);
            free(atoms);
        }
        for (int s = 0; s < systems.count; ++s) {
            RingSystem system = systems.items[s];
            ++kinds[system.kind];
            char *rings = integers(&system.rings, ",", 1);
            line(&paragraph, "system %d kind=%s rings=%s atoms=%d", s + 1,
                 system_names[system.kind], rings, system.atoms);
            free(rings);
            ints_free(&systems.items[s].rings);
        }
        free(systems.items);
        Text double_bonds = {0};
        text_add(&double_bonds, "kekule");
        bool any = false;
        for (int e = 0; e < m->bond_count; ++e) {
            Bond b = m->bonds[e];
            if (b.type == 4 && b.multiplicity == 2) {
                text_format(&double_bonds, " %d=%d", b.a + 1, b.b + 1);
                any = true;
            }
        }
        if (!any)
            text_add(&double_bonds, " -");
        lines_add(&paragraph, text_take(&double_bonds));
        paragraph_add(&out, paragraph);
    }
    Lines summary = {0};
    line(&summary, "SUMMARY molecules=%d cyclic=%d rings=%d aromatic=%d", n, cyclic, total,
         aromatic);
    Text size_line = {0};
    text_add(&size_line, "sizes");
    bool any = false;
    for (int size = 1; size <= 300; ++size)
        if (sizes[size]) {
            text_format(&size_line, " %d=%d", size, sizes[size]);
            any = true;
        }
    if (!any)
        text_add(&size_line, " -");
    lines_add(&summary, text_take(&size_line));
    line(&summary, "systems isolated=%d fused=%d spiro=%d bridged=%d", kinds[0], kinds[1], kinds[2],
         kinds[3]);
    paragraph_add(&out, summary);
    return out;
}
typedef enum {
    QUERY_MATCH,
    QUERY_CONTAINS,
    QUERY_MATRIX,
    QUERY_NEAREST,
    QUERY_WITHIN,
    QUERY_COMPARE,
    QUERY_CLUSTER
} QueryKind;
static const char *const query_names[] = {"MATCH",  "CONTAINS", "MATRIX", "NEAREST",
                                          "WITHIN", "COMPARE",  "CLUSTER"};
typedef struct {
    QueryKind kind;
    Words source;
    char *id, **args;
    size_t argument_count;
    Molecule *pattern;
    Fraction threshold;
    int count;
} Query;
static int molecule_index(Molecule *const *molecules, int count, const char *name) {
    for (int i = 0; i < count; ++i)
        if (strcmp(molecules[i]->name, name) == 0)
            return i;
    return -1;
}
static bool number(const char *text, int low, int high) {
    size_t length = strlen(text);
    if (length < 1 || length > 2 || (length > 1 && text[0] == '0'))
        return false;
    for (const char *p = text; *p; ++p)
        if (!digit(*p))
            return false;
    int value = atoi(text);
    return value >= low && value <= high;
}
static bool parse_threshold(const char *text, Fraction *out) {
    Words a = split(text, '/');
    bool valid = a.count == 2 && number(a.items[0], 0, 99) && number(a.items[1], 1, 99);
    if (valid) {
        int n = atoi(a.items[0]), d = atoi(a.items[1]);
        valid = n <= d;
        if (valid)
            *out = fraction(n, d);
    }
    words_free(&a);
    return valid;
}
static Query *check_query(Words *tokens, char seen[100][33], int *seen_count,
                          Molecule *const *molecules, int n, const Elements *elements,
                          char **reason) {
    int kind = -1;
    for (int i = 0; i < 7; ++i)
        if (strcmp(tokens->items[0], query_names[i]) == 0)
            kind = i;
    if (kind < 0) {
        *reason = copy_text("unknown query");
        return NULL;
    }
    if (tokens->count == 1 || !valid_name(tokens->items[1])) {
        *reason = copy_text("bad id");
        return NULL;
    }
    const char *id = tokens->items[1];
    for (int i = 0; i < *seen_count; ++i)
        if (strcmp(id, seen[i]) == 0) {
            *reason = copy_text("duplicate id");
            return NULL;
        }
    strcpy(seen[(*seen_count)++], id);
    char **args = tokens->items + 2;
    size_t count = tokens->count - 2;
    bool length = kind == QUERY_MATCH || kind == QUERY_CLUSTER ? count == 1
                  : kind == QUERY_MATRIX                       ? count >= 2 && count <= 12
                                                               : count == 2;
    if (!length) {
        *reason = copy_text("bad arguments");
        return NULL;
    }
    Molecule *pattern = NULL;
    Fraction threshold = {0, 1};
    int nearest = 0;
    if (kind == QUERY_MATCH) {
        ParseError error;
        pattern = parse_smiles(args[0], elements, true, &error);
        if (!pattern) {
            *reason = format_text("bad pattern %s at column %d", error.reason, error.column);
            return NULL;
        }
    } else if (kind == QUERY_CLUSTER) {
        if (!parse_threshold(args[0], &threshold)) {
            *reason = copy_text("bad threshold");
            return NULL;
        }
    } else if (kind == QUERY_CONTAINS || kind == QUERY_MATRIX || kind == QUERY_COMPARE) {
        for (size_t i = 0; i < count; ++i)
            if (molecule_index(molecules, n, args[i]) < 0) {
                *reason = format_text("unknown molecule %s", args[i]);
                return NULL;
            }
        for (size_t i = 0; i < count; ++i)
            for (size_t j = 0; j < i; ++j)
                if (strcmp(args[i], args[j]) == 0) {
                    *reason = copy_text("repeated molecule");
                    return NULL;
                }
    } else {
        if (molecule_index(molecules, n, args[0]) < 0) {
            *reason = format_text("unknown molecule %s", args[0]);
            return NULL;
        }
        if (kind == QUERY_NEAREST) {
            if (!number(args[1], 1, 99)) {
                *reason = copy_text("bad count");
                return NULL;
            }
            nearest = atoi(args[1]);
        } else if (!parse_threshold(args[1], &threshold)) {
            *reason = copy_text("bad threshold");
            return NULL;
        }
    }
    Query *query = allocate(sizeof(*query));
    *query = (Query){.kind = (QueryKind)kind,
                     .source = *tokens,
                     .pattern = pattern,
                     .threshold = threshold,
                     .count = nearest,
                     .argument_count = count};
    *tokens = (Words){0};
    query->id = query->source.items[1];
    query->args = query->source.items + 2;
    return query;
}
static Paragraphs substructure_paragraphs(Query *const *queries, int query_count,
                                          Molecule *const *molecules, int n) {
    Paragraphs out = {0};
    int patterns = 0, hits = 0, contains = 0, found = 0;
    for (int qn = 0; qn < query_count; ++qn) {
        Query *q = queries[qn];
        if (q->kind == QUERY_MATCH) {
            ++patterns;
            Lines hit_lines = {0};
            int total = 0, top_count = 0, top = -1;
            for (int i = 0; i < n; ++i) {
                Embeddings result = embeddings(q->pattern, molecules[i]);
                if (result.count) {
                    ++hits;
                    total += result.count;
                    char *mapping = integers(&result.first, ",", 0);
                    line(&hit_lines, "%s count=%d unique=%d map=%s", molecules[i]->name,
                         result.count, result.unique, mapping);
                    free(mapping);
                    if (result.count > top_count) {
                        top = i;
                        top_count = result.count;
                    }
                }
                ints_free(&result.first);
            }
            Lines paragraph = {0};
            line(&paragraph, "MATCH %s %s atoms=%d bonds=%d hits=%zu embeddings=%d", q->id,
                 q->args[0], q->pattern->atom_count, q->pattern->bond_count, hit_lines.count,
                 total);
            lines_take(&paragraph, hit_lines);
            if (top >= 0)
                line(&paragraph, "top %s count=%d", molecules[top]->name, top_count);
            paragraph_add(&out, paragraph);
        } else if (q->kind == QUERY_CONTAINS) {
            ++contains;
            Molecule *x = molecules[molecule_index(molecules, n, q->args[0])],
                     *y = molecules[molecule_index(molecules, n, q->args[1])],
                     *pattern = molecule_pattern(x);
            Embeddings result = embeddings(pattern, y);
            Lines paragraph = {0};
            if (result.count) {
                ++found;
                char *mapping = integers(&result.first, ",", 0);
                line(&paragraph, "CONTAINS %s %s %s result=yes count=%d unique=%d map=%s", q->id,
                     x->name, y->name, result.count, result.unique, mapping);
                free(mapping);
            } else
                line(&paragraph, "CONTAINS %s %s %s result=no", q->id, x->name, y->name);
            ints_free(&result.first);
            molecule_free(pattern);
            paragraph_add(&out, paragraph);
        }
    }
    Lines summary = {0};
    line(&summary, "SUMMARY patterns=%d hits=%d contains=%d found=%d", patterns, hits, contains,
         found);
    paragraph_add(&out, summary);
    return out;
}
static Paragraphs similarity_paragraphs(Query *const *queries, int query_count,
                                        Molecule *const *molecules, int n) {
    Similarity *matrix = allocate((size_t)n * n * sizeof(Similarity));
    for (int i = 0; i < n; ++i)
        for (int j = i; j < n; ++j)
            matrix[i * n + j] = matrix[j * n + i] = similarity(molecules[i], molecules[j]);
    Paragraphs out = {0};
    Lines fingerprints = {0};
    line(&fingerprints, "FINGERPRINTS molecules=%d size=1024 depth=5", n);
    for (int i = 0; i < n; ++i)
        line(&fingerprints, "%s bits=%d paths=%d", molecules[i]->name, molecules[i]->bit_count,
             molecules[i]->paths);
    paragraph_add(&out, fingerprints);
    for (int qn = 0; qn < query_count; ++qn) {
        Query *q = queries[qn];
        Lines paragraph = {0};
        char f[32];
        if (q->kind == QUERY_MATRIX) {
            int indices[12];
            for (size_t i = 0; i < q->argument_count; ++i)
                indices[i] = molecule_index(molecules, n, q->args[i]);
            line(&paragraph, "MATRIX %s size=%zu", q->id, q->argument_count);
            int best_i = 0, best_j = 1;
            for (int i = 0; i < (int)q->argument_count; ++i) {
                Text row = {0};
                text_format(&row, "row %s", q->args[i]);
                for (int j = 0; j < (int)q->argument_count; ++j) {
                    Similarity value = matrix[indices[i] * n + indices[j]];
                    text_format(&row, " %s", fraction_text(value.value, f));
                    if (i < j &&
                        fraction_compare(value.value,
                                         matrix[indices[best_i] * n + indices[best_j]].value) > 0) {
                        best_i = i;
                        best_j = j;
                    }
                }
                lines_add(&paragraph, text_take(&row));
            }
            line(&paragraph, "best %s %s %s", q->args[best_i], q->args[best_j],
                 fraction_text(matrix[indices[best_i] * n + indices[best_j]].value, f));
        } else if (q->kind == QUERY_NEAREST || q->kind == QUERY_WITHIN) {
            int base = molecule_index(molecules, n, q->args[0]);
            IntList order = {0};
            for (int i = 0; i < n; ++i)
                if (i != base)
                    ints_add(&order, i);
            for (int i = 1; i < order.count; ++i) {
                int current = order.items[i], j = i;
                while (j && fraction_compare(matrix[base * n + current].value,
                                             matrix[base * n + order.items[j - 1]].value) > 0) {
                    order.items[j] = order.items[j - 1];
                    --j;
                }
                order.items[j] = current;
            }
            if (q->kind == QUERY_NEAREST) {
                if (order.count > q->count)
                    order.count = q->count;
                line(&paragraph, "NEAREST %s %s count=%d", q->id, q->args[0], order.count);
            } else {
                int count = 0;
                for (int i = 0; i < order.count; ++i)
                    if (fraction_compare(matrix[base * n + order.items[i]].value, q->threshold) >=
                        0)
                        order.items[count++] = order.items[i];
                order.count = count;
                line(&paragraph, "WITHIN %s %s threshold=%s count=%d", q->id, q->args[0],
                     fraction_text(q->threshold, f), order.count);
            }
            for (int i = 0; i < order.count; ++i) {
                int index = order.items[i];
                Similarity value = matrix[base * n + index];
                line(&paragraph, "%d %s %s common=%d", i + 1, molecules[index]->name,
                     fraction_text(value.value, f), value.common);
            }
            ints_free(&order);
        } else if (q->kind == QUERY_COMPARE) {
            int a = molecule_index(molecules, n, q->args[0]),
                b = molecule_index(molecules, n, q->args[1]);
            Similarity value = matrix[a * n + b];
            line(&paragraph,
                 "COMPARE %s %s %s bits=%d,%d common=%d union=%d tanimoto=%s identical=%s", q->id,
                 q->args[0], q->args[1], molecules[a]->bit_count, molecules[b]->bit_count,
                 value.common, value.total, fraction_text(value.value, f),
                 strcmp(molecules[a]->canonical, molecules[b]->canonical) == 0 ? "yes" : "no");
        } else if (q->kind == QUERY_CLUSTER) {
            IntList *neighbors = allocate((size_t)n * sizeof(IntList)),
                    *clusters = allocate((size_t)n * sizeof(IntList));
            memset(neighbors, 0, (size_t)n * sizeof(IntList));
            int *order = allocate((size_t)n * sizeof(int));
            bool *assigned = allocate((size_t)n * sizeof(bool));
            memset(assigned, 0, (size_t)n * sizeof(bool));
            for (int i = 0; i < n; ++i) {
                order[i] = i;
                for (int j = 0; j < n; ++j)
                    if (i != j && fraction_compare(matrix[i * n + j].value, q->threshold) >= 0)
                        ints_add(&neighbors[i], j);
            }
            for (int i = 1; i < n; ++i) {
                int current = order[i], j = i;
                while (j && neighbors[current].count > neighbors[order[j - 1]].count) {
                    order[j] = order[j - 1];
                    --j;
                }
                order[j] = current;
            }
            int cluster_count = 0, singletons = 0;
            for (int i = 0; i < n; ++i) {
                int center = order[i];
                if (assigned[center])
                    continue;
                IntList members = {0};
                ints_add(&members, center);
                assigned[center] = true;
                for (int j = 0; j < neighbors[center].count; ++j) {
                    int neighbor = neighbors[center].items[j];
                    if (!assigned[neighbor]) {
                        ints_add(&members, neighbor);
                        assigned[neighbor] = true;
                    }
                }
                singletons += members.count == 1;
                clusters[cluster_count++] = members;
            }
            line(&paragraph, "CLUSTER %s threshold=%s clusters=%d singletons=%d", q->id,
                 fraction_text(q->threshold, f), cluster_count, singletons);
            int serial = 0;
            for (int i = 0; i < cluster_count; ++i) {
                IntList members = clusters[i];
                if (members.count >= 2) {
                    char *names = member_names(molecules, &members);
                    line(&paragraph, "cluster %d centroid=%s size=%d members=%s", ++serial,
                         molecules[members.items[0]]->name, members.count, names);
                    free(names);
                }
                ints_free(&clusters[i]);
            }
            for (int i = 0; i < n; ++i)
                ints_free(&neighbors[i]);
            free(neighbors);
            free(clusters);
            free(order);
            free(assigned);
        }
        if (paragraph.count)
            paragraph_add(&out, paragraph);
    }
    free(matrix);
    return out;
}
typedef struct {
    char *name;
    int count;
} Cause;
static void cause_add(Cause causes[400], int *count, const char *name) {
    for (int i = 0; i < *count; ++i)
        if (strcmp(causes[i].name, name) == 0) {
            ++causes[i].count;
            return;
        }
    causes[*count] = (Cause){copy_text(name), 1};
    ++*count;
}
static void save_paragraphs(const char *name, Paragraphs paragraphs) {
    write_paragraphs(name, &paragraphs);
    paragraphs_free(&paragraphs);
}
int main(void) {
    Elements elements;
    read_elements(&elements);
    Molecule *molecules[300];
    int molecule_count = 0, molecule_lines = 0, seen_name_count = 0;
    char seen_names[300][33];
    Lines molecule_errors = {0}, query_errors = {0};
    Cause causes[400];
    int cause_count = 0;
    Lines source = read_lines("input/molecules.smi");
    for (size_t i = 0; i < source.count; ++i) {
        if (ignored(source.items[i]))
            continue;
        ++molecule_lines;
        Words tokens = split(source.items[i], ' ');
        if (tokens.count != 2 || !*tokens.items[0] || !valid_name(tokens.items[1])) {
            line(&molecule_errors, "line %zu: bad line", i + 1);
            cause_add(causes, &cause_count, "bad line");
            words_free(&tokens);
            continue;
        }
        const char *name = tokens.items[1];
        bool duplicate = false;
        for (int j = 0; j < seen_name_count; ++j)
            if (strcmp(name, seen_names[j]) == 0)
                duplicate = true;
        if (duplicate) {
            line(&molecule_errors, "line %zu %s: duplicate name", i + 1, name);
            cause_add(causes, &cause_count, "duplicate name");
            words_free(&tokens);
            continue;
        }
        strcpy(seen_names[seen_name_count++], name);
        ParseError error;
        Molecule *m = parse_smiles(tokens.items[0], &elements, false, &error);
        if (m && !analyze(m, &elements, &error)) {
            molecule_free(m);
            m = NULL;
        }
        if (!m) {
            line(&molecule_errors, "line %zu %s: %s at column %d", i + 1, name, error.reason,
                 error.column);
            cause_add(causes, &cause_count, error.reason);
            words_free(&tokens);
            continue;
        }
        m->name = copy_text(name);
        properties(m, &elements);
        canonical_ranks(m, &elements);
        m->canonical = canonical_smiles(m, &elements);
        m->scaffold = scaffold(m, &elements);
        fingerprint(m, &elements);
        molecules[molecule_count++] = m;
        words_free(&tokens);
    }
    lines_free(&source);
    Query *queries[100];
    int query_count = 0, query_lines = 0, seen_id_count = 0;
    char seen_ids[100][33];
    source = read_lines("input/queries.txt");
    for (size_t i = 0; i < source.count; ++i) {
        if (ignored(source.items[i]))
            continue;
        ++query_lines;
        Words tokens = split(source.items[i], ' ');
        char *reason = NULL;
        Query *q = check_query(&tokens, seen_ids, &seen_id_count, molecules, molecule_count,
                               &elements, &reason);
        if (reason) {
            if (strcmp(reason, "unknown query") == 0)
                line(&query_errors, "line %zu: unknown query", i + 1);
            else if (strcmp(reason, "bad id") == 0)
                line(&query_errors, "line %zu %s: bad id", i + 1, tokens.items[0]);
            else
                line(&query_errors, "line %zu %s %s: %s", i + 1, tokens.items[0], tokens.items[1],
                     reason);
            const char *cause = strncmp(reason, "bad pattern ", 12) == 0        ? "bad pattern"
                                : strncmp(reason, "unknown molecule ", 17) == 0 ? "unknown molecule"
                                                                                : reason;
            cause_add(causes, &cause_count, cause);
            free(reason);
        } else
            queries[query_count++] = q;
        words_free(&tokens);
    }
    lines_free(&source);
    Lines property_lines = {0};
    line(&property_lines,
         "name,formula,weight,heavy_atoms,rings,rotatable,donors,acceptors,lipinski");
    for (int i = 0; i < molecule_count; ++i) {
        Molecule *m = molecules[i];
        line(&property_lines, "%s,%s,%d.%03d,%d,%d,%d,%d,%d,%s", m->name, m->formula,
             m->weight / 1000, m->weight % 1000, m->heavy, m->ring_count, m->rotatable, m->donors,
             m->acceptors, m->lipinski);
    }
    Lines mol_errors = {0}, que_errors = {0}, cause_lines = {0};
    line(&mol_errors, "MOLECULES lines=%d valid=%d errors=%zu", molecule_lines, molecule_count,
         molecule_errors.count);
    lines_take(&mol_errors, molecule_errors);
    line(&que_errors, "QUERIES lines=%d valid=%d errors=%zu", query_lines, query_count,
         query_errors.count);
    lines_take(&que_errors, query_errors);
    int order[400];
    for (int i = 0; i < cause_count; ++i)
        order[i] = i;
    for (int i = 1; i < cause_count; ++i) {
        int current = order[i], j = i;
        while (j) {
            Cause a = causes[current], b = causes[order[j - 1]];
            bool less = a.count != b.count ? a.count > b.count : strcmp(a.name, b.name) < 0;
            if (!less)
                break;
            order[j] = order[j - 1];
            --j;
        }
        order[j] = current;
    }
    line(&cause_lines, "CAUSES kinds=%d", cause_count);
    for (int i = 0; i < cause_count; ++i)
        line(&cause_lines, "%s=%d", causes[order[i]].name, causes[order[i]].count);
    Paragraphs errors = {0};
    paragraph_add(&errors, mol_errors);
    paragraph_add(&errors, que_errors);
    paragraph_add(&errors, cause_lines);
    if (mkdir("output", 0777) != 0 && errno != EEXIST) {
        perror("output");
        exit(EXIT_FAILURE);
    }
    write_lines("properties.csv", &property_lines);
    save_paragraphs("canonical.txt", canonical_paragraphs(molecules, molecule_count));
    save_paragraphs("rings.txt", ring_paragraphs(molecules, molecule_count, &elements));
    save_paragraphs("substructure.txt",
                    substructure_paragraphs(queries, query_count, molecules, molecule_count));
    save_paragraphs("similarity.txt",
                    similarity_paragraphs(queries, query_count, molecules, molecule_count));
    save_paragraphs("errors.txt", errors);
    lines_free(&property_lines);
    for (int i = 0; i < query_count; ++i) {
        molecule_free(queries[i]->pattern);
        words_free(&queries[i]->source);
        free(queries[i]);
    }
    for (int i = 0; i < molecule_count; ++i)
        molecule_free(molecules[i]);
    for (int i = 0; i < cause_count; ++i)
        free(causes[i].name);
    return EXIT_SUCCESS;
}
