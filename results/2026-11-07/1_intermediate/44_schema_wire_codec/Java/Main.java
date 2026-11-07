import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

public class Main {
    static final long MAX_UNSIGNED = 9_007_199_254_740_991L;
    enum Kind { UINT32, UINT64, SINT32, SINT64, BOOL, FIXED32, SFIXED32, FIXED64, STRING, BYTES, ENUM, MESSAGE }
    static final class Type {
        final String name;
        final Kind kind;
        final List<Field> fields = new ArrayList<>();
        final NavigableMap<Long, String> members = new TreeMap<>();
        Type(String name, Kind kind) { this.name = name; this.kind = kind; }
        int wire() {
            return switch (kind) {
                case FIXED64 -> 1;
                case STRING, BYTES, MESSAGE -> 2;
                case FIXED32, SFIXED32 -> 5;
                default -> 0;
            };
        }
        boolean contains(long value) {
            return switch (kind) {
                case UINT32, FIXED32 -> value >= 0 && value <= 4_294_967_295L;
                case UINT64, FIXED64 -> value >= 0 && value <= MAX_UNSIGNED;
                case SINT32, SFIXED32 -> value >= -2_147_483_648L && value <= 2_147_483_647L;
                case SINT64 -> value >= -4_503_599_627_370_496L && value <= 4_503_599_627_370_495L;
                default -> true;
            };
        }
        Field byName(String name) {
            for (var field : fields) if (field.name.equals(name)) return field;
            return null;
        }
        Field byNumber(long number) {
            for (var field : fields) if (field.number == number) return field;
            return null;
        }
    }
    static final class Field {
        final long number;
        final String name, typeName, group;
        final boolean required, repeated, packed;
        Type type;
        Field(String[] words) {
            number = Long.parseLong(words[1]); typeName = words[2]; name = words[3];
            String mode = words.length > 4 ? words[4] : "";
            required = mode.equals("REQUIRED"); repeated = mode.equals("REPEATED");
            packed = repeated && words.length == 6; group = mode.equals("ONEOF") ? words[5] : null;
        }
    }
    static final class Schema {
        final Map<String, Type> types = new HashMap<>();
        Schema(BufferedReader input) throws IOException {
            String[] names = {"uint32", "uint64", "sint32", "sint64", "bool", "fixed32", "sfixed32", "fixed64", "string", "bytes"};
            for (int i = 0; i < names.length; i++) types.put(names[i], new Type(names[i], Kind.values()[i]));
            Type current = null;
            for (String line; !(line = input.readLine()).equals("END SCHEMA");) {
                String[] words = line.split(" ", -1);
                switch (words[0]) {
                    case "ENUM", "MESSAGE" -> {
                        current = new Type(words[1], words[0].equals("ENUM") ? Kind.ENUM : Kind.MESSAGE);
                        types.put(current.name, current);
                    }
                    case "VALUE" -> current.members.put(Long.parseLong(words[2]), words[1]);
                    case "FIELD" -> current.fields.add(new Field(words));
                    default -> {}
                }
            }
            for (var type : types.values()) {
                type.fields.sort(Comparator.comparingLong(field -> field.number));
                for (var field : type.fields) field.type = types.get(field.typeName);
            }
        }
    }
    sealed interface Value permits NumberValue, BooleanValue, BinaryValue, Message {}
    record NumberValue(long number) implements Value {}
    record BooleanValue(boolean state) implements Value {}
    record BinaryValue(byte[] bytes) implements Value {}
    record Unknown(long number, int wire, long integer, byte[] bytes) {}
    static final class Message implements Value {
        final Type type;
        final Map<Field, List<Value>> fields = new HashMap<>();
        final List<Unknown> unknown = new ArrayList<>();
        Message(Type type) { this.type = type; }
        List<Value> values(Field field) { return fields.getOrDefault(field, List.of()); }
        void choose(Field field) {
            if (field.group == null) return;
            for (var other : type.fields) if (other != field && field.group.equals(other.group)) fields.remove(other);
        }
        void apply(Field field, List<Value> incoming) {
            if (incoming.isEmpty()) return;
            choose(field);
            var old = values(field);
            if (field.repeated) fields.computeIfAbsent(field, _ -> new ArrayList<>()).addAll(incoming);
            else if (field.type.kind == Kind.MESSAGE && !old.isEmpty()) ((Message)old.getFirst()).merge((Message)incoming.getFirst());
            else fields.put(field, new ArrayList<>(incoming));
        }
        void merge(Message incoming) {
            for (var field : type.fields) apply(field, incoming.values(field));
            unknown.addAll(incoming.unknown);
        }
        void required(String prefix) {
            for (var field : type.fields) {
                var values = values(field);
                String path = prefix + field.name;
                if (field.required && values.isEmpty()) throw new CodecException("missing required field " + path);
                if (field.type.kind == Kind.MESSAGE) for (int i = 0; i < values.size(); i++)
                    ((Message)values.get(i)).required(path + (field.repeated ? "[" + i + "]" : "") + ".");
            }
        }
    }
    static final class CodecException extends RuntimeException {
        CodecException(String message) { super(message); }
    }
    static CodecException byteError(String reason, int offset) { return new CodecException(reason + " at byte " + offset); }
    static CodecException columnError(String reason, int column) { return new CodecException(reason + " at column " + column); }
    static long zigzag(long number) { return number >= 0 ? number * 2 : -number * 2 - 1; }
    static long unzigzag(long number) { return number % 2 == 0 ? number / 2 : -1 - number / 2; }
    static void putVarint(ByteArrayOutputStream bytes, long number) {
        while (number >= 128) { bytes.write((int)(number % 128 + 128)); number /= 128; }
        bytes.write((int)number);
    }
    static void encodeElement(ByteArrayOutputStream bytes, Type type, Value value) {
        if (value instanceof Message || value instanceof BinaryValue) {
            byte[] payload = value instanceof Message message ? encode(message) : ((BinaryValue)value).bytes;
            putVarint(bytes, payload.length); bytes.writeBytes(payload); return;
        }
        long number = value instanceof BooleanValue b ? (b.state ? 1 : 0) : ((NumberValue)value).number;
        if (type.kind == Kind.SINT32 || type.kind == Kind.SINT64) number = zigzag(number);
        if (type.kind == Kind.SFIXED32 && number < 0) number += 4_294_967_296L;
        if (type.wire() == 0) putVarint(bytes, number);
        else for (int i = 0; i < (type.wire() == 1 ? 8 : 4); i++) { bytes.write((int)(number % 256)); number /= 256; }
    }
    static byte[] encodeField(Field field, List<Value> values) {
        var bytes = new ByteArrayOutputStream();
        if (!values.isEmpty()) {
            if (field.packed) {
                var payload = new ByteArrayOutputStream();
                for (var value : values) encodeElement(payload, field.type, value);
                putVarint(bytes, field.number * 8 + 2); putVarint(bytes, payload.size()); bytes.writeBytes(payload.toByteArray());
            } else for (var value : values) {
                putVarint(bytes, field.number * 8 + field.type.wire()); encodeElement(bytes, field.type, value);
            }
        }
        return bytes.toByteArray();
    }
    static byte[] encode(Message message) {
        var bytes = new ByteArrayOutputStream();
        for (var field : message.type.fields) bytes.writeBytes(encodeField(field, message.values(field)));
        for (var unknown : message.unknown) {
            putVarint(bytes, unknown.number * 8 + unknown.wire);
            if (unknown.wire == 0) putVarint(bytes, unknown.integer);
            else { if (unknown.wire == 2) putVarint(bytes, unknown.bytes.length); bytes.writeBytes(unknown.bytes); }
        }
        return bytes.toByteArray();
    }
    static String hex(byte[] bytes) { return bytes.length == 0 ? "-" : HexFormat.of().formatHex(bytes); }
    static String byteNotation(byte[] bytes) { return "<" + HexFormat.of().formatHex(bytes) + ">"; }
    static String quote(byte[] bytes, boolean json) {
        var text = new StringBuilder("\"");
        for (byte raw : bytes) {
            int b = raw & 255;
            switch (b) {
                case 34 -> text.append("\\\""); case 92 -> text.append("\\\\");
                case 10 -> text.append("\\n"); case 9 -> text.append("\\t");
                default -> {
                    if (b >= 32 && b <= 126) text.append((char)b);
                    else text.append(json ? "\\u00" : "\\x").append(String.format(Locale.ROOT, "%02x", b));
                }
            }
        }
        return text.append('"').toString();
    }
    static String notation(Type type, Value value, boolean json) {
        if (value == null) return "(none)";
        return switch (value) {
            case NumberValue n -> {
                String text = type.kind == Kind.ENUM ? type.members.get(n.number) : Long.toString(n.number);
                boolean quoted = json && (type.kind == Kind.ENUM || type.kind == Kind.UINT64 || type.kind == Kind.SINT64 || type.kind == Kind.FIXED64);
                yield quoted ? "\"" + text + "\"" : text;
            }
            case BooleanValue b -> Boolean.toString(b.state);
            case BinaryValue b -> type.kind == Kind.STRING ? quote(b.bytes, json) : json ? "\"" + Base64.getEncoder().encodeToString(b.bytes) + "\"" : byteNotation(b.bytes);
            case Message m -> messageNotation(m, json);
        };
    }
    static String sequenceNotation(Type type, List<Value> values, boolean json) {
        var items = new ArrayList<String>();
        for (var value : values) items.add(notation(type, value, json));
        return "[" + String.join(json ? "," : ", ", items) + "]";
    }
    static String messageNotation(Message message, boolean json) {
        var items = new ArrayList<String>();
        for (var field : message.type.fields) {
            var values = message.values(field);
            if (values.isEmpty()) continue;
            String key = field.name + ": ";
            if (json) {
                var name = new StringBuilder(); boolean uppercase = false;
                for (char c : field.name.toCharArray()) {
                    if (c == '_') { uppercase = true; continue; }
                    name.append(uppercase && c >= 'a' && c <= 'z' ? (char)(c - 'a' + 'A') : c); uppercase = false;
                }
                key = "\"" + name + "\":";
            }
            items.add(key + (field.repeated ? sequenceNotation(field.type, values, json) : notation(field.type, values.getFirst(), json)));
        }
        return "{" + String.join(json ? "," : ", ", items) + "}";
    }
    static String wireName(int wire) { return switch (wire) { case 0 -> "varint"; case 1 -> "i64"; case 2 -> "len"; default -> "i32"; }; }
    static String rawNotation(Unknown unknown) { return unknown.wire == 0 ? Long.toString(unknown.integer) : byteNotation(unknown.bytes); }
    static void textContents(Message message, int depth, List<String> lines) {
        String indent = "  ".repeat(depth);
        for (var field : message.type.fields) for (var value : message.values(field)) {
            if (value instanceof Message child) {
                lines.add(indent + field.name + " {"); textContents(child, depth + 1, lines); lines.add(indent + "}");
            } else lines.add(indent + field.name + ": " + notation(field.type, value, false));
        }
        for (var unknown : message.unknown) lines.add(indent + unknown.number + ": " + wireName(unknown.wire) + " " + rawNotation(unknown));
    }
    static List<String> textMessage(Message message) {
        var lines = new ArrayList<String>(); lines.add(message.type.name + " {"); textContents(message, 1, lines); lines.add("}"); return lines;
    }

    record Raw(long number, byte[] bytes, int position, int payload) {}
    static final class ByteReader {
        final byte[] data;
        final int end;
        int position;
        ByteReader(byte[] data, int position, int end) { this.data = data; this.position = position; this.end = end; }
        long varint() {
            int start = position; long number = 0;
            for (int i = 0; i < 8; i++) {
                if (position >= end) throw byteError("truncated varint", start);
                int b = data[position++] & 255; number += (long)(b & 127) << (7 * i);
                if (b < 128) { if (number > MAX_UNSIGNED) throw byteError("varint too large", start); return number; }
            }
            throw byteError("varint too long", start);
        }
        Raw read(int wire) {
            int start = position;
            if (wire == 0) return new Raw(varint(), new byte[0], start, start);
            long length = wire == 2 ? varint() : wire == 1 ? 8 : 4;
            if (length > end - position) throw byteError(wire == 2 ? "length past end" : wire == 1 ? "truncated i64" : "truncated i32", start);
            int payload = position; position += (int)length;
            return new Raw(0, Arrays.copyOfRange(data, payload, position), start, payload);
        }
    }
    static Value convert(Type type, Raw raw) {
        if (type.kind == Kind.STRING || type.kind == Kind.BYTES) {
            if (type.kind == Kind.STRING) for (int i = 0; i < raw.bytes.length; i++)
                if ((raw.bytes[i] & 255) >= 128) throw byteError("invalid string", raw.payload + i);
            return new BinaryValue(raw.bytes);
        }
        long number = raw.number;
        if (type.wire() == 1 || type.wire() == 5) {
            if (type.kind == Kind.FIXED64 && (raw.bytes[7] != 0 || (raw.bytes[6] & 255) >= 32)) throw byteError("value out of range", raw.position);
            number = 0;
            for (int i = raw.bytes.length - 1; i >= 0; i--) number = number * 256 + (raw.bytes[i] & 255);
        }
        if (type.kind == Kind.SINT32 || type.kind == Kind.SINT64) number = unzigzag(number);
        if (type.kind == Kind.SFIXED32 && number >= 2_147_483_648L) number -= 4_294_967_296L;
        if (!type.contains(number) || type.kind == Kind.BOOL && number > 1) throw byteError("value out of range", raw.position);
        if (type.kind == Kind.ENUM && !type.members.containsKey(number)) throw byteError("unknown enum number", raw.position);
        return type.kind == Kind.BOOL ? new BooleanValue(number != 0) : new NumberValue(number);
    }
    static final class Decoder {
        final byte[] data;
        final boolean explain;
        final List<String> lines = new ArrayList<>();
        Decoder(byte[] data, boolean explain) { this.data = data; this.explain = explain; }
        Message message(Type type, int start, int end, int depth) {
            var message = new Message(type); var reader = new ByteReader(data, start, end);
            while (reader.position < end) {
                int offset = reader.position; long tag = reader.varint(), number = tag / 8; int wire = (int)(tag % 8);
                if (number == 0) throw byteError("invalid field number", offset);
                if (wire != 0 && wire != 1 && wire != 2 && wire != 5) throw byteError("invalid wire type", offset);
                var field = type.byNumber(number);
                boolean packed = field != null && field.repeated && field.type.wire() != 2 && wire == 2;
                if (field != null && wire != field.type.wire() && !packed) throw byteError("wire type mismatch", offset);
                var raw = reader.read(wire);
                String header = "  ".repeat(depth) + offset + " " + number + " " + (field == null ? "?" : field.name) + " " + wireName(wire);
                if (wire == 2) header += " " + raw.bytes.length;
                if (field == null) {
                    var unknown = new Unknown(number, wire, raw.number, raw.bytes);
                    if (explain) lines.add(header + " " + rawNotation(unknown)); else message.unknown.add(unknown);
                    continue;
                }
                var values = new ArrayList<Value>();
                if (field.type.kind == Kind.MESSAGE) {
                    if (explain) lines.add(header);
                    values.add(message(field.type, raw.payload, raw.payload + raw.bytes.length, depth + 1));
                } else {
                    if (packed) {
                        var elements = new ByteReader(data, raw.payload, raw.payload + raw.bytes.length);
                        while (elements.position < elements.end) values.add(convert(field.type, elements.read(field.type.wire())));
                    } else values.add(convert(field.type, raw));
                    if (explain) {
                        if (packed) header += " packed";
                        for (var value : values) header += " " + notation(field.type, value, false);
                        lines.add(header);
                    }
                }
                if (!explain) message.apply(field, values);
            }
            return message;
        }
    }
    static Message decode(Type type, byte[] bytes, String suffix) {
        try { var message = new Decoder(bytes, false).message(type, 0, bytes.length, 0); message.required(""); return message; }
        catch (CodecException error) { throw new CodecException(error.getMessage() + suffix); }
    }

    enum TokenKind { SYMBOL, INTEGER, NAME, STRING, BYTES, END }
    enum Shape { NONE, MESSAGE, LIST, INTEGER, BOOLEAN, NAME, STRING, BYTES }
    record Token(TokenKind kind, int column, String text, long number, byte[] bytes) {
        Shape shape() {
            return switch (kind) {
                case INTEGER -> Shape.INTEGER; case STRING -> Shape.STRING; case BYTES -> Shape.BYTES;
                case NAME -> text.equals("true") || text.equals("false") ? Shape.BOOLEAN : Shape.NAME;
                case SYMBOL -> text.equals("{") ? Shape.MESSAGE : text.equals("[") ? Shape.LIST : Shape.NONE;
                default -> Shape.NONE;
            };
        }
    }
    static boolean digit(char c) { return c >= '0' && c <= '9'; }
    static boolean letter(char c) { return c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z'; }
    static int hexDigit(char c) { return digit(c) ? c - '0' : c >= 'a' && c <= 'f' ? c - 'a' + 10 : -1; }
    static List<Token> tokenize(String source) {
        var tokens = new ArrayList<Token>();
        for (int at = 0; at < source.length();) {
            char c = source.charAt(at);
            if (c == ' ') { at++; continue; }
            int start = at++, column = start + 1;
            Token token;
            if ("{}[]:,".indexOf(c) >= 0) token = new Token(TokenKind.SYMBOL, column, Character.toString(c), 0, null);
            else if (c == '"') {
                var bytes = new ByteArrayOutputStream();
                while (at < source.length() && source.charAt(at) != '"') {
                    int b = source.charAt(at++);
                    if (b == '\\') {
                        if (at == source.length()) throw columnError("syntax error", column);
                        char escaped = source.charAt(at++);
                        switch (escaped) {
                            case '"', '\\' -> b = escaped; case 'n' -> b = '\n'; case 't' -> b = '\t';
                            case 'x' -> {
                                if (at + 1 >= source.length()) throw columnError("syntax error", column);
                                int high = hexDigit(source.charAt(at)), low = hexDigit(source.charAt(at + 1));
                                if (high < 0 || high > 7 || low < 0) throw columnError("syntax error", column);
                                b = high * 16 + low; at += 2;
                            }
                            default -> throw columnError("syntax error", column);
                        }
                    }
                    bytes.write(b);
                }
                if (at == source.length()) throw columnError("syntax error", column);
                at++; token = new Token(TokenKind.STRING, column, null, 0, bytes.toByteArray());
            } else if (c == '<') {
                int end = source.indexOf('>', at);
                if (end < 0 || (end - at) % 2 != 0) throw columnError("syntax error", column);
                var bytes = new ByteArrayOutputStream();
                while (at < end) {
                    int high = hexDigit(source.charAt(at)), low = hexDigit(source.charAt(at + 1));
                    if (high < 0 || low < 0) throw columnError("syntax error", column);
                    bytes.write(high * 16 + low); at += 2;
                }
                at++; token = new Token(TokenKind.BYTES, column, null, 0, bytes.toByteArray());
            } else if (c == '-' || digit(c)) {
                if (c == '-' && (at == source.length() || !digit(source.charAt(at)))) throw columnError("syntax error", column);
                while (at < source.length() && digit(source.charAt(at))) at++;
                token = new Token(TokenKind.INTEGER, column, null, Long.parseLong(source.substring(start, at)), null);
            } else if (letter(c) || c == '_') {
                while (at < source.length() && (letter(source.charAt(at)) || digit(source.charAt(at)) || source.charAt(at) == '_')) at++;
                token = new Token(TokenKind.NAME, column, source.substring(start, at), 0, null);
            } else throw columnError("syntax error", column);
            tokens.add(token);
        }
        tokens.add(new Token(TokenKind.END, source.length() + 1, null, 0, null)); return tokens;
    }
    static final class Literal {
        final List<Token> tokens;
        int position;
        Literal(String source) { tokens = tokenize(source); }
        Token next() { return tokens.get(position); }
        boolean symbol(String text) { return next().kind == TokenKind.SYMBOL && next().text.equals(text); }
        Token expect(String text) {
            if (!symbol(text)) throw columnError("syntax error", next().column);
            return tokens.get(position++);
        }
        void end() { if (next().kind != TokenKind.END) throw columnError("syntax error", next().column); }
        void require(Shape shape) {
            if (next().shape() == Shape.NONE) throw columnError("syntax error", next().column);
            if (next().shape() != shape) throw columnError("type mismatch", next().column);
        }
        Value element(Type type) {
            Shape shape = switch (type.kind) {
                case BOOL -> Shape.BOOLEAN; case STRING -> Shape.STRING; case BYTES -> Shape.BYTES;
                case ENUM -> Shape.NAME; case MESSAGE -> Shape.MESSAGE; default -> Shape.INTEGER;
            };
            require(shape);
            if (shape == Shape.MESSAGE) return message(type);
            Token token = tokens.get(position++);
            return switch (shape) {
                case INTEGER -> {
                    if (!type.contains(token.number)) throw columnError("out of range", token.column);
                    yield new NumberValue(token.number);
                }
                case BOOLEAN -> new BooleanValue(token.text.equals("true"));
                case NAME -> {
                    Long number = null;
                    for (var entry : type.members.entrySet()) if (entry.getValue().equals(token.text)) { number = entry.getKey(); break; }
                    if (number == null) throw columnError("unknown enum value", token.column);
                    yield new NumberValue(number);
                }
                case STRING, BYTES -> new BinaryValue(token.bytes);
                default -> throw new AssertionError();
            };
        }
        List<Value> field(Field field) {
            if (!field.repeated) return List.of(element(field.type));
            require(Shape.LIST); expect("[");
            var values = new ArrayList<Value>();
            if (!symbol("]")) {
                values.add(element(field.type));
                while (symbol(",")) { position++; values.add(element(field.type)); }
            }
            expect("]"); return values;
        }
        Message message(Type type) {
            expect("{");
            var message = new Message(type); var seen = new HashSet<Field>(); var groups = new HashSet<String>();
            if (!symbol("}")) {
                while (true) {
                    Token token = next();
                    if (token.kind != TokenKind.NAME) throw columnError("syntax error", token.column);
                    var field = type.byName(token.text);
                    if (field == null) throw columnError("unknown field", token.column);
                    if (!seen.add(field)) throw columnError("duplicate field", token.column);
                    if (field.group != null && !groups.add(field.group)) throw columnError("oneof conflict", token.column);
                    position++; expect(":"); message.fields.put(field, field(field));
                    if (!symbol(",")) break;
                    position++;
                }
            }
            Token closing = expect("}");
            for (var field : type.fields) if (field.required && !seen.contains(field))
                throw columnError("missing required field " + field.name, closing.column);
            return message;
        }
    }

    record Segment(Field field, Integer index) {
        boolean wholeList() { return field.repeated && index == null; }
    }
    static List<Segment> path(Type type, String source) {
        String[] parts = source.split("\\.", -1); var path = new ArrayList<Segment>();
        for (int i = 0; i < parts.length; i++) {
            String part = parts[i], name = part; Integer index = null;
            int open = part.indexOf('[');
            if (open >= 0) {
                if (!part.endsWith("]")) throw new CodecException("invalid path");
                String digits = part.substring(open + 1, part.length() - 1);
                if (digits.isEmpty() || digits.length() > 6 || !digits.chars().allMatch(c -> c >= '0' && c <= '9')) throw new CodecException("invalid path");
                index = Integer.parseInt(digits); name = part.substring(0, open);
            }
            var field = type.byName(name);
            if (field == null || index != null && !field.repeated) throw new CodecException("invalid path");
            if (i + 1 < parts.length && (field.type.kind != Kind.MESSAGE || field.repeated && index == null)) throw new CodecException("invalid path");
            path.add(new Segment(field, index)); type = field.type;
        }
        return path;
    }
    static String get(Message message, List<Segment> path) {
        for (int i = 0; i < path.size(); i++) {
            var segment = path.get(i); List<Value> values = message == null ? List.of() : message.values(segment.field);
            int index = segment.index == null ? 0 : segment.index;
            if (i + 1 == path.size() && segment.wholeList()) return sequenceNotation(segment.field.type, values, false);
            Value value = index < values.size() ? values.get(index) : null;
            if (i + 1 == path.size()) return notation(segment.field.type, value, false);
            message = (Message)value;
        }
        throw new AssertionError();
    }
    static void edit(Message message, List<Segment> path, List<Value> replacement) {
        for (int i = 0; i < path.size(); i++) {
            var segment = path.get(i); var field = segment.field; var values = message.values(field);
            int index = segment.index == null ? 0 : segment.index;
            if (i + 1 == path.size()) {
                if (segment.index != null) {
                    if (index >= values.size()) { if (replacement != null) throw new CodecException("index out of range"); }
                    else if (replacement == null) values.remove(index);
                    else values.set(index, replacement.getFirst());
                } else if (replacement == null) message.fields.remove(field);
                else { message.choose(field); message.fields.put(field, new ArrayList<>(replacement)); }
                return;
            }
            if (index >= values.size()) {
                if (replacement == null) return;
                if (segment.index != null) throw new CodecException("index out of range");
                message.choose(field); values = new ArrayList<>(List.of(new Message(field.type))); message.fields.put(field, values);
            }
            message = (Message)values.get(index);
        }
    }
    static boolean equal(Value a, Value b) {
        if (a == null || b == null) return a == b;
        return switch (a) {
            case NumberValue n -> n.number == ((NumberValue)b).number;
            case BooleanValue v -> v.state == ((BooleanValue)b).state;
            case BinaryValue v -> Arrays.equals(v.bytes, ((BinaryValue)b).bytes);
            case Message _ -> false;
        };
    }
    static void differences(Message a, Message b, String prefix, List<String> lines) {
        for (var field : a.type.fields) {
            var x = a.values(field); var y = b.values(field);
            for (int i = 0; i < Math.max(x.size(), y.size()); i++) {
                String path = prefix + field.name + (field.repeated ? "[" + i + "]" : "");
                Value left = i < x.size() ? x.get(i) : null, right = i < y.size() ? y.get(i) : null;
                if (left instanceof Message l && right instanceof Message r) differences(l, r, path + ".", lines);
                else if (!equal(left, right)) lines.add(path + ": " + notation(field.type, left, false) + " -> " + notation(field.type, right, false));
            }
        }
    }
    static void schemaFields(Type type, List<Type> chain, List<String> lines) {
        chain.add(type);
        for (var field : type.fields) {
            String mode = field.required ? "required " : field.packed ? "repeated packed " : field.repeated ? "repeated " : field.group != null ? "oneof " + field.group + " " : "";
            String line = "  ".repeat(chain.size()) + field.number + " " + field.name + ": " + mode + field.type.name;
            if (field.type.kind == Kind.ENUM) {
                var members = new ArrayList<String>(); field.type.members.forEach((number, name) -> members.add(name + "=" + number));
                line += " (" + String.join(", ", members) + ")";
            }
            boolean recursive = field.type.kind == Kind.MESSAGE && chain.contains(field.type);
            lines.add(line + (recursive ? " (recursive)" : ""));
            if (field.type.kind == Kind.MESSAGE && !recursive) schemaFields(field.type, chain, lines);
        }
        chain.removeLast();
    }
    static byte[] parseHex(String source) {
        if (source.equals("-")) return new byte[0];
        if (!source.matches("(?:[0-9a-f]{2})+")) throw new CodecException("invalid hex");
        return HexFormat.of().parseHex(source);
    }
    static String rest(String source, int count) { return source.split(" ", count + 1)[count]; }
    static List<String> execute(Schema schema, String source) {
        String[] words = source.split(" ", -1); String command = words[0];
        int count = switch (command) {
            case "VARINT", "ZIGZAG", "SCHEMA" -> 2;
            case "ENCODE", "SIZE", "DECODE", "LITERAL", "JSON", "CANON", "EXPLAIN" -> 3;
            case "GET", "CLEAR", "MERGE", "DIFF" -> 4;
            case "PATCH" -> 5;
            default -> throw new CodecException("unknown command");
        };
        boolean flexible = Set.of("ENCODE", "SIZE", "PATCH").contains(command);
        if (words.length < count || !flexible && words.length != count) throw new CodecException("wrong number of arguments");
        if (command.equals("VARINT") || command.equals("ZIGZAG")) {
            if (!words[1].matches("-?[0-9]{1,18}")) throw new CodecException("invalid number");
            long number = Long.parseLong(words[1]);
            if (command.equals("VARINT") ? number < 0 || number > MAX_UNSIGNED : !schema.types.get("sint64").contains(number)) throw new CodecException("invalid number");
            long value = command.equals("ZIGZAG") ? zigzag(number) : number;
            var bytes = new ByteArrayOutputStream(); putVarint(bytes, value);
            return List.of((command.equals("ZIGZAG") ? value + " " : "") + hex(bytes.toByteArray()));
        }
        var type = schema.types.get(words[1]);
        if (type == null || type.kind != Kind.MESSAGE) throw new CodecException("unknown message type");
        if (command.equals("SCHEMA")) {
            var lines = new ArrayList<String>(); lines.add(type.name); schemaFields(type, new ArrayList<>(), lines); return lines;
        }
        if (command.equals("ENCODE") || command.equals("SIZE")) {
            var literal = new Literal(rest(source, 2)); var message = literal.message(type); literal.end();
            byte[] bytes = encode(message);
            if (command.equals("ENCODE")) return List.of(hex(bytes));
            var line = new StringBuilder(Integer.toString(bytes.length));
            for (var field : type.fields) if (!message.values(field).isEmpty()) line.append(' ').append(field.name).append('=').append(encodeField(field, message.values(field)).length);
            return List.of(line.toString());
        }
        byte[] first = parseHex(words[2]);
        byte[] second = command.equals("MERGE") || command.equals("DIFF") ? parseHex(words[3]) : new byte[0];
        var path = Set.of("GET", "PATCH", "CLEAR").contains(command) ? path(type, words[3]) : List.<Segment>of();
        if (command.equals("EXPLAIN")) {
            var decoder = new Decoder(first, true); decoder.message(type, 0, first.length, 0);
            return first.length == 0 ? List.of("(empty)") : decoder.lines;
        }
        if (command.equals("DIFF")) {
            var a = decode(type, first, " in first"); var b = decode(type, second, " in second");
            var lines = new ArrayList<String>(); differences(a, b, "", lines); return lines.isEmpty() ? List.of("SAME") : lines;
        }
        if (command.equals("MERGE")) {
            byte[] joined = Arrays.copyOf(first, first.length + second.length); System.arraycopy(second, 0, joined, first.length, second.length); first = joined;
        }
        var message = decode(type, first, "");
        return switch (command) {
            case "DECODE", "MERGE" -> textMessage(message);
            case "LITERAL", "JSON" -> List.of(messageNotation(message, command.equals("JSON")));
            case "GET" -> List.of(get(message, path));
            default -> {
                if (command.equals("PATCH")) {
                    var literal = new Literal(rest(source, 4)); var last = path.getLast();
                    var replacement = last.wholeList() ? literal.field(last.field) : List.of(literal.element(last.field.type));
                    literal.end(); edit(message, path, replacement); message.required("");
                } else if (command.equals("CLEAR")) { edit(message, path, null); message.required(""); }
                yield List.of(hex(encode(message)));
            }
        };
    }
    public static void main(String[] args) throws IOException {
        var input = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.US_ASCII));
        var schema = new Schema(input); int count = Integer.parseInt(input.readLine());
        var output = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out, StandardCharsets.US_ASCII)));
        for (int i = 0; i < count; i++) {
            try { for (String line : execute(schema, input.readLine())) output.print(line + "\n"); }
            catch (CodecException error) { output.print("ERROR " + error.getMessage() + "\n"); }
        }
        output.flush();
    }
}
