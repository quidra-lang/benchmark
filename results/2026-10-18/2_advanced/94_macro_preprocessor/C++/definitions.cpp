#include "preprocessor.hpp"
std::string position_text(const Position &position) {
    return position.file + ":" + std::to_string(position.line);
}
bool builtin(const std::string &name) { return word_in("__LINE__ __FILE__ __COUNTER__", name); }
std::string Macro::signature() const {
    if (!function)
        return name;
    std::string result = name + "(";
    for (size_t i = 0; i < parameters.size(); ++i) {
        if (i)
            result += ", ";
        result += variadic && i + 1 == parameters.size() ? "..." : parameters[i];
    }
    return result + ")";
}
void check_name(const Tokens &tokens, const std::string &directive) {
    if (tokens.empty())
        throw PreprocessingError{"no macro name given in #" + directive + " directive"};
    if (tokens[0].kind != "identifier")
        throw PreprocessingError{"macro names must be identifiers"};
    const std::string &name = tokens[0].spelling;
    if (name == "defined")
        throw PreprocessingError{"\"defined\" cannot be used as a macro name"};
    if (builtin(name))
        throw PreprocessingError{std::string(directive == "define"
                                                 ? "cannot redefine builtin macro \""
                                                 : "cannot undefine builtin macro \"") +
                                 name + "\""};
}
std::shared_ptr<Macro> parse_definition(Tokens tokens, Position position, bool main_file) {
    check_name(tokens, "define");
    auto result = std::make_shared<Macro>();
    result->name = tokens[0].spelling;
    result->position = position;
    result->main_file = main_file;
    const std::string variadic_name = "__VA_ARGS__",
                      variadic_error =
                          "\"__VA_ARGS__\" can only appear in the expansion of a variadic macro";
    if (result->name == variadic_name)
        throw PreprocessingError{variadic_error};
    size_t index = 1;
    if (index < tokens.size() && tokens[index].spelling == "(" && !tokens[index].space) {
        result->function = true;
        ++index;
        if (index == tokens.size())
            throw PreprocessingError{"missing ')' in macro parameter list"};
        if (tokens[index].spelling == ")")
            ++index;
        else {
            std::set<std::string> seen;
            while (true) {
                if (index == tokens.size())
                    throw PreprocessingError{"missing ')' in macro parameter list"};
                Token token = tokens[index++];
                std::string parameter = token.spelling;
                if (parameter == "...") {
                    result->variadic = true;
                    parameter = variadic_name;
                } else if (token.kind == "identifier") {
                    if (parameter == variadic_name)
                        throw PreprocessingError{variadic_error};
                    if (seen.count(parameter))
                        throw PreprocessingError{"duplicate macro parameter \"" + parameter + "\""};
                } else
                    throw PreprocessingError{"expected parameter name, found \"" + parameter +
                                             "\""};
                seen.insert(parameter);
                result->parameters.push_back(parameter);
                if (index == tokens.size())
                    throw PreprocessingError{"missing ')' in macro parameter list"};
                std::string next = tokens[index++].spelling;
                if (next == ")")
                    break;
                if (result->variadic)
                    throw PreprocessingError{"expected ')' after \"...\", found \"" + next + "\""};
                if (next != ",")
                    throw PreprocessingError{"expected ',' or ')', found \"" + next + "\""};
            }
        }
    }
    result->replacement.assign(tokens.begin() + index, tokens.end());
    if (!result->replacement.empty()) {
        result->replacement[0].space = false;
        if (result->replacement.front().spelling == "##" ||
            result->replacement.back().spelling == "##")
            throw PreprocessingError{"'##' cannot appear at either end of a macro expansion"};
    }
    std::set<std::string> parameters(result->parameters.begin(), result->parameters.end());
    for (size_t i = 0; i < result->replacement.size(); ++i) {
        const Token &token = result->replacement[i];
        if (token.kind == "identifier" && token.spelling == variadic_name && !result->variadic)
            throw PreprocessingError{variadic_error};
        if (token.spelling == "#" && result->function &&
            (i + 1 == result->replacement.size() ||
             result->replacement[i + 1].kind != "identifier" ||
             !parameters.count(result->replacement[i + 1].spelling)))
            throw PreprocessingError{"'#' is not followed by a macro parameter"};
    }
    return result;
}
bool Macro::identical(const Macro &other) const {
    if (function != other.function || variadic != other.variadic ||
        parameters != other.parameters || replacement.size() != other.replacement.size())
        return false;
    for (size_t i = 0; i < replacement.size(); ++i)
        if (replacement[i].spelling != other.replacement[i].spelling ||
            replacement[i].space != other.replacement[i].space)
            return false;
    return true;
}
