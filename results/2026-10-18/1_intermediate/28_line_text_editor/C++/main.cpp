#include <algorithm>
#include <array>
#include <cstdint>
#include <iostream>
#include <map>
#include <memory>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <variant>
#include <vector>

class EditorError : public std::runtime_error {
public:
    using std::runtime_error::runtime_error;
};

[[noreturn]] void fail(const std::string& reason) { throw EditorError(reason); }
bool digit(char ch) { return ch >= '0' && ch <= '9'; }
bool lower(char ch) { return ch >= 'a' && ch <= 'z'; }
bool upper(char ch) { return ch >= 'A' && ch <= 'Z'; }
bool contains(std::string_view choices, char ch) { return choices.find(ch) != std::string_view::npos; }
bool digits(const std::string& text) { return std::all_of(text.begin(), text.end(), digit); }
char lowercase(char ch) { return upper(ch) ? static_cast<char>(ch + ('a' - 'A')) : ch; }

using Text = std::vector<std::string>;
using Replacement = std::vector<std::optional<char>>; // nullopt denotes an unescaped '&'.

struct Delimited {
    std::string text;
    Replacement replacement;
    std::string raw;
    std::size_t next;
};

Delimited readDelimited(const std::string& source, std::size_t start, char delimiter) {
    std::string text;
    Replacement replacement;
    for (std::size_t i = start; i < source.size(); ++i) {
        char ch = source[i];
        if (ch == '\\') {
            if (++i == source.size()) fail("missing delimiter");
            ch = source[i];
            text += ch;
            replacement.emplace_back(ch);
        } else if (ch == delimiter) {
            return {text, replacement, source.substr(start, i - start), i + 1};
        } else {
            text += ch;
            replacement.push_back(ch == '&' ? std::nullopt : std::optional<char>(ch));
        }
    }
    fail("missing delimiter");
}

enum class ElementKind { number, offset, current, last, comma, semicolon, all, mark, forward, backward };

struct Element {
    ElementKind kind;
    std::string word;
};
using Address = std::vector<Element>;

struct AddressScan {
    Address elements;
    std::string command;
};

AddressScan scanAddress(const std::string& source) {
    Address elements;
    std::size_t i = 0;
    while (i < source.size()) {
        const char ch = source[i];
        if (digit(ch) || ch == '+' || ch == '-') {
            const std::size_t start = i++;
            while (i < source.size() && digit(source[i])) ++i;
            elements.push_back({digit(ch) ? ElementKind::number : ElementKind::offset, source.substr(start, i - start)});
        } else if (contains(".$,;%", ch)) {
            ElementKind kind = ElementKind::all;
            if (ch == '.') kind = ElementKind::current;
            else if (ch == '$') kind = ElementKind::last;
            else if (ch == ',') kind = ElementKind::comma;
            else if (ch == ';') kind = ElementKind::semicolon;
            elements.push_back({kind, ""});
            ++i;
        } else if (ch == '\'') {
            ++i;
            elements.push_back({ElementKind::mark, i < source.size() ? source.substr(i++, 1) : ""});
        } else if (ch == '/' || ch == '?') {
            const Delimited found = readDelimited(source, i + 1, ch);
            elements.push_back({ch == '/' ? ElementKind::forward : ElementKind::backward, found.text});
            i = found.next;
        } else break;
    }
    return {elements, source.substr(i)};
}

bool singleAddress(const Address& elements) {
    if (elements.empty()) return false;
    for (std::size_t i = 0; i < elements.size(); ++i) {
        const ElementKind kind = elements[i].kind;
        if (kind == ElementKind::offset) continue;
        if (i != 0 || kind == ElementKind::comma || kind == ElementKind::semicolon || kind == ElementKind::all) return false;
    }
    return true;
}

struct AddressForm {
    int count = 0;
    Address left, right;
    ElementKind separator = ElementKind::comma;
};

AddressForm addressForm(const Address& elements) {
    if (elements.empty()) return {};
    if (elements.size() == 1 && elements[0].kind == ElementKind::all) {
        return {2, {{ElementKind::number, "1"}}, {{ElementKind::last, ""}}, ElementKind::comma};
    }
    std::optional<std::size_t> separator;
    for (std::size_t i = 0; i < elements.size(); ++i) {
        if (elements[i].kind != ElementKind::comma && elements[i].kind != ElementKind::semicolon) continue;
        if (separator) fail("bad address");
        separator = i;
    }
    if (!separator) {
        if (!singleAddress(elements)) fail("bad address");
        return {1, elements, {}, ElementKind::comma};
    }
    Address left(elements.begin(), elements.begin() + *separator);
    Address right(elements.begin() + *separator + 1, elements.end());
    if ((!left.empty() && !singleAddress(left)) || (!right.empty() && !singleAddress(right))) fail("bad address");
    return {2, left, right, elements[*separator].kind};
}

enum class Kind {
    bare, append, insert, change, print, numbered, list, position, count, yank, marks, history, files,
    erase, put, join, joinWords, scroll, indent, unindent, undo, letterCase, redo, read, writePrint,
    write, writeAppend, edit, mark, move, copy, substitute, global, inverseGlobal, sort
};

struct Command {
    Kind kind;
    char suffix = '\0';
    std::optional<int> amount;
    std::string argument;
    Address destination;
    std::string pattern;
    std::optional<Replacement> replacement;
    bool allMatches = false;
    int occurrence = 1;
    std::unique_ptr<Command> subcommand;

    explicit Command(Kind kind) : kind(kind) {}
};

std::optional<int> positiveArgument(const std::string& argument) {
    if (argument.empty()) return std::nullopt;
    if (!digits(argument) || std::stoi(argument) == 0) fail("invalid suffix");
    return std::stoi(argument);
}

char printSuffix(const std::string& argument) {
    if (argument.empty()) return '\0';
    if (argument.size() != 1 || !contains("pnl", argument[0])) fail("invalid suffix");
    return argument[0];
}

std::string fileName(const std::string& argument) {
    if (argument.size() < 2 || argument.size() > 9 || argument[0] != ' '
        || !std::all_of(argument.begin() + 1, argument.end(), [](char ch) { return lower(ch) || digit(ch); })) {
        fail("invalid file name");
    }
    return argument.substr(1);
}

Command parseSubstitution(const std::string& argument) {
    Command command(Kind::substitute);
    std::string flags = argument;
    if (!std::all_of(argument.begin(), argument.end(), [](char ch) { return digit(ch) || contains("gpnl", ch); })) {
        const char delimiter = argument[0];
        if (delimiter == ' ' || delimiter == '\\') fail("missing delimiter");
        const Delimited search = readDelimited(argument, 1, delimiter);
        const Delimited replacement = readDelimited(argument, search.next, delimiter);
        command.pattern = search.text;
        if (replacement.raw != "%") command.replacement = replacement.replacement;
        flags = argument.substr(replacement.next);
    }
    bool counted = false;
    for (std::size_t i = 0; i < flags.size();) {
        const char ch = flags[i++];
        if (ch == 'g') {
            if (command.allMatches) fail("invalid suffix");
            command.allMatches = true;
        } else if (contains("pnl", ch)) {
            if (command.suffix != '\0') fail("invalid suffix");
            command.suffix = ch;
        } else if (digit(ch)) {
            if (counted) fail("invalid suffix");
            const std::size_t start = i - 1;
            while (i < flags.size() && digit(flags[i])) ++i;
            command.occurrence = std::stoi(flags.substr(start, i - start));
            if (command.occurrence == 0) fail("invalid suffix");
            counted = true;
        } else fail("invalid suffix");
    }
    return command;
}

bool sortForm(const std::string& source) { return source == "sort" || source.compare(0, 5, "sort ") == 0; }

Command parseCommand(const std::string& source) {
    if (sortForm(source)) {
        Command command(Kind::sort);
        command.argument = source == "sort" ? "" : source.substr(5);
        if (source != "sort") {
            std::string seen;
            if (command.argument.empty()) fail("invalid suffix");
            for (char ch : command.argument) {
                if (!contains("ruin", ch) || contains(seen, ch)) fail("invalid suffix");
                seen += ch;
            }
            if (contains(seen, 'i') && contains(seen, 'n')) fail("invalid suffix");
        }
        return command;
    }
    const char ch = source.empty() ? '\0' : source[0];
    const std::string argument = source.empty() ? "" : source.substr(1);
    static const std::map<char, Kind> plain = {
        {'\0', Kind::bare}, {'a', Kind::append}, {'i', Kind::insert}, {'c', Kind::change},
        {'p', Kind::print}, {'n', Kind::numbered}, {'l', Kind::list}, {'=', Kind::position},
        {'#', Kind::count}, {'y', Kind::yank}, {'K', Kind::marks}, {'h', Kind::history}, {'f', Kind::files}
    };
    const auto plainCommand = plain.find(ch);
    if (plainCommand != plain.end()) {
        if (!argument.empty()) fail("invalid suffix");
        return Command(plainCommand->second);
    }
    if (contains("dxjJ", ch)) {
        Command command(ch == 'd' ? Kind::erase : ch == 'x' ? Kind::put : ch == 'j' ? Kind::join : Kind::joinWords);
        command.suffix = printSuffix(argument);
        return command;
    }
    if (contains("z><u", ch)) {
        Command command(ch == 'z' ? Kind::scroll : ch == '>' ? Kind::indent : ch == '<' ? Kind::unindent : Kind::undo);
        command.amount = positiveArgument(argument);
        return command;
    }
    if (ch == '~') {
        if (!argument.empty() && argument != "u" && argument != "l") fail("invalid suffix");
        Command command(Kind::letterCase);
        command.argument = argument;
        return command;
    }
    if (ch == 'r' && digits(argument)) {
        Command command(Kind::redo);
        command.amount = positiveArgument(argument);
        return command;
    }
    if (ch == 'w' && argument.empty()) return Command(Kind::writePrint);
    if (contains("rwWe", ch)) {
        Command command(ch == 'r' ? Kind::read : ch == 'w' ? Kind::write : ch == 'W' ? Kind::writeAppend : Kind::edit);
        command.argument = fileName(argument);
        return command;
    }
    if (ch == 'k') {
        if (argument.size() != 1 || !lower(argument[0])) fail("invalid mark");
        Command command(Kind::mark);
        command.argument = argument;
        return command;
    }
    if (ch == 'm' || ch == 't') {
        const AddressScan destination = scanAddress(argument);
        if (!singleAddress(destination.elements)) fail("invalid destination");
        Command command(ch == 'm' ? Kind::move : Kind::copy);
        command.destination = destination.elements;
        command.suffix = printSuffix(destination.command);
        return command;
    }
    if (ch == 's') return parseSubstitution(argument);
    if (ch == 'g' || ch == 'v') {
        if (argument.empty() || argument[0] == ' ' || argument[0] == '\\') fail("missing delimiter");
        const Delimited search = readDelimited(argument, 1, argument[0]);
        const std::string subcommand = search.next == argument.size() ? "p" : argument.substr(search.next);
        if (!contains("pnldmtjJs><~aicx", subcommand[0]) || sortForm(subcommand)) fail("invalid global command");
        Command command(ch == 'g' ? Kind::global : Kind::inverseGlobal);
        command.pattern = search.text;
        command.subcommand = std::make_unique<Command>(parseCommand(subcommand));
        return command;
    }
    fail("unknown command");
}

bool hasText(const std::string& source) {
    try {
        const std::string command = scanAddress(source).command;
        if (command.size() == 1 && contains("aic", command[0])) return true;
        if (command.size() < 2 || !contains("gv", command[0]) || command[1] == ' ' || command[1] == '\\') return false;
        const Delimited search = readDelimited(command, 2, command[1]);
        return search.next + 1 == command.size() && contains("aic", command[search.next]);
    } catch (const EditorError&) { return false; }
}

int addressKind(Kind kind) {
    switch (kind) {
    case Kind::undo: case Kind::redo: case Kind::history: case Kind::marks: case Kind::files: case Kind::edit:
        return 0;
    case Kind::append: case Kind::insert: case Kind::put: case Kind::position: case Kind::read: case Kind::mark: case Kind::scroll:
        return 1;
    default: return 2;
    }
}

bool modifying(const Command& command) {
    switch (command.kind) {
    case Kind::global: case Kind::inverseGlobal:
        return command.subcommand->kind != Kind::print && command.subcommand->kind != Kind::numbered && command.subcommand->kind != Kind::list;
    case Kind::append: case Kind::insert: case Kind::change: case Kind::erase: case Kind::put:
    case Kind::join: case Kind::joinWords: case Kind::move: case Kind::copy: case Kind::substitute:
    case Kind::indent: case Kind::unindent: case Kind::letterCase: case Kind::sort: case Kind::read: case Kind::edit:
        return true;
    default: return false;
    }
}

struct Line {
    std::uint64_t id;
    std::string text;
};
using Buffer = std::vector<Line>;

struct Record {
    std::string command;
    std::shared_ptr<const Buffer> lines;
    int current;
};

struct State {
    Buffer lines;
    int current = 0;
    std::array<std::uint64_t, 26> marks{};
    Text cut;
    std::optional<std::string> pattern;
    std::optional<Replacement> replacement;
    int displayCount = 5;
    std::vector<Record> undo, redo;
    std::map<std::string, std::shared_ptr<const Text>> files;
    std::uint64_t nextId = 1;
};

int byteCount(const Text& text) {
    int count = 0;
    for (const std::string& line : text) count += static_cast<int>(line.size()) + 1;
    return count;
}

class Editor {
    State state;
    Text output;

    int last() const { return static_cast<int>(state.lines.size()); }
    void emit(std::string text) { output.push_back(std::move(text)); }

    Buffer newLines(const Text& text) {
        Buffer lines;
        for (const std::string& value : text) lines.push_back({state.nextId++, value});
        return lines;
    }

    Record snapshot(const std::string& command) const {
        return {command, std::make_shared<const Buffer>(state.lines), state.current};
    }

    Text contents(int a, int b) const {
        Text text;
        for (int i = a - 1; i < b; ++i) text.push_back(state.lines[i].text);
        return text;
    }

    void replace(int position, int count, const Buffer& inserted) {
        state.lines.erase(state.lines.begin() + position, state.lines.begin() + position + count);
        state.lines.insert(state.lines.begin() + position, inserted.begin(), inserted.end());
    }

    int lineNumber(std::uint64_t id) const {
        for (int i = 0; i < last(); ++i) if (state.lines[i].id == id) return i + 1;
        return 0;
    }

    std::string pattern(const std::string& text) {
        if (!text.empty()) state.pattern = text;
        if (!state.pattern) fail("no previous pattern");
        return *state.pattern;
    }

    int address(const Address& elements) {
        int value = state.current;
        std::size_t firstOffset = 0;
        const Element& base = elements[0];
        if (base.kind != ElementKind::offset) {
            firstOffset = 1;
            if (base.kind == ElementKind::number) value = std::stoi(base.word);
            else if (base.kind == ElementKind::current) value = state.current;
            else if (base.kind == ElementKind::last) value = last();
            else if (base.kind == ElementKind::mark) {
                if (base.word.size() != 1 || !lower(base.word[0])) fail("invalid mark");
                value = lineNumber(state.marks[base.word[0] - 'a']);
                if (value == 0) fail("mark not set");
            } else {
                const std::string search = pattern(base.word);
                value = 0;
                for (int step = 1; step <= last(); ++step) {
                    const int pivot = state.current == 0 && base.kind == ElementKind::backward ? last() + 1 : state.current;
                    const int index = base.kind == ElementKind::forward
                        ? (pivot + step - 1) % last() : (pivot - step - 1 + last()) % last();
                    if (state.lines[index].text.find(search) != std::string::npos) { value = index + 1; break; }
                }
                if (value == 0) fail("no match");
            }
        }
        for (std::size_t i = firstOffset; i < elements.size(); ++i) {
            const std::string& word = elements[i].word;
            const int magnitude = word.size() == 1 ? 1 : std::stoi(word.substr(1));
            value += word[0] == '+' ? magnitude : -magnitude;
        }
        return value;
    }

    std::vector<int> addresses(const AddressForm& form) {
        if (form.count == 0) return {};
        if (form.count == 1) return {address(form.left)};
        const int left = form.left.empty() ? (form.separator == ElementKind::comma ? 1 : state.current) : address(form.left);
        if (form.separator == ElementKind::semicolon) {
            if (left < 0 || left > last()) fail("address out of range");
            state.current = left;
        }
        return {left, form.right.empty() ? last() : address(form.right)};
    }

    std::pair<int, int> range(const Command& command, const std::vector<int>& values) const {
        const Kind kind = command.kind;
        const int category = addressKind(kind);
        if (category == 0) return {0, 0};
        if (category == 1) {
            const int fallback = kind == Kind::position || kind == Kind::read ? last() : state.current + (kind == Kind::scroll ? 1 : 0);
            const int a = values.empty() ? fallback : values[0];
            const int minimum = kind == Kind::mark || kind == Kind::scroll ? 1 : 0;
            if (a < minimum || a > last()) fail("address out of range");
            return {a, a};
        }
        int a, b;
        if (!values.empty()) { a = values.front(); b = values.back(); }
        else if (kind == Kind::writePrint || kind == Kind::write || kind == Kind::writeAppend || kind == Kind::count) return {1, last()};
        else if (kind == Kind::global || kind == Kind::inverseGlobal || kind == Kind::sort) { a = 1; b = last(); }
        else { a = state.current; b = state.current + (kind == Kind::join || kind == Kind::joinWords ? 1 : 0); }
        if (a < 1 || b < 1 || a > last() || b > last()) fail("address out of range");
        if (a > b || (a == b && (kind == Kind::join || kind == Kind::joinWords))) fail("invalid range");
        return {a, b};
    }

    void print(int number, char form) {
        const std::string& text = state.lines[number - 1].text;
        if (form == 'p') emit(text);
        else if (form == 'n') {
            const std::string label = std::to_string(number);
            emit(std::string(label.size() < 3 ? 3 - label.size() : 0, ' ') + label + " " + text);
        } else {
            std::string escaped;
            for (char ch : text) { escaped += ch; if (ch == '\\') escaped += ch; }
            escaped += '$';
            while (escaped.size() > 40) {
                emit(escaped.substr(0, 39) + "\\");
                escaped.erase(0, 39);
            }
            emit(escaped);
        }
    }

    void suffix(const Command& command) {
        if (command.suffix != '\0' && state.current > 0) print(state.current, command.suffix);
    }

    int substitute(const Command& command, int a, int b, bool insideGlobal) {
        const std::string search = pattern(command.pattern);
        const std::optional<Replacement> replacement = command.replacement ? command.replacement : state.replacement;
        if (!replacement) fail("no previous substitution");
        state.replacement = replacement;
        std::string expanded;
        for (const std::optional<char>& part : *replacement) expanded += part ? std::string(1, *part) : search;
        int changed = 0;
        for (int i = a - 1; i < b; ++i) {
            Line& line = state.lines[i];
            std::size_t position = 0;
            int occurrence = 0;
            std::string result;
            bool substituted = false;
            for (;;) {
                const std::size_t found = line.text.find(search, position);
                if (found == std::string::npos) break;
                ++occurrence;
                const bool replace = occurrence == command.occurrence || (command.allMatches && occurrence > command.occurrence);
                result += line.text.substr(position, found - position) + (replace ? expanded : search);
                substituted = substituted || replace;
                position = found + search.size();
            }
            if (!substituted) continue;
            result += line.text.substr(position);
            if (result.size() > 80) fail("line too long");
            if (result.empty() || result.back() == ' ') fail("bad line");
            line.text = std::move(result);
            state.current = i + 1;
            ++changed;
        }
        if (changed == 0 && !insideGlobal) fail("no match");
        if (changed > 0) suffix(command);
        return changed;
    }

    void global(const Command& command, int a, int b, const Text& text) {
        const std::string search = pattern(command.pattern);
        std::vector<std::uint64_t> selected;
        for (int i = a - 1; i < b; ++i) {
            const Line& line = state.lines[i];
            if ((line.text.find(search) != std::string::npos) == (command.kind == Kind::global)) selected.push_back(line.id);
        }
        if (selected.empty()) fail("no match");
        int changed = 0;
        for (std::uint64_t id : selected) {
            const int number = lineNumber(id);
            if (number == 0) continue;
            state.current = number;
            const auto [start, end] = range(*command.subcommand, {});
            changed += execute(*command.subcommand, start, end, text, true);
        }
        if (command.subcommand->kind == Kind::substitute && changed == 0) fail("no match");
    }

    int execute(const Command& command, int a, int b, const Text& text, bool insideGlobal = false) {
        const Kind kind = command.kind;
        if (kind == Kind::substitute) return substitute(command, a, b, insideGlobal);
        if (kind == Kind::global || kind == Kind::inverseGlobal) global(command, a, b, text);
        else if (kind == Kind::bare || kind == Kind::print || kind == Kind::numbered || kind == Kind::list) {
            const char form = kind == Kind::numbered ? 'n' : kind == Kind::list ? 'l' : 'p';
            for (int i = kind == Kind::bare ? b : a; i <= b; ++i) print(i, form);
            state.current = b;
        } else if (kind == Kind::scroll) {
            if (command.amount) state.displayCount = *command.amount;
            const int end = std::min(a + state.displayCount - 1, last());
            for (int i = a; i <= end; ++i) print(i, 'p');
            state.current = end;
        } else if (kind == Kind::position) emit(std::to_string(a));
        else if (kind == Kind::count) {
            const Text text = contents(a, b);
            int words = 0, characters = 0;
            for (const std::string& line : text) {
                characters += static_cast<int>(line.size());
                bool inWord = false;
                for (char ch : line) {
                    if (ch != ' ' && !inWord) ++words;
                    inWord = ch != ' ';
                }
            }
            emit("count lines=" + std::to_string(text.size()) + " words=" + std::to_string(words) + " chars=" + std::to_string(characters));
        } else if (kind == Kind::writePrint) {
            const Text text = contents(a, b);
            for (const std::string& line : text) emit(line);
            emit("lines=" + std::to_string(text.size()) + " bytes=" + std::to_string(byteCount(text)));
        } else if (kind == Kind::append || kind == Kind::insert) {
            const int position = kind == Kind::append ? a : std::max(a, 1) - 1;
            const Buffer inserted = newLines(text);
            replace(position, 0, inserted);
            state.current = position + static_cast<int>(inserted.size());
        } else if (kind == Kind::change || kind == Kind::erase) {
            state.cut = contents(a, b);
            const Buffer inserted = kind == Kind::change ? newLines(text) : Buffer{};
            replace(a - 1, b - a + 1, inserted);
            state.current = inserted.empty() ? std::min(a, last()) : a + static_cast<int>(inserted.size()) - 1;
            suffix(command);
        } else if (kind == Kind::yank) state.cut = contents(a, b);
        else if (kind == Kind::put) {
            if (state.cut.empty()) fail("nothing to put");
            const Buffer inserted = newLines(state.cut);
            replace(a, 0, inserted);
            state.current = a + static_cast<int>(inserted.size());
            suffix(command);
        } else if (kind == Kind::move || kind == Kind::copy) {
            const int destination = address(command.destination), count = b - a + 1;
            if (destination < 0 || destination > last()) fail("address out of range");
            if (kind == Kind::move) {
                if (a <= destination && destination < b) fail("invalid destination");
                const Buffer moved(state.lines.begin() + a - 1, state.lines.begin() + b);
                replace(a - 1, count, {});
                const int position = destination < a ? destination : destination - count;
                replace(position, 0, moved);
                state.current = position + count;
            } else {
                const Buffer copied = newLines(contents(a, b));
                replace(destination, 0, copied);
                state.current = destination + count;
            }
            suffix(command);
        } else if (kind == Kind::join || kind == Kind::joinWords) {
            std::string joined = state.lines[a - 1].text;
            for (int i = a; i < b; ++i) {
                const std::string& line = state.lines[i].text;
                if (kind == Kind::join) joined += line;
                else joined += " " + line.substr(line.find_first_not_of(' '));
            }
            if (joined.size() > 80) fail("line too long");
            const Buffer joinedLine = {{state.lines[a - 1].id, joined}};
            replace(a - 1, b - a + 1, joinedLine);
            state.current = a;
            suffix(command);
        } else if (kind == Kind::indent || kind == Kind::unindent || kind == Kind::letterCase) {
            const int width = command.amount.value_or(4);
            for (int i = a - 1; i < b; ++i) {
                std::string& value = state.lines[i].text;
                if (kind == Kind::indent) {
                    if (value.size() + width > 80) fail("line too long");
                    value.insert(0, width, ' ');
                } else if (kind == Kind::unindent) {
                    const std::size_t spaces = value.find_first_not_of(' ');
                    value.erase(0, std::min(static_cast<std::size_t>(width), spaces));
                } else {
                    for (char& ch : value) {
                        if (lower(ch) && command.argument != "l") ch = static_cast<char>(ch - ('a' - 'A'));
                        else if (upper(ch) && command.argument != "u") ch = lowercase(ch);
                    }
                }
            }
            state.current = b;
        } else if (kind == Kind::sort) {
            struct KeyedLine { Line line; std::variant<int, std::string> key; };
            std::vector<KeyedLine> sorted;
            const bool numeric = contains(command.argument, 'n');
            for (int i = a - 1; i < b; ++i) {
                const Line& line = state.lines[i];
                if (numeric) {
                    const std::size_t start = line.text[0] == '-' ? 1 : 0;
                    std::size_t end = start;
                    while (end < line.text.size() && digit(line.text[end])) ++end;
                    sorted.push_back({line, end == start ? 0 : std::stoi(line.text.substr(0, end))});
                } else {
                    std::string key = line.text;
                    if (contains(command.argument, 'i')) std::transform(key.begin(), key.end(), key.begin(), lowercase);
                    sorted.push_back({line, key});
                }
            }
            const bool reverse = contains(command.argument, 'r');
            std::stable_sort(sorted.begin(), sorted.end(), [reverse](const KeyedLine& x, const KeyedLine& y) {
                return reverse ? y.key < x.key : x.key < y.key;
            });
            if (contains(command.argument, 'u')) {
                sorted.erase(std::unique(sorted.begin(), sorted.end(), [](const KeyedLine& x, const KeyedLine& y) {
                    return x.key == y.key;
                }), sorted.end());
            }
            Buffer lines;
            for (const KeyedLine& item : sorted) lines.push_back(item.line);
            replace(a - 1, b - a + 1, lines);
            state.current = a + static_cast<int>(lines.size()) - 1;
        } else if (kind == Kind::mark) state.marks[command.argument[0] - 'a'] = state.lines[a - 1].id;
        else if (kind == Kind::marks) {
            std::string text = "marks";
            for (int i = 0; i < 26; ++i) {
                const int number = lineNumber(state.marks[i]);
                if (number > 0) text += " " + std::string(1, static_cast<char>('a' + i)) + "=" + std::to_string(number);
            }
            emit(text == "marks" ? "marks none" : text);
        } else if (kind == Kind::undo || kind == Kind::redo) {
            std::vector<Record>& source = kind == Kind::undo ? state.undo : state.redo;
            std::vector<Record>& target = kind == Kind::undo ? state.redo : state.undo;
            const int count = command.amount.value_or(1);
            if (source.size() < static_cast<std::size_t>(count)) fail(kind == Kind::undo ? "nothing to undo" : "nothing to redo");
            for (int i = 0; i < count; ++i) {
                const Record record = source.back();
                source.pop_back();
                target.push_back(snapshot(record.command));
                state.lines = *record.lines;
                state.current = record.current;
            }
        } else if (kind == Kind::history) {
            emit("history undo=" + std::to_string(state.undo.size()) + " redo=" + std::to_string(state.redo.size()));
            for (const std::string name : {"undo", "redo"}) {
                const std::vector<Record>& history = name == "undo" ? state.undo : state.redo;
                int number = 0;
                for (auto it = history.rbegin(); it != history.rend(); ++it) emit(name + " " + std::to_string(++number) + ": " + it->command);
            }
        } else if (kind == Kind::write || kind == Kind::writeAppend || kind == Kind::read || kind == Kind::edit) {
            const auto found = state.files.find(command.argument);
            std::shared_ptr<const Text> file;
            if (kind == Kind::write || kind == Kind::writeAppend) {
                Text written = kind == Kind::writeAppend && found != state.files.end() ? *found->second : Text{};
                const Text added = contents(a, b);
                written.insert(written.end(), added.begin(), added.end());
                file = std::make_shared<const Text>(std::move(written));
                state.files[command.argument] = file;
            } else {
                if (found == state.files.end()) fail("no such file");
                file = found->second;
                const Buffer inserted = newLines(*file);
                if (kind == Kind::edit) { state.lines = inserted; state.current = last(); }
                else { replace(a, 0, inserted); state.current = a + static_cast<int>(inserted.size()); }
            }
            emit("file " + command.argument + " lines=" + std::to_string(file->size()) + " bytes=" + std::to_string(byteCount(*file)));
        } else if (kind == Kind::files) {
            std::string text = "files";
            for (const auto& [name, file] : state.files) text += " " + name + "=" + std::to_string(file->size());
            emit(text == "files" ? "files none" : text);
        }
        return 0;
    }

public:
    Text process(const std::string& source, const Text& text) {
        // History buffers and file contents are immutable shared snapshots;
        // all writable state is copied for the command's transaction.
        State previous = state;
        const Record before = snapshot(source);
        output.clear();
        try {
            const AddressScan scanned = scanAddress(source);
            const AddressForm form = addressForm(scanned.elements);
            const Command command = parseCommand(scanned.command);
            const int category = addressKind(command.kind);
            if (category == 0 && form.count > 0) fail("unexpected address");
            if (category == 1 && form.count > 1) fail("too many addresses");
            const std::vector<int> values = addresses(form);
            const auto [a, b] = range(command, values);
            execute(command, a, b, text);
            if (last() > 200) fail("buffer full");
            if (modifying(command)) {
                state.undo.push_back(before);
                state.redo.clear();
            }
            return output;
        } catch (const EditorError& error) {
            state = std::move(previous);
            return {"? " + std::string(error.what())};
        }
    }
};

int main() {
    std::ios::sync_with_stdio(false);
    std::cin.tie(nullptr);
    Editor editor;
    std::string command;
    while (std::getline(std::cin, command) && command != "Q") {
        Text text;
        if (hasText(command)) {
            std::string line;
            while (std::getline(std::cin, line) && line != ".") text.push_back(line);
        }
        for (const std::string& line : editor.process(command, text)) std::cout << line << '\n';
    }
}
