#ifndef CIPHER_H
#define CIPHER_H

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef enum {
    CAESAR, AFFINE, VIGENERE, AUTOKEY, PLAYFAIR, RAILFENCE, COLUMNAR,
    CIPHER_COUNT
} Cipher;

typedef struct {
    int mono[26];
    int bigram[26][26];
} Weights;

typedef struct {
    int code;
    int count;
    int *positions;
    int gcd;
} Repeat;

typedef struct {
    int max_length;
    int indices[21][20];
    int averages[21];
    int kasiski[21];
    Repeat *repeats;
    int repeat_count;
    int gap_count;
} Profile;

typedef struct {
    int pair;
    int count;
} PairCount;

int letter_value(char character);
char *letter_string(const char *text);
bool read_weights(const char *path, Weights *weights);
int monogram_fitness(const Weights *weights, const char *text);
int bigram_fitness(const Weights *weights, const char *text);
char *substitute(Cipher cipher, const char *text, const char *key, bool decrypt);
int rail_number(int position, int rails);
char *rail_fence(const char *text, int rails, bool decrypt);
void column_ranks(const char *key, int ranks[9]);
void rank_string(const char *key, char *result);
char *columnar(const char *text, const char *key, bool decrypt);
void playfair_square(const char *key, char square[26]);
bool valid_playfair(const char *text);
char *playfair_prepare(const char *text);
char *playfair_transform(const char *text, const char *key, bool decrypt);
void letter_counts(const char *text, int counts[26]);
int index_of_coincidence(const char *text);
void column_indices(const char *text, int period, int *indices);
Profile *analyze_periods(const char *text, int max_length);
void free_profile(Profile *profile);
void percentage(int count, int total, char *result);
int pair_counts(const char *text, bool aligned, PairCount result[676]);

#endif
