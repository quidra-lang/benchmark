record DecodedText(String text, boolean error) {}
final class Mime {
    static final String ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    static int hex(char letter) { return letter >= '0' && letter <= '9' ? letter - '0' : letter >= 'A' && letter <= 'F' ? letter - 'A' + 10 : letter >= 'a' && letter <= 'f' ? letter - 'a' + 10 : -1; }
    static String strictBase64(String text) {
        if (text.length() % 4 != 0) return null;
        int end = text.length();
        while (end > 0 && text.charAt(end - 1) == '=') end--;
        if (text.length() - end >= 3) return null;
        StringBuilder result = new StringBuilder();
        int buffer = 0, bits = 0;
        for (int i = 0; i < end; i++) {
            int value = ALPHABET.indexOf(text.charAt(i));
            if (value < 0) return null;
            buffer = buffer << 6 | value; bits += 6;
            if (bits >= 8) { bits -= 8; result.append((char) (buffer >> bits)); buffer &= (1 << bits) - 1; }
        }
        return result.toString();
    }
    static String base64Body(String text) {
        String data = strictBase64(text.replace(" ", "").replace("\t", "").replace("\n", ""));
        if (data == null) return null;
        data = data.replace("\r\n", "\n");
        for (int i = 0; i < data.length(); i++) { char letter = data.charAt(i); if (letter != 9 && letter != 10 && (letter < 32 || letter > 126)) return null; }
        return data;
    }
    static DecodedText quotedPrintable(String text) {
        String[] lines = text.split("\n", -1); StringBuilder output = new StringBuilder(); boolean error = false;
        for (int i = 0; i < lines.length; i++) {
            String line = Headers.rstrip(lines[i]); boolean soft = line.endsWith("=");
            if (soft) line = line.substring(0, line.length() - 1);
            for (int position = 0; position < line.length();) {
                char letter = line.charAt(position); int value = -1;
                if (letter == '=' && position + 2 < line.length()) {
                    int first = hex(line.charAt(position + 1)), second = hex(line.charAt(position + 2));
                    if (first >= 0 && second >= 0) { int candidate = first * 16 + second; if (candidate == 9 || candidate >= 32 && candidate <= 126) value = candidate; }
                }
                if (value >= 0) { output.append((char) value); position += 3; }
                else { output.append(letter); error |= letter == '='; position++; }
            }
            if (!soft && i + 1 < lines.length) output.append('\n');
        }
        return new DecodedText(output.toString(), error);
    }
}
