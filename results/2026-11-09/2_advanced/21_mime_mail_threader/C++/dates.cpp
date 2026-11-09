#include "mail.hpp"
#include <iomanip>

static const Lines weekdays{"mon", "tue", "wed", "thu", "fri", "sat", "sun"};
static const Lines months{"jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"};
static const std::map<std::string, int> zones{{"ut", 0}, {"gmt", 0}, {"z", 0}, {"est", -300}, {"edt", -240}, {"cst", -360}, {"cdt", -300}, {"mst", -420}, {"mdt", -360}, {"pst", -480}, {"pdt", -420}};
static bool leap(int year) { return year % 4 == 0 && year % 100 != 0 || year % 400 == 0; }
static int daysInMonth(int year, int month) { static const int days[]{31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}; return days[month - 1] + (month == 2 && leap(year)); }
static bool digits(const std::string& value, std::size_t first, std::size_t second = 0) { if (value.size() != first && value.size() != second) return false; if (value.empty()) return false; for (char character : value) if (character < '0' || character > '9') return false; return true; }
DateResult parseDate(const std::string& value) {
    const DateResult syntax{std::nullopt, "bad Date syntax"}, range{std::nullopt, "Date out of range"};
    std::optional<std::string> uncommented = removeComments(value);
    if (!uncommented) return syntax;
    std::string expanded; for (char character : *uncommented) { if (character == ',') expanded += " , "; else expanded += character; }
    Lines fields = words(expanded); int weekday = -1;
    if (fields.size() >= 3 && fields[1] == ",") {
        Lines::const_iterator found = std::find(weekdays.begin(), weekdays.end(), lower(fields[0]));
        if (found != weekdays.end()) { weekday = static_cast<int>(found - weekdays.begin()); fields.erase(fields.begin(), fields.begin() + 2); }
    }
    if (fields.size() != 5) return syntax;
    Lines::const_iterator monthPosition = std::find(months.begin(), months.end(), lower(fields[1]));
    Lines time = split(fields[3], ':');
    bool numeric = fields[4].size() == 5 && (fields[4][0] == '+' || fields[4][0] == '-') && digits(fields[4].substr(1), 4);
    std::map<std::string, int>::const_iterator named = zones.find(lower(fields[4]));
    if (!digits(fields[0], 1, 2) || monthPosition == months.end() || !digits(fields[2], 2, 4) || (time.size() != 2 && time.size() != 3) || (!numeric && named == zones.end())) return syntax;
    for (const std::string& piece : time) if (!digits(piece, 2)) return syntax;
    int day = std::stoi(fields[0]), month = static_cast<int>(monthPosition - months.begin()) + 1, year = std::stoi(fields[2]);
    if (fields[2].size() == 2) year += year < 50 ? 2000 : 1900;
    int hour = std::stoi(time[0]), minute = std::stoi(time[1]), second = time.size() == 3 ? std::stoi(time[2]) : 0, offset;
    if (numeric) { int zoneHour = std::stoi(fields[4].substr(1, 2)), zoneMinute = std::stoi(fields[4].substr(3, 2)); if (zoneHour > 23 || zoneMinute > 59) return range; offset = (zoneHour * 60 + zoneMinute) * (fields[4][0] == '-' ? -1 : 1); }
    else offset = named->second;
    if (year < 1970 || year > 2099 || day < 1 || day > daysInMonth(year, month) || hour > 23 || minute > 59 || second > 59) return range;
    Integer days = 0;
    for (int current = 1970; current < year; ++current) days += 365 + leap(current);
    for (int current = 1; current < month; ++current) days += daysInMonth(year, current);
    days += day - 1;
    Integer seconds = days * 86400 + hour * 3600 + minute * 60 + second - offset * 60;
    if (seconds < 0) return range;
    if (weekday >= 0 && (days + 3) % 7 != weekday) return {std::nullopt, "Date weekday mismatch"};
    return {seconds, ""};
}
std::string formatUtc(Integer seconds) {
    Integer days = seconds / 86400, rest = seconds % 86400; int year = 1970, month = 1;
    while (days >= 365 + leap(year)) { days -= 365 + leap(year); ++year; }
    while (days >= daysInMonth(year, month)) { days -= daysInMonth(year, month); ++month; }
    std::ostringstream stream; stream << std::setfill('0') << std::setw(4) << year << '-' << std::setw(2) << month << '-' << std::setw(2) << days + 1 << ' ' << std::setw(2) << rest / 3600 << ':' << std::setw(2) << rest % 3600 / 60 << ':' << std::setw(2) << rest % 60;
    return stream.str();
}
