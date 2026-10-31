#ifndef CROSSWORD_H
#define CROSSWORD_H
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <sys/stat.h>
#include <errno.h>

typedef struct { char **items; int count, capacity; } Lines;
typedef struct { char *data; size_t size, capacity; } Text;
typedef struct { int *values, count; } IntList;
typedef struct { char *text; int score, first; IntList clues; } Word;
typedef struct { Word words[2000]; int count; IntList length[16], letter[16][15][26]; } WordIndex;
typedef struct { int width, height; char cells[226]; } Grid;
typedef struct { int number, length, cells[15]; bool across; char *label; IntList crossings; } Slot;
typedef struct { Grid grid; Slot slots[150]; int count, numbers[225], across[225], down[225]; } Layout;
typedef struct { char letters[226]; int words[150]; bool used[2000]; } State;
enum Outcome { FILLED, UNFILLABLE, BUDGET };
typedef struct {
    const Layout *layout; const WordIndex *index;
    State state, best;
    int min_score, budget, nodes, backtracks, prunes, dead_ends, max_depth;
    int sequence[150], depth, failures[150];
    char *trace[10]; int trace_count;
    enum Outcome outcome;
} Attempt;
void *allocate(size_t bytes);
char *format(const char *pattern, ...);
void text_add(Text *text, const char *pattern, ...);
void add_line(Lines *lines, const char *pattern, ...);
void paragraph(Lines *target, Lines source);
void write_lines(const char *name, Lines lines);
char *decimal(int numerator, int denominator, int places);
void render_grid(const Grid *grid, const State *state, Lines *lines);
void render_numbers(const Layout *layout, Lines *lines);
char *list_line(const Slot *slot, const char *clue, const char *entry, const char *score, bool theme);
bool is_open(const Grid *grid, int row, int column);
int asymmetric_cell(const Grid *grid, const char *symmetry);
int component_count(const Grid *grid);
int run_length(const Grid *grid, int row, int column, bool across);
bool starts_run(const Grid *grid, int row, int column, bool across);
int short_run(const Grid *grid, bool *across);
Layout extract_slots(Grid grid);
int owner_count(const Layout *layout, int cell);
bool valid_word(const char *text);
bool valid_integer(const char *text, int low, int high);
const char *word_line_error(const char *line);
const char *clue_line_error(const char *line);
void build_index(WordIndex *index);
int find_word(const WordIndex *index, const char *word);
bool word_matches(const char *word, const char *pattern);
int candidates(const WordIndex *index, const char *pattern, int min_score, const bool *used, int *result);
void initial_state(const Layout *layout, State *state);
char *slot_pattern(const State *state, const Slot *slot);
void assign_word(State *state, const Slot *slot, const WordIndex *index, int word);
void run_attempt(Attempt *attempt, const Layout *layout, const WordIndex *index, const State *initial, int min_score, int budget);
#endif
