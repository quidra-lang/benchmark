#include "regex.hpp"
static std::unique_ptr<Node> node(const std::string &kind) {
    auto result = std::make_unique<Node>();
    result->kind = kind;
    return result;
}
struct ClassItem {
    CharSet set;
    int character;
    bool set_item;
};
struct PatternParser {
    Pattern &pattern;
    size_t index = 0;
    std::vector<Node *> references;
    unsigned char peek(size_t offset = 0) const {
        return index + offset < pattern.source.size()
                   ? static_cast<unsigned char>(pattern.source[index + offset])
                   : 0;
    }
    void fail(const std::string &message, int column) const { throw PatternError{message, column}; }
    std::string digits() {
        size_t start = index;
        while (digit(peek()))
            ++index;
        return pattern.source.substr(start, index - start);
    }
    std::string name() {
        size_t start = index;
        if (letter(peek()) || peek() == '_') {
            ++index;
            while (letter(peek()) || digit(peek()) || peek() == '_')
                ++index;
        }
        if (start == index || peek() != '>')
            fail("invalid group name", static_cast<int>(index) + 1);
        std::string result = pattern.source.substr(start, index - start);
        ++index;
        return result;
    }
    bool quantifier(unsigned char c) const {
        return c && std::string("*+?{").find(static_cast<char>(c)) != std::string::npos;
    }
    std::unique_ptr<Node> parse() {
        auto root = alternation();
        if (index != pattern.source.size())
            fail("unmatched )", static_cast<int>(index) + 1);
        for (Node *reference : references) {
            if (!reference->name.empty()) {
                auto found = pattern.names.find(reference->name);
                if (found == pattern.names.end())
                    fail("unknown group name", reference->column);
                reference->number = found->second;
            } else if (reference->number > pattern.groups)
                fail("invalid group reference", reference->column);
        }
        return root;
    }
    std::unique_ptr<Node> alternation() {
        std::vector<std::unique_ptr<Node>> children;
        children.push_back(concatenation());
        while (peek() == '|') {
            ++index;
            children.push_back(concatenation());
        }
        if (children.size() == 1)
            return std::move(children[0]);
        auto result = node("alternation");
        result->children = std::move(children);
        return result;
    }
    std::unique_ptr<Node> concatenation() {
        std::vector<std::unique_ptr<Node>> children;
        while (peek() && peek() != '|' && peek() != ')')
            children.push_back(quantified());
        if (children.size() == 1)
            return std::move(children[0]);
        auto result = node("concat");
        result->children = std::move(children);
        return result;
    }
    std::unique_ptr<Node> quantified() {
        if (quantifier(peek()))
            fail("nothing to repeat", static_cast<int>(index) + 1);
        auto child = element();
        if (!quantifier(peek()))
            return child;
        if (child->kind == "assert" || child->kind == "look")
            fail("nothing to repeat", static_cast<int>(index) + 1);
        int lower = 0, upper = -1;
        if (peek() == '*')
            ++index;
        else if (peek() == '+') {
            lower = 1;
            ++index;
        } else if (peek() == '?') {
            upper = 1;
            ++index;
        } else {
            int column = static_cast<int>(index) + 1;
            ++index;
            std::string first = digits();
            if (first.empty())
                fail("invalid quantifier", column);
            lower = std::stoi(first);
            if (peek() == '}')
                upper = lower;
            else if (peek() == ',') {
                ++index;
                if (peek() != '}') {
                    std::string last = digits();
                    if (last.empty())
                        fail("invalid quantifier", column);
                    upper = std::stoi(last);
                }
            } else
                fail("invalid quantifier", column);
            if (peek() != '}')
                fail("invalid quantifier", column);
            ++index;
            if (lower > 100 || upper > 100)
                fail("quantifier too large", column);
            if (upper >= 0 && lower > upper)
                fail("quantifier range out of order", column);
        }
        std::string mode = "greedy";
        if (peek() == '?') {
            mode = "lazy";
            ++index;
        } else if (peek() == '+') {
            mode = "possessive";
            ++index;
        }
        if (quantifier(peek()))
            fail("nested quantifier", static_cast<int>(index) + 1);
        auto result = node("repeat");
        result->child = std::move(child);
        result->lower = lower;
        result->upper = upper;
        result->mode = mode;
        return result;
    }
    std::unique_ptr<Node> element() {
        unsigned char c = peek();
        if (c == '(')
            return group();
        if (c == '[')
            return character_class();
        if (c == '\\')
            return escape();
        ++index;
        auto result = node(c == '.' ? "any" : c == '^' || c == '$' ? "assert" : "literal");
        if (c == '^' || c == '$')
            result->value = c == '^' ? "BOL" : "EOL";
        else
            result->character = c;
        return result;
    }
    std::unique_ptr<Node> group() {
        int column = static_cast<int>(index) + 1;
        ++index;
        unsigned char kind = 'c';
        std::string group_name;
        if (peek() == '?') {
            ++index;
            kind = peek();
            if (kind != ':' && kind != '=' && kind != '!' && kind != '<')
                fail("invalid group", column);
            ++index;
            if (kind == '<') {
                int name_column = static_cast<int>(index) + 1;
                group_name = name();
                if (pattern.names.count(group_name))
                    fail("duplicate group name", name_column);
            }
        }
        int number = 0;
        if (kind == 'c' || kind == '<') {
            number = ++pattern.groups;
            if (!group_name.empty())
                pattern.names[group_name] = number;
        }
        auto content = alternation();
        if (peek() != ')')
            fail("missing )", column);
        ++index;
        if (kind == ':')
            return content;
        auto result = node(kind == '=' || kind == '!' ? "look" : "group");
        result->positive = kind == '=';
        result->number = number;
        result->child = std::move(content);
        return result;
    }
    ClassItem class_item() {
        unsigned char c = peek();
        ++index;
        if (c == '\\') {
            int column = static_cast<int>(index);
            c = peek();
            if (!c)
                fail("trailing backslash", column);
            ++index;
            if (std::string("dDwWsS").find(static_cast<char>(c)) != std::string::npos)
                return {standard_set(c), 0, true};
            if (c == 'n')
                c = '\n';
            else if (c == 't')
                c = '\t';
            else if (letter(c) || digit(c))
                fail("invalid escape", column);
        }
        CharSet set;
        set.set(c);
        return {set, c, false};
    }
    std::unique_ptr<Node> character_class() {
        int column = static_cast<int>(index) + 1;
        ++index;
        bool negated = false;
        if (peek() == '^') {
            negated = true;
            ++index;
        }
        if (peek() == ']')
            fail("empty class", static_cast<int>(index) + 1);
        CharSet set;
        while (true) {
            if (!peek())
                fail("missing ]", column);
            if (peek() == ']') {
                ++index;
                break;
            }
            ClassItem first = class_item();
            if (peek() == '-' && peek(1) && peek(1) != ']') {
                int dash = static_cast<int>(index) + 1;
                ++index;
                if (first.set_item)
                    fail("invalid range", dash);
                ClassItem last = class_item();
                if (last.set_item || first.character > last.character)
                    fail("invalid range", dash);
                for (int c = first.character; c <= last.character; ++c)
                    set.set(static_cast<size_t>(c));
            } else
                set |= first.set;
        }
        auto result = node("class");
        result->set = set;
        result->negated = negated;
        return result;
    }
    std::unique_ptr<Node> escape() {
        int column = static_cast<int>(index) + 1;
        ++index;
        unsigned char c = peek();
        if (!c)
            fail("trailing backslash", column);
        ++index;
        if (std::string("dDwWsS").find(static_cast<char>(c)) != std::string::npos) {
            auto result = node("class");
            result->set = standard_set(static_cast<unsigned char>(c | 32));
            result->negated = c >= 'A' && c <= 'Z';
            return result;
        }
        if (c == 'b' || c == 'B') {
            auto result = node("assert");
            result->value = c == 'b' ? "WORD" : "NOTWORD";
            return result;
        }
        if (c == 'n' || c == 't') {
            auto result = node("literal");
            result->character = c == 'n' ? '\n' : '\t';
            return result;
        }
        auto result = node("backref");
        result->column = column;
        if (c >= '1' && c <= '9')
            result->number = std::stoi(std::string(1, static_cast<char>(c)) + digits());
        else if (c == 'k') {
            if (peek() != '<')
                fail("invalid escape", column);
            ++index;
            result->name = name();
        } else {
            if (letter(c) || digit(c))
                fail("invalid escape", column);
            result->kind = "literal";
            result->character = c;
            return result;
        }
        references.push_back(result.get());
        return result;
    }
};
struct Compiler {
    std::vector<Instruction> program;
    int emit(const std::string &op) {
        Instruction instruction;
        instruction.op = op;
        program.push_back(instruction);
        return static_cast<int>(program.size()) - 1;
    }
    void save(int number) { program[static_cast<size_t>(emit("SAVE"))].number = number; }
    void split_targets(int index, int continuing, int stopping, bool lazy) {
        program[static_cast<size_t>(index)].x = lazy ? stopping : continuing;
        program[static_cast<size_t>(index)].y = lazy ? continuing : stopping;
    }
    void repetition(const Node &e, bool lazy) {
        if (e.upper < 0) {
            if (e.lower == 0) {
                int h = emit("SPLIT");
                compile(*e.child);
                int back = emit("JMP");
                program[static_cast<size_t>(back)].x = h;
                split_targets(h, h + 1, static_cast<int>(program.size()), lazy);
            } else {
                for (int i = 0; i < e.lower - 1; ++i)
                    compile(*e.child);
                int h = static_cast<int>(program.size());
                compile(*e.child);
                int split = emit("SPLIT");
                split_targets(split, h, static_cast<int>(program.size()), lazy);
            }
        } else {
            for (int i = 0; i < e.lower; ++i)
                compile(*e.child);
            std::vector<int> splits;
            for (int i = e.lower; i < e.upper; ++i) {
                int split = emit("SPLIT");
                splits.push_back(split);
                compile(*e.child);
            }
            int end = static_cast<int>(program.size());
            for (int split : splits)
                split_targets(split, split + 1, end, lazy);
        }
    }
    void compile(const Node &e) {
        if (e.kind == "literal")
            program[static_cast<size_t>(emit("CHAR"))].character = e.character;
        else if (e.kind == "any")
            emit("ANY");
        else if (e.kind == "class") {
            int index = emit("CLASS");
            program[static_cast<size_t>(index)].set = e.set;
            program[static_cast<size_t>(index)].negated = e.negated;
        } else if (e.kind == "assert")
            program[static_cast<size_t>(emit("ASSERT"))].kind = e.value;
        else if (e.kind == "backref")
            program[static_cast<size_t>(emit("BACKREF"))].number = e.number;
        else if (e.kind == "group") {
            save(2 * e.number);
            compile(*e.child);
            save(2 * e.number + 1);
        } else if (e.kind == "look") {
            int index = emit("LOOK");
            program[static_cast<size_t>(index)].kind = e.positive ? "AHEAD" : "NOT";
            compile(*e.child);
            emit("MATCH");
            program[static_cast<size_t>(index)].x = static_cast<int>(program.size());
        } else if (e.kind == "concat")
            for (const auto &child : e.children)
                compile(*child);
        else if (e.kind == "alternation") {
            std::vector<int> jumps;
            for (size_t i = 0; i + 1 < e.children.size(); ++i) {
                int split = emit("SPLIT");
                program[static_cast<size_t>(split)].x = split + 1;
                compile(*e.children[i]);
                jumps.push_back(emit("JMP"));
                program[static_cast<size_t>(split)].y = static_cast<int>(program.size());
            }
            compile(*e.children.back());
            for (int jump : jumps)
                program[static_cast<size_t>(jump)].x = static_cast<int>(program.size());
        } else if (e.kind == "repeat") {
            if (e.mode == "possessive") {
                int index = emit("LOOK");
                program[static_cast<size_t>(index)].kind = "ATOMIC";
                repetition(e, false);
                emit("MATCH");
                program[static_cast<size_t>(index)].x = static_cast<int>(program.size());
            } else
                repetition(e, e.mode == "lazy");
        }
    }
};
struct LengthRange {
    int64_t minimum = 0, maximum = 0;
};
static LengthRange length_range(const Node &e) {
    if (e.kind == "literal" || e.kind == "any" || e.kind == "class")
        return {1, 1};
    if (e.kind == "assert" || e.kind == "look")
        return {};
    if (e.kind == "backref")
        return {0, -1};
    if (e.kind == "group")
        return length_range(*e.child);
    if (e.kind == "repeat") {
        LengthRange child = length_range(*e.child);
        int64_t maximum = child.maximum == 0                 ? 0
                          : child.maximum < 0 || e.upper < 0 ? -1
                                                             : child.maximum * e.upper;
        return {child.minimum * e.lower, maximum};
    }
    LengthRange result;
    bool first = true;
    for (const auto &child : e.children) {
        LengthRange next = length_range(*child);
        if (e.kind == "concat") {
            result.minimum += next.minimum;
            result.maximum =
                result.maximum < 0 || next.maximum < 0 ? -1 : result.maximum + next.maximum;
        } else {
            if (first)
                result = next;
            else {
                result.minimum = std::min(result.minimum, next.minimum);
                result.maximum = result.maximum < 0 || next.maximum < 0
                                     ? -1
                                     : std::max(result.maximum, next.maximum);
            }
            first = false;
        }
    }
    return result;
}
struct FirstSet {
    CharSet set;
    bool nullable = true;
};
static FirstSet first_set(const Node &e, const std::string &flags) {
    if (e.kind == "literal") {
        CharSet set;
        set.set(e.character);
        if (flags.find('i') != std::string::npos && letter(e.character))
            set.set(swapped(e.character));
        return {set, false};
    }
    if (e.kind == "any" || e.kind == "class") {
        CharSet set;
        for (int c = 0; c < 128; ++c)
            if (e.kind == "any"
                    ? (flags.find('s') != std::string::npos || c != '\n')
                    : class_matches(e.set, e.negated, static_cast<unsigned char>(c), flags))
                set.set(static_cast<size_t>(c));
        return {set, false};
    }
    if (e.kind == "assert" || e.kind == "look")
        return {};
    if (e.kind == "backref") {
        CharSet set;
        set.set();
        return {set, true};
    }
    if (e.kind == "group")
        return first_set(*e.child, flags);
    if (e.kind == "repeat") {
        if (e.upper == 0)
            return {};
        FirstSet child = first_set(*e.child, flags);
        child.nullable = child.nullable || e.lower == 0;
        return child;
    }
    FirstSet result;
    if (e.kind == "alternation")
        result.nullable = false;
    for (const auto &child : e.children) {
        FirstSet next = first_set(*child, flags);
        result.set |= next.set;
        if (e.kind == "concat") {
            if (!next.nullable) {
                result.nullable = false;
                break;
            }
        } else
            result.nullable = result.nullable || next.nullable;
    }
    return result;
}
static std::vector<std::string> read_lines(const std::string &path) {
    std::ifstream input(path);
    std::vector<std::string> result;
    std::string line;
    while (std::getline(input, line))
        result.push_back(line);
    return result;
}
static std::string decode(const std::string &quoted) {
    std::string result;
    for (size_t i = 1; i + 1 < quoted.size(); ++i) {
        char c = quoted[i];
        if (c == '\\') {
            c = quoted[++i];
            if (c == 'n')
                c = '\n';
            else if (c == 't')
                c = '\t';
        }
        result += c;
    }
    return result;
}
struct TemplatePart {
    std::string text;
    int group = -1;
};
struct TemplateError {};
static std::vector<TemplatePart> parse_template(const std::string &text, const Pattern &pattern) {
    std::vector<TemplatePart> result;
    std::string literal;
    auto flush = [&]() {
        if (!literal.empty()) {
            result.push_back({literal, -1});
            literal.clear();
        }
    };
    for (size_t i = 0; i < text.size();) {
        if (text[i] != '$') {
            literal += text[i++];
            continue;
        }
        ++i;
        if (i == text.size())
            throw TemplateError{};
        if (text[i] == '$') {
            literal += '$';
            ++i;
            continue;
        }
        int number = -1;
        if (digit(static_cast<unsigned char>(text[i])))
            number = text[i++] - '0';
        else if (text[i] == '{') {
            size_t end = text.find('}', i + 1);
            if (end == std::string::npos)
                throw TemplateError{};
            std::string name = text.substr(i + 1, end - i - 1);
            if (!name.empty() &&
                std::all_of(name.begin(), name.end(), [](unsigned char c) { return digit(c); }))
                number = std::stoi(name);
            else {
                auto found = pattern.names.find(name);
                if (found == pattern.names.end())
                    throw TemplateError{};
                number = found->second;
            }
            i = end + 1;
        } else
            throw TemplateError{};
        if (number > pattern.groups)
            throw TemplateError{};
        flush();
        result.push_back({"", number});
    }
    flush();
    return result;
}
static bool group_set(const Captures &captures, int number) {
    return captures[static_cast<size_t>(2 * number)] >= 0 &&
           captures[static_cast<size_t>(2 * number + 1)] >= 0;
}
static std::string captured(const Captures &captures, int number, const std::string &text) {
    if (!group_set(captures, number))
        return "";
    int first = captures[static_cast<size_t>(2 * number)],
        last = captures[static_cast<size_t>(2 * number + 1)];
    return text.substr(static_cast<size_t>(first), static_cast<size_t>(last - first));
}
static std::string expand_template(const std::vector<TemplatePart> &parts, const Captures &captures,
                                   const std::string &text) {
    std::string result;
    for (const TemplatePart &part : parts)
        result += part.group < 0 ? part.text : captured(captures, part.group, text);
    return result;
}
template <class VM> static std::vector<Captures> matches(VM &vm, bool scan) {
    std::vector<Captures> result;
    if (!scan) {
        std::optional<Captures> found = vm.search(0);
        if (found)
            result.push_back(std::move(*found));
        return result;
    }
    int start = 0;
    while (start <= static_cast<int>(vm.text.size())) {
        std::optional<Captures> found = vm.search(start);
        if (!found)
            break;
        start = (*found)[1] > (*found)[0] ? (*found)[1] : (*found)[1] + 1;
        result.push_back(std::move(*found));
    }
    return result;
}
static std::string span(const Captures &captures, int number, const std::string &text) {
    return std::to_string(captures[static_cast<size_t>(2 * number)]) + "-" +
           std::to_string(captures[static_cast<size_t>(2 * number + 1)]) + " " +
           quote(captured(captures, number, text));
}
static void match_lines(std::ostream &output, const Captures &captures, const Pattern &pattern,
                        const std::string &text) {
    output << "match " << span(captures, 0, text) << "\n";
    for (int k = 1; k <= pattern.groups; ++k)
        output << "group " << k << " " << (group_set(captures, k) ? span(captures, k, text) : "-")
               << "\n";
}
static void list_program(std::ostream &output, const Pattern &pattern) {
    std::vector<std::pair<int, std::string>> names;
    for (const auto &entry : pattern.names)
        names.push_back({entry.second, entry.first});
    std::sort(names.begin(), names.end());
    std::string name_list;
    for (const auto &entry : names) {
        if (!name_list.empty())
            name_list += ",";
        name_list += entry.second + ":" + std::to_string(entry.first);
    }
    if (name_list.empty())
        name_list = "-";
    LengthRange length = length_range(*pattern.root);
    FirstSet first = first_set(*pattern.root, pattern.flags);
    output << "=== " << pattern.name << "\nflags=" << pattern.flags << " groups=" << pattern.groups
           << " names=" << name_list << " length=" << length.minimum << ".."
           << (length.maximum < 0 ? "inf" : std::to_string(length.maximum))
           << " first=" << (first.set.none() ? "-" : set_notation(first.set))
           << " pike=" << (pattern.pike ? "yes" : "no") << " size=" << pattern.program.size()
           << "\n";
    for (size_t i = 0; i < pattern.program.size(); ++i)
        output << i << " " << instruction_notation(pattern.program[i]) << "\n";
}
int main() {
    std::vector<std::unique_ptr<Pattern>> patterns;
    std::map<std::string, Pattern *> pattern_names;
    for (const std::string &line : read_lines("input/patterns.txt")) {
        size_t first = line.find(' '), second = line.find(' ', first + 1);
        auto pattern = std::make_unique<Pattern>();
        pattern->name = line.substr(0, first);
        pattern->flags = line.substr(first + 1, second - first - 1);
        pattern->source = line.substr(second + 1);
        PatternParser parser{*pattern, 0, {}};
        try {
            pattern->root = parser.parse();
            Compiler compiler;
            compiler.save(0);
            compiler.compile(*pattern->root);
            compiler.save(1);
            compiler.emit("MATCH");
            pattern->program = std::move(compiler.program);
            for (const Instruction &instruction : pattern->program)
                if (instruction.op == "LOOK" || instruction.op == "BACKREF")
                    pattern->pike = false;
        } catch (const PatternError &error) {
            pattern->error = error;
        }
        pattern_names[pattern->name] = pattern.get();
        patterns.push_back(std::move(pattern));
    }
    std::map<std::string, std::string> subjects;
    for (const std::string &line : read_lines("input/subjects.txt")) {
        size_t space = line.find(' ');
        subjects[line.substr(0, space)] = decode(line.substr(space + 1));
    }
    std::filesystem::create_directories("output");
    std::ofstream results("output/results.txt"), programs("output/programs.txt"),
        steps("output/steps.csv"), errors("output/errors.txt");
    steps << "command,engine,steps\n";
    bool any_error = false, any_program = false;
    for (const auto &pattern : patterns)
        if (pattern->error) {
            any_error = true;
            errors << pattern->name << ": " << pattern->error->message << " at column "
                   << pattern->error->column << "\n  " << pattern->source << "\n"
                   << std::string(static_cast<size_t>(pattern->error->column + 1), ' ') << "^\n";
        }
    if (!any_error)
        errors << "no errors\n";
    int command_number = 0;
    for (const std::string &line : read_lines("input/commands.txt")) {
        ++command_number;
        results << "#" << command_number << " " << line << "\n";
        std::istringstream input(line);
        std::string command, mode, pattern_name, subject_name;
        input >> command;
        if (command == "REPLACE")
            input >> mode;
        input >> pattern_name;
        Pattern &pattern = *pattern_names.at(pattern_name);
        if (command != "LIST")
            input >> subject_name;
        if (pattern.error) {
            results << "invalid pattern\n";
            continue;
        }
        if (command == "LIST") {
            results << "instructions " << pattern.program.size() << "\n";
            list_program(programs, pattern);
            any_program = true;
            continue;
        }
        std::vector<TemplatePart> replacement;
        if (command == "REPLACE") {
            std::string quoted;
            std::getline(input, quoted);
            if (!quoted.empty() && quoted[0] == ' ')
                quoted.erase(quoted.begin());
            try {
                replacement = parse_template(decode(quoted), pattern);
            } catch (const TemplateError &) {
                results << "invalid template\n";
                continue;
            }
        }
        const std::string &text = subjects.at(subject_name);
        bool scanning =
            command == "FINDALL" || command == "SPLIT" || (command == "REPLACE" && mode == "ALL");
        bool full = command == "MATCH";
        BacktrackVM backtrack{pattern, text, full};
        std::vector<Captures> backtrack_matches;
        try {
            backtrack_matches = matches(backtrack, scanning);
        } catch (const TooManySteps &) {
        }
        steps << command_number << ",backtrack," << backtrack.steps << "\n";
        std::vector<Captures> chosen;
        std::string engine;
        if (pattern.pike) {
            PikeVM pike{pattern, text, full};
            chosen = matches(pike, scanning);
            steps << command_number << ",pike," << pike.steps << "\n";
            if (!backtrack.aborted && chosen != backtrack_matches) {
                results << "MISMATCH\n";
                continue;
            }
            engine = backtrack.aborted ? "pike (backtrack: TOO_MANY_STEPS)" : "both";
        } else {
            if (backtrack.aborted) {
                results << "TOO_MANY_STEPS\n";
                continue;
            }
            chosen = std::move(backtrack_matches);
            engine = "backtrack";
        }
        results << "engine " << engine << "\n";
        if (command == "MATCH" || command == "SEARCH") {
            if (chosen.empty())
                results << "no match\n";
            else
                match_lines(results, chosen[0], pattern, text);
        } else if (command == "FINDALL") {
            results << "matches " << chosen.size() << "\n";
            for (const Captures &captures : chosen)
                match_lines(results, captures, pattern, text);
        } else if (command == "REPLACE") {
            std::string output;
            int last = 0;
            for (const Captures &captures : chosen) {
                output +=
                    text.substr(static_cast<size_t>(last), static_cast<size_t>(captures[0] - last));
                output += expand_template(replacement, captures, text);
                last = captures[1];
            }
            output += text.substr(static_cast<size_t>(last));
            results << "replacements " << chosen.size() << "\nresult " << quote(output) << "\n";
        } else if (command == "SPLIT") {
            results << "pieces " << chosen.size() + 1 << "\n";
            int last = 0;
            for (const Captures &captures : chosen) {
                results << "piece "
                        << quote(text.substr(static_cast<size_t>(last),
                                             static_cast<size_t>(captures[0] - last)))
                        << "\n";
                for (int k = 1; k <= pattern.groups; ++k)
                    results << "group " << k << " "
                            << (group_set(captures, k) ? quote(captured(captures, k, text)) : "-")
                            << "\n";
                last = captures[1];
            }
            results << "piece " << quote(text.substr(static_cast<size_t>(last))) << "\n";
        }
    }
    if (!any_program)
        programs << "no programs\n";
}
