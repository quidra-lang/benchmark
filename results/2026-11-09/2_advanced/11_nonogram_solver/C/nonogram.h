#ifndef NONOGRAM_H
#define NONOGRAM_H
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>

typedef enum { UNKNOWN,FILLED,EMPTY } Cell;
typedef struct { int count,values[50]; } Clue;
typedef struct { int width,height; Clue rows[30],columns[30]; } Model;
typedef struct { int width,height; Cell cells[30][30]; } Grid;
typedef struct { int row,column; Cell state; } Given;
typedef struct { bool row; int index,gain; bool contradiction; } Step;
typedef struct { Step *steps; size_t count,capacity; int conflict; } Propagation;
typedef enum { GUESS_OPEN,GUESS_CONTRADICTION,GUESS_SOLUTION1,GUESS_SOLUTION2 } GuessResult;
typedef struct { int number,depth,row,column; Cell value; int solves,known; GuessResult result; bool conflict_row; int conflict_index; } Guess;
typedef struct { Guess guesses[100]; int guess_count,max_depth,backtracks,line_solves; Grid solutions[2]; int solution_count; } Search;
void *resize(void *pointer,size_t bytes);
bool is_clue_line(const char *text);
bool parse_clue(const char *text,Clue *clue);
Clue run_clue(const Cell *cells,int length);
const char *clue_text(const Clue *clue,const char *separator);
int clue_span(const Clue *clue);
bool equal_clue(const Clue *a,const Clue *b);
bool has_placement(const Cell *cells,int length,const Clue *clue);
bool solve_line(const Cell *cells,int length,const Clue *clue,bool precise,Cell *solved);
const char *line_label(bool row,int index);
int line_cells(const Grid *grid,bool row,int index,Cell *cells);
int determined(const Grid *grid);
Propagation propagate(const Model *model,Grid *grid,bool precise,bool *row_marks,bool *column_marks);
void guess_cell(const Grid *grid,int *row,int *column);
bool search_run(const Model *model,Search *search,const Grid *grid,int depth);
char state_char(Cell state);
Cell char_state(char character);
void state_string(const Cell *cells,int length,char *text);
void grid_display(FILE *file,const char *const *names,const Grid *const *grids,int count);
void answer_sheet(FILE *file,const Model *model,const Grid *grid);
static inline int minimum(int a,int b) { return a<b?a:b; }
static inline int maximum(int a,int b) { return a>b?a:b; }
#endif
