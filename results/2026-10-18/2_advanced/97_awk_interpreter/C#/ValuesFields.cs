enum ValueKind {
    Number, Text, Numeric, Uninitialized
}
sealed record Value(ValueKind Kind, int NumericValue = 0, string StringValue = "") {
    public static readonly Value Uninitialized = new(ValueKind.Uninitialized);
    public static Value Number(int value) => new(ValueKind.Number, value);
    public static Value Text(string value) => new(ValueKind.Text, 0, value);
    public static bool Whitespace(char c) => c is ' ' or (char)9 or (char)10;
    public static Value Input(string text) {
        string raw = text.Trim(' ', (char)9, (char)10);
        string digits = raw.StartsWith('+') || raw.StartsWith('-') ? raw[1..] : raw;
        return digits.Length > 0 && digits.All(Lexer.Digit) ? new(ValueKind.Numeric, Text(text).NumberValue, text) : Text(text);
    }
    public int NumberValue {
        get {
            if (Kind is ValueKind.Number or ValueKind.Numeric) return NumericValue;
            if (Kind == ValueKind.Uninitialized) return 0;
            int i = 0;
            while (i < StringValue.Length && Whitespace(StringValue[i])) i++;
            bool negative = i < StringValue.Length && StringValue[i] == '-';
            if (i < StringValue.Length && StringValue[i] is '+' or '-') i++;
            int n = 0;
            while (i < StringValue.Length && Lexer.Digit(StringValue[i])) n = n * 10 + StringValue[i++] - '0';
            return negative ? -n : n;
        }
    }
    public string String => Kind == ValueKind.Number ? NumericValue.ToString() : Kind == ValueKind.Uninitialized ? "" : StringValue;
    public bool Truth => Kind == ValueKind.Text ? StringValue.Length > 0 : NumberValue != 0;
    public bool NumberLike => Kind != ValueKind.Text;
    public bool NumericKind => Kind is ValueKind.Number or ValueKind.Numeric;
    public int Compare(Value other) => NumberLike && other.NumberLike ? NumberValue.CompareTo(other.NumberValue) : string.CompareOrdinal(String, other.String);
    public string Display => Kind switch {
        ValueKind.Number => NumericValue.ToString(), ValueKind.Text => ValuesFields.Quote(StringValue), ValueKind.Numeric => ValuesFields.Quote(StringValue) + " (strnum)", _ => "(uninitialized)"
    };
}
static class ValuesFields {
    public static string Quote(string text) {
        StringBuilder result = new();
        result.Append((char)34);
        foreach (char c in text) {
            switch ((int)c) {
                case 34: case 92: result.Append((char)92).Append(c);
                break;
                case 10: result.Append((char)92).Append('n');
                break;
                case 9: result.Append((char)92).Append('t');
                break;
                case >= 32 and <= 126: result.Append(c);
                break;
                default: result.Append((char)92).Append(Convert.ToString(c, 8).PadLeft(3, '0'));
                break;
            }
        }
        return result.Append((char)34).ToString();
    }
    public static List<string> Split(string text, string separator) {
        if (separator == " ") {
            List<string> pieces = new();
            int i = 0;
            while (i < text.Length) {
                while (i < text.Length && Value.Whitespace(text[i])) i++;
                int start = i;
                while (i < text.Length && !Value.Whitespace(text[i])) i++;
                if (i > start) pieces.Add(text[start..i]);
            } return pieces;
        }
        if (separator.Length == 0) return text.Select(c => c.ToString()).ToList();
        return text.Length == 0 ? new() : text.Split(separator, StringSplitOptions.None).ToList();
    }
    static int? IntegerKey(string text) {
        if (text == "0") return 0;
        string digits = text.StartsWith('-') ? text[1..] : text;
        if (digits.Length == 0 || digits[0] < '1' || digits[0] > '9' || !digits.All(Lexer.Digit)) return null;
        return int.Parse(text);
    }
    public static int CompareKeys(string a, string b) {
        int? x = IntegerKey(a), y = IntegerKey(b);
        return x.HasValue && y.HasValue ? x.Value.CompareTo(y.Value) : x.HasValue ? -1 : y.HasValue ? 1 : string.CompareOrdinal(a, b);
    }
}
sealed class Fields {
    public Value Record = Value.Text("");
    public List<Value> Values = new();
    public void Set(string text, string separator) {
        Record = Value.Input(text);
        Values = ValuesFields.Split(text, separator).Select(Value.Input).ToList();
    }
    public Value Get(int index) => index == 0 ? Record : index <= Values.Count ? Values[index - 1] : Value.Uninitialized;
    void Rebuild(string separator) {
        Record = Value.Input(string.Join(separator, Values.Select(value => value.String)));
    }
    public void Assign(int index, Value value, string fs, string ofs) {
        if (index == 0) Set(value.String, fs);
        else {
            while (Values.Count < index) Values.Add(Value.Text(""));
            Values[index - 1] = value;
            Rebuild(ofs);
        }
    }
    public void Nf(int size, string ofs) {
        if (size < Values.Count) Values.RemoveRange(size, Values.Count - size);
        while (Values.Count < size) Values.Add(Value.Text(""));
        Rebuild(ofs);
    }
}
