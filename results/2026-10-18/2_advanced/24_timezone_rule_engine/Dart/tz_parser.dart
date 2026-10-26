import 'day_rules.dart';

class FieldError implements Exception {
  final String message;
  FieldError(this.message);
}
class Until {
  final String yearText;
  final String monthText;
  final String dayText;
  final int time;
  final String type;
  final int value;
  Until(this.yearText, this.monthText, this.dayText, this.time, this.type, this.value);
}
String lineContent(String raw) {
  final index = raw.indexOf('#');
  return (index < 0 ? raw : raw.substring(0, index)).replaceFirst(RegExp(r' +$'), '');
}
List<String> splitFields(String content) => content.trim().split(RegExp(' +'));
bool isContinuation(String content) => content.startsWith(' ');
bool isNumber(String text, int low, int high) =>
    text.length >= low && text.length <= high && RegExp(r'^[0-9]+$').hasMatch(text);
int? hmsValue(String text, int maxParts) {
  final parts = text.split(':');
  if (parts.length > maxParts || !isNumber(parts[0], 1, 2)) return null;
  var value = int.parse(parts[0]) * 3600;
  const units = [60, 1];
  for (var i = 1; i < parts.length; i++) {
    if (!isNumber(parts[i], 2, 2) || int.parse(parts[i]) > 59) return null;
    value += int.parse(parts[i]) * units[i - 1];
  }
  return value;
}
int parseYear(String text) {
  if (!isNumber(text, 4, 4) || int.parse(text) < 1800 || int.parse(text) > 2099) throw FieldError('bad year');
  return int.parse(text);
}
int parseTo(String text, int from) {
  if (text == 'only') return from;
  if (text == 'max') return 2099;
  if (!isNumber(text, 4, 4) || int.parse(text) < from || int.parse(text) > 2099) throw FieldError('bad year');
  return int.parse(text);
}
int parseMonth(String text) {
  final value = monthNames.indexOf(text) + 1;
  if (value == 0) throw FieldError('bad month');
  return value;
}
int parseWeekday(String text) {
  final value = weekdayNames.indexOf(text);
  if (value < 0) throw FieldError('bad day spec');
  return value;
}
int parseDayOfMonth(String text, int month) {
  if (!isNumber(text, 1, 2) || text.startsWith('0') || int.parse(text) > commonMonthDays[month - 1]) throw FieldError('bad day spec');
  return int.parse(text);
}
DaySpec parseDaySpec(String text, int month) {
  if (text.startsWith('last')) return DaySpec('last', parseWeekday(text.substring(4)));
  for (final operator in ['>=', '<=']) {
    final position = text.indexOf(operator);
    if (position >= 0) {
      final day = parseWeekday(text.substring(0, position));
      final number = parseDayOfMonth(text.substring(position + 2), month);
      return DaySpec(operator == '>=' ? 'after' : 'before', day, number);
    }
  }
  return DaySpec('day', 0, parseDayOfMonth(text, month));
}
(int, String) parseTime(String text) {
  var type = 'w';
  if (text.isNotEmpty && 'wsu'.contains(text[text.length - 1])) {
    type = text[text.length - 1];
    text = text.substring(0, text.length - 1);
  }
  final value = hmsValue(text, 3);
  if (value == null || value > 86400) throw FieldError('bad time');
  return (value, type);
}
int parseSave(String text) {
  final value = hmsValue(text, 2);
  if (value == null || value > 7200) throw FieldError('bad save');
  return value;
}
String parseLetter(String text) {
  if (text == '-') return '';
  if (!RegExp(r'^[A-Z]{1,5}$').hasMatch(text)) throw FieldError('bad letter');
  return text;
}
int parseOffset(String text) {
  var sign = 1;
  if (text.startsWith('-')) {
    sign = -1;
    text = text.substring(1);
  }
  final value = hmsValue(text, 3);
  if (value == null || value >= 57600) throw FieldError('bad offset');
  return sign * value;
}
void checkFormat(String text, bool usesRules) {
  var placeholders = 0;
  var slashes = 0;
  for (var i = 0; i < text.length; i++) {
    final symbol = text[i];
    if (symbol == '%') {
      if (i + 1 >= text.length || text[i + 1] != 's') throw FieldError('bad format');
      placeholders++;
      i++;
    } else if (symbol == '/') {
      slashes++;
    } else if (!RegExp(r'^[A-Za-z0-9+-]$').hasMatch(symbol)) {
      throw FieldError('bad format');
    }
  }
  if (placeholders > 1 || slashes > 1 || placeholders > 0 && (slashes > 0 || !usesRules) || slashes == 1 && (text.startsWith('/') || text.endsWith('/'))) throw FieldError('bad format');
}
Until parseUntil(List<String> fields) {
  final year = parseYear(fields[0]);
  final monthText = fields.length > 1 ? fields[1] : 'Jan';
  final month = parseMonth(monthText);
  final dayText = fields.length > 2 ? fields[2] : '1';
  final day = parseDaySpec(dayText, month);
  final (time, type) = fields.length > 3 ? parseTime(fields[3]) : (0, 'w');
  return Until(fields[0], monthText, dayText, time, type, day.value(year, month) * secondsPerDay + time);
}
