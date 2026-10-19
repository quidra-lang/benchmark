#include <inttypes.h>
#include <stdbool.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef uint32_t Pattern;
typedef unsigned Flags;
enum { INVALID = 1, DIVBYZERO = 2, OVERFLOW = 4, UNDERFLOW = 8, INEXACT = 16 };
typedef enum { RNE, RNA, RTZ, RUP, RDN } Mode;
typedef enum { ZERO, SUBNORMAL, NORMAL, INFINITY_VALUE, QNAN, SNAN } Class;
typedef enum { ADD, SUB, MUL, DIV, SQRT, FMA } Operation;

typedef struct {
    char name[9];
    int e, m, w, bias, emin, emax;
    Pattern sign, base, infinity, nan;
} Format;

typedef struct { bool negative; uint64_t magnitude; int exponent; } Term;
typedef struct { bool negative; uint64_t numerator, denominator; int exponent; } Exact;
typedef struct { Pattern pattern; Flags flags; } Result;
typedef struct { uint64_t whole; bool inexact; int half; } Quantized;
typedef struct { Pattern pattern; Exact exact; bool special; } Operand;
typedef struct { const char *name; int64_t minimum, maximum; } IntegerType;
typedef struct { char data[256]; } Text;

static const char *const mode_names[] = { "RNE", "RNA", "RTZ", "RUP", "RDN" };
static const char *const class_names[] = { "zero", "subnormal", "normal", "infinity", "qnan", "snan" };
static const char *const operation_names[] = { "ADD", "SUB", "MUL", "DIV", "SQRT", "FMA" };
static const IntegerType integer_types[] = {
    { "I8", -128, 127 }, { "U8", 0, 255 }, { "I16", -32768, 32767 },
    { "U16", 0, 65535 }, { "I32", -INT64_C(2147483648), INT64_C(2147483647) },
    { "U32", 0, INT64_C(4294967295) }
};
static Format formats[13];
static size_t format_count;

static Text text(const char *pattern, ...) {
    Text result;
    va_list args;
    va_start(args, pattern);
    vsnprintf(result.data, sizeof result.data, pattern, args);
    va_end(args);
    return result;
}

static Format *find_format(const char *name) {
    for (size_t i = 0; i < format_count; i++) if (!strcmp(formats[i].name, name)) return &formats[i];
    return NULL;
}

static Format *add_format(const char *name, int e, int m) {
    Format *f = &formats[format_count++];
    strcpy(f->name, name);
    f->e = e;
    f->m = m;
    f->w = 1 + e + m;
    f->bias = (1 << (e - 1)) - 1;
    f->emin = 1 - f->bias;
    f->emax = f->bias;
    f->sign = UINT32_C(1) << (e + m);
    f->base = UINT32_C(1) << m;
    f->infinity = ((UINT32_C(1) << e) - 1) << m;
    f->nan = f->infinity | (f->base >> 1);
    return f;
}

static Class classify(const Format *f, Pattern p) {
    Pattern magnitude = p & (f->sign - 1), fraction = p & (f->base - 1);
    if (magnitude >= f->infinity) {
        if (!fraction) return INFINITY_VALUE;
        return fraction >= f->base / 2 ? QNAN : SNAN;
    }
    if (!magnitude) return ZERO;
    return magnitude < f->base ? SUBNORMAL : NORMAL;
}

static bool is_nan(const Format *f, Pattern p) { return classify(f, p) >= QNAN; }
static bool is_finite(const Format *f, Pattern p) { return classify(f, p) <= NORMAL; }
static bool is_zero(const Format *f, Pattern p) { return !(p & (f->sign - 1)); }
static bool negative(const Format *f, Pattern p) { return (p & f->sign) != 0; }
static Pattern with_sign(const Format *f, Pattern p, bool sign) { return p | (sign ? f->sign : 0); }

static Term term(const Format *f, Pattern p) {
    Pattern field = (p & (f->sign - 1)) >> f->m, fraction = p & (f->base - 1);
    return (Term){ negative(f, p), field ? f->base + fraction : fraction,
        field ? (int)field - f->bias - f->m : f->emin - f->m };
}

static uint64_t gcd(uint64_t a, uint64_t b) {
    while (b) { uint64_t remainder = a % b; a = b; b = remainder; }
    return a;
}

static Exact exact(bool sign, uint64_t numerator, int exponent, uint64_t denominator) {
    if (!numerator) return (Exact){ sign, 0, 1, 0 };
    uint64_t common = gcd(numerator, denominator);
    numerator /= common;
    denominator /= common;
    while (!(numerator & 1)) { numerator >>= 1; exponent++; }
    while (!(denominator & 1)) { denominator >>= 1; exponent--; }
    return (Exact){ sign, numerator, denominator, exponent };
}

static Exact exact_term(Term value) { return exact(value.negative, value.magnitude, value.exponent, 1); }
static Term product(Term a, Term b) {
    return (Term){ a.negative != b.negative, a.magnitude * b.magnitude, a.exponent + b.exponent };
}

static Term sum_terms(const Term *terms, size_t count, Mode mode) {
    bool any = false, all_same_zero = true;
    int exponent = 0;
    for (size_t i = 0; i < count; i++) {
        if (terms[i].magnitude) {
            if (!any || terms[i].exponent < exponent) exponent = terms[i].exponent;
            any = true;
            all_same_zero = false;
        } else if (terms[i].negative != terms[0].negative) all_same_zero = false;
    }
    int64_t sum = 0;
    for (size_t i = 0; i < count; i++) {
        if (!terms[i].magnitude) continue;
        uint64_t aligned = terms[i].magnitude << (terms[i].exponent - exponent);
        sum += terms[i].negative ? -(int64_t)aligned : (int64_t)aligned;
    }
    if (!sum) return (Term){ all_same_zero ? terms[0].negative : mode == RDN, 0, 0 };
    return (Term){ sum < 0, (uint64_t)(sum < 0 ? -sum : sum), exponent };
}

static int bit_length(uint64_t value) {
    int length = 0;
    while (value) { length++; value >>= 1; }
    return length;
}

static int floor_log(Exact value) {
    int power = bit_length(value.numerator) - bit_length(value.denominator);
    bool below = power >= 0 ? value.numerator < (value.denominator << power)
        : (value.numerator << -power) < value.denominator;
    return value.exponent + power - below;
}

static uint64_t integer_sqrt(uint64_t value) {
    if (!value) return 0;
    uint64_t low = 0, high = 1;
    while (high <= value / high) high <<= 1;
    while (low + 1 < high) {
        uint64_t middle = (low + high) / 2;
        if (middle <= value / middle) low = middle; else high = middle;
    }
    return low;
}

static int compare_unsigned(uint64_t a, uint64_t b) { return (a > b) - (a < b); }

static Quantized quantize(Exact value, int quantum, bool square_root) {
    uint64_t numerator = value.numerator, denominator = value.denominator;
    int shift = value.exponent - (square_root ? 2 * quantum : quantum);
    if (shift >= 0) numerator <<= shift; else denominator <<= -shift;
    if (!square_root) {
        uint64_t remainder = numerator % denominator;
        return (Quantized){ numerator / denominator, remainder != 0, compare_unsigned(remainder, denominator - remainder) };
    }
    uint64_t whole = integer_sqrt(numerator / denominator);
    uint64_t midpoint = 2 * whole + 1;
    return (Quantized){ whole, whole * whole * denominator != numerator,
        compare_unsigned(4 * numerator, midpoint * midpoint * denominator) };
}

static bool increment(Quantized value, Mode mode, bool sign) {
    switch (mode) {
        case RNE: return value.half > 0 || (value.half == 0 && (value.whole & 1));
        case RNA: return value.half >= 0;
        case RTZ: return false;
        case RUP: return value.inexact && !sign;
        case RDN: return value.inexact && sign;
    }
    return false;
}

static Result overflow_result(const Format *f, Mode mode, bool sign) {
    bool infinity = mode == RNE || mode == RNA || (mode == RUP && !sign) || (mode == RDN && sign);
    return (Result){ with_sign(f, infinity ? f->infinity : f->infinity - 1, sign), OVERFLOW | INEXACT };
}

static Result round_exact(const Format *f, Exact value, Mode mode, bool square_root) {
    if (!value.numerator) return (Result){ with_sign(f, 0, value.negative), 0 };
    int t = floor_log(value);
    if (square_root) t = t < 0 ? -((-t + 1) / 2) : t / 2;
    if (t > f->emax) return overflow_result(f, mode, value.negative);
    int quantum = (t > f->emin ? t : f->emin) - f->m;
    Quantized divided = quantize(value, quantum, square_root);
    uint64_t significand = divided.whole + increment(divided, mode, value.negative);
    if (significand == 2 * f->base) { significand = f->base; quantum++; }
    if (quantum > f->emax - f->m) return overflow_result(f, mode, value.negative);
    Flags flags = divided.inexact ? INEXACT : 0;
    if (divided.inexact && t < f->emin) {
        bool tiny = t < f->emin - 1;
        if (!tiny) {
            Quantized unbounded = quantize(value, t - f->m, square_root);
            tiny = unbounded.whole + increment(unbounded, mode, value.negative) < 2 * f->base;
        }
        if (tiny) flags |= UNDERFLOW;
    }
    Pattern magnitude = significand < f->base ? (Pattern)significand
        : ((Pattern)(quantum + f->m + f->bias) << f->m) | (Pattern)(significand - f->base);
    return (Result){ with_sign(f, magnitude, value.negative), flags };
}

static Result rounded_term(const Format *f, Term value, Mode mode) { return round_exact(f, exact_term(value), mode, false); }
static Result rounded_sum(const Format *f, const Term *terms, size_t count, Mode mode) {
    return rounded_term(f, sum_terms(terms, count, mode), mode);
}

static Text fraction_text(Exact value) {
    if (!value.numerator) return text("0");
    uint64_t numerator = value.numerator, denominator = value.denominator;
    if (value.exponent >= 0) numerator <<= value.exponent; else denominator <<= -value.exponent;
    if (denominator == 1) return text("%s%" PRIu64, value.negative ? "-" : "", numerator);
    return text("%s%" PRIu64 "/%" PRIu64, value.negative ? "-" : "", numerator, denominator);
}

static Text decimal_text(Term term_value) {
    Exact value = exact_term(term_value);
    if (!value.numerator) return text("0");
    uint64_t numerator = value.numerator, denominator = value.denominator;
    if (value.exponent >= 0) numerator <<= value.exponent; else denominator <<= -value.exponent;
    Text result = text("%s%" PRIu64, value.negative ? "-" : "", numerator / denominator);
    uint64_t remainder = numerator % denominator;
    size_t length = strlen(result.data);
    if (remainder) result.data[length++] = '.';
    while (remainder) {
        remainder *= 10;
        result.data[length++] = (char)('0' + remainder / denominator);
        remainder %= denominator;
    }
    result.data[length] = '\0';
    return result;
}

static Text binary_text(Pattern value, int width) {
    Text result;
    for (int i = 0; i < width; i++) result.data[i] = (char)('0' + ((value >> (width - i - 1)) & 1));
    result.data[width] = '\0';
    return result;
}

static Text bits_text(const Format *f, Pattern p) {
    return text("%d|%s|%s", negative(f, p), binary_text((p & (f->sign - 1)) >> f->m, f->e).data,
        binary_text(p & (f->base - 1), f->m).data);
}

static Text hex_text(const Format *f, Pattern p) { return text("0x%0*" PRIX32, (f->w + 3) / 4, p); }
static Text value_text(const Format *f, Pattern p) {
    if (is_nan(f, p)) return text("nan");
    if (classify(f, p) == INFINITY_VALUE) return text("%sinf", negative(f, p) ? "-" : "");
    if (is_zero(f, p)) return text("%s0", negative(f, p) ? "-" : "");
    return decimal_text(term(f, p));
}

static Text flags_text(Flags flags) {
    static const char *const names[] = { "invalid", "divbyzero", "overflow", "underflow", "inexact" };
    Text result = text("flags=");
    bool first = true;
    for (int i = 0; i < 5; i++) if (flags & (1u << i)) {
        if (!first) strcat(result.data, ",");
        strcat(result.data, names[i]);
        first = false;
    }
    if (first) strcat(result.data, "none");
    return result;
}

static Text pattern_text(const Format *f, Pattern p) {
    return text("%s %s %s", bits_text(f, p).data, hex_text(f, p).data, value_text(f, p).data);
}
static Text result_text(const Format *f, Result result) {
    return text("%s %s", pattern_text(f, result.pattern).data, flags_text(result.flags).data);
}

static Result arithmetic(const Format *f, Operation operation, Pattern a, Pattern b, Pattern c, Mode mode) {
    if (operation == SUB) { b ^= f->sign; operation = ADD; }
    Pattern inputs[] = { a, b, c };
    size_t count = operation == SQRT ? 1 : operation == FMA ? 3 : 2;
    bool nan = false;
    Flags nan_flags = 0;
    for (size_t i = 0; i < count; i++) {
        nan |= is_nan(f, inputs[i]);
        if (classify(f, inputs[i]) == SNAN) nan_flags |= INVALID;
    }
    if (nan) return (Result){ f->nan, nan_flags };
    bool ai = classify(f, a) == INFINITY_VALUE, bi = classify(f, b) == INFINITY_VALUE;
    bool sigma = negative(f, a) != negative(f, b);
    switch (operation) {
        case ADD:
            if (ai && bi && sigma) return (Result){ f->nan, INVALID };
            if (ai || bi) return (Result){ ai ? a : b, 0 };
            return rounded_sum(f, (Term[]){ term(f, a), term(f, b) }, 2, mode);
        case MUL:
            if (ai || bi) return is_zero(f, a) || is_zero(f, b)
                ? (Result){ f->nan, INVALID } : (Result){ with_sign(f, f->infinity, sigma), 0 };
            return rounded_term(f, product(term(f, a), term(f, b)), mode);
        case DIV:
            if (ai) return bi ? (Result){ f->nan, INVALID } : (Result){ with_sign(f, f->infinity, sigma), 0 };
            if (bi) return (Result){ with_sign(f, 0, sigma), 0 };
            if (is_zero(f, b)) return is_zero(f, a) ? (Result){ f->nan, INVALID }
                : (Result){ with_sign(f, f->infinity, sigma), DIVBYZERO };
            if (is_zero(f, a)) return (Result){ with_sign(f, 0, sigma), 0 };
            {
                Term x = term(f, a), y = term(f, b);
                return round_exact(f, exact(sigma, x.magnitude, x.exponent - y.exponent, y.magnitude), mode, false);
            }
        case SQRT:
            if (is_zero(f, a)) return (Result){ a, 0 };
            if (negative(f, a)) return (Result){ f->nan, INVALID };
            if (ai) return (Result){ a, 0 };
            return round_exact(f, exact_term(term(f, a)), mode, true);
        case FMA:
            if (ai || bi) {
                if (is_zero(f, a) || is_zero(f, b) || (classify(f, c) == INFINITY_VALUE && negative(f, c) != sigma)) {
                    return (Result){ f->nan, INVALID };
                }
                return (Result){ with_sign(f, f->infinity, sigma), 0 };
            }
            if (classify(f, c) == INFINITY_VALUE) return (Result){ c, 0 };
            return rounded_sum(f, (Term[]){ product(term(f, a), term(f, b)), term(f, c) }, 2, mode);
        case SUB: break;
    }
    return (Result){ 0, 0 };
}

static bool read_operand(const Format *f, const char *word, bool encoding, Operand *operand) {
    *operand = (Operand){0};
    if (!strncmp(word, "0b", 2) || !strncmp(word, "0x", 2)) {
        bool bits = word[1] == 'b';
        if (encoding || strlen(word + 2) != (size_t)(bits ? f->w : (f->w + 3) / 4)) return false;
        unsigned long value = strtoul(word + 2, NULL, bits ? 2 : 16);
        if (value >= 2 * f->sign) return false;
        operand->pattern = (Pattern)value;
        return true;
    }
    if (!strcmp(word, "nan") || !strcmp(word, "inf") || !strcmp(word, "-inf")) {
        operand->special = true;
        operand->pattern = !strcmp(word, "nan") ? f->nan : with_sign(f, f->infinity, word[0] == '-');
        return true;
    }
    bool sign = word[0] == '-';
    const char *digits = word + sign, *slash = strchr(digits, '/');
    uint64_t numerator = 0, denominator = 1;
    if (slash) {
        numerator = strtoull(digits, NULL, 10);
        denominator = strtoull(slash + 1, NULL, 10);
        if (!denominator) return false;
    } else {
        bool fractional = false;
        for (const char *p = digits; *p; p++) {
            if (*p == '.') { fractional = true; continue; }
            numerator = numerator * 10 + (unsigned)(*p - '0');
            if (fractional) denominator *= 10;
        }
    }
    operand->exact = exact(sign, numerator, 0, denominator);
    if (!encoding) operand->pattern = round_exact(f, operand->exact, RNE, false).pattern;
    return true;
}

static bool checked_operand(const Format *f, const char *word, bool encoding, Operand *operand) {
    if (read_operand(f, word, encoding, operand)) return true;
    printf("ERROR BAD OPERAND %s\n", word);
    return false;
}

static bool read_mode(const char *word, Mode *mode) {
    for (int i = 0; i < 5; i++) if (!strcmp(word, mode_names[i])) { *mode = (Mode)i; return true; }
    printf("ERROR BAD MODE %s\n", word);
    return false;
}

static Format *checked_format(const char *name) {
    Format *f = find_format(name);
    if (!f) printf("ERROR UNKNOWN FORMAT %s\n", name);
    return f;
}

static Text difference_text(const Format *f, Pattern p, Term exact_sum) {
    if (!is_finite(f, p)) return value_text(f, p);
    exact_sum.negative = !exact_sum.negative;
    Term difference = sum_terms((Term[]){ term(f, p), exact_sum }, 2, RNE);
    return fraction_text(exact_term(difference));
}

static void summation(const Format *f, const char *command, char **words, int word_count) {
    Mode mode;
    if (!read_mode(words[2], &mode)) return;
    Pattern values[20];
    size_t count = 0, left_count = 0;
    bool dot = !strcmp(command, "DOT");
    for (int i = 3; i < word_count; i++) {
        if (!strcmp(words[i], "|")) { left_count = count; continue; }
        Operand operand;
        if (!checked_operand(f, words[i], false, &operand)) return;
        values[count++] = operand.pattern;
    }
    if (dot && left_count != count - left_count) { puts("ERROR LENGTH MISMATCH"); return; }
    for (size_t i = 0; i < count; i++) if (!is_finite(f, values[i])) { puts("ERROR NOT FINITE"); return; }
    Term terms[20];
    if (dot) {
        for (size_t i = 0; i < left_count; i++) terms[i] = product(term(f, values[i]), term(f, values[left_count + i]));
        Term exact_sum = sum_terms(terms, left_count, mode);
        Result first = arithmetic(f, MUL, values[0], values[left_count], 0, mode);
        Result naive = first, chained = first;
        for (size_t i = 1; i < left_count; i++) {
            Result multiplied = arithmetic(f, MUL, values[i], values[left_count + i], 0, mode);
            Result added = arithmetic(f, ADD, naive.pattern, multiplied.pattern, 0, mode);
            naive = (Result){ added.pattern, naive.flags | multiplied.flags | added.flags };
        }
        for (size_t i = 1; i < left_count; i++) {
            Result fused = arithmetic(f, FMA, values[i], values[left_count + i], chained.pattern, mode);
            chained = (Result){ fused.pattern, chained.flags | fused.flags };
        }
        Result fused = rounded_term(f, exact_sum, mode);
        printf("DOT %s %s n=%zu\n", f->name, mode_names[mode], left_count);
        printf("NAIVE %s\n", result_text(f, naive).data);
        printf("CHAINED %s\n", result_text(f, chained).data);
        printf("EXACT %s\n", decimal_text(exact_sum).data);
        printf("FUSED %s\n", result_text(f, fused).data);
        printf("DIFF naive=%s chained=%s\n", difference_text(f, naive.pattern, exact_sum).data, difference_text(f, chained.pattern, exact_sum).data);
        return;
    }
    for (size_t i = 0; i < count; i++) terms[i] = term(f, values[i]);
    Term exact_sum = sum_terms(terms, count, mode);
    Result result = { values[0], 0 };
    Pattern compensation = 0;
    printf("%s %s %s count=%zu\n", command, f->name, mode_names[mode], count);
    for (size_t i = 1; i < count; i++) {
        if (!strcmp(command, "SUM")) {
            Result next = arithmetic(f, ADD, result.pattern, values[i], 0, mode);
            result = (Result){ next.pattern, result.flags | next.flags };
            printf("PARTIAL %zu %s\n", i + 1, result_text(f, next).data);
        } else {
            Result y = arithmetic(f, SUB, values[i], compensation, 0, mode);
            Result t = arithmetic(f, ADD, result.pattern, y.pattern, 0, mode);
            Result d = arithmetic(f, SUB, t.pattern, result.pattern, 0, mode);
            Result c = arithmetic(f, SUB, d.pattern, y.pattern, 0, mode);
            Flags step_flags = y.flags | t.flags | d.flags | c.flags;
            result = (Result){ t.pattern, result.flags | step_flags };
            compensation = c.pattern;
            printf("KSTEP %zu sum=%s comp=%s %s\n", i + 1, value_text(f, result.pattern).data,
                value_text(f, compensation).data, flags_text(step_flags).data);
        }
    }
    printf("RESULT %s\n", result_text(f, result).data);
    printf("EXACT %s\n", decimal_text(exact_sum).data);
    printf("ROUNDED %s\n", result_text(f, rounded_term(f, exact_sum, mode)).data);
    printf("DIFF %s\n", difference_text(f, result.pattern, exact_sum).data);
}

static void table_output(const Format *f) {
    if (f->w > 8) { puts("ERROR TABLE TOO LARGE"); return; }
    Pattern count = f->infinity;
    printf("TABLE %s count=%" PRIu32 "\n", f->name, count);
    for (Pattern p = 0; p < count; p++) {
        Text gap = text("-");
        if (p + 1 < count) {
            Term previous = term(f, p);
            previous.negative = true;
            gap = decimal_text(sum_terms((Term[]){ term(f, p + 1), previous }, 2, RNE));
        }
        printf("ENTRY %" PRIu32 " %s gap=%s\n", p, pattern_text(f, p).data, gap.data);
    }
    printf("MAX %s\n", pattern_text(f, count - 1).data);
    printf("MINNORMAL %s\n", pattern_text(f, f->base).data);
    printf("MINSUBNORMAL %s\n", pattern_text(f, 1).data);
    printf("EPSILON %s\n", decimal_text((Term){ false, 1, -f->m }).data);
    printf("PATTERNS finite=%" PRIu32 " infinite=2 nan=%" PRIu32 " total=%" PRIu32 "\n", 2 * count, 2 * (f->base - 1), 2 * f->sign);
}

static int64_t order_key(const Format *f, Pattern p) {
    return negative(f, p) ? -(int64_t)(p - f->sign) - 1 : (int64_t)p;
}

static const char *relation(int64_t a, int64_t b) { return a < b ? "LT" : a == b ? "EQ" : "GT"; }

static Pattern next_up(const Format *f, Pattern p) {
    if (p == f->infinity) return p;
    if (is_zero(f, p)) return 1;
    return negative(f, p) ? p - 1 : p + 1;
}

static void execute(char **words, int count) {
    const char *command = words[0];
    if (!strcmp(command, "FORMAT")) {
        if (find_format(words[1])) { printf("ERROR FORMAT EXISTS %s\n", words[1]); return; }
        int e = atoi(words[2]), m = atoi(words[3]);
        if (e < 2 || e > 5 || m < 1 || m > 10) { puts("ERROR BAD FORMAT"); return; }
        Format *f = add_format(words[1], e, m);
        printf("FORMAT %s e=%d m=%d bits=%d bias=%d emin=%d emax=%d\n", f->name, f->e, f->m, f->w, f->bias, f->emin, f->emax);
        return;
    }
    Format *f = checked_format(words[1]);
    if (!f) return;
    if (!strcmp(command, "TABLE")) { table_output(f); return; }
    if (!strcmp(command, "SUM") || !strcmp(command, "KAHAN") || !strcmp(command, "DOT")) {
        summation(f, command, words, count);
        return;
    }
    Mode mode = RNE;
    if (!strcmp(command, "CONVERT")) {
        Format *g = checked_format(words[2]);
        if (!g) return;
        Operand a;
        if (!checked_operand(f, words[3], false, &a)) return;
        if (count == 5 && !read_mode(words[4], &mode)) return;
        Result result;
        Class kind = classify(f, a.pattern);
        if (kind >= QNAN) result = (Result){ g->nan, kind == SNAN ? INVALID : 0 };
        else if (kind == INFINITY_VALUE || kind == ZERO) {
            result = (Result){ with_sign(g, kind == ZERO ? 0 : g->infinity, negative(f, a.pattern)), 0 };
        } else result = rounded_term(g, term(f, a.pattern), mode);
        printf("CONVERT %s %s %s %s\n", f->name, g->name, mode_names[mode], result_text(g, result).data);
        return;
    }
    Operand a;
    if (!checked_operand(f, words[2], !strcmp(command, "ENCODE"), &a)) return;
    if (!strcmp(command, "ENCODE")) {
        if (count == 4 && !read_mode(words[3], &mode)) return;
        Result result = a.special ? (Result){ a.pattern, 0 } : round_exact(f, a.exact, mode, false);
        Text source = a.special ? value_text(f, a.pattern) : fraction_text(a.exact);
        printf("ENCODE %s %s %s %s\n", f->name, mode_names[mode], source.data, result_text(f, result).data);
        return;
    }
    if (!strcmp(command, "DECODE")) {
        Class kind = classify(f, a.pattern);
        Pattern exponent = (a.pattern & (f->sign - 1)) >> f->m, fraction = a.pattern & (f->base - 1);
        printf("DECODE %s %s %s %s sign=%d\n", f->name, bits_text(f, a.pattern).data,
            hex_text(f, a.pattern).data, class_names[kind], negative(f, a.pattern));
        if (kind <= NORMAL) {
            Term value = term(f, a.pattern);
            printf("FIELDS exponent=%" PRIu32 " fraction=%" PRIu32 " unbiased=%d significand=%d.%s\n",
                exponent, fraction, value.exponent + f->m, kind == NORMAL, binary_text(fraction, f->m).data);
            printf("VALUE %s %s\n", fraction_text(exact_term(value)).data, value_text(f, a.pattern).data);
        } else if (kind == INFINITY_VALUE) {
            printf("FIELDS exponent=%" PRIu32 " fraction=%" PRIu32 "\n", exponent, fraction);
        } else {
            printf("FIELDS exponent=%" PRIu32 " fraction=%" PRIu32 " payload=%" PRIu32 "\n", exponent, fraction, fraction % (f->base / 2));
        }
        return;
    }
    if (!strcmp(command, "COMPARE")) {
        Operand b;
        if (!checked_operand(f, words[3], false, &b)) return;
        int64_t ak = order_key(f, a.pattern), bk = order_key(f, b.pattern);
        const char *numeric = is_nan(f, a.pattern) || is_nan(f, b.pattern) ? "UN"
            : is_zero(f, a.pattern) && is_zero(f, b.pattern) ? "EQ" : relation(ak, bk);
        Flags flags = classify(f, a.pattern) == SNAN || classify(f, b.pattern) == SNAN ? INVALID : 0;
        printf("COMPARE %s %s %s %s total=%s %s\n", f->name, hex_text(f, a.pattern).data,
            hex_text(f, b.pattern).data, numeric, relation(ak, bk), flags_text(flags).data);
        return;
    }
    if (!strcmp(command, "TOINT")) {
        const IntegerType *type = NULL;
        for (size_t i = 0; i < sizeof integer_types / sizeof *integer_types; i++) {
            if (!strcmp(words[3], integer_types[i].name)) type = &integer_types[i];
        }
        if (!type) { printf("ERROR BAD TYPE %s\n", words[3]); return; }
        if (count == 5 && !read_mode(words[4], &mode)) return;
        bool invalid = !is_finite(f, a.pattern);
        int64_t result = 0;
        Flags flags = 0;
        if (!invalid) {
            Exact value = exact_term(term(f, a.pattern));
            Quantized divided = quantize(value, 0, false);
            uint64_t magnitude = divided.whole + increment(divided, mode, value.negative);
            result = value.negative ? -(int64_t)magnitude : (int64_t)magnitude;
            invalid = result < type->minimum || result > type->maximum;
            flags = divided.inexact ? INEXACT : 0;
        }
        if (invalid) printf("TOINT %s %s %s invalid flags=invalid\n", f->name, type->name, mode_names[mode]);
        else printf("TOINT %s %s %s %" PRId64 " %s\n", f->name, type->name, mode_names[mode], result, flags_text(flags).data);
        return;
    }
    if (!strcmp(command, "NEXTUP") || !strcmp(command, "NEXTDOWN") || !strcmp(command, "ULP")) {
        Result result = { 0, 0 };
        Class kind = classify(f, a.pattern);
        if (kind >= QNAN) result = (Result){ f->nan, kind == SNAN ? INVALID : 0 };
        else if (!strcmp(command, "ULP")) {
            result.pattern = kind == INFINITY_VALUE ? f->infinity
                : rounded_term(f, (Term){ false, 1, term(f, a.pattern).exponent }, RNE).pattern;
        } else if (!strcmp(command, "NEXTUP")) result.pattern = next_up(f, a.pattern);
        else result.pattern = next_up(f, a.pattern ^ f->sign) ^ f->sign;
        printf("%s %s %s\n", command, f->name, result_text(f, result).data);
        return;
    }
    for (int i = 0; i < 6; i++) if (!strcmp(command, operation_names[i])) {
        Operation operation = (Operation)i;
        int arity = operation == SQRT ? 1 : operation == FMA ? 3 : 2;
        Operand b = {0}, c = {0};
        if (arity >= 2 && !checked_operand(f, words[3], false, &b)) return;
        if (arity == 3 && !checked_operand(f, words[4], false, &c)) return;
        if (count == arity + 3 && !read_mode(words[arity + 2], &mode)) return;
        Result result = arithmetic(f, operation, a.pattern, b.pattern, c.pattern, mode);
        printf("%s %s %s %s\n", command, f->name, mode_names[mode], result_text(f, result).data);
        return;
    }
}

int main(void) {
    add_format("HALF", 5, 10);
    add_format("E5M2", 5, 2);
    add_format("E4M3", 4, 3);
    char line[1024];
    if (!fgets(line, sizeof line, stdin)) return 0;
    int commands = atoi(line);
    for (int i = 0; i < commands && fgets(line, sizeof line, stdin); i++) {
        char *words[32];
        int count = 0;
        for (char *word = strtok(line, " \r\n"); word; word = strtok(NULL, " \r\n")) words[count++] = word;
        execute(words, count);
    }
    return 0;
}
