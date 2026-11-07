#include <algorithm>
#include <iostream>
#include <limits>
#include <map>
#include <regex>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

using Integer = long long;

enum class Kind { Absent, Integer, String, Boolean, List, Map };

struct Value {
    Kind kind = Kind::Absent;
    Integer integer = 0;
    std::string text;
    bool boolean = false;
    std::vector<Value> elements;
    std::map<std::string, Value> fields;

    Value() = default;
    explicit Value(Integer number) : kind(Kind::Integer), integer(number) {}
    explicit Value(std::string string) : kind(Kind::String), text(std::move(string)) {}
    explicit Value(bool flag) : kind(Kind::Boolean), boolean(flag) {}
    static Value container(Kind kind) {
        Value value;
        value.kind = kind;
        return value;
    }
};

struct SourceLine {
    int number;
    std::string text;
};
using Source = std::vector<SourceLine>;

struct TemplateError : std::runtime_error {
    int line;
    TemplateError(int line, const std::string& reason)
        : std::runtime_error(reason), line(line) {}
};

std::string trim(const std::string& text) {
    std::size_t begin = text.find_first_not_of(' ');
    if (begin == std::string::npos) return "";
    return text.substr(begin, text.find_last_not_of(' ') - begin + 1);
}

bool identifier(const std::string& text) {
    static const std::regex pattern("[A-Za-z_][A-Za-z0-9_]*");
    return std::regex_match(text, pattern);
}

bool subscript(const std::string& text) {
    static const std::regex pattern("0|[1-9][0-9]*");
    return std::regex_match(text, pattern);
}

bool numeric_text(const std::string& text) {
    static const std::regex pattern("-?[0-9]{1,9}");
    return std::regex_match(text, pattern);
}

std::vector<std::string> split(const std::string& text, char delimiter,
                               bool respect_quotes = false) {
    std::vector<std::string> parts;
    bool quoted = false;
    std::size_t start = 0;
    for (std::size_t i = 0; i < text.size(); ++i) {
        if (respect_quotes && text[i] == '\'') quoted = !quoted;
        if (text[i] == delimiter && !quoted) {
            parts.push_back(text.substr(start, i - start));
            start = i + 1;
        }
    }
    parts.push_back(text.substr(start));
    return parts;
}

bool valid_name(const std::string& name) {
    if (name == "." || name == "@index" || name == "@number" ||
        name == "@first" || name == "@last") return true;
    for (const std::string& part : split(name, '.')) {
        if (!identifier(part) && !subscript(part)) return false;
    }
    return true;
}

struct Part {
    bool index;
    std::string key;
    std::size_t number;
    std::string prefix;
};

std::size_t index_number(const std::string& text) {
    std::size_t value = 0;
    for (char c : text) {
        std::size_t digit = static_cast<std::size_t>(c - '0');
        if (value > (std::numeric_limits<std::size_t>::max() - digit) / 10)
            return std::numeric_limits<std::size_t>::max();
        value = value * 10 + digit;
    }
    return value;
}

std::vector<Part> parse_key(const std::string& key) {
    static const std::regex pattern(
        "[A-Za-z_][A-Za-z0-9_]*(\\.[A-Za-z_][A-Za-z0-9_]*|\\[(0|[1-9][0-9]*)\\])*");
    if (!std::regex_match(key, pattern))
        throw std::runtime_error("bad key '" + key + "'");
    std::vector<Part> parts;
    std::size_t position = 0;
    while (position < key.size()) {
        if (key[position] == '.') ++position;
        bool index = key[position] == '[';
        std::size_t start = position + (index ? 1 : 0);
        position = start;
        if (index) {
            while (key[position] != ']') ++position;
        } else {
            while (position < key.size() && key[position] != '.' && key[position] != '[')
                ++position;
        }
        std::string token = key.substr(start, position - start);
        if (index) ++position;
        parts.push_back({index, token, index ? index_number(token) : 0,
                         key.substr(0, position)});
    }
    return parts;
}

const Value* get(const Value& value, const Part& part) {
    if (part.index) {
        if (value.kind == Kind::List && part.number < value.elements.size())
            return &value.elements[part.number];
    } else if (value.kind == Kind::Map) {
        auto found = value.fields.find(part.key);
        if (found != value.fields.end()) return &found->second;
    }
    return nullptr;
}

Value& put(Value& container, const Part& part, Value value) {
    if (!part.index) {
        container.fields[part.key] = std::move(value);
        return container.fields[part.key];
    }
    if (part.number == container.elements.size())
        container.elements.push_back(std::move(value));
    else
        container.elements[part.number] = std::move(value);
    return container.elements[part.number];
}

Value read_scalar(const std::string& text, std::size_t& position) {
    if (position < text.size() && text[position] == '"') {
        std::string result;
        ++position;
        while (position < text.size()) {
            char c = text[position++];
            if (c == '"') return Value(result);
            if (c == '\\') {
                if (position == text.size()) throw std::runtime_error("invalid value");
                c = text[position++];
                if (c == 'n') c = '\n';
                else if (c != '"' && c != '\\') throw std::runtime_error("invalid value");
            }
            result += c;
        }
        throw std::runtime_error("invalid value");
    }
    std::size_t end = text.find_first_of(",]", position);
    if (end == std::string::npos) end = text.size();
    std::string word = text.substr(position, end - position);
    position = end;
    if (word == "true" || word == "false") return Value(word == "true");
    static const std::regex integer("0|-?[1-9][0-9]*");
    if (!std::regex_match(word, integer)) throw std::runtime_error("invalid value");
    return Value(std::stoll(word));
}

Value parse_value(const std::string& notation) {
    try {
        if (notation == "[]") return Value::container(Kind::List);
        if (notation == "{}") return Value::container(Kind::Map);
        std::size_t position = 0;
        if (!notation.empty() && notation[0] == '[') {
            Value result = Value::container(Kind::List);
            position = 1;
            while (true) {
                result.elements.push_back(read_scalar(notation, position));
                if (notation.substr(position) == "]") return result;
                if (notation.compare(position, 2, ", ") != 0)
                    throw std::runtime_error("invalid value");
                position += 2;
            }
        }
        Value value = read_scalar(notation, position);
        if (position != notation.size()) throw std::runtime_error("invalid value");
        return value;
    } catch (const std::exception&) {
        throw std::runtime_error("bad value '" + notation + "'");
    }
}

void assign(Value& root, const std::string& line) {
    std::size_t separator = line.find(" = ");
    if (separator == std::string::npos) throw std::runtime_error("bad line");
    std::vector<Part> parts = parse_key(line.substr(0, separator));
    Value value = parse_value(line.substr(separator + 3));
    Value updated = root;
    Value* container = &updated;
    for (std::size_t i = 0; i < parts.size(); ++i) {
        const Part& part = parts[i];
        if (part.index && part.number > container->elements.size())
            throw std::runtime_error("index gap at '" + part.prefix + "'");
        if (i + 1 == parts.size()) {
            put(*container, part, std::move(value));
            break;
        }
        Kind required = parts[i + 1].index ? Kind::List : Kind::Map;
        const Value* child = get(*container, part);
        if (child && child->kind != required)
            throw std::runtime_error("type conflict at '" + part.prefix + "'");
        if (!child) put(*container, part, Value::container(required));
        container = part.index ? &container->elements[part.number]
                               : &container->fields.at(part.key);
    }
    root = std::move(updated);
}

void unset(Value& root, const std::string& key) {
    std::vector<Part> parts = parse_key(key);
    Value* container = &root;
    for (std::size_t i = 0; i < parts.size(); ++i) {
        const Part& part = parts[i];
        if (!get(*container, part)) throw std::runtime_error("no value at '" + key + "'");
        if (i + 1 == parts.size()) {
            if (part.index)
                container->elements.erase(container->elements.begin() + part.number);
            else
                container->fields.erase(part.key);
            return;
        }
        container = part.index ? &container->elements[part.number]
                               : &container->fields.at(part.key);
    }
}

bool truthy(const Value& value) {
    switch (value.kind) {
        case Kind::Absent: return false;
        case Kind::Integer: return value.integer != 0;
        case Kind::Boolean: return value.boolean;
        case Kind::String: return !value.text.empty();
        case Kind::List: return !value.elements.empty();
        case Kind::Map: return !value.fields.empty();
    }
    return false;
}

std::string stringify(const Value& value) {
    switch (value.kind) {
        case Kind::Absent: return "";
        case Kind::Integer: return std::to_string(value.integer);
        case Kind::String: return value.text;
        case Kind::Boolean: return value.boolean ? "true" : "false";
        case Kind::List: {
            std::string result;
            for (std::size_t i = 0; i < value.elements.size(); ++i) {
                if (i) result += ", ";
                result += stringify(value.elements[i]);
            }
            return result;
        }
        case Kind::Map: throw std::runtime_error("cannot render map");
    }
    return "";
}

Integer number(const Value& value, const std::string& filter) {
    if (value.kind == Kind::Absent) return 0;
    if (value.kind == Kind::Integer) return value.integer;
    if (value.kind == Kind::String && numeric_text(value.text)) return std::stoll(value.text);
    throw std::runtime_error("not a number for '" + filter + "'");
}

struct Filter {
    std::string name;
    std::vector<Value> arguments;
};
struct Expression {
    std::string name;
    std::vector<Filter> filters;
};

bool valid_arguments(const Filter& filter) {
    const std::string& name = filter.name;
    const std::vector<Value>& a = filter.arguments;
    auto is = [&](std::size_t i, Kind kind) { return i < a.size() && a[i].kind == kind; };
    if (name == "default" || name == "eq") return a.size() == 1;
    if (name == "pad" || name == "lpad")
        return (a.size() == 1 || a.size() == 2) && is(0, Kind::Integer) &&
               a[0].integer >= 0 &&
               (a.size() == 1 || (is(1, Kind::String) && a[1].text.size() == 1));
    if (name == "truncate") return a.size() == 1 && is(0, Kind::Integer) && a[0].integer >= 0;
    if (name == "replace")
        return a.size() == 2 && is(0, Kind::String) && is(1, Kind::String) && !a[0].text.empty();
    if (name == "join" || name == "pluck") return a.size() == 1 && is(0, Kind::String);
    if (name == "sort") return a.empty() || (a.size() == 1 && is(0, Kind::String));
    if (name == "div" || name == "mod")
        return a.size() == 1 && is(0, Kind::Integer) && a[0].integer != 0;
    if (name == "add" || name == "sub" || name == "mul" || name == "gt" || name == "lt")
        return a.size() == 1 && is(0, Kind::Integer);
    return a.empty();
}

Expression parse_expression(const std::string& text, int line) {
    static const std::set<std::string> names = {
        "upper", "lower", "title", "trim", "length", "first", "last", "reverse", "items",
        "comma", "sum", "min", "max", "default", "eq", "pad", "lpad", "truncate", "replace",
        "join", "sort", "pluck", "add", "sub", "mul", "div", "mod", "gt", "lt"
    };
    std::vector<std::string> pieces = split(text, '|', true);
    Expression expression{trim(pieces[0]), {}};
    if (!valid_name(expression.name))
        throw TemplateError(line, "invalid name '" + expression.name + "'");
    for (std::size_t i = 1; i < pieces.size(); ++i) {
        std::vector<std::string> items = split(trim(pieces[i]), ':', true);
        Filter filter{items[0], {}};
        if (!names.count(filter.name))
            throw TemplateError(line, "unknown filter '" + filter.name + "'");
        bool valid = true;
        for (std::size_t j = 1; j < items.size(); ++j) {
            const std::string& argument = items[j];
            if (argument.size() >= 2 && argument.front() == '\'' && argument.back() == '\'' &&
                argument.find('\'', 1) == argument.size() - 1)
                filter.arguments.emplace_back(argument.substr(1, argument.size() - 2));
            else if (numeric_text(argument))
                filter.arguments.emplace_back(std::stoll(argument));
            else
                valid = false;
        }
        if (!valid || !valid_arguments(filter))
            throw TemplateError(line, "bad arguments for '" + filter.name + "'");
        expression.filters.push_back(std::move(filter));
    }
    return expression;
}

struct Node {
    char kind = 't';
    int line = 0;
    std::string text;
    std::string indentation;
    Expression expression;
    std::size_t closing = 0;
};

std::vector<Node> analyze(const Source& source) {
    std::vector<Node> nodes;
    std::vector<std::pair<std::string, int>> sections;
    std::vector<std::size_t> openings;
    std::string opening = "{{", closing = "}}";
    for (const SourceLine& line : source) {
        std::vector<Node> tokens;
        std::size_t position = 0, tag_count = 0;
        bool only_spaces = true;
        while (true) {
            std::size_t start = line.text.find(opening, position);
            std::string text = line.text.substr(position, start == std::string::npos
                                                             ? std::string::npos : start - position);
            if (!trim(text).empty()) only_spaces = false;
            Node literal;
            literal.text = std::move(text);
            tokens.push_back(std::move(literal));
            if (start == std::string::npos) break;
            std::size_t after = start + opening.size();
            bool triple = after < line.text.size() && line.text[after] == '{';
            std::string terminator = (triple ? "}" : "") + closing;
            std::size_t end = line.text.find(terminator, after + (triple ? 1 : 0));
            if (end == std::string::npos) throw TemplateError(line.number, "unclosed tag");
            std::string content = trim(line.text.substr(after + (triple ? 1 : 0),
                                                       end - after - (triple ? 1 : 0)));
            position = end + terminator.size();
            Node tag;
            tag.line = line.number;
            tag.kind = triple ? '&' : 'v';
            tag.text = content;
            if (!triple && !content.empty() && std::string("#^/!>&=").find(content[0]) != std::string::npos) {
                tag.kind = content[0];
                if (tag.kind != '=') tag.text = trim(content.substr(1));
            }
            if (tag.kind == '=') {
                std::vector<std::string> delimiters;
                if (content.size() >= 2 && content.back() == '=') {
                    std::istringstream input(content.substr(1, content.size() - 2));
                    std::string item;
                    while (input >> item) delimiters.push_back(item);
                }
                if (delimiters.size() != 2 || delimiters[0].find('=') != std::string::npos ||
                    delimiters[1].find('=') != std::string::npos)
                    throw TemplateError(line.number, "invalid delimiters");
                opening = delimiters[0];
                closing = delimiters[1];
            } else if (tag.kind == 'v' || tag.kind == '&' || tag.kind == '#' || tag.kind == '^') {
                tag.expression = parse_expression(tag.text, line.number);
                if (tag.kind == '#' || tag.kind == '^')
                    sections.emplace_back(tag.expression.name, line.number);
            } else if (tag.kind == '/') {
                if (!valid_name(tag.text)) throw TemplateError(line.number, "invalid name '" + tag.text + "'");
                if (sections.empty()) throw TemplateError(line.number, "unexpected closing '" + tag.text + "'");
                if (sections.back().first != tag.text)
                    throw TemplateError(line.number, "mismatched closing '" + tag.text +
                                                        "', expected '" + sections.back().first + "'");
                sections.pop_back();
            } else if (tag.kind == '>' && !identifier(tag.text)) {
                throw TemplateError(line.number, "invalid name '" + tag.text + "'");
            }
            tag.indentation = line.text.substr(0, start);
            tokens.push_back(std::move(tag));
            ++tag_count;
        }
        bool standalone = tag_count == 1 && only_spaces &&
                          std::string("#^/!>=").find(tokens[1].kind) != std::string::npos;
        for (Node& node : tokens) {
            if (node.kind == 't' && (standalone || node.text.empty())) continue;
            if (node.kind == '>' && !standalone) node.indentation.clear();
            if (node.kind == '#' || node.kind == '^') openings.push_back(nodes.size());
            if (node.kind == '/') {
                nodes[openings.back()].closing = nodes.size();
                openings.pop_back();
            }
            nodes.push_back(std::move(node));
        }
        if (!standalone) {
            Node newline;
            newline.text = "\n";
            nodes.push_back(std::move(newline));
        }
    }
    if (!sections.empty())
        throw TemplateError(sections.back().second, "unclosed section '" + sections.back().first + "'");
    return nodes;
}

Value field(const Value& value, const std::string& key) {
    if (value.kind == Kind::Map) {
        auto found = value.fields.find(key);
        if (found != value.fields.end()) return found->second;
    }
    return Value();
}

int sort_rank(const Value& value) {
    switch (value.kind) {
        case Kind::Absent: return 0;
        case Kind::Integer: return 1;
        case Kind::String: return 2;
        case Kind::Boolean: return 3;
        default: return 4;
    }
}

bool less(const Value& left, const Value& right) {
    int a = sort_rank(left), b = sort_rank(right);
    if (a != b) return a < b;
    if (a == 1) return left.integer < right.integer;
    if (a == 2) return left.text < right.text;
    if (a == 3) return left.boolean < right.boolean;
    return false;
}

Value apply_filter(const Filter& filter, Value value) {
    const std::string& name = filter.name;
    const std::vector<Value>& a = filter.arguments;
    if (name == "default") return truthy(value) ? value : a[0];
    if (name == "eq") return Value(stringify(value) == stringify(a[0]));
    if (name == "length") {
        std::size_t length = value.kind == Kind::List ? value.elements.size()
                           : value.kind == Kind::Map ? value.fields.size() : stringify(value).size();
        return Value(static_cast<Integer>(length));
    }
    if (name == "first" || name == "last") {
        if (value.kind != Kind::List) return value;
        if (value.elements.empty()) return Value();
        return name == "first" ? value.elements.front() : value.elements.back();
    }
    if (name == "reverse") {
        if (value.kind == Kind::List) std::reverse(value.elements.begin(), value.elements.end());
        if (value.kind == Kind::String) std::reverse(value.text.begin(), value.text.end());
        return value;
    }
    if (name == "items") {
        if (value.kind != Kind::Map) return value;
        Value result = Value::container(Kind::List);
        for (const auto& entry : value.fields) {
            Value item = Value::container(Kind::Map);
            item.fields["key"] = Value(entry.first);
            item.fields["value"] = entry.second;
            result.elements.push_back(std::move(item));
        }
        return result;
    }
    if (name == "sort") {
        if (value.kind != Kind::List) return value;
        std::stable_sort(value.elements.begin(), value.elements.end(), [&](const Value& l, const Value& r) {
            return a.empty() ? less(l, r) : less(field(l, a[0].text), field(r, a[0].text));
        });
        return value;
    }
    if (name == "pluck") {
        if (value.kind != Kind::List) return value;
        for (Value& element : value.elements) element = field(element, a[0].text);
        return value;
    }
    if (name == "sum" || name == "min" || name == "max") {
        if (value.kind != Kind::List) return Value(number(value, name));
        if (value.elements.empty()) return name == "sum" ? Value(Integer{0}) : Value();
        Integer result = 0;
        for (std::size_t i = 0; i < value.elements.size(); ++i) {
            Integer current = number(value.elements[i], name);
            if (name == "sum") result += current;
            else if (!i) result = current;
            else if (name == "min") result = std::min(result, current);
            else result = std::max(result, current);
        }
        return Value(result);
    }
    if (name == "comma") {
        Integer n = number(value, name);
        std::string digits = std::to_string(n < 0 ? -n : n), result;
        for (std::size_t i = 0; i < digits.size(); ++i) {
            if (i && (digits.size() - i) % 3 == 0) result += ',';
            result += digits[i];
        }
        return Value((n < 0 ? "-" : "") + result);
    }
    if (name == "add" || name == "sub" || name == "mul" || name == "div" ||
        name == "mod" || name == "gt" || name == "lt") {
        Integer n = number(value, name), operand = a[0].integer;
        if (name == "add") return Value(n + operand);
        if (name == "sub") return Value(n - operand);
        if (name == "mul") return Value(n * operand);
        if (name == "gt") return Value(n > operand);
        if (name == "lt") return Value(n < operand);
        Integer quotient = n / operand;
        if (n % operand != 0 && (n < 0) != (operand < 0)) --quotient;
        return Value(name == "div" ? quotient : n - operand * quotient);
    }
    if (name == "join" && value.kind == Kind::List) {
        std::string result;
        for (std::size_t i = 0; i < value.elements.size(); ++i) {
            if (i) result += a[0].text;
            result += stringify(value.elements[i]);
        }
        return Value(result);
    }
    std::string text = stringify(value);
    if (name == "upper" || name == "lower" || name == "title") {
        for (std::size_t i = 0; i < text.size(); ++i) {
            bool upper = name == "upper" || (name == "title" && (i == 0 || text[i - 1] == ' '));
            if (upper && text[i] >= 'a' && text[i] <= 'z') text[i] -= 'a' - 'A';
            if (!upper && text[i] >= 'A' && text[i] <= 'Z') text[i] += 'a' - 'A';
        }
    } else if (name == "trim") {
        text = trim(text);
    } else if (name == "pad" || name == "lpad") {
        if (static_cast<Integer>(text.size()) < a[0].integer) {
            std::string padding(static_cast<std::size_t>(a[0].integer) - text.size(),
                                a.size() == 2 ? a[1].text[0] : ' ');
            text = name == "pad" ? text + padding : padding + text;
        }
    } else if (name == "truncate") {
        if (static_cast<Integer>(text.size()) > a[0].integer)
            text = text.substr(0, static_cast<std::size_t>(a[0].integer)) + "...";
    } else if (name == "replace") {
        std::string result;
        std::size_t position = 0;
        while (true) {
            std::size_t found = text.find(a[0].text, position);
            if (found == std::string::npos) {
                result += text.substr(position);
                break;
            }
            result += text.substr(position, found - position) + a[1].text;
            position = found + a[0].text.size();
        }
        text = std::move(result);
    }
    return Value(text);
}

std::string escape_html(const std::string& text) {
    std::string result;
    for (char c : text) {
        switch (c) {
            case '&':
                result += "&amp;";
                break;
            case '<':
                result += "&lt;";
                break;
            case '>':
                result += "&gt;";
                break;
            case '"':
                result += "&quot;";
                break;
            case '\'':
                result += "&#39;";
                break;
            default: result += c;
        }
    }
    return result;
}

class Renderer {
    const std::map<std::string, Source>& partials;
    bool strict;
    std::vector<Value> contexts;
    std::vector<std::pair<std::size_t, std::size_t>> loops;
    std::string output;

    std::pair<bool, Value> resolve(const std::string& name) const {
        if (name == ".") return {true, contexts.back()};
        if (name[0] == '@') {
            if (loops.empty()) return {false, Value()};
            std::size_t i = loops.back().first, n = loops.back().second;
            if (name == "@index") return {true, Value(static_cast<Integer>(i))};
            if (name == "@number") return {true, Value(static_cast<Integer>(i + 1))};
            return {true, Value(name == "@first" ? i == 0 : i + 1 == n)};
        }
        std::vector<Part> parts;
        for (const std::string& token : split(name, '.')) {
            bool index = subscript(token);
            parts.push_back({index, token, index ? index_number(token) : 0, ""});
        }
        for (auto context = contexts.rbegin(); context != contexts.rend(); ++context) {
            const Value* current = get(*context, parts[0]);
            if (!current) continue;
            for (std::size_t i = 1; i < parts.size() && current; ++i) current = get(*current, parts[i]);
            return current ? std::make_pair(true, *current) : std::make_pair(false, Value());
        }
        return {false, Value()};
    }

    Value evaluate(const Expression& expression, bool require) const {
        std::pair<bool, Value> found = resolve(expression.name);
        if (!found.first && require) throw std::runtime_error("missing '" + expression.name + "'");
        for (const Filter& filter : expression.filters)
            found.second = apply_filter(filter, std::move(found.second));
        return found.second;
    }

    void render(const std::vector<Node>& nodes, std::size_t begin, std::size_t end, int depth) {
        for (std::size_t i = begin; i < end; ++i) {
            const Node& node = nodes[i];
            try {
                if (node.kind == 't') {
                    output += node.text;
                } else if (node.kind == 'v' || node.kind == '&') {
                    std::string text = stringify(evaluate(node.expression, strict));
                    output += node.kind == '&' ? text : escape_html(text);
                } else if (node.kind == '#' || node.kind == '^') {
                    Value value = evaluate(node.expression, false);
                    if (node.kind == '^') {
                        if (!truthy(value)) render(nodes, i + 1, node.closing, depth);
                    } else if (value.kind == Kind::List) {
                        for (std::size_t j = 0; j < value.elements.size(); ++j) {
                            contexts.push_back(value.elements[j]);
                            loops.emplace_back(j, value.elements.size());
                            render(nodes, i + 1, node.closing, depth);
                            loops.pop_back();
                            contexts.pop_back();
                        }
                    } else if (truthy(value)) {
                        contexts.push_back(std::move(value));
                        render(nodes, i + 1, node.closing, depth);
                        contexts.pop_back();
                    }
                    i = node.closing;
                } else if (node.kind == '>') {
                    auto found = partials.find(node.text);
                    if (found == partials.end()) throw std::runtime_error("unknown partial '" + node.text + "'");
                    if (depth == 8) throw std::runtime_error("partial depth exceeded at '" + node.text + "'");
                    Source source = found->second;
                    for (SourceLine& line : source)
                        if (!line.text.empty()) line.text = node.indentation + line.text;
                    std::vector<Node> partial_nodes = analyze(source);
                    render(partial_nodes, 0, partial_nodes.size(), depth + 1);
                }
            } catch (const TemplateError&) {
                throw;
            } catch (const std::runtime_error& error) {
                throw TemplateError(node.line, error.what());
            }
        }
    }

public:
    Renderer(const Value& root, const std::map<std::string, Source>& partials, bool strict)
        : partials(partials), strict(strict), contexts{root} {}

    std::string run(const std::vector<Node>& nodes) {
        render(nodes, 0, nodes.size(), 0);
        return output;
    }
};

std::string notation(const Value& value) {
    if (value.kind == Kind::String) {
        std::string text = "\"";
        for (char c : value.text) {
            if (c == '\\' || c == '"') text += '\\';
            text += c == '\n' ? "\\n" : std::string(1, c);
        }
        return text + '"';
    }
    if (value.kind == Kind::List) return "[]";
    if (value.kind == Kind::Map) return "{}";
    return stringify(value);
}

void leaves(const Value& value, const std::string& path, std::vector<std::string>& output) {
    if (value.kind == Kind::Map && !value.fields.empty()) {
        for (const auto& entry : value.fields)
            leaves(entry.second, path.empty() ? entry.first : path + "." + entry.first, output);
    } else if (value.kind == Kind::List && !value.elements.empty()) {
        for (std::size_t i = 0; i < value.elements.size(); ++i)
            leaves(value.elements[i], path + "[" + std::to_string(i) + "]", output);
    } else if (!path.empty()) {
        output.push_back(path + " = " + notation(value));
    }
}

void render_template(const std::string& name, const Source& source, const Value& root,
                     const std::map<std::string, Source>& partials, bool strict) {
    try {
        std::vector<Node> nodes = analyze(source);
        std::string result = Renderer(root, partials, strict).run(nodes);
        std::size_t lines = static_cast<std::size_t>(std::count(result.begin(), result.end(), '\n'));
        if (!result.empty() && result.back() != '\n') ++lines;
        std::cout << "TEMPLATE " << name << " OK lines=" << lines << " chars=" << result.size() << '\n';
        std::cout << result;
        if (!result.empty() && result.back() != '\n') std::cout << '\n';
    } catch (const TemplateError& error) {
        std::cout << "TEMPLATE " << name << " ERROR line " << error.line << ": " << error.what() << '\n';
    }
}

int main() {
    Value root = Value::container(Kind::Map);
    std::map<std::string, Source> partials, templates;
    bool strict = false;
    int number = 0;
    std::string command;
    while (std::getline(std::cin, command)) {
        ++number;
        if (command == "END") break;
        if (command == "DATA" || command.compare(0, 8, "PARTIAL ") == 0 ||
            command.compare(0, 9, "TEMPLATE ") == 0) {
            std::string marker = command == "DATA" ? "ENDDATA"
                               : command[0] == 'P' ? "ENDPARTIAL" : "ENDTEMPLATE";
            Source body;
            std::string line;
            while (std::getline(std::cin, line)) {
                ++number;
                if (line == marker) break;
                body.push_back({number, line});
            }
            if (command == "DATA") {
                int set_count = 0, unset_count = 0;
                std::vector<std::string> errors;
                for (const SourceLine& data : body) {
                    if (data.text.empty() || data.text[0] == '#') continue;
                    try {
                        if (data.text.compare(0, 6, "UNSET ") == 0) {
                            unset(root, data.text.substr(6));
                            ++unset_count;
                        } else {
                            assign(root, data.text);
                            ++set_count;
                        }
                    } catch (const std::runtime_error& error) {
                        errors.push_back("ERROR line " + std::to_string(data.number) + ": " + error.what());
                    }
                }
                std::cout << "DATA set=" << set_count << " unset=" << unset_count << " errors=" << errors.size() << '\n';
                for (const std::string& error : errors) std::cout << error << '\n';
            } else if (command[0] == 'P') {
                std::string name = command.substr(8);
                try {
                    analyze(body);
                    bool replaced = partials.count(name) != 0;
                    partials[name] = body;
                    std::cout << "PARTIAL " << name << (replaced ? " REPLACED" : " DEFINED")
                              << " lines=" << body.size() << '\n';
                } catch (const TemplateError& error) {
                    std::cout << "PARTIAL " << name << " ERROR line " << error.line << ": " << error.what() << '\n';
                }
            } else {
                std::string name = command.substr(9);
                templates[name] = body;
                render_template(name, body, root, partials, strict);
            }
        } else if (command.compare(0, 7, "RENDER ") == 0) {
            std::string name = command.substr(7);
            auto found = templates.find(name);
            if (found == templates.end())
                std::cout << "TEMPLATE " << name << " ERROR line " << number << ": unknown template '" << name << "'\n";
            else
                render_template(name, found->second, root, partials, strict);
        } else if (command == "DUMP") {
            std::vector<std::string> output;
            leaves(root, "", output);
            std::cout << "DUMP leaves=" << output.size() << '\n';
            for (const std::string& line : output) std::cout << line << '\n';
        } else if (command == "RESET") {
            root = Value::container(Kind::Map);
            partials.clear();
            templates.clear();
            std::cout << "RESET\n";
        } else if (command.compare(0, 7, "STRICT ") == 0) {
            strict = command == "STRICT ON";
            std::cout << command << '\n';
        }
    }
}
