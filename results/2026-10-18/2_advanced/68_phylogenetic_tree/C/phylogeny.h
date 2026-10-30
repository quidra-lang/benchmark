#ifndef PHYLOGENY_H
#define PHYLOGENY_H
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdarg.h>
#include <ctype.h>
#include <math.h>
#include <limits.h>
#include <sys/stat.h>
typedef unsigned Mask;
typedef struct {
    char **values;
    int count, capacity;
} Lines;
typedef struct {
    char *data;
    size_t length, capacity;
} Text;
char *format(const char *pattern, ...), *read_line(FILE *input), *real(double value, int digits),
    *symbols(Mask mask, int size);
void text(Text *text, const char *pattern, ...), line(Lines *lines, const char *pattern, ...),
    save(const char *name, const Lines *lines);
typedef struct {
    int line;
    char name[21];
    char *sequence;
} Record;
typedef struct {
    Record values[20];
    int count;
} Records;
int base_index(char character);
unsigned base_set(char character);
Records read_fasta(void);
typedef struct {
    char text[300][17];
    unsigned encoded[300][16];
    int weights[300], columns[300], count, length;
} Patterns;
Patterns *compress_patterns(char **sequences, int count, int length);
typedef struct {
    int constant, variable, informative, gapped, empty;
} Classes;
Classes classify(char **sequences, int count, int length);
typedef struct {
    int first, second, sites, transitions, transversions;
} Pair;
typedef struct {
    Pair values[120];
    int count;
} Pairs;
typedef struct {
    double values[16][16];
} Matrix;
Pairs all_pairs(char **sequences, int count, int length, const int *weights);
double corrected(int model, Pair pair, double replacement, int *saturated);
Matrix build_matrix(const Pairs *pairs, int model, double replacement, Pairs *saturated);
typedef struct {
    int size, next, negative;
    unsigned char present[32], adjacent[32][32];
    double length[32][32];
} Tree;
typedef struct {
    Mask values[80];
    int count;
} Masks;
typedef struct {
    int root, outgroup, parent[32], children[32][32], child_count[32], order[32], count;
    Mask masks[32], ingroup;
} Rooted;
Tree tree_create(int size), star(int size, const int *taxa, int count),
    neighbor_joining(const Matrix *matrix, int size, const int *taxa, int count);
int tree_internal(Tree *tree);
void connect(Tree *tree, int a, int b, double length);
double disconnect(Tree *tree, int a, int b);
Rooted rooted(const Tree *tree, int outgroup);
Masks split_set(const Tree *tree, const Rooted *root);
void paths(const Tree *tree, int start, int unit, double output[32]);
Matrix patristic(const Tree *tree);
typedef struct {
    unsigned sets[32];
    int changes;
} Provisional;
unsigned merge(unsigned a, unsigned b, int *changes);
Provisional provisional(const Tree *tree, const Rooted *root, const unsigned pattern[16]);
void pattern_scores(const Tree *tree, const Patterns *patterns, int outgroup, int *scores);
int score(const Tree *tree, const Patterns *patterns, int outgroup);
typedef struct {
    char ancestors[32][301];
    int changes[32][32], sites[300];
} Reconstruction;
Reconstruction *reconstruct(const Tree *tree, const Patterns *patterns, int outgroup);
typedef struct {
    Mask mask;
    int first, second;
} Branch;
typedef struct {
    Branch values[29];
    int count;
} Branches;
Branches branches(const Tree *tree, int outgroup);
Tree insert(const Tree *tree, int first, int second, int taxon);
typedef struct {
    Mask mask;
    int number;
    Tree tree;
} Swap;
typedef struct {
    Swap *values;
    int count;
} Swaps;
Swaps nni_candidates(const Tree *tree, int outgroup);
char *newick(const Tree *tree, char names[16][21], int outgroup, int lengths, const int *support);
Lines cladogram(const Tree *tree, char names[16][21], int outgroup, const int *support);
#endif
