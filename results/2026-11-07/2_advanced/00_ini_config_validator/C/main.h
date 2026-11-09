#ifndef MAIN_H
#define MAIN_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define VECTOR(type, name) typedef struct { type *data; size_t len, cap; } name
#define PUSH(v, item) do { \
    if ((v).len == (v).cap) { \
        (v).cap = (v).cap ? (v).cap * 2 : 8; \
        (v).data = checked_realloc((v).data, (v).cap * sizeof *(v).data); \
    } \
    (v).data[(v).len++] = (item); \
} while (0)

VECTOR(char *, Strings);
typedef struct { char *data; size_t len, cap; } Buffer;
typedef struct { char *document; int line; } Origin;
VECTOR(Origin, Origins);
typedef struct { Origin origin; char *code, *message; } Diagnostic;
VECTOR(Diagnostic, Diagnostics);
typedef struct {
    char *raw;
    Origin origin;
    int64_t number;
    Origins history;
} Definition;
typedef struct { char *key; Definition definition; } Entry;
VECTOR(Entry, Configuration);

typedef enum {
    TYPE_STRING, TYPE_INT, TYPE_BOOL, TYPE_ENUM, TYPE_SIZE, TYPE_DURATION,
    TYPE_HOST, TYPE_PATH, TYPE_URL, TYPE_DATE, TYPE_LIST
} Kind;
typedef struct Value Value;
struct Value {
    Kind kind;
    int64_t number;
    char *text;
    Value *items;
    size_t count;
};
typedef struct Spec Spec;
typedef struct {
    char *key;
    Definition definition;
    Spec *spec;
    Value value;
    char *notation;
} OutputKey;
VECTOR(OutputKey, Outputs);
typedef struct { char *section, *parent; Origin origin; } Parent;
VECTOR(Parent, Parents);
typedef struct { int depth; char *text; } TreeLine;
VECTOR(TreeLine, IncludeTree);
typedef struct {
    char *name, *root;
    int line;
    int64_t definition_count;
    Strings overrides;
    Configuration configuration;
    Parents parents;
    IncludeTree tree;
    Diagnostics diagnostics;
    Outputs outputs;
    int errors, warnings, document_keys, manifest_keys, default_keys;
    size_t configured_count, dropped;
} Profile;
VECTOR(Profile *, Profiles);
typedef struct { char mark; char *key; OutputKey *before, *after; } DiffEntry;
VECTOR(DiffEntry, DiffEntries);
typedef struct {
    char *first, *second;
    int added, removed, changed;
    DiffEntries entries;
} ProfileDiff;
VECTOR(ProfileDiff, Diffs);

void *checked_realloc(void *pointer, size_t size);
char *copy_text(const char *text);
char *slice(const char *text, size_t start, size_t length);
char *format(const char *pattern, ...);
void buffer_char(Buffer *buffer, char ch);
void buffer_text(Buffer *buffer, const char *text);
char *buffer_result(Buffer *buffer);
char *read_file(const char *path);
Strings split(const char *text, char separator);
Strings file_lines(const char *text);
char *trim_spaces(const char *text);
char *lowercase(const char *text);
char *section_of(const char *key);
const char *name_of(const char *key);
int compare_keys(const char *first, const char *second);
int key_comparator(const void *first, const void *second);
bool strings_contain(Strings strings, const char *text);
char *join_strings(Strings strings, const char *separator);
bool same_origin(Origin first, Origin second);
char *origin_text(Origin origin);
void report(Diagnostics *diagnostics, Origin origin, const char *code, char *message);
int configuration_index(Configuration configuration, const char *key);
int output_index(Outputs outputs, const char *key);
Strings configuration_keys(Configuration configuration);
Strings output_keys(Outputs outputs);
void sort_diagnostics(Profile *profile);

#endif
