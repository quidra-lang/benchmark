using System;
using System.Collections.Generic;
using System.Text;
public static class Protocol {
    public const string SPECIAL = "[]\\`_^{}|";
    public record Message(string command, List<string> parameters);
    public static string Fold(string value) {
        StringBuilder result = new();
        foreach (char c in value)
            result.Append(c >= 'A' && c <= 'Z'
                              ? (char)(c + 32)
                              : c switch { '[' => '{', ']' => '}', '\\' => '|', '^' => '~',
                                           _ => c });
        return result.ToString();
    }
    public static bool Letter(char c) => c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z';
    public static bool Digits(string value) {
        if (value.Length == 0)
            return false;
        foreach (char c in value)
            if (c < '0' || c > '9')
                return false;
        return true;
    }
    public static bool ValidNickname(string value) {
        if (value.Length == 0 || !Letter(value[0]) && SPECIAL.IndexOf(value[0]) < 0)
            return false;
        for (int i = 1; i < value.Length; i++) {
            char c = value[i];
            if (!Letter(c) && SPECIAL.IndexOf(c) < 0 && !(c >= '0' && c <= '9') && c != '-')
                return false;
        }
        return true;
    }
    public static bool ValidChannel(string value,
                                    int maximum) => value.Length >= 2 && value.Length <= maximum
                                                    && value.StartsWith('#') &&
                                                    !value.Contains(':');
    public static Message Parse(string raw) {
        int position = 0;
        if (raw.StartsWith(':')) {
            position = raw.IndexOf(' ');
            if (position < 0)
                return new("", new());
        }
        while (position < raw.Length && raw[position] == ' ')
            position++;
        int start = position;
        while (position < raw.Length && raw[position] != ' ')
            position++;
        string command = raw[start..position].ToUpperInvariant();
        List<string> parameters = new();
        while (position < raw.Length) {
            while (position < raw.Length && raw[position] == ' ')
                position++;
            if (position == raw.Length)
                break;
            if (raw[position] == ':') {
                parameters.Add(raw[(position + 1)..]);
                break;
            }
            if (parameters.Count == 14) {
                parameters.Add(raw[position..]);
                break;
            }
            start = position;
            while (position < raw.Length && raw[position] != ' ')
                position++;
            parameters.Add(raw[start..position]);
        }
        return new(command, parameters);
    }
}
