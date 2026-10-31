#include "mail.h"

Header parse_fields(SourceLines lines) {
    Header header = {0};
    header.fields = allocate((size_t)lines.count * sizeof(Field));
    header.invalid = allocate((size_t)lines.count * sizeof(int));
    bool in_field = false;
    for (int i = 0; i < lines.count; ++i) {
        char *text = lines.items[i].text;
        if (whitespace(text[0])) {
            if (in_field) header.fields[header.count - 1].value = format("%s%s", header.fields[header.count - 1].value, text);
            else header.invalid[header.invalid_count++] = lines.items[i].number;
            continue;
        }
        char *colon = strchr(text, ':');
        in_field = colon && colon != text;
        if (in_field) for (char *character = text; character < colon; ++character) if ((unsigned char)*character < 33 || (unsigned char)*character > 126) in_field = false;
        if (in_field) header.fields[header.count++] = (Field){lowercase(slice(text, 0, (size_t)(colon - text))), colon + 1};
        else header.invalid[header.invalid_count++] = lines.items[i].number;
    }
    for (int i = 0; i < header.count; ++i) header.fields[i].value = strip(header.fields[i].value);
    return header;
}

char *header_value(const Header *header, const char *name) {
    for (int i = 0; i < header->count; ++i) if (equal_case(header->fields[i].name, name)) return header->fields[i].value;
    return NULL;
}

int header_count(const Header *header, const char *name) {
    int count = 0;
    for (int i = 0; i < header->count; ++i) count += equal_case(header->fields[i].name, name);
    return count;
}

char *remove_comments(const char *text) {
    Text output = {0};
    int depth = 0;
    for (size_t i = 0; text[i]; ++i) {
        char character = text[i];
        if (!depth) {
            if (character == '(') { depth = 1; text_add(&output, " "); }
            else text_add(&output, "%c", character);
        } else if (character == '\\') { if (text[i + 1]) ++i; }
        else if (character == '(') ++depth;
        else if (character == ')') --depth;
    }
    return depth ? NULL : output.data ? output.data : "";
}

static bool word_character(char character, bool mime) {
    if (mime) return (unsigned char)character >= 33 && (unsigned char)character <= 126 && !strchr("()<>@,;:\\\"/[]?=", character);
    return (character >= 'A' && character <= 'Z') || (character >= 'a' && character <= 'z') || (character >= '0' && character <= '9') || strchr("!#$%&'*+-/=?^_`{|}~", character);
}

Tokens tokenize(const char *text, bool mime) {
    Tokens result = {allocate((strlen(text) + 1) * sizeof(Token)), 0, false};
    const char *specials = mime ? "/;=" : "<>:;@,.";
    bool spaced = false;
    size_t position = 0;
    while (text[position]) {
        char character = text[position];
        if (whitespace(character)) { spaced = true; ++position; continue; }
        if (character == '(') {
            int depth = 1;
            ++position;
            while (text[position] && depth) {
                if (text[position] == '\\') {
                    ++position;
                    if (text[position]) ++position;
                } else {
                    if (text[position] == '(') ++depth;
                    else if (text[position] == ')') --depth;
                    ++position;
                }
            }
            if (depth) return result;
            spaced = true;
            continue;
        }
        Token token = {0, NULL, spaced};
        if (character == '"') {
            Text quoted = {0};
            ++position;
            while (text[position] && text[position] != '"') {
                if (text[position] == '\\') { ++position; if (!text[position]) return result; }
                text_add(&quoted, "%c", text[position++]);
            }
            if (!text[position]) return result;
            ++position;
            token.kind = QUOTED;
            token.text = quoted.data ? quoted.data : "";
        } else if (strchr(specials, character)) {
            token.kind = character;
            token.text = slice(text, position++, 1);
        } else if (word_character(character, mime)) {
            size_t start = position;
            while (text[position] && word_character(text[position], mime)) ++position;
            token.kind = WORD;
            token.text = slice(text, start, position - start);
        } else return result;
        result.items[result.count++] = token;
        spaced = false;
    }
    result.valid = true;
    return result;
}

DecodedWord decode_word(const char *word) {
    DecodedWord result = {(char *)word, false, false};
    size_t size = strlen(word);
    if (size < 4 || strncmp(word, "=?", 2) || strcmp(word + size - 2, "?=")) return result;
    Lines pieces = split_text(slice(word, 2, size - 4), '?');
    if (pieces.count != 3 || !pieces.items[0][0] || !pieces.items[1][0] || !pieces.items[2][0]) return result;
    result.error = true;
    if (!equal_case(pieces.items[0], "us-ascii")) return result;
    char *data = NULL;
    size_t length = 0;
    char *encoding = pieces.items[1], *encoded = pieces.items[2];
    if (!strcmp(encoding, "Q") || !strcmp(encoding, "q")) {
        data = allocate(strlen(encoded) + 1);
        for (size_t i = 0; encoded[i];) {
            int value = (unsigned char)encoded[i];
            if (encoded[i] == '_') { value = 32; ++i; }
            else if (encoded[i] == '=') {
                if (!encoded[i + 1] || !encoded[i + 2]) return result;
                int first = hex_value(encoded[i + 1]), second = hex_value(encoded[i + 2]);
                if (first < 0 || second < 0) return result;
                value = 16 * first + second;
                i += 3;
            } else ++i;
            if (value < 32 || value > 126) return result;
            data[length++] = (char)value;
        }
    } else if (!strcmp(encoding, "B") || !strcmp(encoding, "b")) {
        Bytes bytes = strict_base64(encoded);
        if (!bytes.valid) return result;
        for (size_t i = 0; i < bytes.size; ++i) if (bytes.data[i] < 32 || bytes.data[i] > 126) return result;
        data = (char *)bytes.data;
        length = bytes.size;
    } else return result;
    data[length] = '\0';
    return (DecodedWord){data, true, false};
}

Decoded decode_unstructured(const char *text) {
    Lines words = split_words(text);
    Text output = {0};
    bool previous = false, error = false;
    for (int i = 0; i < words.count; ++i) {
        DecodedWord word = decode_word(words.items[i]);
        if (i && !(word.decoded && previous)) text_add(&output, " ");
        text_add(&output, "%s", word.text);
        previous = word.decoded;
        error |= word.error;
    }
    return (Decoded){collapse_whitespace(output.data ? output.data : ""), error};
}

char *parameter(const Parameters *parameters, const char *name) {
    for (int i = 0; i < parameters->count; ++i) if (!strcmp(parameters->items[i].name, name)) return parameters->items[i].value;
    return NULL;
}

Parameters parse_parameters(const char *text, bool with_subtype) {
    Parameters result = {0};
    Tokens tokens = tokenize(text, true);
    if (!tokens.valid || !tokens.count || tokens.items[0].kind != WORD) return result;
    result.type = lowercase(tokens.items[0].text);
    result.subtype = "";
    int position = 1;
    if (with_subtype) {
        if (tokens.count < 3 || tokens.items[1].kind != '/' || tokens.items[2].kind != WORD) return result;
        result.subtype = lowercase(tokens.items[2].text);
        position = 3;
    }
    result.items = allocate((size_t)tokens.count * sizeof(Parameter));
    while (position < tokens.count) {
        if (position + 3 >= tokens.count || tokens.items[position].kind != ';' || tokens.items[position + 1].kind != WORD || tokens.items[position + 2].kind != '=' || (tokens.items[position + 3].kind != WORD && tokens.items[position + 3].kind != QUOTED)) return result;
        char *name = lowercase(tokens.items[position + 1].text);
        if (!parameter(&result, name)) result.items[result.count++] = (Parameter){name, tokens.items[position + 3].text};
        position += 4;
    }
    result.valid = true;
    return result;
}
