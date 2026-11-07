using System.Text;

sealed record DecodedText(string Text, bool Error);
static class Mime {
    const string Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    public static int Hex(char letter) => letter >= '0' && letter <= '9' ? letter - '0' : letter >= 'A' && letter <= 'F' ? letter - 'A' + 10 : letter >= 'a' && letter <= 'f' ? letter - 'a' + 10 : -1;
    public static string StrictBase64(string text) {
        if (text.Length % 4 != 0) return null;
        int end = text.Length;
        while (end > 0 && text[end - 1] == '=') end--;
        if (text.Length - end >= 3) return null;
        StringBuilder result = new();
        int buffer = 0, bits = 0;
        for (int i = 0; i < end; i++) {
            int value = Alphabet.IndexOf(text[i]);
            if (value < 0) return null;
            buffer = buffer << 6 | value; bits += 6;
            if (bits >= 8) { bits -= 8; result.Append((char)(buffer >> bits)); buffer &= (1 << bits) - 1; }
        }
        return result.ToString();
    }
    public static string Base64Body(string text) {
        string data = StrictBase64(text.Replace(" ", "").Replace("\t", "").Replace("\n", ""));
        if (data == null) return null;
        data = data.Replace("\r\n", "\n");
        foreach (char letter in data) if (letter != 9 && letter != 10 && (letter < 32 || letter > 126)) return null;
        return data;
    }
    public static DecodedText QuotedPrintable(string text) {
        string[] lines = text.Split('\n');
        StringBuilder output = new();
        bool error = false;
        for (int i = 0; i < lines.Length; i++) {
            string line = Headers.Rstrip(lines[i]);
            bool soft = line.EndsWith('=');
            if (soft) line = line[..^1];
            for (int position = 0; position < line.Length;) {
                char letter = line[position];
                int value = -1;
                if (letter == '=' && position + 2 < line.Length) {
                    int first = Hex(line[position + 1]), second = Hex(line[position + 2]);
                    if (first >= 0 && second >= 0) { int candidate = first * 16 + second; if (candidate == 9 || candidate >= 32 && candidate <= 126) value = candidate; }
                }
                if (value >= 0) { output.Append((char)value); position += 3; }
                else { output.Append(letter); error |= letter == '='; position++; }
            }
            if (!soft && i + 1 < lines.Length) output.Append('\n');
        }
        return new DecodedText(output.ToString(), error);
    }
}
