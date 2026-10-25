#include <algorithm>
#include <array>
#include <cstdint>
#include <iomanip>
#include <iostream>
#include <map>
#include <numeric>
#include <optional>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

using Integer = std::int64_t;
enum class Mode { RNE, RNA, RTZ, RUP, RDN };
enum class Operation { Add, Sub, Mul, Div, Sqrt, Fma };
enum Flag : unsigned { Invalid = 1, DivByZero = 2, Overflow = 4, Underflow = 8, Inexact = 16 };

struct Result { int pattern; unsigned flags = 0; };
struct Units { Integer integer; bool inexact; };

class CommandError : public std::runtime_error {
public:
    using std::runtime_error::runtime_error;
};

[[noreturn]] void fail(const std::string& reason) { throw CommandError(reason); }

const std::array<std::string, 5> mode_names{"RNE", "RNA", "RTZ", "RUP", "RDN"};
const std::map<std::string, std::pair<Integer, Integer>> integer_types{
    {"I8", {-128, 127}}, {"U8", {0, 255}}, {"I16", {-32768, 32767}}, {"U16", {0, 65535}},
    {"I32", {-2147483648LL, 2147483647LL}}, {"U32", {0, 4294967295LL}}
};

Mode parse_mode(const std::vector<std::string>& words, std::size_t index) {
    if (index == words.size()) return Mode::RNE;
    const auto found = std::find(mode_names.begin(), mode_names.end(), words[index]);
    if (found == mode_names.end()) fail("BAD MODE " + words[index]);
    return static_cast<Mode>(found - mode_names.begin());
}

std::string mode_text(Mode mode) { return mode_names[static_cast<std::size_t>(mode)]; }

std::string flags_text(unsigned flags) {
    static const std::array<std::string, 5> names{"invalid", "divbyzero", "overflow", "underflow", "inexact"};
    std::string result;
    for (std::size_t i = 0; i < names.size(); ++i) {
        if (!(flags & (1u << i))) continue;
        if (!result.empty()) result += ',';
        result += names[i];
    }
    return "flags=" + (result.empty() ? "none" : result);
}

std::string binary(int value, int width) {
    std::string text(width, '0');
    for (int i = 0; i < width; ++i) if (value & (1 << i)) text[width - 1 - i] = '1';
    return text;
}

int bit_length(Integer n) {
    int length = 0;
    for (; n; n >>= 1) ++length;
    return length;
}

std::pair<Integer, Integer> scaled(Integer n, Integer d, int exponent) {
    if (exponent >= 0) return {n << exponent, d};
    return {n, d << -exponent};
}

Integer integer_sqrt(Integer n) {
    if (n == 0) return 0;
    Integer root = Integer{1} << ((bit_length(n) + 1) / 2);
    for (;;) {
        const Integer next = (root + n / root) / 2;
        if (next >= root) return root;
        root = next;
    }
}

struct Exact {
    Integer n;
    int exponent;
    Integer denominator;
    bool negative;

    Exact(Integer n = 0, int exponent = 0, Integer denominator = 1, bool negative = false)
        : n(n), exponent(exponent), denominator(denominator), negative(negative) {}

    Exact negated() const { return {n, exponent, denominator, !negative}; }

    int log2_floor() const {
        int t = bit_length(n) - bit_length(denominator) + exponent;
        const auto [numerator, divisor] = scaled(n, denominator, exponent - t);
        if (numerator < divisor) --t;
        return t;
    }

    std::string fraction() const {
        if (n == 0) return "0";
        auto [numerator, divisor] = scaled(n, denominator, exponent);
        const Integer factor = std::gcd(numerator, divisor);
        numerator /= factor;
        divisor /= factor;
        return (negative ? "-" : "") + std::to_string(numerator)
            + (divisor == 1 ? "" : "/" + std::to_string(divisor));
    }

    std::string decimal(bool keep_zero_sign = false) const {
        const auto [numerator, divisor] = scaled(n, denominator, exponent);
        std::string text = std::to_string(numerator / divisor);
        Integer remainder = numerator % divisor;
        if (remainder) {
            text += '.';
            while (remainder) {
                remainder *= 10;
                text += static_cast<char>('0' + remainder / divisor);
                remainder %= divisor;
            }
        }
        if (negative && (n != 0 || keep_zero_sign)) text.insert(text.begin(), '-');
        return text;
    }
};

Exact exact_product(const Exact& a, const Exact& b) {
    return {a.n * b.n, a.exponent + b.exponent, a.denominator * b.denominator, a.negative != b.negative};
}

Exact exact_sum(const std::vector<Exact>& terms, Mode mode) {
    std::optional<int> exponent;
    for (const Exact& term : terms) {
        if (term.n != 0 && (!exponent || term.exponent < *exponent)) exponent = term.exponent;
    }
    if (!exponent) {
        const bool same_sign = std::all_of(terms.begin(), terms.end(), [&](const Exact& term) {
            return term.negative == terms.front().negative;
        });
        return {0, 0, 1, same_sign ? terms.front().negative : mode == Mode::RDN};
    }
    Integer numerator = 0;
    for (const Exact& term : terms) {
        if (!term.n) continue;
        const Integer aligned = term.n << (term.exponent - *exponent);
        numerator += term.negative ? -aligned : aligned;
    }
    const bool negative = numerator < 0 || (numerator == 0 && mode == Mode::RDN);
    return {numerator < 0 ? -numerator : numerator, *exponent, 1, negative};
}

bool increment(Mode mode, bool negative, Integer integer, bool inexact, Integer halfway) {
    if (!inexact) return false;
    switch (mode) {
        case Mode::RNE: return halfway > 0 || (halfway == 0 && integer % 2 != 0);
        case Mode::RNA: return halfway >= 0;
        case Mode::RTZ: return false;
        case Mode::RUP: return !negative;
        case Mode::RDN: return negative;
    }
    return false;
}

Units rounded_units(const Exact& value, int exponent, Mode mode) {
    const auto [n, d] = scaled(value.n, value.denominator, value.exponent - exponent);
    Integer integer = n / d;
    const Integer remainder = n % d;
    if (increment(mode, value.negative, integer, remainder != 0, 2 * remainder - d)) ++integer;
    return {integer, remainder != 0};
}

Units rounded_sqrt_units(const Exact& value, int exponent, Mode mode) {
    const auto [n, d] = scaled(value.n, value.denominator, value.exponent - 2 * exponent);
    Integer integer = integer_sqrt(n / d);
    const bool inexact = integer * integer * d != n;
    const Integer midpoint = 2 * integer + 1;
    if (increment(mode, false, integer, inexact, 4 * n - d * midpoint * midpoint)) ++integer;
    return {integer, inexact};
}

struct Fields { bool negative; int exponent, fraction, q; };

class Format {
    template<class UnitsAt>
    Result round_nonzero(bool negative, int t, Mode mode, UnitsAt units_at) const {
        if (t > emax) return overflow(negative, mode);
        int exponent = std::max(t, emin) - m;
        const Units units = units_at(exponent);
        Integer n = units.integer;
        if (n == 2 * hidden) {
            n = hidden;
            ++exponent;
        }
        if (exponent > emax - m) return overflow(negative, mode);
        const int magnitude = n >= hidden
            ? (exponent + m + bias) * hidden + static_cast<int>(n - hidden) : static_cast<int>(n);
        unsigned flags = units.inexact ? Inexact : 0;
        if (units.inexact && t < emin && (t < emin - 1 || units_at(t - m).integer < 2 * hidden)) flags |= Underflow;
        return {zero(negative) + magnitude, flags};
    }

public:
    std::string name;
    int e, m, w, bias, emin, emax, hidden, exponent_mask, sign_bit, infinity, nan, maximum;

    Format(std::string name, int e, int m)
        : name(std::move(name)), e(e), m(m), w(1 + e + m), bias((1 << (e - 1)) - 1),
          emin(1 - bias), emax(bias), hidden(1 << m), exponent_mask((1 << e) - 1),
          sign_bit(1 << (e + m)), infinity(exponent_mask * hidden), nan(infinity + hidden / 2), maximum(infinity - 1) {}

    Fields fields(int pattern) const {
        const bool negative = (pattern & sign_bit) != 0;
        const int exponent = (pattern >> m) & exponent_mask;
        const int fraction = pattern & (hidden - 1);
        return {negative, exponent, fraction, (exponent == 0 ? emin : exponent - bias) - m};
    }

    bool is_nan(int pattern) const {
        const Fields f = fields(pattern);
        return f.exponent == exponent_mask && f.fraction != 0;
    }
    bool is_signaling(int pattern) const { return is_nan(pattern) && fields(pattern).fraction < hidden / 2; }
    bool is_infinity(int pattern) const { return (pattern & (sign_bit - 1)) == infinity; }
    bool is_zero(int pattern) const { return (pattern & (sign_bit - 1)) == 0; }
    bool is_finite(int pattern) const { return fields(pattern).exponent != exponent_mask; }
    int zero(bool negative) const { return negative ? sign_bit : 0; }
    int inf(bool negative) const { return zero(negative) + infinity; }
    int flip(int pattern) const { return pattern ^ sign_bit; }

    Exact exact(int pattern) const {
        const Fields f = fields(pattern);
        return {f.exponent == 0 ? f.fraction : hidden + f.fraction, f.q, 1, f.negative};
    }

    std::string bits(int pattern) const {
        const Fields f = fields(pattern);
        return std::string(f.negative ? "1|" : "0|") + binary(f.exponent, e) + '|' + binary(f.fraction, m);
    }

    std::string hex(int pattern) const {
        std::ostringstream out;
        out << "0x" << std::uppercase << std::hex << std::setw((w + 3) / 4) << std::setfill('0') << pattern;
        return out.str();
    }

    std::string value(int pattern) const {
        if (is_nan(pattern)) return "nan";
        if (is_infinity(pattern)) return fields(pattern).negative ? "-inf" : "inf";
        return exact(pattern).decimal(true);
    }

    std::string pattern_text(int pattern) const { return bits(pattern) + ' ' + hex(pattern) + ' ' + value(pattern); }
    std::string result_text(Result result) const { return pattern_text(result.pattern) + ' ' + flags_text(result.flags); }

    Result overflow(bool negative, Mode mode) const {
        const bool to_infinity = mode == Mode::RNE || mode == Mode::RNA
            || (mode == Mode::RUP && !negative) || (mode == Mode::RDN && negative);
        return {zero(negative) + (to_infinity ? infinity : maximum), Overflow | Inexact};
    }

    Result round(const Exact& value, Mode mode) const {
        if (value.n == 0) return {zero(value.negative)};
        return round_nonzero(value.negative, value.log2_floor(), mode,
                             [&](int exponent) { return rounded_units(value, exponent, mode); });
    }

    Result sqrt(const Exact& value, Mode mode) const {
        const int log = value.log2_floor();
        const int t = log >= 0 ? log / 2 : -((-log + 1) / 2);
        return round_nonzero(false, t, mode, [&](int exponent) { return rounded_sqrt_units(value, exponent, mode); });
    }
};

enum class RealKind { Finite, Infinity, NaN };
struct RealInput { RealKind kind; Exact exact; };

Integer decimal_integer(const std::string& text) {
    Integer value = 0;
    for (char digit : text) value = value * 10 + digit - '0';
    return value;
}

RealInput parse_real(const std::string& word) {
    if (word == "nan") return {RealKind::NaN, {}};
    if (word == "inf" || word == "-inf") return {RealKind::Infinity, {0, 0, 1, word == "-inf"}};
    if (word.compare(0, 2, "0b") == 0 || word.compare(0, 2, "0x") == 0) fail("BAD OPERAND " + word);
    const bool negative = word.front() == '-';
    std::string body = negative ? word.substr(1) : word;
    const auto slash = body.find('/');
    if (slash != std::string::npos) {
        const Integer n = decimal_integer(body.substr(0, slash));
        const Integer d = decimal_integer(body.substr(slash + 1));
        if (d == 0) fail("BAD OPERAND " + word);
        return {RealKind::Finite, {n, 0, d, negative}};
    }
    Integer denominator = 1;
    const auto dot = body.find('.');
    if (dot != std::string::npos) {
        for (std::size_t i = dot + 1; i < body.size(); ++i) denominator *= 10;
        body.erase(dot, 1);
    }
    return {RealKind::Finite, {decimal_integer(body), 0, denominator, negative}};
}

Result encoded(const Format& format, const RealInput& input, Mode mode) {
    if (input.kind == RealKind::NaN) return {format.nan};
    if (input.kind == RealKind::Infinity) return {format.inf(input.exact.negative)};
    return format.round(input.exact, mode);
}

int operand(const Format& format, const std::string& word) {
    const bool bits = word.compare(0, 2, "0b") == 0;
    const bool hex = word.compare(0, 2, "0x") == 0;
    if (bits || hex) {
        const auto width = static_cast<std::size_t>(bits ? format.w : (format.w + 3) / 4);
        if (word.size() - 2 != width) fail("BAD OPERAND " + word);
        int pattern = 0;
        for (std::size_t i = 2; i < word.size(); ++i)
            pattern = pattern * (bits ? 2 : 16) + (word[i] <= '9' ? word[i] - '0' : word[i] - 'A' + 10);
        if (pattern >= (1 << format.w)) fail("BAD OPERAND " + word);
        return pattern;
    }
    return encoded(format, parse_real(word), Mode::RNE).pattern;
}

std::optional<Operation> parse_operation(const std::string& command) {
    if (command == "ADD") return Operation::Add;
    if (command == "SUB") return Operation::Sub;
    if (command == "MUL") return Operation::Mul;
    if (command == "DIV") return Operation::Div;
    if (command == "SQRT") return Operation::Sqrt;
    if (command == "FMA") return Operation::Fma;
    return std::nullopt;
}

Result operation(const Format& format, Operation op, std::vector<int> inputs, Mode mode) {
    if (op == Operation::Sub) {
        inputs[1] = format.flip(inputs[1]);
        op = Operation::Add;
    }
    const bool nan = std::any_of(inputs.begin(), inputs.end(), [&](int p) { return format.is_nan(p); });
    if (nan) {
        const bool signaling = std::any_of(inputs.begin(), inputs.end(), [&](int p) { return format.is_signaling(p); });
        return {format.nan, signaling ? Invalid : 0u};
    }
    const int a = inputs[0];
    const bool negative = format.fields(a).negative;
    const Result invalid{format.nan, Invalid};
    if (op == Operation::Sqrt) {
        if (format.is_zero(a)) return {a};
        if (negative) return invalid;
        if (format.is_infinity(a)) return {a};
        return format.sqrt(format.exact(a), mode);
    }
    const int b = inputs[1];
    const bool sigma = negative != format.fields(b).negative;
    if (op == Operation::Add) {
        if (format.is_infinity(a) && format.is_infinity(b) && sigma) return invalid;
        if (format.is_infinity(a)) return {a};
        if (format.is_infinity(b)) return {b};
        return format.round(exact_sum({format.exact(a), format.exact(b)}, mode), mode);
    }
    if (op == Operation::Mul) {
        if (format.is_infinity(a) || format.is_infinity(b))
            return format.is_zero(a) || format.is_zero(b) ? invalid : Result{format.inf(sigma)};
        if (format.is_zero(a) || format.is_zero(b)) return {format.zero(sigma)};
        return format.round(exact_product(format.exact(a), format.exact(b)), mode);
    }
    if (op == Operation::Div) {
        if (format.is_infinity(a)) return format.is_infinity(b) ? invalid : Result{format.inf(sigma)};
        if (format.is_infinity(b)) return {format.zero(sigma)};
        if (format.is_zero(b)) return format.is_zero(a) ? invalid : Result{format.inf(sigma), DivByZero};
        if (format.is_zero(a)) return {format.zero(sigma)};
        const Exact x = format.exact(a), y = format.exact(b);
        return format.round({x.n * y.denominator, x.exponent - y.exponent, x.denominator * y.n, sigma}, mode);
    }
    const int c = inputs[2];
    if (format.is_infinity(a) || format.is_infinity(b)) {
        if (format.is_zero(a) || format.is_zero(b) || (format.is_infinity(c) && format.fields(c).negative != sigma)) return invalid;
        return {format.inf(sigma)};
    }
    if (format.is_infinity(c)) return {c};
    return format.round(exact_sum({exact_product(format.exact(a), format.exact(b)), format.exact(c)}, mode), mode);
}

int next_up(const Format& format, int pattern) {
    if (pattern == format.infinity) return pattern;
    if (format.is_zero(pattern)) return 1;
    return pattern + (format.fields(pattern).negative ? -1 : 1);
}

std::string difference(const Format& format, int pattern, const Exact& exact) {
    if (!format.is_finite(pattern)) return format.value(pattern);
    return exact_sum({format.exact(pattern), exact.negated()}, Mode::RNE).fraction();
}

std::string relation(int a, int b) { return a < b ? "LT" : a > b ? "GT" : "EQ"; }

class Laboratory {
    std::map<std::string, Format> formats;

    const Format& format(const std::string& name) const {
        const auto found = formats.find(name);
        if (found == formats.end()) fail("UNKNOWN FORMAT " + name);
        return found->second;
    }

    static std::vector<int> operands(const Format& format, const std::vector<std::string>& words,
                                     std::size_t begin, std::size_t end) {
        std::vector<int> patterns;
        for (std::size_t i = begin; i < end; ++i) patterns.push_back(operand(format, words[i]));
        return patterns;
    }

    static bool all_finite(const Format& format, const std::vector<int>& patterns) {
        return std::all_of(patterns.begin(), patterns.end(), [&](int p) { return format.is_finite(p); });
    }

    static void summary(const Format& format, Mode mode, const std::vector<int>& patterns, Result result) {
        std::vector<Exact> terms;
        for (int pattern : patterns) terms.push_back(format.exact(pattern));
        const Exact exact = exact_sum(terms, mode);
        std::cout << "RESULT " << format.result_text(result) << '\n'
                  << "EXACT " << exact.decimal() << '\n'
                  << "ROUNDED " << format.result_text(format.round(exact, mode)) << '\n'
                  << "DIFF " << difference(format, result.pattern, exact) << '\n';
    }

    static void summation(const std::string& command, const Format& format, Mode mode, const std::vector<int>& patterns) {
        if (!all_finite(format, patterns)) fail("NOT FINITE");
        std::cout << command << ' ' << format.name << ' ' << mode_text(mode) << " count=" << patterns.size() << '\n';
        int sum = patterns[0], compensation = 0;
        unsigned flags = 0;
        for (std::size_t i = 1; i < patterns.size(); ++i) {
            if (command == "SUM") {
                const Result added = operation(format, Operation::Add, {sum, patterns[i]}, mode);
                sum = added.pattern;
                flags |= added.flags;
                std::cout << "PARTIAL " << i + 1 << ' ' << format.result_text(added) << '\n';
            } else {
                const Result y = operation(format, Operation::Sub, {patterns[i], compensation}, mode);
                const Result t = operation(format, Operation::Add, {sum, y.pattern}, mode);
                const Result d = operation(format, Operation::Sub, {t.pattern, sum}, mode);
                const Result c = operation(format, Operation::Sub, {d.pattern, y.pattern}, mode);
                sum = t.pattern;
                compensation = c.pattern;
                const unsigned step_flags = y.flags | t.flags | d.flags | c.flags;
                flags |= step_flags;
                std::cout << "KSTEP " << i + 1 << " sum=" << format.value(sum) << " comp=" << format.value(compensation)
                          << ' ' << flags_text(step_flags) << '\n';
            }
        }
        summary(format, mode, patterns, {sum, flags});
    }

    static void dot(const Format& format, Mode mode, const std::vector<int>& a, const std::vector<int>& b) {
        if (a.size() != b.size()) fail("LENGTH MISMATCH");
        if (!all_finite(format, a) || !all_finite(format, b)) fail("NOT FINITE");
        Result naive = operation(format, Operation::Mul, {a[0], b[0]}, mode);
        Result chained = naive;
        for (std::size_t i = 1; i < a.size(); ++i) {
            const Result product = operation(format, Operation::Mul, {a[i], b[i]}, mode);
            const Result added = operation(format, Operation::Add, {naive.pattern, product.pattern}, mode);
            naive = {added.pattern, naive.flags | product.flags | added.flags};
            const Result fused = operation(format, Operation::Fma, {a[i], b[i], chained.pattern}, mode);
            chained = {fused.pattern, chained.flags | fused.flags};
        }
        std::vector<Exact> terms;
        for (std::size_t i = 0; i < a.size(); ++i) terms.push_back(exact_product(format.exact(a[i]), format.exact(b[i])));
        const Exact exact = exact_sum(terms, mode);
        std::cout << "DOT " << format.name << ' ' << mode_text(mode) << " n=" << a.size() << '\n'
                  << "NAIVE " << format.result_text(naive) << '\n'
                  << "CHAINED " << format.result_text(chained) << '\n'
                  << "EXACT " << exact.decimal() << '\n'
                  << "FUSED " << format.result_text(format.round(exact, mode)) << '\n'
                  << "DIFF naive=" << difference(format, naive.pattern, exact)
                  << " chained=" << difference(format, chained.pattern, exact) << '\n';
    }

    static void table(const Format& format) {
        if (format.w > 8) fail("TABLE TOO LARGE");
        const int count = format.infinity;
        std::cout << "TABLE " << format.name << " count=" << count << '\n';
        for (int pattern = 0; pattern < count; ++pattern) {
            const std::string gap = pattern == count - 1 ? "-"
                : exact_sum({format.exact(pattern + 1), format.exact(pattern).negated()}, Mode::RNE).decimal();
            std::cout << "ENTRY " << pattern << ' ' << format.pattern_text(pattern) << " gap=" << gap << '\n';
        }
        std::cout << "MAX " << format.pattern_text(format.maximum) << '\n'
                  << "MINNORMAL " << format.pattern_text(format.hidden) << '\n'
                  << "MINSUBNORMAL " << format.pattern_text(1) << '\n'
                  << "EPSILON " << Exact(1, -format.m).decimal() << '\n'
                  << "PATTERNS finite=" << 2 * count << " infinite=2 nan=" << 2 * (format.hidden - 1)
                  << " total=" << (1 << format.w) << '\n';
    }

public:
    Laboratory() {
        formats.emplace("HALF", Format("HALF", 5, 10));
        formats.emplace("E5M2", Format("E5M2", 5, 2));
        formats.emplace("E4M3", Format("E4M3", 4, 3));
    }

    void command(const std::vector<std::string>& words) {
        const std::string& command = words[0];
        if (command == "FORMAT") {
            const std::string& name = words[1];
            const int e = static_cast<int>(decimal_integer(words[2])), m = static_cast<int>(decimal_integer(words[3]));
            if (formats.find(name) != formats.end()) fail("FORMAT EXISTS " + name);
            if (e < 2 || e > 5 || m < 1 || m > 10) fail("BAD FORMAT");
            const auto entry = formats.emplace(name, Format(name, e, m));
            const Format& f = entry.first->second;
            std::cout << "FORMAT " << name << " e=" << e << " m=" << m << " bits=" << f.w
                      << " bias=" << f.bias << " emin=" << f.emin << " emax=" << f.emax << '\n';
            return;
        }
        const Format& f = format(words[1]);
        if (command == "ENCODE") {
            const RealInput input = parse_real(words[2]);
            const Mode mode = parse_mode(words, 3);
            const std::string value = input.kind == RealKind::Finite ? input.exact.fraction() : words[2];
            std::cout << "ENCODE " << f.name << ' ' << mode_text(mode) << ' ' << value << ' '
                      << f.result_text(encoded(f, input, mode)) << '\n';
        } else if (command == "CONVERT") {
            const Format& g = format(words[2]);
            const int a = operand(f, words[3]);
            const Mode mode = parse_mode(words, 4);
            Result result;
            if (f.is_nan(a)) result = {g.nan, f.is_signaling(a) ? Invalid : 0u};
            else if (f.is_infinity(a)) result = {g.inf(f.fields(a).negative)};
            else result = g.round(f.exact(a), mode);
            std::cout << "CONVERT " << f.name << ' ' << g.name << ' ' << mode_text(mode) << ' ' << g.result_text(result) << '\n';
        } else if (command == "SUM" || command == "KAHAN" || command == "DOT") {
            const Mode mode = parse_mode(words, 2);
            if (command == "DOT") {
                const auto separator = static_cast<std::size_t>(std::find(words.begin(), words.end(), "|") - words.begin());
                const auto a = operands(f, words, 3, separator);
                const auto b = operands(f, words, separator + 1, words.size());
                dot(f, mode, a, b);
            } else {
                const auto patterns = operands(f, words, 3, words.size());
                summation(command, f, mode, patterns);
            }
        } else if (command == "TABLE") table(f);
        else if (const auto op = parse_operation(command)) {
            const std::size_t count = *op == Operation::Sqrt ? 1 : *op == Operation::Fma ? 3 : 2;
            const auto patterns = operands(f, words, 2, 2 + count);
            const Mode mode = parse_mode(words, 2 + count);
            std::cout << command << ' ' << f.name << ' ' << mode_text(mode) << ' '
                      << f.result_text(operation(f, *op, patterns, mode)) << '\n';
        } else {
            const int a = operand(f, words[2]);
            const Fields fields = f.fields(a);
            if (command == "DECODE") {
                const std::string classification = f.is_nan(a) ? (f.is_signaling(a) ? "snan" : "qnan")
                    : f.is_infinity(a) ? "infinity" : f.is_zero(a) ? "zero" : fields.exponent == 0 ? "subnormal" : "normal";
                std::cout << "DECODE " << f.name << ' ' << f.bits(a) << ' ' << f.hex(a) << ' ' << classification
                          << " sign=" << (fields.negative ? 1 : 0) << '\n';
                std::cout << "FIELDS exponent=" << fields.exponent << " fraction=" << fields.fraction;
                if (f.is_finite(a)) {
                    std::cout << " unbiased=" << fields.q + f.m << " significand=" << (fields.exponent == 0 ? '0' : '1')
                              << '.' << binary(fields.fraction, f.m) << '\n'
                              << "VALUE " << f.exact(a).fraction() << ' ' << f.value(a) << '\n';
                } else {
                    if (f.is_nan(a)) std::cout << " payload=" << fields.fraction % (f.hidden / 2);
                    std::cout << '\n';
                }
            } else if (command == "COMPARE") {
                const int b = operand(f, words[3]);
                auto key = [&](int p) { return f.fields(p).negative ? -(p - f.sign_bit) - 1 : p; };
                const std::string order = relation(key(a), key(b));
                const std::string numeric = f.is_nan(a) || f.is_nan(b) ? "UN"
                    : f.is_zero(a) && f.is_zero(b) ? "EQ" : order;
                const unsigned flags = f.is_signaling(a) || f.is_signaling(b) ? Invalid : 0;
                std::cout << "COMPARE " << f.name << ' ' << f.hex(a) << ' ' << f.hex(b) << ' ' << numeric
                          << " total=" << order << ' ' << flags_text(flags) << '\n';
            } else if (command == "TOINT") {
                const auto type = integer_types.find(words[3]);
                if (type == integer_types.end()) fail("BAD TYPE " + words[3]);
                const Mode mode = parse_mode(words, 4);
                std::cout << "TOINT " << f.name << ' ' << words[3] << ' ' << mode_text(mode) << ' ';
                if (!f.is_finite(a)) std::cout << "invalid flags=invalid\n";
                else {
                    const Units units = rounded_units(f.exact(a), 0, mode);
                    const Integer integer = fields.negative ? -units.integer : units.integer;
                    const auto [minimum, maximum] = type->second;
                    if (integer < minimum || integer > maximum) std::cout << "invalid flags=invalid\n";
                    else std::cout << integer << ' ' << flags_text(units.inexact ? Inexact : 0) << '\n';
                }
            } else {
                Result result;
                if (f.is_nan(a)) result = {f.nan, f.is_signaling(a) ? Invalid : 0u};
                else if (command == "NEXTUP") result = {next_up(f, a)};
                else if (command == "NEXTDOWN") result = {f.flip(next_up(f, f.flip(a)))};
                else result = {f.is_infinity(a) ? f.infinity : f.round({1, fields.q}, Mode::RNE).pattern};
                std::cout << command << ' ' << f.name << ' ' << f.result_text(result) << '\n';
            }
        }
    }
};

int main() {
    std::ios::sync_with_stdio(false);
    std::cin.tie(nullptr);
    int count;
    std::cin >> count;
    std::string line;
    std::getline(std::cin, line);
    Laboratory laboratory;
    for (int i = 0; i < count; ++i) {
        std::getline(std::cin, line);
        std::istringstream input(line);
        std::vector<std::string> words;
        for (std::string word; input >> word;) words.push_back(std::move(word));
        try {
            laboratory.command(words);
        } catch (const CommandError& error) {
            std::cout << "ERROR " << error.what() << '\n';
        }
    }
}
