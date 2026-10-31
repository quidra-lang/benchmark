import 'mime.dart';

const whitespace = ' \t';
const addressSpecials = '<>:;@,.';
const addressWordChars =
    r"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$%&'*+-/=?^_`{|}~";
const mimeExcluded = '()<>@,;:\\"/[]?=';

class MailLine {
  final int number;
  final String text;
  MailLine(this.number, this.text);
}

class Field {
  final String name;
  String value;
  Field(this.name, this.value);
}

class Header {
  final fields = <Field>[];
  final invalid = <int>[];

  String? value(String name) {
    name = name.toLowerCase();
    for (final field in fields) {
      if (field.name == name) return field.value;
    }
    return null;
  }

  int count(String name) =>
      fields.where((field) => field.name == name.toLowerCase()).length;
}

class Token {
  final String kind;
  final String text;
  final bool spaced;
  Token(this.kind, this.text, this.spaced);
}

class Parameters {
  final String mainType;
  final String subtype;
  final Map<String, String> values;
  Parameters(this.mainType, this.subtype, this.values);
}

List<String> splitWords(String text) =>
    text.split(RegExp(r'[ \t]+')).where((word) => word.isNotEmpty).toList();
String collapseWhitespace(String text) => splitWords(text).join(' ');
String stripWhitespace(String text) =>
    text.replaceFirst(RegExp(r'^[ \t]+'), '').replaceFirst(RegExp(r'[ \t]+$'), '');
String stripTrailing(String text) =>
    text.replaceFirst(RegExp(r'[ \t]+$'), '');

Header parseFields(List<MailLine> lines) {
  final header = Header();
  var inField = false;
  for (final line in lines) {
    final text = line.text;
    if (text.isNotEmpty && whitespace.contains(text[0])) {
      if (inField) {
        header.fields.last.value += text;
      } else {
        header.invalid.add(line.number);
      }
      continue;
    }
    final colon = text.indexOf(':');
    inField = colon > 0 &&
        text.substring(0, colon).codeUnits.every((c) => c >= 33 && c <= 126);
    if (inField) {
      header.fields.add(Field(
          text.substring(0, colon).toLowerCase(), text.substring(colon + 1)));
    } else {
      header.invalid.add(line.number);
    }
  }
  for (final field in header.fields) {
    field.value = stripWhitespace(field.value);
  }
  return header;
}

String? removeComments(String text) {
  final output = StringBuffer();
  var depth = 0;
  for (var position = 0; position < text.length; position++) {
    final c = text[position];
    if (depth == 0) {
      if (c == '(') {
        depth = 1;
        output.write(' ');
      } else {
        output.write(c);
      }
    } else if (c == '\\') {
      position++;
    } else if (c == '(') {
      depth++;
    } else if (c == ')') {
      depth--;
    }
  }
  return depth == 0 ? output.toString() : null;
}

List<Token>? tokenize(String text, bool mime) {
  final tokens = <Token>[];
  var position = 0;
  var spaced = false;
  final specials = mime ? '/;=' : addressSpecials;
  bool isWord(String c) => mime
      ? c.codeUnitAt(0) >= 33 &&
          c.codeUnitAt(0) <= 126 &&
          !mimeExcluded.contains(c)
      : addressWordChars.contains(c);
  while (position < text.length) {
    var c = text[position];
    if (whitespace.contains(c)) {
      spaced = true;
      position++;
      continue;
    }
    if (c == '(') {
      var depth = 1;
      position++;
      while (position < text.length && depth > 0) {
        c = text[position];
        if (c == '\\') {
          position += 2;
          continue;
        }
        if (c == '(') depth++;
        if (c == ')') depth--;
        position++;
      }
      if (depth != 0) return null;
      spaced = true;
      continue;
    }
    if (c == '"') {
      final value = StringBuffer();
      position++;
      var closed = false;
      while (position < text.length) {
        c = text[position++];
        if (c == '"') {
          closed = true;
          break;
        }
        if (c == '\\') {
          if (position == text.length) return null;
          c = text[position++];
        }
        value.write(c);
      }
      if (!closed) return null;
      tokens.add(Token('quoted', value.toString(), spaced));
    } else if (specials.contains(c)) {
      tokens.add(Token(c, c, spaced));
      position++;
    } else if (isWord(c)) {
      var end = position + 1;
      while (end < text.length && isWord(text[end])) {
        end++;
      }
      tokens.add(Token('word', text.substring(position, end), spaced));
      position = end;
    } else {
      return null;
    }
    spaced = false;
  }
  return tokens;
}

(String, bool, bool) decodeWord(String word) {
  if (word.length < 4 || !word.startsWith('=?') || !word.endsWith('?=')) {
    return (word, false, false);
  }
  final pieces = word.substring(2, word.length - 2).split('?');
  if (pieces.length != 3 || pieces.any((piece) => piece.isEmpty)) {
    return (word, false, false);
  }
  if (pieces[0].toLowerCase() != 'us-ascii') return (word, false, true);
  List<int>? data;
  if (pieces[1] == 'B' || pieces[1] == 'b') {
    data = strictBase64(pieces[2]);
  } else if (pieces[1] == 'Q' || pieces[1] == 'q') {
    data = <int>[];
    for (var position = 0; position < pieces[2].length;) {
      final c = pieces[2][position];
      if (c == '_') {
        data.add(32);
        position++;
      } else if (c == '=') {
        final value = escapedByte(pieces[2], position);
        if (value == null) return (word, false, true);
        data.add(value);
        position += 3;
      } else {
        data.add(c.codeUnitAt(0));
        position++;
      }
    }
  }
  if (data == null || data.any((c) => c < 32 || c > 126)) {
    return (word, false, true);
  }
  return (String.fromCharCodes(data), true, false);
}

(String, bool) decodeUnstructured(String value) {
  final output = StringBuffer();
  var previous = false;
  var error = false;
  final words = splitWords(value);
  for (var i = 0; i < words.length; i++) {
    final (text, decoded, failed) = decodeWord(words[i]);
    if (i > 0 && !(decoded && previous)) output.write(' ');
    output.write(text);
    previous = decoded;
    error = error || failed;
  }
  return (collapseWhitespace(output.toString()), error);
}

Parameters? parseParameters(String value, bool withSubtype) {
  final tokens = tokenize(value, true);
  if (tokens == null || tokens.isEmpty || tokens[0].kind != 'word') {
    return null;
  }
  final mainType = tokens[0].text.toLowerCase();
  var subtype = '';
  var position = 1;
  if (withSubtype) {
    if (tokens.length < 3 || tokens[1].kind != '/' || tokens[2].kind != 'word') {
      return null;
    }
    subtype = tokens[2].text.toLowerCase();
    position = 3;
  }
  final parameters = <String, String>{};
  while (position < tokens.length) {
    if (position + 3 >= tokens.length ||
        tokens[position].kind != ';' ||
        tokens[position + 1].kind != 'word' ||
        tokens[position + 2].kind != '=' ||
        !['word', 'quoted'].contains(tokens[position + 3].kind)) {
      return null;
    }
    parameters.putIfAbsent(tokens[position + 1].text.toLowerCase(),
        () => tokens[position + 3].text);
    position += 4;
  }
  return Parameters(mainType, subtype, parameters);
}
