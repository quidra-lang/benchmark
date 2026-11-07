#include "timezone.h"

char *line_content(const char *raw) {
    const char *comment = strchr(raw, '#');
    size_t size = comment ? (size_t)(comment - raw) : strlen(raw);
    while (size && raw[size - 1] == ' ') --size;
    return slice(raw, 0, size);
}
bool digits(const char *text, int minimum, int maximum) {
    size_t length = strlen(text);
    if (length < (size_t)minimum || length > (size_t)maximum) return false;
    for (size_t i = 0; i < length; ++i) if (text[i] < '0' || text[i] > '9') return false;
    return true;
}
static bool hms_value(const char *text, int max_parts, Integer *result) {
    Lines fields = {0};
    size_t start = 0;
    for (size_t i = 0;; ++i) if (!text[i] || text[i] == ':') {
        add_line(&fields, "%s", slice(text, start, i - start));
        if (!text[i]) break;
        start = i + 1;
    }
    if (fields.count > max_parts || !digits(fields.items[0], 1, 2)) return false;
    Integer value = atoi(fields.items[0]) * 3600;
    for (int i = 1; i < fields.count; ++i) {
        if (!digits(fields.items[i], 2, 2) || atoi(fields.items[i]) > 59) return false;
        value += atoi(fields.items[i]) * (i == 1 ? 60 : 1);
    }
    *result = value;
    return true;
}
bool parse_year(const char *text, int *year) {
    if (!digits(text, 4, 4)) return false;
    *year = atoi(text);
    return *year >= 1800 && *year <= 2099;
}
bool parse_to(const char *text, int from, int *to) {
    if (!strcmp(text, "only")) { *to = from; return true; }
    if (!strcmp(text, "max")) { *to = 2099; return true; }
    return parse_year(text, to) && *to >= from;
}
bool parse_month(const char *text, int *month) {
    for (int i = 0; i < 12; ++i) if (!strcmp(text, month_names[i])) { *month = i + 1; return true; }
    return false;
}
static bool parse_weekday(const char *text, int *weekday) {
    for (int i = 0; i < 7; ++i) if (!strcmp(text, weekday_names[i])) { *weekday = i; return true; }
    return false;
}
static bool day_of_month(const char *text, int month, int *day) {
    if (!digits(text, 1, 2) || text[0] == '0') return false;
    *day = atoi(text);
    return *day <= days_in_month(2001, month);
}
bool parse_day_spec(const char *text, int month, DaySpec *spec) {
    *spec = (DaySpec){DAY,0,0};
    if (!strncmp(text, "last", 4)) { spec->kind = LAST; return parse_weekday(text + 4, &spec->weekday); }
    const char *operators[] = {">=", "<="};
    for (int i = 0; i < 2; ++i) {
        const char *operator = strstr(text, operators[i]);
        if (!operator) continue;
        spec->kind = i == 0 ? AFTER : BEFORE;
        return parse_weekday(slice(text, 0, (size_t)(operator - text)), &spec->weekday) && day_of_month(operator + 2, month, &spec->day);
    }
    return day_of_month(text, month, &spec->day);
}
bool parse_time(const char *text, Integer *value, char *type) {
    size_t size = strlen(text);
    *type = 'w';
    if (size && strchr("wsu", text[size - 1])) { *type = text[size - 1]; text = slice(text, 0, size - 1); }
    return hms_value(text, 3, value) && *value <= 86400;
}
bool parse_save(const char *text, Integer *value) { return hms_value(text, 2, value) && *value <= 7200; }
bool parse_letter(char *text, char **letter) {
    if (!strcmp(text, "-")) { *letter = ""; return true; }
    if (strlen(text) > 5) return false;
    for (char *c = text; *c; ++c) if (*c < 'A' || *c > 'Z') return false;
    *letter = text;
    return true;
}
bool parse_offset(const char *text, Integer *value) {
    bool negative = text[0] == '-';
    if (negative) ++text;
    if (!hms_value(text, 3, value) || *value >= 57600) return false;
    if (negative) *value = -*value;
    return true;
}
bool check_format(const char *text, bool rule_set) {
    int placeholders = 0, slashes = 0;
    size_t size = strlen(text);
    for (size_t i = 0; i < size; ++i) {
        char c = text[i];
        if (c == '%') {
            if (text[i + 1] != 's') return false;
            ++placeholders; ++i;
        } else if (c == '/') { if (!i || i + 1 == size) return false; ++slashes; }
        else if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '+' || c == '-')) return false;
    }
    return placeholders <= 1 && slashes <= 1 && !(placeholders && slashes) && (rule_set || !placeholders);
}
Until *parse_until(Lines fields, int start, char **error) {
    Until *until = allocate(sizeof(*until));
    until->year_text = fields.items[start];
    until->month_text = fields.count > start + 1 ? fields.items[start + 1] : "Jan";
    until->day_text = fields.count > start + 2 ? fields.items[start + 2] : "1";
    int year, month;
    DaySpec day;
    if (!parse_year(until->year_text, &year)) *error = "bad year";
    else if (!parse_month(until->month_text, &month)) *error = "bad month";
    else if (!parse_day_spec(until->day_text, month, &day)) *error = "bad day spec";
    else {
        until->type = 'w';
        if (fields.count > start + 3 && !parse_time(fields.items[start + 3], &until->time, &until->type)) *error = "bad time";
        if (!*error) until->value = day_spec_value(day, year, month) * 86400 + until->time;
    }
    return *error ? NULL : until;
}
