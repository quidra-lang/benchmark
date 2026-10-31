const secondsPerDay = 86400;
const negInfinity = -(1 << 60);
const posInfinity = 1 << 60;
const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const weekdayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const commonMonthDays = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
int floorDiv(int a, int b) {
  final q = a ~/ b;
  return a < 0 && a.remainder(b) != 0 ? q - 1 : q;
}
int modulo(int a, int b) => a - b * floorDiv(a, b);
bool leap(int year) => year % 4 == 0 && year % 100 != 0 || year % 400 == 0;
int daysInMonth(int year, int month) => month == 2 && leap(year) ? 29 : commonMonthDays[month - 1];
int daysBeforeYear(int year) {
  final previous = year - 1;
  return previous * 365 + floorDiv(previous, 4) - floorDiv(previous, 100) + floorDiv(previous, 400);
}
int dayNumber(int year, int month, int day) {
  var days = daysBeforeYear(year) - daysBeforeYear(1970) + day - 1;
  for (var earlier = 1; earlier < month; earlier++) {
    days += daysInMonth(year, earlier);
  }
  return days;
}
int weekday(int number) => modulo(number + 4, 7);
(int, int, int) dateOfDay(int number) {
  var year = 1970 + floorDiv(number, 366);
  while (dayNumber(year, 1, 1) > number) { year--; }
  while (dayNumber(year + 1, 1, 1) <= number) { year++; }
  var month = 1;
  var day = number - dayNumber(year, 1, 1) + 1;
  while (day > daysInMonth(year, month)) {
    day -= daysInMonth(year, month);
    month++;
  }
  return (year, month, day);
}
int timeValue(int year, int month, int day, int hour, int minute, int second) =>
    dayNumber(year, month, day) * secondsPerDay + hour * 3600 + minute * 60 + second;
(int, int, int, int, int, int) splitTime(int value) {
  final (year, month, day) = dateOfDay(floorDiv(value, secondsPerDay));
  final rest = modulo(value, secondsPerDay);
  return (year, month, day, rest ~/ 3600, rest ~/ 60 % 60, rest % 60);
}
class DaySpec {
  final String kind;
  final int weekdayNumber;
  final int day;
  DaySpec(this.kind, [this.weekdayNumber = 0, this.day = 0]);
  int value(int year, int month) {
    if (kind == 'last') {
      final last = dayNumber(year, month, daysInMonth(year, month));
      return last - modulo(weekday(last) - weekdayNumber, 7);
    }
    final base = dayNumber(year, month, day);
    if (kind == 'after') return base + modulo(weekdayNumber - weekday(base), 7);
    if (kind == 'before') return base - modulo(weekday(base) - weekdayNumber, 7);
    return base;
  }
}
