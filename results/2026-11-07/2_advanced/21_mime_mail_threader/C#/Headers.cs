using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

sealed record SourceLine(int Number, string Text);
sealed record Field(string Name, string Value);
sealed record Token(string Kind, string Text, bool Spaced);
sealed record DecodedWord(string Text, bool Decoded, bool Error);
sealed record Parameters(string Type, string Subtype, Dictionary<string, string> Values);
sealed class Header {
    public readonly List<Field> Fields = new();
    public readonly List<int> Invalid = new();
    public string Value(string name) => Fields.FirstOrDefault(field => field.Name == name.ToLowerInvariant())?.Value;
    public int Count(string name) => Fields.Count(field => field.Name == name.ToLowerInvariant());
}
static class Headers {
    const string AddressSpecials = "<>:;@,.", AddressWords = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$%&'*+-/=?^_`{|}~";
    const string MimeSpecials = "/;=", MimeExcluded = "()<>@,;:\\\"/[]?=";
    public static bool Whitespace(char letter) => letter == ' ' || letter == '\t';
    public static string Rstrip(string text) => text.TrimEnd(' ', '\t');
    public static string Strip(string text) => text.Trim(' ', '\t');
    public static List<string> Words(string text) => text.Split([' ', '\t'], StringSplitOptions.RemoveEmptyEntries).ToList();
    public static string Collapse(string text) => string.Join(" ", Words(text));
    public static Header ParseFields(List<SourceLine> lines) {
        Header header = new();
        List<string> names = new(), values = new();
        bool inField = false;
        foreach (SourceLine line in lines) {
            string text = line.Text;
            if (Whitespace(text[0])) {
                if (inField) values[^1] += text; else header.Invalid.Add(line.Number);
                continue;
            }
            int split = text.IndexOf(':');
            string name = split < 0 ? "" : text[..split];
            inField = name.Length > 0 && name.All(letter => letter >= 33 && letter <= 126);
            if (inField) { names.Add(name.ToLowerInvariant()); values.Add(text[(split + 1)..]); }
            else header.Invalid.Add(line.Number);
        }
        for (int i = 0; i < names.Count; i++) header.Fields.Add(new Field(names[i], Strip(values[i])));
        return header;
    }
    public static string RemoveComments(string text) {
        StringBuilder result = new();
        int depth = 0;
        for (int i = 0; i < text.Length; i++) {
            char letter = text[i];
            if (depth == 0) { if (letter == '(') { depth = 1; result.Append(' '); } else result.Append(letter); }
            else if (letter == '\\') i++;
            else if (letter == '(') depth++;
            else if (letter == ')') depth--;
        }
        return depth == 0 ? result.ToString() : null;
    }
    public static List<Token> Tokenize(string text, bool mime) {
        List<Token> tokens = new();
        int position = 0;
        bool spaced = false;
        string specials = mime ? MimeSpecials : AddressSpecials;
        while (position < text.Length) {
            char letter = text[position];
            if (Whitespace(letter)) { spaced = true; position++; continue; }
            if (letter == '(') {
                int depth = 1; position++;
                while (position < text.Length && depth > 0) {
                    char next = text[position++];
                    if (next == '\\') position++;
                    else if (next == '(') depth++;
                    else if (next == ')') depth--;
                }
                if (depth != 0) return null;
                spaced = true;
                continue;
            }
            if (letter == '"') {
                position++;
                StringBuilder value = new();
                bool closed = false;
                while (position < text.Length) {
                    char next = text[position++];
                    if (next == '"') { closed = true; break; }
                    if (next == '\\') { if (position == text.Length) return null; next = text[position++]; }
                    value.Append(next);
                }
                if (!closed) return null;
                tokens.Add(new Token("quoted", value.ToString(), spaced));
            } else if (specials.Contains(letter)) { tokens.Add(new Token(letter.ToString(), letter.ToString(), spaced)); position++; }
            else if (WordCharacter(letter, mime)) {
                int start = position;
                while (position < text.Length && WordCharacter(text[position], mime)) position++;
                tokens.Add(new Token("word", text[start..position], spaced));
            } else return null;
            spaced = false;
        }
        return tokens;
    }
    static bool WordCharacter(char letter, bool mime) => mime ? letter >= 33 && letter <= 126 && !MimeExcluded.Contains(letter) : AddressWords.Contains(letter);
    static string DecodeQ(string text) {
        StringBuilder result = new();
        for (int i = 0; i < text.Length; i++) {
            char letter = text[i];
            if (letter == '_') result.Append(' ');
            else if (letter == '=') {
                if (i + 2 >= text.Length) return null;
                int first = Mime.Hex(text[i + 1]), second = Mime.Hex(text[i + 2]);
                if (first < 0 || second < 0) return null;
                result.Append((char)(first * 16 + second)); i += 2;
            } else result.Append(letter);
        }
        return result.ToString();
    }
    public static DecodedWord DecodeWord(string word) {
        if (word.Length < 4 || !word.StartsWith("=?", StringComparison.Ordinal) || !word.EndsWith("?=", StringComparison.Ordinal)) return new DecodedWord(word, false, false);
        string[] parts = word[2..^2].Split('?');
        if (parts.Length != 3 || parts.Any(part => part.Length == 0)) return new DecodedWord(word, false, false);
        string decoded = null;
        if (parts[0].ToLowerInvariant() == "us-ascii") {
            if (parts[1] is "Q" or "q") decoded = DecodeQ(parts[2]);
            else if (parts[1] is "B" or "b") decoded = Mime.StrictBase64(parts[2]);
        }
        if (decoded == null || !decoded.All(letter => letter >= 32 && letter <= 126)) return new DecodedWord(word, false, true);
        return new DecodedWord(decoded, true, false);
    }
    public static DecodedText Unstructured(string value) {
        StringBuilder text = new();
        bool previous = false, error = false, first = true;
        foreach (string word in Words(value)) {
            DecodedWord decoded = DecodeWord(word);
            if (!first && !(previous && decoded.Decoded)) text.Append(' ');
            text.Append(decoded.Text); previous = decoded.Decoded; error |= decoded.Error; first = false;
        }
        return new DecodedText(Collapse(text.ToString()), error);
    }
    public static Parameters ParseParameters(string value, bool withSubtype) {
        List<Token> tokens = Tokenize(value, true);
        if (tokens == null || tokens.Count == 0 || tokens[0].Kind != "word") return null;
        string type = tokens[0].Text.ToLowerInvariant(), subtype = "";
        int position = 1;
        if (withSubtype) {
            if (tokens.Count < 3 || tokens[1].Kind != "/" || tokens[2].Kind != "word") return null;
            subtype = tokens[2].Text.ToLowerInvariant(); position = 3;
        }
        Dictionary<string, string> values = new(StringComparer.Ordinal);
        while (position < tokens.Count) {
            if (position + 3 >= tokens.Count || tokens[position].Kind != ";" || tokens[position + 1].Kind != "word" || tokens[position + 2].Kind != "=" || tokens[position + 3].Kind is not ("word" or "quoted")) return null;
            values.TryAdd(tokens[position + 1].Text.ToLowerInvariant(), tokens[position + 3].Text);
            position += 4;
        }
        return new Parameters(type, subtype, values);
    }
}
