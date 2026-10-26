#ifndef CLASSIFIER_H
#define CLASSIFIER_H
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <math.h>
#include <stdint.h>
#include <sys/stat.h>
#include <errno.h>

typedef long long Integer;
typedef struct { char **items; int count, capacity; } Lines;
typedef struct { char *data; size_t size, capacity; } Text;
typedef struct { int *items, count; } Terms;
typedef struct { int raw_count, stopword_count, short_count; Terms words, bigram_terms; } Tokens;
typedef struct { char *name; int label; Tokens tokens; } Document;
typedef struct { int term, frequency, best_class; double score; } RankedTerm;
typedef struct { int term_count, candidate_count, size; int *terms, *frequencies, *map; RankedTerm *ranking; } Vocabulary;
typedef struct { int *terms, *first, *frequencies, count, distinct; } Encoded;
typedef struct {
    int classes, size, document_total, documents[8];
    Integer *occurrences, *containing, *term_totals, totals[8], total;
} TrainingCounts;
typedef struct { int kind, classes, size; double priors[8], base[8], *weights; } NaiveBayes;
typedef struct { int label, ranking[8]; double score, scores[8], probabilities[8], normalizer, margin; } Prediction;
typedef struct { int classes, size; double *idf, *centroids, lengths[8]; } Rocchio;
typedef struct { int classes, matrix[8][8], total, correct; double micro_f1, macro_f1; } Evaluation;

void *allocate(size_t bytes);
void *temporary(size_t count, size_t size);
char *format(const char *pattern, ...);
void text_add(Text *text, const char *pattern, ...);
void add_line(Lines *lines, const char *pattern, ...);
void paragraph(Lines *target, Lines source);
Lines read_lines(const char *name);
Lines split_text(const char *text, char separator);
Tokens tokenize(const char *text, Lines stopwords);
Terms token_terms(const Tokens *tokens, bool bigrams);
int term_count(void);
const char *term_name(int term);
Vocabulary build_vocabulary(Document *const *documents, int count, bool bigrams, int classes, int min_df, int size);
void free_vocabulary(Vocabulary *vocabulary);
Encoded encode(const Vocabulary *vocabulary, Terms terms);
void free_encoded(Encoded *sequence);
TrainingCounts training_counts(const Encoded *sequences, Document *const *documents, int count, int classes, int size);
void free_counts(TrainingCounts *counts);
double smoothed_log(Integer count, Integer total, int alpha, int outcomes);
NaiveBayes train_model(int kind, const TrainingCounts *counts, int alpha);
void free_model(NaiveBayes *model);
Prediction posterior(const double *scores, int classes);
Prediction predict_nb(const NaiveBayes *model, const Encoded *sequence);
Rocchio train_rocchio(const Encoded *sequences, Document *const *documents, int count, int classes, const Vocabulary *vocabulary);
Prediction predict_rocchio(const Rocchio *model, const Encoded *sequence);
void free_rocchio(Rocchio *model);
Evaluation evaluate(int classes, const int *truths, const int *predictions, int count);
Lines evaluation_lines(const Evaluation *evaluation, char *const *names);
char *real_text(double value);
char *proportion_text(Integer numerator, Integer denominator);
char *fraction_text(Integer numerator, Integer denominator);
double decimal_value(double value);
#endif
