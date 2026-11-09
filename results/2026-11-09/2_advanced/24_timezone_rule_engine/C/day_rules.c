#include "timezone.h"

const char *month_names[12] = {"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"};
const char *weekday_names[7] = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"};
Integer floor_divide(Integer value, Integer divisor) {
    Integer quotient = value / divisor;
    return value % divisor < 0 ? quotient - 1 : quotient;
}
Integer modulo(Integer value, Integer divisor) { return value - divisor * floor_divide(value, divisor); }
bool leap_year(int year) { return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0; }
int days_in_month(int year, int month) {
    const int lengths[] = {31,28,31,30,31,30,31,31,30,31,30,31};
    return month == 2 && leap_year(year) ? 29 : lengths[month - 1];
}
static Integer days_before_year(int year) {
    Integer previous = year - 1;
    return previous * 365 + floor_divide(previous, 4) - floor_divide(previous, 100) + floor_divide(previous, 400);
}
Integer day_number(int year, int month, int day) {
    Integer result = days_before_year(year) - days_before_year(1970) + day - 1;
    for (int earlier = 1; earlier < month; ++earlier) result += days_in_month(year, earlier);
    return result;
}
int weekday_of(Integer number) { return (int)modulo(number + 4, 7); }
Integer day_spec_value(DaySpec spec, int year, int month) {
    if (spec.kind == LAST) {
        Integer last = day_number(year, month, days_in_month(year, month));
        return last - modulo(weekday_of(last) - spec.weekday, 7);
    }
    Integer base = day_number(year, month, spec.day);
    if (spec.kind == AFTER) return base + modulo(spec.weekday - weekday_of(base), 7);
    if (spec.kind == BEFORE) return base - modulo(weekday_of(base) - spec.weekday, 7);
    return base;
}
Integer time_value(DateTime date) { return day_number(date.year, date.month, date.day) * 86400 + date.hour * 3600 + date.minute * 60 + date.second; }
DateTime split_time(Integer time) {
    Integer number = floor_divide(time, 86400), seconds = modulo(time, 86400);
    int year = 1970 + (int)floor_divide(number, 366), month = 1;
    while (day_number(year, 1, 1) > number) --year;
    while (day_number(year + 1, 1, 1) <= number) ++year;
    int day = (int)(number - day_number(year, 1, 1) + 1);
    while (day > days_in_month(year, month)) { day -= days_in_month(year, month); ++month; }
    return (DateTime){year, month, day, (int)(seconds / 3600), (int)(seconds / 60 % 60), (int)(seconds % 60)};
}
