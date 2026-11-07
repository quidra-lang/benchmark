const base64Alphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

List<int>? strictBase64(String text) {
  if (text.length % 4 != 0) return null;
  var end = text.length;
  while (end > 0 && text[end - 1] == '=') {
    end--;
  }
  if (text.length - end >= 3) return null;
  final result = <int>[];
  var buffer = 0;
  var bits = 0;
  for (var i = 0; i < end; i++) {
    final value = base64Alphabet.indexOf(text[i]);
    if (value < 0) return null;
    buffer = (buffer << 6) | value;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      result.add(buffer >> bits);
      buffer &= (1 << bits) - 1;
    }
  }
  return result;
}

String? decodeBase64Body(String text) {
  final compact = text.replaceAll(RegExp(r'[ \t\n]'), '');
  final data = strictBase64(compact);
  if (data == null) return null;
  final content = String.fromCharCodes(data).replaceAll('\r\n', '\n');
  if (content.codeUnits.any(
      (c) => c != 9 && c != 10 && (c < 32 || c > 126))) {
    return null;
  }
  return content;
}

int hexValue(String c) {
  final value = c.codeUnitAt(0);
  if (value >= 48 && value <= 57) return value - 48;
  if (value >= 65 && value <= 70) return value - 55;
  if (value >= 97 && value <= 102) return value - 87;
  return -1;
}

int? escapedByte(String text, int position) {
  if (position + 2 >= text.length) return null;
  final a = hexValue(text[position + 1]);
  final b = hexValue(text[position + 2]);
  if (a < 0 || b < 0) return null;
  return a * 16 + b;
}

(String, bool) decodeQuotedPrintable(String text) {
  final output = StringBuffer();
  var error = false;
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].replaceFirst(RegExp(r'[ \t]+$'), '');
    final soft = line.endsWith('=');
    if (soft) line = line.substring(0, line.length - 1);
    var position = 0;
    while (position < line.length) {
      final c = line[position];
      final decoded = c == '=' ? escapedByte(line, position) : null;
      if (decoded != null &&
          (decoded == 9 || decoded >= 32 && decoded <= 126)) {
        output.writeCharCode(decoded);
        position += 3;
      } else {
        output.write(c);
        error = error || c == '=';
        position++;
      }
    }
    if (!soft && i < lines.length - 1) output.write('\n');
  }
  return (output.toString(), error);
}
