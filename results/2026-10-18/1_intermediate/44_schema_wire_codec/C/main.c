#include <inttypes.h>
#include <setjmp.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct Block {
    struct Block *next;
    max_align_t alignment;
    unsigned char data[];
} Block;
typedef struct { Block *blocks; } Arena;
static Arena schema_arena, command_arena;
static Arena *arena;

static void *allocate(size_t size) {
    Block *block = calloc(1, sizeof(*block) + size);
    if (!block) exit(EXIT_FAILURE);
    block->next = arena->blocks;
    arena->blocks = block;
    return block->data;
}

static void release(Arena *storage) {
    while (storage->blocks) {
        Block *block = storage->blocks;
        storage->blocks = block->next;
        free(block);
    }
}

static void *grow(void *items, size_t *capacity, size_t need, size_t size) {
    if (need <= *capacity) return items;
    size_t next = *capacity ? *capacity * 2 : 8;
    while (next < need) next *= 2;
    void *copy = allocate(next * size);
    if (*capacity) memcpy(copy, items, *capacity * size);
    *capacity = next;
    return copy;
}

#define VECTOR(T, Name) typedef struct { T *items; size_t count, capacity; } Name
#define PUSH(v, value) do { \
    (v).items = grow((v).items, &(v).capacity, (v).count + 1, sizeof(*(v).items)); \
    (v).items[(v).count++] = (value); \
} while (0)

VECTOR(unsigned char, Bytes);
VECTOR(char *, Words);
typedef struct { char *data; size_t length, capacity; } Text;
static Text output;
static jmp_buf recovery;
static char *error_message;
static const char *error_suffix;

static char *copy_range(const char *source, size_t length) {
    char *copy = allocate(length + 1);
    memcpy(copy, source, length);
    return copy;
}

static char *vformat(const char *format, va_list args) {
    va_list copy;
    va_copy(copy, args);
    int length = vsnprintf(NULL, 0, format, copy);
    va_end(copy);
    char *text = allocate((size_t)length + 1);
    vsnprintf(text, (size_t)length + 1, format, args);
    return text;
}

static char *format(const char *template, ...) {
    va_list args;
    va_start(args, template);
    char *result = vformat(template, args);
    va_end(args);
    return result;
}

static void text_add(Text *text, const char *part) {
    size_t length = strlen(part);
    text->data = grow(text->data, &text->capacity, text->length + length + 1, 1);
    memcpy(text->data + text->length, part, length + 1);
    text->length += length;
}

static void text_char(Text *text, char character) {
    text->data = grow(text->data, &text->capacity, text->length + 2, 1);
    text->data[text->length++] = character;
    text->data[text->length] = '\0';
}

static void line(const char *text) { text_add(&output, text); text_char(&output, '\n'); }

static _Noreturn void fail(const char *template, ...) {
    va_list args;
    va_start(args, template);
    char *reason = vformat(template, args);
    va_end(args);
    error_message = format("%s%s", reason, error_suffix);
    longjmp(recovery, 1);
}

static _Noreturn void byte_error(const char *reason, size_t offset) { fail("%s at byte %zu", reason, offset); }
static _Noreturn void column_error(const char *reason, size_t column) { fail("%s at column %zu", reason, column); }

static void bytes_add(Bytes *to, Bytes from) {
    if (!from.count) return;
    to->items = grow(to->items, &to->capacity, to->count + from.count, 1);
    memcpy(to->items + to->count, from.items, from.count);
    to->count += from.count;
}

static int hex_digit(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    return -1;
}

static char *hex(Bytes bytes, bool brackets) {
    static const char digits[] = "0123456789abcdef";
    Text text = {0};
    if (brackets) text_char(&text, '<');
    for (size_t i = 0; i < bytes.count; i++) {
        text_char(&text, digits[bytes.items[i] / 16]);
        text_char(&text, digits[bytes.items[i] % 16]);
    }
    if (brackets) text_char(&text, '>');
    else if (!bytes.count) text_char(&text, '-');
    return text.data;
}

typedef enum { UINT32, UINT64, SINT32, SINT64, BOOL, FIXED32, SFIXED32, FIXED64, STRING, BYTES, ENUM, MESSAGE } Kind;
typedef struct Type Type;
typedef struct Field Field;
typedef struct Message Message;
typedef struct Value Value;
VECTOR(Field *, Fields);
VECTOR(Type *, Types);
typedef struct { char *name; int64_t number; } EnumValue;
VECTOR(EnumValue, EnumValues);

struct Type {
    char *name;
    Kind kind;
    Fields fields;
    EnumValues values;
};
struct Field {
    int64_t number;
    char *name, *type_name, *group;
    Type *type;
    size_t index;
    bool required, repeated, packed;
};
typedef enum { NUMBER_VALUE, BOOLEAN_VALUE, BINARY_VALUE, MESSAGE_VALUE } ValueKind;
struct Value {
    ValueKind kind;
    union { int64_t number; bool boolean; Bytes binary; Message *message; } as;
};
VECTOR(Value *, Values);
typedef struct { int64_t number, integer; int wire; Bytes bytes; } Unknown;
VECTOR(Unknown, Unknowns);
struct Message { Type *type; Values *fields; Unknowns unknown; };
static Types types;
static const int64_t MAX_UNSIGNED = INT64_C(9007199254740991);

static Type *find_type(const char *name) {
    for (size_t i = 0; i < types.count; i++) if (!strcmp(types.items[i]->name, name)) return types.items[i];
    return NULL;
}
static Field *field_name(Type *type, const char *name) {
    for (size_t i = 0; i < type->fields.count; i++) if (!strcmp(type->fields.items[i]->name, name)) return type->fields.items[i];
    return NULL;
}
static Field *field_number(Type *type, int64_t number) {
    for (size_t i = 0; i < type->fields.count; i++) if (type->fields.items[i]->number == number) return type->fields.items[i];
    return NULL;
}
static EnumValue *enum_number(Type *type, int64_t number) {
    for (size_t i = 0; i < type->values.count; i++) if (type->values.items[i].number == number) return &type->values.items[i];
    return NULL;
}
static EnumValue *enum_name(Type *type, const char *name) {
    for (size_t i = 0; i < type->values.count; i++) if (!strcmp(type->values.items[i].name, name)) return &type->values.items[i];
    return NULL;
}
static int wire_type(Type *type) {
    switch (type->kind) {
        case FIXED64: return 1;
        case STRING: case BYTES: case MESSAGE: return 2;
        case FIXED32: case SFIXED32: return 5;
        default: return 0;
    }
}
static bool in_range(Type *type, int64_t value) {
    switch (type->kind) {
        case UINT32: case FIXED32: return value >= 0 && value <= INT64_C(4294967295);
        case UINT64: case FIXED64: return value >= 0 && value <= MAX_UNSIGNED;
        case SINT32: case SFIXED32: return value >= -INT64_C(2147483648) && value <= INT64_C(2147483647);
        case SINT64: return value >= -INT64_C(4503599627370496) && value <= INT64_C(4503599627370495);
        default: return true;
    }
}
static int64_t zigzag(int64_t value) { return value >= 0 ? value * 2 : -value * 2 - 1; }
static int64_t unzigzag(int64_t value) { return value % 2 ? -1 - value / 2 : value / 2; }
static Value *new_value(ValueKind kind) {
    Value *value = allocate(sizeof(*value));
    value->kind = kind;
    return value;
}
static Message *new_message(Type *type) {
    Message *message = allocate(sizeof(*message));
    message->type = type;
    message->fields = allocate(type->fields.count * sizeof(*message->fields));
    return message;
}
static Value *message_value(Message *message) {
    Value *value = new_value(MESSAGE_VALUE);
    value->as.message = message;
    return value;
}
static void choose(Message *message, Field *field) {
    if (!field->group) return;
    for (size_t i = 0; i < message->type->fields.count; i++) {
        Field *other = message->type->fields.items[i];
        if (other != field && other->group && !strcmp(field->group, other->group)) message->fields[i].count = 0;
    }
}
static void merge(Message *a, Message *b);
static void apply(Message *message, Field *field, Values values) {
    if (!values.count) return;
    choose(message, field);
    Values *old = &message->fields[field->index];
    if (field->repeated) {
        for (size_t i = 0; i < values.count; i++) PUSH(*old, values.items[i]);
    } else if (field->type->kind == MESSAGE && old->count) {
        merge(old->items[0]->as.message, values.items[0]->as.message);
    } else *old = values;
}
static void merge(Message *a, Message *b) {
    for (size_t i = 0; i < a->type->fields.count; i++) apply(a, a->type->fields.items[i], b->fields[i]);
    for (size_t i = 0; i < b->unknown.count; i++) PUSH(a->unknown, b->unknown.items[i]);
}

static void put_varint(Bytes *bytes, int64_t value) {
    while (value >= 128) { PUSH(*bytes, (unsigned char)(value % 128 + 128)); value /= 128; }
    PUSH(*bytes, (unsigned char)value);
}
static Bytes encode(Message *message);
static void encode_element(Bytes *bytes, Type *type, Value *value) {
    if (value->kind == MESSAGE_VALUE || value->kind == BINARY_VALUE) {
        Bytes payload = value->kind == MESSAGE_VALUE ? encode(value->as.message) : value->as.binary;
        put_varint(bytes, (int64_t)payload.count);
        bytes_add(bytes, payload);
        return;
    }
    int64_t number = value->kind == BOOLEAN_VALUE ? value->as.boolean : value->as.number;
    if (type->kind == SINT32 || type->kind == SINT64) number = zigzag(number);
    if (type->kind == SFIXED32 && number < 0) number += INT64_C(4294967296);
    int wire = wire_type(type);
    if (!wire) put_varint(bytes, number);
    else for (int i = 0; i < (wire == 1 ? 8 : 4); i++) { PUSH(*bytes, (unsigned char)(number % 256)); number /= 256; }
}
static Bytes encode_field(Field *field, Values values) {
    Bytes bytes = {0};
    if (!values.count) return bytes;
    if (field->packed) {
        Bytes payload = {0};
        for (size_t i = 0; i < values.count; i++) encode_element(&payload, field->type, values.items[i]);
        put_varint(&bytes, field->number * 8 + 2);
        put_varint(&bytes, (int64_t)payload.count);
        bytes_add(&bytes, payload);
    } else for (size_t i = 0; i < values.count; i++) {
        put_varint(&bytes, field->number * 8 + wire_type(field->type));
        encode_element(&bytes, field->type, values.items[i]);
    }
    return bytes;
}
static Bytes encode(Message *message) {
    Bytes bytes = {0};
    for (size_t i = 0; i < message->type->fields.count; i++) bytes_add(&bytes, encode_field(message->type->fields.items[i], message->fields[i]));
    for (size_t i = 0; i < message->unknown.count; i++) {
        Unknown unknown = message->unknown.items[i];
        put_varint(&bytes, unknown.number * 8 + unknown.wire);
        if (!unknown.wire) put_varint(&bytes, unknown.integer);
        else {
            if (unknown.wire == 2) put_varint(&bytes, (int64_t)unknown.bytes.count);
            bytes_add(&bytes, unknown.bytes);
        }
    }
    return bytes;
}

static void quoted(Text *text, Bytes bytes, bool json) {
    text_char(text, '"');
    for (size_t i = 0; i < bytes.count; i++) {
        unsigned char c = bytes.items[i];
        if (c == '"') text_add(text, "\\\"");
        else if (c == '\\') text_add(text, "\\\\");
        else if (c == '\n') text_add(text, "\\n");
        else if (c == '\t') text_add(text, "\\t");
        else if (c >= 32 && c <= 126) text_char(text, (char)c);
        else text_add(text, format(json ? "\\u00%02x" : "\\x%02x", (unsigned)c));
    }
    text_char(text, '"');
}
static void base64(Text *text, Bytes bytes) {
    static const char alphabet[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    text_char(text, '"');
    for (size_t i = 0; i < bytes.count; i += 3) {
        unsigned number = (unsigned)bytes.items[i] * 65536;
        if (i + 1 < bytes.count) number += (unsigned)bytes.items[i + 1] * 256;
        if (i + 2 < bytes.count) number += bytes.items[i + 2];
        text_char(text, alphabet[number / 262144]);
        text_char(text, alphabet[number / 4096 % 64]);
        text_char(text, i + 1 < bytes.count ? alphabet[number / 64 % 64] : '=');
        text_char(text, i + 2 < bytes.count ? alphabet[number % 64] : '=');
    }
    text_char(text, '"');
}
static void value_notation(Text *text, Type *type, Value *value, bool json);
static void sequence_notation(Text *text, Type *type, Values values, bool json) {
    text_char(text, '[');
    for (size_t i = 0; i < values.count; i++) {
        if (i) text_add(text, json ? "," : ", ");
        value_notation(text, type, values.items[i], json);
    }
    text_char(text, ']');
}
static void message_notation(Text *text, Message *message, bool json) {
    text_char(text, '{');
    bool first = true;
    for (size_t i = 0; i < message->type->fields.count; i++) {
        Values values = message->fields[i];
        if (!values.count) continue;
        Field *field = message->type->fields.items[i];
        if (!first) text_add(text, json ? "," : ", ");
        first = false;
        if (json) {
            text_char(text, '"');
            for (const char *p = field->name; *p; p++) {
                char c = *p;
                if (c == '_') { c = *++p; if (c >= 'a' && c <= 'z') c -= 'a' - 'A'; }
                text_char(text, c);
            }
            text_add(text, "\":");
        } else { text_add(text, field->name); text_add(text, ": "); }
        if (field->repeated) sequence_notation(text, field->type, values, json);
        else value_notation(text, field->type, values.items[0], json);
    }
    text_char(text, '}');
}
static void value_notation(Text *text, Type *type, Value *value, bool json) {
    if (!value) { text_add(text, "(none)"); return; }
    if (type->kind == MESSAGE) message_notation(text, value->as.message, json);
    else if (type->kind == STRING) quoted(text, value->as.binary, json);
    else if (type->kind == BYTES) {
        if (json) base64(text, value->as.binary);
        else text_add(text, hex(value->as.binary, true));
    } else if (type->kind == BOOL) text_add(text, value->as.boolean ? "true" : "false");
    else if (type->kind == ENUM) text_add(text, format(json ? "\"%s\"" : "%s", enum_number(type, value->as.number)->name));
    else {
        bool quote = json && (type->kind == UINT64 || type->kind == SINT64 || type->kind == FIXED64);
        if (quote) text_char(text, '"');
        text_add(text, format("%" PRId64, value->as.number));
        if (quote) text_char(text, '"');
    }
}
static char *notation(Type *type, Value *value) {
    Text text = {0};
    value_notation(&text, type, value, false);
    return text.data;
}
static const char *wire_name(int wire) {
    switch (wire) { case 0: return "varint"; case 1: return "i64"; case 2: return "len"; default: return "i32"; }
}
static void contents(Message *message, int depth) {
    for (size_t i = 0; i < message->type->fields.count; i++) {
        Field *field = message->type->fields.items[i];
        Values values = message->fields[i];
        for (size_t j = 0; j < values.count; j++) {
            Value *value = values.items[j];
            if (field->type->kind == MESSAGE) {
                line(format("%*s%s {", depth * 2, "", field->name));
                contents(value->as.message, depth + 1);
                line(format("%*s}", depth * 2, ""));
            } else line(format("%*s%s: %s", depth * 2, "", field->name, notation(field->type, value)));
        }
    }
    for (size_t i = 0; i < message->unknown.count; i++) {
        Unknown unknown = message->unknown.items[i];
        char *raw = unknown.wire ? hex(unknown.bytes, true) : format("%" PRId64, unknown.integer);
        line(format("%*s%" PRId64 ": %s %s", depth * 2, "", unknown.number, wire_name(unknown.wire), raw));
    }
}
static void text_message(Message *message) {
    line(format("%s {", message->type->name)); contents(message, 1); line("}");
}
static void required(Message *message, const char *prefix) {
    for (size_t i = 0; i < message->type->fields.count; i++) {
        Field *field = message->type->fields.items[i];
        Values values = message->fields[i];
        char *path = format("%s%s", prefix, field->name);
        if (field->required && !values.count) fail("missing required field %s", path);
        if (field->type->kind == MESSAGE) for (size_t j = 0; j < values.count; j++) {
            char *next = field->repeated ? format("%s[%zu].", path, j) : format("%s.", path);
            required(values.items[j]->as.message, next);
        }
    }
}

typedef struct { int64_t integer; Bytes bytes; size_t position, payload; } Raw;
typedef struct { Bytes data; bool explain; } Decoder;
static int64_t read_varint(Decoder *decoder, size_t *position, size_t end) {
    size_t start = *position;
    int64_t number = 0, factor = 1;
    for (int i = 0; i < 8; i++) {
        if (*position >= end) byte_error("truncated varint", start);
        unsigned byte = decoder->data.items[(*position)++];
        number += (byte % 128) * factor;
        if (byte < 128) {
            if (number > MAX_UNSIGNED) byte_error("varint too large", start);
            return number;
        }
        if (i == 7) byte_error("varint too long", start);
        factor *= 128;
    }
    return 0;
}
static Raw read_raw(Decoder *decoder, int wire, size_t *position, size_t end) {
    Raw raw = {.position = *position};
    if (!wire) { raw.integer = read_varint(decoder, position, end); return raw; }
    size_t length;
    if (wire == 2) {
        int64_t value = read_varint(decoder, position, end);
        if (value > (int64_t)(end - *position)) byte_error("length past end", raw.position);
        length = (size_t)value;
    } else {
        length = wire == 1 ? 8 : 4;
        if (end - *position < length) byte_error(wire == 1 ? "truncated i64" : "truncated i32", raw.position);
    }
    raw.payload = *position;
    raw.bytes.items = decoder->data.items + *position;
    raw.bytes.count = length;
    *position += length;
    return raw;
}
static Value *convert(Type *type, Raw raw) {
    if (type->kind == STRING || type->kind == BYTES) {
        if (type->kind == STRING) for (size_t i = 0; i < raw.bytes.count; i++)
            if (raw.bytes.items[i] >= 128) byte_error("invalid string", raw.payload + i);
        Value *value = new_value(BINARY_VALUE); value->as.binary = raw.bytes; return value;
    }
    int64_t number = raw.integer;
    int wire = wire_type(type);
    if (wire == 1 || wire == 5) {
        if (wire == 1 && (raw.bytes.items[7] || raw.bytes.items[6] >= 32)) byte_error("value out of range", raw.position);
        number = 0;
        for (size_t i = raw.bytes.count; i-- > 0;) number = number * 256 + raw.bytes.items[i];
    }
    if (type->kind == SINT32 || type->kind == SINT64) number = unzigzag(number);
    if (type->kind == SFIXED32 && number >= INT64_C(2147483648)) number -= INT64_C(4294967296);
    if (!in_range(type, number) || (type->kind == BOOL && number > 1)) byte_error("value out of range", raw.position);
    if (type->kind == ENUM && !enum_number(type, number)) byte_error("unknown enum number", raw.position);
    Value *value = new_value(type->kind == BOOL ? BOOLEAN_VALUE : NUMBER_VALUE);
    if (type->kind == BOOL) value->as.boolean = number != 0;
    else value->as.number = number;
    return value;
}
static Message *read_message(Decoder *decoder, Type *type, size_t position, size_t end, int depth) {
    Message *message = new_message(type);
    while (position < end) {
        size_t start = position;
        int64_t tag = read_varint(decoder, &position, end), number = tag / 8;
        int wire = (int)(tag % 8);
        if (!number) byte_error("invalid field number", start);
        if (wire != 0 && wire != 1 && wire != 2 && wire != 5) byte_error("invalid wire type", start);
        Field *field = field_number(type, number);
        bool packed = field && field->repeated && wire_type(field->type) != 2 && wire == 2;
        if (field && wire != wire_type(field->type) && !packed) byte_error("wire type mismatch", start);
        Raw raw = read_raw(decoder, wire, &position, end);
        Text explanation = {0};
        if (decoder->explain) {
            text_add(&explanation, format("%*s%zu %" PRId64 " %s %s", depth * 2, "", start, number, field ? field->name : "?", wire_name(wire)));
            if (wire == 2) text_add(&explanation, format(" %zu", raw.bytes.count));
        }
        if (!field) {
            if (decoder->explain) {
                text_add(&explanation, format(" %s", wire ? hex(raw.bytes, true) : format("%" PRId64, raw.integer)));
                line(explanation.data);
            } else PUSH(message->unknown, ((Unknown){number, raw.integer, wire, raw.bytes}));
            continue;
        }
        Values values = {0};
        if (field->type->kind == MESSAGE) {
            if (decoder->explain) line(explanation.data);
            Message *child = read_message(decoder, field->type, raw.payload, raw.payload + raw.bytes.count, depth + 1);
            PUSH(values, message_value(child));
        } else {
            if (packed) {
                size_t element = raw.payload, limit = raw.payload + raw.bytes.count;
                while (element < limit) {
                    Raw item = read_raw(decoder, wire_type(field->type), &element, limit);
                    PUSH(values, convert(field->type, item));
                }
            } else PUSH(values, convert(field->type, raw));
            if (decoder->explain) {
                if (packed) text_add(&explanation, " packed");
                for (size_t i = 0; i < values.count; i++) text_add(&explanation, format(" %s", notation(field->type, values.items[i])));
                line(explanation.data);
            }
        }
        if (!decoder->explain) apply(message, field, values);
    }
    return message;
}
static Message *decode(Type *type, Bytes bytes, bool explain) {
    Decoder decoder = {bytes, explain};
    Message *message = read_message(&decoder, type, 0, bytes.count, 0);
    if (!explain) required(message, "");
    else if (!bytes.count) line("(empty)");
    return message;
}

typedef enum { SYMBOL_TOKEN, INTEGER_TOKEN, NAME_TOKEN, STRING_TOKEN, BYTES_TOKEN, END_TOKEN } TokenKind;
typedef struct { TokenKind kind; size_t column; char symbol; char *name; int64_t number; Bytes bytes; } Token;
VECTOR(Token, Tokens);
typedef struct { Tokens tokens; size_t position; } Parser;
typedef enum { NO_SHAPE, MESSAGE_SHAPE, LIST_SHAPE, INTEGER_SHAPE, BOOLEAN_SHAPE, NAME_SHAPE, STRING_SHAPE, BYTES_SHAPE } Shape;
static bool digit(char c) { return c >= '0' && c <= '9'; }
static bool letter(char c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'); }
static Tokens tokenize(const char *source) {
    Tokens tokens = {0};
    size_t length = strlen(source), position = 0;
    while (position < length) {
        char c = source[position];
        if (c == ' ') { position++; continue; }
        size_t start = position++;
        Token token = {.column = start + 1};
        if (strchr("{}[]:,", c)) { token.kind = SYMBOL_TOKEN; token.symbol = c; }
        else if (c == '"') {
            token.kind = STRING_TOKEN;
            while (position < length && source[position] != '"') {
                unsigned char byte = (unsigned char)source[position++];
                if (byte == '\\') {
                    if (position == length) column_error("syntax error", start + 1);
                    char escaped = source[position++];
                    if (escaped == '"' || escaped == '\\') byte = (unsigned char)escaped;
                    else if (escaped == 'n') byte = '\n';
                    else if (escaped == 't') byte = '\t';
                    else if (escaped == 'x' && position + 1 < length && hex_digit(source[position]) >= 0 && hex_digit(source[position]) < 8 && hex_digit(source[position + 1]) >= 0) {
                        byte = (unsigned char)(hex_digit(source[position]) * 16 + hex_digit(source[position + 1])); position += 2;
                    } else column_error("syntax error", start + 1);
                }
                PUSH(token.bytes, byte);
            }
            if (position == length) column_error("syntax error", start + 1);
            position++;
        } else if (c == '<') {
            token.kind = BYTES_TOKEN;
            const char *close = strchr(source + position, '>');
            if (!close || (size_t)(close - source - position) % 2) column_error("syntax error", start + 1);
            size_t end = (size_t)(close - source);
            while (position < end) {
                int high = hex_digit(source[position]), low = hex_digit(source[position + 1]);
                if (high < 0 || low < 0) column_error("syntax error", start + 1);
                PUSH(token.bytes, (unsigned char)(high * 16 + low)); position += 2;
            }
            position++;
        } else if (c == '-' || digit(c)) {
            token.kind = INTEGER_TOKEN;
            position = start + (c == '-');
            if (position == length || !digit(source[position])) column_error("syntax error", start + 1);
            while (position < length && digit(source[position])) token.number = token.number * 10 + source[position++] - '0';
            if (c == '-') token.number = -token.number;
        } else if (letter(c) || c == '_') {
            token.kind = NAME_TOKEN;
            while (position < length && (letter(source[position]) || digit(source[position]) || source[position] == '_')) position++;
            token.name = copy_range(source + start, position - start);
        } else column_error("syntax error", start + 1);
        PUSH(tokens, token);
    }
    PUSH(tokens, ((Token){.kind = END_TOKEN, .column = length + 1}));
    return tokens;
}
static Token *peek(Parser *parser) { return &parser->tokens.items[parser->position]; }
static bool symbol(Parser *parser, char c) { return peek(parser)->kind == SYMBOL_TOKEN && peek(parser)->symbol == c; }
static void expect(Parser *parser, char c) {
    if (!symbol(parser, c)) column_error("syntax error", peek(parser)->column);
    parser->position++;
}
static void expect_end(Parser *parser) { if (peek(parser)->kind != END_TOKEN) column_error("syntax error", peek(parser)->column); }
static Shape shape(Token *token) {
    switch (token->kind) {
        case INTEGER_TOKEN: return INTEGER_SHAPE;
        case NAME_TOKEN: return !strcmp(token->name, "true") || !strcmp(token->name, "false") ? BOOLEAN_SHAPE : NAME_SHAPE;
        case STRING_TOKEN: return STRING_SHAPE;
        case BYTES_TOKEN: return BYTES_SHAPE;
        case SYMBOL_TOKEN: return token->symbol == '{' ? MESSAGE_SHAPE : token->symbol == '[' ? LIST_SHAPE : NO_SHAPE;
        default: return NO_SHAPE;
    }
}
static void expect_shape(Parser *parser, Shape wanted) {
    Shape actual = shape(peek(parser));
    if (actual == NO_SHAPE) column_error("syntax error", peek(parser)->column);
    if (actual != wanted) column_error("type mismatch", peek(parser)->column);
}
static Message *parse_message(Parser *parser, Type *type);
static Value *parse_element(Parser *parser, Type *type) {
    Shape wanted = type->kind == MESSAGE ? MESSAGE_SHAPE : type->kind == STRING ? STRING_SHAPE : type->kind == BYTES ? BYTES_SHAPE : type->kind == BOOL ? BOOLEAN_SHAPE : type->kind == ENUM ? NAME_SHAPE : INTEGER_SHAPE;
    expect_shape(parser, wanted);
    if (wanted == MESSAGE_SHAPE) return message_value(parse_message(parser, type));
    Token token = *peek(parser); parser->position++;
    Value *value;
    if (wanted == STRING_SHAPE || wanted == BYTES_SHAPE) {
        value = new_value(BINARY_VALUE); value->as.binary = token.bytes;
    } else if (wanted == BOOLEAN_SHAPE) {
        value = new_value(BOOLEAN_VALUE); value->as.boolean = !strcmp(token.name, "true");
    } else {
        value = new_value(NUMBER_VALUE);
        if (wanted == NAME_SHAPE) {
            EnumValue *item = enum_name(type, token.name);
            if (!item) column_error("unknown enum value", token.column);
            value->as.number = item->number;
        } else {
            if (!in_range(type, token.number)) column_error("out of range", token.column);
            value->as.number = token.number;
        }
    }
    return value;
}
static Values parse_field(Parser *parser, Field *field) {
    Values values = {0};
    if (!field->repeated) { PUSH(values, parse_element(parser, field->type)); return values; }
    expect_shape(parser, LIST_SHAPE); expect(parser, '[');
    if (!symbol(parser, ']')) {
        PUSH(values, parse_element(parser, field->type));
        while (symbol(parser, ',')) { parser->position++; PUSH(values, parse_element(parser, field->type)); }
    }
    expect(parser, ']');
    return values;
}
static Message *parse_message(Parser *parser, Type *type) {
    expect(parser, '{');
    Message *message = new_message(type);
    bool *seen = allocate(type->fields.count * sizeof(*seen));
    if (!symbol(parser, '}')) for (;;) {
        Token *token = peek(parser);
        if (token->kind != NAME_TOKEN) column_error("syntax error", token->column);
        Field *field = field_name(type, token->name);
        if (!field) column_error("unknown field", token->column);
        if (seen[field->index]) column_error("duplicate field", token->column);
        if (field->group) for (size_t i = 0; i < type->fields.count; i++) {
            Field *other = type->fields.items[i];
            if (seen[i] && other->group && !strcmp(other->group, field->group)) column_error("oneof conflict", token->column);
        }
        parser->position++; seen[field->index] = true;
        expect(parser, ':'); message->fields[field->index] = parse_field(parser, field);
        if (!symbol(parser, ',')) break;
        parser->position++;
    }
    size_t closing = peek(parser)->column;
    expect(parser, '}');
    for (size_t i = 0; i < type->fields.count; i++) if (type->fields.items[i]->required && !seen[i])
        column_error(format("missing required field %s", type->fields.items[i]->name), closing);
    return message;
}

typedef struct { Field *field; size_t index; bool indexed; } Segment;
VECTOR(Segment, Path);
static Path parse_path(Type *type, const char *source) {
    Path path = {0};
    const char *start = source;
    for (;;) {
        const char *end = strchr(start, '.');
        if (!end) end = start + strlen(start);
        if (start == end) fail("invalid path");
        const char *bracket = memchr(start, '[', (size_t)(end - start));
        Segment segment = {0};
        segment.field = field_name(type, copy_range(start, (size_t)((bracket ? bracket : end) - start)));
        if (!segment.field) fail("invalid path");
        if (bracket) {
            size_t digits = (size_t)(end - bracket - 2);
            if (end[-1] != ']' || digits < 1 || digits > 6 || !segment.field->repeated) fail("invalid path");
            for (const char *p = bracket + 1; p < end - 1; p++) {
                if (!digit(*p)) fail("invalid path");
                segment.index = segment.index * 10 + (size_t)(*p - '0');
            }
            segment.indexed = true;
        }
        PUSH(path, segment);
        if (!*end) break;
        if (segment.field->type->kind != MESSAGE || (segment.field->repeated && !segment.indexed)) fail("invalid path");
        type = segment.field->type;
        start = end + 1;
    }
    return path;
}
static void get_path(Message *message, Path path) {
    Text text = {0};
    for (size_t i = 0; i < path.count; i++) {
        Segment segment = path.items[i];
        Values values = message ? message->fields[segment.field->index] : (Values){0};
        if (i + 1 == path.count && segment.field->repeated && !segment.indexed) {
            sequence_notation(&text, segment.field->type, values, false); break;
        }
        Value *value = segment.index < values.count ? values.items[segment.index] : NULL;
        if (i + 1 == path.count) { value_notation(&text, segment.field->type, value, false); break; }
        message = value ? value->as.message : NULL;
    }
    line(text.data);
}
static void edit_path(Message *message, Path path, const Values *replacement) {
    for (size_t i = 0; i < path.count; i++) {
        Segment segment = path.items[i];
        Field *field = segment.field;
        Values *values = &message->fields[field->index];
        if (i + 1 == path.count) {
            if (segment.indexed) {
                if (segment.index >= values->count) { if (replacement) fail("index out of range"); return; }
                if (replacement) values->items[segment.index] = replacement->items[0];
                else {
                    memmove(values->items + segment.index, values->items + segment.index + 1, (values->count - segment.index - 1) * sizeof(*values->items));
                    values->count--;
                }
            } else if (replacement) { choose(message, field); *values = *replacement; }
            else values->count = 0;
            return;
        }
        if (segment.index >= values->count) {
            if (!replacement) return;
            if (segment.indexed) fail("index out of range");
            choose(message, field);
            PUSH(*values, message_value(new_message(field->type)));
        }
        message = values->items[segment.index]->as.message;
    }
}
static bool equal_value(Value *a, Value *b) {
    if (!a || !b) return a == b;
    switch (a->kind) {
        case NUMBER_VALUE: return a->as.number == b->as.number;
        case BOOLEAN_VALUE: return a->as.boolean == b->as.boolean;
        case BINARY_VALUE: return a->as.binary.count == b->as.binary.count && (!a->as.binary.count || !memcmp(a->as.binary.items, b->as.binary.items, a->as.binary.count));
        default: return false;
    }
}
static void difference(Message *a, Message *b, const char *prefix) {
    for (size_t i = 0; i < a->type->fields.count; i++) {
        Field *field = a->type->fields.items[i];
        Values x = a->fields[i], y = b->fields[i];
        size_t count = x.count > y.count ? x.count : y.count;
        for (size_t j = 0; j < count; j++) {
            char *path = field->repeated ? format("%s%s[%zu]", prefix, field->name, j) : format("%s%s", prefix, field->name);
            Value *left = j < x.count ? x.items[j] : NULL, *right = j < y.count ? y.items[j] : NULL;
            if (left && right && field->type->kind == MESSAGE) difference(left->as.message, right->as.message, format("%s.", path));
            else if (!equal_value(left, right)) line(format("%s: %s -> %s", path, notation(field->type, left), notation(field->type, right)));
        }
    }
}
static void schema_tree(Type *type, Type **chain, int depth) {
    chain[depth - 1] = type;
    for (size_t i = 0; i < type->fields.count; i++) {
        Field *field = type->fields.items[i];
        Text text = {0};
        text_add(&text, format("%*s%" PRId64 " %s: ", depth * 2, "", field->number, field->name));
        if (field->required) text_add(&text, "required ");
        else if (field->packed) text_add(&text, "repeated packed ");
        else if (field->repeated) text_add(&text, "repeated ");
        else if (field->group) text_add(&text, format("oneof %s ", field->group));
        text_add(&text, field->type->name);
        if (field->type->kind == ENUM) {
            text_add(&text, " (");
            for (size_t j = 0; j < field->type->values.count; j++) {
                EnumValue value = field->type->values.items[j];
                if (j) text_add(&text, ", ");
                text_add(&text, format("%s=%" PRId64, value.name, value.number));
            }
            text_char(&text, ')');
        }
        bool recursive = false;
        if (field->type->kind == MESSAGE) for (int j = 0; j < depth; j++) if (chain[j] == field->type) recursive = true;
        if (recursive) text_add(&text, " (recursive)");
        line(text.data);
        if (field->type->kind == MESSAGE && !recursive) schema_tree(field->type, chain, depth + 1);
    }
}
static Words split_words(const char *source) {
    Words words = {0};
    const char *start = source;
    for (;;) {
        const char *end = strchr(start, ' ');
        if (!end) end = start + strlen(start);
        PUSH(words, copy_range(start, (size_t)(end - start)));
        if (!*end) return words;
        start = end + 1;
    }
}
static const char *after_spaces(const char *source, int count) {
    while (count--) source = strchr(source, ' ') + 1;
    return source;
}
static bool integer(const char *source, int64_t *value) {
    bool negative = *source == '-';
    if (negative) source++;
    size_t length = strlen(source);
    if (!length || length > 18) return false;
    int64_t number = 0;
    for (const char *p = source; *p; p++) { if (!digit(*p)) return false; number = number * 10 + *p - '0'; }
    *value = negative ? -number : number;
    return true;
}
static Bytes parse_hex(const char *source) {
    Bytes bytes = {0};
    if (!strcmp(source, "-")) return bytes;
    size_t length = strlen(source);
    if (!length || length % 2) fail("invalid hex");
    for (size_t i = 0; i < length; i += 2) {
        int high = hex_digit(source[i]), low = hex_digit(source[i + 1]);
        if (high < 0 || low < 0) fail("invalid hex");
        PUSH(bytes, (unsigned char)(high * 16 + low));
    }
    return bytes;
}
typedef enum { VARINT_COMMAND, ZIGZAG_COMMAND, SCHEMA_COMMAND, ENCODE_COMMAND, SIZE_COMMAND, DECODE_COMMAND, LITERAL_COMMAND, JSON_COMMAND, CANON_COMMAND, EXPLAIN_COMMAND, GET_COMMAND, PATCH_COMMAND, CLEAR_COMMAND, MERGE_COMMAND, DIFF_COMMAND } Command;
typedef struct { const char *name; size_t words; bool minimum; } Form;
static const Form forms[] = {
    {"VARINT", 2, false}, {"ZIGZAG", 2, false}, {"SCHEMA", 2, false}, {"ENCODE", 3, true}, {"SIZE", 3, true},
    {"DECODE", 3, false}, {"LITERAL", 3, false}, {"JSON", 3, false}, {"CANON", 3, false}, {"EXPLAIN", 3, false},
    {"GET", 4, false}, {"PATCH", 5, true}, {"CLEAR", 4, false}, {"MERGE", 4, false}, {"DIFF", 4, false}
};
static void execute(const char *source) {
    Words words = split_words(source);
    size_t index = 0;
    while (index < sizeof(forms) / sizeof(*forms) && strcmp(forms[index].name, words.items[0])) index++;
    if (index == sizeof(forms) / sizeof(*forms)) fail("unknown command");
    Form form = forms[index];
    if (words.count < form.words || (!form.minimum && words.count != form.words)) fail("wrong number of arguments");
    Command command = (Command)index;
    if (command == VARINT_COMMAND || command == ZIGZAG_COMMAND) {
        int64_t number;
        if (!integer(words.items[1], &number)) fail("invalid number");
        if (command == VARINT_COMMAND ? number < 0 || number > MAX_UNSIGNED : number < -INT64_C(4503599627370496) || number > INT64_C(4503599627370495)) fail("invalid number");
        if (command == ZIGZAG_COMMAND) number = zigzag(number);
        Bytes bytes = {0}; put_varint(&bytes, number);
        line(command == VARINT_COMMAND ? hex(bytes, false) : format("%" PRId64 " %s", number, hex(bytes, false)));
        return;
    }
    Type *type = find_type(words.items[1]);
    if (!type || type->kind != MESSAGE) fail("unknown message type");
    if (command == SCHEMA_COMMAND) { Type *chain[31]; line(type->name); schema_tree(type, chain, 1); return; }
    if (command == ENCODE_COMMAND || command == SIZE_COMMAND) {
        Parser parser = {.tokens = tokenize(after_spaces(source, 2))};
        Message *message = parse_message(&parser, type); expect_end(&parser);
        Bytes bytes = encode(message);
        if (command == ENCODE_COMMAND) line(hex(bytes, false));
        else {
            Text text = {0}; text_add(&text, format("%zu", bytes.count));
            for (size_t i = 0; i < type->fields.count; i++) if (message->fields[i].count)
                text_add(&text, format(" %s=%zu", type->fields.items[i]->name, encode_field(type->fields.items[i], message->fields[i]).count));
            line(text.data);
        }
        return;
    }
    Bytes first = parse_hex(words.items[2]), second = {0};
    if (command == MERGE_COMMAND || command == DIFF_COMMAND) second = parse_hex(words.items[3]);
    Path path = {0};
    if (command == GET_COMMAND || command == PATCH_COMMAND || command == CLEAR_COMMAND) path = parse_path(type, words.items[3]);
    if (command == DIFF_COMMAND) {
        error_suffix = " in first"; Message *a = decode(type, first, false);
        error_suffix = " in second"; Message *b = decode(type, second, false);
        error_suffix = "";
        difference(a, b, ""); if (!output.length) line("SAME");
        return;
    }
    if (command == MERGE_COMMAND) bytes_add(&first, second);
    Message *message = decode(type, first, command == EXPLAIN_COMMAND);
    switch (command) {
        case DECODE_COMMAND: case MERGE_COMMAND: text_message(message); break;
        case LITERAL_COMMAND: case JSON_COMMAND: {
            Text text = {0}; message_notation(&text, message, command == JSON_COMMAND); line(text.data); break;
        }
        case CANON_COMMAND: line(hex(encode(message), false)); break;
        case GET_COMMAND: get_path(message, path); break;
        case PATCH_COMMAND: {
            Parser parser = {.tokens = tokenize(after_spaces(source, 4))};
            Segment last = path.items[path.count - 1];
            Values replacement = {0};
            if (last.field->repeated && !last.indexed) replacement = parse_field(&parser, last.field);
            else PUSH(replacement, parse_element(&parser, last.field->type));
            expect_end(&parser);
            edit_path(message, path, &replacement); required(message, ""); line(hex(encode(message), false)); break;
        }
        case CLEAR_COMMAND: edit_path(message, path, NULL); required(message, ""); line(hex(encode(message), false)); break;
        default: break;
    }
}
static bool read_line(char *buffer, size_t capacity) {
    if (!fgets(buffer, (int)capacity, stdin)) return false;
    buffer[strcspn(buffer, "\r\n")] = '\0';
    return true;
}
static int compare_fields(const void *a, const void *b) {
    int64_t x = (*(Field *const *)a)->number, y = (*(Field *const *)b)->number;
    return (x > y) - (x < y);
}
static int compare_enum_values(const void *a, const void *b) {
    int64_t x = ((const EnumValue *)a)->number, y = ((const EnumValue *)b)->number;
    return (x > y) - (x < y);
}
static void read_schema(void) {
    static const char *names[] = {"uint32", "uint64", "sint32", "sint64", "bool", "fixed32", "sfixed32", "fixed64", "string", "bytes"};
    for (size_t i = 0; i < sizeof(names) / sizeof(*names); i++) {
        Type *type = allocate(sizeof(*type)); type->name = copy_range(names[i], strlen(names[i])); type->kind = (Kind)i; PUSH(types, type);
    }
    char buffer[1002];
    Type *current = NULL;
    while (read_line(buffer, sizeof(buffer)) && strcmp(buffer, "END SCHEMA")) {
        Words words = split_words(buffer);
        if (!strcmp(words.items[0], "ENUM") || !strcmp(words.items[0], "MESSAGE")) {
            current = allocate(sizeof(*current)); current->name = words.items[1];
            current->kind = !strcmp(words.items[0], "ENUM") ? ENUM : MESSAGE;
            PUSH(types, current);
        } else if (!strcmp(words.items[0], "VALUE")) {
            PUSH(current->values, ((EnumValue){words.items[1], strtoll(words.items[2], NULL, 10)}));
        } else if (!strcmp(words.items[0], "FIELD")) {
            Field *field = allocate(sizeof(*field));
            field->number = strtoll(words.items[1], NULL, 10); field->type_name = words.items[2]; field->name = words.items[3];
            if (words.count > 4) {
                field->required = !strcmp(words.items[4], "REQUIRED"); field->repeated = !strcmp(words.items[4], "REPEATED");
                field->packed = field->repeated && words.count == 6;
                if (!strcmp(words.items[4], "ONEOF")) field->group = words.items[5];
            }
            PUSH(current->fields, field);
        }
    }
    for (size_t i = 0; i < types.count; i++) {
        Type *type = types.items[i];
        if (type->fields.count > 1) qsort(type->fields.items, type->fields.count, sizeof(*type->fields.items), compare_fields);
        if (type->values.count > 1) qsort(type->values.items, type->values.count, sizeof(*type->values.items), compare_enum_values);
        for (size_t j = 0; j < type->fields.count; j++) {
            Field *field = type->fields.items[j]; field->index = j; field->type = find_type(field->type_name);
        }
    }
}
int main(void) {
    arena = &schema_arena; read_schema();
    char buffer[1002];
    if (!read_line(buffer, sizeof(buffer))) { release(&schema_arena); return 0; }
    int count = (int)strtol(buffer, NULL, 10);
    for (int i = 0; i < count && read_line(buffer, sizeof(buffer)); i++) {
        arena = &command_arena; output = (Text){0}; error_suffix = "";
        if (!setjmp(recovery)) { execute(buffer); if (output.data) fputs(output.data, stdout); }
        else printf("ERROR %s\n", error_message);
        release(&command_arena);
    }
    release(&schema_arena);
    return 0;
}
