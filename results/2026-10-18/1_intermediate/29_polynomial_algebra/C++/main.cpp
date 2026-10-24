#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <functional>
#include <iostream>
#include <map>
#include <memory>
#include <numeric>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <tuple>
#include <utility>
#include <vector>

struct CalculatorError : std::runtime_error { using std::runtime_error::runtime_error; };
[[noreturn]] void fail(const std::string& message) { throw CalculatorError(message); }

struct Fraction {
    std::int64_t n, d;
    Fraction(std::int64_t numerator = 0, std::int64_t denominator = 1) {
        if (denominator < 0) { numerator = -numerator; denominator = -denominator; }
        const auto divisor = std::gcd(numerator, denominator);
        n = numerator / divisor;
        d = denominator / divisor;
    }
    static Fraction parse(const std::string& word) {
        const auto slash = word.find('/');
        const auto denominator = slash == std::string::npos ? 1 : std::stoll(word.substr(slash + 1));
        if (denominator == 0) fail("ZERO DENOMINATOR");
        return {std::stoll(word.substr(0, slash)), denominator};
    }
    Fraction operator+(const Fraction& b) const { return {n * b.d + b.n * d, d * b.d}; }
    Fraction operator-(const Fraction& b) const { return {n * b.d - b.n * d, d * b.d}; }
    Fraction operator*(const Fraction& b) const { return {n * b.n, d * b.d}; }
    Fraction operator/(const Fraction& b) const { return {n * b.d, d * b.n}; }
    Fraction operator-() const { return {-n, d}; }
    Fraction absolute() const { return n < 0 ? -*this : *this; }
    int compare(const Fraction& b) const {
        const auto left = n * b.d, right = b.n * d;
        return (left > right) - (left < right);
    }
    bool operator<(const Fraction& b) const { return compare(b) < 0; }
    bool operator==(const Fraction& b) const { return compare(b) == 0; }
    Fraction power(int exponent) const {
        Fraction result(1);
        for (int i = 0; i < exponent; ++i) result = result * *this;
        return result;
    }
    std::string notation() const {
        return std::to_string(n) + (d == 1 ? "" : "/" + std::to_string(d));
    }
};

struct Polynomial {
    std::vector<Fraction> coefficients;
    Polynomial(std::vector<Fraction> values = {}) : coefficients(std::move(values)) {
        while (!coefficients.empty() && coefficients.back().n == 0) coefficients.pop_back();
    }
    static Polynomial constant(Fraction value) { return Polynomial({value}); }
    int degree() const { return static_cast<int>(coefficients.size()) - 1; }
    bool zero() const { return coefficients.empty(); }
    Fraction leading() const { return coefficients.back(); }
    Fraction coefficient(int index) const { return index < 0 || index > degree() ? Fraction() : coefficients[index]; }
    Polynomial operator+(const Polynomial& b) const {
        std::vector<Fraction> result(std::max(degree(), b.degree()) + 1);
        for (int i = 0; i < static_cast<int>(result.size()); ++i) result[i] = coefficient(i) + b.coefficient(i);
        return Polynomial(std::move(result));
    }
    Polynomial operator-(const Polynomial& b) const {
        std::vector<Fraction> result(std::max(degree(), b.degree()) + 1);
        for (int i = 0; i < static_cast<int>(result.size()); ++i) result[i] = coefficient(i) - b.coefficient(i);
        return Polynomial(std::move(result));
    }
    Polynomial operator-() const {
        auto result = coefficients;
        for (auto& value : result) value = -value;
        return Polynomial(std::move(result));
    }
    Polynomial scale(Fraction scalar) const {
        auto result = coefficients;
        for (auto& value : result) value = value * scalar;
        return Polynomial(std::move(result));
    }
    Polynomial divideScalar(Fraction scalar) const {
        auto result = coefficients;
        for (auto& value : result) value = value / scalar;
        return Polynomial(std::move(result));
    }
    Polynomial operator*(const Polynomial& b) const {
        if (zero() || b.zero()) return {};
        std::vector<Fraction> result(degree() + b.degree() + 1);
        for (int i = 0; i <= degree(); ++i) {
            for (int j = 0; j <= b.degree(); ++j) result[i + j] = result[i + j] + coefficients[i] * b.coefficients[j];
        }
        return Polynomial(std::move(result));
    }
    Polynomial power(int exponent) const {
        if (exponent == 0) return constant(1);
        if (zero()) return *this;
        if (degree() == 0 && leading().d == 1 && std::abs(leading().n) == 1) {
            return constant(leading().n < 0 && exponent % 2 ? -1 : 1);
        }
        Polynomial result = constant(1);
        for (int i = 0; i < exponent; ++i) result = result * *this;
        return result;
    }
    std::pair<Polynomial, Polynomial> divide(const Polynomial& b) const {
        auto remainder = coefficients;
        std::vector<Fraction> quotient(std::max(0, degree() - b.degree() + 1));
        while (!remainder.empty() && remainder.size() >= b.coefficients.size()) {
            const Fraction value = remainder.back() / b.leading();
            const int shift = static_cast<int>(remainder.size() - b.coefficients.size());
            quotient[shift] = value;
            for (int j = 0; j <= b.degree(); ++j) remainder[shift + j] = remainder[shift + j] - value * b.coefficients[j];
            while (!remainder.empty() && remainder.back().n == 0) remainder.pop_back();
        }
        return {Polynomial(std::move(quotient)), Polynomial(std::move(remainder))};
    }
    Polynomial mod(const Polynomial& b) const { return divide(b).second; }
    Polynomial monic() const { return zero() ? *this : divideScalar(leading()); }
    Polynomial derivative(int count = 1) const {
        Polynomial result = *this;
        for (int repetition = 0; repetition < count && !result.zero(); ++repetition) {
            std::vector<Fraction> next(result.degree());
            for (int i = 1; i <= result.degree(); ++i) next[i - 1] = Fraction(i) * result.coefficients[i];
            result = Polynomial(std::move(next));
        }
        return result;
    }
    Polynomial integral() const {
        std::vector<Fraction> result(coefficients.size() + 1);
        for (int i = 0; i <= degree(); ++i) result[i + 1] = coefficients[i] / Fraction(i + 1);
        return Polynomial(std::move(result));
    }
    Fraction evaluate(Fraction value) const {
        Fraction result;
        for (int i = degree(); i >= 0; --i) result = result * value + coefficients[i];
        return result;
    }
    Polynomial compose(const Polynomial& b) const {
        Polynomial result;
        for (int i = degree(); i >= 0; --i) result = result * b + constant(coefficients[i]);
        return result;
    }
    Fraction content() const {
        std::int64_t multiple = 1, divisor = 0;
        for (const auto& value : coefficients) {
            multiple = multiple * value.d / std::gcd(multiple, value.d);
            divisor = std::gcd(divisor, value.n);
        }
        return {leading().n < 0 ? -divisor : divisor, multiple};
    }
    Polynomial primitive() const { return divideScalar(content()); }
    std::string notation(const std::string& variable = "x") const {
        std::string result;
        for (int i = degree(); i >= 0; --i) {
            const Fraction value = coefficients[i];
            if (value.n == 0) continue;
            result += result.empty() ? (value.n < 0 ? "-" : "") : (value.n < 0 ? " - " : " + ");
            if (i == 0 || !(value.absolute() == Fraction(1))) result += value.absolute().notation();
            if (i > 0) result += variable + (i == 1 ? "" : "^" + std::to_string(i));
        }
        return result.empty() ? "0" : result;
    }
};

const Polynomial unit = Polynomial::constant(1);
const Polynomial variable({Fraction(), Fraction(1)});
Polynomial linear(Fraction constant, Fraction slope = 1) { return Polynomial({constant, slope}); }
void degreeLimit(bool condition) { if (condition) fail("DEGREE LIMIT"); }
void productLimit(const Polynomial& a, const Polynomial& b) {
    degreeLimit(!a.zero() && !b.zero() && a.degree() + b.degree() > 30);
}
void compositionLimit(const Polynomial& a, const Polynomial& b) {
    degreeLimit(a.degree() >= 1 && b.degree() >= 1 && a.degree() * b.degree() > 30);
}
void requireNonzero(const Polynomial& a) { if (a.zero()) fail("ZERO POLYNOMIAL"); }
bool isOne(const Polynomial& a) { return a.degree() == 0 && a.leading() == Fraction(1); }

Polynomial polynomialGcd(Polynomial a, Polynomial b) {
    while (!b.zero()) {
        Polynomial remainder = a.mod(b);
        a = std::move(b);
        b = std::move(remainder);
    }
    return a.monic();
}

std::tuple<Polynomial, Polynomial, Polynomial> extendedGcd(Polynomial a, Polynomial b) {
    Polynomial s0 = unit, s1, t0, t1 = unit;
    while (!b.zero()) {
        auto [quotient, remainder] = a.divide(b);
        a = std::move(b);
        b = std::move(remainder);
        Polynomial nextS = s0 - quotient * s1;
        s0 = std::move(s1);
        s1 = std::move(nextS);
        Polynomial nextT = t0 - quotient * t1;
        t0 = std::move(t1);
        t1 = std::move(nextT);
    }
    if (a.zero()) return {a, s0, t0};
    return {a.monic(), s0.divideScalar(a.leading()), t0.divideScalar(a.leading())};
}

std::vector<std::int64_t> divisors(std::int64_t number) {
    std::vector<std::int64_t> result;
    for (std::int64_t divisor = 1; divisor * divisor <= number; ++divisor) {
        if (number % divisor != 0) continue;
        result.push_back(divisor);
        if (divisor * divisor != number) result.push_back(number / divisor);
    }
    return result;
}

struct Root { Fraction value; int multiplicity; };
struct RootFactorization { std::vector<Root> roots; Polynomial remaining; };

RootFactorization rationalRoots(const Polynomial& a) {
    Polynomial remaining = a.primitive();
    int zeros = 0;
    while (remaining.coefficient(0).n == 0) {
        remaining = Polynomial(std::vector<Fraction>(remaining.coefficients.begin() + 1, remaining.coefficients.end()));
        ++zeros;
    }
    std::vector<Fraction> candidates;
    const auto numerators = divisors(std::abs(remaining.coefficient(0).n));
    const auto denominators = divisors(remaining.leading().n);
    for (auto numerator : numerators) {
        for (auto denominator : denominators) {
            if (std::gcd(numerator, denominator) == 1) {
                candidates.emplace_back(numerator, denominator);
                candidates.emplace_back(-numerator, denominator);
            }
        }
    }
    std::sort(candidates.begin(), candidates.end());
    std::vector<Root> roots;
    for (const auto& root : candidates) {
        int multiplicity = 0;
        const Polynomial factor = linear(-root.n, root.d);
        while (remaining.degree() >= 1 && remaining.evaluate(root).n == 0) {
            remaining = remaining.divide(factor).first;
            ++multiplicity;
        }
        if (multiplicity > 0) roots.push_back({root, multiplicity});
    }
    if (zeros > 0) roots.push_back({Fraction(), zeros});
    std::sort(roots.begin(), roots.end(), [](const Root& a, const Root& b) { return a.value < b.value; });
    return {std::move(roots), std::move(remaining)};
}

Polynomial squareFreePart(const Polynomial& a) {
    return a.degree() < 1 ? a : a.divide(polynomialGcd(a, a.derivative())).first;
}

std::vector<Polynomial> sturmSequence(const Polynomial& a) {
    Polynomial previous = squareFreePart(a), current = previous.derivative();
    std::vector<Polynomial> sequence{previous};
    while (!current.zero()) {
        sequence.push_back(current);
        Polynomial next = -previous.mod(current);
        previous = std::move(current);
        current = std::move(next);
    }
    return sequence;
}

enum class EndpointKind { NegativeInfinity, Finite, PositiveInfinity };
struct Endpoint {
    EndpointKind kind;
    Fraction value;
    Endpoint(Fraction value = 0) : kind(EndpointKind::Finite), value(value) {}
    Endpoint(EndpointKind kind) : kind(kind) {}
    static Endpoint parse(const std::string& word) {
        if (word == "-inf") return EndpointKind::NegativeInfinity;
        if (word == "inf") return EndpointKind::PositiveInfinity;
        return Fraction::parse(word);
    }
    int compare(const Endpoint& other) const {
        if (kind != other.kind) return kind < other.kind ? -1 : 1;
        return kind == EndpointKind::Finite ? value.compare(other.value) : 0;
    }
    std::string notation() const {
        return kind == EndpointKind::NegativeInfinity ? "-inf" : kind == EndpointKind::PositiveInfinity ? "inf" : value.notation();
    }
};

int signChanges(const std::vector<int>& signs) {
    int previous = 0, changes = 0;
    for (int sign : signs) {
        if (sign == 0) continue;
        if (previous != 0 && previous != sign) ++changes;
        previous = sign;
    }
    return changes;
}

int variations(const std::vector<Polynomial>& sequence, const Endpoint& endpoint) {
    std::vector<int> signs;
    for (const auto& polynomial : sequence) {
        int sign;
        if (endpoint.kind == EndpointKind::Finite) sign = polynomial.evaluate(endpoint.value).compare(0);
        else {
            sign = polynomial.leading().compare(0);
            if (endpoint.kind == EndpointKind::NegativeInfinity && polynomial.degree() % 2) sign = -sign;
        }
        signs.push_back(sign);
    }
    return signChanges(signs);
}

std::vector<std::pair<Fraction, Fraction>> isolate(const Polynomial& a, int precision) {
    const auto sequence = sturmSequence(a);
    const Polynomial& first = sequence.front();
    Fraction maximum;
    for (int i = 0; i < first.degree(); ++i) maximum = std::max(maximum, (first.coefficients[i] / first.leading()).absolute());
    const Fraction bound = Fraction(1) + maximum, width(1, std::int64_t(1) << precision);
    std::vector<std::pair<Fraction, Fraction>> intervals;
    const auto count = [&](Fraction left, Fraction right) { return variations(sequence, left) - variations(sequence, right); };
    std::function<void(Fraction, Fraction)> examine = [&](Fraction left, Fraction right) {
        const int roots = count(left, right);
        if (roots >= 2) {
            const Fraction middle = (left + right) / Fraction(2);
            examine(left, middle);
            examine(middle, right);
        } else if (roots == 1) {
            while (width < right - left) {
                const Fraction middle = (left + right) / Fraction(2);
                if (count(left, middle) >= 1) right = middle;
                else left = middle;
            }
            intervals.emplace_back(left, right);
        }
    };
    examine(-bound, bound);
    return intervals;
}

Fraction resultant(Polynomial a, Polynomial b) {
    Fraction result(1);
    while (b.degree() >= 1) {
        Polynomial remainder = a.mod(b);
        if (remainder.zero()) return 0;
        result = result * b.leading().power(a.degree() - remainder.degree());
        if (a.degree() * b.degree() % 2) result = -result;
        a = std::move(b);
        b = std::move(remainder);
    }
    return result * b.coefficient(0).power(a.degree());
}

Polynomial interpolate(const std::vector<Endpoint>& values) {
    std::vector<Fraction> xs, differences;
    for (std::size_t i = 0; i < values.size(); i += 2) {
        xs.push_back(values[i].value);
        differences.push_back(values[i + 1].value);
    }
    const int count = static_cast<int>(xs.size());
    for (int j = 1; j < count; ++j) {
        for (int i = 0; i < j; ++i) if (xs[j] == xs[i]) fail("DUPLICATE X " + xs[j].notation());
    }
    for (int j = 1; j < count; ++j) {
        for (int i = count - 1; i >= j; --i) differences[i] = (differences[i] - differences[i - 1]) / (xs[i] - xs[i - j]);
    }
    Polynomial result;
    for (int i = count - 1; i >= 0; --i) result = result * linear(-xs[i]) + Polynomial::constant(differences[i]);
    return result;
}

Polynomial special(const std::string& kind, int order) {
    const std::set<std::string> kinds{"chebyshev", "chebyshev2", "legendre", "hermite", "laguerre"};
    if (!kinds.count(kind)) fail("UNKNOWN KIND " + kind);
    degreeLimit(order > 30);
    if (order == 0) return unit;
    Polynomial previous = unit;
    Polynomial current = kind == "laguerre" ? linear(1, -1)
        : kind == "chebyshev2" || kind == "hermite" ? variable.scale(2) : variable;
    for (int j = 1; j < order; ++j) {
        Polynomial next;
        if (kind == "chebyshev" || kind == "chebyshev2") next = variable.scale(2) * current - previous;
        else if (kind == "hermite") next = variable.scale(2) * current - previous.scale(2 * j);
        else {
            const Polynomial multiplier = kind == "legendre" ? variable.scale(2 * j + 1) : linear(2 * j + 1, -1);
            next = (multiplier * current - previous.scale(j)).scale(Fraction(1, j + 1));
        }
        previous = std::move(current);
        current = std::move(next);
    }
    return current;
}

enum class NodeKind { Number, Variable, Name, Negate, Add, Subtract, Multiply, Divide, Power, Call };
struct Node {
    NodeKind kind;
    Fraction value;
    std::string name;
    int amount = 0;
    std::unique_ptr<Node> left, right;
    explicit Node(NodeKind kind) : kind(kind) {}
};
using Expression = std::unique_ptr<Node>;
struct Token { char kind; std::string word; int position; };

class ExpressionParser {
    std::vector<Token> tokens;
    std::size_t position = 0;
    const Token& token() const { return tokens[position]; }
    bool take(char kind) {
        if (token().kind != kind) return false;
        ++position;
        return true;
    }
    [[noreturn]] void syntaxError() const {
        fail("SYNTAX AT " + (token().kind == '\0' ? std::string("END") : std::to_string(token().position)));
    }
    void expect(char kind) { if (!take(kind)) syntaxError(); }
    Expression binary(NodeKind kind, Expression left, Expression right) {
        auto result = std::make_unique<Node>(kind);
        result->left = std::move(left);
        result->right = std::move(right);
        return result;
    }
    Expression expression() {
        const bool negative = take('-');
        Expression result = term();
        if (negative) {
            auto negation = std::make_unique<Node>(NodeKind::Negate);
            negation->left = std::move(result);
            result = std::move(negation);
        }
        while (token().kind == '+' || token().kind == '-') {
            const NodeKind kind = token().kind == '+' ? NodeKind::Add : NodeKind::Subtract;
            ++position;
            Expression right = term();
            result = binary(kind, std::move(result), std::move(right));
        }
        return result;
    }
    Expression term() {
        Expression result = factor();
        while (token().kind == '*' || token().kind == '/' || token().kind == 'x' || token().kind == 'N' || token().kind == '(') {
            NodeKind kind = NodeKind::Multiply;
            if (token().kind == '*' || token().kind == '/') {
                if (token().kind == '/') kind = NodeKind::Divide;
                ++position;
            }
            Expression right = factor();
            result = binary(kind, std::move(result), std::move(right));
        }
        return result;
    }
    Expression factor() {
        Expression result = primary();
        if (take('^')) {
            if (token().kind != '0') syntaxError();
            auto power = std::make_unique<Node>(NodeKind::Power);
            power->amount = std::stoi(token().word);
            ++position;
            power->left = std::move(result);
            result = std::move(power);
        }
        return result;
    }
    Expression primary() {
        const Token current = token();
        if (take('0')) {
            auto result = std::make_unique<Node>(NodeKind::Number);
            result->value = Fraction(std::stoll(current.word));
            return result;
        }
        if (take('x')) return std::make_unique<Node>(NodeKind::Variable);
        if (take('N')) {
            auto reference = std::make_unique<Node>(NodeKind::Name);
            reference->name = current.word;
            while (take('\'')) ++reference->amount;
            if (!take('(')) return reference;
            Expression argument = expression();
            expect(')');
            return binary(NodeKind::Call, std::move(reference), std::move(argument));
        }
        if (take('(')) {
            Expression result = expression();
            expect(')');
            return result;
        }
        syntaxError();
    }
public:
    explicit ExpressionParser(const std::string& source) {
        const auto digit = [](char ch) { return '0' <= ch && ch <= '9'; };
        const auto uppercase = [](char ch) { return 'A' <= ch && ch <= 'Z'; };
        for (std::size_t i = 0; i < source.size();) {
            if (source[i] == ' ') { ++i; continue; }
            const std::size_t start = i++;
            char kind = source[start];
            if (digit(kind)) {
                kind = '0';
                while (i < source.size() && digit(source[i])) ++i;
            } else if (uppercase(kind)) {
                kind = 'N';
                while (i < source.size() && (uppercase(source[i]) || digit(source[i]))) ++i;
            }
            tokens.push_back({kind, source.substr(start, i - start), static_cast<int>(start + 1)});
        }
        tokens.push_back({'\0', "", static_cast<int>(source.size() + 1)});
    }
    Expression parse() {
        Expression result = expression();
        if (token().kind != '\0') syntaxError();
        return result;
    }
};

const std::map<std::string, std::vector<int>> references{
    {"PRINT", {1}}, {"DELETE", {1}}, {"DEGREE", {1}}, {"ADD", {2, 3}}, {"SUB", {2, 3}}, {"MUL", {2, 3}},
    {"POW", {2}}, {"DIV", {3, 4}}, {"GCD", {2, 3}}, {"XGCD", {4, 5}}, {"LCM", {2, 3}}, {"INVMOD", {2, 3}},
    {"CRT", {2, 3, 4, 5}}, {"MODPOW", {2, 4}}, {"DERIV", {2}}, {"INTEG", {2}}, {"AREA", {1}},
    {"TANGENT", {2}}, {"TAYLOR", {1}}, {"COMPOSE", {2, 3}}, {"EVAL", {1}}, {"ROOTS", {1}}, {"FACTOR", {1}},
    {"SQFREE", {1}}, {"DESCARTES", {1}}, {"STURM", {1}}, {"ISOLATE", {1}}, {"RESULTANT", {1, 2}},
    {"DISCRIM", {1}}, {"POWERSUM", {1}}
};

std::string join(const std::vector<std::string>& values, const std::string& separator) {
    std::string result;
    for (const auto& value : values) {
        if (!result.empty()) result += separator;
        result += value;
    }
    return result;
}

class Calculator {
    std::map<std::string, Polynomial> polynomials;
    const Polynomial& lookup(const std::string& name) const {
        const auto found = polynomials.find(name);
        if (found == polynomials.end()) fail("UNKNOWN " + name);
        return found->second;
    }
    Polynomial evaluate(const Node& node) const {
        switch (node.kind) {
            case NodeKind::Number: return Polynomial::constant(node.value);
            case NodeKind::Variable: return variable;
            case NodeKind::Name: return lookup(node.name).derivative(node.amount);
            case NodeKind::Negate: return -evaluate(*node.left);
            case NodeKind::Power: {
                const Polynomial value = evaluate(*node.left);
                degreeLimit(!value.zero() && value.degree() * node.amount > 30);
                return value.power(node.amount);
            }
            default: break;
        }
        const Polynomial left = evaluate(*node.left);
        const Polynomial right = evaluate(*node.right);
        if (node.kind == NodeKind::Add) return left + right;
        if (node.kind == NodeKind::Subtract) return left - right;
        if (node.kind == NodeKind::Multiply) { productLimit(left, right); return left * right; }
        if (node.kind == NodeKind::Call) { compositionLimit(left, right); return left.compose(right); }
        if (right.zero()) fail("DIVISION BY ZERO");
        if (right.degree() > 0) fail("NONCONSTANT DIVISOR");
        return left.divideScalar(right.leading());
    }
public:
    std::vector<std::string> execute(const std::string& source) {
        std::istringstream input(source);
        std::vector<std::string> words;
        for (std::string word; input >> word;) words.push_back(word);
        const std::string command = words[0], name = words.size() > 1 ? words[1] : "";
        std::vector<std::pair<std::string, Polynomial>> pending;
        std::vector<std::string> output;
        const auto store = [&](const std::string& target, const Polynomial& value) {
            pending.emplace_back(target, value);
            output.push_back(target + " = " + value.notation());
        };
        if (command == "DEF") {
            Expression syntax = ExpressionParser(source.substr(name.size() + 5)).parse();
            store(name, evaluate(*syntax));
        } else {
            if (command == "DIV" && words[1] == words[2]) fail("SAME NAME");
            if (command == "XGCD" && std::set<std::string>(words.begin() + 1, words.begin() + 4).size() < 3) fail("SAME NAME");
            std::vector<Polynomial> operands;
            const auto positions = references.find(command);
            if (positions != references.end()) for (int index : positions->second) operands.push_back(lookup(words[index]));
            const Polynomial empty;
            const Polynomial& a = operands.empty() ? empty : operands[0];
            const Polynomial& b = operands.size() < 2 ? empty : operands[1];
            std::size_t literalStart = words.size(), literalEnd = words.size();
            if (command == "AREA" || command == "STURM") { literalStart = 2; literalEnd = 4; }
            else if (command == "TANGENT") { literalStart = 3; literalEnd = 4; }
            else if (command == "TAYLOR") { literalStart = 2; literalEnd = 3; }
            else if (command == "EVAL" || command == "INTERP") literalStart = 2;
            std::vector<Endpoint> values;
            for (std::size_t i = literalStart; i < literalEnd; ++i) values.push_back(Endpoint::parse(words[i]));
            if (command == "PRINT") output.push_back(name + " = " + a.notation());
            else if (command == "DELETE") { polynomials.erase(name); output.push_back("deleted " + name); }
            else if (command == "LIST") {
                for (const auto& [key, value] : polynomials) output.push_back(key + " = " + value.notation());
                if (output.empty()) output.push_back("no polynomials");
            } else if (command == "DEGREE") output.push_back("deg(" + name + ") = " + (a.zero() ? "-inf" : std::to_string(a.degree())));
            else if (command == "ADD") store(name, a + b);
            else if (command == "SUB") store(name, a - b);
            else if (command == "MUL") { productLimit(a, b); store(name, a * b); }
            else if (command == "POW") {
                const int exponent = std::stoi(words[3]);
                degreeLimit(!a.zero() && a.degree() * exponent > 30);
                store(name, a.power(exponent));
            } else if (command == "DIV") {
                if (b.zero()) fail("DIVISION BY ZERO");
                const auto [quotient, remainder] = a.divide(b);
                store(name, quotient);
                store(words[2], remainder);
            } else if (command == "GCD") store(name, polynomialGcd(a, b));
            else if (command == "XGCD") {
                const auto [common, s, t] = extendedGcd(a, b);
                store(name, common); store(words[2], s); store(words[3], t);
            } else if (command == "LCM") {
                if (a.zero() || b.zero()) store(name, {});
                else {
                    const Polynomial common = polynomialGcd(a, b);
                    degreeLimit(a.degree() + b.degree() - common.degree() > 30);
                    store(name, (a.divide(common).first * b).monic());
                }
            } else if (command == "INVMOD") {
                if (b.zero()) fail("DIVISION BY ZERO");
                if (b.degree() == 0) fail("DEGREE TOO LOW");
                const auto [common, inverse, unused] = extendedGcd(a, b);
                if (!isOne(common)) fail("NOT COPRIME");
                store(name, inverse.mod(b));
            } else if (command == "CRT") {
                const Polynomial& c = operands[2];
                const Polynomial& d = operands[3];
                if (b.zero() || d.zero()) fail("DIVISION BY ZERO");
                degreeLimit(b.degree() + d.degree() > 30);
                const auto [common, inverse, unused] = extendedGcd(b, d);
                if (!isOne(common)) fail("NOT COPRIME");
                const Polynomial first = a.mod(b), second = c.mod(d);
                const Polynomial correction = ((second - first) * inverse).mod(d);
                store(name, first + b * correction);
            } else if (command == "MODPOW") {
                if (b.zero()) fail("DIVISION BY ZERO");
                degreeLimit(2 * b.degree() - 2 > 30);
                Polynomial result = unit.mod(b), base = a.mod(b);
                int exponent = std::stoi(words[3]);
                while (exponent > 0) {
                    if (exponent % 2) result = (result * base).mod(b);
                    exponent /= 2;
                    if (exponent > 0) base = (base * base).mod(b);
                }
                store(name, result);
            } else if (command == "DERIV") store(name, a.derivative(std::stoi(words[3])));
            else if (command == "INTEG") { degreeLimit(!a.zero() && a.degree() + 1 > 30); store(name, a.integral()); }
            else if (command == "AREA") {
                const Polynomial integral = a.integral();
                const Fraction result = integral.evaluate(values[1].value) - integral.evaluate(values[0].value);
                output.push_back("integral(" + name + ", " + values[0].notation() + ", " + values[1].notation() + ") = " + result.notation());
            } else if (command == "TANGENT") {
                const Fraction point = values[0].value, value = a.evaluate(point), slope = a.derivative().evaluate(point);
                store(name, linear(value - slope * point, slope));
            } else if (command == "TAYLOR") {
                const Fraction point = values[0].value;
                const std::string symbol = point.n == 0 ? "x" : point.n > 0 ? "(x - " + point.notation() + ")" : "(x + " + (-point).notation() + ")";
                output.push_back("taylor(" + name + ", " + point.notation() + ") = " + a.compose(linear(point)).notation(symbol));
            } else if (command == "COMPOSE") { compositionLimit(a, b); store(name, a.compose(b)); }
            else if (command == "EVAL") {
                for (const auto& point : values) output.push_back(name + "(" + point.notation() + ") = " + a.evaluate(point.value).notation());
            } else if (command == "ROOTS" || command == "FACTOR") {
                requireNonzero(a);
                const auto factorization = rationalRoots(a);
                if (command == "ROOTS") {
                    std::vector<std::string> roots;
                    for (const auto& root : factorization.roots) roots.push_back(root.value.notation() + " (" + std::to_string(root.multiplicity) + ")");
                    output.push_back("roots(" + name + ") = " + (roots.empty() ? "none" : join(roots, ", ")));
                } else {
                    std::string result = "factor(" + name + ") = " + a.content().notation();
                    for (const auto& root : factorization.roots) {
                        result += " * " + (root.value.n == 0 ? std::string("x") : "(" + linear(-root.value.n, root.value.d).notation() + ")");
                        if (root.multiplicity > 1) result += "^" + std::to_string(root.multiplicity);
                    }
                    if (factorization.remaining.degree() >= 1) result += " * (" + factorization.remaining.notation() + ")";
                    output.push_back(result);
                }
            } else if (command == "SQFREE") {
                requireNonzero(a);
                std::string result = "sqfree(" + name + ") = " + a.content().notation();
                if (a.degree() >= 1) {
                    const Polynomial monic = a.monic();
                    Polynomial common = polynomialGcd(monic, monic.derivative()), remaining = monic.divide(common).first;
                    for (int multiplicity = 1; remaining.degree() >= 1; ++multiplicity) {
                        const Polynomial shared = polynomialGcd(remaining, common), factor = remaining.divide(shared).first;
                        if (factor.degree() >= 1) {
                            const std::string notation = factor.primitive().notation();
                            result += " * " + (notation == "x" ? notation : "(" + notation + ")");
                            if (multiplicity > 1) result += "^" + std::to_string(multiplicity);
                        }
                        common = common.divide(shared).first;
                        remaining = shared;
                    }
                }
                output.push_back(result);
            } else if (command == "DESCARTES") {
                requireNonzero(a);
                std::vector<int> positive, negative;
                for (int i = a.degree(); i >= 0; --i) {
                    const int sign = a.coefficients[i].compare(0);
                    positive.push_back(sign);
                    negative.push_back(i % 2 ? -sign : sign);
                }
                output.push_back("descartes(" + name + ") = positive " + std::to_string(signChanges(positive)) + ", negative " + std::to_string(signChanges(negative)));
            } else if (command == "STURM") {
                requireNonzero(a);
                if (values[0].compare(values[1]) >= 0) fail("BAD INTERVAL");
                const auto sequence = sturmSequence(a);
                const int count = variations(sequence, values[0]) - variations(sequence, values[1]);
                output.push_back("sturm(" + name + ", " + values[0].notation() + ", " + values[1].notation() + ") = " + std::to_string(count));
            } else if (command == "ISOLATE") {
                requireNonzero(a);
                const int precision = std::stoi(words[2]);
                std::vector<std::string> intervals;
                for (const auto& [left, right] : isolate(a, precision)) intervals.push_back("(" + left.notation() + ", " + right.notation() + "]");
                output.push_back("isolate(" + name + ", " + std::to_string(precision) + ") = " + (intervals.empty() ? "none" : join(intervals, ", ")));
            } else if (command == "RESULTANT") {
                requireNonzero(a); requireNonzero(b);
                output.push_back("res(" + name + ", " + words[2] + ") = " + resultant(a, b).notation());
            } else if (command == "DISCRIM") {
                requireNonzero(a);
                if (a.degree() == 0) fail("DEGREE TOO LOW");
                Fraction discriminant = resultant(a, a.derivative()) / a.leading();
                if (a.degree() * (a.degree() - 1) / 2 % 2) discriminant = -discriminant;
                output.push_back("disc(" + name + ") = " + discriminant.notation());
            } else if (command == "POWERSUM") {
                requireNonzero(a);
                if (a.degree() == 0) fail("DEGREE TOO LOW");
                const Polynomial monic = a.monic();
                std::vector<Fraction> sums(1);
                std::vector<std::string> parts;
                const int count = std::stoi(words[2]);
                for (int j = 1; j <= count; ++j) {
                    Fraction sum = j <= a.degree() ? Fraction(j) * monic.coefficient(a.degree() - j) : Fraction();
                    for (int i = 1; i <= std::min(j - 1, a.degree()); ++i) sum = sum + monic.coefficient(a.degree() - i) * sums[j - i];
                    sums.push_back(-sum);
                    parts.push_back((-sum).notation());
                }
                output.push_back("powersum(" + name + ") = " + join(parts, ", "));
            } else if (command == "INTERP") store(name, interpolate(values));
            else if (command == "SPECIAL") store(name, special(words[2], std::stoi(words[3])));
        }
        for (auto& [target, value] : pending) polynomials[target] = std::move(value);
        return output;
    }
};

int main() {
    int count;
    std::cin >> count;
    std::string source;
    std::getline(std::cin, source);
    Calculator calculator;
    for (int i = 0; i < count; ++i) {
        std::getline(std::cin, source);
        try {
            for (const auto& line : calculator.execute(source)) std::cout << line << '\n';
        } catch (const CalculatorError& error) {
            std::cout << "ERROR " << error.what() << '\n';
        }
    }
}
