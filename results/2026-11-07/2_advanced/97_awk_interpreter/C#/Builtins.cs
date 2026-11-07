sealed class RuntimeError(Position position, string message) : Exception(message) {
    public Position Position {
        get;
    } = position;
}
static class Builtins {
    public static string Format(List<Value> values, Position position) {
        string format = values[0].String;
        StringBuilder output = new();
        int i = 0, argument = 1;
        RuntimeError Error(string message) => new(position, message);
        while (i < format.Length) {
            if (format[i] != '%') {
                output.Append(format[i++]);
                continue;
            } i++;
            if (i < format.Length && format[i] == '%') {
                output.Append('%');
                i++;
                continue;
            }
            bool left = false, zero = false;
            while (i < format.Length && format[i] is '-' or '0') {
                left |= format[i] == '-';
                zero |= format[i] == '0';
                i++;
            }
            int start = i;
            while (i < format.Length && Lexer.Digit(format[i])) i++;
            int width = start == i ? 0 : int.Parse(format[start..i]);
            int? precision = null;
            if (i < format.Length && format[i] == '.') {
                i++;
                int begin = i;
                while (i < format.Length && Lexer.Digit(format[i])) i++;
                precision = begin == i ? 0 : int.Parse(format[begin..i]);
            }
            if (i == format.Length || !"discxo".Contains(format[i])) throw Error("invalid format");
            char conversion = format[i++];
            if (argument == values.Count) throw Error("not enough arguments");
            Value value = values[argument++];
            bool numeric = "dixo".Contains(conversion);
            string body;
            if (numeric) {
                int n = value.NumberValue;
                string digits = Convert.ToString(Math.Abs(n), conversion == 'x' ? 16 : conversion == 'o' ? 8 : 10);
                if (precision.HasValue) digits = precision.Value == 0 && n == 0 ? "" : digits.PadLeft(precision.Value, '0');
                body = (n < 0 ? "-" : "") + digits;
            } else if (conversion == 's') body = precision.HasValue ? value.String[..Math.Min(value.String.Length, precision.Value)] : value.String;
            else if (value.NumericKind) {
                int code = value.NumberValue;
                if (code != 10 && (code < 32 || code > 126)) throw Error("invalid character code");
                body = ((char)code).ToString();
            }
            else body = value.String.Length == 0 ? "" : value.String[..1];
            if (body.Length < width) {
                int padding = width - body.Length;
                body = left ? body + new string(' ', padding) : numeric && zero && !precision.HasValue ? body.StartsWith('-') ? "-" + new string('0', padding) + body[1..] : new string('0', padding) + body : new string(' ', padding) + body;
            }
            output.Append(body);
        }
        return output.ToString();
    }
    public static Value Scalar(string name, List<Value> values, Position position) {
        switch (name) {
            case "substr": {
                string text = values[0].String;
                int original = values[1].NumberValue, start = Math.Max(1, original), end = Math.Min(text.Length + 1, values.Count == 3 ? original + values[2].NumberValue : text.Length + 1);
                return Value.Text(end > start ? text.Substring(start - 1, end - start) : "");
            }
            case "index": {
                string target = values[1].String;
                return Value.Number(target.Length == 0 ? 0 : values[0].String.IndexOf(target, StringComparison.Ordinal) + 1);
            }
            case "toupper": return Value.Text(new(values[0].String.Select(c => c >= 'a' && c <= 'z' ? (char)(c - 32) : c).ToArray()));
            case "tolower": return Value.Text(new(values[0].String.Select(c => c >= 'A' && c <= 'Z' ? (char)(c + 32) : c).ToArray()));
            case "int": return Value.Number(values[0].NumberValue);
            default: return Value.Text(Format(values, position));
        }
    }
}
