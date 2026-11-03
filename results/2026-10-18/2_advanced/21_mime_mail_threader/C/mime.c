#include "mail.h"

int hex_value(char character) {
    if (character >= '0' && character <= '9') return character - '0';
    if (character >= 'A' && character <= 'F') return character - 'A' + 10;
    if (character >= 'a' && character <= 'f') return character - 'a' + 10;
    return -1;
}

Bytes strict_base64(const char *text) {
    size_t size = strlen(text), end = size;
    Bytes result = {0};
    if (size % 4) return result;
    while (end && text[end - 1] == '=') --end;
    if (size - end >= 3) return result;
    result.data = allocate(size + 1);
    unsigned int buffer = 0;
    int bits = 0;
    const char *alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    for (size_t i = 0; i < end; ++i) {
        const char *position = strchr(alphabet, text[i]);
        if (!position) return (Bytes){0};
        buffer = (buffer << 6) | (unsigned int)(position - alphabet);
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            result.data[result.size++] = (unsigned char)(buffer >> bits);
            buffer &= (1u << bits) - 1;
        }
    }
    result.valid = true;
    return result;
}

char *decode_base64_body(const char *text) {
    Text compact = {0};
    for (const char *character = text; *character; ++character) if (!whitespace(*character) && *character != '\n') text_add(&compact, "%c", *character);
    Bytes bytes = strict_base64(compact.data ? compact.data : "");
    if (!bytes.valid) return NULL;
    char *result = allocate(bytes.size + 1);
    size_t length = 0;
    for (size_t i = 0; i < bytes.size; ++i) {
        int value = bytes.data[i];
        if (value == 13 && i + 1 < bytes.size && bytes.data[i + 1] == 10) { value = 10; ++i; }
        if (value != 9 && value != 10 && (value < 32 || value > 126)) return NULL;
        result[length++] = (char)value;
    }
    return result;
}

Decoded decode_quoted_printable(const char *text) {
    Lines lines = split_text(text, '\n');
    Text output = {0};
    bool error = false;
    for (int i = 0; i < lines.count; ++i) {
        char *line = rstrip(lines.items[i]);
        size_t size = strlen(line);
        bool soft = size && line[size - 1] == '=';
        if (soft) --size;
        for (size_t position = 0; position < size;) {
            int value = -1;
            if (line[position] == '=' && position + 2 < size) {
                int first = hex_value(line[position + 1]), second = hex_value(line[position + 2]);
                if (first >= 0 && second >= 0) value = 16 * first + second;
            }
            if (value == 9 || (value >= 32 && value <= 126)) { text_add(&output, "%c", value); position += 3; }
            else {
                error |= line[position] == '=';
                text_add(&output, "%c", line[position++]);
            }
        }
        if (!soft && i + 1 < lines.count) text_add(&output, "\n");
    }
    return (Decoded){output.data ? output.data : "", error};
}
