import 'dates_calendar.dart';
List<int> couponSchedule(int issue, int maturity, int frequency, bool eom, bool long) {
  final (year, month, day) = civilDate(maturity);
  eom = eom && day == monthLength(year, month);
  final dates = <int>[];
  var boundary = maturity;
  while (boundary > issue) {
    dates.add(boundary);
    final index = year * 12 + month - 1 - (12 ~/ frequency) * dates.length, y = index ~/ 12, m = index % 12 + 1;
    final length = monthLength(y, m);
    boundary = dayNumber(y, m, eom || day > length ? length : day);
  }
  if (long && boundary != issue && dates.length >= 2) dates.removeLast();
  dates.add(issue);
  return dates.reversed.toList();
}
