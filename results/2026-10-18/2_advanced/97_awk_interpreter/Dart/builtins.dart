part of 'main.dart';

class RuntimeIssue implements Exception {
  final Position position;
  final String message;
  RuntimeIssue(this.position, this.message);
}

Never runtimeError(Position position, String message) =>
    throw RuntimeIssue(position, message);
String formatOutput(List<Value> values, Position position) {
  final format = values[0].text;
  var argument = 1, i = 0;
  final out = StringBuffer();
  while (i < format.length) {
    if (format[i] != '%') {
      out.write(format[i++]);
      continue;
    }
    i++;
    if (i < format.length && format[i] == '%') {
      out.write('%');
      i++;
      continue;
    }
    var left = false, zero = false;
    while (i < format.length && (format[i] == '-' || format[i] == '0')) {
      left = left || format[i] == '-';
      zero = zero || format[i] == '0';
      i++;
    }
    var start = i;
    while (i < format.length && digit(format.codeUnitAt(i))) i++;
    final width = i > start ? decimal(format.substring(start, i)) : 0;
    var precision = -1;
    if (i < format.length && format[i] == '.') {
      start = ++i;
      while (i < format.length && digit(format.codeUnitAt(i))) i++;
      precision = i > start ? decimal(format.substring(start, i)) : 0;
    }
    if (i == format.length || !'discxo'.contains(format[i]))
      runtimeError(position, 'invalid format');
    final kind = format[i++];
    if (argument == values.length)
      runtimeError(position, 'not enough arguments');
    final value = values[argument++];
    var body = '';
    if ('dixo'.contains(kind)) {
      final n = value.number;
      final base = kind == 'x'
          ? 16
          : kind == 'o'
          ? 8
          : 10;
      var digits = n.abs().toRadixString(base);
      if (precision == 0 && n == 0) digits = '';
      if (precision > digits.length) digits = digits.padLeft(precision, '0');
      body = n < 0 ? '-$digits' : digits;
      if (body.length < width) {
        final pad = width - body.length;
        if (left) {
          body = body.padRight(width);
        } else if (zero && precision < 0) {
          body = n < 0
              ? '-${digits.padLeft(digits.length + pad, '0')}'
              : body.padLeft(width, '0');
        } else {
          body = body.padLeft(width);
        }
      }
    } else {
      if (kind == 's') {
        body = value.text;
        if (precision >= 0 && body.length > precision)
          body = body.substring(0, precision);
      } else if (value.kind == 'number' || value.kind == 'strnum') {
        final n = value.number;
        if (n != 10 && (n < 32 || n > 126))
          runtimeError(position, 'invalid character code');
        body = String.fromCharCode(n);
      } else {
        body = value.text;
        if (body.length > 1) body = body.substring(0, 1);
      }
      if (body.length < width)
        body = left ? body.padRight(width) : body.padLeft(width);
    }
    out.write(body);
  }
  return out.toString();
}

Value invokeBuiltin(String name, List<Value> values, Position position) {
  switch (name) {
    case 'substr':
      final text = values[0].text;
      var start = values[1].number;
      var end = values.length == 3 ? start + values[2].number : text.length + 1;
      start = max(start, 1);
      end = min(end, text.length + 1);
      return stringValue(end > start ? text.substring(start - 1, end - 1) : '');
    case 'index':
      final haystack = values[0].text, part = values[1].text;
      return numeric(part.isEmpty ? 0 : haystack.indexOf(part) + 1);
    case 'toupper':
      return stringValue(values[0].text.toUpperCase());
    case 'tolower':
      return stringValue(values[0].text.toLowerCase());
    case 'int':
      return numeric(values[0].number);
    case 'sprintf':
      return stringValue(formatOutput(values, position));
  }
  throw StateError('unknown built-in');
}
