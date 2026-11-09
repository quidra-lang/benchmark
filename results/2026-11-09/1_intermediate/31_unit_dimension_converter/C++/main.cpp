#include <algorithm>
#include <array>
#include <cstdint>
#include <iostream>
#include <map>
#include <numeric>
#include <optional>
#include <regex>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

using Integer = std::int64_t;

struct CommandError : std::runtime_error { using std::runtime_error::runtime_error; };
[[noreturn]] void fail(const std::string& message) { throw CommandError(message); }

struct Fraction {
    Integer n, d;

    Fraction(Integer numerator = 0, Integer denominator = 1) : n(numerator), d(denominator) {
        if (d < 0) { n = -n; d = -d; }
        const auto divisor = std::gcd(n, d);
        n /= divisor;
        d /= divisor;
    }
    Fraction operator+(Fraction b) const { return {n * b.d + b.n * d, d * b.d}; }
    Fraction operator-(Fraction b) const { return {n * b.d - b.n * d, d * b.d}; }
    Fraction operator*(Fraction b) const { return {n * b.n, d * b.d}; }
    Fraction operator/(Fraction b) const { return {n * b.d, d * b.n}; }
    Fraction operator-() const { return {-n, d}; }
    Fraction absolute() const { return n < 0 ? -*this : *this; }
    int compare(Fraction b) const {
        const auto left = n * b.d, right = b.n * d;
        return left < right ? -1 : left > right ? 1 : 0;
    }
    Fraction power(Integer exponent) const {
        const Fraction factor = exponent < 0 ? Fraction(1) / *this : *this;
        Fraction result(1);
        if (exponent < 0) exponent = -exponent;
        for (Integer i = 0; i < exponent; ++i) result = result * factor;
        return result;
    }
    std::string str() const {
        return std::to_string(n) + (d == 1 ? "" : "/" + std::to_string(d));
    }
    std::string decimal() const {
        const auto magnitude = n < 0 ? -n : n;
        const auto whole = magnitude / d, tail = magnitude % d * 1000000 / d;
        const auto digits = std::to_string(tail);
        return std::string(n < 0 ? "-" : "") + std::to_string(whole) + "." + std::string(6 - digits.size(), '0') + digits;
    }
    std::string notation(const std::string& unit) const { return str() + " " + unit + " (" + decimal() + ")"; }
};

std::vector<std::string> split(const std::string& text, char separator) {
    std::vector<std::string> result;
    std::size_t start = 0;
    for (;;) {
        const auto end = text.find(separator, start);
        result.push_back(text.substr(start, end == std::string::npos ? end : end - start));
        if (end == std::string::npos) return result;
        start = end + 1;
    }
}
std::string join(const std::vector<std::string>& values, const std::string& separator = " ") {
    std::string result;
    for (std::size_t i = 0; i < values.size(); ++i) {
        if (i) result += separator;
        result += values[i];
    }
    return result;
}
Fraction numberValue(const std::string& text) {
    static const std::regex pattern(R"(-?[0-9]+([./][0-9]+)?)");
    if (!std::regex_match(text, pattern)) fail("BAD NUMBER " + text);
    const bool negative = text.front() == '-';
    const auto body = negative ? text.substr(1) : text;
    Fraction result;
    if (const auto slash = body.find('/'); slash != std::string::npos) {
        const Integer denominator = std::stoll(body.substr(slash + 1));
        if (denominator == 0) fail("BAD NUMBER " + text);
        result = Fraction(std::stoll(body.substr(0, slash)), denominator);
    } else if (const auto dot = body.find('.'); dot != std::string::npos) {
        Integer scale = 1;
        for (std::size_t i = dot + 1; i < body.size(); ++i) scale *= 10;
        result = Fraction(std::stoll(body.substr(0, dot)) * scale + std::stoll(body.substr(dot + 1)), scale);
    } else result = Fraction(std::stoll(body));
    return negative ? -result : result;
}
Integer checkedExponent(const std::string& text) {
    const Integer value = std::stoll(text);
    if (value == 0 || value < -3 || value > 3) fail("BAD EXPONENT " + text);
    return value;
}
const std::map<std::string, std::size_t> FUNCTIONS{{"abs", 1}, {"sqrt", 1}, {"min", 2}, {"max", 2}};
void checkName(const std::string& name, bool variable = false) {
    static const std::regex pattern("[A-Za-z]{1,12}");
    if (!std::regex_match(name, pattern) || (variable && FUNCTIONS.count(name))) fail("BAD NAME " + name);
}

struct Dimension {
    std::array<Integer, 7> exponents{};

    Dimension operator+(const Dimension& other) const {
        Dimension result;
        for (std::size_t i = 0; i < 7; ++i) result.exponents[i] = exponents[i] + other.exponents[i];
        return result;
    }
    Dimension operator-(const Dimension& other) const {
        Dimension result;
        for (std::size_t i = 0; i < 7; ++i) result.exponents[i] = exponents[i] - other.exponents[i];
        return result;
    }
    Dimension scaled(Integer factor) const {
        Dimension result;
        for (std::size_t i = 0; i < 7; ++i) result.exponents[i] = exponents[i] * factor;
        return result;
    }
    bool operator==(const Dimension& other) const { return exponents == other.exponents; }
    void match(const Dimension& other) const {
        if (!(*this == other)) fail("DIMENSION MISMATCH " + str() + " vs " + other.str());
    }
    std::string str() const {
        const std::array<std::string, 7> symbols{"kg", "m", "s", "A", "K", "mol", "cd"};
        std::vector<std::string> parts;
        for (std::size_t i = 0; i < 7; ++i) if (exponents[i] != 0) {
            parts.push_back(symbols[i] + (exponents[i] == 1 ? "" : "^" + std::to_string(exponents[i])));
        }
        return parts.empty() ? "1" : join(parts);
    }
};
struct Quantity { Fraction value{1}; Dimension dimension; };

const std::vector<std::pair<std::string, Dimension>> KINDS{
    {"dimensionless", {{0,0,0,0,0,0,0}}}, {"length", {{0,1,0,0,0,0,0}}}, {"mass", {{1,0,0,0,0,0,0}}},
    {"time", {{0,0,1,0,0,0,0}}}, {"current", {{0,0,0,1,0,0,0}}}, {"temperature", {{0,0,0,0,1,0,0}}},
    {"amount", {{0,0,0,0,0,1,0}}}, {"luminous_intensity", {{0,0,0,0,0,0,1}}},
    {"area", {{0,2,0,0,0,0,0}}}, {"volume", {{0,3,0,0,0,0,0}}}, {"speed", {{0,1,-1,0,0,0,0}}},
    {"acceleration", {{0,1,-2,0,0,0,0}}}, {"density", {{1,-3,0,0,0,0,0}}}, {"momentum", {{1,1,-1,0,0,0,0}}},
    {"force", {{1,1,-2,0,0,0,0}}}, {"energy", {{1,2,-2,0,0,0,0}}}, {"power", {{1,2,-3,0,0,0,0}}},
    {"pressure", {{1,-1,-2,0,0,0,0}}}, {"frequency", {{0,0,-1,0,0,0,0}}}, {"charge", {{0,0,1,1,0,0,0}}},
    {"voltage", {{1,2,-3,-1,0,0,0}}}, {"resistance", {{1,2,-3,-2,0,0,0}}},
    {"conductance", {{-1,-2,3,2,0,0,0}}}, {"capacitance", {{-1,-2,4,2,0,0,0}}},
    {"magnetic_flux", {{1,2,-2,-1,0,0,0}}}, {"flux_density", {{1,0,-2,-1,0,0,0}}},
    {"inductance", {{1,2,-2,-2,0,0,0}}}, {"illuminance", {{0,-2,0,0,0,0,1}}},
    {"catalytic_activity", {{0,0,-1,0,0,1,0}}},
};
std::optional<Dimension> kindDimension(const std::string& name) {
    for (const auto& [label, dimension] : KINDS) if (label == name) return dimension;
    return std::nullopt;
}
std::string kindName(const Dimension& dimension) {
    for (const auto& [name, known] : KINDS) if (known == dimension) return name;
    return "-";
}
struct Definition { Fraction value; std::string expression; };
struct Unit {
    std::string symbol;
    Quantity quantity;
    bool prefixable;
    std::optional<Definition> definition;
};
struct BuiltinRow { std::string symbol; Fraction factor; std::string kind; bool prefixable; };
const std::vector<BuiltinRow> BUILTINS{
    {"m",1,"length",true}, {"g",{1,1000},"mass",true}, {"s",1,"time",true},
    {"A",1,"current",true}, {"K",1,"temperature",true}, {"mol",1,"amount",true},
    {"cd",1,"luminous_intensity",true}, {"N",1,"force",true}, {"J",1,"energy",true},
    {"W",1,"power",true}, {"Pa",1,"pressure",true}, {"Hz",1,"frequency",true},
    {"C",1,"charge",true}, {"V",1,"voltage",true}, {"ohm",1,"resistance",true},
    {"S",1,"conductance",true}, {"F",1,"capacitance",true}, {"Wb",1,"magnetic_flux",true},
    {"T",1,"flux_density",true}, {"H",1,"inductance",true}, {"lx",1,"illuminance",true},
    {"kat",1,"catalytic_activity",true}, {"L",{1,1000},"volume",true}, {"t",1000,"mass",false},
    {"min",60,"time",false}, {"h",3600,"time",false}, {"day",86400,"time",false},
    {"in",{127,5000},"length",false}, {"ft",{381,1250},"length",false}, {"yd",{1143,1250},"length",false},
    {"mi",{201168,125},"length",false}, {"nmi",1852,"length",false}, {"ha",10000,"area",false},
    {"kn",{463,900},"speed",false}, {"bar",100000,"pressure",true}, {"atm",101325,"pressure",false},
    {"Torr",{20265,152},"pressure",false}, {"cal",{523,125},"energy",true}, {"Wh",3600,"energy",true},
    {"Ah",3600,"charge",true}, {"dC",1,"temperature",false}, {"dF",{5,9},"temperature",false},
};
const std::vector<std::pair<std::string, Fraction>> PREFIXES{
    {"G",1000000000}, {"M",1000000}, {"k",1000}, {"h",100}, {"da",10},
    {"d",{1,10}}, {"c",{1,100}}, {"m",{1,1000}}, {"u",{1,1000000}}, {"n",{1,1000000000}},
};

class Database {
public:
    std::vector<Unit> units;
    std::map<std::string, Quantity> variables;

    Database() {
        for (const auto& row : BUILTINS) units.push_back({row.symbol, {row.factor, *kindDimension(row.kind)}, row.prefixable, std::nullopt});
    }
    std::optional<Quantity> resolve(const std::string& name) const {
        for (const auto& unit : units) if (unit.symbol == name) return unit.quantity;
        for (const auto& [prefix, factor] : PREFIXES) {
            if (name.compare(0, prefix.size(), prefix) != 0) continue;
            const auto suffix = name.substr(prefix.size());
            for (std::size_t i = 0; i < BUILTINS.size(); ++i) {
                const auto& unit = units[i];
                if (unit.prefixable && unit.symbol == suffix) return Quantity{factor * unit.quantity.value, unit.quantity.dimension};
            }
        }
        return std::nullopt;
    }
    std::string simplified(const Dimension& dimension) const {
        for (const auto& unit : units) if (unit.quantity.value.compare(1) == 0 && unit.quantity.dimension == dimension) return unit.symbol;
        return dimension.str();
    }
    std::vector<Unit> selected(const Dimension& dimension) const {
        std::vector<Unit> result;
        for (const auto& unit : units) if (unit.quantity.dimension == dimension) result.push_back(unit);
        std::sort(result.begin(), result.end(), [](const Unit& a, const Unit& b) {
            const auto comparison = a.quantity.value.compare(b.quantity.value);
            return comparison ? comparison < 0 : a.symbol < b.symbol;
        });
        return result;
    }
};

enum class TokenKind { Name, Number, Unit, Symbol, Invalid, End };
struct Token { TokenKind kind; std::string text; std::size_t position; };
struct UnitExpr {
    enum class Kind { Name, Number, Power, Product } kind;
    std::string text;
    std::vector<UnitExpr> children;
    std::vector<char> operations;
};
struct QuantityExpr {
    enum class Kind { Literal, Variable, Negative, Power, Binary, Call } kind;
    std::string text, unit;
    char operation = 0;
    std::vector<QuantityExpr> children;
};
bool letter(char c) { return ('A' <= c && c <= 'Z') || ('a' <= c && c <= 'z'); }
bool digit(char c) { return '0' <= c && c <= '9'; }

class Parser {
    std::string source;
    std::vector<Token> tokens;
    std::size_t position = 0;

    const Token& current() const { return tokens[position]; }
    Token advance() { return tokens[position++]; }
    [[noreturn]] void syntax() const {
        fail("SYNTAX " + source + " AT " + (current().kind == TokenKind::End ? "END" : std::to_string(current().position)));
    }
    bool take(const std::string& text) {
        if (current().text != text) return false;
        ++position;
        return true;
    }
    void expect(const std::string& text) { if (!take(text)) syntax(); }
    std::string exponent() {
        const std::string sign = take("-") ? "-" : "";
        if (current().kind != TokenKind::Number || current().text.find('.') != std::string::npos) syntax();
        return sign + advance().text;
    }
    UnitExpr unitTerm() {
        UnitExpr node;
        if (current().kind == TokenKind::Name) node = {UnitExpr::Kind::Name, advance().text, {}, {}};
        else if (current().kind == TokenKind::Number && current().text.front() != '0') node = {UnitExpr::Kind::Number, advance().text, {}, {}};
        else if (take("(")) { node = unitExpression(); expect(")"); }
        else syntax();
        if (take("^")) {
            auto power = exponent();
            node = {UnitExpr::Kind::Power, power, {std::move(node)}, {}};
        }
        return node;
    }
    UnitExpr unitExpression() {
        UnitExpr node{UnitExpr::Kind::Product, "", {unitTerm()}, {'*'}};
        while (current().text == "*" || current().text == "/") {
            node.operations.push_back(advance().text.front());
            node.children.push_back(unitTerm());
        }
        return node;
    }
    QuantityExpr primary() {
        const auto token = current();
        QuantityExpr node;
        if (token.kind == TokenKind::Number) {
            advance();
            const auto unit = current().kind == TokenKind::Unit ? advance().text : "";
            node = {QuantityExpr::Kind::Literal, token.text, unit.empty() ? "" : unit.substr(1, unit.size() - 2), 0, {}};
        } else if (token.kind == TokenKind::Unit) {
            advance();
            node = {QuantityExpr::Kind::Literal, "1", token.text.substr(1, token.text.size() - 2), 0, {}};
        } else if (token.kind == TokenKind::Name) {
            advance();
            if (take("(")) {
                node = {QuantityExpr::Kind::Call, token.text, "", 0, {expression()}};
                while (take(",")) node.children.push_back(expression());
                expect(")");
            } else node = {QuantityExpr::Kind::Variable, token.text, "", 0, {}};
        } else if (take("(")) { node = expression(); expect(")"); }
        else syntax();
        if (take("^")) {
            auto power = exponent();
            node = {QuantityExpr::Kind::Power, power, "", 0, {std::move(node)}};
        }
        return node;
    }
    QuantityExpr unary() {
        if (take("-")) return {QuantityExpr::Kind::Negative, "", "", 0, {unary()}};
        return primary();
    }
    QuantityExpr product() {
        auto node = unary();
        while (current().text == "*" || current().text == "/") {
            const auto operation = advance().text.front();
            auto right = unary();
            node = {QuantityExpr::Kind::Binary, "", "", operation, {std::move(node), std::move(right)}};
        }
        return node;
    }
    QuantityExpr expression() {
        auto node = product();
        while (current().text == "+" || current().text == "-") {
            const auto operation = advance().text.front();
            auto right = product();
            node = {QuantityExpr::Kind::Binary, "", "", operation, {std::move(node), std::move(right)}};
        }
        return node;
    }
public:
    Parser(std::string text, bool quantityMode) : source(std::move(text)) {
        for (std::size_t i = 0; i < source.size();) {
            const auto start = i;
            const auto character = source[i++];
            auto kind = TokenKind::Invalid;
            if (letter(character)) {
                kind = TokenKind::Name;
                while (i < source.size() && letter(source[i])) ++i;
            } else if (digit(character)) {
                kind = TokenKind::Number;
                while (i < source.size() && digit(source[i])) ++i;
                if (quantityMode && i + 1 < source.size() && source[i] == '.' && digit(source[i + 1])) {
                    ++i;
                    while (i < source.size() && digit(source[i])) ++i;
                }
            } else if (quantityMode && character == '[') {
                const auto closing = source.find(']', i);
                if (closing != std::string::npos && closing > i) { kind = TokenKind::Unit; i = closing + 1; }
            } else if (std::string(quantityMode ? "+-*/^()," : "*/^()-").find(character) != std::string::npos) kind = TokenKind::Symbol;
            tokens.push_back({kind, source.substr(start, i - start), start + 1});
        }
        tokens.push_back({TokenKind::End, "", source.size() + 1});
    }
    UnitExpr unit() {
        auto node = unitExpression();
        if (current().kind != TokenKind::End) syntax();
        return node;
    }
    QuantityExpr quantity() {
        auto node = expression();
        if (current().kind != TokenKind::End) syntax();
        return node;
    }
};

void validateUnit(const Database& database, const UnitExpr& node) {
    if (node.kind == UnitExpr::Kind::Name) {
        if (!database.resolve(node.text)) fail("UNKNOWN UNIT " + node.text);
    } else {
        for (const auto& child : node.children) validateUnit(database, child);
        if (node.kind == UnitExpr::Kind::Power) checkedExponent(node.text);
    }
}
Quantity evaluateUnit(const Database& database, const UnitExpr& node) {
    if (node.kind == UnitExpr::Kind::Name) return *database.resolve(node.text);
    if (node.kind == UnitExpr::Kind::Number) return {Fraction(std::stoll(node.text)), {}};
    if (node.kind == UnitExpr::Kind::Power) {
        const auto value = evaluateUnit(database, node.children.front());
        const Integer exponent = std::stoll(node.text);
        return {value.value.power(exponent), value.dimension.scaled(exponent)};
    }
    Quantity result;
    for (std::size_t i = 0; i < node.children.size(); ++i) {
        const auto right = evaluateUnit(database, node.children[i]);
        result = node.operations[i] == '*' ? Quantity{result.value * right.value, result.dimension + right.dimension} :
            Quantity{result.value / right.value, result.dimension - right.dimension};
    }
    return result;
}
UnitExpr parseUnit(const Database& database, const std::string& text) {
    auto tree = Parser(text, false).unit();
    validateUnit(database, tree);
    return tree;
}
Quantity unitValue(const Database& database, const std::string& text) { return evaluateUnit(database, parseUnit(database, text)); }

struct Reduced { Fraction coefficient{1}; std::vector<std::pair<std::string, Integer>> powers; };
Reduced reduceUnit(const UnitExpr& node) {
    if (node.kind == UnitExpr::Kind::Name) return {1, {{node.text, 1}}};
    if (node.kind == UnitExpr::Kind::Number) return {Fraction(std::stoll(node.text)), {}};
    if (node.kind == UnitExpr::Kind::Power) {
        auto result = reduceUnit(node.children.front());
        const Integer exponent = std::stoll(node.text);
        result.coefficient = result.coefficient.power(exponent);
        for (auto& item : result.powers) item.second *= exponent;
        return result;
    }
    Reduced result;
    for (std::size_t i = 0; i < node.children.size(); ++i) {
        const auto right = reduceUnit(node.children[i]);
        const bool multiply = node.operations[i] == '*';
        result.coefficient = multiply ? result.coefficient * right.coefficient : result.coefficient / right.coefficient;
        for (const auto& [name, power] : right.powers) {
            auto found = std::find_if(result.powers.begin(), result.powers.end(), [&](const auto& item) { return item.first == name; });
            const auto amount = multiply ? power : -power;
            if (found == result.powers.end()) result.powers.emplace_back(name, amount);
            else found->second += amount;
        }
    }
    return result;
}
std::string reducedText(const UnitExpr& tree) {
    const auto result = reduceUnit(tree);
    std::vector<std::string> parts;
    if (result.coefficient.compare(1) != 0) parts.push_back(result.coefficient.str());
    for (const auto& [name, power] : result.powers) if (power != 0) {
        parts.push_back(name + (power == 1 ? "" : "^" + std::to_string(power)));
    }
    return parts.empty() ? "1" : join(parts);
}
Integer integerSqrt(Integer value) {
    if (value < 2) return value;
    Integer current = value, next = (value + 1) / 2;
    while (next < current) {
        current = next;
        next = (current + value / current) / 2;
    }
    return current;
}
Quantity evaluateQuantity(const Database& database, const QuantityExpr& node) {
    if (node.kind == QuantityExpr::Kind::Literal) {
        const auto unit = node.unit.empty() ? Quantity{} : unitValue(database, node.unit);
        return {numberValue(node.text) * unit.value, unit.dimension};
    }
    if (node.kind == QuantityExpr::Kind::Variable) {
        const auto found = database.variables.find(node.text);
        if (found == database.variables.end()) fail("UNKNOWN VARIABLE " + node.text);
        return found->second;
    }
    if (node.kind == QuantityExpr::Kind::Call) {
        const auto function = FUNCTIONS.find(node.text);
        if (function == FUNCTIONS.end()) fail("UNKNOWN FUNCTION " + node.text);
        if (node.children.size() != function->second) fail("BAD ARGUMENTS " + node.text);
        const auto first = evaluateQuantity(database, node.children.front());
        if (node.text == "abs") return {first.value.absolute(), first.dimension};
        if (node.text == "sqrt") {
            if (first.value.n < 0) fail("NEGATIVE ROOT");
            for (const auto exponent : first.dimension.exponents) if (exponent % 2 != 0) fail("ODD DIMENSION " + first.dimension.str());
            const auto n = integerSqrt(first.value.n), d = integerSqrt(first.value.d);
            if (n * n != first.value.n || d * d != first.value.d) fail("NOT EXACT");
            auto dimension = first.dimension;
            for (auto& exponent : dimension.exponents) exponent /= 2;
            return {{n, d}, dimension};
        }
        const auto second = evaluateQuantity(database, node.children[1]);
        first.dimension.match(second.dimension);
        const auto comparison = first.value.compare(second.value);
        return (node.text == "min" ? comparison <= 0 : comparison >= 0) ? first : second;
    }
    const auto left = evaluateQuantity(database, node.children.front());
    if (node.kind == QuantityExpr::Kind::Negative) return {-left.value, left.dimension};
    if (node.kind == QuantityExpr::Kind::Power) {
        const auto exponent = checkedExponent(node.text);
        if (left.value.n == 0 && exponent < 0) fail("DIVISION BY ZERO");
        return {left.value.power(exponent), left.dimension.scaled(exponent)};
    }
    const auto right = evaluateQuantity(database, node.children[1]);
    if (node.operation == '+' || node.operation == '-') {
        left.dimension.match(right.dimension);
        return {node.operation == '+' ? left.value + right.value : left.value - right.value, left.dimension};
    }
    if (node.operation == '*') return {left.value * right.value, left.dimension + right.dimension};
    if (right.value.n == 0) fail("DIVISION BY ZERO");
    return {left.value / right.value, left.dimension - right.dimension};
}
Quantity quantityValue(const Database& database, const std::string& text) {
    return evaluateQuantity(database, Parser(text, true).quantity());
}

std::vector<std::string> execute(Database& database, const std::string& line) {
    const auto words = split(line, ' ');
    const auto& command = words[0];
    if (command == "DEFINE") {
        const auto& name = words[1];
        checkName(name);
        const auto value = numberValue(words[3]);
        const auto unit = unitValue(database, words[4]);
        if (kindDimension(name) || database.resolve(name)) fail("NAME TAKEN " + name);
        if (value.n <= 0) fail("NOT POSITIVE " + words[3]);
        const Quantity result{value * unit.value, unit.dimension};
        database.units.push_back({name, result, false, Definition{value, words[4]}});
        return {"DEFINE " + name + " factor=" + result.value.str() + " dim=" + result.dimension.str() + " kind=" + kindName(result.dimension)};
    }
    if (command == "UNDEF") {
        const auto found = std::find_if(database.units.begin(), database.units.end(), [&](const Unit& unit) { return unit.symbol == words[1]; });
        if (found == database.units.end()) fail("NOT DEFINED " + words[1]);
        if (std::size_t(found - database.units.begin()) < BUILTINS.size()) fail("BUILTIN UNIT " + words[1]);
        database.units.erase(found);
        return {"UNDEF " + words[1]};
    }
    if (command == "DEFS") {
        std::vector<std::string> rows{"DEFS count=" + std::to_string(database.units.size() - BUILTINS.size())};
        for (std::size_t i = BUILTINS.size(); i < database.units.size(); ++i) {
            const auto& unit = database.units[i];
            rows.push_back("DEF " + unit.symbol + " = " + unit.definition->value.str() + " " + unit.definition->expression +
                " factor=" + unit.quantity.value.str() + " dim=" + unit.quantity.dimension.str());
        }
        return rows;
    }
    if (command == "CONVERT" || command == "INVERT") {
        const auto value = numberValue(words[1]);
        const auto source = unitValue(database, words[2]);
        const auto target = unitValue(database, words[4]);
        if (command == "INVERT") {
            if (source.dimension == Dimension{} || !(source.dimension + target.dimension == Dimension{})) {
                fail("NOT RECIPROCAL " + source.dimension.str() + " vs " + target.dimension.str());
            }
            if (value.n == 0) fail("DIVISION BY ZERO");
        } else source.dimension.match(target.dimension);
        auto result = value * source.value;
        if (command == "INVERT") result = Fraction(1) / result;
        return {command + " " + value.str() + " " + words[2] + " = " + (result / target.value).notation(words[4])};
    }
    if (command == "DIM" || command == "REDUCE" || command == "SIMPLIFY") {
        const auto tree = parseUnit(database, words[1]);
        const auto unit = evaluateUnit(database, tree);
        const auto result = command == "DIM" ? unit.dimension.str() + " factor=" + unit.value.str() + " kind=" + kindName(unit.dimension) :
            command == "REDUCE" ? reducedText(tree) : unit.value.notation(database.simplified(unit.dimension));
        return {command + " " + words[1] + " = " + result};
    }
    if (command == "ADD" || command == "SUB" || command == "MUL" || command == "DIV" || command == "COMPARE") {
        const auto a = numberValue(words[1]);
        const auto first = unitValue(database, words[2]);
        const auto b = numberValue(words[3]);
        const auto second = unitValue(database, words[4]);
        const bool hasTarget = words.size() == 7;
        const auto target = hasTarget ? unitValue(database, words[6]) : first;
        const auto prefix = command + " " + a.str() + " " + words[2];
        const auto suffix = b.str() + " " + words[4];
        if (command == "ADD" || command == "SUB" || command == "COMPARE") {
            first.dimension.match(second.dimension);
            if (hasTarget) first.dimension.match(target.dimension);
            const auto left = a * first.value, right = b * second.value;
            if (command == "COMPARE") {
                const auto comparison = left.compare(right);
                const std::string relation = comparison < 0 ? "<" : comparison > 0 ? ">" : "=";
                return {prefix + " " + relation + " " + suffix + " ratio=" + (right.n == 0 ? "undefined" : (left / right).str())};
            }
            const auto result = command == "ADD" ? left + right : left - right;
            return {prefix + (command == "ADD" ? " + " : " - ") + suffix + " = " +
                (result / target.value).notation(hasTarget ? words[6] : words[2])};
        }
        const bool multiply = command == "MUL";
        const auto dimension = multiply ? first.dimension + second.dimension : first.dimension - second.dimension;
        if (!multiply && b.n == 0) fail("DIVISION BY ZERO");
        if (hasTarget) dimension.match(target.dimension);
        const auto raw = multiply ? a * b : a / b;
        const auto left = a * first.value, right = b * second.value;
        const auto coherent = multiply ? left * right : left / right;
        const std::string operation = multiply ? "*" : "/";
        const auto heading = prefix + " " + operation + " " + suffix + " = ";
        if (hasTarget) return {heading + (coherent / target.value).notation(words[6])};
        const auto rightUnit = !multiply && words[4].find_first_of("*/") != std::string::npos ? "(" + words[4] + ")" : words[4];
        return {heading + raw.str() + " " + words[2] + operation + rightUnit + " = " + coherent.notation(database.simplified(dimension))};
    }
    if (command == "TEMP") {
        const auto value = numberValue(words[1]);
        for (const auto index : {2, 4}) if (words[index] != "C" && words[index] != "F" && words[index] != "K" && words[index] != "R") {
            fail("UNKNOWN SCALE " + words[index]);
        }
        const Fraction celsius(5463, 20), fahrenheit(45967, 100);
        const auto kelvin = words[2] == "C" ? value + celsius : words[2] == "F" ? (value + fahrenheit) * Fraction(5, 9) :
            words[2] == "R" ? value * Fraction(5, 9) : value;
        if (kelvin.n < 0) fail("BELOW ABSOLUTE ZERO");
        const auto result = words[4] == "C" ? kelvin - celsius : words[4] == "F" ? kelvin * Fraction(9, 5) - fahrenheit :
            words[4] == "R" ? kelvin * Fraction(9, 5) : kelvin;
        return {"TEMP " + value.str() + " " + words[2] + " = " + result.notation(words[4])};
    }
    if (command == "LIST") {
        const auto known = kindDimension(words[1]);
        const auto dimension = known ? *known : unitValue(database, words[1]).dimension;
        const auto units = database.selected(dimension);
        std::vector<std::string> rows{"LIST " + words[1] + " dim=" + dimension.str() + " kind=" + kindName(dimension) + " count=" + std::to_string(units.size())};
        for (const auto& unit : units) rows.push_back("UNIT " + unit.symbol + " factor=" + unit.quantity.value.str() +
            " origin=" + (unit.definition ? "user" : "builtin") + " prefix=" + (unit.prefixable ? "yes" : "no"));
        return rows;
    }
    if (command == "TABLE") {
        const auto value = numberValue(words[1]);
        const auto unit = unitValue(database, words[2]);
        const auto selected = database.selected(unit.dimension);
        std::vector<std::string> rows{"TABLE " + value.str() + " " + words[2] + " dim=" + unit.dimension.str() + " count=" + std::to_string(selected.size())};
        for (const auto& item : selected) rows.push_back("ROW " + (value * unit.value / item.quantity.value).notation(item.symbol));
        return rows;
    }
    if (command == "AUTO") {
        const auto value = numberValue(words[1]);
        const auto unit = unitValue(database, words[2]);
        std::size_t index = 0;
        while (index < BUILTINS.size() && !(database.units[index].prefixable && database.units[index].quantity.dimension == unit.dimension)) ++index;
        if (index == BUILTINS.size()) fail("NO PREFIXABLE UNIT " + unit.dimension.str());
        const auto& reference = database.units[index];
        const auto scaled = value * unit.value / reference.quantity.value;
        const auto magnitude = scaled.absolute();
        Integer exponent = 0;
        if (magnitude.compare(1) >= 0) {
            while (exponent < 9 && magnitude.compare(Fraction(10).power(exponent + 3)) >= 0) exponent += 3;
        } else if (magnitude.n > 0) {
            while (exponent > -9 && magnitude.compare(Fraction(10).power(exponent)) < 0) exponent -= 3;
        }
        const std::array<std::string, 7> prefixes{"n", "u", "m", "", "k", "M", "G"};
        return {"AUTO " + value.str() + " " + words[2] + " = " + (scaled / Fraction(10).power(exponent)).notation(prefixes[(exponent + 9) / 3] + reference.symbol)};
    }
    if (command == "SPLIT") {
        const auto value = numberValue(words[1]);
        const auto unit = unitValue(database, words[2]);
        const auto parts = split(words[4], ',');
        std::vector<Quantity> targets;
        for (const auto& part : parts) targets.push_back(unitValue(database, part));
        if (value.n < 0) fail("NEGATIVE VALUE");
        for (const auto& target : targets) unit.dimension.match(target.dimension);
        for (std::size_t i = 0; i + 1 < targets.size(); ++i) if (targets[i].value.compare(targets[i + 1].value) <= 0) fail("UNIT ORDER");
        auto remaining = value * unit.value;
        std::vector<std::string> pieces;
        for (std::size_t i = 0; i + 1 < targets.size(); ++i) {
            const auto quotient = remaining / targets[i].value;
            const auto whole = quotient.n / quotient.d;
            remaining = remaining - Fraction(whole) * targets[i].value;
            pieces.push_back(std::to_string(whole) + " " + parts[i]);
        }
        pieces.push_back((remaining / targets.back().value).notation(parts.back()));
        return {"SPLIT " + value.str() + " " + words[2] + " = " + join(pieces)};
    }
    if (command == "LET") {
        checkName(words[1], true);
        const auto value = quantityValue(database, words[3]);
        database.variables[words[1]] = value;
        return {"LET " + words[1] + " = " + value.value.notation(database.simplified(value.dimension))};
    }
    if (command == "EVAL") {
        const auto value = quantityValue(database, words[1]);
        auto result = value.value;
        auto label = database.simplified(value.dimension);
        if (words.size() == 4) {
            const auto target = unitValue(database, words[3]);
            value.dimension.match(target.dimension);
            result = result / target.value;
            label = words[3];
        }
        return {"EVAL " + words[1] + " = " + result.notation(label)};
    }
    if (command == "VARS") {
        std::vector<std::string> rows{"VARS count=" + std::to_string(database.variables.size())};
        for (const auto& [name, value] : database.variables) rows.push_back("VAR " + name + " = " + value.value.notation(database.simplified(value.dimension)));
        return rows;
    }
    fail("UNKNOWN COMMAND " + command);
}

int main() {
    std::ios::sync_with_stdio(false);
    std::cin.tie(nullptr);
    std::string line;
    std::getline(std::cin, line);
    const int count = std::stoi(line);
    Database database;
    for (int i = 0; i < count; ++i) {
        std::getline(std::cin, line);
        if (!line.empty() && line.back() == '\r') line.pop_back();
        try {
            for (const auto& row : execute(database, line)) std::cout << row << '\n';
        } catch (const CommandError& error) {
            std::cout << "ERROR " << error.what() << '\n';
        }
    }
}
