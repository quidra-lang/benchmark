#include "mesh.h"
#include <stdarg.h>
void *resize(void *memory, size_t size) {
    void *result = realloc(memory, size ? size : 1);
    if (!result)
        exit(1);
    return result;
}
char *text(const char *value) {
    char *out = resize(NULL, strlen(value) + 1);
    strcpy(out, value);
    return out;
}
char *format(const char *pattern, ...) {
    va_list args, copy;
    va_start(args, pattern);
    va_copy(copy, args);
    int length = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    char *out = resize(NULL, (size_t)length + 1);
    vsnprintf(out, (size_t)length + 1, pattern, args);
    va_end(args);
    return out;
}
void int_push(IntList *list, int value) {
    if (list->count == list->capacity) {
        list->capacity = list->capacity ? 2 * list->capacity : 8;
        list->data = resize(list->data, (size_t)list->capacity * sizeof(int));
    }
    list->data[list->count++] = value;
}
bool int_contains(const IntList *list, int value) {
    for (int i = 0; i < list->count; ++i)
        if (list->data[i] == value)
            return true;
    return false;
}
IntList int_copy(const IntList *list) {
    IntList out = {0};
    for (int i = 0; i < list->count; ++i)
        int_push(&out, list->data[i]);
    return out;
}
void int_free(IntList *list) {
    free(list->data);
    *list = (IntList){0};
}
static int int_compare(const void *a, const void *b) {
    int x = *(const int *)a, y = *(const int *)b;
    return (x > y) - (x < y);
}
void int_sort(IntList *list) {
    if (list->count > 1)
        qsort(list->data, (size_t)list->count, sizeof(int), int_compare);
}
char *list(const IntList *values, int offset) {
    if (!values->count)
        return text("-");
    char *out = text("");
    for (int i = 0; i < values->count; ++i) {
        char *next = format("%s%s%d", out, i ? " " : "", values->data[i] + offset);
        free(out);
        out = next;
    }
    return out;
}
void line_push(Lines *lines, char *line) {
    if (lines->count == lines->capacity) {
        lines->capacity = lines->capacity ? 2 * lines->capacity : 8;
        lines->data = resize(lines->data, (size_t)lines->capacity * sizeof(char *));
    }
    lines->data[lines->count++] = line;
}
void free_lines(Lines *lines) {
    for (int i = 0; i < lines->count; ++i)
        free(lines->data[i]);
    free(lines->data);
    *lines = (Lines){0};
}
Lines read_lines(const char *path) {
    Lines out = {0};
    FILE *file = fopen(path, "rb");
    if (!file)
        return out;
    char buffer[256];
    while (fgets(buffer, sizeof buffer, file)) {
        size_t length = strlen(buffer);
        if (length && buffer[length - 1] == '\n')
            buffer[--length] = 0;
        line_push(&out, text(buffer));
    }
    fclose(file);
    return out;
}
Lines words(const char *line) {
    Lines out = {0};
    const char *position = line;
    while (*position) {
        while (*position == ' ')
            ++position;
        if (!*position)
            break;
        const char *first = position;
        while (*position && *position != ' ')
            ++position;
        size_t length = (size_t)(position - first);
        char *word = resize(NULL, length + 1);
        memcpy(word, first, length);
        word[length] = 0;
        line_push(&out, word);
    }
    return out;
}
bool integer_word(const char *word) {
    int first = word[0] == '-';
    if (!word[first])
        return false;
    for (int i = first; word[i]; ++i)
        if (word[i] < '0' || word[i] > '9')
            return false;
    return true;
}
Object *read_object(void) {
    Object *out = calloc(1, sizeof(Object));
    char *current = text("default");
    Lines lines = read_lines("input/model.obj");
    for (int i = 0; i < lines.count; ++i) {
        ++out->lines;
        const char *line = lines.data[i];
        if (!*line || *line == '#')
            continue;
        Lines tokens = words(line);
        const char *key = tokens.data[0], *error = NULL;
        if (!strcmp(key, "v")) {
            if (tokens.count != 4 || !integer_word(tokens.data[1]) || !integer_word(tokens.data[2]) ||
                !integer_word(tokens.data[3]))
                error = "bad_vertex";
            else {
                Point point = {{strtoll(tokens.data[1], NULL, 10), strtoll(tokens.data[2], NULL, 10),
                                strtoll(tokens.data[3], NULL, 10)}};
                out->vertices[++out->vertex_count] = point;
            }
        } else if (!strcmp(key, "f")) {
            Polygon polygon = {.line = out->lines};
            if (tokens.count < 4)
                error = "short_face";
            else
                for (int t = 1; t < tokens.count; ++t) {
                    char *vertex = text(tokens.data[t]);
                    char *slash = strchr(vertex, '/');
                    if (slash)
                        *slash = 0;
                    if (!integer_word(vertex) || strtoll(vertex, NULL, 10) == 0) {
                        error = "bad_index";
                        free(vertex);
                        break;
                    }
                    Integer index = strtoll(vertex, NULL, 10),
                            number = index > 0 ? index : out->vertex_count + 1 + index;
                    free(vertex);
                    if (number < 1 || number > out->vertex_count) {
                        error = "out_of_range";
                        break;
                    }
                    int_push(&polygon.vertices, (int)number);
                }
            if (!error) {
                int group = 0;
                while (group < out->groups.count && strcmp(out->groups.data[group], current))
                    ++group;
                if (group == out->groups.count)
                    line_push(&out->groups, text(current));
                polygon.group = group;
                out->polygons[out->polygon_count++] = polygon;
            } else
                int_free(&polygon.vertices);
        } else if (!strcmp(key, "g")) {
            free(current);
            current = text(tokens.count > 1 ? tokens.data[1] : "default");
        } else if (!strcmp(key, "vt") || !strcmp(key, "vn") || !strcmp(key, "s") || !strcmp(key, "o") ||
                   !strcmp(key, "usemtl") || !strcmp(key, "mtllib"))
            ++out->ignored;
        else
            error = "unknown_keyword";
        if (error)
            out->errors[out->error_count++] = (InputError){out->lines, text(error)};
        free_lines(&tokens);
    }
    free(current);
    free_lines(&lines);
    return out;
}
void write_lines(const char *name, const Lines *lines) {
    char *path = format("output/%s", name);
    FILE *file = fopen(path, "wb");
    free(path);
    if (!file)
        return;
    for (int i = 0; i < lines->count; ++i) {
        fputs(lines->data[i], file);
        fputc('\n', file);
    }
    fclose(file);
}
void write_object(const Cleanup *clean, const Lines *groups) {
    Lines out = {0};
    line_push(&out, format("# vertices %d faces %d", clean->point_count, clean->faces.count));
    for (int v = 1; v <= clean->point_count; ++v)
        line_push(&out, format("v %s", point_text(clean->points[v])));
    int group = -1;
    for (int f = 0; f < clean->faces.count; ++f) {
        const Face *face = &clean->faces.data[f];
        if (face->group != group) {
            group = face->group;
            line_push(&out, format("g %s", groups->data[group]));
        }
        line_push(&out, format("f %d %d %d", face->v[0], face->v[1], face->v[2]));
    }
    write_lines("repaired.obj", &out);
    free_lines(&out);
}
