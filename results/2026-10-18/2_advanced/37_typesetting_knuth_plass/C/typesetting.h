#ifndef TYPESETTING_H
#define TYPESETTING_H
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdarg.h>
#include <inttypes.h>
#include <limits.h>
typedef int64_t Integer;
typedef struct {
    char **data;
    size_t len, cap;
} Lines;
typedef struct {
    char *data;
    size_t len, cap;
} Text;
typedef struct {
    int *data;
    size_t len, cap;
} Ints;
void *allocate(size_t count, size_t size);
void grow(void **data, size_t *cap, size_t need, size_t size);
char *format(const char *pattern, ...);
void text_add(Text *text, const char *pattern, ...);
void line_add(Lines *lines, const char *pattern, ...);
void extend(Lines *out, Lines lines);
void int_add(Ints *values, int value);
Lines read_lines(const char *path);
Lines split(const char *text, char delimiter);
Lines words(const char *text);
char *join(Lines values, const char *delimiter);
char *number(Integer value);
char *lower(const char *value);
char *upper(const char *value);
char *trim(const char *value);
char *rtrim(const char *value);
char *spaces(int count);
bool letter(char c);
typedef struct {
    int line;
    char *message;
    size_t sequence;
} Warning;
typedef struct {
    Warning *data;
    size_t len, cap;
} Warnings;
typedef struct {
    int line;
    char *text;
} SourceLine;
typedef struct {
    SourceLine *data;
    size_t len, cap;
} SourceLines;
void source_add(SourceLines *values, int line, const char *text);
typedef enum {
    PARAGRAPH,
    ITEM,
    ENUMERATION,
    QUOTE,
    TERM,
    TITLE,
    AUTHOR,
    H1,
    H2,
    TABLE,
    VERBATIM,
    TOC,
    LOT,
    INDEX,
    BIBLIOGRAPHY
} Kind;
typedef struct {
    char *kind, *text;
    int id;
} Inline;
typedef struct {
    Inline *data;
    size_t len, cap;
} Tokens;
void token_add(Tokens *values, const char *kind, const char *text, int id);
typedef struct {
    Kind kind;
    int line, width, indent;
    char *align, *text, *term, *columns, *caption, *label, *number;
    bool page_break;
    int body_number;
    SourceLines body, inner;
    Tokens tokens;
    Lines *cells;
} Block;
typedef struct {
    Block *data;
    size_t len, cap;
} Blocks;
typedef struct {
    int line;
    char *key, *author, *year, *title, *base, *label;
    bool cited;
} Bib;
typedef struct {
    Bib *data;
    size_t len, cap;
} Bibs;
typedef struct {
    Blocks blocks;
    Bibs bibliography;
    Warnings warnings;
    Lines additions;
    int width, height;
    char *header[3], *footer[3];
} Document;
void warning_add(Document *doc, int line, const char *message);
Document parse_document(Lines lines);
bool body_kind(Kind kind);
typedef struct {
    Integer line_penalty, hyphen_penalty, double_hyphen_demerit, final_hyphen_demerit, fitness_demerit,
        overfull_penalty, left_min, right_min, orphan_lines, widow_lines, underfull_slack, underfull_page;
} Params;
typedef struct {
    char *word;
    Ints points;
} DictionaryWord;
typedef struct {
    DictionaryWord *data;
    size_t len, cap;
} Dictionary;
typedef struct {
    int position;
    bool hyphen;
} SplitPoint;
typedef struct {
    SplitPoint *data;
    size_t len, cap;
} SplitPoints;
void register_word(Dictionary *dictionary, const char *word);
SplitPoints split_points(const Dictionary *dictionary, const char *word, const Params *params);
typedef struct {
    int length, slack, gaps;
    bool mid, last, previous_mid;
} Measure;
typedef struct {
    Measure *data;
    size_t len, cap;
} Measures;
typedef Measure (*MeasureLine)(void *context, int a, int b);
typedef struct {
    Ints ends;
    Integer cost;
} Breaking;
int line_class(Measure line);
Integer line_cost(Measure line, int previous, const Params *p);
Breaking break_lines(int count, MeasureLine measure, void *context, const Params *p, bool greedy);
typedef struct {
    int word, first, last;
    char *text;
} Piece;
typedef struct {
    Piece *data;
    size_t len, cap;
} Pieces;
char *render_line(Pieces pieces, Measure line, const char *align);
Lines render_table(const Block *block);
typedef struct {
    char *page, *pages, *chapter, *section;
} HeadValues;
char *running_head(char *const fields[3], HeadValues values, int width, int serial);
typedef struct {
    char *text;
    Ints footnotes, indices;
    int first_block, toc_target, index_entry, dynamic_width;
} LayoutLine;
LayoutLine layout_line(const char *text);
typedef struct {
    LayoutLine *data;
    size_t len, cap;
} LayoutLines;
void layout_line_add(LayoutLines *lines, LayoutLine line);
typedef enum { HEADING, SOLID, FLOW } LayoutType;
typedef struct {
    LayoutLines lines;
    LayoutType type;
    bool list, page_break;
} LayoutBlock;
typedef struct {
    LayoutBlock *data;
    size_t len, cap;
} LayoutBlocks;
typedef struct {
    LayoutLines content;
    Ints footnotes;
    int height;
    bool forced, blank;
    char *display;
    int body_number;
} Page;
typedef struct {
    Page *data;
    size_t len, cap;
} Pages;
void page_add(Pages *pages, Page page);
Pages build_pages(LayoutBlocks blocks, Lines *footnotes, size_t footnote_count, const Params *p, int height);
Lines render_pages(Pages pages, Lines *footnotes, const Document *document, const int *block_pages,
                   int front);
#endif
