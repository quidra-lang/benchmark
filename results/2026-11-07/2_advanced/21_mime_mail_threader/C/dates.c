#include "mail.h"

static bool leap(int year) { return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0; }
static int month_days(int year, int month) {
    static const int lengths[] = {31,28,31,30,31,30,31,31,30,31,30,31};
    return month == 2 && leap(year) ? 29 : lengths[month - 1];
}
static int year_days(int year) { return leap(year) ? 366 : 365; }
static bool digits(const char *text, int first_length, int second_length) {
    int length = (int)strlen(text);
    if (length != first_length && length != second_length) return false;
    for (int i = 0; i < length; ++i) if (text[i] < '0' || text[i] > '9') return false;
    return true;
}
static Date failure(char *error) { return (Date){0, error, false}; }

Date parse_date(const char *value) {
    const char *weekdays[] = {"mon", "tue", "wed", "thu", "fri", "sat", "sun"};
    const char *months[] = {"jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"};
    const char *zones[] = {"ut", "gmt", "z", "est", "edt", "cst", "cdt", "mst", "mdt", "pst", "pdt"};
    const int offsets[] = {0,0,0,-300,-240,-360,-300,-420,-360,-480,-420};
    char *clean = remove_comments(value);
    if (!clean) return failure("bad Date syntax");
    Text spaced = {0};
    for (const char *character = clean; *character; ++character) {
        if (*character == ',') text_add(&spaced, " , ");
        else text_add(&spaced, "%c", *character);
    }
    Lines tokens = split_words(spaced.data ? spaced.data : "");
    int weekday = -1, start = 0;
    if (tokens.count >= 3 && !strcmp(tokens.items[1], ",")) {
        for (int i = 0; i < 7; ++i) if (equal_case(tokens.items[0], weekdays[i])) weekday = i;
        if (weekday >= 0) start = 2;
    }
    if (tokens.count - start != 5) return failure("bad Date syntax");
    char *day_text = tokens.items[start], *month_text = tokens.items[start + 1], *year_text = tokens.items[start + 2];
    char *time_text = tokens.items[start + 3], *zone_text = tokens.items[start + 4];
    int month = 0, zone_index = -1;
    for (int i = 0; i < 12; ++i) if (equal_case(month_text, months[i])) month = i + 1;
    for (int i = 0; i < 11; ++i) if (equal_case(zone_text, zones[i])) zone_index = i;
    bool numeric_zone = (zone_text[0] == '+' || zone_text[0] == '-') && digits(zone_text + 1, 4, 4);
    Lines time = split_text(time_text, ':');
    bool time_valid = time.count == 2 || time.count == 3;
    for (int i = 0; i < time.count; ++i) if (!digits(time.items[i], 2, 2)) time_valid = false;
    if (!digits(day_text, 1, 2) || !month || !digits(year_text, 2, 4) || !time_valid || (!numeric_zone && zone_index < 0)) return failure("bad Date syntax");
    int year = atoi(year_text), day = atoi(day_text), hour = atoi(time.items[0]), minute = atoi(time.items[1]);
    int second = time.count == 3 ? atoi(time.items[2]) : 0, offset;
    if (strlen(year_text) == 2) year += year < 50 ? 2000 : 1900;
    if (numeric_zone) {
        int hours = atoi(slice(zone_text, 1, 2)), minutes = atoi(zone_text + 3);
        if (hours > 23 || minutes > 59) return failure("Date out of range");
        offset = hours * 60 + minutes;
        if (zone_text[0] == '-') offset = -offset;
    } else offset = offsets[zone_index];
    if (year < 1970 || year > 2099 || day < 1 || day > month_days(year, month) || hour > 23 || minute > 59 || second > 59) return failure("Date out of range");
    Integer days = 0;
    for (int current = 1970; current < year; ++current) days += year_days(current);
    for (int current = 1; current < month; ++current) days += month_days(year, current);
    days += day - 1;
    Integer seconds = days * 86400 + hour * 3600 + minute * 60 + second - offset * 60;
    if (seconds < 0) return failure("Date out of range");
    if (weekday >= 0 && (days + 3) % 7 != weekday) return failure("Date weekday mismatch");
    return (Date){seconds, NULL, true};
}

char *format_utc(Integer seconds) {
    Integer days = seconds / 86400, rest = seconds % 86400;
    int year = 1970, month = 1;
    while (days >= year_days(year)) { days -= year_days(year); ++year; }
    while (days >= month_days(year, month)) { days -= month_days(year, month); ++month; }
    return format("%04d-%02d-%02lld %02lld:%02lld:%02lld", year, month, days + 1, rest / 3600, (rest % 3600) / 60, rest % 60);
}
