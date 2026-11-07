#include <algorithm>
#include <array>
#include <iomanip>
#include <iostream>
#include <map>
#include <numeric>
#include <optional>
#include <regex>
#include <sstream>
#include <stdexcept>
#include <string>
#include <tuple>
#include <utility>
#include <vector>

using std::string;
using std::vector;

enum Calendar { GREGORIAN, JULIAN, ISO, ISLAMIC, HEBREW, PERSIAN, COPTIC, ETHIOPIC, FRENCH, MAYAN, JD, FIXED };
const vector<string> calendarNames = {
    "GREGORIAN", "JULIAN", "ISO", "ISLAMIC", "HEBREW", "PERSIAN",
    "COPTIC", "ETHIOPIC", "FRENCH", "MAYAN", "JD", "FIXED",
};
const vector<string> weekdays = {"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"};
const vector<string> tzolkin = {
    "Imix", "Ik", "Akbal", "Kan", "Chicchan", "Cimi", "Manik", "Lamat", "Muluc", "Oc",
    "Chuen", "Eb", "Ben", "Ix", "Men", "Cib", "Caban", "Etznab", "Cauac", "Ahau",
};
const vector<string> haab = {
    "Pop", "Uo", "Zip", "Zotz", "Tzec", "Xul", "Yaxkin", "Mol", "Chen", "Yax",
    "Zac", "Ceh", "Mac", "Kankin", "Muan", "Pax", "Kayab", "Cumku", "Uayeb",
};
const vector<string> decades = {"Primidi", "Duodi", "Tridi", "Quartidi", "Quintidi", "Sextidi", "Septidi", "Octidi", "Nonidi", "Decadi"};
const vector<string> festivals = {"Vertu", "Genie", "Travail", "Opinion", "Recompenses", "Revolution"};
const long long maxFixed = 3652059;
const std::map<Calendar, vector<string>> monthNames = {
    {GREGORIAN, {"January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"}},
    {JULIAN, {"January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"}},
    {ISLAMIC, {"Muharram", "Safar", "RabiI", "RabiII", "JumadaI", "JumadaII", "Rajab", "Shaban", "Ramadan", "Shawwal", "DhuAlQidah", "DhuAlHijjah"}},
    {HEBREW, {"Tishri", "Heshvan", "Kislev", "Tevet", "Shevat", "Adar", "Nisan", "Iyyar", "Sivan", "Tammuz", "Av", "Elul"}},
    {PERSIAN, {"Farvardin", "Ordibehesht", "Khordad", "Tir", "Mordad", "Shahrivar", "Mehr", "Aban", "Azar", "Dey", "Bahman", "Esfand"}},
    {COPTIC, {"Thout", "Paopi", "Hathor", "Koiak", "Tobi", "Meshir", "Paremhat", "Parmouti", "Pashons", "Paoni", "Epip", "Mesori", "Nasie"}},
    {ETHIOPIC, {"Meskerem", "Tekemt", "Hedar", "Tahsas", "Ter", "Yekatit", "Megabit", "Miazia", "Genbot", "Sene", "Hamle", "Nehase", "Pagume"}},
    {FRENCH, {"Vendemiaire", "Brumaire", "Frimaire", "Nivose", "Pluviose", "Ventose", "Germinal", "Floreal", "Prairial", "Messidor", "Thermidor", "Fructidor", "Sansculottides"}},
};
const vector<string> hebrewLeapNames = {
    "Tishri", "Heshvan", "Kislev", "Tevet", "Shevat", "AdarI", "AdarII", "Nisan", "Iyyar", "Sivan", "Tammuz", "Av", "Elul",
};
const std::regex yearPattern("[0-9]{1,5}");
const std::regex twoDigitPattern("[0-9]{1,2}");
const std::regex amountPattern("-?[0-9]{1,7}");
const std::regex ymdPattern("([0-9]{1,5})-([0-9]{1,2})-([0-9]{1,2})");
const std::regex isoPattern("([0-9]{1,5})-W([0-9]{1,2})-([0-9])");
const std::regex mayanPattern("([0-9]{1,2})\\.([0-9]{1,2})\\.([0-9]{1,2})\\.([0-9]{1,2})\\.([0-9]{1,2})");
const std::regex integerPattern("-?[0-9]{1,8}");

struct DateError : std::runtime_error {
    using std::runtime_error::runtime_error;
};
struct CommandError {};
struct Date { long long year; int month, day; };
struct Molad { long long day, parts, start; vector<string> rules; };
struct Easter { long long epact; string letters; long long moon, sunday; };
struct Holiday { string name; Calendar calendar; string month; int day; };
struct Entry { long long fixed; int order; string name; Calendar calendar; };

void require(bool condition) {
    if (!condition) throw CommandError();
}
long long floorDiv(long long a, long long b) {
    long long quotient = a / b;
    return a % b < 0 ? quotient - 1 : quotient;
}
long long mod(long long a, long long n) {
    long long remainder = a % n;
    return remainder < 0 ? remainder + n : remainder;
}
int indexOf(const vector<string> &items, const string &item) {
    vector<string>::const_iterator found = std::find(items.begin(), items.end(), item);
    return found == items.end() ? -1 : int(found - items.begin());
}
bool contains(const vector<string> &items, const string &item) { return indexOf(items, item) >= 0; }
vector<string> split(const string &s, char delimiter) {
    vector<string> result;
    std::size_t begin = 0;
    for (std::size_t i = 0; i <= s.size(); ++i) {
        if (i == s.size() || s[i] == delimiter) {
            result.push_back(s.substr(begin, i - begin));
            begin = i + 1;
        }
    }
    return result;
}
string join(const vector<string> &items, const string &separator) {
    string result;
    for (std::size_t i = 0; i < items.size(); ++i) {
        if (i) result += separator;
        result += items[i];
    }
    return result;
}
template <typename... Values> string text(const Values &...values) {
    std::ostringstream out;
    (out << ... << values);
    return out.str();
}
string padded(long long value, int width, char fill = '0') {
    std::ostringstream out;
    out << std::setw(width) << std::setfill(fill) << value;
    return out.str();
}
Calendar calendarOf(const string &name) { return Calendar(indexOf(calendarNames, name)); }
bool inRange(long long fixed) { return 1 <= fixed && fixed <= maxFixed; }
bool isYmd(Calendar calendar) { return calendar != ISO && calendar != MAYAN && calendar != JD && calendar != FIXED; }
bool hasYears(Calendar calendar) { return isYmd(calendar) || calendar == ISO; }

long long start(Calendar calendar, long long year);

bool leap(Calendar calendar, long long year) {
    switch (calendar) {
    case GREGORIAN:
        return mod(year, 4) == 0 && (mod(year, 100) != 0 || mod(year, 400) == 0);
    case JULIAN:
        return mod(year, 4) == 0;
    case ISLAMIC: {
        const std::array<long long, 11> leapYears = {2, 5, 7, 10, 13, 16, 18, 21, 24, 26, 29};
        return std::find(leapYears.begin(), leapYears.end(), mod(year, 30)) != leapYears.end();
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

long long monthsBefore(long long year) { return floorDiv(235 * year - 234, 19); }

Molad molad(long long year) {
    long long quantity = 5604 + 765433 * monthsBefore(year);
    Molad result{floorDiv(quantity, 25920), mod(quantity, 25920), 0, {}};
    long long weekday = mod(result.day - 1373427, 7);
    long long postponed = result.day;
    if (result.parts >= 19440) {
        postponed += 1;
        result.rules.push_back("ZAKEN");
    } else if (!leap(HEBREW, year) && weekday == 2 && result.parts >= 9924) {
        postponed += 2;
        result.rules.push_back("GATARAD");
    } else if (leap(HEBREW, year - 1) && weekday == 1 && result.parts >= 16789) {
        postponed += 1;
        result.rules.push_back("BETUTAKPAT");
    }
    long long finalWeekday = mod(postponed - 1373427, 7);
    if (finalWeekday == 0 || finalWeekday == 3 || finalWeekday == 5) {
        postponed += 1;
        result.rules.push_back("ADU");
    }
    result.start = postponed - 1373427;
    return result;
}

long long start(Calendar calendar, long long year) {
    long long previous = year - 1;
    switch (calendar) {
    case GREGORIAN:
        return 365 * previous + floorDiv(previous, 4) - floorDiv(previous, 100) + floorDiv(previous, 400) + 1;
    case JULIAN:
        return 365 * previous + floorDiv(previous, 4) - 1;
    case ISLAMIC:
        return 227015 + 354 * previous + floorDiv(3 + 11 * year, 30);
    case HEBREW:
        return molad(year).start;
    case PERSIAN: {
        long long a = year - 474;
        long long b = mod(a, 2820) + 474;
        return 226896 + 1029983 * floorDiv(a, 2820) + 365 * (b - 1) + floorDiv(682 * b - 110, 2816);
    }
    case COPTIC:
        return 103605 + 365 * previous + floorDiv(year, 4);
    case ETHIOPIC:
        return 2796 + 365 * previous + floorDiv(year, 4);
    case FRENCH:
        return 654415 + 365 * previous + floorDiv(previous, 4) - floorDiv(previous, 100) + floorDiv(previous, 400) - floorDiv(previous, 4000);
    default: {
        long long januaryFour = start(GREGORIAN, year) + 3;
        return januaryFour - mod(januaryFour - 1, 7);
    }
    }
}

string yearType(long long year) {
    long long length = start(HEBREW, year + 1) - start(HEBREW, year);
    if (length == 353 || length == 383) return "DEFICIENT";
    if (length == 354 || length == 384) return "REGULAR";
    return "COMPLETE";
}

const vector<string> &names(Calendar calendar, long long year) {
    if (calendar == HEBREW && leap(calendar, year)) return hebrewLeapNames;
    return monthNames.at(calendar);
}

vector<int> lengths(Calendar calendar, long long year) {
    int extra = leap(calendar, year) ? 1 : 0;
    switch (calendar) {
    case GREGORIAN:
    case JULIAN:
        return {31, 28 + extra, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    case ISLAMIC:
        return {30, 29, 30, 29, 30, 29, 30, 29, 30, 29, 30, 29 + extra};
    case PERSIAN:
        return {31, 31, 31, 31, 31, 31, 30, 30, 30, 30, 30, 29 + extra};
    case COPTIC:
    case ETHIOPIC:
    case FRENCH:
        return {30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 5 + extra};
    default: {
        string kind = yearType(year);
        int heshvan = kind == "COMPLETE" ? 30 : 29;
        int kislev = kind == "DEFICIENT" ? 29 : 30;
        if (extra) return {30, heshvan, kislev, 29, 30, 30, 29, 30, 29, 30, 29, 30, 29};
        return {30, heshvan, kislev, 29, 30, 29, 30, 29, 30, 29, 30, 29};
    }
    }
}

long long fixedDate(Calendar calendar, long long year, int month, int day) {
    if (calendar == ISO) return start(calendar, year) + 7 * (month - 1) + day - 1;
    vector<int> days = lengths(calendar, year);
    return start(calendar, year) + std::accumulate(days.begin(), days.begin() + (month - 1), 0LL) + day - 1;
}

long long yearOf(Calendar calendar, long long fixed) {
    if (fixed < start(calendar, 1)) return 0;
    long long low = 1, high = 100000;
    while (low + 1 < high) {
        long long middle = (low + high) / 2;
        if (start(calendar, middle) <= fixed) low = middle;
        else high = middle;
    }
    return low;
}

std::optional<Date> partsOf(Calendar calendar, long long fixed) {
    long long year = yearOf(calendar, fixed);
    if (year == 0) return std::nullopt;
    long long offset = fixed - start(calendar, year);
    if (calendar == ISO) return Date{year, int(offset / 7) + 1, int(offset % 7) + 1};
    vector<int> days = lengths(calendar, year);
    for (int month = 1; month <= int(days.size()); ++month) {
        if (offset < days[month - 1]) return Date{year, month, int(offset) + 1};
        offset -= days[month - 1];
    }
    throw std::logic_error("calendar year length");
}

string formatDate(Calendar calendar, long long fixed) {
    if (!inRange(fixed)) return "OUT OF RANGE";
    if (hasYears(calendar)) {
        std::optional<Date> date = partsOf(calendar, fixed);
        if (!date) return "OUT OF RANGE";
        if (calendar == ISO) return text(padded(date->year, 4), "-W", padded(date->month, 2), "-", date->day);
        return text(padded(date->year, 4), "-", padded(date->month, 2), "-", padded(date->day, 2));
    }
    if (calendar == JD) return std::to_string(fixed + 1721425);
    if (calendar == FIXED) return std::to_string(fixed);
    long long count = fixed + 1137142;
    long long haabDay = (count + 348) % 365;
    return text(count / 144000, ".", count / 7200 % 20, ".", count / 360 % 20, ".", count / 20 % 18, ".", count % 20, " ",
                (count + 3) % 13 + 1, " ", tzolkin[(count + 19) % 20], " ", haabDay % 20, " ", haab[haabDay / 20]);
}

long long parseDate(Calendar calendar, const string &value) {
    std::smatch match;
    long long fixed;
    if (isYmd(calendar)) {
        if (!std::regex_match(value, match, ymdPattern)) throw DateError("FORMAT");
        long long year = std::stoll(match.str(1));
        int month = std::stoi(match.str(2)), day = std::stoi(match.str(3));
        if (year == 0) throw DateError("YEAR");
        vector<int> days = lengths(calendar, year);
        if (month < 1 || month > int(days.size())) throw DateError("MONTH");
        if (day < 1 || day > days[month - 1]) throw DateError("DAY");
        fixed = fixedDate(calendar, year, month, day);
    } else if (calendar == ISO) {
        if (!std::regex_match(value, match, isoPattern)) throw DateError("FORMAT");
        long long year = std::stoll(match.str(1));
        int week = std::stoi(match.str(2)), day = std::stoi(match.str(3));
        if (year == 0) throw DateError("YEAR");
        long long weeks = (start(calendar, year + 1) - start(calendar, year)) / 7;
        if (week < 1 || week > weeks) throw DateError("WEEK");
        if (day < 1 || day > 7) throw DateError("DAY");
        fixed = fixedDate(calendar, year, week, day);
    } else if (calendar == MAYAN) {
        if (!std::regex_match(value, match, mayanPattern)) throw DateError("FORMAT");
        long long b = std::stoll(match.str(1)), k = std::stoll(match.str(2)), t = std::stoll(match.str(3));
        long long u = std::stoll(match.str(4)), n = std::stoll(match.str(5));
        if (k > 19 || t > 19 || u > 17 || n > 19) throw DateError("FIELD");
        fixed = (((b * 20 + k) * 20 + t) * 18 + u) * 20 + n - 1137142;
    } else {
        if (!std::regex_match(value, integerPattern)) throw DateError("FORMAT");
        fixed = std::stoll(value) - (calendar == JD ? 1721425 : 0);
    }
    if (!inRange(fixed)) throw DateError("RANGE");
    return fixed;
}

long long monthIndex(Calendar calendar, long long year) {
    if (calendar == HEBREW) return monthsBefore(year);
    long long count = calendar == COPTIC || calendar == ETHIOPIC || calendar == FRENCH ? 13 : 12;
    return count * (year - 1);
}

std::optional<long long> shift(Calendar calendar, long long fixed, long long years, long long months) {
    Date date = *partsOf(calendar, fixed);
    long long targetYear = date.year + years;
    if (calendar == ISO) {
        if (targetYear < 1 || targetYear > 99999) return std::nullopt;
        long long weeks = (start(calendar, targetYear + 1) - start(calendar, targetYear)) / 7;
        return fixedDate(calendar, targetYear, int(std::min<long long>(date.month, weeks)), date.day);
    }
    int month = date.month;
    if (calendar == HEBREW) {
        string oldName = names(calendar, date.year)[month - 1];
        const vector<string> &newNames = names(calendar, targetYear);
        if (!contains(newNames, oldName)) oldName = oldName == "Adar" ? "AdarII" : "Adar";
        month = indexOf(newNames, oldName) + 1;
    }
    long long absolute = monthIndex(calendar, targetYear) + month - 1 + months;
    long long finalYear;
    if (calendar == HEBREW) {
        finalYear = floorDiv(19 * absolute + 234, 235);
        while (monthIndex(calendar, finalYear) > absolute) --finalYear;
        while (monthIndex(calendar, finalYear + 1) <= absolute) ++finalYear;
    } else {
        long long count = names(calendar, targetYear).size();
        finalYear = floorDiv(absolute, count) + 1;
    }
    if (finalYear < 1 || finalYear > 99999) return std::nullopt;
    int finalMonth = int(absolute - monthIndex(calendar, finalYear)) + 1;
    int finalDay = std::min(date.day, lengths(calendar, finalYear)[finalMonth - 1]);
    return fixedDate(calendar, finalYear, finalMonth, finalDay);
}

std::pair<long long, long long> monthBounds(Calendar calendar, long long year, int month) {
    vector<int> days = lengths(calendar, year);
    if (month < 1 || month > int(days.size())) throw DateError("MONTH");
    long long first = fixedDate(calendar, year, month, 1);
    return {first, first + days[month - 1] - 1};
}

vector<std::pair<long long, long long>> newYears(Calendar calendar, long long first, long long last) {
    long long year = std::max(1LL, yearOf(calendar, first));
    while (start(calendar, year) < first) ++year;
    vector<std::pair<long long, long long>> result;
    for (; start(calendar, year) <= last; ++year) result.push_back({year, start(calendar, year)});
    return result;
}

Easter easter(long long year, Calendar calendar) {
    long long golden = year % 19;
    long long epact;
    if (calendar == GREGORIAN) {
        long long century = year / 100 + 1;
        epact = mod(14 + 11 * golden - 3 * century / 4 + (5 + 8 * century) / 25, 30);
        if (epact == 0 || (epact == 1 && golden > 10)) ++epact;
    } else {
        epact = (14 + 11 * golden) % 30;
    }
    long long moon = fixedDate(calendar, year, 4, 19) - epact;
    long long sunday = moon + 7 - mod(moon, 7);
    long long index = mod(-start(calendar, year), 7);
    const string alphabet = "ABCDEFG";
    string letters(1, alphabet[index]);
    if (leap(calendar, year)) letters += alphabet[mod(index - 1, 7)];
    return {epact, letters, moon, sunday};
}

const vector<Holiday> holidays = {
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

vector<string> holidayLines(long long year) {
    long long first = start(GREGORIAN, year);
    long long last = start(GREGORIAN, year + 1) - 1;
    long long gregorianEaster = easter(year, GREGORIAN).sunday;
    long long orthodoxEaster = easter(year, JULIAN).sunday;
    const vector<std::pair<string, int>> movable = {
        {"AshWednesday", -46}, {"GoodFriday", -2}, {"Easter", 0}, {"Ascension", 39}, {"Pentecost", 49},
    };
    vector<Entry> entries;
    for (int order = 0; order < int(movable.size()); ++order) {
        entries.push_back({gregorianEaster + movable[order].second, order, movable[order].first, GREGORIAN});
    }
    entries.push_back({orthodoxEaster, 5, "OrthodoxEaster", JULIAN});
    for (int i = 0; i < int(holidays.size()); ++i) {
        const Holiday &holiday = holidays[i];
        Calendar calendar = holiday.calendar;
        for (long long candidate = std::max(1LL, yearOf(calendar, first)); start(calendar, candidate) <= last; ++candidate) {
            string actualName = holiday.month;
            if (calendar == HEBREW && actualName == "Adar" && leap(calendar, candidate)) actualName = "AdarII";
            int month = indexOf(names(calendar, candidate), actualName) + 1;
            if (holiday.day > lengths(calendar, candidate)[month - 1]) continue;
            long long fixed = fixedDate(calendar, candidate, month, holiday.day);
            if (first <= fixed && fixed <= last) entries.push_back({fixed, i + 6, holiday.name, calendar});
        }
    }
    std::sort(entries.begin(), entries.end(), [](const Entry &a, const Entry &b) {
        return std::tie(a.fixed, a.order) < std::tie(b.fixed, b.order);
    });
    vector<string> result;
    for (const Entry &entry : entries) {
        result.push_back(text(formatDate(GREGORIAN, entry.fixed), " ", weekdays[entry.fixed % 7], " ", entry.name, " ",
                              calendarNames[entry.calendar], " ", formatDate(entry.calendar, entry.fixed)));
    }
    return result;
}

const std::map<string, int> arity = {
    {"CONVERT", 4}, {"ALL", 2}, {"VALID", 2}, {"WEEKDAY", 2}, {"INFO", 2},
    {"LEAP", 2}, {"MONTHS", 2}, {"MONTHCAL", 3}, {"NTH", 5}, {"NEWYEAR", 2},
    {"DIFF", 4}, {"COUNT", 4}, {"ADD", 4}, {"SPAN", 3}, {"EASTER", 2},
    {"COMPUTUS", 2}, {"PASSOVER", 1}, {"HOLIDAYS", 1}, {"MOLAD", 1}, {"ROUND", 6},
};

bool validYear(const string &value) { return std::regex_match(value, yearPattern) && std::stoi(value) >= 1; }

void validateArguments(const string &command, const vector<string> &args) {
    if (command == "EASTER" || command == "COMPUTUS") {
        require(validYear(args[0]) && (args[1] == "GREGORIAN" || args[1] == "JULIAN"));
        return;
    }
    if (command == "PASSOVER" || command == "HOLIDAYS" || command == "MOLAD") {
        require(validYear(args[0]));
        return;
    }
    require(contains(calendarNames, args[0]));
    Calendar calendar = calendarOf(args[0]);
    if (command == "INFO" || command == "MONTHS" || command == "MONTHCAL" || command == "NTH" || command == "SPAN") {
        require(isYmd(calendar));
    } else if (command == "LEAP" || command == "NEWYEAR") {
        require(hasYears(calendar));
    }
    if (command == "CONVERT") {
        require(args[2] == "TO" && contains(calendarNames, args[3]));
    } else if (command == "DIFF") {
        require(contains(calendarNames, args[2]));
    } else if (command == "LEAP" || command == "MONTHS" || command == "MONTHCAL" || command == "NTH" || command == "NEWYEAR") {
        require(validYear(args[1]));
        if (command == "MONTHCAL" || command == "NTH") require(std::regex_match(args[2], twoDigitPattern));
        if (command == "NTH") {
            require(contains({"1", "2", "3", "4", "5", "LAST"}, args[3]));
            require(contains(weekdays, args[4]));
        }
    } else if (command == "COUNT") {
        require(contains(weekdays, args[3]));
    } else if (command == "ADD") {
        require(std::regex_match(args[2], amountPattern));
        require(contains({"DAYS", "WEEKS", "MONTHS", "YEARS"}, args[3]));
        if (args[3] == "MONTHS") require(isYmd(calendar));
        if (args[3] == "YEARS") require(hasYears(calendar));
    } else if (command == "ROUND") {
        require(std::regex_match(args[2], twoDigitPattern));
        int number = std::stoi(args[2]);
        require(1 <= number && number <= 13 && contains(tzolkin, args[3]));
        require(std::regex_match(args[4], twoDigitPattern));
        require(contains(haab, args[5]));
        require(std::stoi(args[4]) <= (args[5] == "Uayeb" ? 4 : 19));
    }
}

vector<string> calendarLines(Calendar calendar, long long year, int month) {
    auto [first, last] = monthBounds(calendar, year, month);
    if (!inRange(first) || !inRange(last)) return {"OUT OF RANGE"};
    vector<string> result = {
        text(names(calendar, year)[month - 1], " ", year, " (", formatDate(GREGORIAN, first), " to ", formatDate(GREGORIAN, last), ")"),
        "Mo Tu We Th Fr Sa Su",
    };
    for (long long cursor = first - (first - 1) % 7; cursor <= last; cursor += 7) {
        vector<string> fields;
        for (long long fixed = cursor; fixed < cursor + 7; ++fixed) {
            fields.push_back(first <= fixed && fixed <= last ? padded(fixed - first + 1, 2, ' ') : "  ");
        }
        string row = join(fields, " ");
        row.erase(row.find_last_not_of(' ') + 1);
        result.push_back(row);
    }
    return result;
}

string spanText(Calendar calendar, long long first, long long last) {
    bool negative = first > last;
    if (negative) std::swap(first, last);
    long long startYear = partsOf(calendar, first)->year;
    long long endYear = partsOf(calendar, last)->year;
    long long low = 0, high = endYear - startYear + 2;
    while (low + 1 < high) {
        long long middle = (low + high) / 2;
        std::optional<long long> shifted = shift(calendar, first, middle, 0);
        if (shifted && *shifted <= last) low = middle;
        else high = middle;
    }
    long long years = low;
    low = 0;
    high = 32;
    while (low + 1 < high) {
        long long middle = (low + high) / 2;
        std::optional<long long> shifted = shift(calendar, first, years, middle);
        if (shifted && *shifted <= last) low = middle;
        else high = middle;
    }
    long long months = low;
    long long days = last - *shift(calendar, first, years, months);
    return text(negative ? "-" : "", years, "y ", months, "m ", days, "d");
}

string roundDate(Calendar calendar, long long fixed, int number, const string &tzName, int day, const string &month) {
    int targetTz = indexOf(tzolkin, tzName);
    int targetHaab = indexOf(haab, month) * 20 + day;
    long long candidate = fixed;
    while (true) {
        long long count = candidate + 1137142;
        if ((count + 3) % 13 + 1 == number && (count + 19) % 20 == targetTz) break;
        ++candidate;
    }
    for (; candidate <= fixed + 18979; candidate += 260) {
        if ((candidate + 1137142 + 348) % 365 == targetHaab) return formatDate(calendar, candidate);
    }
    return "NONE";
}

vector<string> execute(const string &command, const vector<string> &args) {
    validateArguments(command, args);
    if (command == "EASTER" || command == "COMPUTUS") {
        long long year = std::stoll(args[0]);
        if (year > 9999) return {"OUT OF RANGE"};
        Calendar kind = calendarOf(args[1]);
        Easter result = easter(year, kind);
        if (command == "EASTER") return {formatDate(GREGORIAN, result.sunday)};
        return {text("golden=", year % 19 + 1, " epact=", result.epact, " letters=", result.letters,
                     " moon=", formatDate(kind, result.moon), " easter=", formatDate(kind, result.sunday))};
    }
    if (command == "PASSOVER" || command == "HOLIDAYS" || command == "MOLAD") {
        long long year = std::stoll(args[0]);
        if (command == "MOLAD") {
            Molad result = molad(year);
            if (!inRange(result.start)) return {"OUT OF RANGE"};
            string applied = result.rules.empty() ? "NONE" : join(result.rules, "+");
            return {text(weekdays[mod(result.day - 1373427, 7)], " ", result.parts / 1080, "h ", result.parts % 1080, "p ",
                         applied, " ", weekdays[result.start % 7], " ", formatDate(GREGORIAN, result.start))};
        }
        if (year > 9999) return {"OUT OF RANGE"};
        if (command == "HOLIDAYS") return holidayLines(year);
        long long hebrewYear = year + 3760;
        int month = indexOf(names(HEBREW, hebrewYear), "Nisan") + 1;
        long long fixed = fixedDate(HEBREW, hebrewYear, month, 15);
        return {formatDate(GREGORIAN, fixed) + " " + weekdays[fixed % 7]};
    }
    Calendar calendar = calendarOf(args[0]);
    if (command == "LEAP" || command == "MONTHS" || command == "MONTHCAL" || command == "NTH" || command == "NEWYEAR") {
        long long year = std::stoll(args[1]);
        if (command == "LEAP") {
            string line = text(leap(calendar, year) ? "YES" : "NO", " ", start(calendar, year + 1) - start(calendar, year));
            if (calendar == HEBREW) line += " " + yearType(year);
            return {line};
        }
        if (command == "MONTHS") {
            const vector<string> &monthList = names(calendar, year);
            vector<int> days = lengths(calendar, year);
            vector<string> items;
            for (std::size_t i = 0; i < days.size(); ++i) items.push_back(text(monthList[i], "=", days[i]));
            return {join(items, " ")};
        }
        if (command == "NEWYEAR") {
            if (year > 9999) return {"OUT OF RANGE"};
            vector<string> items;
            for (const auto &[newYear, fixed] : newYears(calendar, start(GREGORIAN, year), start(GREGORIAN, year + 1) - 1)) {
                items.push_back(text(newYear, ":", formatDate(GREGORIAN, fixed)));
            }
            return {items.empty() ? "NONE" : join(items, " ")};
        }
        int month = std::stoi(args[2]);
        if (command == "MONTHCAL") return calendarLines(calendar, year, month);
        auto [first, last] = monthBounds(calendar, year, month);
        int weekday = indexOf(weekdays, args[4]);
        long long fixed;
        if (args[3] == "LAST") fixed = last - mod(last - weekday, 7);
        else fixed = first + mod(weekday - first, 7) + 7 * (std::stoi(args[3]) - 1);
        return {fixed > last ? "NONE" : formatDate(calendar, fixed)};
    }
    if (command == "VALID") {
        try {
            return {"YES " + formatDate(calendar, parseDate(calendar, args[1]))};
        } catch (const DateError &error) {
            return {string("NO ") + error.what()};
        }
    }
    long long first = parseDate(calendar, args[1]);
    if (command == "DIFF") return {std::to_string(parseDate(calendarOf(args[2]), args[3]) - first)};
    if (command == "COUNT" || command == "SPAN") {
        long long last = parseDate(calendar, args[2]);
        if (command == "SPAN") return {spanText(calendar, first, last)};
        long long low = std::min(first, last), high = std::max(first, last);
        long long occurrence = low + mod(indexOf(weekdays, args[3]) - low, 7);
        return {std::to_string(occurrence > high ? 0 : (high - occurrence) / 7 + 1)};
    }
    if (command == "CONVERT") return {formatDate(calendarOf(args[3]), first)};
    if (command == "WEEKDAY") return {weekdays[first % 7]};
    if (command == "ALL") {
        vector<string> result;
        for (std::size_t index = 0; index < calendarNames.size(); ++index) {
            Calendar target = Calendar(index);
            string line = formatDate(target, first);
            if (isYmd(target) && line != "OUT OF RANGE") {
                Date date = *partsOf(target, first);
                line += " " + names(target, date.year)[date.month - 1];
            }
            result.push_back(calendarNames[target] + " " + line);
        }
        return result;
    }
    if (command == "INFO") {
        Date date = *partsOf(calendar, first);
        string weekday = weekdays[first % 7];
        if (calendar == FRENCH) weekday = date.month <= 12 ? decades[(date.day - 1) % 10] : festivals[date.day - 1];
        long long ordinal = first - start(calendar, date.year) + 1;
        long long length = start(calendar, date.year + 1) - start(calendar, date.year);
        return {text(weekday, " ", date.day, " ", names(calendar, date.year)[date.month - 1], " ", date.year, " day=", ordinal, "/", length)};
    }
    if (command == "ROUND") return {roundDate(calendar, first, std::stoi(args[2]), args[3], std::stoi(args[4]), args[5])};
    long long amount = std::stoll(args[2]);
    const string &unit = args[3];
    std::optional<long long> result;
    if (unit == "DAYS") result = first + amount;
    else if (unit == "WEEKS") result = first + 7 * amount;
    else if (unit == "YEARS") result = shift(calendar, first, amount, 0);
    else result = shift(calendar, first, 0, amount);
    return {result ? formatDate(calendar, *result) : "OUT OF RANGE"};
}

int main() {
    std::ios::sync_with_stdio(false);
    string line;
    std::getline(std::cin, line);
    int count = std::stoi(line);
    for (int i = 0; i < count && std::getline(std::cin, line); ++i) {
        vector<string> words = split(line, ' ');
        const string &command = words[0];
        vector<string> args(words.begin() + 1, words.end());
        std::map<string, int>::const_iterator found = arity.find(command);
        if (found == arity.end() || int(args.size()) != found->second) {
            std::cout << "INVALID COMMAND\n";
            continue;
        }
        try {
            for (const string &output : execute(command, args)) std::cout << output << '\n';
        } catch (const CommandError &) {
            std::cout << "INVALID COMMAND\n";
        } catch (const DateError &error) {
            std::cout << (string(error.what()) == "RANGE" ? "OUT OF RANGE" : "INVALID DATE") << '\n';
        }
    }
}
