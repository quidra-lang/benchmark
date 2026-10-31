#include "preprocessor.hpp"
static std::set<std::string> intersection(const std::set<std::string> &left,
                                          const std::set<std::string> &right) {
    std::set<std::string> result;
    std::set_intersection(left.begin(), left.end(), right.begin(), right.end(),
                          std::inserter(result, result.end()));
    return result;
}
static Token stringize(const Tokens &raw, const Token &hash) {
    Token result;
    result.kind = "string";
    result.space = hash.space;
    result.spelling = "\"";
    for (size_t i = 0; i < raw.size(); ++i) {
        if (i && raw[i].space)
            result.spelling += " ";
        for (char c : raw[i].spelling) {
            if ((raw[i].kind == "string" || raw[i].kind == "character") && (c == '\\' || c == '"'))
                result.spelling += '\\';
            result.spelling += c;
        }
    }
    result.spelling += '"';
    return result;
}
static Tokens paste(Preprocessor &processor, const Inclusion &inclusion, Token left, Token right,
                    const Token &invocation) {
    if (left.kind == "placemarker") {
        right.space = left.space;
        return {right};
    }
    if (right.kind == "placemarker")
        return {left};
    std::string combined = left.spelling + right.spelling;
    std::optional<std::string> kind = single_token(combined);
    if (kind)
        return {{*kind, combined, 0, left.space, intersection(left.hide, right.hide)}};
    processor.diagnostic(inclusion.position(invocation.line), "error",
                         "pasting \"" + left.spelling + "\" and \"" + right.spelling +
                             "\" does not give a valid preprocessing token");
    right.space = false;
    return {left, right};
}
struct SubstitutionItem {
    bool paste = false;
    Tokens tokens;
    Token operator_token;
};
static Tokens substitute(Preprocessor &processor, const Inclusion &inclusion, const Macro &macro,
                         const Token &invocation, const std::vector<Tokens> &raw,
                         const std::set<std::string> &hide) {
    std::map<std::string, size_t> parameters;
    for (size_t i = 0; i < macro.parameters.size(); ++i)
        parameters[macro.parameters[i]] = i;
    std::vector<std::optional<Tokens>> expanded(raw.size());
    std::vector<SubstitutionItem> items;
    for (size_t i = 0; i < macro.replacement.size(); ++i) {
        Token token = macro.replacement[i];
        if (token.spelling == "#" && macro.function) {
            const Token &parameter = macro.replacement[++i];
            items.push_back({false, {stringize(raw[parameters.at(parameter.spelling)], token)}});
        } else if (token.spelling == "##")
            items.push_back({true, {}, token});
        else if (token.kind == "identifier" && parameters.count(token.spelling)) {
            size_t index = parameters.at(token.spelling);
            bool adjacent =
                (i > 0 && macro.replacement[i - 1].spelling == "##") ||
                (i + 1 < macro.replacement.size() && macro.replacement[i + 1].spelling == "##");
            Tokens sequence;
            if (adjacent)
                sequence = raw[index];
            else {
                if (!expanded[index])
                    expanded[index] = expand(processor, inclusion, raw[index]);
                sequence = *expanded[index];
            }
            if (sequence.empty())
                sequence.push_back({"placemarker", "", 0, token.space, {}});
            else
                sequence[0].space = token.space;
            items.push_back({false, std::move(sequence)});
        } else
            items.push_back({false, {token}});
    }
    Tokens combined;
    for (size_t i = 0; i < items.size(); ++i) {
        if (!items[i].paste)
            combined.insert(combined.end(), items[i].tokens.begin(), items[i].tokens.end());
        else {
            Token left = combined.back();
            combined.pop_back();
            SubstitutionItem &right = items[++i];
            Tokens sequence = right.paste ? Tokens{right.operator_token} : right.tokens;
            Tokens result = paste(processor, inclusion, left, sequence.front(), invocation);
            combined.insert(combined.end(), result.begin(), result.end());
            combined.insert(combined.end(), sequence.begin() + 1, sequence.end());
        }
    }
    Tokens result;
    bool space = false;
    for (Token token : combined) {
        if (token.kind == "placemarker") {
            if (token.space)
                space = true;
            continue;
        }
        if (space) {
            token.space = true;
            space = false;
        }
        token.line = invocation.line;
        token.hide.insert(hide.begin(), hide.end());
        result.push_back(std::move(token));
    }
    if (!result.empty())
        result[0].space = invocation.space;
    return result;
}
Tokens expand(Preprocessor &processor, const Inclusion &inclusion, const Tokens &tokens) {
    std::deque<Token> input(tokens.begin(), tokens.end());
    Tokens result;
    while (!input.empty()) {
        Token invocation = input.front();
        input.pop_front();
        const std::string &name = invocation.spelling;
        if (invocation.kind != "identifier" || invocation.hide.count(name)) {
            result.push_back(invocation);
            continue;
        }
        if (builtin(name)) {
            ++processor.builtin_counts[name];
            Token token;
            token.line = invocation.line;
            token.space = invocation.space;
            token.kind = name == "__FILE__" ? "string" : "number";
            if (name == "__LINE__")
                token.spelling = std::to_string(inclusion.position(invocation.line).line);
            else if (name == "__FILE__")
                token.spelling = "\"" + inclusion.display_file + "\"";
            else
                token.spelling = std::to_string(processor.counter++);
            result.push_back(std::move(token));
            continue;
        }
        auto found = processor.macros.find(name);
        if (found == processor.macros.end()) {
            result.push_back(invocation);
            continue;
        }
        const std::shared_ptr<Macro> macro = found->second;
        std::set<std::string> hide = invocation.hide;
        std::vector<Tokens> raw;
        if (macro->function) {
            if (input.empty() || input.front().spelling != "(") {
                result.push_back(invocation);
                continue;
            }
            std::vector<Tokens> arguments(1);
            std::vector<Token> commas;
            int depth = 0;
            size_t close = 1;
            for (; close < input.size(); ++close) {
                const Token &token = input[close];
                if (token.spelling == ")" && depth == 0)
                    break;
                if (token.spelling == "," && depth == 0) {
                    commas.push_back(token);
                    arguments.emplace_back();
                } else {
                    if (token.spelling == "(")
                        ++depth;
                    else if (token.spelling == ")")
                        --depth;
                    arguments.back().push_back(token);
                }
            }
            std::string error;
            size_t k = arguments.size(), n = macro->parameters.size() - (macro->variadic ? 1 : 0);
            if (close == input.size())
                error = "unterminated argument list invoking macro \"" + name + "\"";
            else if (!macro->variadic && n == 0 && !(k == 1 && arguments[0].empty()))
                error = "macro \"" + name + "\" passed " + std::to_string(k) +
                        " arguments, but takes just 0";
            else if (k < n)
                error = "macro \"" + name + "\" requires " + std::to_string(n) +
                        " arguments, but only " + std::to_string(k) + " given";
            else if (k > n && !macro->variadic)
                error = "macro \"" + name + "\" passed " + std::to_string(k) +
                        " arguments, but takes just " + std::to_string(n);
            if (!error.empty()) {
                processor.diagnostic(inclusion.position(invocation.line), "error", error);
                result.push_back(invocation);
                continue;
            }
            hide = intersection(invocation.hide, input[close].hide);
            raw.assign(arguments.begin(), arguments.begin() + n);
            if (macro->variadic) {
                Tokens variadic;
                for (size_t i = n; i < arguments.size(); ++i) {
                    if (i > n)
                        variadic.push_back(commas[i - 1]);
                    variadic.insert(variadic.end(), arguments[i].begin(), arguments[i].end());
                }
                raw.push_back(std::move(variadic));
            }
            input.erase(input.begin(), input.begin() + close + 1);
        }
        hide.insert(name);
        Tokens replacement = substitute(processor, inclusion, *macro, invocation, raw, hide);
        ++macro->expanded;
        if (replacement.empty() && invocation.space && !input.empty())
            input.front().space = true;
        for (auto it = replacement.rbegin(); it != replacement.rend(); ++it)
            input.push_front(*it);
    }
    return result;
}
