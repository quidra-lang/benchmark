#ifndef RATINGS_H
#define RATINGS_H
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
typedef struct { char *data; size_t size, capacity; } Text;
typedef struct { Integer numerator, denominator; } Fraction;
typedef struct { char *code, *name; } Team;
typedef struct { int round, home, away, home_score, away_score, margin, y2; } Match;
typedef struct {
    Integer win_points, draw_points, elo_k, elo_home, elo_initial, simulations, seed;
    Integer close_margin, bt_iterations, od_iterations, link_iterations, upsets;
    int form_length, holdout_round, calibration_bins, top_positions, bottom_positions;
    double exponent;
    Integer *grid_k, *grid_home;
    int grid_k_count, grid_home_count;
} Settings;
typedef struct { Team teams[30]; Match matches[600]; int n, count, rounds; Settings settings; } Season;
typedef struct { double ratings[30], expected[600], changes[600], round_ratings[40][30]; } EloRun;
typedef struct { double alpha, beta; } Link;
typedef struct { bool exact; Fraction fraction; double real; } Comparison;

void *allocate(size_t bytes);
char *format(const char *pattern, ...);
void text_add(Text *text, const char *pattern, ...);
void add_line(Lines *lines, const char *pattern, ...);
Lines read_lines(const char *name);
Lines split_text(const char *text, char separator);
void paragraph(Lines *target, Lines source);
Season *load_season(void);
int matches_before(const Season *season, int round);
double match_result(const Match *match);
double expected_score(double home, double away, double advantage);
EloRun run_elo(int n, const Match *matches, int count, Integer k, Integer home, Integer initial);
void colley_ratings(int n, const Match *matches, int count, double *ratings);
double massey_ratings(int n, const Match *matches, int count, double *ratings);
double bradley_terry(int n, const Match *matches, int count, Integer iterations, double *strengths);
void offense_defense(int n, const Match *matches, int count, Integer iterations, double *offense, double *defense, double *ratings);
Fraction fraction(Integer numerator, Integer denominator);
Fraction fraction_add(Fraction first, Fraction second);
Fraction fraction_multiply(Fraction first, Fraction second);
Fraction fraction_divide(Fraction value, Integer divisor);
int fraction_compare(Fraction first, Fraction second);
double fraction_real(Fraction value);
char *fraction_text(Fraction value);
char *fraction_fixed(Fraction value, int places);
char *fraction_with_real(Fraction value);
char *fixed(double value, int places);
double decimal_value(double value, int places);
void write_lines(const char *name, Lines lines);
double sigma(double value);
Link fit_link(const double *features, const Match *matches, int count, Integer iterations);
double log_loss(double probability, int y2);
double brier_score(double probability, int y2);
int correctness(double probability, int y2);
int comparison_compare(Comparison first, Comparison second);
Fraction kendall_tau(const Comparison *first, const Comparison *second, int count);
Fraction spearman_rho(const Comparison *first, const Comparison *second, int count);
#endif
