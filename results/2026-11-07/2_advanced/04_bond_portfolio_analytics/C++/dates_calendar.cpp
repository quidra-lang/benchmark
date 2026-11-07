#include "bond.hpp"
#include <algorithm>
#include <iomanip>
#include <sstream>

bool leap(int year) { return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0); }
int monthLength(int year, int month) { const std::array<int, 12> days{31,28,31,30,31,30,31,31,30,31,30,31}; return days[month - 1] + (month == 2 && leap(year)); }
int dayNumber(int year, int month, int day) {
    int total = day - 1; for (int y = 2000; y < year; ++y) total += 365 + leap(y); for (int m = 1; m < month; ++m) total += monthLength(year, m); return total;
}
std::array<int, 3> civilDate(int day) {
    int year = 2000, month = 1;
    while (day >= 365 + leap(year)) day -= 365 + leap(year++);
    while (day >= monthLength(year, month)) day -= monthLength(year, month++);
    return {year, month, day + 1};
}
bool validDate(const std::string& text) {
    if (text.size() != 10 || text[4] != '-' || text[7] != '-') return false;
    for (int i : {0,1,2,3,5,6,8,9}) if (text[i] < '0' || text[i] > '9') return false;
    int year = std::stoi(text.substr(0, 4)), month = std::stoi(text.substr(5, 2)), day = std::stoi(text.substr(8, 2));
    return year >= 2001 && year <= 2099 && month >= 1 && month <= 12 && day >= 1 && day <= monthLength(year, month);
}
int parseDate(const std::string& text) { return dayNumber(std::stoi(text.substr(0, 4)), std::stoi(text.substr(5, 2)), std::stoi(text.substr(8, 2))); }
std::string formatDate(int day) {
    auto [year, month, date] = civilDate(day); std::ostringstream output; output << std::setfill('0') << std::setw(4) << year << '-' << std::setw(2) << month << '-' << std::setw(2) << date; return output.str();
}
bool Calendar::business(int day) const { return (day + 5) % 7 < 5 && !holidays.count(day); }
int Calendar::move(int day, int count) const {
    int step = count < 0 ? -1 : 1; if (count < 0) count = -count;
    while (count > 0) { day += step; if (business(day)) --count; } return day;
}
int Calendar::adjust(int day, const std::string& convention) const {
    if (convention == "UNADJUSTED") return day;
    int following = day; while (!business(following)) ++following;
    if (convention == "FOLLOWING" || (convention == "MODIFIED_FOLLOWING" && civilDate(following)[1] == civilDate(day)[1])) return following;
    while (!business(day)) --day; return day;
}
