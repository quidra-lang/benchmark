#include "columnar.h"
struct MemoryBlock {
    MemoryBlock *next;
    size_t used, capacity;
    max_align_t alignment;
    unsigned char data[];
};
Memory permanent = {0};
Memory *memory = &permanent;
void *allocate(size_t size) {
    size_t alignment = _Alignof(max_align_t);
    size = (size + alignment - 1) / alignment * alignment;
    if (!memory->head || memory->head->capacity - memory->head->used < size) {
        size_t capacity = size > 65536 ? size : 65536;
        MemoryBlock *block = malloc(sizeof(*block) + capacity);
        if (!block)
            exit(1);
        block->next = memory->head;
        block->used = 0;
        block->capacity = capacity;
        memory->head = block;
    }
    void *result = memory->head->data + memory->head->used;
    memory->head->used += size;
    memset(result, 0, size);
    return result;
}
void clear_memory(Memory *pool) {
    while (pool->head) {
        MemoryBlock *next = pool->head->next;
        free(pool->head);
        pool->head = next;
    }
}
char *substring(const char *source, size_t length) {
    char *result = allocate(length + 1);
    memcpy(result, source, length);
    return result;
}
char *copy_text(const char *source) { return substring(source, strlen(source)); }
char *format(const char *pattern, ...) {
    va_list arguments, copy;
    va_start(arguments, pattern);
    va_copy(copy, arguments);
    int length = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    char *result = allocate((size_t)length + 1);
    vsnprintf(result, (size_t)length + 1, pattern, arguments);
    va_end(arguments);
    return result;
}
Names split(const char *source, const char *separator) {
    Names out = {0};
    size_t length = strlen(separator);
    const char *start = source;
    for (;;) {
        const char *end = strstr(start, separator);
        Names_add(&out, end ? substring(start, (size_t)(end - start)) : copy_text(start));
        if (!end)
            return out;
        start = end + length;
    }
}
char *join(Names values, const char *separator) {
    size_t length = 1;
    for (size_t i = 0; i < values.count; ++i)
        length += strlen(values.items[i]) + (i ? strlen(separator) : 0);
    char *out = allocate(length), *at = out;
    for (size_t i = 0; i < values.count; ++i) {
        if (i) {
            size_t n = strlen(separator);
            memcpy(at, separator, n);
            at += n;
        }
        size_t n = strlen(values.items[i]);
        memcpy(at, values.items[i], n);
        at += n;
    }
    return out;
}
char *trim(const char *source) {
    while (*source == ' ')
        ++source;
    size_t length = strlen(source);
    while (length && source[length - 1] == ' ')
        --length;
    return substring(source, length);
}
Names read_lines(const char *path) {
    FILE *file = fopen(path, "rb");
    if (!file)
        exit(1);
    fseek(file, 0, SEEK_END);
    long length = ftell(file);
    rewind(file);
    char *source = allocate((size_t)length + 1);
    fread(source, 1, (size_t)length, file);
    fclose(file);
    Names lines = split(source, "\n");
    if (length && source[length - 1] == '\n')
        --lines.count;
    return lines;
}

const char *type_names[4] = {"INT", "STRING", "BOOL", "DATE"};
void append_bytes(Bytes *out, Bytes data) {
    for (size_t i = 0; i < data.count; ++i)
        Bytes_add(out, data.items[i]);
}
void extend_lines(Names *out, Names data) {
    for (size_t i = 0; i < data.count; ++i)
        Names_add(out, data.items[i]);
}
Value null_value(void) { return (Value){.null = true}; }
Value number_value(Number value) { return (Value){.number = value, .string = ""}; }
Value string_value(char *value) { return (Value){.string = value}; }
bool value_equal(Value a, Value b) {
    return a.null == b.null && a.unknown == b.unknown &&
           (a.null || (a.number == b.number && !strcmp(a.string, b.string)));
}
int value_compare(Value a, Value b) {
    if (a.null != b.null)
        return a.null ? -1 : 1;
    if (a.null)
        return 0;
    if (a.number != b.number)
        return a.number < b.number ? -1 : 1;
    int comparison = strcmp(a.string, b.string);
    return comparison < 0 ? -1 : comparison > 0;
}
static bool leap(int year) { return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0); }
static int month_days(int year, int month) {
    const int days[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    return days[month - 1] + (month == 2 && leap(year));
}
static Number before_year(int year) {
    Number y = year - 1;
    return 365 * y + y / 4 - y / 100 + y / 400;
}
Number day_number(const char *source) {
    int year = atoi(source), month = atoi(source + 5), day = atoi(source + 8);
    Number result = before_year(year) - before_year(1970) + day - 1;
    for (int m = 1; m < month; ++m)
        result += month_days(year, m);
    return result;
}
Value parse_value(Type kind, char *source) {
    if (!*source)
        return null_value();
    if (kind == T_STRING)
        return string_value(source);
    if (kind == T_BOOL)
        return number_value(!strcmp(source, "true"));
    return number_value(kind == T_DATE ? day_number(source) : atoll(source));
}
char *value_text(Type kind, Value value, const char *null_text) {
    if (value.unknown)
        return "?";
    if (value.null)
        return (char *)null_text;
    if (kind == T_STRING)
        return value.string;
    if (kind == T_BOOL)
        return value.number ? "true" : "false";
    if (kind == T_INT)
        return format("%lld", value.number);
    int year = 1970, month = 1;
    Number day = value.number;
    while (day < 0) {
        --year;
        day += leap(year) ? 366 : 365;
    }
    while (day >= (leap(year) ? 366 : 365)) {
        day -= leap(year) ? 366 : 365;
        ++year;
    }
    while (day >= month_days(year, month)) {
        day -= month_days(year, month);
        ++month;
    }
    return format("%04d-%02d-%02lld", year, month, day + 1);
}
Inputs read_inputs(void) {
    Inputs out = {0};
    Names lines = read_lines("input/schema.txt");
    for (size_t i = 0; i < lines.count; ++i) {
        Names f = split(lines.items[i], " ");
        int kind = 0;
        while (strcmp(type_names[kind], f.items[1]))
            ++kind;
        Columns_add(&out.columns,
                    (Column){f.items[0], (Type)kind, !strcmp(f.items[2], "NULLABLE")});
    }
    lines = read_lines("input/table.csv");
    for (size_t i = 1; i < lines.count; ++i) {
        Names fields = split(lines.items[i], ",");
        Row row = {0};
        for (size_t c = 0; c < out.columns.count; ++c)
            Values_add(&row, parse_value(out.columns.items[c].kind, fields.items[c]));
        Table_add(&out.rows, row);
    }
    lines = read_lines("input/options.txt");
    out.options.row_group_size = atoi(split(lines.items[0], " ").items[1]);
    out.options.page_size = atoi(split(lines.items[1], " ").items[1]);
    out.options.dictionary_limit = atoi(split(lines.items[2], " ").items[1]);
    for (size_t i = 3; i < lines.count; ++i) {
        char *method = split(lines.items[i], " ").items[2];
        int selected = -1;
        if (strcmp(method, "AUTO")) {
            selected = 0;
            while (strcmp(methods[selected], method))
                ++selected;
        }
        out.options.encoding[i - 3] = selected;
    }
    out.queries = read_lines("input/queries.txt");
    lines = read_lines("input/damaged.hex");
    for (size_t i = 0; i < lines.count; ++i)
        for (size_t j = 0; lines.items[i][j]; j += 2)
            Bytes_add(&out.damaged,
                      (unsigned char)strtol(substring(lines.items[i] + j, 2), NULL, 16));
    return out;
}
void write_lines(const char *filename, Names lines) {
    mkdir("output", 0777);
    FILE *file = fopen(format("output/%s", filename), "wb");
    for (size_t i = 0; i < lines.count; ++i)
        fprintf(file, "%s\n", lines.items[i]);
    fclose(file);
}
