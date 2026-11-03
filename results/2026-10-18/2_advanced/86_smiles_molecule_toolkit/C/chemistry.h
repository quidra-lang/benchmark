#ifndef CHEMISTRY_H
#define CHEMISTRY_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
typedef struct {
    int *items, count, capacity;
} IntList;
void ints_add(IntList *, int);
IntList ints_copy(const IntList *);
void ints_free(IntList *);
void ints_sort(IntList *);
bool ints_contains(const IntList *, int);
typedef struct {
    char symbol[3];
    int number, weight, valences[4], valence_count;
} Element;
typedef struct {
    Element items[40];
    int count;
} Elements;
typedef struct {
    int element;
    bool aromatic;
} Choice;
typedef struct {
    int element, mass, charge, hydrogens, column;
    bool aromatic, bracket;
    Choice *choices;
    int choice_count;
    char wildcard;
} Atom;
typedef struct {
    int a, b;
    char symbol;
    int type, multiplicity, match;
    bool ring;
} Bond;
typedef struct {
    char *name;
    Atom *atoms;
    int atom_count, atom_capacity;
    Bond *bonds;
    int bond_count, bond_capacity;
    IntList *adjacent, *rings;
    int ring_count, ring_capacity;
    bool *ring_atoms;
    int *ranks, classes;
    char *canonical, *scaffold, *formula;
    const char *lipinski;
    int weight, heavy, rotatable, donors, acceptors, charge;
    uint64_t bits[16];
    int bit_count, paths;
} Molecule;
typedef struct {
    const char *reason;
    int column;
} ParseError;
void read_elements(Elements *);
int element_index(const Elements *, const char *);
int bond_other(const Bond *, int);
Molecule *molecule_new(void);
void molecule_add_atom(Molecule *, Atom);
void molecule_add_bond(Molecule *, Bond);
void molecule_build(Molecule *);
const Bond *molecule_bond(const Molecule *, int, int);
int atom_base(const Molecule *, int);
int atom_multiplicity(const Molecule *, int);
bool needs_pi(const Molecule *, int, const Elements *, bool);
bool organic_hydrogens(const Molecule *, int, const Elements *, int *);
void molecule_free(Molecule *);
bool digit(char);
bool organic_atom(const char *, size_t, const Elements *, Atom *, size_t *);
const char *bracket_atom(const char *, const Elements *, Atom *);
int symbol_type(char);
Molecule *parse_smiles(const char *, const Elements *, bool, ParseError *);
const char *pattern_atom(const char *, size_t, const Elements *, Atom *, size_t *);
Molecule *molecule_pattern(const Molecule *);
void detect_rings(Molecule *);
bool kekulize(Molecule *, const Elements *, ParseError *);
void canonical_ranks(Molecule *, const Elements *);
char *canonical_smiles(const Molecule *, const Elements *);
typedef struct {
    int count, unique;
    IntList first;
} Embeddings;
Embeddings embeddings(const Molecule *, const Molecule *);
void fingerprint(Molecule *, const Elements *);
typedef struct {
    int n, d;
} Fraction;
typedef struct {
    Fraction value;
    int common, total;
} Similarity;
Fraction fraction(int, int);
int fraction_compare(Fraction, Fraction);
char *fraction_text(Fraction, char[32]);
Similarity similarity(const Molecule *, const Molecule *);
typedef struct {
    char **items;
    size_t count, capacity;
} Lines;
typedef struct {
    char *data;
    size_t count, capacity;
} Text;
typedef struct {
    char *storage, **items;
    size_t count;
} Words;
typedef struct {
    Lines *items;
    size_t count, capacity;
} Paragraphs;
void *allocate(size_t);
void *resize(void *, size_t);
char *copy_text(const char *);
char *format_text(const char *, ...);
void text_add(Text *, const char *);
void text_format(Text *, const char *, ...);
char *text_take(Text *);
void lines_add(Lines *, char *);
void line(Lines *, const char *, ...);
void lines_take(Lines *, Lines);
void lines_free(Lines *);
Words split(const char *, char);
void words_free(Words *);
bool ignored(const char *);
Lines read_lines(const char *);
void paragraph_add(Paragraphs *, Lines);
void paragraphs_free(Paragraphs *);
void write_lines(const char *, const Lines *);
void write_paragraphs(const char *, const Paragraphs *);
#endif
