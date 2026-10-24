#include <algorithm>
#include <cstdint>
#include <iomanip>
#include <iostream>
#include <optional>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

enum class Kind { Object, Array, String, Number, Boolean, Null };
struct Value {
    Kind kind = Kind::Null;
    std::string text;
    std::int64_t number = 0;
    bool boolean = false;
    std::vector<std::string> keys;
    std::vector<Value> items;

    explicit Value(Kind kind = Kind::Null) : kind(kind) {}
    int find(const std::string& key) const {
        auto found = std::find(keys.begin(), keys.end(), key);
        return found == keys.end() ? -1 : static_cast<int>(found - keys.begin());
    }
    int count() const {
        int result = 1;
        for (const Value& item : items) result += item.count();
        return result;
    }
    int depth() const {
        int result = 1;
        for (const Value& item : items) result = std::max(result, 1 + item.depth());
        return result;
    }
};

bool letter(char c) { return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z'); }
bool digit(char c) { return c >= '0' && c <= '9'; }
bool identifier_start(char c) { return letter(c) || c == '_'; }
bool identifier_char(char c) { return identifier_start(c) || digit(c); }
bool identifier(const std::string& text) {
    return !text.empty() && identifier_start(text[0]) &&
           std::all_of(text.begin(), text.end(), identifier_char);
}
bool integer_notation(const std::string& text) {
    if (text == "0") return true;
    std::size_t start = !text.empty() && text[0] == '-' ? 1 : 0;
    return text.size() > start && text.size() - start <= 9 && text[start] != '0' &&
           std::all_of(text.begin() + start, text.end(), digit);
}
int hexadecimal(char c) {
    if (digit(c)) return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

std::string quote(const std::string& text, char mark = '"') {
    std::string result(1, mark);
    static const char* digits = "0123456789abcdef";
    for (unsigned char c : text) {
        if (c == static_cast<unsigned char>(mark) || c == '\\') {
            result += '\\';
            result += static_cast<char>(c);
        }
        else if (c == 8) result += "\\b";
        else if (c == 12) result += "\\f";
        else if (c == 10) result += "\\n";
        else if (c == 13) result += "\\r";
        else if (c == 9) result += "\\t";
        else if (c < 32 || c == 127) {
            result += "\\u00";
            result += digits[c >> 4];
            result += digits[c & 15];
        } else result += static_cast<char>(c);
    }
    return result + mark;
}

std::string compact(const Value& value) {
    if (value.kind == Kind::Null) return "null";
    if (value.kind == Kind::Boolean) return value.boolean ? "true" : "false";
    if (value.kind == Kind::Number) return std::to_string(value.number);
    if (value.kind == Kind::String) return quote(value.text);
    std::string result = value.kind == Kind::Object ? "{" : "[";
    for (std::size_t i = 0; i < value.items.size(); ++i) {
        if (i) result += ',';
        if (value.kind == Kind::Object) result += quote(value.keys[i]) + ":";
        result += compact(value.items[i]);
    }
    return result + (value.kind == Kind::Object ? '}' : ']');
}

std::string pretty(const Value& value, const std::string& indent = "") {
    if (value.items.empty()) return compact(value);
    std::string inner = indent + "  ";
    std::string result = value.kind == Kind::Object ? "{\n" : "[\n";
    for (std::size_t i = 0; i < value.items.size(); ++i) {
        if (i) result += ",\n";
        result += inner;
        if (value.kind == Kind::Object) result += quote(value.keys[i]) + ": ";
        result += pretty(value.items[i], inner);
    }
    return result + "\n" + indent + (value.kind == Kind::Object ? "}" : "]");
}

bool equal(const Value& a, const Value& b) {
    if (a.kind != b.kind) return false;
    if (a.kind == Kind::String) return a.text == b.text;
    if (a.kind == Kind::Number) return a.number == b.number;
    if (a.kind == Kind::Boolean) return a.boolean == b.boolean;
    if (a.items.size() != b.items.size()) return false;
    for (std::size_t i = 0; i < a.items.size(); ++i) {
        int j = a.kind == Kind::Object ? b.find(a.keys[i]) : static_cast<int>(i);
        if (j < 0 || !equal(a.items[i], b.items[static_cast<std::size_t>(j)])) return false;
    }
    return true;
}

struct JsonError : std::runtime_error {
    std::size_t position;
    JsonError(const std::string& reason, std::size_t position) : std::runtime_error(reason), position(position) {}
};

class JsonReader {
    const std::string& text;
    std::size_t position = 0;
    char peek() const { return position < text.size() ? text[position] : '\0'; }
    [[noreturn]] void fail(const std::string& reason) const { throw JsonError(reason, position); }
    void whitespace() { while (peek() == ' ' || peek() == '\n') ++position; }
    void require(char c, const std::string& reason) const {
        if (position == text.size()) fail("unexpected end of input");
        if (peek() != c) fail(reason);
    }
    std::string string() {
        ++position;
        std::string result;
        while (true) {
            char c = peek();
            if (c == '\0' || c == '\n') fail("unterminated string");
            if (c == '"') {
                ++position;
                return result;
            }
            if (c != '\\') {
                result += c;
                ++position;
                continue;
            }
            std::size_t slash = position++;
            char escape = peek();
            if (escape == '\0' || escape == '\n') fail("unterminated string");
            if (escape == 'u') {
                int code = 0;
                if (position + 4 >= text.size()) throw JsonError("bad unicode escape", slash);
                for (std::size_t i = position + 1; i <= position + 4; ++i) {
                    int h = hexadecimal(text[i]);
                    if (h < 0) throw JsonError("bad unicode escape", slash);
                    code = code * 16 + h;
                }
                if (code > 127) throw JsonError("non-ascii escape", slash);
                result += static_cast<char>(code);
                position += 5;
            } else {
                switch (escape) {
                    case '"': case '\\': case '/': result += escape;
                    break;
                    case 'b': result += '\b';
                    break;
                    case 'f': result += '\f';
                    break;
                    case 'n': result += '\n';
                    break;
                    case 'r': result += '\r';
                    break;
                    case 't': result += '\t';
                    break;
                    default: throw JsonError("invalid escape '\\" + std::string(1, escape) + "'", slash);
                }
                ++position;
            }
        }
    }
    Value number() {
        std::size_t start = position;
        bool negative = peek() == '-';
        if (negative) ++position;
        std::size_t digits = position;
        while (digit(peek())) ++position;
        std::size_t length = position - digits;
        if (!length) throw JsonError("invalid number", start);
        if (length > 1 && text[digits] == '0') throw JsonError("leading zero", digits);
        if (peek() == '.') fail("fraction not allowed");
        if (peek() == 'e' || peek() == 'E') fail("exponent not allowed");
        if (length > 9) throw JsonError("number out of range", start);
        Value value(Kind::Number);
        value.number = std::stoll(text.substr(start, position - start));
        return value;
    }
    bool end_container(char closing, const std::string& reason) {
        whitespace();
        if (peek() == closing) {
            ++position;
            return true;
        }
        require(',', reason);
        ++position;
        whitespace();
        if (peek() == closing) fail("trailing comma");
        return false;
    }
    Value object() {
        ++position;
        whitespace();
        Value object(Kind::Object);
        if (peek() == '}') {
            ++position;
            return object;
        }
        while (true) {
            whitespace();
            require('"', "expected key");
            std::size_t key_start = position;
            std::string key = string();
            if (object.find(key) >= 0) throw JsonError("duplicate key " + quote(key), key_start);
            whitespace();
            require(':', "expected ':'");
            ++position;
            Value child = value();
            object.keys.push_back(std::move(key));
            object.items.push_back(std::move(child));
            if (end_container('}', "expected ',' or '}'")) return object;
        }
    }
    Value array() {
        ++position;
        whitespace();
        Value array(Kind::Array);
        if (peek() == ']') {
            ++position;
            return array;
        }
        while (true) {
            array.items.push_back(value());
            if (end_container(']', "expected ',' or ']'")) return array;
        }
    }
    Value value() {
        whitespace();
        char c = peek();
        if (c == '\0') fail("unexpected end of input");
        if (c == '{') return object();
        if (c == '[') return array();
        if (c == '"') {
            Value result(Kind::String);
            result.text = string();
            return result;
        }
        if (c == '-' || digit(c)) return number();
        if (letter(c)) {
            std::size_t start = position;
            while (letter(peek())) ++position;
            std::string word = text.substr(start, position - start);
            if (word == "null") return Value();
            if (word == "true" || word == "false") {
                Value result(Kind::Boolean);
                result.boolean = word == "true";
                return result;
            }
            throw JsonError("invalid literal '" + word + "'", start);
        }
        fail("unexpected character '" + std::string(1, c) + "'");
    }
public:
    explicit JsonReader(const std::string& text) : text(text) {}
    Value parse() {
        Value result = value();
        whitespace();
        if (position != text.size()) fail("trailing characters");
        return result;
    }
};

enum class SelectorKind { Key, Index, All, Slice };
struct Selector {
    SelectorKind kind = SelectorKind::Key;
    bool descendant = false;
    std::string key;
    int index = 0;
    std::optional<int> first, last;
};

class PathReader {
    const std::string& text;
    std::string reason;
    std::size_t position = 0;
    char peek() const { return position < text.size() ? text[position] : '\0'; }
    [[noreturn]] void fail() const { throw std::runtime_error(reason); }
    bool accept(char c) {
        if (peek() != c) return false;
        ++position;
        return true;
    }
    void expect(char c) { if (!accept(c)) fail(); }
    std::string name() {
        if (!identifier_start(peek())) fail();
        std::size_t start = position++;
        while (identifier_char(peek())) ++position;
        return text.substr(start, position - start);
    }
    std::string quoted_key() {
        expect('\'');
        std::string result;
        while (true) {
            char c = peek();
            if (c == '\0') fail();
            ++position;
            if (c == '\'') return result;
            if (c != '\\') {
                result += c;
                continue;
            }
            char escape = peek();
            if (escape == '\0') fail();
            ++position;
            if (escape == 'u') {
                if (position + 4 > text.size()) fail();
                int code = 0;
                for (int i = 0; i < 4; ++i) {
                    int h = hexadecimal(text[position++]);
                    if (h < 0) fail();
                    code = code * 16 + h;
                }
                if (code > 127) fail();
                result += static_cast<char>(code);
            } else {
                switch (escape) {
                    case '\'': case '\\': case '/': result += escape;
                    break;
                    case 'b': result += '\b';
                    break;
                    case 'f': result += '\f';
                    break;
                    case 'n': result += '\n';
                    break;
                    case 'r': result += '\r';
                    break;
                    case 't': result += '\t';
                    break;
                    default: fail();
                }
            }
        }
    }
    Selector selection() {
        Selector selector;
        if (peek() == '\'') {
            selector.key = quoted_key();
            expect(']');
            return selector;
        }
        std::size_t end = text.find(']', position);
        if (end == std::string::npos) fail();
        std::string content = text.substr(position, end - position);
        position = end + 1;
        if (content == "*") {
            selector.kind = SelectorKind::All;
            return selector;
        }
        if (integer_notation(content)) {
            selector.kind = SelectorKind::Index;
            selector.index = std::stoi(content);
            return selector;
        }
        std::size_t colon = content.find(':');
        if (colon == std::string::npos || content.find(':', colon + 1) != std::string::npos) fail();
        std::string first = content.substr(0, colon), last = content.substr(colon + 1);
        if ((!first.empty() && !integer_notation(first)) || (!last.empty() && !integer_notation(last))) fail();
        selector.kind = SelectorKind::Slice;
        if (!first.empty()) selector.first = std::stoi(first);
        if (!last.empty()) selector.last = std::stoi(last);
        return selector;
    }
public:
    PathReader(const std::string& text, std::string reason) : text(text), reason(std::move(reason)) {}
    std::vector<Selector> path(bool field = false) {
        expect(field ? '@' : '$');
        std::vector<Selector> selectors;
        while (position != text.size()) {
            Selector selector;
            if (accept('[')) selector = selection();
            else {
                expect('.');
                bool descendant = !field && accept('.');
                if (!field && accept('*')) selector.kind = SelectorKind::All;
                else if (descendant && accept('[')) selector = selection();
                else selector.key = name();
                selector.descendant = descendant;
            }
            if (field && selector.kind != SelectorKind::Key && selector.kind != SelectorKind::Index) fail();
            selectors.push_back(std::move(selector));
        }
        return selectors;
    }
    std::string key() {
        std::string result = peek() == '\'' ? quoted_key() : name();
        if (position != text.size()) fail();
        return result;
    }
};

struct Step {
    std::optional<std::string> key;
    int position;
    std::string text() const {
        if (!key) return "[" + std::to_string(position) + "]";
        return identifier(*key) ? "." + *key : "[" + quote(*key, '\'') + "]";
    }
};
struct Match {
    const Value* value;
    std::vector<Step> steps;
    Match child(int position) const {
        Match result{&value->items[static_cast<std::size_t>(position)], steps};
        result.steps.push_back({value->kind == Kind::Object ? std::optional<std::string>(value->keys[position]) : std::nullopt, position});
        return result;
    }
    std::string location() const {
        std::string result = "$";
        for (const Step& step : steps) result += step.text();
        return result;
    }
    std::vector<int> positions() const {
        std::vector<int> result;
        for (const Step& step : steps) result.push_back(step.position);
        return result;
    }
};

int child_position(const Value& value, const Selector& selector) {
    if (selector.kind == SelectorKind::Key) return value.kind == Kind::Object ? value.find(selector.key) : -1;
    if (value.kind != Kind::Array) return -1;
    int count = static_cast<int>(value.items.size());
    int index = selector.index < 0 ? count + selector.index : selector.index;
    return index >= 0 && index < count ? index : -1;
}

void select(const Selector& selector, const Match& match, std::vector<Match>& output) {
    const Value& value = *match.value;
    if (selector.kind == SelectorKind::Key || selector.kind == SelectorKind::Index) {
        int position = child_position(value, selector);
        if (position >= 0) output.push_back(match.child(position));
    } else if (selector.kind == SelectorKind::All) {
        for (int i = 0; i < static_cast<int>(value.items.size()); ++i) output.push_back(match.child(i));
    } else if (value.kind == Kind::Array) {
        int count = static_cast<int>(value.items.size());
        auto clamp = [count](int bound) {
            if (bound < 0) bound += count;
            return std::clamp(bound, 0, count);
        };
        int begin = selector.first ? clamp(*selector.first) : 0;
        int end = selector.last ? clamp(*selector.last) : count;
        for (int i = begin; i < end; ++i) output.push_back(match.child(i));
    }
}

void select_descendants(const Selector& selector, const Match& match, std::vector<Match>& output) {
    select(selector, match, output);
    for (int i = 0; i < static_cast<int>(match.value->items.size()); ++i)
        select_descendants(selector, match.child(i), output);
}

std::vector<Match> apply(const Selector& selector, const std::vector<Match>& matches) {
    std::vector<Match> result;
    for (const Match& match : matches) {
        if (selector.descendant) select_descendants(selector, match, result);
        else select(selector, match, result);
    }
    return result;
}

std::vector<Match> evaluate(const Value& root, const std::vector<Selector>& selectors) {
    std::vector<Match> matches{{&root, {}}};
    for (const Selector& selector : selectors) matches = apply(selector, matches);
    return matches;
}

const Value* field_value(const Value& value, const std::vector<Selector>& selectors) {
    const Value* current = &value;
    for (const Selector& selector : selectors) {
        int position = child_position(*current, selector);
        if (position < 0) return nullptr;
        current = &current->items[static_cast<std::size_t>(position)];
    }
    return current;
}

std::vector<Match> targets(std::vector<Match> matches) {
    std::sort(matches.begin(), matches.end(), [](const Match& a, const Match& b) { return a.positions() > b.positions(); });
    matches.erase(std::unique(matches.begin(), matches.end(), [](const Match& a, const Match& b) {
        return a.positions() == b.positions();
    }), matches.end());
    return matches;
}

Value& resolve(Value& root, const Match& match, bool parent = false) {
    Value* value = &root;
    std::size_t count = match.steps.size() - (parent ? 1 : 0);
    for (std::size_t i = 0; i < count; ++i) value = &value->items[static_cast<std::size_t>(match.steps[i].position)];
    return *value;
}

void require_kind(const std::vector<Match>& matches, Kind kind, const std::string& reason) {
    for (const Match& match : matches) if (match.value->kind != kind) throw std::runtime_error(reason + " at " + match.location());
}

void merge(Value& target, const Value& patch) {
    for (std::size_t i = 0; i < patch.items.size(); ++i) {
        int position = target.find(patch.keys[i]);
        if (position < 0) {
            target.keys.push_back(patch.keys[i]);
            target.items.push_back(patch.items[i]);
        } else if (target.items[position].kind == Kind::Object && patch.items[i].kind == Kind::Object) {
            merge(target.items[position], patch.items[i]);
        } else target.items[position] = patch.items[i];
    }
}

bool filter_holds(const std::string& op, const Value* value, const Value& reference) {
    if (op == "EXISTS") return value != nullptr;
    if (op == "==" || op == "!=") {
        bool same = value && equal(*value, reference);
        return op == "==" ? same : !same;
    }
    if (!value || value->kind != reference.kind || (value->kind != Kind::Number && value->kind != Kind::String)) return false;
    int comparison = value->kind == Kind::Number ? (value->number < reference.number ? -1 : value->number > reference.number ? 1 : 0)
                                                : value->text.compare(reference.text);
    if (op == "<") return comparison < 0;
    if (op == "<=") return comparison <= 0;
    if (op == ">") return comparison > 0;
    return comparison >= 0;
}

int rank(const Value* value) {
    if (!value) return 3;
    if (value->kind == Kind::Null) return 0;
    if (value->kind == Kind::Number) return 1;
    if (value->kind == Kind::String) return 2;
    return 3;
}

bool less(const Value* a, const Value* b) {
    int ar = rank(a), br = rank(b);
    if (ar != br) return ar < br;
    if (ar == 1) return a->number < b->number;
    if (ar == 2) return a->text < b->text;
    return false;
}

std::vector<std::string> split_arguments(const std::optional<std::string>& arguments, std::size_t maximum) {
    std::vector<std::string> result;
    if (!arguments) return result;
    std::size_t position = 0;
    while (result.size() + 1 < maximum) {
        std::size_t space = arguments->find(' ', position);
        if (space == std::string::npos) break;
        result.push_back(arguments->substr(position, space - position));
        position = space + 1;
    }
    result.push_back(arguments->substr(position));
    return result;
}

std::vector<std::string> words(const std::optional<std::string>& arguments, std::size_t minimum, std::size_t maximum) {
    std::vector<std::string> result = split_arguments(arguments, std::string::npos);
    if (result.size() < minimum || result.size() > maximum) throw std::runtime_error("bad arguments");
    return result;
}

class QueryTool {
    Value document;
    std::vector<Value> history;

    void commit(Value value) {
        history.push_back(std::move(document));
        document = std::move(value);
    }
    void flatten(const Match& match) const {
        if (match.value->items.empty()) {
            std::cout << match.location() << " = " << compact(*match.value) << '\n';
        } else {
            for (int i = 0; i < static_cast<int>(match.value->items.size()); ++i) flatten(match.child(i));
        }
    }
    void modify(const std::string& command, const std::optional<std::string>& arguments) {
        std::vector<std::string> args;
        if (command == "SET" || command == "MERGE" || command == "INSERT") {
            std::size_t expected = command == "INSERT" ? 3 : 2;
            args = split_arguments(arguments, expected);
            if (args.size() != expected) throw std::runtime_error("bad arguments");
        } else args = words(arguments, command == "RENAME" ? 2 : 1, command == "SORT" ? 3 : command == "RENAME" ? 2 : 1);
        bool descending = false;
        std::string field_text = "@";
        if (command == "SORT" && args.size() > 1) {
            descending = args.back() == "DESC";
            std::size_t remaining = args.size() - 1 - (descending ? 1 : 0);
            if (remaining > 1 || (remaining == 1 && args[1] == "DESC")) throw std::runtime_error("bad arguments");
            if (remaining) field_text = args[1];
        }
        std::vector<Selector> path = PathReader(args[0], "bad path").path();
        std::vector<Selector> field;
        std::string new_key;
        int insertion = 0;
        Value value;
        if (command == "INSERT") {
            if (!integer_notation(args[1])) throw std::runtime_error("bad index");
            insertion = std::stoi(args[1]);
        }
        if (command == "SET" || command == "MERGE" || command == "INSERT") value = JsonReader(args.back()).parse();
        if (command == "SORT") field = PathReader(field_text, "bad field").path(true);
        if (command == "RENAME") new_key = PathReader(args[1], "bad key").key();
        if (command == "DELETE" && path.empty()) throw std::runtime_error("cannot delete root");
        if (command == "MERGE" && value.kind != Kind::Object) throw std::runtime_error("merge value is not an object");
        if (command == "SET" && path.empty()) {
            commit(std::move(value));
            std::cout << "SET 1\n";
            return;
        }
        std::vector<Match> matches;
        if (command == "SET") {
            Selector last = path.back();
            path.pop_back();
            for (const Match& parent : evaluate(document, path)) {
                if (!last.descendant && last.kind == SelectorKind::Key && parent.value->kind == Kind::Object) {
                    int position = parent.value->find(last.key);
                    if (position < 0) position = static_cast<int>(parent.value->items.size());
                    Match target{nullptr, parent.steps};
                    target.steps.push_back({last.key, position});
                    matches.push_back(std::move(target));
                } else {
                    std::vector<Match> selected = apply(last, {parent});
                    matches.insert(matches.end(), selected.begin(), selected.end());
                }
            }
        } else matches = evaluate(document, path);
        if (command == "INSERT" || command == "SORT") require_kind(matches, Kind::Array, "not an array");
        if (command == "MERGE") require_kind(matches, Kind::Object, "not an object");
        if (command == "INSERT") {
            for (const Match& match : matches) {
                int count = static_cast<int>(match.value->items.size());
                if (insertion < -count - 1 || insertion > count)
                    throw std::runtime_error("index out of range at " + match.location());
            }
        }
        if (command == "RENAME") {
            for (const Match& match : matches)
                if (match.steps.empty() || !match.steps.back().key)
                    throw std::runtime_error("not a member at " + match.location());
        }
        std::vector<Match> selected = targets(std::move(matches));
        Value updated = document;
        for (const Match& target : selected) {
            if (command == "SET" || command == "DELETE" || command == "RENAME") {
                Value& parent = resolve(updated, target, true);
                int position = target.steps.back().position;
                if (command == "SET") {
                    if (position == static_cast<int>(parent.items.size())) {
                        parent.keys.push_back(*target.steps.back().key);
                        parent.items.push_back(value);
                    } else parent.items[position] = value;
                } else if (command == "DELETE") {
                    parent.items.erase(parent.items.begin() + position);
                    if (parent.kind == Kind::Object) parent.keys.erase(parent.keys.begin() + position);
                } else {
                    if (parent.keys[position] != new_key && parent.find(new_key) >= 0)
                        throw std::runtime_error("key exists at " + target.location());
                    parent.keys[position] = new_key;
                }
            } else {
                Value& array = resolve(updated, target);
                if (command == "INSERT") {
                    int position = insertion < 0 ? static_cast<int>(array.items.size()) + 1 + insertion : insertion;
                    array.items.insert(array.items.begin() + position, value);
                } else if (command == "MERGE") merge(array, value);
                else {
                    std::stable_sort(array.items.begin(), array.items.end(), [&](const Value& a, const Value& b) {
                        const Value* av = field_value(a, field), *bv = field_value(b, field);
                        return descending ? less(bv, av) : less(av, bv);
                    });
                }
            }
        }
        commit(std::move(updated));
        std::cout << command << ' ' << selected.size() << '\n';
    }

    void execute(const std::string& command, const std::optional<std::string>& arguments) {
        static const std::set<std::string> modifying{"SET", "DELETE", "INSERT", "MERGE", "SORT", "RENAME"};
        static const std::set<std::string> ordinary{"GET", "COMPACT", "PRETTY", "TYPE", "LENGTH", "KEYS", "FLATTEN",
                                                    "COUNT", "SUM", "MIN", "MAX", "AVG"};
        if (modifying.count(command)) {
            modify(command, arguments);
            return;
        }
        if (command == "UNDO") {
            words(arguments, 0, 0);
            if (history.empty()) throw std::runtime_error("nothing to undo");
            document = std::move(history.back());
            history.pop_back();
            std::cout << "UNDO " << history.size() << '\n';
            return;
        }
        if (command == "FILTER") {
            std::vector<std::string> args = split_arguments(arguments, 4);
            if (args.size() < 3 || (args.size() == 4) == (args[2] == "EXISTS")) throw std::runtime_error("bad arguments");
            std::vector<Selector> path = PathReader(args[0], "bad path").path();
            std::vector<Selector> field = PathReader(args[1], "bad field").path(true);
            static const std::set<std::string> operators{"==", "!=", "<", "<=", ">", ">=", "EXISTS"};
            if (!operators.count(args[2])) throw std::runtime_error("bad operator");
            Value reference;
            if (args.size() == 4) reference = JsonReader(args[3]).parse();
            std::vector<Match> matches = evaluate(document, path);
            require_kind(matches, Kind::Array, "not an array");
            bool found = false;
            for (const Match& match : matches) {
                for (int i = 0; i < static_cast<int>(match.value->items.size()); ++i) {
                    Match element = match.child(i);
                    if (!filter_holds(args[2], field_value(*element.value, field), reference)) continue;
                    std::cout << element.location() << " = " << compact(*element.value) << '\n';
                    found = true;
                }
            }
            if (!found) std::cout << "no match\n";
            return;
        }
        if (!ordinary.count(command)) throw std::runtime_error("unknown command '" + command + "'");
        bool optional = command == "COMPACT" || command == "PRETTY" || command == "FLATTEN";
        std::vector<std::string> args = words(arguments, optional ? 0 : 1, 1);
        std::vector<Match> matches = evaluate(document, PathReader(args.empty() ? "$" : args[0], "bad path").path());
        if (command == "COUNT") {
            std::cout << "COUNT " << matches.size() << '\n';
            return;
        }
        if (command == "SUM" || command == "MIN" || command == "MAX" || command == "AVG") {
            std::vector<std::int64_t> numbers;
            std::int64_t sum = 0;
            for (const Match& match : matches) if (match.value->kind == Kind::Number) {
                numbers.push_back(match.value->number);
                sum += match.value->number;
            }
            std::cout << command << ' ';
            if (command == "SUM") std::cout << sum;
            else if (numbers.empty()) std::cout << "null";
            else if (command == "MIN") std::cout << *std::min_element(numbers.begin(), numbers.end());
            else if (command == "MAX") std::cout << *std::max_element(numbers.begin(), numbers.end());
            else {
                std::int64_t count = static_cast<std::int64_t>(numbers.size());
                std::int64_t q = ((sum < 0 ? -sum : sum) * 200 + count) / (2 * count);
                if (sum < 0 && q) std::cout << '-';
                std::cout << q / 100 << '.' << std::setw(2) << std::setfill('0') << q % 100 << std::setfill(' ');
            }
            std::cout << '\n';
            return;
        }
        if (command == "KEYS") require_kind(matches, Kind::Object, "not an object");
        if (command == "LENGTH") for (const Match& match : matches) {
            Kind kind = match.value->kind;
            if (kind != Kind::Object && kind != Kind::Array && kind != Kind::String)
                throw std::runtime_error("no length at " + match.location());
        }
        if (matches.empty()) std::cout << "no match\n";
        static const std::vector<std::string> type_names{"object", "array", "string", "number", "boolean", "null"};
        for (const Match& match : matches) {
            if (command == "COMPACT") std::cout << compact(*match.value) << '\n';
            else if (command == "PRETTY") std::cout << pretty(*match.value) << '\n';
            else if (command == "FLATTEN") flatten(match);
            else if (command == "GET") std::cout << match.location() << " = " << compact(*match.value) << '\n';
            else if (command == "TYPE") std::cout << match.location() << ' ' << type_names[static_cast<int>(match.value->kind)] << '\n';
            else if (command == "LENGTH")
                std::cout << match.location() << ' ' << (match.value->kind == Kind::String ? match.value->text.size() : match.value->items.size()) << '\n';
            else if (command == "KEYS") {
                std::cout << match.location() << " [";
                for (std::size_t i = 0; i < match.value->keys.size(); ++i) {
                    if (i) std::cout << ',';
                    std::cout << quote(match.value->keys[i]);
                }
                std::cout << "]\n";
            }
        }
    }
public:
    void load(const std::vector<std::string>& lines) {
        std::string text;
        for (std::size_t i = 0; i < lines.size(); ++i) {
            if (i) text += '\n';
            text += lines[i];
        }
        try {
            Value value = JsonReader(text).parse();
            int count = value.count(), depth = value.depth();
            commit(std::move(value));
            std::cout << "LOADED nodes=" << count << " depth=" << depth << '\n';
        } catch (const JsonError& error) {
            int line = 1, column = 1;
            for (std::size_t i = 0; i < error.position; ++i) {
                if (text[i] == '\n') {
                    ++line;
                    column = 1;
                }
                else ++column;
            }
            std::cout << "PARSE ERROR line " << line << " col " << column << ": " << error.what() << '\n';
        }
    }
    void command(const std::string& line) {
        std::size_t space = line.find(' ');
        std::optional<std::string> arguments;
        if (space != std::string::npos) arguments = line.substr(space + 1);
        try { execute(line.substr(0, space), arguments); }
        catch (const JsonError& error) { std::cout << "PARSE ERROR col " << error.position + 1 << ": " << error.what() << '\n'; }
        catch (const std::runtime_error& error) { std::cout << "ERROR " << error.what() << '\n'; }
    }
};

std::vector<std::string> read_block() {
    std::vector<std::string> lines;
    std::string line;
    while (std::getline(std::cin, line) && line != "%%") lines.push_back(line);
    return lines;
}

int main() {
    QueryTool tool;
    tool.load(read_block());
    std::string line;
    while (std::getline(std::cin, line) && line != "END") {
        if (line == "LOAD") tool.load(read_block());
        else tool.command(line);
    }
}
