import 'dates_calendar.dart';
const dayCounts = {'30/360', '30E/360', 'ACT/360', 'ACT/365F', 'ACT/ACT'};
(int, int) yearFraction(String convention, int start, int end) {
  var (y1, m1, d1) = civilDate(start);
  var (y2, m2, d2) = civilDate(end);
  if (convention == '30/360' || convention == '30E/360') {
    if (convention == '30/360') {
      final february = m1 == 2 && d1 == monthLength(y1, 2);
      if (february && m2 == 2 && d2 == monthLength(y2, 2)) d2 = 30;
      if (february) d1 = 30;
      if (d2 == 31 && d1 >= 30) d2 = 30;
      if (d1 == 31) d1 = 30;
    } else { if (d1 == 31) d1 = 30; if (d2 == 31) d2 = 30; }
    return (360 * (y2 - y1) + 30 * (m2 - m1) + d2 - d1, 360);
  }
  if (convention == 'ACT/360') return (end - start, 360);
  if (convention == 'ACT/365F') return (end - start, 365);
  var numerator = 0;
  while (start < end) {
    final boundary = dayNumber(y1 + 1, 1, 1) < end ? dayNumber(y1 + 1, 1, 1) : end;
    numerator += (boundary - start) * (isLeap(y1) ? 365 : 366);
    start = boundary; y1++;
  }
  return (numerator, 133590);
}
