#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_FIXED 3652059
#define TEXT_SIZE 64

typedef enum {
    GREGORIAN, JULIAN, ISO, ISLAMIC, HEBREW, PERSIAN, COPTIC, ETHIOPIC, FRENCH, MAYAN, JD, FIXED, CALENDAR_COUNT
} Calendar;
typedef enum { ACCEPTED, FORMAT, YEAR, MONTH, WEEK, DAY, FIELD, RANGE } Reason;
typedef enum {
    CONVERT, ALL, VALID, WEEKDAY, INFO, LEAP, MONTHS, MONTHCAL, NTH, NEWYEAR,
    DIFF, COUNT, ADD, SPAN, EASTER, COMPUTUS, PASSOVER, HOLIDAYS, MOLAD, ROUND, COMMAND_COUNT
} Command;
typedef struct { long long year; int month, day; } Date;
typedef struct { int days[13], count; } Months;
typedef struct { long long day, parts, start; char rules[32]; } Molad;
typedef struct { long long epact; char letters[3]; long long moon, sunday; } Easter;
typedef struct { const char *name; Calendar calendar; const char *month; int day; } Holiday;
typedef struct { long long fixed; int order; const char *name; Calendar calendar; } Entry;
typedef struct { long long year, fixed; } NewYear;

static const char *const calendar_names[] = {
    "GREGORIAN", "JULIAN", "ISO", "ISLAMIC", "HEBREW", "PERSIAN",
    "COPTIC", "ETHIOPIC", "FRENCH", "MAYAN", "JD", "FIXED",
};
static const char *const reason_names[] = {"ACCEPTED", "FORMAT", "YEAR", "MONTH", "WEEK", "DAY", "FIELD", "RANGE"};
static const char *const command_names[] = {
    "CONVERT", "ALL", "VALID", "WEEKDAY", "INFO", "LEAP", "MONTHS", "MONTHCAL", "NTH", "NEWYEAR",
    "DIFF", "COUNT", "ADD", "SPAN", "EASTER", "COMPUTUS", "PASSOVER", "HOLIDAYS", "MOLAD", "ROUND",
};
static const int arity[] = {4, 2, 2, 2, 2, 2, 2, 3, 5, 2, 4, 4, 4, 3, 2, 2, 1, 1, 1, 6};
static const char *const weekday_names[] = {"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"};
static const char *const tzolkin_names[] = {
    "Imix", "Ik", "Akbal", "Kan", "Chicchan", "Cimi", "Manik", "Lamat", "Muluc", "Oc",
    "Chuen", "Eb", "Ben", "Ix", "Men", "Cib", "Caban", "Etznab", "Cauac", "Ahau",
};
static const char *const haab_names[] = {
    "Pop", "Uo", "Zip", "Zotz", "Tzec", "Xul", "Yaxkin", "Mol", "Chen", "Yax",
    "Zac", "Ceh", "Mac", "Kankin", "Muan", "Pax", "Kayab", "Cumku", "Uayeb",
};
static const char *const decade_names[] = {
    "Primidi", "Duodi", "Tridi", "Quartidi", "Quintidi", "Sextidi", "Septidi", "Octidi", "Nonidi", "Decadi",
};
static const char *const festival_names[] = {"Vertu", "Genie", "Travail", "Opinion", "Recompenses", "Revolution"};
static const char *const month_names[CALENDAR_COUNT][13] = {
    [GREGORIAN] = {"January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"},
    [JULIAN] = {"January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"},
    [ISLAMIC] = {"Muharram", "Safar", "RabiI", "RabiII", "JumadaI", "JumadaII", "Rajab", "Shaban", "Ramadan", "Shawwal", "DhuAlQidah", "DhuAlHijjah"},
    [HEBREW] = {"Tishri", "Heshvan", "Kislev", "Tevet", "Shevat", "Adar", "Nisan", "Iyyar", "Sivan", "Tammuz", "Av", "Elul"},
    [PERSIAN] = {"Farvardin", "Ordibehesht", "Khordad", "Tir", "Mordad", "Shahrivar", "Mehr", "Aban", "Azar", "Dey", "Bahman", "Esfand"},
    [COPTIC] = {"Thout", "Paopi", "Hathor", "Koiak", "Tobi", "Meshir", "Paremhat", "Parmouti", "Pashons", "Paoni", "Epip", "Mesori", "Nasie"},
    [ETHIOPIC] = {"Meskerem", "Tekemt", "Hedar", "Tahsas", "Ter", "Yekatit", "Megabit", "Miazia", "Genbot", "Sene", "Hamle", "Nehase", "Pagume"},
    [FRENCH] = {"Vendemiaire", "Brumaire", "Frimaire", "Nivose", "Pluviose", "Ventose", "Germinal", "Floreal", "Prairial", "Messidor", "Thermidor", "Fructidor", "Sansculottides"},
};
static const char *const hebrew_leap_names[] = {
    "Tishri", "Heshvan", "Kislev", "Tevet", "Shevat", "AdarI", "AdarII", "Nisan", "Iyyar", "Sivan", "Tammuz", "Av", "Elul",
};
static const Holiday holiday_table[] = {
    {"Christmas", GREGORIAN, "December", 25},
    {"OrthodoxChristmas", JULIAN, "December", 25},
    {"RoshHashanah", HEBREW, "Tishri", 1},
    {"YomKippur", HEBREW, "Tishri", 10},
    {"Sukkot", HEBREW, "Tishri", 15},
    {"Hanukkah", HEBREW, "Kislev", 25},
    {"Purim", HEBREW, "Adar", 14},
    {"Passover", HEBREW, "Nisan", 15},
    {"Shavuot", HEBREW, "Sivan", 6},
    {"IslamicNewYear", ISLAMIC, "Muharram", 1},
    {"Ashura", ISLAMIC, "Muharram", 10},
    {"Mawlid", ISLAMIC, "RabiI", 12},
    {"RamadanStart", ISLAMIC, "Ramadan", 1},
    {"EidAlFitr", ISLAMIC, "Shawwal", 1},
    {"EidAlAdha", ISLAMIC, "DhuAlHijjah", 10},
    {"Nowruz", PERSIAN, "Farvardin", 1},
    {"SizdahBedar", PERSIAN, "Farvardin", 13},
    {"Yalda", PERSIAN, "Azar", 30},
    {"Nayrouz", COPTIC, "Thout", 1},
    {"CopticChristmas", COPTIC, "Koiak", 29},
    {"Enkutatash", ETHIOPIC, "Meskerem", 1},
    {"Meskel", ETHIOPIC, "Meskerem", 17},
    {"Timkat", ETHIOPIC, "Ter", 11},
    {"RepublicDay", FRENCH, "Vendemiaire", 1},
    {"RevolutionDay", FRENCH, "Sansculottides", 6},
};

static long long floor_div(long long a, long long b) {
    long long quotient = a / b;
    return a % b < 0 ? quotient - 1 : quotient;
}

static long long mod(long long a, long long n) {
    long long remainder = a % n;
    return remainder < 0 ? remainder + n : remainder;
}

static long long smaller(long long a, long long b) { return a < b ? a : b; }

static long long larger(long long a, long long b) { return a > b ? a : b; }

static int lookup(const char *const *names, int count, const char *text) {
    for (int i = 0; i < count; ++i) {
        if (strcmp(names[i], text) == 0) return i;
    }
    return -1;
}

static int calendar_id(const char *text) { return lookup(calendar_names, CALENDAR_COUNT, text); }

static int weekday_id(const char *text) { return lookup(weekday_names, 7, text); }

static bool digits(const char *text, size_t low, size_t high) {
    size_t length = strlen(text);
    return length >= low && length <= high && strspn(text, "0123456789") == length;
}

static bool in_range(long long fixed) { return fixed >= 1 && fixed <= MAX_FIXED; }

static bool is_ymd(Calendar calendar) {
    return calendar != ISO && calendar != MAYAN && calendar != JD && calendar != FIXED;
}

static bool has_years(Calendar calendar) { return is_ymd(calendar) || calendar == ISO; }

static long long start(Calendar calendar, long long year);

static bool leap(Calendar calendar, long long year) {
    switch (calendar) {
    case GREGORIAN:
        return mod(year, 4) == 0 && (mod(year, 100) != 0 || mod(year, 400) == 0);
    case JULIAN:
        return mod(year, 4) == 0;
    case ISLAMIC: {
        static const int leap_years[] = {2, 5, 7, 10, 13, 16, 18, 21, 24, 26, 29};
        for (int i = 0; i < 11; ++i) {
            if (mod(year, 30) == leap_years[i]) return true;
        }
        return false;
    }
    case HEBREW:
        return mod(7 * year + 1, 19) < 7;
    case PERSIAN: {
        long long b = mod(year - 474, 2820) + 474;
        return mod((b + 38) * 682, 2816) < 682;
    }
    case COPTIC:
    case ETHIOPIC:
        return mod(year, 4) == 3;
    case FRENCH: {
        long long century = mod(year, 400);
        return mod(year, 4) == 0 && century != 100 && century != 200 && century != 300 && mod(year, 4000) != 0;
    }
    default:
        return (start(ISO, year + 1) - start(ISO, year)) / 7 == 53;
    }
}

static long long months_before(long long year) { return floor_div(235 * year - 234, 19); }

static void add_rule(Molad *molad, const char *rule) {
    if (molad->rules[0] != '\0') strcat(molad->rules, "+");
    strcat(molad->rules, rule);
}

static Molad molad(long long year) {
    long long quantity = 5604 + 765433 * months_before(year);
    Molad result = {floor_div(quantity, 25920), mod(quantity, 25920), 0, ""};
    long long weekday = mod(result.day - 1373427, 7);
    long long postponed = result.day;
    if (result.parts >= 19440) {
        postponed += 1;
        add_rule(&result, "ZAKEN");
    } else if (!leap(HEBREW, year) && weekday == 2 && result.parts >= 9924) {
        postponed += 2;
        add_rule(&result, "GATARAD");
    } else if (leap(HEBREW, year - 1) && weekday == 1 && result.parts >= 16789) {
        postponed += 1;
        add_rule(&result, "BETUTAKPAT");
    }
    long long final_weekday = mod(postponed - 1373427, 7);
    if (final_weekday == 0 || final_weekday == 3 || final_weekday == 5) {
        postponed += 1;
        add_rule(&result, "ADU");
    }
    result.start = postponed - 1373427;
    return result;
}

static long long start(Calendar calendar, long long year) {
    long long previous = year - 1;
    switch (calendar) {
    case GREGORIAN:
        return 365 * previous + floor_div(previous, 4) - floor_div(previous, 100) + floor_div(previous, 400) + 1;
    case JULIAN:
        return 365 * previous + floor_div(previous, 4) - 1;
    case ISLAMIC:
        return 227015 + 354 * previous + floor_div(3 + 11 * year, 30);
    case HEBREW:
        return molad(year).start;
    case PERSIAN: {
        long long a = year - 474;
        long long b = mod(a, 2820) + 474;
        return 226896 + 1029983 * floor_div(a, 2820) + 365 * (b - 1) + floor_div(682 * b - 110, 2816);
    }
    case COPTIC:
        return 103605 + 365 * previous + floor_div(year, 4);
    case ETHIOPIC:
        return 2796 + 365 * previous + floor_div(year, 4);
    case FRENCH:
        return 654415 + 365 * previous + floor_div(previous, 4) - floor_div(previous, 100)
               + floor_div(previous, 400) - floor_div(previous, 4000);
    default: {
        long long january_four = start(GREGORIAN, year) + 3;
        return january_four - mod(january_four - 1, 7);
    }
    }
}

static const char *year_type(long long year) {
    long long length = start(HEBREW, year + 1) - start(HEBREW, year);
    if (length == 353 || length == 383) return "DEFICIENT";
    if (length == 354 || length == 384) return "REGULAR";
    return "COMPLETE";
}

static const char *const *names(Calendar calendar, long long year) {
    return calendar == HEBREW && leap(calendar, year) ? hebrew_leap_names : month_names[calendar];
}

static int month_number(Calendar calendar, long long year, const char *name) {
    const char *const *list = names(calendar, year);
    for (int i = 0; i < 13 && list[i] != NULL; ++i) {
        if (strcmp(list[i], name) == 0) return i + 1;
    }
    return 0;
}

static Months lengths(Calendar calendar, long long year) {
    int extra = leap(calendar, year);
    switch (calendar) {
    case GREGORIAN:
    case JULIAN:
        return (Months){{31, 28 + extra, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}, 12};
    case ISLAMIC:
        return (Months){{30, 29, 30, 29, 30, 29, 30, 29, 30, 29, 30, 29 + extra}, 12};
    case PERSIAN:
        return (Months){{31, 31, 31, 31, 31, 31, 30, 30, 30, 30, 30, 29 + extra}, 12};
    case COPTIC:
    case ETHIOPIC:
    case FRENCH:
        return (Months){{30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 5 + extra}, 13};
    default: {
        const char *kind = year_type(year);
        int heshvan = strcmp(kind, "COMPLETE") == 0 ? 30 : 29;
        int kislev = strcmp(kind, "DEFICIENT") == 0 ? 29 : 30;
        if (extra) return (Months){{30, heshvan, kislev, 29, 30, 30, 29, 30, 29, 30, 29, 30, 29}, 13};
        return (Months){{30, heshvan, kislev, 29, 30, 29, 30, 29, 30, 29, 30, 29}, 12};
    }
    }
}

static long long fixed_date(Calendar calendar, long long year, int month, int day) {
    if (calendar == ISO) return start(calendar, year) + 7 * (month - 1) + day - 1;
    Months months = lengths(calendar, year);
    long long fixed = start(calendar, year) + day - 1;
    for (int i = 0; i < month - 1; ++i) fixed += months.days[i];
    return fixed;
}

static long long year_of(Calendar calendar, long long fixed) {
    if (fixed < start(calendar, 1)) return 0;
    long long low = 1, high = 100000;
    while (low + 1 < high) {
        long long middle = (low + high) / 2;
        if (start(calendar, middle) <= fixed) low = middle;
        else high = middle;
    }
    return low;
}

static Date parts_of(Calendar calendar, long long fixed) {
    Date date = {year_of(calendar, fixed), 0, 0};
    if (date.year == 0) return date;
    long long offset = fixed - start(calendar, date.year);
    if (calendar == ISO) {
        date.month = (int)(offset / 7) + 1;
        date.day = (int)(offset % 7) + 1;
        return date;
    }
    Months months = lengths(calendar, date.year);
    date.month = 1;
    while (offset >= months.days[date.month - 1]) {
        offset -= months.days[date.month - 1];
        ++date.month;
    }
    date.day = (int)offset + 1;
    return date;
}

static char *format_date(Calendar calendar, long long fixed, char *text) {
    if (!in_range(fixed)) {
        snprintf(text, TEXT_SIZE, "OUT OF RANGE");
    } else if (has_years(calendar)) {
        Date date = parts_of(calendar, fixed);
        if (date.year == 0) snprintf(text, TEXT_SIZE, "OUT OF RANGE");
        else if (calendar == ISO) snprintf(text, TEXT_SIZE, "%04lld-W%02d-%d", date.year, date.month, date.day);
        else snprintf(text, TEXT_SIZE, "%04lld-%02d-%02d", date.year, date.month, date.day);
    } else if (calendar == JD) {
        snprintf(text, TEXT_SIZE, "%lld", fixed + 1721425);
    } else if (calendar == FIXED) {
        snprintf(text, TEXT_SIZE, "%lld", fixed);
    } else {
        long long count = fixed + 1137142;
        long long haab = (count + 348) % 365;
        snprintf(text, TEXT_SIZE, "%lld.%lld.%lld.%lld.%lld %lld %s %lld %s",
                 count / 144000, count / 7200 % 20, count / 360 % 20, count / 20 % 18, count % 20,
                 (count + 3) % 13 + 1, tzolkin_names[(count + 19) % 20], haab % 20, haab_names[haab / 20]);
    }
    return text;
}

static Reason parse_date(Calendar calendar, const char *text, long long *fixed) {
    int length = 0;
    if (is_ymd(calendar)) {
        char year_text[6], month_text[3], day_text[3];
        int matched = sscanf(text, "%5[0-9]-%2[0-9]-%2[0-9]%n", year_text, month_text, day_text, &length);
        if (matched != 3 || text[length] != '\0') return FORMAT;
        long long year = atoll(year_text);
        int month = atoi(month_text), day = atoi(day_text);
        if (year == 0) return YEAR;
        Months months = lengths(calendar, year);
        if (month < 1 || month > months.count) return MONTH;
        if (day < 1 || day > months.days[month - 1]) return DAY;
        *fixed = fixed_date(calendar, year, month, day);
    } else if (calendar == ISO) {
        char year_text[6], week_text[3], day_text[2];
        int matched = sscanf(text, "%5[0-9]-W%2[0-9]-%1[0-9]%n", year_text, week_text, day_text, &length);
        if (matched != 3 || text[length] != '\0') return FORMAT;
        long long year = atoll(year_text);
        int week = atoi(week_text), day = atoi(day_text);
        if (year == 0) return YEAR;
        long long weeks = (start(calendar, year + 1) - start(calendar, year)) / 7;
        if (week < 1 || week > weeks) return WEEK;
        if (day < 1 || day > 7) return DAY;
        *fixed = fixed_date(calendar, year, week, day);
    } else if (calendar == MAYAN) {
        char fields[5][3];
        int matched = sscanf(text, "%2[0-9].%2[0-9].%2[0-9].%2[0-9].%2[0-9]%n",
                             fields[0], fields[1], fields[2], fields[3], fields[4], &length);
        if (matched != 5 || text[length] != '\0') return FORMAT;
        long long b = atoll(fields[0]), k = atoll(fields[1]), t = atoll(fields[2]);
        long long u = atoll(fields[3]), n = atoll(fields[4]);
        if (k > 19 || t > 19 || u > 17 || n > 19) return FIELD;
        *fixed = (((b * 20 + k) * 20 + t) * 18 + u) * 20 + n - 1137142;
    } else {
        if (!digits(text[0] == '-' ? text + 1 : text, 1, 8)) return FORMAT;
        *fixed = atoll(text) - (calendar == JD ? 1721425 : 0);
    }
    return in_range(*fixed) ? ACCEPTED : RANGE;
}

static long long months_per_year(Calendar calendar) {
    return calendar == COPTIC || calendar == ETHIOPIC || calendar == FRENCH ? 13 : 12;
}

static long long month_index(Calendar calendar, long long year) {
    if (calendar == HEBREW) return months_before(year);
    return months_per_year(calendar) * (year - 1);
}

static bool shift(Calendar calendar, long long fixed, long long years, long long months, long long *result) {
    Date date = parts_of(calendar, fixed);
    long long target_year = date.year + years;
    if (calendar == ISO) {
        if (target_year < 1 || target_year > 99999) return false;
        long long weeks = (start(calendar, target_year + 1) - start(calendar, target_year)) / 7;
        *result = fixed_date(calendar, target_year, (int)smaller(date.month, weeks), date.day);
        return true;
    }
    int month = date.month;
    if (calendar == HEBREW) {
        const char *name = names(calendar, date.year)[month - 1];
        month = month_number(calendar, target_year, name);
        if (month == 0) month = month_number(calendar, target_year, strcmp(name, "Adar") == 0 ? "AdarII" : "Adar");
    }
    long long absolute = month_index(calendar, target_year) + month - 1 + months;
    long long final_year;
    if (calendar == HEBREW) {
        final_year = floor_div(19 * absolute + 234, 235);
        while (month_index(calendar, final_year) > absolute) --final_year;
        while (month_index(calendar, final_year + 1) <= absolute) ++final_year;
    } else {
        final_year = floor_div(absolute, months_per_year(calendar)) + 1;
    }
    if (final_year < 1 || final_year > 99999) return false;
    int final_month = (int)(absolute - month_index(calendar, final_year)) + 1;
    int final_day = (int)smaller(date.day, lengths(calendar, final_year).days[final_month - 1]);
    *result = fixed_date(calendar, final_year, final_month, final_day);
    return true;
}

static bool month_bounds(Calendar calendar, long long year, int month, long long *first, long long *last) {
    Months months = lengths(calendar, year);
    if (month < 1 || month > months.count) return false;
    *first = fixed_date(calendar, year, month, 1);
    *last = *first + months.days[month - 1] - 1;
    return true;
}

static int new_years(Calendar calendar, long long first, long long last, NewYear *found) {
    long long year = larger(1, year_of(calendar, first));
    while (start(calendar, year) < first) ++year;
    int count = 0;
    for (; start(calendar, year) <= last; ++year) found[count++] = (NewYear){year, start(calendar, year)};
    return count;
}

static Easter easter(long long year, Calendar calendar) {
    long long golden = year % 19;
    Easter result = {0, "", 0, 0};
    if (calendar == GREGORIAN) {
        long long century = year / 100 + 1;
        result.epact = mod(14 + 11 * golden - 3 * century / 4 + (5 + 8 * century) / 25, 30);
        if (result.epact == 0 || (result.epact == 1 && golden > 10)) ++result.epact;
    } else {
        result.epact = (14 + 11 * golden) % 30;
    }
    result.moon = fixed_date(calendar, year, 4, 19) - result.epact;
    result.sunday = result.moon + 7 - mod(result.moon, 7);
    long long index = mod(-start(calendar, year), 7);
    result.letters[0] = "ABCDEFG"[index];
    if (leap(calendar, year)) result.letters[1] = "ABCDEFG"[mod(index - 1, 7)];
    return result;
}

static int compare_entries(const void *left, const void *right) {
    const Entry *a = left, *b = right;
    if (a->fixed != b->fixed) return a->fixed < b->fixed ? -1 : 1;
    return a->order - b->order;
}

static void print_holidays(long long year) {
    static const struct { const char *name; int offset; } movable[] = {
        {"AshWednesday", -46}, {"GoodFriday", -2}, {"Easter", 0}, {"Ascension", 39}, {"Pentecost", 49},
    };
    long long first = start(GREGORIAN, year), last = start(GREGORIAN, year + 1) - 1;
    long long gregorian_easter = easter(year, GREGORIAN).sunday;
    Entry entries[64];
    int count = 0;
    for (int order = 0; order < 5; ++order) {
        entries[count++] = (Entry){gregorian_easter + movable[order].offset, order, movable[order].name, GREGORIAN};
    }
    entries[count++] = (Entry){easter(year, JULIAN).sunday, 5, "OrthodoxEaster", JULIAN};
    int holiday_count = (int)(sizeof holiday_table / sizeof *holiday_table);
    for (int i = 0; i < holiday_count; ++i) {
        const Holiday *holiday = &holiday_table[i];
        Calendar calendar = holiday->calendar;
        for (long long candidate = larger(1, year_of(calendar, first)); start(calendar, candidate) <= last; ++candidate) {
            const char *month_name = holiday->month;
            if (calendar == HEBREW && strcmp(month_name, "Adar") == 0 && leap(calendar, candidate)) month_name = "AdarII";
            int month = month_number(calendar, candidate, month_name);
            if (holiday->day > lengths(calendar, candidate).days[month - 1]) continue;
            long long fixed = fixed_date(calendar, candidate, month, holiday->day);
            if (fixed >= first && fixed <= last) entries[count++] = (Entry){fixed, i + 6, holiday->name, calendar};
        }
    }
    qsort(entries, (size_t)count, sizeof *entries, compare_entries);
    for (int i = 0; i < count; ++i) {
        char gregorian[TEXT_SIZE], native[TEXT_SIZE];
        printf("%s %s %s %s %s\n", format_date(GREGORIAN, entries[i].fixed, gregorian), weekday_names[entries[i].fixed % 7],
               entries[i].name, calendar_names[entries[i].calendar], format_date(entries[i].calendar, entries[i].fixed, native));
    }
}

static bool valid_year(const char *text) { return digits(text, 1, 5) && atol(text) >= 1; }

static bool valid_arguments(Command command, char **args) {
    if (command == EASTER || command == COMPUTUS) {
        int kind = calendar_id(args[1]);
        return valid_year(args[0]) && (kind == GREGORIAN || kind == JULIAN);
    }
    if (command == PASSOVER || command == HOLIDAYS || command == MOLAD) return valid_year(args[0]);
    int calendar = calendar_id(args[0]);
    if (calendar < 0) return false;
    if ((command == INFO || command == MONTHS || command == MONTHCAL || command == NTH || command == SPAN) && !is_ymd(calendar)) return false;
    if ((command == LEAP || command == NEWYEAR) && !has_years(calendar)) return false;
    switch (command) {
    case CONVERT:
        return strcmp(args[2], "TO") == 0 && calendar_id(args[3]) >= 0;
    case DIFF:
        return calendar_id(args[2]) >= 0;
    case LEAP:
    case MONTHS:
    case NEWYEAR:
        return valid_year(args[1]);
    case MONTHCAL:
        return valid_year(args[1]) && digits(args[2], 1, 2);
    case NTH: {
        static const char *const ordinals[] = {"1", "2", "3", "4", "5", "LAST"};
        return valid_year(args[1]) && digits(args[2], 1, 2) && lookup(ordinals, 6, args[3]) >= 0 && weekday_id(args[4]) >= 0;
    }
    case COUNT:
        return weekday_id(args[3]) >= 0;
    case ADD: {
        static const char *const units[] = {"DAYS", "WEEKS", "MONTHS", "YEARS"};
        if (!digits(args[2][0] == '-' ? args[2] + 1 : args[2], 1, 7) || lookup(units, 4, args[3]) < 0) return false;
        if (strcmp(args[3], "MONTHS") == 0) return is_ymd(calendar);
        if (strcmp(args[3], "YEARS") == 0) return has_years(calendar);
        return true;
    }
    case ROUND:
        if (!digits(args[2], 1, 2) || atoi(args[2]) < 1 || atoi(args[2]) > 13 || lookup(tzolkin_names, 20, args[3]) < 0) return false;
        if (!digits(args[4], 1, 2) || lookup(haab_names, 19, args[5]) < 0) return false;
        return atoi(args[4]) <= (strcmp(args[5], "Uayeb") == 0 ? 4 : 19);
    default:
        return true;
    }
}

static void print_month_calendar(Calendar calendar, long long year, int month) {
    long long first, last;
    if (!month_bounds(calendar, year, month, &first, &last)) {
        puts("INVALID DATE");
        return;
    }
    if (!in_range(first) || !in_range(last)) {
        puts("OUT OF RANGE");
        return;
    }
    char from[TEXT_SIZE], to[TEXT_SIZE];
    printf("%s %lld (%s to %s)\n", names(calendar, year)[month - 1], year,
           format_date(GREGORIAN, first, from), format_date(GREGORIAN, last, to));
    puts("Mo Tu We Th Fr Sa Su");
    for (long long cursor = first - (first - 1) % 7; cursor <= last; cursor += 7) {
        char row[32];
        int length = 0;
        for (long long fixed = cursor; fixed < cursor + 7; ++fixed) {
            if (fixed > cursor) row[length++] = ' ';
            if (fixed >= first && fixed <= last) length += sprintf(row + length, "%2lld", fixed - first + 1);
            else length += sprintf(row + length, "  ");
        }
        while (length > 0 && row[length - 1] == ' ') --length;
        row[length] = '\0';
        puts(row);
    }
}

static char *span_text(Calendar calendar, long long first, long long last, char *text) {
    bool negative = first > last;
    if (negative) {
        long long swap = first;
        first = last;
        last = swap;
    }
    long long start_year = parts_of(calendar, first).year;
    long long end_year = parts_of(calendar, last).year;
    long long shifted;
    long long low = 0, high = end_year - start_year + 2;
    while (low + 1 < high) {
        long long middle = (low + high) / 2;
        if (shift(calendar, first, middle, 0, &shifted) && shifted <= last) low = middle;
        else high = middle;
    }
    long long years = low;
    low = 0;
    high = 32;
    while (low + 1 < high) {
        long long middle = (low + high) / 2;
        if (shift(calendar, first, years, middle, &shifted) && shifted <= last) low = middle;
        else high = middle;
    }
    long long months = low;
    shift(calendar, first, years, months, &shifted);
    snprintf(text, TEXT_SIZE, "%s%lldy %lldm %lldd", negative ? "-" : "", years, months, last - shifted);
    return text;
}

static char *round_date(Calendar calendar, long long fixed, int number, const char *tz_name, int day, const char *month, char *text) {
    int target_tz = lookup(tzolkin_names, 20, tz_name);
    int target_haab = lookup(haab_names, 19, month) * 20 + day;
    long long candidate = fixed;
    for (;;) {
        long long count = candidate + 1137142;
        if ((count + 3) % 13 + 1 == number && (count + 19) % 20 == target_tz) break;
        ++candidate;
    }
    for (; candidate <= fixed + 18979; candidate += 260) {
        if ((candidate + 1137142 + 348) % 365 == target_haab) return format_date(calendar, candidate, text);
    }
    snprintf(text, TEXT_SIZE, "NONE");
    return text;
}

static bool date_argument(Calendar calendar, const char *text, long long *fixed) {
    Reason reason = parse_date(calendar, text, fixed);
    if (reason != ACCEPTED) puts(reason == RANGE ? "OUT OF RANGE" : "INVALID DATE");
    return reason == ACCEPTED;
}

static void execute(Command command, char **args) {
    char text[TEXT_SIZE], other[TEXT_SIZE];
    if (!valid_arguments(command, args)) {
        puts("INVALID COMMAND");
        return;
    }
    if (command == EASTER || command == COMPUTUS) {
        long long year = atoll(args[0]);
        if (year > 9999) {
            puts("OUT OF RANGE");
            return;
        }
        Calendar kind = calendar_id(args[1]);
        Easter result = easter(year, kind);
        if (command == EASTER) puts(format_date(GREGORIAN, result.sunday, text));
        else printf("golden=%lld epact=%lld letters=%s moon=%s easter=%s\n", year % 19 + 1, result.epact, result.letters,
                    format_date(kind, result.moon, text), format_date(kind, result.sunday, other));
        return;
    }
    if (command == PASSOVER || command == HOLIDAYS || command == MOLAD) {
        long long year = atoll(args[0]);
        if (command == MOLAD) {
            Molad result = molad(year);
            if (!in_range(result.start)) {
                puts("OUT OF RANGE");
                return;
            }
            printf("%s %lldh %lldp %s %s %s\n", weekday_names[mod(result.day - 1373427, 7)], result.parts / 1080,
                   result.parts % 1080, result.rules[0] != '\0' ? result.rules : "NONE", weekday_names[result.start % 7],
                   format_date(GREGORIAN, result.start, text));
            return;
        }
        if (year > 9999) {
            puts("OUT OF RANGE");
            return;
        }
        if (command == HOLIDAYS) {
            print_holidays(year);
            return;
        }
        long long hebrew_year = year + 3760;
        long long fixed = fixed_date(HEBREW, hebrew_year, month_number(HEBREW, hebrew_year, "Nisan"), 15);
        printf("%s %s\n", format_date(GREGORIAN, fixed, text), weekday_names[fixed % 7]);
        return;
    }
    Calendar calendar = calendar_id(args[0]);
    if (command == LEAP || command == MONTHS || command == MONTHCAL || command == NTH || command == NEWYEAR) {
        long long year = atoll(args[1]);
        if (command == LEAP) {
            printf("%s %lld", leap(calendar, year) ? "YES" : "NO", start(calendar, year + 1) - start(calendar, year));
            if (calendar == HEBREW) printf(" %s", year_type(year));
            putchar('\n');
        } else if (command == MONTHS) {
            Months months = lengths(calendar, year);
            const char *const *list = names(calendar, year);
            for (int i = 0; i < months.count; ++i) printf("%s%s=%d", i > 0 ? " " : "", list[i], months.days[i]);
            putchar('\n');
        } else if (command == NEWYEAR) {
            if (year > 9999) {
                puts("OUT OF RANGE");
                return;
            }
            NewYear found[4];
            int count = new_years(calendar, start(GREGORIAN, year), start(GREGORIAN, year + 1) - 1, found);
            if (count == 0) {
                puts("NONE");
                return;
            }
            for (int i = 0; i < count; ++i) printf("%s%lld:%s", i > 0 ? " " : "", found[i].year, format_date(GREGORIAN, found[i].fixed, text));
            putchar('\n');
        } else if (command == MONTHCAL) {
            print_month_calendar(calendar, year, atoi(args[2]));
        } else {
            long long first, last;
            if (!month_bounds(calendar, year, atoi(args[2]), &first, &last)) {
                puts("INVALID DATE");
                return;
            }
            int weekday = weekday_id(args[4]);
            long long fixed;
            if (strcmp(args[3], "LAST") == 0) fixed = last - mod(last - weekday, 7);
            else fixed = first + mod(weekday - first, 7) + 7 * (atoi(args[3]) - 1);
            puts(fixed > last ? "NONE" : format_date(calendar, fixed, text));
        }
        return;
    }
    if (command == VALID) {
        long long fixed;
        Reason reason = parse_date(calendar, args[1], &fixed);
        if (reason == ACCEPTED) printf("YES %s\n", format_date(calendar, fixed, text));
        else printf("NO %s\n", reason_names[reason]);
        return;
    }
    long long first, last;
    if (!date_argument(calendar, args[1], &first)) return;
    switch (command) {
    case DIFF:
        if (date_argument(calendar_id(args[2]), args[3], &last)) printf("%lld\n", last - first);
        break;
    case COUNT: {
        if (!date_argument(calendar, args[2], &last)) break;
        long long low = smaller(first, last), high = larger(first, last);
        long long occurrence = low + mod(weekday_id(args[3]) - low, 7);
        printf("%lld\n", occurrence > high ? 0 : (high - occurrence) / 7 + 1);
        break;
    }
    case SPAN:
        if (date_argument(calendar, args[2], &last)) puts(span_text(calendar, first, last, text));
        break;
    case CONVERT:
        puts(format_date(calendar_id(args[3]), first, text));
        break;
    case WEEKDAY:
        puts(weekday_names[first % 7]);
        break;
    case ALL:
        for (int target = 0; target < CALENDAR_COUNT; ++target) {
            format_date(target, first, text);
            if (is_ymd(target) && strcmp(text, "OUT OF RANGE") != 0) {
                Date date = parts_of(target, first);
                printf("%s %s %s\n", calendar_names[target], text, names(target, date.year)[date.month - 1]);
            } else {
                printf("%s %s\n", calendar_names[target], text);
            }
        }
        break;
    case INFO: {
        Date date = parts_of(calendar, first);
        const char *weekday = weekday_names[first % 7];
        if (calendar == FRENCH) weekday = date.month <= 12 ? decade_names[(date.day - 1) % 10] : festival_names[date.day - 1];
        long long ordinal = first - start(calendar, date.year) + 1;
        long long length = start(calendar, date.year + 1) - start(calendar, date.year);
        printf("%s %d %s %lld day=%lld/%lld\n", weekday, date.day, names(calendar, date.year)[date.month - 1], date.year, ordinal, length);
        break;
    }
    case ROUND:
        puts(round_date(calendar, first, atoi(args[2]), args[3], atoi(args[4]), args[5], text));
        break;
    default: {
        long long amount = atoll(args[2]), result = 0;
        bool shifted = true;
        if (strcmp(args[3], "DAYS") == 0) result = first + amount;
        else if (strcmp(args[3], "WEEKS") == 0) result = first + 7 * amount;
        else if (strcmp(args[3], "YEARS") == 0) shifted = shift(calendar, first, amount, 0, &result);
        else shifted = shift(calendar, first, 0, amount, &result);
        puts(shifted ? format_date(calendar, result, text) : "OUT OF RANGE");
    }
    }
}

int main(void) {
    char line[256];
    if (!fgets(line, sizeof line, stdin)) return 0;
    int count = atoi(line);
    for (int i = 0; i < count && fgets(line, sizeof line, stdin); ++i) {
        line[strcspn(line, "\n")] = '\0';
        char *words[128];
        int length = 0;
        for (char *word = strtok(line, " "); word != NULL; word = strtok(NULL, " ")) words[length++] = word;
        int command = length > 0 ? lookup(command_names, COMMAND_COUNT, words[0]) : -1;
        if (command < 0 || length - 1 != arity[command]) puts("INVALID COMMAND");
        else execute(command, words + 1);
    }
    return 0;
}
