#include "lexer.h"

LogicalLines lex_document(const char *text) {
    Strings physical = file_lines(text);
    LogicalLines result = {0};
    size_t index = 0;
    while (index < physical.len) {
        LogicalLine line = {.number = (int)index + 1};
        const char *source = physical.data[index++];
        size_t position = 0;
        bool quoted = false;
        Buffer current = {0};
        while (source[position]) {
            char ch = source[position];
            if (ch == '\\' && source[position + 1] == '\0') {
                source = physical.data[index++];
                while (*source == ' ') ++source;
                position = 0;
            } else if (quoted && ch == '\\') {
                char next = source[position + 1], decoded = '\0';
                switch (next) {
                    case '\\': decoded = '\\'; break;
                    case '"': decoded = '"'; break;
                    case 'n': decoded = '\n'; break;
                    case 't': decoded = '\t'; break;
                    case '$': decoded = LITERAL_DOLLAR; break;
                    default:
                        if (!line.code) {
                            line.code = "E_ESCAPE";
                            line.message = format("invalid escape sequence \\%c", next);
                        }
                }
                if (decoded) buffer_char(&current, decoded);
                position += 2;
            } else if (ch == '"') {
                Segment segment = {buffer_result(&current), quoted};
                PUSH(line.segments, segment);
                current = (Buffer){0};
                quoted = !quoted;
                ++position;
            } else if (!quoted && (ch == ';' || ch == '#')) {
                break;
            } else {
                buffer_char(&current, ch);
                ++position;
            }
        }
        if (quoted && !line.code) {
            line.code = "E_UNTERMINATED";
            line.message = "unterminated string";
        }
        Segment final = {buffer_result(&current), quoted};
        PUSH(line.segments, final);
        PUSH(result, line);
    }
    return result;
}
