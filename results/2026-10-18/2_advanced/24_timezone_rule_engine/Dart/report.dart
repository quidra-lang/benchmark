import 'dart:io';
import 'day_rules.dart';
import 'resolver.dart';

String padded(int number, [int width = 2]) => number.toString().padLeft(width, '0');
String localText(int time) {
  final (year, month, day, hour, minute, second) = splitTime(time);
  return '${padded(year, 4)}-${padded(month)}-${padded(day)}T${padded(hour)}:${padded(minute)}:${padded(second)}';
}
String utText(int time) => '${localText(time)}Z';
String offsetText(int value) {
  final sign = value < 0 ? '-' : '+';
  value = value.abs();
  var text = '$sign${padded(value ~/ 3600)}:${padded(value ~/ 60 % 60)}';
  if (value % 60 != 0) text += ':${padded(value % 60)}';
  return text;
}
String durationText(int value) {
  final sign = value < 0 ? '-' : '';
  value = value.abs();
  return '$sign${value ~/ 3600}:${padded(value ~/ 60 % 60)}:${padded(value % 60)}';
}
String clockText(int value) {
  var text = '${value ~/ 3600}:${padded(value ~/ 60 % 60)}';
  if (value % 60 != 0) text += ':${padded(value % 60)}';
  return text;
}
String stateText(Period period) => '${offsetText(period.offset)} ${period.dst ? 'DST' : 'STD'} ${period.abbreviation}';
String changeText(int time, Period before, Period after) => '${utText(time)} ${stateText(before)} -> ${stateText(after)}';
void writeLines(String name, List<String> lines) =>
    File('output/$name').writeAsStringSync(lines.isEmpty ? '' : '${lines.join('\n')}\n');
void writeBlocks(String name, List<List<String>> blocks) {
  final lines = <String>[];
  for (var i = 0; i < blocks.length; i++) {
    if (i > 0) lines.add('');
    lines.addAll(blocks[i]);
  }
  writeLines(name, lines);
}
