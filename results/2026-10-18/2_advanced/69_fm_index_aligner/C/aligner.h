#ifndef ALIGNER_H
#define ALIGNER_H
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <stdint.h>
#include <limits.h>
#include <sys/stat.h>
typedef int64_t I;
typedef struct {
    char **values;
    int count, capacity;
} Lines;
typedef struct {
    char *data;
    size_t length, capacity;
} Text;
char *format(const char *pattern, ...), *read_line(FILE *input), *ratio(I numerator, I denominator);
void text(Text *out, const char *pattern, ...), line(Lines *out, const char *pattern, ...),
    save(const char *name, const Lines *lines);
typedef struct {
    char name[17];
    char *bases;
    int masked, length;
} Reference;
typedef struct {
    char name[33];
    char *bases, *quality;
    int length;
} Read;
typedef struct {
    Reference references[10];
    Read reads[400];
    int reference_count, read_count, parameters[16][4];
} Input;
Input *read_inputs(void);
char *reverse_complement(const char *sequence);
typedef struct {
    int mismatches, minimum_length, trim_quality, seed_length, seed_step, maximum_seed_hits,
        band_width, match, mismatch, gap_open, gap_extend, minimum_score, maximum_alternatives,
        occ_interval, sample_interval, direct_limit, coverage_window, coverage_mapq, variant_depth,
        variant_quality, variant_percent, homozygous_percent;
} Params;
int symbol_number(char symbol);
int *counting_sort(const int *positions, int length, const int *keys, int key_count);
typedef struct {
    int *order, classes[32], class_count, size;
} SuffixArray;
SuffixArray suffix_array(const char *text);
int *direct_sort(const char *text);
typedef struct {
    int ordered, maximum, row;
    I lcp_sum;
} Check;
Check adjacent_check(const char *text, const int *suffixes, int length);
typedef struct {
    int lower, upper;
} Interval;
typedef struct {
    int size, interval, C[6], (*checkpoints)[6], checkpoint_count, *samples, sample_count;
    char *bwt;
} Index;
Index build_index(const char *text, const int *suffixes, int occurrence_interval,
                  int sample_interval);
int occurrence(const Index *index, char symbol, int position), lf(const Index *index, int row);
Interval extend(const Index *index, Interval interval, char base),
    backward_search(const Index *index, const char *sequence);
int locate(const Index *index, int row, int *steps);
char *inverse(const Index *index);
int *lower_bounds(const char *sequence, const Index *reverse);
typedef struct {
    int lower, upper, mismatches;
} Leaf;
typedef struct {
    Leaf *leaves;
    int leaf_count, capacity, nodes, positions;
} Search;
Search backtrack(const char *sequence, int maximum, const Index *forward, const Index *reverse);
typedef struct {
    int read, reference;
} AlignedPair;
typedef struct {
    int reference, position, strand, nm;
    char *operations, *oriented, *cigar, *md;
    AlignedPair *pairs;
    int pair_count;
} Alignment;
typedef struct {
    Read read;
    char *core;
    int qualities[100], length, trimmed, mapped, other_count, score, mapq, x0, x1;
    char *reason, *method;
    Alignment primary, *others;
    unsigned targets;
} Result;
Lines sam_header(const Input *input);
char *sam_record(const Result *result, const Input *input, int maximum_alternatives);
#endif
