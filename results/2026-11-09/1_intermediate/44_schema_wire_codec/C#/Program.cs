using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

enum Kind { UInt32, UInt64, SInt32, SInt64, Bool, Fixed32, SFixed32, Fixed64, String, Bytes, Enum, Message }

sealed class SchemaType(string name, Kind kind)
{
    public string Name { get; } = name;
    public Kind Kind { get; } = kind;
    public List<Field> Fields { get; } = [];
    public SortedDictionary<long, string> Numbers { get; } = [];
    public Dictionary<string, long> Names { get; } = new(StringComparer.Ordinal);
    public int Wire => Kind switch {
        Kind.Fixed64 => 1, Kind.String or Kind.Bytes or Kind.Message => 2,
        Kind.Fixed32 or Kind.SFixed32 => 5, _ => 0
    };
    public bool Packable => Wire != 2;
    public Field? Find(string name) => Fields.Find(field => field.Name == name);
    public Field? Find(long number) => Fields.Find(field => field.Number == number);
}

sealed class Field(long number, string typeName, string name, bool required, bool repeated, bool packed, string? group)
{
    public long Number { get; } = number;
    public string TypeName { get; } = typeName;
    public string Name { get; } = name;
    public bool Required { get; } = required;
    public bool Repeated { get; } = repeated;
    public bool Packed { get; } = packed;
    public string? Group { get; } = group;
    public SchemaType Type { get; set; } = null!;
}

abstract record Value;
sealed record NumberValue(long Number) : Value;
sealed record BooleanValue(bool State) : Value;
sealed record BinaryValue(byte[] Bytes) : Value;
sealed record Unknown(long Number, int Wire, long Integer, byte[] Bytes);
sealed record Message(SchemaType Type) : Value
{
    public Dictionary<Field, List<Value>> Fields { get; } = [];
    public List<Unknown> Unknown { get; } = [];
    public List<Value> Values(Field field) => Fields.GetValueOrDefault(field) ?? [];
    public void Choose(Field field)
    {
        if (field.Group is null) return;
        foreach (Field other in Type.Fields)
            if (other != field && other.Group == field.Group) Fields.Remove(other);
    }
    public void Apply(Field field, List<Value> values)
    {
        if (values.Count == 0) return;
        Choose(field);
        if (field.Repeated) {
            if (!Fields.TryGetValue(field, out List<Value>? old)) Fields[field] = old = [];
            old.AddRange(values);
        } else if (field.Type.Kind == Kind.Message && Fields.TryGetValue(field, out List<Value>? old)) {
            ((Message)old[0]).Merge((Message)values[0]);
        } else Fields[field] = values;
    }
    public void Merge(Message source)
    {
        foreach (Field field in Type.Fields) Apply(field, source.Values(field));
        Unknown.AddRange(source.Unknown);
    }
}

sealed class CodecError(string message) : Exception(message);

static class Format
{
    public static string Hex(byte[] bytes) => bytes.Length == 0 ? "-" : Convert.ToHexString(bytes).ToLowerInvariant();
    public static string Bytes(byte[] bytes) => "<" + Convert.ToHexString(bytes).ToLowerInvariant() + ">";
    public static string Wire(int wire) => wire switch { 0 => "varint", 1 => "i64", 2 => "len", _ => "i32" };
    public static string Raw(Unknown value) => value.Wire == 0 ? value.Integer.ToString() : Bytes(value.Bytes);
    public static string Quote(byte[] bytes, bool json)
    {
        StringBuilder result = new("\"");
        foreach (byte value in bytes)
            result.Append(value switch {
                34 => "\\\"", 92 => "\\\\", 10 => "\\n", 9 => "\\t",
                >= 32 and <= 126 => ((char)value).ToString(),
                _ => (json ? "\\u00" : "\\x") + value.ToString("x2")
            });
        return result.Append('"').ToString();
    }
    public static string Value(SchemaType type, Value value, bool json = false) => value switch {
        NumberValue number when type.Kind == Kind.Enum =>
            json ? "\"" + type.Numbers[number.Number] + "\"" : type.Numbers[number.Number],
        NumberValue number when json && type.Kind is Kind.UInt64 or Kind.SInt64 or Kind.Fixed64 =>
            "\"" + number.Number + "\"",
        NumberValue number => number.Number.ToString(),
        BooleanValue boolean => boolean.State ? "true" : "false",
        BinaryValue binary when type.Kind == Kind.String => Quote(binary.Bytes, json),
        BinaryValue binary => json ? "\"" + Convert.ToBase64String(binary.Bytes) + "\"" : Bytes(binary.Bytes),
        Message message => Message(message, json),
        _ => throw new InvalidOperationException()
    };
    public static string Sequence(SchemaType type, IEnumerable<Value> values, bool json = false) =>
        "[" + string.Join(json ? "," : ", ", values.Select(value => Value(type, value, json))) + "]";
    static string JsonName(string name) => Regex.Replace(name, "_([a-z0-9])", match => match.Groups[1].Value.ToUpperInvariant());
    public static string Message(Message message, bool json = false)
    {
        List<string> items = [];
        foreach (Field field in message.Type.Fields) {
            List<Value> values = message.Values(field);
            if (values.Count == 0) continue;
            string key = json ? "\"" + JsonName(field.Name) + "\":" : field.Name + ": ";
            items.Add(key + (field.Repeated ? Sequence(field.Type, values, json) : Value(field.Type, values[0], json)));
        }
        return "{" + string.Join(json ? "," : ", ", items) + "}";
    }
    public static List<string> Text(Message message)
    {
        List<string> lines = [message.Type.Name + " {"];
        Contents(message, 1, lines);
        lines.Add("}");
        return lines;
    }
    static void Contents(Message message, int depth, List<string> lines)
    {
        string indent = new(' ', depth * 2);
        foreach (Field field in message.Type.Fields)
            foreach (Value value in message.Values(field))
                if (value is Message child) {
                    lines.Add(indent + field.Name + " {");
                    Contents(child, depth + 1, lines);
                    lines.Add(indent + "}");
                } else lines.Add(indent + field.Name + ": " + Value(field.Type, value));
        foreach (Unknown unknown in message.Unknown)
            lines.Add(indent + unknown.Number + ": " + Wire(unknown.Wire) + " " + Raw(unknown));
    }
}

static class Codec
{
    public const long MaxUnsigned = 9007199254740991;
    public static long Zigzag(long value) => value >= 0 ? 2 * value : -2 * value - 1;
    public static long Unzigzag(long value) => value % 2 == 0 ? value / 2 : -1 - value / 2;
    public static bool InRange(SchemaType type, long value) => type.Kind switch {
        Kind.UInt32 or Kind.Fixed32 => value is >= 0 and <= 4294967295,
        Kind.UInt64 or Kind.Fixed64 => value is >= 0 and <= MaxUnsigned,
        Kind.SInt32 or Kind.SFixed32 => value is >= -2147483648 and <= 2147483647,
        Kind.SInt64 => value is >= -4503599627370496 and <= 4503599627370495,
        _ => true
    };
    public static void Varint(List<byte> output, long value)
    {
        while (value >= 128) {
            output.Add((byte)(value % 128 + 128));
            value /= 128;
        }
        output.Add((byte)value);
    }
    static void Element(List<byte> output, SchemaType type, Value value)
    {
        if (value is Message message) {
            byte[] payload = Encode(message);
            Varint(output, payload.Length);
            output.AddRange(payload);
        } else if (value is BinaryValue binary) {
            Varint(output, binary.Bytes.Length);
            output.AddRange(binary.Bytes);
        } else {
            long number = value is BooleanValue boolean ? (boolean.State ? 1 : 0) : ((NumberValue)value).Number;
            if (type.Kind is Kind.SInt32 or Kind.SInt64) number = Zigzag(number);
            if (type.Kind == Kind.SFixed32 && number < 0) number += 4294967296;
            if (type.Wire == 0) Varint(output, number);
            else for (int i = 0; i < (type.Wire == 1 ? 8 : 4); i++) {
                output.Add((byte)(number % 256));
                number /= 256;
            }
        }
    }
    public static byte[] FieldBytes(Field field, List<Value> values)
    {
        List<byte> output = [];
        if (values.Count == 0) return [];
        if (field.Packed) {
            List<byte> payload = [];
            foreach (Value value in values) Element(payload, field.Type, value);
            Varint(output, field.Number * 8 + 2);
            Varint(output, payload.Count);
            output.AddRange(payload);
        } else foreach (Value value in values) {
            Varint(output, field.Number * 8 + field.Type.Wire);
            Element(output, field.Type, value);
        }
        return output.ToArray();
    }
    public static byte[] Encode(Message message)
    {
        List<byte> output = [];
        foreach (Field field in message.Type.Fields) output.AddRange(FieldBytes(field, message.Values(field)));
        foreach (Unknown unknown in message.Unknown) {
            Varint(output, unknown.Number * 8 + unknown.Wire);
            if (unknown.Wire == 0) Varint(output, unknown.Integer);
            else {
                if (unknown.Wire == 2) Varint(output, unknown.Bytes.Length);
                output.AddRange(unknown.Bytes);
            }
        }
        return output.ToArray();
    }
    public static void Required(Message message, string prefix = "")
    {
        foreach (Field field in message.Type.Fields) {
            List<Value> values = message.Values(field);
            string path = prefix + field.Name;
            if (field.Required && values.Count == 0) throw new CodecError("missing required field " + path);
            if (field.Type.Kind == Kind.Message)
                for (int i = 0; i < values.Count; i++)
                    Required((Message)values[i], path + (field.Repeated ? "[" + i + "]" : "") + ".");
        }
    }
}

readonly record struct Raw(long Number, byte[] Bytes, int Position, int Payload);

sealed class Decoder(byte[] data, bool explain = false)
{
    public List<string> Lines { get; } = [];
    static CodecError Error(string reason, int offset) => new(reason + " at byte " + offset);
    long Varint(ref int position, int end)
    {
        int start = position;
        long value = 0;
        for (int i = 0; i < 8; i++) {
            if (position == end) throw Error("truncated varint", start);
            byte current = data[position++];
            value += (long)(current & 127) << (7 * i);
            if (current < 128) {
                if (value > Codec.MaxUnsigned) throw Error("varint too large", start);
                return value;
            }
        }
        throw Error("varint too long", start);
    }
    Raw Read(int wire, ref int position, int end)
    {
        int start = position;
        if (wire == 0) return new Raw(Varint(ref position, end), [], start, start);
        long length = wire == 2 ? Varint(ref position, end) : wire == 1 ? 8 : 4;
        if (length > end - position)
            throw Error(wire == 2 ? "length past end" : wire == 1 ? "truncated i64" : "truncated i32", start);
        int payload = position;
        position += (int)length;
        return new Raw(0, data[payload..position], start, payload);
    }
    Value ConvertValue(SchemaType type, Raw raw)
    {
        if (type.Kind == Kind.String) {
            for (int i = 0; i < raw.Bytes.Length; i++)
                if (raw.Bytes[i] >= 128) throw Error("invalid string", raw.Payload + i);
            return new BinaryValue(raw.Bytes);
        }
        if (type.Kind == Kind.Bytes) return new BinaryValue(raw.Bytes);
        long number = raw.Number;
        if (type.Wire is 1 or 5) {
            if (type.Kind == Kind.Fixed64 && (raw.Bytes[7] != 0 || raw.Bytes[6] >= 32))
                throw Error("value out of range", raw.Position);
            number = 0;
            for (int i = raw.Bytes.Length - 1; i >= 0; i--) number = number * 256 + raw.Bytes[i];
        }
        if (type.Kind is Kind.SInt32 or Kind.SInt64) number = Codec.Unzigzag(number);
        if (type.Kind == Kind.SFixed32 && number >= 2147483648) number -= 4294967296;
        if (!Codec.InRange(type, number)) throw Error("value out of range", raw.Position);
        if (type.Kind == Kind.Bool) {
            if (number > 1) throw Error("value out of range", raw.Position);
            return new BooleanValue(number == 1);
        }
        if (type.Kind == Kind.Enum && !type.Numbers.ContainsKey(number)) throw Error("unknown enum number", raw.Position);
        return new NumberValue(number);
    }
    Message ReadMessage(SchemaType type, int start, int end, int depth)
    {
        Message message = new(type);
        int position = start;
        while (position < end) {
            int offset = position;
            long tag = Varint(ref position, end), number = tag / 8;
            int wire = (int)(tag % 8);
            if (number == 0) throw Error("invalid field number", offset);
            if (wire is not (0 or 1 or 2 or 5)) throw Error("invalid wire type", offset);
            Field? field = type.Find(number);
            bool packed = field is not null && field.Repeated && field.Type.Packable && wire == 2;
            if (field is not null && wire != field.Type.Wire && !packed) throw Error("wire type mismatch", offset);
            Raw raw = Read(wire, ref position, end);
            string header = new string(' ', depth * 2) + offset + " " + number + " " +
                (field?.Name ?? "?") + " " + Format.Wire(wire) + (wire == 2 ? " " + raw.Bytes.Length : "");
            if (field is null) {
                Unknown unknown = new(number, wire, raw.Number, raw.Bytes);
                if (explain) Lines.Add(header + " " + Format.Raw(unknown));
                else message.Unknown.Add(unknown);
                continue;
            }
            List<Value> values = [];
            if (field.Type.Kind == Kind.Message) {
                if (explain) Lines.Add(header);
                values.Add(ReadMessage(field.Type, raw.Payload, raw.Payload + raw.Bytes.Length, depth + 1));
            } else if (packed) {
                int at = raw.Payload, limit = at + raw.Bytes.Length;
                while (at < limit) values.Add(ConvertValue(field.Type, Read(field.Type.Wire, ref at, limit)));
                if (explain) Lines.Add(header + " packed" + string.Concat(values.Select(value => " " + Format.Value(field.Type, value))));
            } else {
                values.Add(ConvertValue(field.Type, raw));
                if (explain) Lines.Add(header + " " + Format.Value(field.Type, values[0]));
            }
            if (!explain) message.Apply(field, values);
        }
        return message;
    }
    public Message Decode(SchemaType type)
    {
        Message message = ReadMessage(type, 0, data.Length, 0);
        if (explain) { if (Lines.Count == 0) Lines.Add("(empty)"); }
        else Codec.Required(message);
        return message;
    }
}

enum TokenKind { Symbol, Integer, Name, String, Bytes, End }
enum Shape { None, Message, List, Integer, Boolean, Name, String, Bytes }
readonly record struct Token(TokenKind Kind, string Text, int Column, long Number = 0, byte[]? Data = null)
{
    public Shape Shape => Kind switch {
        TokenKind.Integer => Shape.Integer, TokenKind.String => Shape.String, TokenKind.Bytes => Shape.Bytes,
        TokenKind.Name => Text is "true" or "false" ? Shape.Boolean : Shape.Name,
        TokenKind.Symbol when Text == "{" => Shape.Message,
        TokenKind.Symbol when Text == "[" => Shape.List, _ => Shape.None
    };
}

sealed class Literal
{
    readonly List<Token> tokens = [];
    int position;
    Token Next => tokens[position];
    static bool Letter(char value) => value is >= 'a' and <= 'z' or >= 'A' and <= 'Z';
    static bool Digit(char value) => value is >= '0' and <= '9';
    static int HexDigit(char value) => value is >= '0' and <= '9' ? value - '0' :
        value is >= 'a' and <= 'f' ? value - 'a' + 10 : -1;
    static CodecError Error(string reason, Token token) => new(reason + " at column " + token.Column);
    public Literal(string text)
    {
        int at = 0;
        while (at < text.Length) {
            char value = text[at];
            if (value == ' ') { at++; continue; }
            int start = at++;
            Token token = new(TokenKind.Symbol, value.ToString(), start + 1);
            if ("{}[]:,".Contains(value)) tokens.Add(token);
            else if (value == '"') {
                List<byte> bytes = [];
                bool closed = false;
                while (at < text.Length) {
                    char current = text[at++];
                    if (current == '"') { closed = true; break; }
                    if (current != '\\') { bytes.Add((byte)current); continue; }
                    if (at == text.Length) throw Error("syntax error", token);
                    char escaped = text[at++];
                    if (escaped is '"' or '\\') bytes.Add((byte)escaped);
                    else if (escaped == 'n') bytes.Add(10);
                    else if (escaped == 't') bytes.Add(9);
                    else if (escaped == 'x') {
                        if (at + 2 > text.Length) throw Error("syntax error", token);
                        int high = HexDigit(text[at]), low = HexDigit(text[at + 1]);
                        if (high is < 0 or > 7 || low < 0) throw Error("syntax error", token);
                        bytes.Add((byte)(high * 16 + low));
                        at += 2;
                    } else throw Error("syntax error", token);
                }
                if (!closed) throw Error("syntax error", token);
                tokens.Add(new(TokenKind.String, "", start + 1, Data: bytes.ToArray()));
            } else if (value == '<') {
                int end = text.IndexOf('>', at);
                if (end < 0) throw Error("syntax error", token);
                string digits = text[at..end];
                if (digits.Length % 2 != 0 || digits.Any(character => HexDigit(character) < 0)) throw Error("syntax error", token);
                tokens.Add(new(TokenKind.Bytes, "", start + 1, Data: Convert.FromHexString(digits)));
                at = end + 1;
            } else if (value == '-' || Digit(value)) {
                if (value == '-' && (at == text.Length || !Digit(text[at]))) throw Error("syntax error", token);
                while (at < text.Length && Digit(text[at])) at++;
                tokens.Add(new(TokenKind.Integer, "", start + 1, long.Parse(text[start..at])));
            } else if (Letter(value) || value == '_') {
                while (at < text.Length && (Letter(text[at]) || Digit(text[at]) || text[at] == '_')) at++;
                tokens.Add(new(TokenKind.Name, text[start..at], start + 1));
            } else throw Error("syntax error", token);
        }
        tokens.Add(new(TokenKind.End, "", text.Length + 1));
    }
    bool Is(string symbol) => Next.Kind == TokenKind.Symbol && Next.Text == symbol;
    void Expect(string symbol)
    {
        if (!Is(symbol)) throw Error("syntax error", Next);
        position++;
    }
    public void End()
    {
        if (Next.Kind != TokenKind.End) throw Error("syntax error", Next);
    }
    public Message Message(SchemaType type)
    {
        Expect("{");
        Message message = new(type);
        HashSet<Field> seen = [];
        HashSet<string> groups = new(StringComparer.Ordinal);
        if (!Is("}")) while (true) {
            Token name = Next;
            if (name.Kind != TokenKind.Name) throw Error("syntax error", name);
            Field field = type.Find(name.Text) ?? throw Error("unknown field", name);
            if (!seen.Add(field)) throw Error("duplicate field", name);
            if (field.Group is not null && !groups.Add(field.Group)) throw Error("oneof conflict", name);
            position++;
            Expect(":");
            message.Fields[field] = FieldValue(field);
            if (!Is(",")) break;
            position++;
        }
        Token closing = Next;
        Expect("}");
        foreach (Field field in type.Fields)
            if (field.Required && !seen.Contains(field)) throw Error("missing required field " + field.Name, closing);
        return message;
    }
    void Require(Shape shape)
    {
        if (Next.Shape == Shape.None) throw Error("syntax error", Next);
        if (Next.Shape != shape) throw Error("type mismatch", Next);
    }
    public List<Value> FieldValue(Field field)
    {
        if (!field.Repeated) return [Element(field.Type)];
        Require(Shape.List);
        Expect("[");
        List<Value> values = [];
        if (!Is("]")) {
            values.Add(Element(field.Type));
            while (Is(",")) { position++; values.Add(Element(field.Type)); }
        }
        Expect("]");
        return values;
    }
    public Value Element(SchemaType type)
    {
        Shape shape = type.Kind switch {
            Kind.Bool => Shape.Boolean, Kind.String => Shape.String, Kind.Bytes => Shape.Bytes,
            Kind.Enum => Shape.Name, Kind.Message => Shape.Message, _ => Shape.Integer
        };
        Require(shape);
        Token token = Next;
        if (shape == Shape.Message) return Message(type);
        position++;
        if (shape == Shape.Integer) {
            if (!Codec.InRange(type, token.Number)) throw Error("out of range", token);
            return new NumberValue(token.Number);
        }
        if (shape == Shape.Boolean) return new BooleanValue(token.Text == "true");
        if (shape == Shape.Name) {
            if (!type.Names.TryGetValue(token.Text, out long number)) throw Error("unknown enum value", token);
            return new NumberValue(number);
        }
        return new BinaryValue(token.Data!);
    }
}

readonly record struct Segment(Field Field, int? Index)
{
    public bool WholeList => Field.Repeated && Index is null;
}

sealed class Engine
{
    readonly Dictionary<string, SchemaType> types = new(StringComparer.Ordinal);
    public Engine()
    {
        string[] names = ["uint32", "uint64", "sint32", "sint64", "bool", "fixed32", "sfixed32", "fixed64", "string", "bytes"];
        for (int i = 0; i < names.Length; i++) types[names[i]] = new(names[i], (Kind)i);
    }
    public void ReadSchema()
    {
        SchemaType? current = null;
        while (Console.ReadLine() is string line && line != "END SCHEMA") {
            string[] words = line.Split(' ');
            if (words[0] is "ENUM" or "MESSAGE") {
                current = new(words[1], words[0] == "ENUM" ? Kind.Enum : Kind.Message);
                types.Add(current.Name, current);
            } else if (words[0] == "VALUE") {
                long number = long.Parse(words[2]);
                current!.Numbers.Add(number, words[1]);
                current.Names.Add(words[1], number);
            } else if (words[0] == "FIELD") {
                string mode = words.Length > 4 ? words[4] : "";
                current!.Fields.Add(new(long.Parse(words[1]), words[2], words[3], mode == "REQUIRED",
                    mode == "REPEATED", words.Length > 5 && words[5] == "PACKED", mode == "ONEOF" ? words[5] : null));
            }
        }
        foreach (SchemaType type in types.Values) {
            type.Fields.Sort((a, b) => a.Number.CompareTo(b.Number));
            foreach (Field field in type.Fields) field.Type = types[field.TypeName];
        }
    }
    static List<Segment> Path(SchemaType type, string path)
    {
        List<Segment> segments = [];
        string[] words = path.Split('.');
        for (int i = 0; i < words.Length; i++) {
            Match match = Regex.Match(words[i], @"^([a-z][a-z0-9_]*)(?:\[([0-9]{1,6})\])?$");
            if (!match.Success) throw new CodecError("invalid path");
            Field? field = type.Find(match.Groups[1].Value);
            int? index = match.Groups[2].Success ? int.Parse(match.Groups[2].Value) : null;
            if (field is null || (index is not null && !field.Repeated)) throw new CodecError("invalid path");
            if (i + 1 < words.Length && (field.Type.Kind != Kind.Message || (field.Repeated && index is null)))
                throw new CodecError("invalid path");
            segments.Add(new(field, index));
            type = field.Type;
        }
        return segments;
    }
    static string Get(Message message, List<Segment> path)
    {
        Message? current = message;
        for (int step = 0; step < path.Count; step++) {
            Segment segment = path[step];
            List<Value> values = current?.Values(segment.Field) ?? [];
            if (step == path.Count - 1) {
                if (segment.WholeList) return Format.Sequence(segment.Field.Type, values);
                int index = segment.Index ?? 0;
                return index < values.Count ? Format.Value(segment.Field.Type, values[index]) : "(none)";
            }
            int at = segment.Index ?? 0;
            current = at < values.Count ? (Message)values[at] : null;
        }
        throw new InvalidOperationException();
    }
    static void Edit(Message message, List<Segment> path, List<Value>? replacement)
    {
        Message current = message;
        for (int i = 0; i < path.Count - 1; i++) {
            Segment segment = path[i];
            List<Value> values = current.Values(segment.Field);
            int index = segment.Index ?? 0;
            if (index >= values.Count) {
                if (replacement is null) return;
                if (segment.Index is not null) throw new CodecError("index out of range");
                current.Choose(segment.Field);
                values = [new Message(segment.Field.Type)];
                current.Fields[segment.Field] = values;
            }
            current = (Message)values[index];
        }
        Segment last = path[^1];
        if (last.Index is int at) {
            List<Value> values = current.Values(last.Field);
            if (at >= values.Count) {
                if (replacement is not null) throw new CodecError("index out of range");
            } else if (replacement is null) values.RemoveAt(at);
            else values[at] = replacement[0];
        } else if (replacement is null) current.Fields.Remove(last.Field);
        else {
            current.Choose(last.Field);
            current.Fields[last.Field] = replacement;
        }
    }
    static bool Equal(Value a, Value b) => (a, b) switch {
        (NumberValue x, NumberValue y) => x.Number == y.Number,
        (BooleanValue x, BooleanValue y) => x.State == y.State,
        (BinaryValue x, BinaryValue y) => x.Bytes.SequenceEqual(y.Bytes),
        _ => false
    };
    static void Differences(Message a, Message b, string prefix, List<string> lines)
    {
        foreach (Field field in a.Type.Fields) {
            List<Value> x = a.Values(field), y = b.Values(field);
            for (int i = 0; i < Math.Max(x.Count, y.Count); i++) {
                string path = prefix + field.Name + (field.Repeated ? "[" + i + "]" : "");
                if (i < x.Count && i < y.Count && field.Type.Kind == Kind.Message)
                    Differences((Message)x[i], (Message)y[i], path + ".", lines);
                else if (i >= x.Count || i >= y.Count || !Equal(x[i], y[i]))
                    lines.Add(path + ": " + (i < x.Count ? Format.Value(field.Type, x[i]) : "(none)") +
                        " -> " + (i < y.Count ? Format.Value(field.Type, y[i]) : "(none)"));
            }
        }
    }
    static List<string> Schema(SchemaType type)
    {
        List<string> lines = [type.Name];
        HashSet<SchemaType> chain = [];
        void Visit(SchemaType current, int depth)
        {
            chain.Add(current);
            foreach (Field field in current.Fields) {
                string mode = field.Required ? "required " : field.Packed ? "repeated packed " : field.Repeated ? "repeated " :
                    field.Group is not null ? "oneof " + field.Group + " " : "";
                string line = new string(' ', depth * 2) + field.Number + " " + field.Name + ": " + mode + field.Type.Name;
                if (field.Type.Kind == Kind.Enum)
                    line += " (" + string.Join(", ", field.Type.Numbers.Select(pair => pair.Value + "=" + pair.Key)) + ")";
                bool recursive = field.Type.Kind == Kind.Message && chain.Contains(field.Type);
                lines.Add(line + (recursive ? " (recursive)" : ""));
                if (field.Type.Kind == Kind.Message && !recursive) Visit(field.Type, depth + 1);
            }
            chain.Remove(current);
        }
        Visit(type, 1);
        return lines;
    }
    static byte[] Hex(string text)
    {
        if (text == "-") return [];
        if (text.Length == 0 || text.Length % 2 != 0 || text.Any(c => c is not (>= '0' and <= '9' or >= 'a' and <= 'f')))
            throw new CodecError("invalid hex");
        return Convert.FromHexString(text);
    }
    static string Rest(string line, int separators)
    {
        int at = -1;
        for (int i = 0; i < separators; i++) at = line.IndexOf(' ', at + 1);
        return line[(at + 1)..];
    }
    static Message Decode(SchemaType type, byte[] bytes, string suffix = "")
    {
        try { return new Decoder(bytes).Decode(type); }
        catch (CodecError error) { throw new CodecError(error.Message + suffix); }
    }
    public List<string> Execute(string line)
    {
        string[] words = line.Split(' ');
        string command = words[0];
        int minimum = command switch {
            "VARINT" or "ZIGZAG" or "SCHEMA" => 2,
            "ENCODE" or "SIZE" or "DECODE" or "LITERAL" or "JSON" or "CANON" or "EXPLAIN" => 3,
            "GET" or "CLEAR" or "MERGE" or "DIFF" => 4, "PATCH" => 5, _ => 0
        };
        if (minimum == 0) throw new CodecError("unknown command");
        if (words.Length < minimum || (command is not ("ENCODE" or "SIZE" or "PATCH") && words.Length != minimum))
            throw new CodecError("wrong number of arguments");
        if (command is "VARINT" or "ZIGZAG") {
            if (!Regex.IsMatch(words[1], @"^-?[0-9]{1,18}$")) throw new CodecError("invalid number");
            long number = long.Parse(words[1]);
            if (command == "VARINT" ? number < 0 || number > Codec.MaxUnsigned :
                number < -4503599627370496 || number > 4503599627370495) throw new CodecError("invalid number");
            long value = command == "ZIGZAG" ? Codec.Zigzag(number) : number;
            List<byte> bytes = [];
            Codec.Varint(bytes, value);
            return [(command == "ZIGZAG" ? value + " " : "") + Format.Hex(bytes.ToArray())];
        }
        if (!types.TryGetValue(words[1], out SchemaType? type) || type.Kind != Kind.Message)
            throw new CodecError("unknown message type");
        byte[] data = [], second = [];
        if (command is not ("SCHEMA" or "ENCODE" or "SIZE")) data = Hex(words[2]);
        if (command is "MERGE" or "DIFF") second = Hex(words[3]);
        List<Segment> path = command is "GET" or "PATCH" or "CLEAR" ? Path(type, words[3]) : [];
        if (command == "SCHEMA") return Schema(type);
        if (command is "ENCODE" or "SIZE") {
            Literal literal = new(Rest(line, 2));
            Message parsed = literal.Message(type);
            literal.End();
            byte[] encoded = Codec.Encode(parsed);
            if (command == "ENCODE") return [Format.Hex(encoded)];
            return [encoded.Length + string.Concat(type.Fields.Where(field => parsed.Values(field).Count > 0)
                .Select(field => " " + field.Name + "=" + Codec.FieldBytes(field, parsed.Values(field)).Length))];
        }
        if (command == "EXPLAIN") {
            Decoder decoder = new(data, true);
            decoder.Decode(type);
            return decoder.Lines;
        }
        if (command == "MERGE") return Format.Text(Decode(type, [.. data, .. second]));
        if (command == "DIFF") {
            Message firstMessage = Decode(type, data, " in first");
            Message secondMessage = Decode(type, second, " in second");
            List<string> lines = [];
            Differences(firstMessage, secondMessage, "", lines);
            return lines.Count == 0 ? ["SAME"] : lines;
        }
        Message message = Decode(type, data);
        if (command == "DECODE") return Format.Text(message);
        if (command == "LITERAL") return [Format.Message(message)];
        if (command == "JSON") return [Format.Message(message, true)];
        if (command == "GET") return [Get(message, path)];
        if (command == "PATCH") {
            Literal literal = new(Rest(line, 4));
            Segment last = path[^1];
            List<Value> replacement = last.WholeList ? literal.FieldValue(last.Field) : [literal.Element(last.Field.Type)];
            literal.End();
            Edit(message, path, replacement);
            Codec.Required(message);
        } else if (command == "CLEAR") {
            Edit(message, path, null);
            Codec.Required(message);
        }
        return [Format.Hex(Codec.Encode(message))];
    }
}

static class Program
{
    public static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        Engine engine = new();
        engine.ReadSchema();
        int count = int.Parse(Console.ReadLine()!);
        for (int i = 0; i < count; i++) {
            try {
                foreach (string output in engine.Execute(Console.ReadLine()!)) Console.WriteLine(output);
            } catch (CodecError error) {
                Console.WriteLine("ERROR " + error.Message);
            }
        }
    }
}
