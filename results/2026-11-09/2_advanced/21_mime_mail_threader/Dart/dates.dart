import 'headers.dart';

const weekdays = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
const months = [
  'jan', 'feb', 'mar', 'apr', 'may', 'jun',
  'jul', 'aug', 'sep', 'oct', 'nov', 'dec'
];
const namedZones = {
  'ut': 0, 'gmt': 0, 'z': 0, 'est': -300, 'edt': -240, 'cst': -360,
  'cdt': -300, 'mst': -420, 'mdt': -360, 'pst': -480, 'pdt': -420
};

bool leap(int year) => year % 4 == 0 && year % 100 != 0 || year % 400 == 0;
int yearDays(int year) => leap(year) ? 366 : 365;
int monthDays(int year, int month) {
  if (month == 2 && leap(year)) return 29;
  return [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1];
}

bool digits(String text, List<int> lengths) =>
    lengths.contains(text.length) && RegExp(r'^[0-9]+$').hasMatch(text);

(int?, String) parseDate(String value) {
  final text = removeComments(value);
  if (text == null) return (null, 'bad Date syntax');
  var tokens = splitWords(text.replaceAll(',', ' , '));
  var weekday = -1;
  if (tokens.length >= 3 && tokens[1] == ',') {
    weekday = weekdays.indexOf(tokens[0].toLowerCase());
    if (weekday >= 0) tokens = tokens.sublist(2);
  }
  if (tokens.length != 5) return (null, 'bad Date syntax');
  final pieces = tokens[3].split(':');
  final month = months.indexOf(tokens[1].toLowerCase()) + 1;
  final zone = tokens[4];
  final numericZone = zone.length == 5 &&
      (zone[0] == '+' || zone[0] == '-') && digits(zone.substring(1), [4]);
  var offset = namedZones[zone.toLowerCase()];
  if (!digits(tokens[0], [1, 2]) || month == 0 ||
      !digits(tokens[2], [2, 4]) || pieces.length < 2 || pieces.length > 3 ||
      pieces.any((piece) => !digits(piece, [2])) ||
      !(numericZone || offset != null)) {
    return (null, 'bad Date syntax');
  }
  final day = int.parse(tokens[0]);
  var year = int.parse(tokens[2]);
  if (tokens[2].length == 2) year += year < 50 ? 2000 : 1900;
  final hour = int.parse(pieces[0]);
  final minute = int.parse(pieces[1]);
  final second = pieces.length == 3 ? int.parse(pieces[2]) : 0;
  if (numericZone) {
    final hh = int.parse(zone.substring(1, 3));
    final mm = int.parse(zone.substring(3, 5));
    if (hh > 23 || mm > 59) return (null, 'Date out of range');
    offset = (hh * 60 + mm) * (zone[0] == '-' ? -1 : 1);
  }
  if (year < 1970 || year > 2099 || day < 1 ||
      day > monthDays(year, month) || hour > 23 || minute > 59 || second > 59) {
    return (null, 'Date out of range');
  }
  var days = 0;
  for (var current = 1970; current < year; current++) {
    days += yearDays(current);
  }
  for (var current = 1; current < month; current++) {
    days += monthDays(year, current);
  }
  days += day - 1;
  final seconds = days * 86400 + hour * 3600 + minute * 60 + second - offset! * 60;
  if (seconds < 0) return (null, 'Date out of range');
  if (weekday >= 0 && (days + 3) % 7 != weekday) {
    return (null, 'Date weekday mismatch');
  }
  return (seconds, '');
}

String formatUTC(int seconds) {
  var days = seconds ~/ 86400;
  final rest = seconds % 86400;
  var year = 1970;
  while (days >= yearDays(year)) {
    days -= yearDays(year);
    year++;
  }
  var month = 1;
  while (days >= monthDays(year, month)) {
    days -= monthDays(year, month);
    month++;
  }
  String pad(int value, int width) => value.toString().padLeft(width, '0');
  return '${pad(year, 4)}-${pad(month, 2)}-${pad(days + 1, 2)} '
      '${pad(rest ~/ 3600, 2)}:${pad((rest % 3600) ~/ 60, 2)}:${pad(rest % 60, 2)}';
}
