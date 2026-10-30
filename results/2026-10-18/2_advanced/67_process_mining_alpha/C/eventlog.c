#include "mining.h"
Input read_inputs(void) {
    Input out = {0};
    out.rows = calloc(3000, sizeof(Event));
    FILE *in = fopen("input/eventlog.csv", "r");
    char buffer[160];
    fgets(buffer, sizeof buffer, in);
    int number = 2;
    while (fgets(buffer, sizeof buffer, in)) {
        Event *e = &out.rows[out.row_count++];
        e->line = number++;
        sscanf(buffer, "%8[^,],%20[^,],%16[^,],%12[^\n]", e->case_id, e->activity, e->timestamp,
               e->resource);
    }
    fclose(in);
    in = fopen("input/params.txt", "r");
    for (int i = 0; i < 8; ++i)
        fscanf(in, "%31s %31s", out.keys[i], out.values[i]);
    fclose(in);
    return out;
}
int timestamp_minutes(const char *value, I *time) {
    const int days[12] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    int month = (value[5] - '0') * 10 + value[6] - '0',
        day = (value[8] - '0') * 10 + value[9] - '0',
        hour = (value[11] - '0') * 10 + value[12] - '0',
        minute = (value[14] - '0') * 10 + value[15] - '0';
    if (month < 1 || month > 12 || day < 1 || day > days[month - 1] || hour > 23 || minute > 59)
        return 0;
    I before = 0;
    for (int i = 0; i < month - 1; ++i)
        before += days[i];
    *time = ((before + day - 1) * 24 + hour) * 60 + minute;
    return 1;
}
static int compare_events(const void *left, const void *right) {
    const Event *a = *(Event *const *)left, *b = *(Event *const *)right;
    if (a->time != b->time)
        return (a->time > b->time) - (a->time < b->time);
    return a->line - b->line;
}
static int compare_cases(const void *left, const void *right) {
    return strcmp(((const Case *)left)->id, ((const Case *)right)->id);
}
Case *group_cases(Event *events, int event_count, int *case_count) {
    Case *out = calloc(300, sizeof(Case));
    *case_count = 0;
    for (int i = 0; i < event_count; ++i) {
        int c = 0;
        while (c < *case_count && strcmp(out[c].id, events[i].case_id))
            ++c;
        if (c == *case_count) {
            strcpy(out[c].id, events[i].case_id);
            ++*case_count;
        }
        out[c].events[out[c].count++] = &events[i];
    }
    qsort(out, (size_t)*case_count, sizeof(Case), compare_cases);
    for (int c = 0; c < *case_count; ++c) {
        qsort(out[c].events, (size_t)out[c].count, sizeof(Event *), compare_events);
        out[c].duration = out[c].events[out[c].count - 1]->time - out[c].events[0]->time;
    }
    return out;
}
static int compare_values(const void *left, const void *right) {
    I a = *(const I *)left, b = *(const I *)right;
    return (a > b) - (a < b);
}
Fraction median(const I *values, int count) {
    I *sorted = malloc((size_t)count * sizeof(I));
    memcpy(sorted, values, (size_t)count * sizeof(I));
    qsort(sorted, (size_t)count, sizeof(I), compare_values);
    Fraction out = count % 2 ? ratio(sorted[count / 2], 1)
                             : ratio(sorted[count / 2 - 1] + sorted[count / 2], 2);
    free(sorted);
    return out;
}
