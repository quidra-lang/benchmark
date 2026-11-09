#include "survival.h"
#include <stdarg.h>
void *resize(void *memory, size_t size) {
    void *out = realloc(memory, size ? size : 1);
    if (!out)
        exit(1);
    return out;
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
void line_push(Lines *lines, char *line) {
    if (lines->count == lines->capacity) {
        lines->capacity = lines->capacity ? 2 * lines->capacity : 16;
        lines->data = resize(lines->data, (size_t)lines->capacity * sizeof(char *));
    }
    lines->data[lines->count++] = line;
}
void lines_extend(Lines *target, const Lines *source) {
    for (int i = 0; i < source->count; ++i)
        line_push(target, text(source->data[i]));
}
void lines_free(Lines *lines) {
    for (int i = 0; i < lines->count; ++i)
        free(lines->data[i]);
    free(lines->data);
    *lines = (Lines){0};
}
void int_push(IntList *list, int value) {
    if (list->count == list->capacity) {
        list->capacity = list->capacity ? 2 * list->capacity : 8;
        list->data = resize(list->data, (size_t)list->capacity * sizeof(int));
    }
    list->data[list->count++] = value;
}
static int compare_int(const void *a, const void *b) {
    int x = *(const int *)a, y = *(const int *)b;
    return (x > y) - (x < y);
}
void int_sort(IntList *list) {
    if (list->count > 1)
        qsort(list->data, (size_t)list->count, sizeof(int), compare_int);
}
void subject_push(Subjects *subjects, Subject subject) {
    if (subjects->count == subjects->capacity) {
        subjects->capacity = subjects->capacity ? 2 * subjects->capacity : 16;
        subjects->data = resize(subjects->data, (size_t)subjects->capacity * sizeof(Subject));
    }
    subjects->data[subjects->count++] = subject;
}
static Lines read_lines(const char *path) {
    Lines out = {0};
    FILE *file = fopen(path, "rb");
    char *buffer = NULL;
    size_t length = 0, capacity = 0;
    int character;
    while ((character = fgetc(file)) != EOF) {
        if (character == '\n') {
            if (length + 1 > capacity)
                buffer = resize(buffer, length + 1);
            buffer[length] = 0;
            line_push(&out, text(buffer));
            length = 0;
        } else {
            if (length + 1 >= capacity) {
                capacity = capacity ? 2 * capacity : 128;
                buffer = resize(buffer, capacity);
            }
            buffer[length++] = (char)character;
        }
    }
    free(buffer);
    fclose(file);
    return out;
}
static Lines split(const char *value, char delimiter) {
    Lines out = {0};
    const char *first = value;
    while (true) {
        const char *end = strchr(first, delimiter);
        size_t length = end ? (size_t)(end - first) : strlen(first);
        char *part = resize(NULL, length + 1);
        memcpy(part, first, length);
        part[length] = 0;
        line_push(&out, part);
        if (!end)
            break;
        first = end + 1;
    }
    return out;
}
static int subject_compare(const void *a, const void *b) {
    const Subject *x = a, *y = b;
    return (x->id > y->id) - (x->id < y->id);
}
Dataset *read_dataset(void) {
    Dataset *out = calloc(1, sizeof(Dataset));
    Lines lines = read_lines("input/params.txt");
    for (int i = 0; i < lines.count; ++i) {
        Lines fields = split(lines.data[i], ' ');
        const char *key = fields.data[0];
        Lines *list = !strcmp(key, "GROUPS")      ? &out->params.groups
                      : !strcmp(key, "SUBGROUPS") ? &out->params.subgroups
                      : !strcmp(key, "COX")       ? &out->params.covariates
                                                  : NULL;
        if (list) {
            for (int j = 1; j < fields.count; ++j)
                line_push(list, text(fields.data[j]));
        } else if (!strcmp(key, "REPORT_TIMES")) {
            for (int j = 1; j < fields.count; ++j)
                int_push(&out->params.report_times, atoi(fields.data[j]));
        } else if (!strcmp(key, "TAU"))
            out->params.tau = atoi(fields.data[1]);
        else if (!strcmp(key, "LIFE_TABLE")) {
            out->params.life_width = atoi(fields.data[1]);
            out->params.life_intervals = atoi(fields.data[2]);
        } else if (!strcmp(key, "STRATA"))
            out->params.strata = text(fields.data[1]);
        else if (!strcmp(key, "LANDMARK"))
            out->params.landmark = atoi(fields.data[1]);
        else if (!strcmp(key, "RESIDUALS"))
            out->params.residuals = atoi(fields.data[1]);
        else if (!strcmp(key, "PLOT")) {
            out->params.plot_width = atoi(fields.data[1]);
            out->params.plot_height = atoi(fields.data[2]);
            out->params.plot_time = atoi(fields.data[3]);
            out->params.plot_divisions = atoi(fields.data[4]);
        }
        lines_free(&fields);
    }
    lines_free(&lines);
    lines = read_lines("input/subjects.csv");
    for (int i = 1; i < lines.count; ++i) {
        Lines fields = split(lines.data[i], ',');
        int group = 0;
        while (strcmp(out->params.groups.data[group], fields.data[1]))
            ++group;
        Subject subject = {atoi(fields.data[0]), group,
                           atoi(fields.data[2]), atoi(fields.data[3]),
                           atoi(fields.data[4]), atoi(fields.data[6]),
                           fields.data[5][0]};
        subject_push(&out->subjects, subject);
        lines_free(&fields);
    }
    lines_free(&lines);
    qsort(out->subjects.data, (size_t)out->subjects.count, sizeof(Subject), subject_compare);
    return out;
}
