#include <algorithm>
#include <cstdint>
#include <functional>
#include <iostream>
#include <map>
#include <memory>
#include <optional>
#include <regex>
#include <set>
#include <stdexcept>
#include <string>
#include <utility>
#include <variant>
#include <vector>

using Int = std::int64_t;
using UInt = std::uint64_t;
using Bytes = std::vector<std::uint8_t>;
using Lines = std::vector<std::string>;
constexpr UInt maximum = 9007199254740991ULL;
constexpr Int signedMinimum = -4503599627370496LL;
constexpr Int signedMaximum = 4503599627370495LL;
enum class Wire : unsigned { Varint = 0, I64 = 1, Length = 2, I32 = 5 };

struct CommandError : std::runtime_error { using std::runtime_error::runtime_error; };
[[noreturn]] void fail(const std::string& reason) { throw CommandError(reason); }
[[noreturn]] void byteError(const std::string& reason, std::size_t offset) { fail(reason + " at byte " + std::to_string(offset)); }
[[noreturn]] void columnError(const std::string& reason, std::size_t column) { fail(reason + " at column " + std::to_string(column)); }

Lines split(const std::string& text, char separator = ' ') {
    Lines result;
    std::size_t start = 0;
    while (true) {
        std::size_t end = text.find(separator, start);
        if (end == std::string::npos) { result.push_back(text.substr(start)); return result; }
        result.push_back(text.substr(start, end - start)); start = end + 1;
    }
}
std::string joined(const Lines& lines, const std::string& separator) {
    std::string result;
    for (std::size_t index = 0; index < lines.size(); ++index) {
        if (index) result += separator;
        result += lines[index];
    }
    return result;
}
std::string readLine(std::istream& input) {
    std::string line;
    std::getline(input, line);
    if (!line.empty() && line.back() == '\r') line.pop_back();
    return line;
}
bool digit(char character) { return character >= '0' && character <= '9'; }
bool letter(char character) { return (character >= 'a' && character <= 'z') || (character >= 'A' && character <= 'Z'); }
Int decimal(const std::string& text) {
    bool negative = text.front() == '-';
    Int value = 0;
    for (std::size_t index = negative ? 1 : 0; index < text.size(); ++index) value = value * 10 + text[index] - '0';
    return negative ? -value : value;
}
void append(Bytes& target, const Bytes& source) { target.insert(target.end(), source.begin(), source.end()); }
std::string hexDigits(const Bytes& bytes) {
    constexpr char digits[] = "0123456789abcdef";
    std::string result;
    for (std::uint8_t byte : bytes) { result += digits[byte / 16]; result += digits[byte % 16]; }
    return result;
}
std::string hex(const Bytes& bytes) { return bytes.empty() ? "-" : hexDigits(bytes); }
std::string wireName(Wire wire) {
    switch (wire) {
        case Wire::Varint: return "varint";
        case Wire::I64: return "i64";
        case Wire::Length: return "len";
        case Wire::I32: return "i32";
    }
    throw std::logic_error("Invalid wire type");
}
UInt zigzag(Int value) { return value < 0 ? UInt(-value) * 2 - 1 : UInt(value) * 2; }

struct Type;
struct Field {
    UInt number = 0;
    std::string typeName, name;
    const Type* type = nullptr;
    bool required = false, repeated = false, packed = false;
    std::optional<std::string> group;
};
struct IntegerSpec { Int minimum, maximum; };
struct BooleanSpec {};
struct StringSpec {};
struct BytesSpec {};
struct EnumSpec { std::map<std::string, Int> byName; std::map<Int, std::string> byNumber; };
struct MessageSpec {
    std::vector<Field> fields;
    std::map<std::string, std::size_t> byName;
    std::map<UInt, std::size_t> byNumber;
};
using TypeData = std::variant<IntegerSpec, BooleanSpec, StringSpec, BytesSpec, EnumSpec, MessageSpec>;
struct Type {
    std::string name;
    Wire wire;
    TypeData data;
    bool message() const { return std::holds_alternative<MessageSpec>(data); }
    const std::vector<Field>& fields() const { return std::get<MessageSpec>(data).fields; }
    const Field* field(const std::string& name) const {
        const MessageSpec& definition = std::get<MessageSpec>(data);
        std::map<std::string, std::size_t>::const_iterator found = definition.byName.find(name);
        return found == definition.byName.end() ? nullptr : &definition.fields[found->second];
    }
    const Field* field(UInt number) const {
        const MessageSpec& definition = std::get<MessageSpec>(data);
        std::map<UInt, std::size_t>::const_iterator found = definition.byNumber.find(number);
        return found == definition.byNumber.end() ? nullptr : &definition.fields[found->second];
    }
};
struct Schema {
    std::map<std::string, Type> types;
    explicit Schema(std::istream& input) {
        for (const Type& type : std::vector<Type>{
            {"uint32", Wire::Varint, IntegerSpec{0, 4294967295LL}},
            {"uint64", Wire::Varint, IntegerSpec{0, Int(maximum)}},
            {"sint32", Wire::Varint, IntegerSpec{-2147483648LL, 2147483647LL}},
            {"sint64", Wire::Varint, IntegerSpec{signedMinimum, signedMaximum}},
            {"fixed32", Wire::I32, IntegerSpec{0, 4294967295LL}},
            {"sfixed32", Wire::I32, IntegerSpec{-2147483648LL, 2147483647LL}},
            {"fixed64", Wire::I64, IntegerSpec{0, Int(maximum)}},
            {"bool", Wire::Varint, BooleanSpec{}}, {"string", Wire::Length, StringSpec{}}, {"bytes", Wire::Length, BytesSpec{}},
        }) types.emplace(type.name, type);
        Type* current = nullptr;
        for (std::string line = readLine(input); line != "END SCHEMA"; line = readLine(input)) {
            Lines words = split(line);
            if (words[0] == "ENUM" || words[0] == "MESSAGE") {
                TypeData data = words[0] == "ENUM" ? TypeData(EnumSpec{}) : TypeData(MessageSpec{});
                Wire wire = words[0] == "ENUM" ? Wire::Varint : Wire::Length;
                current = &types.emplace(words[1], Type{words[1], wire, std::move(data)}).first->second;
            } else if (words[0] == "VALUE") {
                EnumSpec& definition = std::get<EnumSpec>(current->data);
                Int number = decimal(words[2]);
                definition.byName.emplace(words[1], number); definition.byNumber.emplace(number, words[1]);
            } else if (words[0] == "FIELD") {
                Field field;
                field.number = UInt(decimal(words[1])); field.typeName = words[2]; field.name = words[3];
                std::string mode = words.size() > 4 ? words[4] : "";
                field.required = mode == "REQUIRED"; field.repeated = mode == "REPEATED";
                field.packed = words.size() > 5 && words[5] == "PACKED";
                if (mode == "ONEOF") field.group = words[5];
                std::get<MessageSpec>(current->data).fields.push_back(std::move(field));
            } else current = nullptr;
        }
        for (auto& [name, type] : types) {
            if (!type.message()) continue;
            MessageSpec& definition = std::get<MessageSpec>(type.data);
            std::sort(definition.fields.begin(), definition.fields.end(), [](const Field& left, const Field& right) { return left.number < right.number; });
            for (std::size_t index = 0; index < definition.fields.size(); ++index) {
                Field& field = definition.fields[index]; field.type = &types.at(field.typeName);
                definition.byName.emplace(field.name, index); definition.byNumber.emplace(field.number, index);
            }
        }
    }
    Lines tree(const Type& type) const {
        Lines result{type.name};
        std::vector<const Type*> chain{&type};
        std::function<void(const Type&, std::size_t)> visit = [&](const Type& current, std::size_t depth) {
            for (const Field& field : current.fields()) {
                std::string kind = field.required ? "required " : field.packed ? "repeated packed " : field.repeated ? "repeated "
                    : field.group ? "oneof " + *field.group + " " : "";
                std::string line = std::string(depth * 2, ' ') + std::to_string(field.number) + " " + field.name + ": " + kind + field.type->name;
                if (const EnumSpec* enumeration = std::get_if<EnumSpec>(&field.type->data)) {
                    Lines values;
                    for (const auto& [number, name] : enumeration->byNumber) values.push_back(name + "=" + std::to_string(number));
                    line += " (" + joined(values, ", ") + ")";
                }
                bool recursive = field.type->message() && std::find(chain.begin(), chain.end(), field.type) != chain.end();
                if (recursive) line += " (recursive)";
                result.push_back(line);
                if (field.type->message() && !recursive) { chain.push_back(field.type); visit(*field.type, depth + 1); chain.pop_back(); }
            }
        };
        visit(type, 1); return result;
    }
};

struct Message;
using MessagePtr = std::shared_ptr<Message>;
using Value = std::variant<Int, bool, std::string, Bytes, MessagePtr>;
using Values = std::vector<Value>;
using Raw = std::variant<UInt, Bytes>;
struct UnknownField { UInt number; Wire wire; Raw raw; };
struct Message {
    const Type* type;
    std::map<UInt, Values> values;
    std::vector<UnknownField> unknown;
    explicit Message(const Type& type) : type(&type) {}
    const Values& sequence(const Field& field) const {
        static const Values empty;
        std::map<UInt, Values>::const_iterator found = values.find(field.number);
        return found == values.end() ? empty : found->second;
    }
    void replace(const Field& field, Values items) {
        if (field.group) for (const Field& other : type->fields()) if (other.number != field.number && other.group == field.group) values.erase(other.number);
        if (items.empty()) values.erase(field.number);
        else values.insert_or_assign(field.number, std::move(items));
    }
    void apply(const Field& field, const Values& items) {
        if (field.repeated) {
            Values combined = sequence(field); combined.insert(combined.end(), items.begin(), items.end()); replace(field, std::move(combined));
        } else if (field.type->message() && !sequence(field).empty()) {
            Values previous = sequence(field);
            std::get<MessagePtr>(previous.front())->merge(*std::get<MessagePtr>(items.front()));
            replace(field, std::move(previous));
        } else replace(field, items);
    }
    void merge(const Message& other) {
        for (const Field& field : type->fields()) if (!other.sequence(field).empty()) apply(field, other.sequence(field));
        unknown.insert(unknown.end(), other.unknown.begin(), other.unknown.end());
    }
    void checkRequired(const std::string& prefix = "") const {
        for (const Field& field : type->fields()) {
            const Values& items = sequence(field);
            std::string path = prefix + field.name;
            if (field.required && items.empty()) fail("missing required field " + path);
            if (field.type->message()) for (std::size_t index = 0; index < items.size(); ++index) {
                std::get<MessagePtr>(items[index])->checkRequired(path + (field.repeated ? "[" + std::to_string(index) + "]" : "") + ".");
            }
        }
    }
};

Bytes varint(UInt value) {
    Bytes result;
    do { unsigned low = unsigned(value % 128); value /= 128; result.push_back(std::uint8_t(low + (value ? 128 : 0))); } while (value);
    return result;
}
Bytes encode(const Message& message);
Bytes valueBytes(const Type& type, const Value& value) {
    if (const MessagePtr* message = std::get_if<MessagePtr>(&value)) return encode(**message);
    if (const bool* boolean = std::get_if<bool>(&value)) return varint(*boolean ? 1 : 0);
    if (const std::string* text = std::get_if<std::string>(&value)) return Bytes(text->begin(), text->end());
    if (const Bytes* bytes = std::get_if<Bytes>(&value)) return *bytes;
    Int integer = std::get<Int>(value);
    UInt number = type.name == "sint32" || type.name == "sint64" ? zigzag(integer)
        : type.name == "sfixed32" && integer < 0 ? UInt(integer + 4294967296LL) : UInt(integer);
    if (type.wire == Wire::Varint) return varint(number);
    Bytes result(type.wire == Wire::I32 ? 4 : 8);
    for (std::uint8_t& byte : result) { byte = std::uint8_t(number % 256); number /= 256; }
    return result;
}
Bytes record(UInt number, Wire wire, const Raw& raw) {
    Bytes result = varint(number * 8 + UInt(wire));
    if (wire == Wire::Varint) append(result, varint(std::get<UInt>(raw)));
    else {
        const Bytes& bytes = std::get<Bytes>(raw);
        if (wire == Wire::Length) append(result, varint(bytes.size()));
        append(result, bytes);
    }
    return result;
}
Bytes fieldBytes(const Field& field, const Values& values) {
    Bytes result;
    if (values.empty()) return result;
    if (field.packed) {
        for (const Value& value : values) append(result, valueBytes(*field.type, value));
        return record(field.number, Wire::Length, result);
    }
    for (const Value& value : values) {
        Bytes bytes = valueBytes(*field.type, value);
        append(result, varint(field.number * 8 + UInt(field.type->wire)));
        if (field.type->wire == Wire::Length) append(result, varint(bytes.size()));
        append(result, bytes);
    }
    return result;
}
Bytes encode(const Message& message) {
    Bytes result;
    for (const Field& field : message.type->fields()) append(result, fieldBytes(field, message.sequence(field)));
    for (const UnknownField& field : message.unknown) append(result, record(field.number, field.wire, field.raw));
    return result;
}

std::string quote(const std::string& text, bool json = false) {
    std::string result = "\"";
    for (unsigned char byte : text) {
        if (byte == '"' || byte == '\\') { result += '\\'; result += char(byte); }
        else if (byte == '\n') result += "\\n";
        else if (byte == '\t') result += "\\t";
        else if (byte >= 32 && byte <= 126) result += char(byte);
        else result += std::string(json ? "\\u00" : "\\x") + hexDigits(Bytes{byte});
    }
    return result + '"';
}
std::string camel(const std::string& name) {
    std::string result;
    bool upper = false;
    for (char character : name) {
        if (character == '_') upper = true;
        else { result += upper && character >= 'a' && character <= 'z' ? char(character - 'a' + 'A') : character; upper = false; }
    }
    return result;
}
std::string base64(const Bytes& bytes) {
    constexpr char alphabet[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    std::string result;
    for (std::size_t index = 0; index < bytes.size(); index += 3) {
        unsigned value = unsigned(bytes[index]) << 16;
        if (index + 1 < bytes.size()) value += unsigned(bytes[index + 1]) << 8;
        if (index + 2 < bytes.size()) value += bytes[index + 2];
        result += alphabet[value / 262144]; result += alphabet[value / 4096 % 64];
        result += index + 1 < bytes.size() ? alphabet[value / 64 % 64] : '=';
        result += index + 2 < bytes.size() ? alphabet[value % 64] : '=';
    }
    return result;
}
std::string notation(const Type& type, const Value& value, bool json = false);
std::string listNotation(const Type& type, const Values& values, bool json = false) {
    Lines items;
    for (const Value& value : values) items.push_back(notation(type, value, json));
    return "[" + joined(items, json ? "," : ", ") + "]";
}
std::string notation(const Type& type, const Value& value, bool json) {
    if (const MessagePtr* message = std::get_if<MessagePtr>(&value)) {
        Lines items;
        for (const Field& field : type.fields()) {
            const Values& values = (*message)->sequence(field);
            if (values.empty()) continue;
            std::string key = json ? quote(camel(field.name), true) : field.name;
            std::string text = field.repeated ? listNotation(*field.type, values, json) : notation(*field.type, values.front(), json);
            items.push_back(key + (json ? ":" : ": ") + text);
        }
        return "{" + joined(items, json ? "," : ", ") + "}";
    }
    if (const std::string* text = std::get_if<std::string>(&value)) return quote(*text, json);
    if (const Bytes* bytes = std::get_if<Bytes>(&value)) return json ? quote(base64(*bytes), true) : "<" + hexDigits(*bytes) + ">";
    if (const bool* boolean = std::get_if<bool>(&value)) return *boolean ? "true" : "false";
    Int integer = std::get<Int>(value);
    if (const EnumSpec* enumeration = std::get_if<EnumSpec>(&type.data)) {
        const std::string& name = enumeration->byNumber.at(integer);
        return json ? quote(name, true) : name;
    }
    std::string text = std::to_string(integer);
    return json && (type.name == "uint64" || type.name == "sint64" || type.name == "fixed64") ? quote(text, true) : text;
}
std::string rawText(const Raw& raw) {
    if (const UInt* integer = std::get_if<UInt>(&raw)) return std::to_string(*integer);
    return "<" + hexDigits(std::get<Bytes>(raw)) + ">";
}
Lines textFormat(const Message& message) {
    Lines result{message.type->name + " {"};
    std::function<void(const Message&, std::size_t)> visit = [&](const Message& current, std::size_t depth) {
        std::string indent(depth * 2, ' ');
        for (const Field& field : current.type->fields()) for (const Value& value : current.sequence(field)) {
            if (field.type->message()) {
                result.push_back(indent + field.name + " {"); visit(*std::get<MessagePtr>(value), depth + 1); result.push_back(indent + "}");
            } else result.push_back(indent + field.name + ": " + notation(*field.type, value));
        }
        for (const UnknownField& field : current.unknown) result.push_back(indent + std::to_string(field.number) + ": " + wireName(field.wire) + " " + rawText(field.raw));
    };
    visit(message, 1); result.push_back("}"); return result;
}

struct ReadValue { Raw raw; std::size_t position, start; };
struct Reader {
    const Bytes& data;
    std::size_t position, end;
    UInt integer() {
        std::size_t start = position;
        UInt result = 0;
        for (unsigned index = 0; index < 8; ++index) {
            if (position == end) byteError("truncated varint", start);
            unsigned byte = data[position++];
            result += UInt(byte % 128) << (7 * index);
            if (byte < 128) {
                if (result > maximum) byteError("varint too large", start);
                return result;
            }
        }
        byteError("varint too long", start);
    }
    ReadValue raw(Wire wire) {
        std::size_t valuePosition = position;
        if (wire == Wire::Varint) return {integer(), valuePosition, valuePosition};
        std::size_t count;
        if (wire == Wire::Length) {
            UInt length = integer();
            if (length > end - position) byteError("length past end", valuePosition);
            count = std::size_t(length);
        } else {
            count = wire == Wire::I32 ? 4 : 8;
            if (end - position < count) byteError("truncated " + wireName(wire), valuePosition);
        }
        std::size_t start = position;
        Bytes bytes(data.begin() + position, data.begin() + position + count);
        position += count;
        return {std::move(bytes), valuePosition, start};
    }
};
struct Decoder {
    const Bytes& data;
    bool explain = false;
    Lines lines;
    Value convert(const Type& type, const ReadValue& input, std::size_t depth) {
        if (type.wire == Wire::Length) {
            const Bytes& bytes = std::get<Bytes>(input.raw);
            if (type.message()) return message(type, input.start, input.start + bytes.size(), depth);
            if (std::holds_alternative<BytesSpec>(type.data)) return bytes;
            for (std::size_t index = 0; index < bytes.size(); ++index) if (bytes[index] >= 128) byteError("invalid string", input.start + index);
            return std::string(bytes.begin(), bytes.end());
        }
        UInt number = 0;
        if (const UInt* integer = std::get_if<UInt>(&input.raw)) number = *integer;
        else {
            const Bytes& bytes = std::get<Bytes>(input.raw);
            for (std::size_t index = 0; index < bytes.size(); ++index) number |= UInt(bytes[index]) << (8 * index);
        }
        if (number > maximum) byteError("value out of range", input.position);
        if (std::holds_alternative<BooleanSpec>(type.data)) {
            if (number > 1) byteError("value out of range", input.position);
            return number == 1;
        }
        if (const EnumSpec* enumeration = std::get_if<EnumSpec>(&type.data)) {
            if (!enumeration->byNumber.count(Int(number))) byteError("unknown enum number", input.position);
            return Int(number);
        }
        Int value = Int(number);
        if (type.name == "sint32" || type.name == "sint64") value = number % 2 ? -Int((number + 1) / 2) : Int(number / 2);
        else if (type.name == "sfixed32" && number >= 2147483648ULL) value -= 4294967296LL;
        const IntegerSpec& range = std::get<IntegerSpec>(type.data);
        if (value < range.minimum || value > range.maximum) byteError("value out of range", input.position);
        return value;
    }
    MessagePtr message(const Type& type, std::size_t start, std::size_t end, std::size_t depth = 0) {
        MessagePtr result = std::make_shared<Message>(type);
        Reader reader{data, start, end};
        while (reader.position < end) {
            std::size_t offset = reader.position;
            UInt tag = reader.integer(), number = tag / 8, wireNumber = tag % 8;
            if (number == 0) byteError("invalid field number", offset);
            if (wireNumber != 0 && wireNumber != 1 && wireNumber != 2 && wireNumber != 5) byteError("invalid wire type", offset);
            Wire wire = Wire(wireNumber);
            const Field* field = type.field(number);
            bool packed = field && field->repeated && field->type->wire != Wire::Length && wire == Wire::Length;
            if (field && wire != field->type->wire && !packed) byteError("wire type mismatch", offset);
            ReadValue input = reader.raw(wire);
            std::string line;
            if (explain) {
                line = std::string(depth * 2, ' ') + std::to_string(offset) + " " + std::to_string(number) + " " + (field ? field->name : "?") + " " + wireName(wire);
                if (wire == Wire::Length) line += " " + std::to_string(std::get<Bytes>(input.raw).size());
            }
            if (!field) {
                if (explain) lines.push_back(line + " " + rawText(input.raw));
                else result->unknown.push_back({number, wire, std::move(input.raw)});
                continue;
            }
            Values values;
            if (packed) {
                Reader elements{data, input.start, reader.position};
                while (elements.position < elements.end) values.push_back(convert(*field->type, elements.raw(field->type->wire), depth + 1));
                if (explain) {
                    line += " packed";
                    for (const Value& value : values) line += " " + notation(*field->type, value);
                    lines.push_back(line);
                }
            } else {
                if (explain && field->type->message()) lines.push_back(line);
                values.push_back(convert(*field->type, input, depth + 1));
                if (explain && !field->type->message()) lines.push_back(line + " " + notation(*field->type, values.front()));
            }
            if (!explain) result->apply(*field, values);
        }
        return result;
    }
    MessagePtr decode(const Type& type) {
        MessagePtr result = message(type, 0, data.size());
        result->checkRequired(); return result;
    }
};

bool lowerHex(char character) { return digit(character) || (character >= 'a' && character <= 'f'); }
Bytes fromHex(const std::string& text) {
    Bytes result;
    for (std::size_t index = 0; index < text.size(); index += 2) {
        unsigned high = digit(text[index]) ? text[index] - '0' : text[index] - 'a' + 10;
        unsigned low = digit(text[index + 1]) ? text[index + 1] - '0' : text[index + 1] - 'a' + 10;
        result.push_back(std::uint8_t(high * 16 + low));
    }
    return result;
}
Bytes parseHex(const std::string& text) {
    if (text == "-") return {};
    if (text.empty() || text.size() % 2 || !std::all_of(text.begin(), text.end(), lowerHex)) fail("invalid hex");
    return fromHex(text);
}
enum class TokenKind { Symbol, Integer, Name, String, Bytes, End };
enum class Shape { None, Message, List, Integer, Boolean, Name, String, Bytes };
struct Token {
    TokenKind kind;
    std::size_t column;
    std::variant<std::monostate, char, Int, std::string, Bytes> value;
    bool symbol(char expected) const { return kind == TokenKind::Symbol && std::get<char>(value) == expected; }
    Shape shape() const {
        switch (kind) {
            case TokenKind::Symbol: return symbol('{') ? Shape::Message : symbol('[') ? Shape::List : Shape::None;
            case TokenKind::Integer: return Shape::Integer;
            case TokenKind::Name: {
                const std::string& name = std::get<std::string>(value);
                return name == "true" || name == "false" ? Shape::Boolean : Shape::Name;
            }
            case TokenKind::String: return Shape::String;
            case TokenKind::Bytes: return Shape::Bytes;
            case TokenKind::End: return Shape::None;
        }
        throw std::logic_error("Invalid token kind");
    }
};
std::vector<Token> tokenize(const std::string& text) {
    std::vector<Token> tokens;
    std::size_t index = 0;
    while (index < text.size()) {
        char character = text[index];
        if (character == ' ') { ++index; continue; }
        std::size_t start = index++, column = start + 1;
        if (std::string("{}[]:,").find(character) != std::string::npos) tokens.push_back({TokenKind::Symbol, column, character});
        else if (character == '"') {
            std::string value;
            bool closed = false;
            while (index < text.size()) {
                char current = text[index++];
                if (current == '"') { closed = true; break; }
                if (current != '\\') { value += current; continue; }
                if (index == text.size()) columnError("syntax error", column);
                char escape = text[index++];
                if (escape == '"' || escape == '\\') value += escape;
                else if (escape == 'n') value += '\n';
                else if (escape == 't') value += '\t';
                else if (escape == 'x' && index + 2 <= text.size() && lowerHex(text[index]) && lowerHex(text[index + 1]) && text[index] <= '7') {
                    value += char(fromHex(text.substr(index, 2)).front()); index += 2;
                } else columnError("syntax error", column);
            }
            if (!closed) columnError("syntax error", column);
            tokens.push_back({TokenKind::String, column, std::move(value)});
        } else if (character == '<') {
            std::size_t end = text.find('>', index);
            if (end == std::string::npos) columnError("syntax error", column);
            std::string digits = text.substr(index, end - index);
            if (digits.size() % 2 || !std::all_of(digits.begin(), digits.end(), lowerHex)) columnError("syntax error", column);
            tokens.push_back({TokenKind::Bytes, column, fromHex(digits)}); index = end + 1;
        } else if (character == '-' || digit(character)) {
            if (character == '-' && (index == text.size() || !digit(text[index]))) columnError("syntax error", column);
            while (index < text.size() && digit(text[index])) ++index;
            tokens.push_back({TokenKind::Integer, column, decimal(text.substr(start, index - start))});
        } else if (letter(character) || character == '_') {
            while (index < text.size() && (letter(text[index]) || digit(text[index]) || text[index] == '_')) ++index;
            tokens.push_back({TokenKind::Name, column, text.substr(start, index - start)});
        } else columnError("syntax error", column);
    }
    tokens.push_back({TokenKind::End, text.size() + 1, std::monostate{}}); return tokens;
}
struct LiteralParser {
    std::vector<Token> tokens;
    std::size_t position = 0;
    explicit LiteralParser(const std::string& text) : tokens(tokenize(text)) {}
    const Token& peek() const { return tokens[position]; }
    const Token& take() { return tokens[position++]; }
    bool accept(char symbol) { if (!peek().symbol(symbol)) return false; ++position; return true; }
    const Token& expect(char symbol) {
        if (!peek().symbol(symbol)) columnError("syntax error", peek().column);
        return take();
    }
    void finish() const { if (peek().kind != TokenKind::End) columnError("syntax error", peek().column); }
    void requireShape(Shape expected) const {
        Shape actual = peek().shape();
        if (actual == Shape::None) columnError("syntax error", peek().column);
        if (actual != expected) columnError("type mismatch", peek().column);
    }
    MessagePtr message(const Type& type) {
        expect('{');
        MessagePtr result = std::make_shared<Message>(type);
        std::set<UInt> seen;
        std::set<std::string> groups;
        if (!peek().symbol('}')) while (true) {
            const Token& token = peek();
            if (token.kind != TokenKind::Name) columnError("syntax error", token.column);
            const Field* field = type.field(std::get<std::string>(token.value));
            if (!field) columnError("unknown field", token.column);
            if (seen.count(field->number)) columnError("duplicate field", token.column);
            if (field->group && groups.count(*field->group)) columnError("oneof conflict", token.column);
            seen.insert(field->number); if (field->group) groups.insert(*field->group);
            take(); expect(':'); result->replace(*field, fieldValue(*field));
            if (!accept(',')) break;
        }
        const Token& closing = expect('}');
        for (const Field& field : type.fields()) if (field.required && !seen.count(field.number)) columnError("missing required field " + field.name, closing.column);
        return result;
    }
    Values fieldValue(const Field& field) {
        if (!field.repeated) return {element(*field.type)};
        requireShape(Shape::List); expect('[');
        Values values;
        if (!peek().symbol(']')) {
            values.push_back(element(*field.type));
            while (accept(',')) values.push_back(element(*field.type));
        }
        expect(']'); return values;
    }
    Value element(const Type& type) {
        Shape expected = std::holds_alternative<IntegerSpec>(type.data) ? Shape::Integer
            : std::holds_alternative<BooleanSpec>(type.data) ? Shape::Boolean
            : std::holds_alternative<EnumSpec>(type.data) ? Shape::Name
            : std::holds_alternative<StringSpec>(type.data) ? Shape::String
            : std::holds_alternative<BytesSpec>(type.data) ? Shape::Bytes : Shape::Message;
        requireShape(expected);
        if (expected == Shape::Message) return message(type);
        const Token& token = take();
        if (expected == Shape::Integer) {
            Int value = std::get<Int>(token.value);
            const IntegerSpec& range = std::get<IntegerSpec>(type.data);
            if (value < range.minimum || value > range.maximum) columnError("out of range", token.column);
            return value;
        }
        if (expected == Shape::Boolean) return std::get<std::string>(token.value) == "true";
        if (expected == Shape::Name) {
            const EnumSpec& enumeration = std::get<EnumSpec>(type.data);
            std::map<std::string, Int>::const_iterator found = enumeration.byName.find(std::get<std::string>(token.value));
            if (found == enumeration.byName.end()) columnError("unknown enum value", token.column);
            return found->second;
        }
        if (expected == Shape::String) return std::get<std::string>(token.value);
        return std::get<Bytes>(token.value);
    }
};

struct Segment { const Field* field; std::optional<std::size_t> index; };
using Path = std::vector<Segment>;
Path parsePath(const Type& type, const std::string& text) {
    static const std::regex syntax(R"(^([a-z][a-z0-9]*(?:_[a-z0-9]+)*)(?:\[([0-9]{1,6})\])?$)");
    Lines parts = split(text, '.');
    const Type* current = &type;
    Path path;
    for (std::size_t index = 0; index < parts.size(); ++index) {
        std::smatch match;
        if (!std::regex_match(parts[index], match, syntax)) fail("invalid path");
        const Field* field = current->field(match[1].str());
        if (!field) fail("invalid path");
        std::optional<std::size_t> element;
        if (match[2].matched) element = std::size_t(decimal(match[2].str()));
        if (element && !field->repeated) fail("invalid path");
        if (index + 1 < parts.size() && (!field->type->message() || (field->repeated && !element))) fail("invalid path");
        path.push_back({field, element}); current = field->type;
    }
    return path;
}
Message* parentAt(Message& message, const Path& path, bool create = false) {
    Message* current = &message;
    for (std::size_t index = 0; index + 1 < path.size(); ++index) {
        const Segment& segment = path[index];
        std::size_t element = segment.index.value_or(0);
        if (current->sequence(*segment.field).size() <= element) {
            if (!create) return nullptr;
            if (segment.index) fail("index out of range");
            current->replace(*segment.field, {std::make_shared<Message>(*segment.field->type)});
        }
        current = std::get<MessagePtr>(current->sequence(*segment.field)[element]).get();
    }
    return current;
}
std::string getAt(Message& message, const Path& path) {
    const Segment& last = path.back();
    Message* parent = parentAt(message, path);
    bool whole = last.field->repeated && !last.index;
    if (!parent) return whole ? "[]" : "(none)";
    const Values& values = parent->sequence(*last.field);
    if (whole) return listNotation(*last.field->type, values);
    std::size_t index = last.index.value_or(0);
    return index < values.size() ? notation(*last.field->type, values[index]) : "(none)";
}
void patchAt(Message& message, const Path& path, Values values) {
    Message* parent = parentAt(message, path, true);
    const Segment& last = path.back();
    if (last.index) {
        Values previous = parent->sequence(*last.field);
        if (*last.index >= previous.size()) fail("index out of range");
        previous[*last.index] = values.front(); parent->replace(*last.field, std::move(previous));
    } else parent->replace(*last.field, std::move(values));
}
void clearAt(Message& message, const Path& path) {
    Message* parent = parentAt(message, path);
    if (!parent) return;
    const Segment& last = path.back();
    if (!last.index) parent->values.erase(last.field->number);
    else {
        Values values = parent->sequence(*last.field);
        if (*last.index >= values.size()) return;
        values.erase(values.begin() + *last.index); parent->replace(*last.field, std::move(values));
    }
}
void differences(const Message& first, const Message& second, const std::string& prefix, Lines& lines) {
    for (const Field& field : first.type->fields()) {
        const Values& left = first.sequence(field);
        const Values& right = second.sequence(field);
        for (std::size_t index = 0; index < std::max(left.size(), right.size()); ++index) {
            const Value* a = index < left.size() ? &left[index] : nullptr;
            const Value* b = index < right.size() ? &right[index] : nullptr;
            std::string path = prefix + field.name + (field.repeated ? "[" + std::to_string(index) + "]" : "");
            if (a && b && field.type->message()) differences(*std::get<MessagePtr>(*a), *std::get<MessagePtr>(*b), path + ".", lines);
            else if (!a || !b || *a != *b) lines.push_back(path + ": " + (a ? notation(*field.type, *a) : "(none)") + " -> " + (b ? notation(*field.type, *b) : "(none)"));
        }
    }
}

Lines execute(const Schema& schema, const std::string& line) {
    static const std::map<std::string, std::pair<std::size_t, std::size_t>> arity{
        {"VARINT", {2, 2}}, {"ZIGZAG", {2, 2}}, {"SCHEMA", {2, 2}},
        {"ENCODE", {3, 0}}, {"SIZE", {3, 0}}, {"DECODE", {3, 3}}, {"LITERAL", {3, 3}},
        {"JSON", {3, 3}}, {"CANON", {3, 3}}, {"EXPLAIN", {3, 3}},
        {"GET", {4, 4}}, {"CLEAR", {4, 4}}, {"MERGE", {4, 4}}, {"DIFF", {4, 4}}, {"PATCH", {5, 0}},
    };
    Lines words = split(line);
    const std::string& command = words[0];
    if (!arity.count(command)) fail("unknown command");
    const auto& [minimumWords, maximumWords] = arity.at(command);
    if (words.size() < minimumWords || (maximumWords && words.size() != maximumWords)) fail("wrong number of arguments");
    if (command == "VARINT" || command == "ZIGZAG") {
        static const std::regex numberSyntax("-?[0-9]{1,18}");
        if (!std::regex_match(words[1], numberSyntax)) fail("invalid number");
        Int value = decimal(words[1]);
        if (command == "VARINT") {
            if (value < 0 || value > Int(maximum)) fail("invalid number");
            return {hex(varint(UInt(value)))};
        }
        if (value < signedMinimum || value > signedMaximum) fail("invalid number");
        UInt encoded = zigzag(value);
        return {std::to_string(encoded) + " " + hex(varint(encoded))};
    }
    std::map<std::string, Type>::const_iterator found = schema.types.find(words[1]);
    if (found == schema.types.end() || !found->second.message()) fail("unknown message type");
    const Type& type = found->second;
    if (command == "SCHEMA") return schema.tree(type);
    if (command == "ENCODE" || command == "SIZE") {
        LiteralParser parser(joined(Lines(words.begin() + 2, words.end()), " "));
        MessagePtr message = parser.message(type); parser.finish();
        Bytes bytes = encode(*message);
        if (command == "ENCODE") return {hex(bytes)};
        std::string result = std::to_string(bytes.size());
        for (const Field& field : type.fields()) if (!message->sequence(field).empty()) {
            result += " " + field.name + "=" + std::to_string(fieldBytes(field, message->sequence(field)).size());
        }
        return {result};
    }
    Bytes first = parseHex(words[2]), second;
    if (command == "MERGE" || command == "DIFF") second = parseHex(words[3]);
    Path path;
    if (command == "GET" || command == "PATCH" || command == "CLEAR") path = parsePath(type, words[3]);
    if (command == "EXPLAIN") {
        Decoder decoder{first, true, {}};
        decoder.message(type, 0, first.size());
        return decoder.lines.empty() ? Lines{"(empty)"} : decoder.lines;
    }
    if (command == "DIFF") {
        MessagePtr a, b;
        try { a = Decoder{first, false, {}}.decode(type); }
        catch (const CommandError& error) { fail(std::string(error.what()) + " in first"); }
        try { b = Decoder{second, false, {}}.decode(type); }
        catch (const CommandError& error) { fail(std::string(error.what()) + " in second"); }
        Lines result;
        differences(*a, *b, "", result);
        return result.empty() ? Lines{"SAME"} : result;
    }
    if (command == "MERGE") append(first, second);
    MessagePtr message = Decoder{first, false, {}}.decode(type);
    if (command == "DECODE" || command == "MERGE") return textFormat(*message);
    if (command == "LITERAL" || command == "JSON") return {notation(type, message, command == "JSON")};
    if (command == "GET") return {getAt(*message, path)};
    if (command == "PATCH") {
        LiteralParser parser(joined(Lines(words.begin() + 4, words.end()), " "));
        const Segment& last = path.back();
        Values values = last.field->repeated && !last.index ? parser.fieldValue(*last.field) : Values{parser.element(*last.field->type)};
        parser.finish(); patchAt(*message, path, std::move(values)); message->checkRequired();
    } else if (command == "CLEAR") { clearAt(*message, path); message->checkRequired(); }
    return {hex(encode(*message))};
}

int main() {
    std::ios::sync_with_stdio(false);
    std::cin.tie(nullptr);
    Schema schema(std::cin);
    Int count = decimal(readLine(std::cin));
    for (Int index = 0; index < count; ++index) {
        std::string line = readLine(std::cin);
        try {
            Lines result = execute(schema, line);
            for (const std::string& output : result) std::cout << output << '\n';
        } catch (const CommandError& error) { std::cout << "ERROR " << error.what() << '\n'; }
    }
}
