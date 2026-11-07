#include "sat.h"
Lines read_lines(const char *path) {
    Lines lines = {0};
    FILE *file = fopen(path, "rb");
    if (!file)
        return lines;
    char buffer[256];
    while (fgets(buffer, sizeof buffer, file)) {
        size_t length = strlen(buffer);
        if (length && buffer[length - 1] == '\n')
            buffer[--length] = 0;
        line_push(&lines, text(buffer));
    }
    fclose(file);
    return lines;
}
Lines words(const char *line) {
    Lines tokens = {0};
    const char *position = line;
    while (*position) {
        while (*position == ' ')
            ++position;
        if (!*position)
            break;
        const char *first = position;
        while (*position && *position != ' ')
            ++position;
        size_t length = (size_t)(position - first);
        char *token = resize(NULL, length + 1);
        memcpy(token, first, length);
        token[length] = 0;
        line_push(&tokens, token);
    }
    return tokens;
}
bool well_number(const char *value) {
    size_t length = strlen(value);
    if (!length || length > 6)
        return false;
    if (!strcmp(value, "0"))
        return true;
    if (value[0] < '1' || value[0] > '9')
        return false;
    for (size_t i = 0; i < length; ++i)
        if (value[i] < '0' || value[i] > '9')
            return false;
    return true;
}
CnfInput read_cnf(const char *name) {
    CnfInput out = {0};
    bool header = false;
    int declared = 0;
    Clause current = {0};
    char *path = format("input/%s", name);
    Lines lines = read_lines(path);
    free(path);
    for (int i = 0; i < lines.count && !out.error; ++i) {
        if (lines.data[i][0] == 'c')
            continue;
        Lines tokens = words(lines.data[i]);
        if (!tokens.count) {
            free_lines(&tokens);
            continue;
        }
        if (!strcmp(tokens.data[0], "p")) {
            if (header)
                out.error = format("duplicate header at line %d", i + 1);
            else if (tokens.count != 4 || strcmp(tokens.data[1], "cnf") || !well_number(tokens.data[2]) ||
                     !well_number(tokens.data[3]))
                out.error = format("bad header at line %d", i + 1);
            else {
                header = true;
                out.formula.variables = atoi(tokens.data[2]);
                declared = atoi(tokens.data[3]);
            }
        } else if (!header)
            out.error = text("missing header");
        else
            for (int t = 0; t < tokens.count && !out.error; ++t) {
                const char *token = tokens.data[t];
                bool negative = token[0] == '-';
                const char *magnitude = token + (negative ? 1 : 0);
                if (!well_number(magnitude) || (negative && !strcmp(magnitude, "0")))
                    out.error = format("bad token %s at line %d", token, i + 1);
                else {
                    int literal = atoi(token);
                    if (abs(literal) > out.formula.variables)
                        out.error = format("literal out of range %s at line %d", token, i + 1);
                    else if (literal)
                        int_push(&current, literal);
                    else {
                        formula_push(&out.formula, current);
                        current = (Clause){0};
                    }
                }
            }
        free_lines(&tokens);
    }
    if (!out.error) {
        if (!header)
            out.error = text("missing header");
        else if (current.count)
            out.error = text("unterminated clause");
        else if (out.formula.count != declared)
            out.error = format("clause count mismatch header=%d found=%d", declared, out.formula.count);
    }
    int_free(&current);
    free_lines(&lines);
    return out;
}
Lines model_lines(const Model *model, int variables) {
    Lines out = {0};
    for (int first = 1; first <= variables + 1; first += 10) {
        char *line = text("v");
        for (int x = first; x < first + 10 && x <= variables + 1; ++x) {
            char *next = format("%s %d", line, x == variables + 1 ? 0 : model->values[x] ? x : -x);
            free(line);
            line = next;
        }
        line_push(&out, line);
    }
    return out;
}
