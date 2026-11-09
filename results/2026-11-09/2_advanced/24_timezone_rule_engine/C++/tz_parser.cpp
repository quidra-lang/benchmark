#include "timezone.hpp"

std::string lineContent(const std::string& raw) {
    std::string content = raw.substr(0, raw.find('#'));
    std::size_t last = content.find_last_not_of(' ');
    return last == std::string::npos ? "" : content.substr(0, last + 1);
}
Lines splitFields(const std::string& content) {
    std::istringstream stream(content);
    Lines fields;
    std::string field;
    while (stream >> field) fields.push_back(field);
    return fields;
}
bool isNumber(const std::string& text, std::size_t low, std::size_t high) {
    return low <= text.size() && text.size() <= high && std::all_of(text.begin(), text.end(), [](char c) { return c >= '0' && c <= '9'; });
}
std::optional<Time> hmsValue(const std::string& text, std::size_t maxParts) {
    Lines parts;
    std::size_t start = 0;
    for (;;) {
        std::size_t separator = text.find(':', start);
        parts.push_back(text.substr(start, separator == std::string::npos ? separator : separator - start));
        if (separator == std::string::npos) break;
        start = separator + 1;
    }
    if (parts.size() > maxParts || !isNumber(parts[0], 1, 2)) return std::nullopt;
    Time value = std::stoll(parts[0]) * 3600;
    for (std::size_t index = 1; index < parts.size(); ++index) {
        if (!isNumber(parts[index], 2, 2) || std::stoi(parts[index]) > 59) return std::nullopt;
        value += std::stoi(parts[index]) * (index == 1 ? 60 : 1);
    }
    return value;
}
int parseYear(const std::string& text) {
    if (!isNumber(text, 4, 4)) throw FieldError("bad year");
    int year = std::stoi(text);
    if (year < 1800 || year > 2099) throw FieldError("bad year");
    return year;
}
int parseTo(const std::string& text, int from) {
    if (text == "only") return from;
    if (text == "max") return 2099;
    if (!isNumber(text, 4, 4)) throw FieldError("bad year");
    int year = std::stoi(text);
    if (year < from || year > 2099) throw FieldError("bad year");
    return year;
}
int parseMonth(const std::string& text) {
    std::array<std::string, 12>::const_iterator found = std::find(MonthNames.begin(), MonthNames.end(), text);
    if (found == MonthNames.end()) throw FieldError("bad month");
    return static_cast<int>(found - MonthNames.begin()) + 1;
}
static int parseWeekday(const std::string& text) {
    std::array<std::string, 7>::const_iterator found = std::find(WeekdayNames.begin(), WeekdayNames.end(), text);
    if (found == WeekdayNames.end()) throw FieldError("bad day spec");
    return static_cast<int>(found - WeekdayNames.begin());
}
static int parseDayOfMonth(const std::string& text, int month) {
    if (!isNumber(text, 1, 2) || text[0] == '0') throw FieldError("bad day spec");
    int day = std::stoi(text);
    if (day > CommonMonthDays[month - 1]) throw FieldError("bad day spec");
    return day;
}
DaySpec parseDaySpec(const std::string& text, int month) {
    if (text.compare(0, 4, "last") == 0) return {DaySpec::Kind::Last, parseWeekday(text.substr(4)), 0};
    for (const std::pair<std::string, DaySpec::Kind>& item : std::vector<std::pair<std::string, DaySpec::Kind>>{{">=", DaySpec::Kind::After}, {"<=", DaySpec::Kind::Before}}) {
        std::size_t position = text.find(item.first);
        if (position != std::string::npos) {
            int weekday = parseWeekday(text.substr(0, position));
            int day = parseDayOfMonth(text.substr(position + 2), month);
            return {item.second, weekday, day};
        }
    }
    return {DaySpec::Kind::Day, 0, parseDayOfMonth(text, month)};
}
std::pair<Time, char> parseTime(const std::string& text) {
    std::string clock = text;
    char type = 'w';
    if (!clock.empty() && std::string("wsu").find(clock.back()) != std::string::npos) { type = clock.back(); clock.pop_back(); }
    std::optional<Time> value = hmsValue(clock);
    if (!value || *value > DaySeconds) throw FieldError("bad time");
    return {*value, type};
}
Time parseSave(const std::string& text) {
    std::optional<Time> value = hmsValue(text, 2);
    if (!value || *value > 7200) throw FieldError("bad save");
    return *value;
}
std::string parseLetter(const std::string& text) {
    if (text == "-") return "";
    if (text.empty() || text.size() > 5 || !std::all_of(text.begin(), text.end(), [](char c) { return c >= 'A' && c <= 'Z'; })) throw FieldError("bad letter");
    return text;
}
Time parseStandardOffset(const std::string& text) {
    bool negative = !text.empty() && text.front() == '-';
    std::optional<Time> value = hmsValue(negative ? text.substr(1) : text);
    if (!value || *value >= 57600) throw FieldError("bad offset");
    return negative ? -*value : *value;
}
void checkFormat(const std::string& text, bool usesRules) {
    std::size_t placeholders = 0;
    std::size_t slashes = 0;
    for (std::size_t index = 0; index < text.size(); ++index) {
        char c = text[index];
        if (c == '%') {
            if (index + 1 == text.size() || text[index + 1] != 's') throw FieldError("bad format");
            ++placeholders;
        } else if (c == '/') ++slashes;
        else if (!((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '+' || c == '-')) throw FieldError("bad format");
    }
    if (placeholders > 1 || slashes > 1 || (placeholders && slashes) || (!usesRules && placeholders) || (slashes && (text.front() == '/' || text.back() == '/'))) throw FieldError("bad format");
}
Until parseUntil(const Lines& fields) {
    int year = parseYear(fields[0]);
    std::string monthText = fields.size() > 1 ? fields[1] : "Jan";
    int month = parseMonth(monthText);
    std::string dayText = fields.size() > 2 ? fields[2] : "1";
    DaySpec day = parseDaySpec(dayText, month);
    std::pair<Time, char> clock = fields.size() > 3 ? parseTime(fields[3]) : std::pair<Time, char>{0, 'w'};
    return {fields[0], monthText, dayText, clock.first, clock.second, day.value(year, month) * DaySeconds + clock.first};
}
