#ifndef TIMEZONE_H
#define TIMEZONE_H
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <sys/stat.h>
#include <errno.h>

typedef long long Integer;
#define NEG_INFINITY (-(1LL << 62))
#define POS_INFINITY (1LL << 62)
typedef struct { char **items; int count, capacity; } Lines;
typedef struct { char *data; size_t size, capacity; } Text;
enum DayKind { DAY, LAST, AFTER, BEFORE };
typedef struct { enum DayKind kind; int weekday, day; } DaySpec;
typedef struct { int year, month, day, hour, minute, second; } DateTime;
typedef struct { char *year_text, *month_text, *day_text; Integer time, value; char type; } Until;
typedef struct Rule {
    int number, from, to, month; Lines fields; char *name, *letter;
    DaySpec day; Integer at, save; char type;
} Rule;
typedef struct { Rule *rule; Integer nominal; } Instance;
typedef struct { Instance *items; int count; } Instances;
typedef struct { Integer time; Rule *rule; } Applied;
typedef struct { Rule *pre_start; Applied *applied; int count; Integer end; } LineRun;
typedef struct { Integer start, offset; bool dst; char *abbreviation; } Period;
typedef struct { Period *items; int count, capacity; } Timeline;
typedef struct { int indices[2], count; } Candidates;

extern const char *month_names[12];
extern const char *weekday_names[7];
void *allocate(size_t bytes);
char *format(const char *pattern, ...);
void text_add(Text *text, const char *pattern, ...);
void add_line(Lines *lines, const char *pattern, ...);
void paragraph(Lines *target, Lines source);
Lines split_fields(const char *text);
char *slice(const char *text, size_t start, size_t length);
Integer floor_divide(Integer value, Integer divisor);
Integer modulo(Integer value, Integer divisor);
bool leap_year(int year);
int days_in_month(int year, int month);
Integer day_number(int year, int month, int day);
int weekday_of(Integer number);
Integer day_spec_value(DaySpec spec, int year, int month);
Integer time_value(DateTime date);
DateTime split_time(Integer time);
char *line_content(const char *raw);
bool digits(const char *text, int minimum, int maximum);
bool parse_year(const char *text, int *year);
bool parse_to(const char *text, int from, int *to);
bool parse_month(const char *text, int *month);
bool parse_day_spec(const char *text, int month, DaySpec *spec);
bool parse_time(const char *text, Integer *value, char *type);
bool parse_save(const char *text, Integer *value);
bool parse_letter(char *text, char **letter);
bool parse_offset(const char *text, Integer *value);
bool check_format(const char *text, bool rule_set);
Until *parse_until(Lines fields, int start, char **error);
Instances instance_sequence(Rule *const *rules, int count);
Integer adjustment(char type, Integer offset, Integer save);
LineRun run_instances(Instances instances, Integer offset, Integer start, const Until *until);
char *abbreviation(const char *text, Integer save, const char *letter);
int period_index(const Timeline *timeline, Integer time);
Integer period_end(const Timeline *timeline, int index);
Candidates candidates(const Timeline *timeline, Integer local);
int skipping_transition(const Timeline *timeline, Integer local);
char *local_text(Integer time);
char *ut_text(Integer time);
char *offset_text(Integer value);
char *duration_text(Integer value);
char *clock_text(Integer value);
char *state_text(const Period *period);
char *change_text(const Timeline *timeline, int index);
void write_lines(const char *name, Lines lines);
#endif
