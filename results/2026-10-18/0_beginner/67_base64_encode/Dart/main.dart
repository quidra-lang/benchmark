import 'dart:io';

void main() {
    final out = StringBuffer();
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    for (final s in ['Man', 'Hello, World!', '', '<b>bold</b>', 'a+b=c?']) {
        final encoded = StringBuffer();
        for (var i = 0; i < s.length; i += 3) {
            final remaining = s.length - i;
            final value = (s.codeUnitAt(i) << 16) | ((remaining > 1 ? s.codeUnitAt(i + 1) : 0) << 8) | (remaining > 2 ? s.codeUnitAt(i + 2) : 0);
            encoded.write(alphabet[(value >> 18) &63]);
            encoded.write(alphabet[(value >> 12) &63]);
            encoded.write(remaining > 1 ? alphabet[(value >> 6) &63] : '=');
            encoded.write(remaining > 2 ? alphabet[value &63] : '=');
        }
        out.writeln('"$s" -> "$encoded"');
    }
    stdout.write(out);
}
