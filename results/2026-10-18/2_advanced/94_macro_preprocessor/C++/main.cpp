#include "preprocessor.hpp"
std::optional<Header> read_header(const Tokens &tokens, size_t index) {
    if (index >= tokens.size())
        return std::nullopt;
    const Token &token = tokens[index];
    if (token.kind == "string" || token.kind == "header")
        return Header{token.spelling, token.spelling.substr(1, token.spelling.size() - 2),
                      token.spelling[0] == '"', index + 1};
    if (token.spelling == "<") {
        size_t end = index + 1;
        while (end < tokens.size() && tokens[end].spelling != ">")
            ++end;
        if (end == tokens.size())
            throw PreprocessingError{"missing terminating > character"};
        std::string name = render(Tokens(tokens.begin() + index + 1, tokens.begin() + end));
        return Header{"<" + name + ">", name, false, end + 1};
    }
    return std::nullopt;
}
static bool separator_needed(const std::string &left, const std::string &right) {
    if (left == "/" && (right[0] == '/' || right[0] == '*'))
        return true;
    return read_token(left + right, 0).end != left.size();
}
static std::string output_render(const Tokens &tokens) {
    std::string result;
    for (size_t i = 0; i < tokens.size(); ++i) {
        if (i && (tokens[i].space || separator_needed(tokens[i - 1].spelling, tokens[i].spelling)))
            result += " ";
        result += tokens[i].spelling;
    }
    return result;
}
static bool decimal_token(const Token &token) {
    return token.kind == "number" && !token.spelling.empty() &&
           std::all_of(token.spelling.begin(), token.spelling.end(),
                       [](char c) { return c >= '0' && c <= '9'; });
}
void Preprocessor::diagnostic(Position position, const std::string &kind,
                              const std::string &message) {
    diagnostics.push_back(position_text(position) + ": " + kind + ": " + message);
    ++diagnostic_counts[kind];
}
void Preprocessor::event(Position position, const std::string &content) {
    history.push_back(position_text(position) + ": " + content);
}
void Preprocessor::poison_check(const Inclusion &inclusion, const Tokens &tokens) {
    for (const Token &token : tokens)
        if (token.kind == "identifier" && poisoned.count(token.spelling))
            diagnostic(inclusion.position(token.line), "error",
                       "attempt to use poisoned \"" + token.spelling + "\"");
}
void Preprocessor::unused_check(const Macro &macro) {
    if (macro.main_file && macro.expanded == 0 && macro.tested == 0)
        diagnostic(macro.position, "warning", "macro \"" + macro.name + "\" is not used");
}
void Preprocessor::define(Tokens tokens, Position position, bool main_file) {
    std::shared_ptr<Macro> macro;
    try {
        macro = parse_definition(std::move(tokens), position, main_file);
    } catch (const PreprocessingError &error) {
        diagnostic(position, "error", error.message);
        return;
    }
    std::string operation = "define";
    auto previous = macros.find(macro->name);
    if (previous == macros.end()) {
        macros[macro->name] = macro;
        ever_defined.insert(macro->name);
    } else if (previous->second->identical(*macro))
        operation = "identical";
    else {
        unused_check(*previous->second);
        diagnostic(position, "warning",
                   "\"" + macro->name + "\" redefined (previous definition at " +
                       position_text(previous->second->position) + ")");
        macros[macro->name] = macro;
        ever_defined.insert(macro->name);
        operation = "redefine";
    }
    event(position, operation + " " + macro->signature());
}
void Preprocessor::undefine(const Tokens &tokens, Position position) {
    try {
        check_name(tokens, "undef");
    } catch (const PreprocessingError &error) {
        diagnostic(position, "error", error.message);
        return;
    }
    if (tokens.size() > 1)
        diagnostic(position, "warning", "extra tokens at end of #undef directive");
    const std::string &name = tokens[0].spelling;
    auto previous = macros.find(name);
    if (previous != macros.end()) {
        unused_check(*previous->second);
        macros.erase(previous);
        event(position, "undef " + name);
    } else
        event(position, "undef " + name + " (not defined)");
}
void Preprocessor::process_defines() {
    std::ifstream input("input/defines.txt");
    std::string line;
    int number = 0;
    while (std::getline(input, line)) {
        ++number;
        if (line.empty())
            continue;
        size_t equal = line.find('=');
        std::string text = equal == std::string::npos
                               ? line + " 1"
                               : line.substr(0, equal) + " " + line.substr(equal + 1);
        define(lex_definition(text, number), {"defines.txt", number}, false);
    }
}
void Preprocessor::marker(const std::string &file, int line, int flag) {
    std::string text = "# " + std::to_string(line) + " \"" + file + "\"";
    if (flag)
        text += " " + std::to_string(flag);
    output.push_back(text);
    previous = {file, line - 1};
}
void Preprocessor::output_line(Inclusion &inclusion, int physical, const std::string &text) {
    Position position = inclusion.position(physical);
    if (position.file == previous.file && previous.line < position.line &&
        static_cast<int64_t>(position.line) <= static_cast<int64_t>(previous.line) + 8)
        for (int64_t i = static_cast<int64_t>(previous.line) + 1; i < position.line; ++i)
            output.emplace_back();
    else
        marker(position.file, position.line);
    output.push_back(text);
    previous = position;
    ++inclusion.source->output_lines;
}
void Preprocessor::flush(Inclusion &inclusion) {
    Tokens segment = std::move(inclusion.segment);
    inclusion.segment.clear();
    if (segment.empty())
        return;
    poison_check(inclusion, segment);
    Tokens expanded = expand(*this, inclusion, segment);
    for (size_t start = 0; start < expanded.size();) {
        size_t end = start + 1;
        while (end < expanded.size() && expanded[end].line == expanded[start].line)
            ++end;
        output_line(inclusion, expanded[start].line,
                    output_render(Tokens(expanded.begin() + start, expanded.begin() + end)));
        start = end;
    }
}
bool Preprocessor::macro_defined(const std::string &name) {
    auto found = macros.find(name);
    if (found != macros.end()) {
        ++found->second->tested;
        return true;
    }
    return builtin(name) || name == "__has_include";
}
Tokens Preprocessor::replace_operators(const Tokens &operands) {
    Tokens result;
    for (size_t position = 0; position < operands.size();) {
        Token token = operands[position];
        size_t index = position + 1;
        bool value = false;
        if (token.kind == "identifier" && token.spelling == "defined") {
            bool parenthesized = index < operands.size() && operands[index].spelling == "(";
            if (parenthesized)
                ++index;
            if (index == operands.size() || operands[index].kind != "identifier")
                throw PreprocessingError{"operator \"defined\" requires an identifier"};
            std::string name = operands[index++].spelling;
            if (parenthesized) {
                if (index == operands.size() || operands[index].spelling != ")")
                    throw PreprocessingError{"missing ')' after \"defined\""};
                ++index;
            }
            value = macro_defined(name);
        } else if (token.kind == "identifier" && token.spelling == "__has_include") {
            if (index == operands.size() || operands[index].spelling != "(")
                throw PreprocessingError{"missing '(' after \"__has_include\""};
            std::optional<Header> header = read_header(operands, index + 1);
            if (!header || header->name.empty())
                throw PreprocessingError{"operator \"__has_include\" requires a header-name"};
            index = header->next;
            if (index == operands.size() || operands[index].spelling != ")")
                throw PreprocessingError{"missing ')' after \"__has_include\" operand"};
            ++index;
            value = !manager.search(header->name, header->quoted).empty();
        } else {
            result.push_back(token);
            ++position;
            continue;
        }
        result.push_back({"number", value ? "1" : "0", token.line, token.space, {}});
        position = index;
    }
    return result;
}
TestResult Preprocessor::test(Inclusion &inclusion, const LogicalLine &line,
                              const std::string &name, const Tokens &operands) {
    Position position = inclusion.position(line.tokens[0].line);
    poison_check(inclusion, operands);
    TestResult result;
    if (name != "if" && name != "elif") {
        if (operands.empty()) {
            diagnostic(position, "error", "no macro name given in #" + name + " directive");
            return result;
        }
        if (operands[0].kind != "identifier") {
            diagnostic(position, "error", "macro names must be identifiers");
            return result;
        }
        if (operands.size() > 1)
            diagnostic(position, "warning", "extra tokens at end of #" + name + " directive");
        bool defined = macro_defined(operands[0].spelling);
        if (name == "ifndef" || name == "elifndef")
            defined = !defined;
        result.valid = true;
        result.value = defined;
        return result;
    }
    Tokens replaced;
    try {
        replaced = replace_operators(operands);
    } catch (const PreprocessingError &error) {
        diagnostic(position, "error", error.message);
        return result;
    }
    result.expanded = expand(*this, inclusion, replaced);
    result.was_expanded = true;
    try {
        std::unique_ptr<ConditionExpr> expression = parse_condition(result.expanded, name);
        result.value = evaluate_condition(*expression, [&](const std::string &message) {
            diagnostic(position, "warning", message);
        });
        result.valid = true;
    } catch (const PreprocessingError &error) {
        diagnostic(position, "error", error.message);
    }
    return result;
}
static std::string test_description(const std::string &name, const TestResult &test) {
    std::string description = "not taken (error)";
    if (test.valid) {
        description = test.value ? "taken" : "not taken";
        if (name == "if" || name == "elif")
            description += " (value " + std::to_string(test.value) + ")";
    }
    if (test.was_expanded)
        description += " [" + output_render(test.expanded) + "]";
    return description;
}
void Preprocessor::close_region(Inclusion &inclusion, ConditionalBlock &block, int end) {
    int start = block.skip_start;
    if (start && end >= start) {
        Position first = inclusion.position(start), last = inclusion.position(end);
        regions.push_back(first.file + ":" + std::to_string(first.line) + "-" +
                          std::to_string(last.line) + " lines=" + std::to_string(end - start + 1));
        inclusion.source->skipped_lines += end - start + 1;
    }
    block.skip_start = 0;
}
void Preprocessor::conditional_record(Position position, size_t depth, const std::string &name,
                                      const Tokens &operands, const std::string &description) {
    std::string directive = "#" + name;
    if (!operands.empty())
        directive += " " + render(operands);
    conditionals.push_back(position_text(position) + ": " + std::string(2 * depth, ' ') +
                           directive + " => " + description);
    const std::vector<std::pair<std::string, std::string>> prefixes = {
        {"taken", "taken"},
        {"not taken", "not_taken"},
        {"skipped", "skipped"},
        {"not evaluated", "not_evaluated"},
        {"closes", "endif"}};
    for (const auto &prefix : prefixes)
        if (description.compare(0, prefix.first.size(), prefix.first) == 0) {
            ++condition_counts[prefix.second];
            break;
        }
}
void Preprocessor::conditional(Inclusion &inclusion, const LogicalLine &line,
                               const std::string &name, const Tokens &operands) {
    Position position = inclusion.position(line.tokens[0].line);
    if (word_in("if ifdef ifndef", name)) {
        ConditionalBlock block;
        block.kind = name;
        block.start = position;
        block.parent = !inclusion.skipping();
        std::string description = "skipped";
        if (block.parent) {
            TestResult tested = test(inclusion, line, name, operands);
            if (tested.valid && tested.value)
                block.chosen = block.active = true;
            else
                block.skip_start = line.end + 1;
            description = test_description(name, tested);
        }
        conditional_record(position, inclusion.stack.size(), name, operands, description);
        inclusion.stack.push_back(block);
        return;
    }
    if (inclusion.stack.empty()) {
        diagnostic(position, "error", "#" + name + " without #if");
        return;
    }
    size_t depth = inclusion.stack.size() - 1;
    ConditionalBlock &block = inclusion.stack.back();
    close_region(inclusion, block, line.start - 1);
    std::string description;
    if (name == "endif") {
        if (block.parent && !operands.empty())
            diagnostic(position, "warning", "extra tokens at end of #endif directive");
        description = "closes #" + block.kind + " at line " + std::to_string(block.start.line);
        inclusion.stack.pop_back();
    } else {
        if (block.else_seen)
            diagnostic(position, "error", "#" + name + " after #else");
        if (name == "else") {
            if (block.parent && !operands.empty())
                diagnostic(position, "warning", "extra tokens at end of #else directive");
            block.else_seen = true;
            if (block.parent) {
                block.active = !block.chosen;
                block.chosen = true;
                description = block.active ? "taken" : "not taken";
            } else {
                block.active = false;
                description = "skipped";
            }
        } else if (!block.parent) {
            block.active = false;
            description = "skipped";
        } else if (block.chosen) {
            block.active = false;
            description = "not evaluated";
        } else {
            TestResult tested = test(inclusion, line, name, operands);
            block.active = tested.valid && tested.value;
            if (block.active)
                block.chosen = true;
            description = test_description(name, tested);
        }
        if (block.parent && !block.active)
            block.skip_start = line.end + 1;
    }
    conditional_record(position, depth, name, operands, description);
}
void Preprocessor::include(Inclusion &inclusion, const LogicalLine &line, Tokens operands) {
    Position position = inclusion.position(line.tokens[0].line);
    std::optional<Header> header;
    try {
        header = read_header(operands, 0);
        if (!header && !operands.empty()) {
            operands = expand(*this, inclusion, operands);
            header = read_header(operands, 0);
        }
    } catch (const PreprocessingError &error) {
        diagnostic(position, "error", error.message);
        return;
    }
    if (!header) {
        diagnostic(position, "error", "#include expects \"FILENAME\" or <FILENAME>");
        return;
    }
    if (header->next < operands.size())
        diagnostic(position, "warning", "extra tokens at end of #include directive");
    if (header->name.empty()) {
        diagnostic(position, "error", "empty filename in #include");
        return;
    }
    std::string prefix = std::string(2 * (inclusion.depth + 1), ' ') +
                         std::to_string(line.tokens[0].line) + ": ",
                path = manager.search(header->name, header->quoted);
    if (path.empty()) {
        tree.push_back(prefix + header->rendering + " [not found]");
        diagnostic(position, "error", "cannot find include file " + header->rendering);
        return;
    }
    auto previous = manager.files.find(path);
    if (previous != manager.files.end() && previous->second->once) {
        tree.push_back(prefix + path + " [skipped: pragma once]");
        ++previous->second->skipped;
        return;
    }
    if (previous != manager.files.end() && !previous->second->guard.empty() &&
        macros.count(previous->second->guard)) {
        tree.push_back(prefix + path + " [skipped: guard " + previous->second->guard + "]");
        ++previous->second->skipped;
        return;
    }
    if (inclusion.depth + 1 > 8) {
        tree.push_back(prefix + path + " [too deep]");
        diagnostic(position, "error", "#include nested too deeply");
        return;
    }
    tree.push_back(prefix + path);
    marker(path, 1, 1);
    process_file(path, inclusion.depth + 1);
    Position next = inclusion.position(line.end + 1);
    marker(next.file, next.line, 2);
}
void Preprocessor::line_directive(Inclusion &inclusion, const LogicalLine &line, Tokens operands) {
    Position position = inclusion.position(line.tokens[0].line);
    if (operands.empty() || !decimal_token(operands[0]))
        operands = expand(*this, inclusion, operands);
    if (operands.empty() || operands.size() > 2 || !decimal_token(operands[0]) ||
        (operands.size() == 2 && operands[1].kind != "string")) {
        diagnostic(position, "error", "invalid #line directive");
        return;
    }
    int64_t number = std::stoll(operands[0].spelling);
    if (number < 1 || number > 2147483647LL) {
        diagnostic(position, "error", "line number out of range");
        return;
    }
    inclusion.offset = static_cast<int>(number) - (line.end + 1);
    if (operands.size() == 2)
        inclusion.display_file = operands[1].spelling.substr(1, operands[1].spelling.size() - 2);
}
void Preprocessor::macro_pragma(Position position, const Tokens &operands,
                                const std::string &operation) {
    if (operands.size() != 4 || operands[1].spelling != "(" || operands[2].kind != "string" ||
        operands[3].spelling != ")") {
        diagnostic(position, "error", "invalid #pragma " + operation + " directive");
        return;
    }
    std::string name = operands[2].spelling.substr(1, operands[2].spelling.size() - 2);
    if (operation == "push_macro") {
        auto found = macros.find(name);
        saved[name].push_back(found == macros.end() ? nullptr : found->second);
        event(position, "push " + name);
        return;
    }
    auto &stack = saved[name];
    if (stack.empty()) {
        diagnostic(position, "warning", "no matching push_macro for \"" + name + "\"");
        return;
    }
    std::shared_ptr<Macro> macro = stack.back();
    stack.pop_back();
    if (!macro) {
        macros.erase(name);
        event(position, "pop " + name + " (undefined)");
    } else {
        macros[name] = macro;
        event(position, "pop " + name);
    }
}
void Preprocessor::pragma(Inclusion &inclusion, const LogicalLine &line, const Tokens &operands) {
    Position position = inclusion.position(line.tokens[0].line);
    std::string name =
        !operands.empty() && operands[0].kind == "identifier" ? operands[0].spelling : "";
    if (name == "once") {
        if (operands.size() > 1)
            diagnostic(position, "warning", "extra tokens at end of #pragma once directive");
        if (inclusion.depth == 0)
            diagnostic(position, "warning", "#pragma once in main file");
        inclusion.source->once = true;
    } else if (operands.size() >= 2 && operands[0].spelling == "GCC" &&
               operands[1].spelling == "poison") {
        for (size_t i = 2; i < operands.size(); ++i)
            if (operands[i].kind != "identifier") {
                diagnostic(position, "error", "invalid #pragma GCC poison directive");
                return;
            }
        for (size_t i = 2; i < operands.size(); ++i) {
            const std::string &name = operands[i].spelling;
            if (macros.count(name))
                diagnostic(position, "warning", "poisoning existing macro \"" + name + "\"");
            poisoned.insert(name);
        }
    } else if (name == "push_macro" || name == "pop_macro")
        macro_pragma(position, operands, name);
    else
        output_line(inclusion, line.tokens[0].line,
                    operands.empty() ? "#pragma" : "#pragma " + render(operands));
}
void Preprocessor::directive(Inclusion &inclusion, const LogicalLine &line, const std::string &name,
                             const Tokens &operands) {
    if (line.tokens.size() == 1)
        return;
    bool poisoning = name == "pragma" && operands.size() >= 2 && operands[0].spelling == "GCC" &&
                     operands[1].spelling == "poison";
    if (!poisoning)
        poison_check(inclusion, operands);
    Position position = inclusion.position(line.tokens[0].line);
    if (name == "define")
        define(operands, position, inclusion.depth == 0);
    else if (name == "undef")
        undefine(operands, position);
    else if (name == "include")
        include(inclusion, line, operands);
    else if (name == "line")
        line_directive(inclusion, line, operands);
    else if (name == "error" || name == "warning")
        diagnostic(position, name, "#" + name + (operands.empty() ? "" : " " + render(operands)));
    else if (name == "pragma")
        pragma(inclusion, line, operands);
    else
        diagnostic(position, "error",
                   "invalid preprocessing directive #" + line.tokens[1].spelling);
}
void Preprocessor::process_file(const std::string &path, int depth) {
    FileData *source = manager.load(path);
    ++source->entered;
    Inclusion inclusion;
    inclusion.source = source;
    inclusion.depth = depth;
    inclusion.display_file = path;
    for (const LogicalLine &line : source->lines) {
        bool is_directive = !line.tokens.empty() && line.tokens[0].spelling == "#";
        std::string name = directive_name(line.tokens);
        Tokens operands =
            line.tokens.size() > 2 ? Tokens(line.tokens.begin() + 2, line.tokens.end()) : Tokens{};
        if (is_directive && word_in("if ifdef ifndef elif elifdef elifndef else endif", name)) {
            flush(inclusion);
            conditional(inclusion, line, name, operands);
        } else if (inclusion.skipping())
            continue;
        else if (is_directive) {
            flush(inclusion);
            directive(inclusion, line, name, operands);
        } else
            inclusion.segment.insert(inclusion.segment.end(), line.tokens.begin(),
                                     line.tokens.end());
    }
    flush(inclusion);
    for (ConditionalBlock &block : inclusion.stack)
        close_region(inclusion, block, source->physical_lines);
    for (const ConditionalBlock &block : inclusion.stack)
        diagnostic(block.start, "error", "unterminated #" + block.kind);
}
static void write_lines(const std::string &name, const std::vector<std::string> &lines) {
    std::ofstream output("output/" + name);
    for (const std::string &line : lines) {
        size_t end = line.find_last_not_of(' ');
        output << (end == std::string::npos ? "" : line.substr(0, end + 1)) << "\n";
    }
}
void Preprocessor::write_reports() {
    std::vector<std::string> includes = tree;
    includes.push_back("");
    includes.push_back("== files ==");
    for (const auto &entry : manager.files) {
        const FileData &file = *entry.second;
        includes.push_back(entry.first + " entered=" + std::to_string(file.entered) +
                           " skipped=" + std::to_string(file.skipped) +
                           " lines=" + std::to_string(file.physical_lines) +
                           " output_lines=" + std::to_string(file.output_lines) +
                           " skipped_lines=" + std::to_string(file.skipped_lines) +
                           " guard=" + (file.guard.empty() ? "-" : file.guard) +
                           " once=" + (file.once ? "yes" : "no"));
    }
    includes.emplace_back();
    std::string current = "main.o:";
    bool has_path = false;
    for (const std::string &path : manager.order) {
        if (current.size() + 1 + path.size() > 76 && has_path) {
            includes.push_back(current + " \\");
            current = " ";
            has_path = false;
        }
        current += " " + path;
        has_path = true;
    }
    includes.push_back(current);
    std::vector<std::string> macro_report = {"== history =="};
    macro_report.insert(macro_report.end(), history.begin(), history.end());
    macro_report.emplace_back();
    macro_report.push_back("== table ==");
    std::map<std::string, std::set<std::string>> references;
    for (const auto &entry : macros) {
        const Macro &macro = *entry.second;
        std::set<std::string> parameters(macro.parameters.begin(), macro.parameters.end());
        for (const Token &token : macro.replacement)
            if (token.kind == "identifier" && macros.count(token.spelling) &&
                !parameters.count(token.spelling))
                references[entry.first].insert(token.spelling);
    }
    auto recursive = [&](const std::string &name) {
        std::vector<std::string> pending(references[name].begin(), references[name].end());
        std::set<std::string> seen;
        while (!pending.empty()) {
            std::string current = pending.back();
            pending.pop_back();
            if (current == name)
                return true;
            if (seen.insert(current).second)
                pending.insert(pending.end(), references[current].begin(),
                               references[current].end());
        }
        return false;
    };
    int objects = 0;
    for (const auto &entry : macros) {
        const Macro &macro = *entry.second;
        macro_report.push_back("#define " + macro.signature() +
                               (macro.replacement.empty() ? "" : " " + render(macro.replacement)));
        macro_report.push_back("  at " + position_text(macro.position) +
                               " expanded=" + std::to_string(macro.expanded) +
                               " tested=" + std::to_string(macro.tested) +
                               " recursive=" + (recursive(entry.first) ? "yes" : "no"));
        std::string refs = "  refs:";
        for (const std::string &name : references[entry.first])
            refs += " " + name;
        macro_report.push_back(refs);
        if (!macro.function)
            ++objects;
    }
    macro_report.emplace_back();
    macro_report.push_back("macros=" + std::to_string(macros.size()) +
                           " object_like=" + std::to_string(objects) +
                           " function_like=" + std::to_string(macros.size() - objects));
    std::string undefined = "undefined:";
    for (const std::string &name : ever_defined)
        if (!macros.count(name))
            undefined += " " + name;
    macro_report.push_back(undefined);
    macro_report.push_back(
        "builtins: __COUNTER__=" + std::to_string(builtin_counts["__COUNTER__"]) +
        " __FILE__=" + std::to_string(builtin_counts["__FILE__"]) +
        " __LINE__=" + std::to_string(builtin_counts["__LINE__"]));
    std::vector<std::string> conditional_report = conditionals;
    conditional_report.emplace_back();
    conditional_report.push_back("== skipped regions ==");
    conditional_report.insert(conditional_report.end(), regions.begin(), regions.end());
    conditional_report.emplace_back();
    conditional_report.push_back(
        "directives=" + std::to_string(conditionals.size()) +
        " taken=" + std::to_string(condition_counts["taken"]) +
        " not_taken=" + std::to_string(condition_counts["not_taken"]) +
        " skipped=" + std::to_string(condition_counts["skipped"]) +
        " not_evaluated=" + std::to_string(condition_counts["not_evaluated"]) + " endif=" +
        std::to_string(condition_counts["endif"]) + " regions=" + std::to_string(regions.size()));
    diagnostics.push_back("errors=" + std::to_string(diagnostic_counts["error"]) +
                          " warnings=" + std::to_string(diagnostic_counts["warning"]));
    std::filesystem::create_directories("output");
    write_lines("preprocessed.txt", output);
    write_lines("includes.txt", includes);
    write_lines("macros.txt", macro_report);
    write_lines("conditionals.txt", conditional_report);
    write_lines("diagnostics.txt", diagnostics);
}
int main() {
    Preprocessor preprocessor;
    preprocessor.process_defines();
    preprocessor.marker("main.c", 1);
    preprocessor.process_file("main.c", 0);
    for (const auto &entry : preprocessor.macros)
        preprocessor.unused_check(*entry.second);
    preprocessor.write_reports();
}
