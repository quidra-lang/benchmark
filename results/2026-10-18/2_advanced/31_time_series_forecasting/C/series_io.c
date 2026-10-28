#include "forecasting.h"
#include <stdarg.h>
char *format(const char *pattern, ...) {
    va_list args, measure;
    va_start(args, pattern);
    va_copy(measure, args);
    int length = vsnprintf(NULL, 0, pattern, measure);
    va_end(measure);
    char *text = malloc((size_t)length + 1);
    vsnprintf(text, (size_t)length + 1, pattern, args);
    va_end(args);
    return text;
}
static char *read_line(FILE *file) {
    size_t count = 0, capacity = 128;
    char *text = malloc(capacity);
    int c;
    while ((c = fgetc(file)) != EOF && c != '\n') {
        if (count + 1 == capacity) {
            capacity *= 2;
            text = realloc(text, capacity);
        }
        text[count++] = (char)c;
    }
    if (c == EOF && !count) {
        free(text);
        return NULL;
    }
    text[count] = 0;
    return text;
}
static int series_index(const Input *input, const char *name) {
    for (int i = 0; i < input->series_count; ++i)
        if (!strcmp(input->series[i].name, name))
            return i;
    abort();
}
Input read_input(void) {
    Input input = {0};
    Params *p = &input.params;
    FILE *file = fopen("input/params.txt", "r");
    char *line;
    int row = 0;
    while ((line = read_line(file))) {
        char *key = strtok(line, " "), *value = strtok(NULL, " ");
        (void)key;
        switch (row++) {
        case 0:
            p->season = atoi(value);
            break;
        case 1:
            p->holdout = atoi(value);
            break;
        case 2:
            p->horizon = atoi(value);
            break;
        case 3:
            p->cv_start = atoi(value);
            break;
        case 4:
            p->combo = atoi(value);
            break;
        case 5:
        case 6:
        case 7:
        case 8: {
            int index = row - 1;
            Vector *values = index == 5   ? &p->alpha
                             : index == 6 ? &p->beta
                             : index == 7 ? &p->gamma
                                          : &p->phi;
            do {
                values->values[values->count++] = strtod(value, NULL);
            } while ((value = strtok(NULL, " ")));
            break;
        }
        case 9:
            p->max_ar = atoi(value);
            break;
        case 10:
            p->max_lag = atoi(value);
            break;
        case 11:
            do {
                p->ljung_box.values[p->ljung_box.count++] = atoi(value);
            } while ((value = strtok(NULL, " ")));
            break;
        case 12:
            p->outlier = strtod(value, NULL);
            break;
        case 13:
            p->z80 = strtod(value, NULL);
            p->z95 = strtod(strtok(NULL, " "), NULL);
            break;
        }
        free(line);
    }
    fclose(file);
    file = fopen("input/series.csv", "r");
    free(read_line(file));
    while ((line = read_line(file))) {
        char *name = strtok(line, ","), *period = strtok(NULL, ","), *value = strtok(NULL, ",");
        if (!input.series_count || strcmp(input.series[input.series_count - 1].name, name)) {
            strcpy(input.series[input.series_count++].name, name);
        }
        Series *series = &input.series[input.series_count - 1];
        int t = series->raw.count++;
        strcpy(series->periods[t], period);
        series->missing[t] = !strcmp(value, "NA");
        series->raw.values[t] = series->missing[t] ? 0 : strtod(value, NULL);
        free(line);
    }
    fclose(file);
    file = fopen("input/events.csv", "r");
    free(read_line(file));
    while ((line = read_line(file))) {
        Event *event = &input.events[input.event_count++];
        strcpy(event->series, strtok(line, ","));
        strcpy(event->period, strtok(NULL, ","));
        strcpy(event->kind, strtok(NULL, ","));
        free(line);
    }
    fclose(file);
    file = fopen("input/inventory.csv", "r");
    free(read_line(file));
    while ((line = read_line(file))) {
        char *name = strtok(line, ",");
        Inventory *policy = &input.inventory[series_index(&input, name)];
        policy->on_hand = strtoll(strtok(NULL, ","), NULL, 10);
        policy->lead_time = atoi(strtok(NULL, ","));
        policy->review = atoi(strtok(NULL, ","));
        policy->service = strtod(strtok(NULL, ","), NULL);
        free(line);
    }
    fclose(file);
    return input;
}
void next_month(const char *period, char *result) {
    int year, month;
    sscanf(period, "%d-%d", &year, &month);
    if (++month == 13) {
        month = 1;
        ++year;
    }
    snprintf(result, 8, "%04d-%02d", year, month);
}
char *real(double value) {
    char *text = format("%.4f", value);
    if (!strcmp(text, "-0.0000"))
        memmove(text, text + 1, strlen(text));
    return text;
}
void write_lines(FILE *file, char **lines, int count) {
    for (int i = 0; i < count; ++i)
        fprintf(file, "%s\n", lines[i]);
}
