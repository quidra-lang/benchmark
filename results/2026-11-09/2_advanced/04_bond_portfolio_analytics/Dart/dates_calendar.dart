const businessDayRules = {'FOLLOWING', 'MODIFIED_FOLLOWING', 'PRECEDING', 'UNADJUSTED'};
bool isLeap(int year) => year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
int monthLength(int year, int month) => month == 2 && isLeap(year) ? 29 : [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1];
bool validDate(String text) {
  final year = int.parse(text.substring(0, 4)), month = int.parse(text.substring(5, 7)), day = int.parse(text.substring(8));
  return year >= 2001 && year <= 2099 && month >= 1 && month <= 12 && day >= 1 && day <= monthLength(year, month);
}
int dayNumber(int year, int month, int day) {
  var number = day - 1;
  for (var earlier = 2000; earlier < year; earlier++) number += isLeap(earlier) ? 366 : 365;
  for (var earlier = 1; earlier < month; earlier++) number += monthLength(year, earlier);
  return number;
}
int parseDate(String text) => dayNumber(int.parse(text.substring(0, 4)), int.parse(text.substring(5, 7)), int.parse(text.substring(8)));
(int, int, int) civilDate(int number) {
  var year = 2000;
  while (number >= (isLeap(year) ? 366 : 365)) { number -= isLeap(year) ? 366 : 365; year++; }
  var month = 1;
  while (number >= monthLength(year, month)) { number -= monthLength(year, month); month++; }
  return (year, month, number + 1);
}
String formatDate(int number) { final (year, month, day) = civilDate(number); return '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}'; }
class Calendar {
  final Set<int> holidays;
  Calendar(Iterable<int> days) : holidays = days.toSet();
  bool business(int day) => (day + 5) % 7 < 5 && !holidays.contains(day);
  int following(int day) { while (!business(day)) day++; return day; }
  int preceding(int day) { while (!business(day)) day--; return day; }
  int adjust(int day, String rule) {
    if (rule == 'FOLLOWING') return following(day);
    if (rule == 'PRECEDING') return preceding(day);
    if (rule == 'MODIFIED_FOLLOWING') { final next = following(day); return civilDate(next).$2 == civilDate(day).$2 ? next : preceding(day); }
    return day;
  }
  int move(int day, int count) {
    final direction = count < 0 ? -1 : 1;
    if (count < 0) count = -count;
    while (count > 0) { day += direction; if (business(day)) count--; }
    return day;
  }
}
