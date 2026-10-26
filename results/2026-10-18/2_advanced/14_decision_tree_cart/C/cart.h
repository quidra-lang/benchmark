#ifndef CART_H
#define CART_H
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <math.h>
#include <sys/stat.h>
#include <errno.h>

typedef long long Integer;
typedef struct { char **items; int count, capacity; } Lines;
typedef struct { char name[21]; bool integer; char values[8][21]; int value_count; } Attribute;
typedef struct { char id[11]; Integer values[12]; int label; } Row;
typedef struct { const Row *items[500]; int count; } Rows;
typedef struct {
    int max_depth, min_split, min_leaf, max_surrogates, folds, bag_trees, repeats;
    Integer bag_seed, permutation_seed;
    int curve[500], curve_count;
} Settings;
typedef struct {
    Attribute attributes[12]; int attribute_count;
    char target[21], classes[6][21]; int class_count;
    Row train[500], validation[300], test[300]; int train_count, validation_count, test_count;
    Settings settings;
} Dataset;
typedef struct { Integer numerator, denominator; } Fraction;
typedef struct { Integer counts[6], size, squares, errors; int prediction; } Statistics;
typedef struct { int attribute; Integer point; } Split;
typedef struct { Split split; bool forward; Integer score; } Surrogate;
typedef struct { Split split; Rows left, right; Fraction value; } Candidate;
typedef struct Node {
    int number, depth;
    Statistics stats;
    bool branch, default_left;
    Split split;
    Surrogate surrogates[11]; int surrogate_count;
    struct Node *left, *right;
} Node;
typedef struct { const Node *root; bool cuts[2048]; } TreeView;
typedef struct { const Node *items[1000]; int count; } Nodes;
typedef enum { PRIMARY, SURROGATE, DEFAULT } Method;
typedef struct { const Node *node; bool left; Method method; } Step;
typedef struct { const Node *leaf, *path[11]; Step steps[10]; int count; } Route;
typedef struct { const Node *node; Integer rows, leaf_error, subtree_error; bool pruned; } Decision;
typedef struct { TreeView tree; Decision decisions[500]; int count; } PruningResult;
typedef struct { TreeView tree; Fraction alpha; } SequenceEntry;
typedef struct { SequenceEntry *items; int count; } Sequence;
void *allocate(size_t bytes);
char *format(const char *pattern, ...);
void add_line(Lines *lines, const char *pattern, ...);
Lines read_lines(const char *path);
char *counts_text(const Integer *counts, int count);
void load_dataset(Dataset *data);
Rows row_sequence(const Row *rows, int count);
Statistics statistics(Rows rows, int classes);
int majority(const Integer *counts, int classes);
int compare(Fraction first, Fraction second);
Fraction evaluation_value(Statistics left, Statistics right);
bool improves(Fraction value, Statistics parent);
double impurity_decrease(Statistics parent, Statistics left, Statistics right);
bool goes_left(const Dataset *data, Split split, const Row *row);
int split_candidates(const Dataset *data, Rows rows, int attribute, Split *result);
bool best_for_attribute(const Dataset *data, Rows rows, int attribute, Candidate *result);
Node *grow_tree(const Dataset *data, Rows rows, int number, int depth);
bool is_leaf(const TreeView *tree, const Node *node);
Nodes preorder(const TreeView *tree, const Node *start);
Nodes leaves(const TreeView *tree, const Node *start);
int tree_depth(const TreeView *tree);
Integer training_errors(const TreeView *tree);
Route route_row(const Dataset *data, const TreeView *tree, const Row *row);
int predict(const Dataset *data, const TreeView *tree, const Row *row);
Integer correct_count(const Dataset *data, const TreeView *tree, Rows rows);
char *real_text(double value, int places);
char *ratio(Integer numerator, Integer denominator);
char *fraction(Fraction value, int places);
Lines classification(const Dataset *data, const char *title, Rows rows, const int *predictions);
void reduced_error(const Dataset *data, const Node *root, Rows rows, PruningResult *result);
Sequence cost_complexity(const Node *root);
#endif
