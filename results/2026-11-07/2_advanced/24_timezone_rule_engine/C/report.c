#include "timezone.h"

char *local_text(Integer time) {
    DateTime date = split_time(time);
    return format("%04d-%02d-%02dT%02d:%02d:%02d", date.year, date.month, date.day, date.hour, date.minute, date.second);
}
char *ut_text(Integer time) { return format("%sZ", local_text(time)); }
char *offset_text(Integer value) {
    char sign = value < 0 ? '-' : '+';
    Integer magnitude = llabs(value);
    char *text = format("%c%02lld:%02lld", sign, magnitude / 3600, magnitude / 60 % 60);
    return magnitude % 60 ? format("%s:%02lld", text, magnitude % 60) : text;
}
char *duration_text(Integer value) {
    Integer magnitude = llabs(value);
    return format("%s%lld:%02lld:%02lld", value < 0 ? "-" : "", magnitude / 3600, magnitude / 60 % 60, magnitude % 60);
}
char *clock_text(Integer value) {
    char *text = format("%lld:%02lld", value / 3600, value / 60 % 60);
    return value % 60 ? format("%s:%02lld", text, value % 60) : text;
}
char *state_text(const Period *period) { return format("%s %s %s", offset_text(period->offset), period->dst ? "DST" : "STD", period->abbreviation); }
char *change_text(const Timeline *timeline, int index) { return format("%s %s -> %s", ut_text(timeline->items[index].start), state_text(&timeline->items[index - 1]), state_text(&timeline->items[index])); }
void write_lines(const char *name, Lines lines) {
    if (mkdir("output", 0777) && errno != EEXIST) exit(EXIT_FAILURE);
    FILE *file = fopen(format("output/%s", name), "wb");
    if (!file) exit(EXIT_FAILURE);
    for (int i = 0; i < lines.count; ++i) if (fprintf(file, "%s\n", lines.items[i]) < 0) exit(EXIT_FAILURE);
    if (fclose(file)) exit(EXIT_FAILURE);
}
