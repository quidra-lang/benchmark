#include <algorithm>
#include <array>
#include <cstdint>
#include <initializer_list>
#include <iostream>
#include <limits>
#include <map>
#include <numeric>
#include <optional>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

using Word = std::uint32_t;
using Matrix = std::vector<Word>;
using Lines = std::vector<std::string>;
using Wide = std::int64_t;

struct CommandError : std::runtime_error { using std::runtime_error::runtime_error; };
[[noreturn]] void fail(const std::string& reason) { throw CommandError(reason); }
bool bit(Word word, int length, int column) { return ((word >> (length - column - 1)) & 1) != 0; }
std::string bits(Word word, int length) {
    std::string result(length, '0');
    for (int column = 0; column < length; ++column) if (bit(word, length, column)) result[column] = '1';
    return result;
}
int degree(Word word) {
    int result = -1;
    for (; word; word >>= 1) ++result;
    return result;
}
int weight(Word word) {
    int count = 0;
    for (; word; word &= word - 1) ++count;
    return count;
}
std::string yes(bool value) { return value ? "yes" : "no"; }
std::string join(const Lines& values, const std::string& separator = " ") {
    std::string result;
    for (const auto& value : values) { if (!result.empty()) result += separator; result += value; }
    return result;
}
struct Division { Word quotient, remainder; };
Division divide(Word dividend, Word divisor) {
    Word quotient = 0;
    const int d = degree(divisor);
    while (dividend && degree(dividend) >= d) {
        const int shift = degree(dividend) - d;
        quotient ^= Word{1} << shift;
        dividend ^= divisor << shift;
    }
    return {quotient, dividend};
}
Matrix basis(const Matrix& rows, int length) {
    Matrix pivots(length), kept;
    for (Word original : rows) {
        Word row = original;
        for (int column = 0; column < length; ++column) if (bit(row, length, column)) {
            if (pivots[column]) row ^= pivots[column];
            else { pivots[column] = row; kept.push_back(original); break; }
        }
    }
    return kept;
}
struct Echelon { Matrix rows; std::vector<int> columns; };
Echelon rref(Matrix rows, int length) {
    std::vector<int> columns;
    for (int column = 0; column < length; ++column) {
        const int pivot = static_cast<int>(columns.size());
        int found = pivot;
        while (found < static_cast<int>(rows.size()) && !bit(rows[found], length, column)) ++found;
        if (found == static_cast<int>(rows.size())) continue;
        std::swap(rows[pivot], rows[found]);
        for (int row = 0; row < static_cast<int>(rows.size()); ++row) if (row != pivot && bit(rows[row], length, column)) rows[row] ^= rows[pivot];
        columns.push_back(column);
    }
    rows.resize(columns.size());
    return {std::move(rows), std::move(columns)};
}
Matrix nullspace(const Matrix& original, int length) {
    const auto reduced = rref(original, length);
    Matrix result;
    for (int column = 0; column < length; ++column) {
        if (std::find(reduced.columns.begin(), reduced.columns.end(), column) != reduced.columns.end()) continue;
        Word word = Word{1} << (length - column - 1);
        for (std::size_t row = 0; row < reduced.rows.size(); ++row) if (bit(reduced.rows[row], length, column)) word |= Word{1} << (length - reduced.columns[row] - 1);
        result.push_back(word);
    }
    return result;
}
Matrix span(const Matrix& rows) {
    Matrix words{0};
    for (Word row : rows) {
        const auto count = words.size();
        for (std::size_t index = 0; index < count; ++index) words.push_back(words[index] ^ row);
    }
    return words;
}
std::vector<int> distribution(const Matrix& words, int length) {
    std::vector<int> counts(length + 1);
    for (Word word : words) ++counts[weight(word)];
    return counts;
}
std::string weightList(const std::vector<int>& counts) {
    Lines result;
    for (std::size_t index = 0; index < counts.size(); ++index) if (counts[index]) result.push_back(std::to_string(index) + ":" + std::to_string(counts[index]));
    return join(result);
}
void dimension(int length, int rank) {
    if (rank < 1 || rank > 12 || length - rank < 1 || length - rank > 12) fail("bad dimension " + std::to_string(length) + " " + std::to_string(rank));
}
Word removeBit(Word word, int length, int column) {
    const int low = length - column - 1;
    return ((word >> (low + 1)) << low) | (word & ((Word{1} << low) - 1));
}
Matrix reedMuller(int order, int variables) {
    const int length = 1 << variables;
    if (order == 0) return {(Word{1} << length) - 1};
    Matrix result;
    for (Word row : reedMuller(std::min(order, variables - 1), variables - 1)) result.push_back((row << (length / 2)) | row);
    const auto lower = reedMuller(order - 1, variables - 1);
    result.insert(result.end(), lower.begin(), lower.end());
    return result;
}

struct Decoded { Word error, word, message; };
class Code {
    std::optional<Matrix> leaderTable;
public:
    int n, k;
    Matrix G, H, words;
    std::optional<Word> polynomial;
    std::map<Word, Word> messages;

    Code(int length, Matrix generator, std::optional<Matrix> check = {}, std::optional<Word> poly = {})
        : n(length), k(static_cast<int>(generator.size())), G(std::move(generator)), polynomial(poly) {
        dimension(n, k);
        H = check ? std::move(*check) : nullspace(G, n);
        for (Word message = 0; message < (Word{1} << k); ++message) {
            const Word word = encode(message);
            messages.emplace(word, message); words.push_back(word);
        }
        std::sort(words.begin(), words.end());
    }
    std::string encoder() const { return polynomial ? "polynomial" : "matrix"; }
    Word encode(Word message) const {
        if (polynomial) {
            const Word shifted = message << (n - k);
            return shifted | divide(shifted, *polynomial).remainder;
        }
        Word word = 0;
        for (int row = 0; row < k; ++row) if (bit(message, k, row)) word ^= G[row];
        return word;
    }
    Word syndrome(Word word) const {
        Word result = 0;
        for (Word row : H) result = (result << 1) | (weight(row & word) % 2);
        return result;
    }
    const Matrix& leaders() {
        if (leaderTable) return *leaderTable;
        const Word absent = std::numeric_limits<Word>::max();
        Matrix leaders(Word{1} << (n - k), absent);
        leaders[0] = 0;
        std::size_t remaining = leaders.size() - 1;
        for (int count = 1; remaining; ++count) {
            for (Word word = (Word{1} << count) - 1; word < (Word{1} << n);) {
                const Word s = syndrome(word);
                if (leaders[s] == absent) {
                    leaders[s] = word;
                    if (--remaining == 0) break;
                }
                const Word lowest = word & (Word{0} - word), next = word + lowest;
                word = next | (((next ^ word) >> 2) / lowest);
            }
        }
        leaderTable = std::move(leaders);
        return *leaderTable;
    }
    Decoded decode(Word received) {
        const Word error = leaders()[syndrome(received)], word = received ^ error;
        return {error, word, messages.at(word)};
    }
    std::string decodedText(const Decoded& value) const {
        return "codeword " + bits(value.word, n) + " message " + bits(value.message, k) + " error " + bits(value.error, n) + " weight " + std::to_string(weight(value.error));
    }
};

enum class Verb {
    Gen, Pcheck, Hamming, Simplex, Repetition, Parity, Rm, Cyclic, Dual, Extend,
    Puncture, Shorten, Augment, Expurgate, Permute, Directsum, Uuv, Product,
    List, Delete, Show, Info, Systematic, Weights, Covering, Burst, Trellis, Stdarray,
    Equal, Encode, Syndrome, Decode, Bounded, Coset, Erasure, Interleave,
    Crc, Crccheck, Factor, Macwilliams, Bounds
};
enum class Argument { Name, Code, Number, Bits, Erasure };
struct Format { Verb verb; std::vector<Argument> types; std::optional<Argument> repeat; int maximum; };
const std::map<std::string, Format> formats = [] {
    using A = Argument;
    using V = Verb;
    std::map<std::string, Format> result;
    auto add = [&](std::initializer_list<std::pair<std::string, V>> names, std::vector<A> types, std::optional<A> repeat = {}, int maximum = 0) {
        for (const auto& [name, verb] : names) result.emplace(name, Format{verb, types, repeat, maximum});
    };
    add({{"GEN", V::Gen}, {"PCHECK", V::Pcheck}}, {A::Name}, A::Bits, 24);
    add({{"HAMMING", V::Hamming}, {"SIMPLEX", V::Simplex}, {"REPETITION", V::Repetition}, {"PARITY", V::Parity}}, {A::Name, A::Number});
    add({{"RM", V::Rm}}, {A::Name, A::Number, A::Number});
    add({{"CYCLIC", V::Cyclic}}, {A::Name, A::Number, A::Bits});
    add({{"DUAL", V::Dual}, {"EXTEND", V::Extend}, {"AUGMENT", V::Augment}, {"EXPURGATE", V::Expurgate}}, {A::Name, A::Code});
    add({{"PUNCTURE", V::Puncture}, {"SHORTEN", V::Shorten}}, {A::Name, A::Code, A::Number});
    add({{"PERMUTE", V::Permute}}, {A::Name, A::Code}, A::Number, 24);
    add({{"DIRECTSUM", V::Directsum}, {"UUV", V::Uuv}, {"PRODUCT", V::Product}}, {A::Name, A::Code, A::Code});
    add({{"LIST", V::List}}, {});
    add({{"DELETE", V::Delete}, {"SHOW", V::Show}, {"INFO", V::Info}, {"SYSTEMATIC", V::Systematic}, {"WEIGHTS", V::Weights},
         {"COVERING", V::Covering}, {"BURST", V::Burst}, {"TRELLIS", V::Trellis}, {"STDARRAY", V::Stdarray}}, {A::Code});
    add({{"EQUAL", V::Equal}}, {A::Code, A::Code});
    add({{"ENCODE", V::Encode}, {"SYNDROME", V::Syndrome}, {"DECODE", V::Decode}, {"COSET", V::Coset}}, {A::Code, A::Bits});
    add({{"BOUNDED", V::Bounded}}, {A::Code, A::Number, A::Bits});
    add({{"ERASURE", V::Erasure}}, {A::Code, A::Erasure});
    add({{"INTERLEAVE", V::Interleave}}, {A::Code, A::Number, A::Number}, A::Bits, 8);
    add({{"CRC", V::Crc}, {"CRCCHECK", V::Crccheck}}, {A::Bits, A::Bits});
    add({{"FACTOR", V::Factor}}, {A::Number});
    add({{"MACWILLIAMS", V::Macwilliams}}, {A::Number}, A::Number, 25);
    add({{"BOUNDS", V::Bounds}}, {A::Number, A::Number});
    return result;
}();
bool valid(const std::string& text, Argument type) {
    const auto letter = [](char c) { return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z'); };
    const auto digit = [](char c) { return c >= '0' && c <= '9'; };
    if (text.empty()) return false;
    if (type == Argument::Name || type == Argument::Code) return text.size() <= 8 && letter(text[0]) &&
        std::all_of(text.begin(), text.end(), [&](char c) { return letter(c) || digit(c); });
    if (type == Argument::Number) return text.size() <= 4 && (text.size() == 1 || text[0] != '0') && std::all_of(text.begin(), text.end(), digit);
    return text.size() <= 30 && std::all_of(text.begin(), text.end(), [&](char c) { return c == '0' || c == '1' || (type == Argument::Erasure && c == '?'); });
}
bool defining(Verb verb) {
    switch (verb) {
        case Verb::Gen: case Verb::Pcheck: case Verb::Hamming: case Verb::Simplex: case Verb::Repetition: case Verb::Parity:
        case Verb::Rm: case Verb::Cyclic: case Verb::Dual: case Verb::Extend: case Verb::Puncture: case Verb::Shorten:
        case Verb::Augment: case Verb::Expurgate: case Verb::Permute: case Verb::Directsum: case Verb::Uuv: case Verb::Product: return true;
        default: return false;
    }
}
struct Command { Verb verb; Lines args; };
Word parseWord(const std::string& text) { return static_cast<Word>(std::stoul(text, nullptr, 2)); }
const std::array<std::array<Wide, 25>, 25> choose = [] {
    std::array<std::array<Wide, 25>, 25> result{};
    for (int n = 0; n <= 24; ++n) {
        result[n][0] = result[n][n] = 1;
        for (int k = 1; k < n; ++k) result[n][k] = result[n - 1][k - 1] + result[n - 1][k];
    }
    return result;
}();
Wide binomial(int n, int k) { return k < 0 || k > n ? 0 : choose[n][k]; }

Lines independent(Verb verb, const Lines& args) {
    if (verb == Verb::Crc || verb == Verb::Crccheck) {
        const auto& generator = args[0]; const auto& text = args[1];
        const int d = static_cast<int>(generator.size()) - 1;
        if (generator[0] == '0' || generator.size() < 2 || generator.size() > 17) fail("bad parameter");
        if (verb == Verb::Crc && text.size() + d > 30) fail("bad length");
        const Word word = parseWord(text), divisor = parseWord(generator);
        const Word remainder = divide(verb == Verb::Crc ? word << d : word, divisor).remainder;
        const auto suffix = bits(remainder, d);
        return {verb == Verb::Crc ? "crc remainder " + suffix + " frame " + text + suffix :
            std::string("crccheck ") + (remainder == 0 ? "ok" : "error") + " remainder " + suffix};
    }
    const int n = std::stoi(args[0]);
    if (verb == Verb::Bounds) {
        const int d = std::stoi(args[1]);
        if (d < 1 || d > n || n > 24) fail("bad parameter");
        const Wide volume = std::accumulate(choose[n].begin(), choose[n].begin() + (d - 1) / 2 + 1, Wide{0});
        int hamming = 0, griesmer = 0, sum = 0;
        for (int k = 0; k <= n; ++k) if ((Wide{1} << k) * volume <= (Wide{1} << n)) hamming = k;
        for (int k = 1; k <= n; ++k) {
            const int denominator = 1 << (k - 1);
            sum += (d + denominator - 1) / denominator;
            if (sum <= n) griesmer = k;
        }
        return {"bounds n " + std::to_string(n) + " d " + std::to_string(d) + " singleton " + std::to_string(n - d + 1) +
            " hamming " + std::to_string(hamming) + " griesmer " + std::to_string(griesmer)};
    }
    if (n < 1 || n > 24) fail("bad parameter");
    if (verb == Verb::Factor) {
        Word remaining = (Word{1} << n) | 1;
        int divisors = 1;
        Lines factors;
        for (Word candidate = 2; 2 * degree(candidate) <= degree(remaining); ++candidate) {
            int exponent = 0;
            while (divide(remaining, candidate).remainder == 0) { remaining = divide(remaining, candidate).quotient; ++exponent; }
            if (exponent) { factors.push_back(bits(candidate, degree(candidate) + 1) + "^" + std::to_string(exponent)); divisors *= exponent + 1; }
        }
        if (remaining > 1) { factors.push_back(bits(remaining, degree(remaining) + 1) + "^1"); divisors *= 2; }
        return {"factor " + std::to_string(n) + " " + join(factors) + " divisors " + std::to_string(divisors)};
    }
    if (args.size() != static_cast<std::size_t>(n + 2)) fail("bad length");
    if (std::stoi(args[1]) != 1) fail("bad parameter");
    std::vector<Wide> counts;
    for (std::size_t index = 1; index < args.size(); ++index) counts.push_back(std::stoi(args[index]));
    const Wide size = std::accumulate(counts.begin(), counts.end(), Wide{0});
    bool feasible = (size & (size - 1)) == 0;
    Lines transformed;
    for (int j = 0; j <= n; ++j) {
        Wide numerator = 0;
        for (int x = 0; x <= n; ++x) {
            Wide krawtchouk = 0;
            for (int y = 0; y <= j; ++y) krawtchouk += (y % 2 ? -1 : 1) * binomial(x, y) * binomial(n - x, j - y);
            numerator += counts[x] * krawtchouk;
        }
        const Wide divisor = std::gcd(numerator, size), p = numerator / divisor, q = size / divisor;
        transformed.push_back(std::to_string(p) + (q == 1 ? "" : "/" + std::to_string(q)));
        if (q != 1 || p < 0) feasible = false;
    }
    return {"macwilliams n " + std::to_string(n) + " size " + std::to_string(size), "dual " + join(transformed), "feasible " + yes(feasible)};
}

class Laboratory {
    std::map<std::string, Code> codes;

    Lines define(Verb verb, const Lines& args) {
        const auto& name = args[0];
        const auto first = codes.find(args[1]);
        const auto second = args.size() > 2 ? codes.find(args[2]) : codes.end();
        const Code* a = first == codes.end() ? nullptr : &first->second;
        const Code* b = second == codes.end() ? nullptr : &second->second;
        int n = 0;
        Matrix G;
        std::optional<Matrix> H;
        std::optional<Word> polynomial;
        switch (verb) {
            case Verb::Gen: case Verb::Pcheck: {
                n = static_cast<int>(args[1].size());
                Matrix rows;
                for (std::size_t index = 1; index < args.size(); ++index) {
                    if (static_cast<int>(args[index].size()) != n) fail("bad length");
                    rows.push_back(parseWord(args[index]));
                }
                rows = basis(rows, n);
                if (verb == Verb::Gen) G = std::move(rows);
                else { H = std::move(rows); G = nullspace(*H, n); }
                break;
            }
            case Verb::Hamming: case Verb::Simplex: {
                const int r = std::stoi(args[1]);
                if (r < 2 || r > 4) fail("bad parameter");
                n = (1 << r) - 1;
                Matrix rows(r);
                for (int column = 1; column <= n; ++column) for (int row = 0; row < r; ++row) rows[row] = (rows[row] << 1) | bit(column, r, row);
                if (verb == Verb::Hamming) { H = std::move(rows); G = nullspace(*H, n); }
                else G = std::move(rows);
                break;
            }
            case Verb::Repetition: case Verb::Parity: {
                n = std::stoi(args[1]);
                if (n < 2 || n > 24) fail("bad parameter");
                if (verb == Verb::Repetition) G.push_back((Word{1} << n) - 1);
                else for (int row = 0; row < n - 1; ++row) G.push_back((Word{1} << (n - row - 1)) | 1);
                break;
            }
            case Verb::Rm: {
                const int r = std::stoi(args[1]), m = std::stoi(args[2]);
                if (m < 1 || m > 4 || r > m) fail("bad parameter");
                n = 1 << m; G = reedMuller(r, m);
                break;
            }
            case Verb::Cyclic: {
                n = std::stoi(args[1]);
                const auto& text = args[2];
                const int d = static_cast<int>(text.size()) - 1;
                if (n < 2 || n > 24 || text[0] == '0' || text.size() < 2 || static_cast<int>(text.size()) > n) fail("bad parameter");
                polynomial = parseWord(text);
                if (divide((Word{1} << n) | 1, *polynomial).remainder) fail("not a divisor");
                const int k = n - d;
                dimension(n, k);
                for (int row = 0; row < k; ++row) G.push_back(*polynomial << (k - row - 1));
                H = Matrix(d);
                for (int column = 0; column < n; ++column) {
                    const Word remainder = divide(Word{1} << (n - column - 1), *polynomial).remainder;
                    for (int row = 0; row < d; ++row) (*H)[row] = ((*H)[row] << 1) | bit(remainder, d, row);
                }
                break;
            }
            case Verb::Dual: n = a->n; G = a->H; H = a->G; break;
            case Verb::Extend:
                n = a->n + 1;
                for (Word row : a->G) G.push_back((row << 1) | (weight(row) % 2));
                break;
            case Verb::Puncture: case Verb::Shorten: {
                const int column = std::stoi(args[2]) - 1;
                if (column < 0 || column >= a->n) fail("bad position");
                Matrix rows = a->G;
                if (verb == Verb::Shorten) {
                    const auto pivot = std::find_if(rows.begin(), rows.end(), [&](Word row) { return bit(row, a->n, column); });
                    if (pivot != rows.end()) {
                        const Word z = *pivot;
                        rows.erase(pivot);
                        for (Word& row : rows) if (bit(row, a->n, column)) row ^= z;
                    }
                }
                n = a->n - 1;
                for (Word row : rows) G.push_back(removeBit(row, a->n, column));
                if (verb == Verb::Puncture) G = basis(G, n);
                break;
            }
            case Verb::Augment:
                n = a->n; G = a->G; G.push_back((Word{1} << n) - 1); G = basis(G, n);
                break;
            case Verb::Expurgate: {
                n = a->n; G = a->G;
                const auto pivot = std::find_if(G.begin(), G.end(), [](Word row) { return weight(row) % 2 != 0; });
                if (pivot != G.end()) {
                    const Word z = *pivot;
                    G.erase(pivot);
                    for (Word& row : G) if (weight(row) % 2) row ^= z;
                }
                break;
            }
            case Verb::Permute: {
                n = a->n;
                std::vector<int> order;
                for (std::size_t index = 2; index < args.size(); ++index) order.push_back(std::stoi(args[index]));
                const std::set<int> distinct(order.begin(), order.end());
                if (static_cast<int>(order.size()) != n || static_cast<int>(distinct.size()) != n || *distinct.begin() != 1 || *distinct.rbegin() != n) fail("bad permutation");
                for (Word row : a->G) {
                    Word word = 0;
                    for (int column : order) word = (word << 1) | bit(row, n, column - 1);
                    G.push_back(word);
                }
                break;
            }
            case Verb::Directsum: case Verb::Uuv: case Verb::Product: {
                if (verb == Verb::Uuv && a->n != b->n) fail("bad length");
                n = verb == Verb::Product ? a->n * b->n : a->n + b->n;
                dimension(n, verb == Verb::Product ? a->k * b->k : a->k + b->k);
                if (verb == Verb::Product) {
                    for (Word x : a->G) for (Word y : b->G) {
                        Word word = 0;
                        for (int column = 0; column < a->n; ++column) word = (word << b->n) | (bit(x, a->n, column) ? y : 0);
                        G.push_back(word);
                    }
                } else {
                    for (Word row : a->G) G.push_back((row << b->n) | (verb == Verb::Uuv ? row : 0));
                    G.insert(G.end(), b->G.begin(), b->G.end());
                }
                break;
            }
            default: throw std::logic_error("not a defining command");
        }
        Code code(n, std::move(G), std::move(H), polynomial);
        const bool replaced = codes.count(name) != 0;
        const int k = code.k;
        codes.insert_or_assign(name, std::move(code));
        return {std::string(replaced ? "redefined " : "defined ") + name + " n " + std::to_string(n) + " k " + std::to_string(k)};
    }
    Lines systematic(const std::string& name, const Code& code) const {
        const int n = code.n, k = code.k;
        Matrix rows = code.G;
        std::vector<int> order(n);
        std::iota(order.begin(), order.end(), 1);
        for (int pivot = 0; pivot < k; ++pivot) {
            int column = pivot;
            while (std::none_of(rows.begin() + pivot, rows.end(), [&](Word row) { return bit(row, n, column); })) ++column;
            if (column != pivot) {
                const Word mask = (Word{1} << (n - pivot - 1)) | (Word{1} << (n - column - 1));
                for (Word& row : rows) if (bit(row, n, pivot) != bit(row, n, column)) row ^= mask;
                std::swap(order[pivot], order[column]);
            }
            int found = pivot;
            while (!bit(rows[found], n, pivot)) ++found;
            std::swap(rows[pivot], rows[found]);
            for (int row = 0; row < k; ++row) if (row != pivot && bit(rows[row], n, pivot)) rows[row] ^= rows[pivot];
        }
        Lines permutation;
        for (int column : order) permutation.push_back(std::to_string(column));
        Lines output{"systematic " + name + " perm " + join(permutation)};
        for (Word row : rows) output.push_back("G " + bits(row, n));
        for (int column = k; column < n; ++column) {
            Word row = 0;
            for (Word value : rows) row = (row << 1) | bit(value, n, column);
            row = (row << (n - k)) | (Word{1} << (n - column - 1));
            output.push_back("H " + bits(row, n));
        }
        return output;
    }
    Lines burst(const std::string& name, const Code& code) const {
        int detect = code.n;
        for (Word word : code.words) if (word) detect = std::min(detect, degree(word) - degree(word & (Word{0} - word)));
        std::set<Word> seen{0};
        for (int length = 1; length <= code.n; ++length) {
            for (int start = 0; start + length <= code.n; ++start) {
                const Word limit = length == 1 ? 1 : Word{1} << (length - 2);
                for (Word middle = 0; middle < limit; ++middle) {
                    const Word pattern = length == 1 ? 1 : (Word{1} << (length - 1)) | (middle << 1) | 1;
                    const Word syndrome = code.syndrome(pattern << (code.n - start - length));
                    if (!seen.insert(syndrome).second) return {"burst " + name + " detect " + std::to_string(detect) + " correct " + std::to_string(length - 1)};
                }
            }
        }
        throw std::logic_error("a nonzero codeword must be an undetectable burst");
    }
    Lines interleave(const std::string& name, Code& code, const Lines& args) const {
        const int start = std::stoi(args[1]), length = std::stoi(args[2]), depth = static_cast<int>(args.size()) - 3;
        for (std::size_t index = 3; index < args.size(); ++index) if (static_cast<int>(args[index].size()) != code.k) fail("bad length");
        if (start < 1 || length < 1 || start + length - 1 > depth * code.n) fail("bad burst");
        Matrix sentWords, receivedWords(depth);
        for (std::size_t index = 3; index < args.size(); ++index) sentWords.push_back(code.encode(parseWord(args[index])));
        std::string sent, received;
        for (int column = 0; column < code.n; ++column) for (int row = 0; row < depth; ++row) {
            const int position = column * depth + row + 1;
            const bool original = bit(sentWords[row], code.n, column), changed = original != (start <= position && position < start + length);
            sent += original ? '1' : '0'; received += changed ? '1' : '0';
            receivedWords[row] = (receivedWords[row] << 1) | changed;
        }
        Lines output{"interleave " + name + " depth " + std::to_string(depth) + " burst " + std::to_string(start) + " " + std::to_string(length), "sent " + sent, "recv " + received};
        int correct = 0;
        for (int row = 0; row < depth; ++row) {
            const auto decoded = code.decode(receivedWords[row]);
            const auto message = bits(decoded.message, code.k);
            const bool ok = message == args[row + 3];
            if (ok) ++correct;
            output.push_back("row " + std::to_string(row + 1) + " errors " + std::to_string(weight(receivedWords[row] ^ sentWords[row])) + " corrected " +
                std::to_string(weight(decoded.error)) + " message " + message + (ok ? " ok" : " wrong"));
        }
        output.push_back("result ok " + std::to_string(correct) + " wrong " + std::to_string(depth - correct));
        return output;
    }
public:
    Command parse(const std::string& line) const {
        std::istringstream input(line);
        std::string name, word;
        input >> name;
        const auto found = formats.find(name);
        if (found == formats.end()) fail("unknown command " + name);
        const auto& spec = found->second;
        Lines args;
        while (input >> word) args.push_back(word);
        const int extra = static_cast<int>(args.size()) - static_cast<int>(spec.types.size());
        if (spec.repeat ? extra < 1 || extra > spec.maximum : extra != 0) fail("bad arguments");
        for (std::size_t index = 0; index < args.size(); ++index) if (!valid(args[index], index < spec.types.size() ? spec.types[index] : *spec.repeat)) fail("bad arguments");
        for (std::size_t index = 0; index < spec.types.size(); ++index) if (spec.types[index] == Argument::Code && !codes.count(args[index])) fail("no code " + args[index]);
        return {spec.verb, std::move(args)};
    }
    Lines execute(const Command& command) {
        const Verb verb = command.verb;
        const auto& args = command.args;
        if (defining(verb)) return define(verb, args);
        if (verb == Verb::Crc || verb == Verb::Crccheck || verb == Verb::Factor || verb == Verb::Macwilliams || verb == Verb::Bounds) return independent(verb, args);
        if (verb == Verb::List) {
            Lines output{"codes " + std::to_string(codes.size())};
            for (const auto& [name, code] : codes) output.push_back(name + " n " + std::to_string(code.n) + " k " + std::to_string(code.k) + " encoder " + code.encoder());
            return output;
        }
        const auto& name = args[0];
        if (verb == Verb::Delete) { codes.erase(name); return {"deleted " + name}; }
        Code& code = codes.at(name);
        const int n = code.n, k = code.k;
        switch (verb) {
            case Verb::Show: {
                Lines output{"code " + name + " n " + std::to_string(n) + " k " + std::to_string(k) + " encoder " + code.encoder()};
                if (code.polynomial) output.push_back("poly g " + bits(*code.polynomial, n - k + 1) + " h " + bits(divide((Word{1} << n) | 1, *code.polynomial).quotient, k + 1));
                for (Word row : code.G) output.push_back("G " + bits(row, n));
                for (Word row : code.H) output.push_back("H " + bits(row, n));
                return output;
            }
            case Verb::Info: {
                int distance = n;
                for (Word word : code.words) if (word) distance = std::min(distance, weight(word));
                const int t = (distance - 1) / 2, divisor = std::gcd(n, k);
                const Wide volume = std::accumulate(choose[n].begin(), choose[n].begin() + t + 1, Wide{0});
                const bool cyclic = std::all_of(code.G.begin(), code.G.end(), [&](Word row) {
                    return code.messages.count(((row << 1) & ((Word{1} << n) - 1)) | (row >> (n - 1))) != 0;
                });
                return {"info " + name + " n " + std::to_string(n) + " k " + std::to_string(k) + " rate " + std::to_string(k / divisor) + "/" + std::to_string(n / divisor) +
                    " d " + std::to_string(distance) + " t " + std::to_string(t) + " perfect " + yes(volume == (Wide{1} << (n - k))) +
                    " mds " + yes(distance == n - k + 1) + " cyclic " + (cyclic ? bits(code.words[1], degree(code.words[1]) + 1) : "no")};
            }
            case Verb::Systematic: return systematic(name, code);
            case Verb::Weights: {
                const auto a = distribution(code.words, n), b = distribution(span(code.H), n);
                bool orthogonal = true;
                for (Word x : code.G) for (Word y : code.G) if (weight(x & y) % 2) orthogonal = false;
                return {"weights " + name + " " + weightList(a), "dual " + name + " " + weightList(b), "duality " + name +
                    " self-orthogonal " + yes(orthogonal) + " self-dual " + yes(orthogonal && n == 2 * k) + " formally-self-dual " + yes(a == b)};
            }
            case Verb::Covering: {
                const auto counts = distribution(code.leaders(), n);
                int radius = n;
                while (counts[radius] == 0) --radius;
                Lines items;
                for (int value = 0; value <= radius; ++value) items.push_back(std::to_string(value) + ":" + std::to_string(counts[value]));
                return {"covering " + name + " radius " + std::to_string(radius) + " leaders " + join(items)};
            }
            case Verb::Burst: return burst(name, code);
            case Verb::Trellis: {
                Lines profile;
                int maximum = 0;
                for (int cut = 0; cut <= n; ++cut) {
                    const int right = n - cut;
                    Matrix prefix, suffix;
                    for (Word row : code.G) { prefix.push_back(row >> right); suffix.push_back(row & ((Word{1} << right) - 1)); }
                    const int value = static_cast<int>(basis(prefix, cut).size() + basis(suffix, right).size()) - k;
                    profile.push_back(std::to_string(value)); maximum = std::max(maximum, value);
                }
                return {"trellis " + name + " profile " + join(profile) + " max " + std::to_string(maximum)};
            }
            case Verb::Stdarray: {
                if (n - k > 6 || k > 4) fail("too large");
                const auto& leaders = code.leaders();
                Matrix syndromes(leaders.size());
                std::iota(syndromes.begin(), syndromes.end(), Word{0});
                std::sort(syndromes.begin(), syndromes.end(), [&](Word a, Word b) {
                    return weight(leaders[a]) != weight(leaders[b]) ? weight(leaders[a]) < weight(leaders[b]) : leaders[a] < leaders[b];
                });
                Lines output{"stdarray " + name + " rows " + std::to_string(leaders.size()) + " columns " + std::to_string(code.words.size())};
                for (Word s : syndromes) {
                    std::string row = bits(s, n - k) + ":";
                    for (Word word : code.words) row += " " + bits(word ^ leaders[s], n);
                    output.push_back(std::move(row));
                }
                return output;
            }
            case Verb::Equal: {
                const auto& other = codes.at(args[1]);
                if (n != other.n) return {"equal " + name + " " + args[1] + " no lengths " + std::to_string(n) + " " + std::to_string(other.n)};
                Matrix combined = code.G;
                combined.insert(combined.end(), other.G.begin(), other.G.end());
                const int common = k + other.k - static_cast<int>(basis(combined, n).size());
                return {"equal " + name + " " + args[1] + " " + yes(k == common && other.k == common) + " intersection " + std::to_string(common)};
            }
            case Verb::Encode:
                if (static_cast<int>(args[1].size()) != k) fail("bad length");
                return {"encode " + name + " message " + args[1] + " codeword " + bits(code.encode(parseWord(args[1])), n)};
            case Verb::Syndrome: case Verb::Decode: case Verb::Bounded: case Verb::Coset: {
                const auto& text = args[verb == Verb::Bounded ? 2 : 1];
                if (static_cast<int>(text.size()) != n) fail("bad length");
                const Word word = parseWord(text), syndrome = code.syndrome(word);
                if (verb == Verb::Syndrome) return {"syndrome " + name + " " + bits(syndrome, n - k) + " codeword " + yes(syndrome == 0)};
                const auto decoded = code.decode(word);
                if (verb == Verb::Coset) {
                    Matrix shifted;
                    for (Word value : code.words) shifted.push_back(value ^ word);
                    return {"coset " + name + " syndrome " + bits(syndrome, n - k) + " leader " + bits(decoded.error, n) + " weights " + weightList(distribution(shifted, n))};
                }
                if (verb == Verb::Bounded && weight(decoded.error) > std::stoi(args[1])) return {"bounded " + name + " fail weight " + std::to_string(weight(decoded.error))};
                return {std::string(verb == Verb::Bounded ? "bounded " : "decode ") + name + " " + code.decodedText(decoded)};
            }
            case Verb::Erasure: {
                const auto& text = args[1];
                if (static_cast<int>(text.size()) != n) fail("bad length");
                Word mask = 0, known = 0;
                int erased = 0;
                for (char character : text) {
                    mask = (mask << 1) | (character != '?'); known = (known << 1) | (character == '1');
                    if (character == '?') ++erased;
                }
                Matrix candidates;
                for (Word word : code.words) if ((word & mask) == known) candidates.push_back(word);
                std::string output = "erasure " + name + " erased " + std::to_string(erased) + " candidates " + std::to_string(candidates.size());
                if (candidates.size() == 1) output += " codeword " + bits(candidates[0], n) + " message " + bits(code.messages.at(candidates[0]), k);
                return {output};
            }
            case Verb::Interleave: return interleave(name, code, args);
            default: throw std::logic_error("unhandled command");
        }
    }
};

int main() {
    std::ios::sync_with_stdio(false);
    std::cin.tie(nullptr);
    std::string line;
    std::getline(std::cin, line);
    const int count = std::stoi(line);
    Laboratory laboratory;
    for (int index = 0; index < count; ++index) {
        std::getline(std::cin, line);
        try { for (const auto& row : laboratory.execute(laboratory.parse(line))) std::cout << row << '\n'; }
        catch (const CommandError& error) { std::cout << "error: " << error.what() << '\n'; }
    }
}
