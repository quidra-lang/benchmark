#include "preprocessor.h"
char *position_text(Position position) { return ml_format("%s:%d", position.file, position.line); }
bool builtin(const char *name) { return word_in("__LINE__ __FILE__ __COUNTER__", name); }
char *signature(Macro *macro) {
    if (!macro->function)
        return (char *)macro->name;
    Text result = {0};
    text_add(&result, macro->name);
    text_char(&result, '(');
    for (int i = 0; i < macro->parameters.count; ++i) {
        if (i)
            text_add(&result, ", ");
        text_add(&result, macro->variadic && i + 1 == macro->parameters.count
                              ? "..."
                              : macro->parameters.items[i]);
    }
    text_char(&result, ')');
    return text_value(&result);
}
char *check_name(Tokens tokens, const char *directive) {
    if (!tokens.count)
        return ml_format("no macro name given in #%s directive", directive);
    if (!equal(tokens.items[0].kind, "identifier"))
        return "macro names must be identifiers";
    const char *name = tokens.items[0].spelling;
    if (equal(name, "defined"))
        return "\"defined\" cannot be used as a macro name";
    if (builtin(name))
        return ml_format(equal(directive, "define") ? "cannot redefine builtin macro \"%s\""
                                                    : "cannot undefine builtin macro \"%s\"",
                         name);
    return NULL;
}
Macro *parse_definition(Tokens tokens, Position position, bool main_file, char **error) {
    *error = check_name(tokens, "define");
    if (*error)
        return NULL;
    Macro *macro = ml_alloc(sizeof(*macro));
    macro->name = tokens.items[0].spelling;
    macro->position = position;
    macro->main_file = main_file;
    const char *variadic_error =
        "\"__VA_ARGS__\" can only appear in the expansion of a variadic macro";
    if (equal(macro->name, "__VA_ARGS__")) {
        *error = (char *)variadic_error;
        return NULL;
    }
    int index = 1;
    if (index < tokens.count && equal(tokens.items[index].spelling, "(") &&
        !tokens.items[index].space) {
        macro->function = true;
        ++index;
        if (index == tokens.count) {
            *error = "missing ')' in macro parameter list";
            return NULL;
        }
        if (equal(tokens.items[index].spelling, ")"))
            ++index;
        else
            while (true) {
                if (index == tokens.count) {
                    *error = "missing ')' in macro parameter list";
                    return NULL;
                }
                Token token = tokens.items[index++];
                const char *parameter = token.spelling;
                if (equal(parameter, "...")) {
                    macro->variadic = true;
                    parameter = "__VA_ARGS__";
                } else if (equal(token.kind, "identifier")) {
                    if (equal(parameter, "__VA_ARGS__")) {
                        *error = (char *)variadic_error;
                        return NULL;
                    }
                    if (string_member(macro->parameters, parameter)) {
                        *error = ml_format("duplicate macro parameter \"%s\"", parameter);
                        return NULL;
                    }
                } else {
                    *error = ml_format("expected parameter name, found \"%s\"", parameter);
                    return NULL;
                }
                PUSH(macro->parameters, (char *)parameter);
                if (index == tokens.count) {
                    *error = "missing ')' in macro parameter list";
                    return NULL;
                }
                const char *next = tokens.items[index++].spelling;
                if (equal(next, ")"))
                    break;
                if (macro->variadic) {
                    *error = ml_format("expected ')' after \"...\", found \"%s\"", next);
                    return NULL;
                }
                if (!equal(next, ",")) {
                    *error = ml_format("expected ',' or ')', found \"%s\"", next);
                    return NULL;
                }
            }
    }
    for (int i = index; i < tokens.count; ++i)
        PUSH(macro->replacement, tokens.items[i]);
    if (macro->replacement.count) {
        macro->replacement.items[0].space = false;
        if (equal(macro->replacement.items[0].spelling, "##") ||
            equal(macro->replacement.items[macro->replacement.count - 1].spelling, "##")) {
            *error = "'##' cannot appear at either end of a macro expansion";
            return NULL;
        }
    }
    for (int i = 0; i < macro->replacement.count; ++i) {
        Token token = macro->replacement.items[i];
        if (equal(token.kind, "identifier") && equal(token.spelling, "__VA_ARGS__") &&
            !macro->variadic) {
            *error = (char *)variadic_error;
            return NULL;
        }
        if (equal(token.spelling, "#") && macro->function &&
            (i + 1 == macro->replacement.count ||
             !equal(macro->replacement.items[i + 1].kind, "identifier") ||
             !string_member(macro->parameters, macro->replacement.items[i + 1].spelling))) {
            *error = "'#' is not followed by a macro parameter";
            return NULL;
        }
    }
    return macro;
}
bool identical(Macro *left, Macro *right) {
    if (left->function != right->function || left->variadic != right->variadic ||
        left->parameters.count != right->parameters.count ||
        left->replacement.count != right->replacement.count)
        return false;
    for (int i = 0; i < left->parameters.count; ++i)
        if (!equal(left->parameters.items[i], right->parameters.items[i]))
            return false;
    for (int i = 0; i < left->replacement.count; ++i)
        if (!equal(left->replacement.items[i].spelling, right->replacement.items[i].spelling) ||
            left->replacement.items[i].space != right->replacement.items[i].space)
            return false;
    return true;
}
