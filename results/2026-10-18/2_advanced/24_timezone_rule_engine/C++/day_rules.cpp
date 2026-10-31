#include "timezone.hpp"

const std::array<std::string, 12> MonthNames = {"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"};
const std::array<std::string, 7> WeekdayNames = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"};
const std::array<int, 12> CommonMonthDays = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};

Time floorDivide(Time value, Time divisor) {
    Time quotient = value / divisor;
    if (value % divisor < 0) --quotient;
    return quotient;
}
Time modulo(Time value, Time divisor) { return value - divisor * floorDivide(value, divisor); }
bool leapYear(int year) { return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0; }
int daysInMonth(int year, int month) { return CommonMonthDays[month - 1] + (month == 2 && leapYear(year) ? 1 : 0); }
static Time daysBeforeYear(int year) {
    Time previous = year - 1;
    return previous * 365 + floorDivide(previous, 4) - floorDivide(previous, 100) + floorDivide(previous, 400);
}
Time dayNumber(int year, int month, int day) {
    Time result = daysBeforeYear(year) - daysBeforeYear(1970) + day - 1;
    for (int earlier = 1; earlier < month; ++earlier) result += daysInMonth(year, earlier);
    return result;
}
std::array<int, 3> dateOfDay(Time number) {
    int year = 1970 + static_cast<int>(floorDivide(number, 366));
    while (dayNumber(year, 1, 1) > number) --year;
    while (dayNumber(year + 1, 1, 1) <= number) ++year;
    int month = 1;
    int day = static_cast<int>(number - dayNumber(year, 1, 1) + 1);
    while (day > daysInMonth(year, month)) { day -= daysInMonth(year, month); ++month; }
    return {year, month, day};
}
Time timeValue(int year, int month, int day, int hour, int minute, int second) {
    return dayNumber(year, month, day) * DaySeconds + hour * 3600 + minute * 60 + second;
}
std::array<int, 6> splitTime(Time value) {
    std::array<int, 3> date = dateOfDay(floorDivide(value, DaySeconds));
    Time seconds = modulo(value, DaySeconds);
    return {date[0], date[1], date[2], static_cast<int>(seconds / 3600), static_cast<int>(seconds / 60 % 60), static_cast<int>(seconds % 60)};
}
Time DaySpec::value(int year, int month) const {
    if (kind == Kind::Last) {
        Time last = dayNumber(year, month, daysInMonth(year, month));
        return last - modulo(modulo(last + 4, 7) - weekday, 7);
    }
    Time base = dayNumber(year, month, day);
    if (kind == Kind::After) return base + modulo(weekday - modulo(base + 4, 7), 7);
    if (kind == Kind::Before) return base - modulo(modulo(base + 4, 7) - weekday, 7);
    return base;
}
