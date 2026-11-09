#pragma once
#include <algorithm>
#include <array>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <map>
#include <optional>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

using Time = std::int64_t;
using Lines = std::vector<std::string>;
using Interval = std::pair<Time, Time>;
constexpr Time DaySeconds = 86400;
constexpr Time NegativeInfinity = -(Time{1} << 62);
constexpr Time PositiveInfinity = Time{1} << 62;
extern const std::array<std::string, 12> MonthNames;
extern const std::array<std::string, 7> WeekdayNames;
extern const std::array<int, 12> CommonMonthDays;

Time floorDivide(Time value, Time divisor);
Time modulo(Time value, Time divisor);
bool leapYear(int year);
int daysInMonth(int year, int month);
Time dayNumber(int year, int month, int day);
std::array<int, 3> dateOfDay(Time number);
Time timeValue(int year, int month, int day, int hour, int minute, int second);
std::array<int, 6> splitTime(Time value);

struct DaySpec {
    enum class Kind { Day, Last, After, Before };
    Kind kind = Kind::Day;
    int weekday = 0;
    int day = 1;
    Time value(int year, int month) const;
};
struct Until {
    std::string yearText;
    std::string monthText;
    std::string dayText;
    Time time = 0;
    char type = 'w';
    Time value = 0;
};
struct FieldError : std::runtime_error { using std::runtime_error::runtime_error; };
std::string lineContent(const std::string& raw);
Lines splitFields(const std::string& content);
bool isNumber(const std::string& text, std::size_t low, std::size_t high);
std::optional<Time> hmsValue(const std::string& text, std::size_t maxParts = 3);
int parseYear(const std::string& text);
int parseTo(const std::string& text, int from);
int parseMonth(const std::string& text);
DaySpec parseDaySpec(const std::string& text, int month);
std::pair<Time, char> parseTime(const std::string& text);
Time parseSave(const std::string& text);
std::string parseLetter(const std::string& text);
Time parseStandardOffset(const std::string& text);
void checkFormat(const std::string& text, bool usesRules);
Until parseUntil(const Lines& fields);

struct Rule {
    int number = 0;
    Lines fields;
    std::string name;
    int from = 0;
    int to = 0;
    int month = 0;
    DaySpec day;
    Time at = 0;
    char atType = 'w';
    Time save = 0;
    std::string letter;
};
struct RuleInstance { std::size_t rule; Time nominal; };
struct LineRun {
    std::vector<std::size_t> preStart;
    std::vector<std::pair<Time, std::size_t>> applied;
    Time end = PositiveInfinity;
};
std::vector<RuleInstance> instanceSequence(const std::vector<Rule>& rules, const std::vector<std::size_t>& members);
Time adjustment(char type, Time standardOffset, Time save);
LineRun runInstances(const std::vector<Rule>& rules, const std::vector<RuleInstance>& instances, Time standardOffset, Time start, const std::optional<Until>& until);
std::string abbreviation(const std::string& format, Time save, const std::string& letter);

struct Period {
    Time start;
    Time offset;
    bool dst;
    std::string abbreviation;
    bool sameState(const Period& other) const;
};
struct Timeline {
    std::vector<Period> periods;
    std::size_t indexAt(Time value) const;
    const Period& periodAt(Time value) const;
    Time endOf(std::size_t index) const;
    std::pair<std::size_t, std::size_t> nearby(Time first, Time last) const;
    std::vector<std::size_t> candidates(Time local) const;
    std::size_t skippingTransition(Time local) const;
};
std::string localText(Time value);
std::string utText(Time value);
std::string offsetText(Time value);
std::string durationText(Time value);
std::string clockText(Time value);
std::string stateText(const Period& period);
std::string changeText(Time value, const Period& before, const Period& after);
void writeLines(const std::string& path, const Lines& lines);
void writeBlocks(const std::string& path, const std::vector<Lines>& blocks);
