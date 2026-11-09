import 'dart:collection';
import 'dart:convert';
import 'dart:io';

enum Kind { uint32, uint64, sint32, sint64, boolType, fixed32, sfixed32, fixed64, string, bytes, enumType, message }

final class SchemaType {
  final String name;
  final Kind kind;
  final fields = <Field>[];
  final numbers = SplayTreeMap<int, String>();
  final names = <String, int>{};
  SchemaType(this.name, this.kind);

  int get wire => switch (kind) {
    Kind.fixed64 => 1,
    Kind.string || Kind.bytes || Kind.message => 2,
    Kind.fixed32 || Kind.sfixed32 => 5,
    _ => 0,
  };
  bool get packable => wire != 2;
  Field? byName(String name) {
    for (final field in fields) {
      if (field.name == name) return field;
    }
    return null;
  }
  Field? byNumber(int number) {
    for (final field in fields) {
      if (field.number == number) return field;
    }
    return null;
  }
}

final class Field {
  final int number;
  final String typeName, name;
  final bool isRequired, isRepeated, isPacked;
  final String? group;
  late SchemaType type;
  Field(this.number, this.typeName, this.name, this.isRequired, this.isRepeated, this.isPacked, this.group);
}

sealed class Value {}
final class NumberValue extends Value {
  final int number;
  NumberValue(this.number);
}
final class BooleanValue extends Value {
  final bool state;
  BooleanValue(this.state);
}
final class BinaryValue extends Value {
  final List<int> bytes;
  BinaryValue(this.bytes);
}
final class Unknown {
  final int number, wire, integer;
  final List<int> bytes;
  Unknown(this.number, this.wire, this.integer, this.bytes);
}
final class Message extends Value {
  final SchemaType type;
  final fields = <Field, List<Value>>{};
  final unknown = <Unknown>[];
  Message(this.type);

  List<Value> values(Field field) => fields[field] ?? <Value>[];
  void choose(Field field) {
    if (field.group == null) return;
    for (final other in type.fields) {
      if (other != field && other.group == field.group) fields.remove(other);
    }
  }
  void apply(Field field, List<Value> incoming) {
    if (incoming.isEmpty) return;
    choose(field);
    if (field.isRepeated) {
      (fields[field] ??= []).addAll(incoming);
    } else if (field.type.kind == Kind.message && fields.containsKey(field)) {
      (fields[field]!.first as Message).merge(incoming.first as Message);
    } else {
      fields[field] = incoming;
    }
  }
  void merge(Message source) {
    for (final field in type.fields) {
      apply(field, source.values(field));
    }
    unknown.addAll(source.unknown);
  }
}

final class CodecError implements Exception {
  final String message;
  CodecError(this.message);
}

String hexDigits(List<int> bytes) => bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
String hex(List<int> bytes) => bytes.isEmpty ? '-' : hexDigits(bytes);
String byteNotation(List<int> bytes) => '<' + hexDigits(bytes) + '>';
String wireName(int wire) => switch (wire) { 0 => 'varint', 1 => 'i64', 2 => 'len', _ => 'i32' };
String rawNotation(Unknown value) => value.wire == 0 ? value.integer.toString() : byteNotation(value.bytes);
String quote(List<int> bytes, bool json) {
  final result = StringBuffer('"');
  for (final byte in bytes) {
    result.write(switch (byte) {
      34 => r'\"', 92 => r'\\', 10 => r'\n', 9 => r'\t',
      >= 32 && <= 126 => String.fromCharCode(byte),
      _ => (json ? r'\u00' : r'\x') + byte.toRadixString(16).padLeft(2, '0'),
    });
  }
  return (result..write('"')).toString();
}
String valueNotation(SchemaType type, Value value, {bool json = false}) {
  if (value is NumberValue) {
    final number = value.number;
    if (type.kind == Kind.enumType) {
      final name = type.numbers[number]!;
      return json ? '"$name"' : name;
    }
    final wide = [Kind.uint64, Kind.sint64, Kind.fixed64].contains(type.kind);
    return json && wide ? '"$number"' : '$number';
  }
  if (value is BooleanValue) return value.state ? 'true' : 'false';
  if (value is BinaryValue) {
    if (type.kind == Kind.string) return quote(value.bytes, json);
    return json ? '"' + base64Encode(value.bytes) + '"' : byteNotation(value.bytes);
  }
  return messageNotation(value as Message, json: json);
}
String sequenceNotation(SchemaType type, List<Value> values, {bool json = false}) =>
    '[' + values.map((value) => valueNotation(type, value, json: json)).join(json ? ',' : ', ') + ']';
String jsonName(String name) => name.replaceAllMapped(RegExp(r'_([a-z0-9])'), (match) => match[1]!.toUpperCase());
String messageNotation(Message message, {bool json = false}) {
  final items = <String>[];
  for (final field in message.type.fields) {
    final values = message.values(field);
    if (values.isEmpty) continue;
    final key = json ? '"' + jsonName(field.name) + '":' : field.name + ': ';
    items.add(key + (field.isRepeated ? sequenceNotation(field.type, values, json: json) :
        valueNotation(field.type, values.first, json: json)));
  }
  return '{' + items.join(json ? ',' : ', ') + '}';
}
List<String> textNotation(Message message) {
  final lines = [message.type.name + ' {'];
  void contents(Message current, int depth) {
    final indent = '  ' * depth;
    for (final field in current.type.fields) {
      for (final value in current.values(field)) {
        if (value is Message) {
          lines.add(indent + field.name + ' {');
          contents(value, depth + 1);
          lines.add('$indent}');
        } else {
          lines.add(indent + field.name + ': ' + valueNotation(field.type, value));
        }
      }
    }
    for (final value in current.unknown) {
      lines.add(indent + value.number.toString() + ': ' + wireName(value.wire) + ' ' + rawNotation(value));
    }
  }
  contents(message, 1);
  lines.add('}');
  return lines;
}

const maxUnsigned = 9007199254740991;
int zigzag(int value) => value >= 0 ? 2 * value : -2 * value - 1;
int unzigzag(int value) => value.isEven ? value ~/ 2 : -1 - value ~/ 2;
bool inRange(SchemaType type, int value) => switch (type.kind) {
  Kind.uint32 || Kind.fixed32 => value >= 0 && value <= 4294967295,
  Kind.uint64 || Kind.fixed64 => value >= 0 && value <= maxUnsigned,
  Kind.sint32 || Kind.sfixed32 => value >= -2147483648 && value <= 2147483647,
  Kind.sint64 => value >= -4503599627370496 && value <= 4503599627370495,
  _ => true,
};
void writeVarint(List<int> output, int value) {
  while (value >= 128) {
    output.add(value % 128 + 128);
    value ~/= 128;
  }
  output.add(value);
}
void writeElement(List<int> output, SchemaType type, Value value) {
  if (value is Message || value is BinaryValue) {
    final payload = value is Message ? encode(value) : (value as BinaryValue).bytes;
    writeVarint(output, payload.length);
    output.addAll(payload);
    return;
  }
  var number = value is BooleanValue ? (value.state ? 1 : 0) : (value as NumberValue).number;
  if (type.kind == Kind.sint32 || type.kind == Kind.sint64) number = zigzag(number);
  if (type.kind == Kind.sfixed32 && number < 0) number += 4294967296;
  if (type.wire == 0) {
    writeVarint(output, number);
  } else {
    for (var i = 0; i < (type.wire == 1 ? 8 : 4); i++) {
      output.add(number % 256);
      number ~/= 256;
    }
  }
}
List<int> encodeField(Field field, List<Value> values) {
  final output = <int>[];
  if (values.isEmpty) return output;
  if (field.isPacked) {
    final payload = <int>[];
    for (final value in values) {
      writeElement(payload, field.type, value);
    }
    writeVarint(output, field.number * 8 + 2);
    writeVarint(output, payload.length);
    output.addAll(payload);
  } else {
    for (final value in values) {
      writeVarint(output, field.number * 8 + field.type.wire);
      writeElement(output, field.type, value);
    }
  }
  return output;
}
List<int> encode(Message message) {
  final output = <int>[];
  for (final field in message.type.fields) {
    output.addAll(encodeField(field, message.values(field)));
  }
  for (final value in message.unknown) {
    writeVarint(output, value.number * 8 + value.wire);
    if (value.wire == 0) {
      writeVarint(output, value.integer);
    } else {
      if (value.wire == 2) writeVarint(output, value.bytes.length);
      output.addAll(value.bytes);
    }
  }
  return output;
}
void checkRequired(Message message, [String prefix = '']) {
  for (final field in message.type.fields) {
    final values = message.values(field), path = prefix + field.name;
    if (field.isRequired && values.isEmpty) throw CodecError('missing required field $path');
    if (field.type.kind == Kind.message) {
      for (var i = 0; i < values.length; i++) {
        checkRequired(values[i] as Message, path + (field.isRepeated ? '[$i]' : '') + '.');
      }
    }
  }
}

final class Raw {
  final int number, position, payload;
  final List<int> bytes;
  Raw(this.number, this.bytes, this.position, this.payload);
}
CodecError byteError(String reason, int position) => CodecError('$reason at byte $position');
final class Reader {
  final List<int> data;
  final int end;
  int position;
  Reader(this.data, this.position, this.end);

  int varint() {
    final start = position;
    var value = 0;
    for (var i = 0; i < 8; i++) {
      if (position == end) throw byteError('truncated varint', start);
      final byte = data[position++];
      value += (byte & 127) << (7 * i);
      if (byte < 128) {
        if (value > maxUnsigned) throw byteError('varint too large', start);
        return value;
      }
    }
    throw byteError('varint too long', start);
  }
  Raw read(int wire) {
    final start = position;
    if (wire == 0) return Raw(varint(), [], start, start);
    final length = wire == 2 ? varint() : wire == 1 ? 8 : 4;
    if (length > end - position) {
      throw byteError(wire == 2 ? 'length past end' : wire == 1 ? 'truncated i64' : 'truncated i32', start);
    }
    final payload = position;
    position += length;
    return Raw(0, data.sublist(payload, position), start, payload);
  }
}

final class Decoder {
  final List<int> data;
  final bool explain;
  final lines = <String>[];
  Decoder(this.data, {this.explain = false});

  Value convertValue(SchemaType type, Raw raw) {
    if (type.kind == Kind.string) {
      for (var i = 0; i < raw.bytes.length; i++) {
        if (raw.bytes[i] >= 128) throw byteError('invalid string', raw.payload + i);
      }
      return BinaryValue(raw.bytes);
    }
    if (type.kind == Kind.bytes) return BinaryValue(raw.bytes);
    var number = raw.number;
    if (type.wire == 1 || type.wire == 5) {
      if (type.kind == Kind.fixed64 && (raw.bytes[7] != 0 || raw.bytes[6] >= 32)) {
        throw byteError('value out of range', raw.position);
      }
      number = 0;
      for (var i = raw.bytes.length - 1; i >= 0; i--) {
        number = number * 256 + raw.bytes[i];
      }
    }
    if (type.kind == Kind.sint32 || type.kind == Kind.sint64) number = unzigzag(number);
    if (type.kind == Kind.sfixed32 && number >= 2147483648) number -= 4294967296;
    if (!inRange(type, number)) throw byteError('value out of range', raw.position);
    if (type.kind == Kind.boolType) {
      if (number > 1) throw byteError('value out of range', raw.position);
      return BooleanValue(number == 1);
    }
    if (type.kind == Kind.enumType && !type.numbers.containsKey(number)) {
      throw byteError('unknown enum number', raw.position);
    }
    return NumberValue(number);
  }
  Message readMessage(SchemaType type, int start, int end, int depth) {
    final message = Message(type), reader = Reader(data, start, end);
    while (reader.position < end) {
      final offset = reader.position, tag = reader.varint();
      final number = tag ~/ 8, wire = tag % 8;
      if (number == 0) throw byteError('invalid field number', offset);
      if (![0, 1, 2, 5].contains(wire)) throw byteError('invalid wire type', offset);
      final field = type.byNumber(number);
      final packed = field != null && field.isRepeated && field.type.packable && wire == 2;
      if (field != null && wire != field.type.wire && !packed) throw byteError('wire type mismatch', offset);
      final raw = reader.read(wire);
      final header = '  ' * depth + '$offset $number ' + (field?.name ?? '?') + ' ' + wireName(wire) +
          (wire == 2 ? ' ' + raw.bytes.length.toString() : '');
      if (field == null) {
        final unknown = Unknown(number, wire, raw.number, raw.bytes);
        if (explain) {
          lines.add('$header ' + rawNotation(unknown));
        } else {
          message.unknown.add(unknown);
        }
        continue;
      }
      final values = <Value>[];
      if (field.type.kind == Kind.message) {
        if (explain) lines.add(header);
        values.add(readMessage(field.type, raw.payload, raw.payload + raw.bytes.length, depth + 1));
      } else if (packed) {
        final elements = Reader(data, raw.payload, raw.payload + raw.bytes.length);
        while (elements.position < elements.end) {
          values.add(convertValue(field.type, elements.read(field.type.wire)));
        }
        if (explain) lines.add('$header packed' + values.map((value) => ' ' + valueNotation(field.type, value)).join());
      } else {
        values.add(convertValue(field.type, raw));
        if (explain) lines.add('$header ' + valueNotation(field.type, values.first));
      }
      if (!explain) message.apply(field, values);
    }
    return message;
  }
  Message decode(SchemaType type) {
    final message = readMessage(type, 0, data.length, 0);
    if (explain) {
      if (lines.isEmpty) lines.add('(empty)');
    } else {
      checkRequired(message);
    }
    return message;
  }
}

enum TokenKind { symbol, integer, name, string, bytes, end }
enum Shape { none, message, list, integer, boolean, name, string, bytes }
final class Token {
  final TokenKind kind;
  final String text;
  final int column, number;
  final List<int> data;
  Token(this.kind, this.text, this.column, {this.number = 0, this.data = const []});
  Shape get shape => switch (kind) {
    TokenKind.integer => Shape.integer, TokenKind.string => Shape.string, TokenKind.bytes => Shape.bytes,
    TokenKind.name => text == 'true' || text == 'false' ? Shape.boolean : Shape.name,
    TokenKind.symbol when text == '{' => Shape.message,
    TokenKind.symbol when text == '[' => Shape.list,
    _ => Shape.none,
  };
}
bool digit(int code) => code >= 48 && code <= 57;
bool letter(int code) => code >= 65 && code <= 90 || code >= 97 && code <= 122;
int hexDigit(int code) => digit(code) ? code - 48 : code >= 97 && code <= 102 ? code - 87 : -1;
List<int> parseHexDigits(String text) => [for (var i = 0; i < text.length; i += 2) int.parse(text.substring(i, i + 2), radix: 16)];

final class Literal {
  final tokens = <Token>[];
  int position = 0;
  Token get next => tokens[position];
  CodecError error(String reason, Token token) => CodecError('$reason at column ' + token.column.toString());
  Literal(String text) {
    var at = 0;
    while (at < text.length) {
      final character = text[at];
      if (character == ' ') { at++; continue; }
      final start = at++;
      final token = Token(TokenKind.symbol, character, start + 1);
      if ('{}[]:,'.contains(character)) {
        tokens.add(token);
      } else if (character == '"') {
        final bytes = <int>[];
        var closed = false;
        while (at < text.length) {
          final current = text[at++];
          if (current == '"') { closed = true; break; }
          if (current != '\\') { bytes.add(current.codeUnitAt(0)); continue; }
          if (at == text.length) throw error('syntax error', token);
          final escaped = text[at++];
          if (escaped == '"' || escaped == '\\') {
            bytes.add(escaped.codeUnitAt(0));
          } else if (escaped == 'n') {
            bytes.add(10);
          } else if (escaped == 't') {
            bytes.add(9);
          } else if (escaped == 'x') {
            if (at + 2 > text.length) throw error('syntax error', token);
            final high = hexDigit(text.codeUnitAt(at)), low = hexDigit(text.codeUnitAt(at + 1));
            if (high < 0 || high > 7 || low < 0) throw error('syntax error', token);
            bytes.add(high * 16 + low);
            at += 2;
          } else {
            throw error('syntax error', token);
          }
        }
        if (!closed) throw error('syntax error', token);
        tokens.add(Token(TokenKind.string, '', start + 1, data: bytes));
      } else if (character == '<') {
        final end = text.indexOf('>', at);
        if (end < 0) throw error('syntax error', token);
        final digits = text.substring(at, end);
        if (digits.length.isOdd || digits.codeUnits.any((code) => hexDigit(code) < 0)) throw error('syntax error', token);
        tokens.add(Token(TokenKind.bytes, '', start + 1, data: parseHexDigits(digits)));
        at = end + 1;
      } else if (character == '-' || digit(character.codeUnitAt(0))) {
        if (character == '-' && (at == text.length || !digit(text.codeUnitAt(at)))) throw error('syntax error', token);
        while (at < text.length && digit(text.codeUnitAt(at))) { at++; }
        tokens.add(Token(TokenKind.integer, '', start + 1, number: int.parse(text.substring(start, at))));
      } else if (letter(character.codeUnitAt(0)) || character == '_') {
        while (at < text.length && (letter(text.codeUnitAt(at)) || digit(text.codeUnitAt(at)) || text[at] == '_')) { at++; }
        tokens.add(Token(TokenKind.name, text.substring(start, at), start + 1));
      } else {
        throw error('syntax error', token);
      }
    }
    tokens.add(Token(TokenKind.end, '', text.length + 1));
  }
  bool isSymbol(String symbol) => next.kind == TokenKind.symbol && next.text == symbol;
  void expect(String symbol) {
    if (!isSymbol(symbol)) throw error('syntax error', next);
    position++;
  }
  void end() {
    if (next.kind != TokenKind.end) throw error('syntax error', next);
  }
  void require(Shape shape) {
    if (next.shape == Shape.none) throw error('syntax error', next);
    if (next.shape != shape) throw error('type mismatch', next);
  }
  Message message(SchemaType type) {
    expect('{');
    final result = Message(type), seen = <Field>{}, groups = <String>{};
    if (!isSymbol('}')) {
      while (true) {
        final name = next;
        if (name.kind != TokenKind.name) throw error('syntax error', name);
        final field = type.byName(name.text);
        if (field == null) throw error('unknown field', name);
        if (!seen.add(field)) throw error('duplicate field', name);
        if (field.group != null && !groups.add(field.group!)) throw error('oneof conflict', name);
        position++;
        expect(':');
        result.fields[field] = fieldValue(field);
        if (!isSymbol(',')) break;
        position++;
      }
    }
    final closing = next;
    expect('}');
    for (final field in type.fields) {
      if (field.isRequired && !seen.contains(field)) throw error('missing required field ' + field.name, closing);
    }
    return result;
  }
  List<Value> fieldValue(Field field) {
    if (!field.isRepeated) return [element(field.type)];
    require(Shape.list);
    expect('[');
    final values = <Value>[];
    if (!isSymbol(']')) {
      values.add(element(field.type));
      while (isSymbol(',')) { position++; values.add(element(field.type)); }
    }
    expect(']');
    return values;
  }
  Value element(SchemaType type) {
    final shape = switch (type.kind) {
      Kind.boolType => Shape.boolean, Kind.string => Shape.string, Kind.bytes => Shape.bytes,
      Kind.enumType => Shape.name, Kind.message => Shape.message, _ => Shape.integer,
    };
    require(shape);
    final token = next;
    if (shape == Shape.message) return message(type);
    position++;
    if (shape == Shape.integer) {
      if (!inRange(type, token.number)) throw error('out of range', token);
      return NumberValue(token.number);
    }
    if (shape == Shape.boolean) return BooleanValue(token.text == 'true');
    if (shape == Shape.name) {
      final number = type.names[token.text];
      if (number == null) throw error('unknown enum value', token);
      return NumberValue(number);
    }
    return BinaryValue(token.data);
  }
}

final class Segment {
  final Field field;
  final int? index;
  Segment(this.field, this.index);
  bool get wholeList => field.isRepeated && index == null;
}

final class Engine {
  final types = <String, SchemaType>{};
  Engine() {
    const names = ['uint32', 'uint64', 'sint32', 'sint64', 'bool', 'fixed32', 'sfixed32', 'fixed64', 'string', 'bytes'];
    for (var i = 0; i < names.length; i++) {
      types[names[i]] = SchemaType(names[i], Kind.values[i]);
    }
  }
  void readSchema() {
    SchemaType? current;
    while (true) {
      final line = stdin.readLineSync()!;
      if (line == 'END SCHEMA') break;
      final words = line.split(' ');
      if (words[0] == 'ENUM' || words[0] == 'MESSAGE') {
        current = SchemaType(words[1], words[0] == 'ENUM' ? Kind.enumType : Kind.message);
        types[current.name] = current;
      } else if (words[0] == 'VALUE') {
        final number = int.parse(words[2]);
        final definition = current!;
        definition.numbers[number] = words[1];
        definition.names[words[1]] = number;
      } else if (words[0] == 'FIELD') {
        final mode = words.length > 4 ? words[4] : '';
        current!.fields.add(Field(int.parse(words[1]), words[2], words[3], mode == 'REQUIRED',
            mode == 'REPEATED', words.length > 5 && words[5] == 'PACKED', mode == 'ONEOF' ? words[5] : null));
      }
    }
    for (final type in types.values) {
      type.fields.sort((a, b) => a.number.compareTo(b.number));
      for (final field in type.fields) {
        field.type = types[field.typeName]!;
      }
    }
  }
  List<Segment> path(SchemaType type, String text) {
    final segments = <Segment>[], words = text.split('.');
    for (var i = 0; i < words.length; i++) {
      final match = RegExp(r'^([a-z][a-z0-9_]*)(?:\[([0-9]{1,6})\])?$').firstMatch(words[i]);
      if (match == null) throw CodecError('invalid path');
      final field = type.byName(match[1]!);
      final index = match[2] == null ? null : int.parse(match[2]!);
      if (field == null || index != null && !field.isRepeated) throw CodecError('invalid path');
      if (i + 1 < words.length && (field.type.kind != Kind.message || field.isRepeated && index == null)) {
        throw CodecError('invalid path');
      }
      segments.add(Segment(field, index));
      type = field.type;
    }
    return segments;
  }
  String get(Message message, List<Segment> segments) {
    Message? current = message;
    for (var step = 0; step < segments.length; step++) {
      final segment = segments[step], values = current?.values(segments[step].field) ?? <Value>[];
      final index = segment.index ?? 0;
      if (step == segments.length - 1) {
        if (segment.wholeList) return sequenceNotation(segment.field.type, values);
        return index < values.length ? valueNotation(segment.field.type, values[index]) : '(none)';
      }
      current = index < values.length ? values[index] as Message : null;
    }
    throw StateError('Empty path');
  }
  void edit(Message message, List<Segment> segments, List<Value>? replacement) {
    var current = message;
    for (var i = 0; i < segments.length - 1; i++) {
      final segment = segments[i], index = segments[i].index ?? 0;
      var values = current.values(segment.field);
      if (index >= values.length) {
        if (replacement == null) return;
        if (segment.index != null) throw CodecError('index out of range');
        current.choose(segment.field);
        values = [Message(segment.field.type)];
        current.fields[segment.field] = values;
      }
      current = values[index] as Message;
    }
    final last = segments.last, index = segments.last.index;
    if (index != null) {
      final values = current.values(last.field);
      if (index >= values.length) {
        if (replacement != null) throw CodecError('index out of range');
      } else if (replacement == null) {
        values.removeAt(index);
      } else {
        values[index] = replacement.first;
      }
    } else if (replacement == null) {
      current.fields.remove(last.field);
    } else {
      current.choose(last.field);
      current.fields[last.field] = replacement;
    }
  }
  bool equal(Value a, Value b) {
    if (a is NumberValue && b is NumberValue) return a.number == b.number;
    if (a is BooleanValue && b is BooleanValue) return a.state == b.state;
    if (a is BinaryValue && b is BinaryValue) {
      if (a.bytes.length != b.bytes.length) return false;
      for (var i = 0; i < a.bytes.length; i++) {
        if (a.bytes[i] != b.bytes[i]) return false;
      }
      return true;
    }
    return false;
  }
  void differences(Message a, Message b, String prefix, List<String> lines) {
    for (final field in a.type.fields) {
      final x = a.values(field), y = b.values(field);
      final count = x.length > y.length ? x.length : y.length;
      for (var i = 0; i < count; i++) {
        final path = prefix + field.name + (field.isRepeated ? '[$i]' : '');
        if (i < x.length && i < y.length && field.type.kind == Kind.message) {
          differences(x[i] as Message, y[i] as Message, '$path.', lines);
        } else if (i >= x.length || i >= y.length || !equal(x[i], y[i])) {
          lines.add('$path: ' + (i < x.length ? valueNotation(field.type, x[i]) : '(none)') +
              ' -> ' + (i < y.length ? valueNotation(field.type, y[i]) : '(none)'));
        }
      }
    }
  }
  List<String> schema(SchemaType type) {
    final lines = [type.name], chain = <SchemaType>{};
    void visit(SchemaType current, int depth) {
      chain.add(current);
      for (final field in current.fields) {
        final mode = field.isRequired ? 'required ' : field.isPacked ? 'repeated packed ' :
            field.isRepeated ? 'repeated ' : field.group != null ? 'oneof ' + field.group! + ' ' : '';
        var line = '  ' * depth + field.number.toString() + ' ' + field.name + ': ' + mode + field.type.name;
        if (field.type.kind == Kind.enumType) {
          line += ' (' + field.type.numbers.entries.map((entry) => entry.value + '=' + entry.key.toString()).join(', ') + ')';
        }
        final recursive = field.type.kind == Kind.message && chain.contains(field.type);
        lines.add(line + (recursive ? ' (recursive)' : ''));
        if (field.type.kind == Kind.message && !recursive) visit(field.type, depth + 1);
      }
      chain.remove(current);
    }
    visit(type, 1);
    return lines;
  }
  List<int> parseHex(String text) {
    if (text == '-') return [];
    if (!RegExp(r'^(?:[0-9a-f]{2})+$').hasMatch(text)) throw CodecError('invalid hex');
    return parseHexDigits(text);
  }
  String rest(String line, int separators) {
    var at = -1;
    for (var i = 0; i < separators; i++) {
      at = line.indexOf(' ', at + 1);
    }
    return line.substring(at + 1);
  }
  Message decode(SchemaType type, List<int> data, [String suffix = '']) {
    try {
      return Decoder(data).decode(type);
    } on CodecError catch (error) {
      throw CodecError(error.message + suffix);
    }
  }
  List<String> execute(String line) {
    final words = line.split(' '), command = words.first;
    final minimum = switch (command) {
      'VARINT' || 'ZIGZAG' || 'SCHEMA' => 2,
      'ENCODE' || 'SIZE' || 'DECODE' || 'LITERAL' || 'JSON' || 'CANON' || 'EXPLAIN' => 3,
      'GET' || 'CLEAR' || 'MERGE' || 'DIFF' => 4, 'PATCH' => 5, _ => 0,
    };
    if (minimum == 0) throw CodecError('unknown command');
    if (words.length < minimum || !['ENCODE', 'SIZE', 'PATCH'].contains(command) && words.length != minimum) {
      throw CodecError('wrong number of arguments');
    }
    if (command == 'VARINT' || command == 'ZIGZAG') {
      if (!RegExp(r'^-?[0-9]{1,18}$').hasMatch(words[1])) throw CodecError('invalid number');
      final number = int.parse(words[1]);
      if (command == 'VARINT' ? number < 0 || number > maxUnsigned :
          number < -4503599627370496 || number > 4503599627370495) {
        throw CodecError('invalid number');
      }
      final value = command == 'ZIGZAG' ? zigzag(number) : number;
      final bytes = <int>[];
      writeVarint(bytes, value);
      return [(command == 'ZIGZAG' ? '$value ' : '') + hex(bytes)];
    }
    final type = types[words[1]];
    if (type == null || type.kind != Kind.message) throw CodecError('unknown message type');
    final data = ['SCHEMA', 'ENCODE', 'SIZE'].contains(command) ? <int>[] : parseHex(words[2]);
    final second = command == 'MERGE' || command == 'DIFF' ? parseHex(words[3]) : <int>[];
    final segments = ['GET', 'PATCH', 'CLEAR'].contains(command) ? path(type, words[3]) : <Segment>[];
    if (command == 'SCHEMA') return schema(type);
    if (command == 'ENCODE' || command == 'SIZE') {
      final literal = Literal(rest(line, 2)), message = literal.message(type);
      literal.end();
      final encoded = encode(message);
      if (command == 'ENCODE') return [hex(encoded)];
      return [encoded.length.toString() + type.fields.where((field) => message.values(field).isNotEmpty)
          .map((field) => ' ' + field.name + '=' + encodeField(field, message.values(field)).length.toString()).join()];
    }
    if (command == 'EXPLAIN') {
      final decoder = Decoder(data, explain: true);
      decoder.decode(type);
      return decoder.lines;
    }
    if (command == 'MERGE') return textNotation(decode(type, [...data, ...second]));
    if (command == 'DIFF') {
      final a = decode(type, data, ' in first');
      final b = decode(type, second, ' in second');
      final lines = <String>[];
      differences(a, b, '', lines);
      return lines.isEmpty ? ['SAME'] : lines;
    }
    final message = decode(type, data);
    if (command == 'DECODE') return textNotation(message);
    if (command == 'LITERAL') return [messageNotation(message)];
    if (command == 'JSON') return [messageNotation(message, json: true)];
    if (command == 'GET') return [get(message, segments)];
    if (command == 'PATCH') {
      final literal = Literal(rest(line, 4)), last = segments.last;
      final replacement = last.wholeList ? literal.fieldValue(last.field) : [literal.element(last.field.type)];
      literal.end();
      edit(message, segments, replacement);
      checkRequired(message);
    } else if (command == 'CLEAR') {
      edit(message, segments, null);
      checkRequired(message);
    }
    return [hex(encode(message))];
  }
}

void main() {
  final engine = Engine()..readSchema();
  final count = int.parse(stdin.readLineSync()!);
  for (var i = 0; i < count; i++) {
    try {
      for (final line in engine.execute(stdin.readLineSync()!)) {
        stdout.writeln(line);
      }
    } on CodecError catch (error) {
      stdout.writeln('ERROR ' + error.message);
    }
  }
}
