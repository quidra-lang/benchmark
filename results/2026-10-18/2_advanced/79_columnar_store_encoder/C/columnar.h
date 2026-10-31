#ifndef COLUMNAR_H
#define COLUMNAR_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
typedef long long Number;
typedef struct MemoryBlock MemoryBlock;
typedef struct {
    MemoryBlock *head;
} Memory;
extern Memory permanent;
extern Memory *memory;
void *allocate(size_t size);
void clear_memory(Memory *pool);
char *substring(const char *source, size_t length), *copy_text(const char *source),
    *format(const char *pattern, ...);
#define VECTOR(Name, Type)                                                                         \
    typedef struct {                                                                               \
        Type *items;                                                                               \
        size_t count, capacity;                                                                    \
    } Name;                                                                                        \
    static inline void Name##_add(Name *list, Type item) {                                         \
        if (list->count == list->capacity) {                                                       \
            size_t capacity = list->capacity ? list->capacity * 2 : 8;                             \
            Type *items = allocate(capacity * sizeof(Type));                                       \
            if (list->count)                                                                       \
                memcpy(items, list->items, list->count * sizeof(Type));                            \
            list->items = items;                                                                   \
            list->capacity = capacity;                                                             \
        }                                                                                          \
        list->items[list->count++] = item;                                                         \
    }
VECTOR(Names, char *)
VECTOR(Bytes, unsigned char)
VECTOR(Numbers, Number)
Names split(const char *source, const char *separator), read_lines(const char *path);
char *join(Names values, const char *separator), *trim(const char *source);
void append_bytes(Bytes *out, Bytes data), extend_lines(Names *out, Names data);
typedef enum { T_INT, T_STRING, T_BOOL, T_DATE } Type;
extern const char *type_names[4], *methods[5];
typedef struct {
    bool null, unknown;
    Number number;
    char *string;
} Value;
Value null_value(void), number_value(Number value), string_value(char *value);
bool value_equal(Value left, Value right);
int value_compare(Value left, Value right);
VECTOR(Values, Value)
typedef Values Row;
VECTOR(Table, Row)
typedef struct {
    bool present;
    Value low, high;
} Bounds;
typedef struct {
    char *name;
    Type kind;
    bool nullable;
} Column;
VECTOR(Columns, Column)
typedef struct {
    int row_group_size, page_size, dictionary_limit;
    int encoding[12];
} Options;
typedef struct {
    Columns columns;
    Table rows;
    Options options;
    Names queries;
    Bytes damaged;
} Inputs;
Number day_number(const char *source);
Value parse_value(Type kind, char *source);
char *value_text(Type kind, Value value, const char *null_text);
Inputs read_inputs(void);
void write_lines(const char *filename, Names lines);
typedef struct {
    const unsigned char *data;
    size_t length, position;
} Reader;
Reader reader_create(Bytes data, size_t position);
int read_byte(Reader *reader);
Bytes read_bytes(Reader *reader, size_t count);
char *read_string(Reader *reader, size_t count);
Number read_uleb(Reader *reader), read_zigzag(Reader *reader),
    read_integer(Reader *reader, bool signed_value);
void write_uleb(Bytes *out, Number value), write_zigzag(Bytes *out, Number value),
    write_integer(Bytes *out, Number value);
int bits(Number value);
Bytes pack(Numbers values, int width), hybrid_encode(Numbers values, int width);
Numbers unpack(Reader *reader, int width, int count),
    hybrid_decode(Reader *reader, int width, int count);
Number adler32(Bytes data);
char *hexadecimal(Bytes data), *checksum_text(Number checksum);
Numbers candidates(Type kind), delta_decode(Reader *reader);
Bytes delta_encode(Numbers values),
    encode_values(Type kind, int method, Values values, Values dictionary);
Values decode_values(Reader *reader, Type kind, int method, int count, Values dictionary);
Bytes encode_statistics(Type kind, Bounds bounds);
Bounds decode_statistics(Reader *reader, Type kind);
typedef struct {
    Type kind;
    Value value;
} Literal;
VECTOR(Literals, Literal)
typedef struct Condition Condition;
struct Condition {
    char *operation, *name;
    int column;
    Literals literals;
    Condition *left, *right;
};
typedef struct {
    char *operation, *name;
    int column;
} Item;
VECTOR(Items, Item)
typedef struct {
    Items items;
    bool star;
    Condition *condition;
    char *group_name, *order_name;
    int group, order, limit;
    bool descending, aggregate;
    unsigned needed, condition_columns;
    Names headers;
} Query;
Query parse_query(const char *source);
#endif
