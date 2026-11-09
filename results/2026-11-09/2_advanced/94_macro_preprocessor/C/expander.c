#include "preprocessor.h"
typedef struct Pending {
    Token token;
    struct Pending *next;
} Pending;
typedef struct {
    bool paste;
    Tokens tokens;
    Token operator_token;
} SubstitutionItem;
typedef struct {
    SubstitutionItem *items;
    int count, capacity;
} ItemList;
static Token stringize(Tokens raw, Token hash) {
    Token result = {0};
    result.kind = "string";
    result.space = hash.space;
    Text text = {0};
    text_char(&text, '"');
    for (int i = 0; i < raw.count; ++i) {
        Token token = raw.items[i];
        if (i && token.space)
            text_char(&text, ' ');
        for (const char *c = token.spelling; *c; ++c) {
            if ((equal(token.kind, "string") || equal(token.kind, "character")) &&
                (*c == '\\' || *c == '"'))
                text_char(&text, '\\');
            text_char(&text, *c);
        }
    }
    text_char(&text, '"');
    result.spelling = text_value(&text);
    return result;
}
static Tokens paste(Preprocessor *p, Inclusion *inclusion, Token left, Token right,
                    Token invocation) {
    Tokens result = {0};
    if (equal(left.kind, "placemarker")) {
        right.space = left.space;
        PUSH(result, right);
        return result;
    }
    if (equal(right.kind, "placemarker")) {
        PUSH(result, left);
        return result;
    }
    char *spelling = ml_format("%s%s", left.spelling, right.spelling);
    const char *kind = single_token(spelling);
    if (kind) {
        Token token = {kind, spelling, 0, left.space, {0}};
        token.hide = names_intersection(left.hide, right.hide);
        PUSH(result, token);
    } else {
        diagnostic(p, display_position(inclusion, invocation.line), "error",
                   ml_format("pasting \"%s\" and \"%s\" does not give a valid preprocessing token",
                             left.spelling, right.spelling));
        right.space = false;
        PUSH(result, left);
        PUSH(result, right);
    }
    return result;
}
static int parameter_index(Macro *macro, const char *name) {
    for (int i = 0; i < macro->parameters.count; ++i)
        if (equal(macro->parameters.items[i], name))
            return i;
    return -1;
}
static Tokens substitute(Preprocessor *p, Inclusion *inclusion, Macro *macro, Token invocation,
                         TokenGroups raw, StringList hide) {
    Tokens *expanded = ml_alloc((size_t)raw.count * sizeof(*expanded));
    bool *cached = ml_alloc((size_t)raw.count * sizeof(*cached));
    ItemList items = {0};
    for (int i = 0; i < macro->replacement.count; ++i) {
        Token token = macro->replacement.items[i];
        SubstitutionItem item = {0};
        if (equal(token.spelling, "#") && macro->function) {
            Token parameter = macro->replacement.items[++i];
            Token quoted = stringize(raw.items[parameter_index(macro, parameter.spelling)], token);
            PUSH(item.tokens, quoted);
        } else if (equal(token.spelling, "##")) {
            item.paste = true;
            item.operator_token = token;
        } else {
            int index =
                equal(token.kind, "identifier") ? parameter_index(macro, token.spelling) : -1;
            if (index >= 0) {
                bool adjacent = (i > 0 && equal(macro->replacement.items[i - 1].spelling, "##")) ||
                                (i + 1 < macro->replacement.count &&
                                 equal(macro->replacement.items[i + 1].spelling, "##"));
                Tokens sequence;
                if (adjacent)
                    sequence = raw.items[index];
                else {
                    if (!cached[index]) {
                        expanded[index] = expand(p, inclusion, raw.items[index]);
                        cached[index] = true;
                    }
                    sequence = expanded[index];
                }
                item.tokens = copy_tokens(sequence);
                if (!item.tokens.count) {
                    Token marker = {"placemarker", "", 0, token.space, {0}};
                    PUSH(item.tokens, marker);
                } else
                    item.tokens.items[0].space = token.space;
            } else
                PUSH(item.tokens, token);
        }
        PUSH(items, item);
    }
    Tokens combined = {0};
    for (int i = 0; i < items.count; ++i) {
        SubstitutionItem item = items.items[i];
        if (!item.paste) {
            for (int j = 0; j < item.tokens.count; ++j)
                PUSH(combined, item.tokens.items[j]);
        } else {
            Token left = combined.items[--combined.count];
            SubstitutionItem right = items.items[++i];
            Tokens sequence = right.tokens;
            if (right.paste) {
                sequence = (Tokens){0};
                PUSH(sequence, right.operator_token);
            }
            Tokens pasted = paste(p, inclusion, left, sequence.items[0], invocation);
            for (int j = 0; j < pasted.count; ++j)
                PUSH(combined, pasted.items[j]);
            for (int j = 1; j < sequence.count; ++j)
                PUSH(combined, sequence.items[j]);
        }
    }
    Tokens result = {0};
    bool carry = false;
    for (int i = 0; i < combined.count; ++i) {
        Token token = combined.items[i];
        if (equal(token.kind, "placemarker")) {
            carry = carry || token.space;
            continue;
        }
        token.space = token.space || carry;
        carry = false;
        token.line = invocation.line;
        token.hide = names_union(token.hide, hide);
        PUSH(result, token);
    }
    if (result.count)
        result.items[0].space = invocation.space;
    return result;
}
Tokens expand(Preprocessor *p, Inclusion *inclusion, Tokens tokens) {
    Pending *input = NULL;
    for (int i = tokens.count - 1; i >= 0; --i) {
        Pending *node = ml_alloc(sizeof(*node));
        node->token = tokens.items[i];
        node->next = input;
        input = node;
    }
    Tokens result = {0};
    while (input) {
        Token invocation = input->token;
        input = input->next;
        const char *name = invocation.spelling;
        if (!equal(invocation.kind, "identifier") || string_member(invocation.hide, name)) {
            PUSH(result, invocation);
            continue;
        }
        if (builtin(name)) {
            Token token = {0};
            token.line = invocation.line;
            token.space = invocation.space;
            token.kind = equal(name, "__FILE__") ? "string" : "number";
            if (equal(name, "__LINE__")) {
                ++p->builtin_counts[2];
                token.spelling = ml_format("%d", display_position(inclusion, invocation.line).line);
            } else if (equal(name, "__FILE__")) {
                ++p->builtin_counts[1];
                token.spelling = ml_format("\"%s\"", inclusion->display_file);
            } else {
                ++p->builtin_counts[0];
                token.spelling = ml_format("%d", p->counter++);
            }
            PUSH(result, token);
            continue;
        }
        Macro *macro = find_macro(p, name);
        if (!macro) {
            PUSH(result, invocation);
            continue;
        }
        StringList hide = invocation.hide;
        TokenGroups raw = {0};
        if (macro->function) {
            if (!input || !equal(input->token.spelling, "(")) {
                PUSH(result, invocation);
                continue;
            }
            TokenGroups arguments = {0};
            Tokens argument = {0}, commas = {0};
            PUSH(arguments, argument);
            int depth = 0;
            Pending *close = input->next;
            for (; close; close = close->next) {
                Token token = close->token;
                if (equal(token.spelling, ")") && depth == 0)
                    break;
                if (equal(token.spelling, ",") && depth == 0) {
                    PUSH(commas, token);
                    Tokens next = {0};
                    PUSH(arguments, next);
                } else {
                    if (equal(token.spelling, "("))
                        ++depth;
                    else if (equal(token.spelling, ")"))
                        --depth;
                    PUSH(arguments.items[arguments.count - 1], token);
                }
            }
            int k = arguments.count, n = macro->parameters.count - (macro->variadic ? 1 : 0);
            char *error = NULL;
            if (!close)
                error = ml_format("unterminated argument list invoking macro \"%s\"", name);
            else if (!macro->variadic && n == 0 && !(k == 1 && !arguments.items[0].count))
                error = ml_format("macro \"%s\" passed %d arguments, but takes just 0", name, k);
            else if (k < n)
                error =
                    ml_format("macro \"%s\" requires %d arguments, but only %d given", name, n, k);
            else if (k > n && !macro->variadic)
                error =
                    ml_format("macro \"%s\" passed %d arguments, but takes just %d", name, k, n);
            if (error) {
                diagnostic(p, display_position(inclusion, invocation.line), "error", error);
                PUSH(result, invocation);
                continue;
            }
            hide = names_intersection(invocation.hide, close->token.hide);
            for (int i = 0; i < n; ++i)
                PUSH(raw, arguments.items[i]);
            if (macro->variadic) {
                Tokens variadic = {0};
                for (int i = n; i < arguments.count; ++i) {
                    if (i > n)
                        PUSH(variadic, commas.items[i - 1]);
                    for (int j = 0; j < arguments.items[i].count; ++j)
                        PUSH(variadic, arguments.items[i].items[j]);
                }
                PUSH(raw, variadic);
            }
            input = close->next;
        }
        StringList own = {0};
        PUSH(own, (char *)name);
        hide = names_union(hide, own);
        Tokens replacement = substitute(p, inclusion, macro, invocation, raw, hide);
        ++macro->expanded;
        if (!replacement.count && invocation.space && input)
            input->token.space = true;
        for (int i = replacement.count - 1; i >= 0; --i) {
            Pending *node = ml_alloc(sizeof(*node));
            node->token = replacement.items[i];
            node->next = input;
            input = node;
        }
    }
    return result;
}
