part of 'main.dart';

class Value {
  final String kind, string;
  final int integer;
  const Value([this.kind = '', this.integer = 0, this.string = '']);
  int get number =>
      kind == 'number' || kind == 'strnum' ? integer : numericPrefix(string).$1;
  String get text => kind == 'number' ? '$integer' : string;
  bool get truth => kind == 'number' || kind == 'strnum'
      ? integer != 0
      : kind == 'string' && string.isNotEmpty;
}

Value numeric(int n) => Value('number', n);
Value stringValue(String s) => Value('string', 0, s);
bool whitespace(int c) => c == 32 || c == 9 || c == 10;
(int, int, bool) numericPrefix(String text) {
  var i = 0, sign = 1;
  while (i < text.length && whitespace(text.codeUnitAt(i))) i++;
  if (i < text.length && (text[i] == '+' || text[i] == '-')) {
    if (text[i] == '-') sign = -1;
    i++;
  }
  final start = i;
  while (i < text.length && digit(text.codeUnitAt(i))) i++;
  if (i == start) return (0, i, false);
  return (sign * decimal(text.substring(start, i)), i, true);
}

Value inputValue(String text) {
  final (n, end, valid) = numericPrefix(text);
  var last = end;
  while (last < text.length && whitespace(text.codeUnitAt(last))) last++;
  return valid && last == text.length
      ? Value('strnum', n, text)
      : stringValue(text);
}

int compare(Value a, Value b) => a.kind != 'string' && b.kind != 'string'
    ? a.number.compareTo(b.number)
    : a.text.compareTo(b.text);
bool integerForm(String text) {
  if (text == '0') return true;
  var i = text.startsWith('-') ? 1 : 0;
  if (i == text.length || text.codeUnitAt(i) < 49 || text.codeUnitAt(i) > 57)
    return false;
  for (i++; i < text.length; i++) {
    if (!digit(text.codeUnitAt(i))) return false;
  }
  return true;
}

List<String> orderedSubscripts(Map<String, Value> array) =>
    array.keys.toList()..sort((a, b) {
      final x = integerForm(a), y = integerForm(b);
      if (x != y) return x ? -1 : 1;
      return x ? decimal(a).compareTo(decimal(b)) : a.compareTo(b);
    });
List<String> splitPieces(String text, String separator) {
  if (text.isEmpty) return [];
  if (separator == ' ') {
    final pieces = <String>[];
    var i = 0;
    while (i < text.length) {
      while (i < text.length && whitespace(text.codeUnitAt(i))) i++;
      final start = i;
      while (i < text.length && !whitespace(text.codeUnitAt(i))) i++;
      if (i > start) pieces.add(text.substring(start, i));
    }
    return pieces;
  }
  if (separator.isEmpty) return [for (var i = 0; i < text.length; i++) text[i]];
  return text.split(separator);
}

class AwkRecord {
  Value zero = stringValue('');
  final List<Value> fields = [];
  final Value Function(String) global;
  AwkRecord(this.global);
  void set(String text) {
    zero = inputValue(text);
    fields.clear();
    fields.addAll(splitPieces(text, global('FS').text).map(inputValue));
  }

  Value read(int index) => index == 0
      ? zero
      : index > fields.length
      ? const Value()
      : fields[index - 1];
  void rebuild() {
    zero = inputValue(fields.map((v) => v.text).join(global('OFS').text));
  }

  void resize(int n) {
    if (n < fields.length) fields.removeRange(n, fields.length);
    while (fields.length < n) fields.add(stringValue(''));
    rebuild();
  }

  void write(int index, Value value) {
    if (index == 0) {
      set(value.text);
      return;
    }
    while (fields.length < index) fields.add(stringValue(''));
    fields[index - 1] = value;
    rebuild();
  }
}

String escapedString(String text) {
  final out = StringBuffer('"');
  for (final c in text.codeUnits) {
    out.write(switch (c) {
      92 => r'\\',
      34 => r'\"',
      10 => r'\n',
      9 => r'\t',
      _ =>
        c >= 32 && c <= 126
            ? String.fromCharCode(c)
            : '\\${c.toRadixString(8).padLeft(3, '0')}',
    });
  }
  out.write('"');
  return out.toString();
}

String describe(Value value) => switch (value.kind) {
  'number' => value.text,
  'string' => escapedString(value.string),
  'strnum' => '${escapedString(value.string)} (strnum)',
  _ => '(uninitialized)',
};
