#include "tides.h"
typedef struct Allocation {
    void *pointer;
    struct Allocation *next;
} Allocation;
static Allocation *allocations;
static void release(void) {
    while (allocations) {
        Allocation *next = allocations->next;
        free(allocations->pointer);
        free(allocations);
        allocations = next;
    }
}
void *allocate(size_t count, size_t size) {
    void *pointer = calloc(count ? count : 1, size);
    Allocation *item = malloc(sizeof(*item));
    if (!pointer || !item)
        exit(EXIT_FAILURE);
    if (!allocations)
        atexit(release);
    item->pointer = pointer;
    item->next = allocations;
    allocations = item;
    return pointer;
}
static char *formatted(const char *pattern, va_list args) {
    va_list copy;
    va_copy(copy, args);
    int length = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    char *out = allocate((size_t)length + 1, 1);
    vsnprintf(out, (size_t)length + 1, pattern, args);
    return out;
}
char *format(const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    char *out = formatted(pattern, args);
    va_end(args);
    return out;
}
char *joined(const char *first, const char *second) { return format("%s%s", first, second); }
void line(Lines *lines, const char *pattern, ...) {
    if (lines->count == lines->capacity) {
        int next = lines->capacity ? 2 * lines->capacity : 16;
        char **data = allocate((size_t)next, sizeof(char *));
        if (lines->count)
            memcpy(data, lines->data, (size_t)lines->count * sizeof(char *));
        lines->data = data;
        lines->capacity = next;
    }
    va_list args;
    va_start(args, pattern);
    lines->data[lines->count++] = formatted(pattern, args);
    va_end(args);
}
int civil_day(int year, int month, int day) {
    year -= month <= 2;
    int era = (year >= 0 ? year : year - 399) / 400, yoe = year - era * 400,
        doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1,
        doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    return era * 146097 + doe;
}
static void civil(int days, int out[3]) {
    int era = (days >= 0 ? days : days - 146096) / 146097, doe = days - era * 146097,
        yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365, year = yoe + era * 400,
        doy = doe - (365 * yoe + yoe / 4 - yoe / 100), mp = (5 * doy + 2) / 153,
        day = doy - (153 * mp + 2) / 5 + 1, month = mp + (mp < 10 ? 3 : -9);
    year += month <= 2;
    out[0] = year;
    out[1] = month;
    out[2] = day;
}
I parse_minutes(const char *value) {
    int year, month, day, hour, minute;
    sscanf(value, "%4d-%2d-%2d %2d:%2d", &year, &month, &day, &hour, &minute);
    return (I)civil_day(year, month, day) * 1440 + hour * 60 + minute;
}
int hour(const char *value, int epoch_day) {
    return (int)((parse_minutes(value) - (I)epoch_day * 1440) / 60);
}
char *date(int day, int epoch_day) {
    int parts[3];
    civil(day + epoch_day, parts);
    return format("%04d-%02d-%02d", parts[0], parts[1], parts[2]);
}
char *datetime(int minutes, int epoch_day) {
    int day = minutes / 1440, remaining = minutes % 1440;
    return format("%s %02d:%02d", date(day, epoch_day), remaining / 60, remaining % 60);
}
Input *read_inputs(void) {
    Input *out = allocate(1, sizeof(Input));
    Params *p = &out->params;
    FILE *settings = fopen("input/params.txt", "rb");
    char text[512];
    while (fgets(text, sizeof(text), settings)) {
        text[strcspn(text, "\n")] = 0;
        char key[32];
        sscanf(text, "%31s", key);
        const char *value = text + strlen(key) + 1;
        if (strcmp(key, "epoch") == 0)
            p->epoch_day = (int)(parse_minutes(value) / 1440);
        else if (strcmp(key, "station") == 0) {
            Station *station = &out->stations[out->station_count++];
            sscanf(value, "%3s", station->code);
            strcpy(station->name, value + 4);
            station->first = 10001;
        } else if (strcmp(key, "reference") == 0)
            sscanf(value, "%3s", p->reference);
        else if (strcmp(key, "flat_run") == 0)
            sscanf(value, "%d", &p->flat_run);
        else if (strcmp(key, "spike") == 0)
            sscanf(value, "%d %d %lf %lf", &p->spike_window, &p->spike_count, &p->spike_factor,
                   &p->spike_minimum);
        else if (strcmp(key, "rayleigh") == 0)
            sscanf(value, "%lf", &p->rayleigh);
        else if (strcmp(key, "snr_min") == 0)
            sscanf(value, "%lf", &p->snr);
        else if (strcmp(key, "top_residuals") == 0)
            sscanf(value, "%d", &p->top);
        else if (strcmp(key, "surge") == 0)
            sscanf(value, "%lf %d", &p->surge, &p->surge_hours);
        else if (strcmp(key, "predict") == 0) {
            p->start = hour(value, p->epoch_day);
            sscanf(value + 17, "%d", &p->length);
        } else if (strcmp(key, "grid_minutes") == 0)
            sscanf(value, "%d", &p->grid);
        else if (strcmp(key, "min_range") == 0)
            sscanf(value, "%lf", &p->min_range);
        else if (strcmp(key, "correlation_lag") == 0)
            sscanf(value, "%d", &p->lag);
        else if (strcmp(key, "plot") == 0)
            sscanf(value, "%3s %d %d %d %d", p->plot, &p->plot_hours, &p->plot_top, &p->plot_bottom,
                   &p->plot_step);
    }
    fclose(settings);
    FILE *constituents = fopen("input/constituents.txt", "rb");
    fscanf(constituents, "%d", &out->constituent_count);
    for (int i = 0; i < out->constituent_count; ++i)
        fscanf(constituents, "%4s %lf", out->constituents[i].name, &out->constituents[i].speed);
    fclose(constituents);
    FILE *observations = fopen("input/observations.csv", "rb");
    fgets(text, sizeof(text), observations);
    while (fgets(text, sizeof(text), observations)) {
        text[strcspn(text, "\n")] = 0;
        char *comma = strchr(text, ','), *last = strrchr(text, ',');
        *comma = 0;
        *last = 0;
        int index = 0;
        while (strcmp(out->stations[index].code, text) != 0)
            ++index;
        Station *station = &out->stations[index];
        int t = hour(comma + 1, p->epoch_day);
        Observation *observation = &station->observations[t];
        observation->present = true;
        ++station->rows;
        if (strcmp(last + 1, "NA") != 0) {
            const char *value = last + 1;
            bool negative = value[0] == '-';
            if (negative)
                ++value;
            const char *dot = strchr(value, '.');
            I milli = 1000 * strtoll(value, NULL, 10) + strtoll(dot + 1, NULL, 10);
            observation->numeric = true;
            observation->milli = negative ? -milli : milli;
            if (t < station->first)
                station->first = t;
            if (t > station->last)
                station->last = t;
        }
    }
    fclose(observations);
    return out;
}
