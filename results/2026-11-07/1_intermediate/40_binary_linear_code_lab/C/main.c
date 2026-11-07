#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef uint32_t Word;
typedef struct { Word rows[32]; int count; } Matrix;
typedef struct { int n; Matrix g, h; Word polynomial; } Code;
typedef struct { char name[9]; Code code; } Entry;
typedef struct { char text[31]; } Bits;
typedef struct { Word quotient, remainder; } Division;
typedef struct { Word words[4096]; int count; } Leaders;
typedef struct { Word syndrome, leader; } Coset;

typedef enum {
    GEN, PCHECK, HAMMING, SIMPLEX, REPETITION, PARITY, RM, CYCLIC,
    DUAL, EXTEND, PUNCTURE, SHORTEN, AUGMENT, EXPURGATE, PERMUTE,
    DIRECTSUM, UUV, PRODUCT, LIST, DELETE, SHOW, INFO, SYSTEMATIC,
    WEIGHTS, COVERING, BURST, TRELLIS, STDARRAY, EQUAL, ENCODE,
    SYNDROME, DECODE, BOUNDED, COSET, ERASURE, INTERLEAVE, CRC,
    CRCCHECK, FACTOR, MACWILLIAMS, BOUNDS, COMMAND_COUNT
} Command;

typedef struct { const char *name, *types; int minimum, maximum; } Format;
static const Format formats[] = {
    {"GEN", "NV", 2, 25}, {"PCHECK", "NV", 2, 25},
    {"HAMMING", "NI", 2, 2}, {"SIMPLEX", "NI", 2, 2},
    {"REPETITION", "NI", 2, 2}, {"PARITY", "NI", 2, 2},
    {"RM", "NII", 3, 3}, {"CYCLIC", "NIV", 3, 3},
    {"DUAL", "NA", 2, 2}, {"EXTEND", "NA", 2, 2},
    {"PUNCTURE", "NAI", 3, 3}, {"SHORTEN", "NAI", 3, 3},
    {"AUGMENT", "NA", 2, 2}, {"EXPURGATE", "NA", 2, 2},
    {"PERMUTE", "NAI", 3, 26}, {"DIRECTSUM", "NAB", 3, 3},
    {"UUV", "NAB", 3, 3}, {"PRODUCT", "NAB", 3, 3},
    {"LIST", "", 0, 0}, {"DELETE", "A", 1, 1},
    {"SHOW", "A", 1, 1}, {"INFO", "A", 1, 1},
    {"SYSTEMATIC", "A", 1, 1}, {"WEIGHTS", "A", 1, 1},
    {"COVERING", "A", 1, 1}, {"BURST", "A", 1, 1},
    {"TRELLIS", "A", 1, 1}, {"STDARRAY", "A", 1, 1},
    {"EQUAL", "AB", 2, 2}, {"ENCODE", "AV", 2, 2},
    {"SYNDROME", "AV", 2, 2}, {"DECODE", "AV", 2, 2},
    {"BOUNDED", "AIV", 3, 3}, {"COSET", "AV", 2, 2},
    {"ERASURE", "AX", 2, 2}, {"INTERLEAVE", "AIIV", 4, 11},
    {"CRC", "VV", 2, 2}, {"CRCCHECK", "VV", 2, 2},
    {"FACTOR", "I", 1, 1}, {"MACWILLIAMS", "II", 2, 26},
    {"BOUNDS", "II", 2, 2}
};

static Entry registry[500];
static int registry_count;
static int64_t combinations[25][25];
static jmp_buf command_error;

static void fail(const char *message) {
    printf("error: %s\n", message);
    longjmp(command_error, 1);
}

static void require(bool condition, const char *message) {
    if (!condition) fail(message);
}

static void check_dimension(int n, int k) {
    if (k < 1 || k > 12 || n - k < 1 || n - k > 12) {
        printf("error: bad dimension %d %d\n", n, k);
        longjmp(command_error, 1);
    }
}

static bool letter(char c) {
    return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z');
}

static bool valid_word(const char *s, char type) {
    size_t length = strlen(s);
    if (type == 'N' || type == 'A' || type == 'B') {
        if (length > 8 || !letter(s[0])) return false;
        for (size_t i = 1; i < length; ++i)
            if (!letter(s[i]) && (s[i] < '0' || s[i] > '9')) return false;
    } else if (type == 'I') {
        if (length > 4 || (length > 1 && s[0] == '0')) return false;
        for (size_t i = 0; i < length; ++i)
            if (s[i] < '0' || s[i] > '9') return false;
    } else {
        if (length > 30) return false;
        for (size_t i = 0; i < length; ++i)
            if (s[i] != '0' && s[i] != '1' && !(type == 'X' && s[i] == '?'))
                return false;
    }
    return length != 0;
}

static int find_code(const char *name) {
    for (int i = 0; i < registry_count; ++i)
        if (strcmp(registry[i].name, name) == 0) return i;
    return -1;
}

static Word mask(int n) { return (UINT32_C(1) << n) - 1; }
static Word bit(int n, int column) { return UINT32_C(1) << (n - column - 1); }
static const char *yes(bool value) { return value ? "yes" : "no"; }
static const char *encoder(const Code *code) { return code->polynomial ? "polynomial" : "matrix"; }

static int weight(Word value) {
    int count = 0;
    for (; value; value &= value - 1) ++count;
    return count;
}

static int length(Word value) {
    int result = 0;
    for (; value; value >>= 1) ++result;
    return result;
}

static Word parse_bits(const char *s) {
    Word result = 0;
    for (; *s; ++s) result = (result << 1) | (Word)(*s - '0');
    return result;
}

static Bits bits(Word value, int n) {
    Bits result;
    for (int i = 0; i < n; ++i) result.text[i] = (value & bit(n, i)) ? '1' : '0';
    result.text[n] = '\0';
    return result;
}

static Division divide(Word value, Word divisor) {
    Division result = {0, value};
    int degree = length(divisor) - 1;
    while (result.remainder && length(result.remainder) - 1 >= degree) {
        int shift = length(result.remainder) - 1 - degree;
        result.quotient ^= UINT32_C(1) << shift;
        result.remainder ^= divisor << shift;
    }
    return result;
}

static Matrix basis(Matrix source, int n) {
    Matrix result = {0};
    Word pivots[32] = {0};
    for (int i = 0; i < source.count; ++i) {
        Word row = source.rows[i];
        for (int j = n - 1; j >= 0; --j) {
            if (!(row & (UINT32_C(1) << j))) continue;
            if (pivots[j]) row ^= pivots[j];
            else {
                pivots[j] = row;
                result.rows[result.count++] = source.rows[i];
                break;
            }
        }
    }
    return result;
}

static int reduce(Matrix *matrix, int n, int pivots[32]) {
    int rank = 0;
    for (int column = 0; column < n; ++column) {
        Word flag = bit(n, column);
        int row = rank;
        while (row < matrix->count && !(matrix->rows[row] & flag)) ++row;
        if (row == matrix->count) continue;
        Word temporary = matrix->rows[rank];
        matrix->rows[rank] = matrix->rows[row];
        matrix->rows[row] = temporary;
        for (int i = 0; i < matrix->count; ++i)
            if (i != rank && (matrix->rows[i] & flag)) matrix->rows[i] ^= matrix->rows[rank];
        pivots[rank++] = column;
    }
    matrix->count = rank;
    return rank;
}

static Matrix null_space(Matrix source, int n) {
    int pivots[32];
    int rank = reduce(&source, n, pivots);
    Matrix result = {0};
    for (int column = 0, next = 0; column < n; ++column) {
        if (next < rank && pivots[next] == column) { ++next; continue; }
        Word row = bit(n, column);
        for (int i = 0; i < rank; ++i)
            if (source.rows[i] & bit(n, column)) row |= bit(n, pivots[i]);
        result.rows[result.count++] = row;
    }
    return result;
}

static Matrix reed_muller(int r, int m) {
    Matrix result = {0};
    if (r == 0) {
        result.rows[result.count++] = mask(1 << m);
    } else {
        int half = 1 << (m - 1);
        Matrix first = reed_muller(r < m ? r : m - 1, m - 1);
        Matrix second = reed_muller(r - 1, m - 1);
        for (int i = 0; i < first.count; ++i)
            result.rows[result.count++] = (first.rows[i] << half) | first.rows[i];
        for (int i = 0; i < second.count; ++i) result.rows[result.count++] = second.rows[i];
    }
    return result;
}

static Word remove_bit(Word row, int n, int position) {
    int low = n - position;
    return ((row >> (low + 1)) << low) | (row & mask(low));
}

static Code construct(Command command, char **args, int count, const Code *a, const Code *b) {
    Code code = {0};
    bool explicit_h = false;
    if (command == GEN || command == PCHECK) {
        code.n = (int)strlen(args[1]);
        Matrix source = {0};
        for (int i = 1; i < count; ++i) {
            require((int)strlen(args[i]) == code.n, "bad length");
            source.rows[source.count++] = parse_bits(args[i]);
        }
        if (command == GEN) code.g = basis(source, code.n);
        else {
            code.h = basis(source, code.n);
            code.g = null_space(code.h, code.n);
            explicit_h = true;
        }
    } else if (command == HAMMING || command == SIMPLEX) {
        int r = atoi(args[1]);
        require(r >= 2 && r <= 4, "bad parameter");
        code.n = (1 << r) - 1;
        Matrix h = {0};
        for (int i = 0; i < r; ++i) {
            Word row = 0;
            for (int j = 1; j <= code.n; ++j) row = (row << 1) | ((j >> (r - i - 1)) & 1);
            h.rows[h.count++] = row;
        }
        if (command == SIMPLEX) code.g = h;
        else { code.h = h; code.g = null_space(h, code.n); explicit_h = true; }
    } else if (command == REPETITION || command == PARITY) {
        code.n = atoi(args[1]);
        require(code.n >= 2 && code.n <= 24, "bad parameter");
        if (command == REPETITION) code.g.rows[code.g.count++] = mask(code.n);
        else for (int i = 0; i < code.n - 1; ++i) code.g.rows[code.g.count++] = bit(code.n, i) | 1;
    } else if (command == RM) {
        int r = atoi(args[1]), m = atoi(args[2]);
        require(m >= 1 && m <= 4 && r <= m, "bad parameter");
        code.n = 1 << m;
        code.g = reed_muller(r, m);
    } else if (command == CYCLIC) {
        code.n = atoi(args[1]);
        int d = (int)strlen(args[2]) - 1;
        require(code.n >= 2 && code.n <= 24 && args[2][0] == '1' && d >= 1 && d < code.n,
                "bad parameter");
        code.polynomial = parse_bits(args[2]);
        require(divide((UINT32_C(1) << code.n) | 1, code.polynomial).remainder == 0, "not a divisor");
        int k = code.n - d;
        for (int i = 0; i < k; ++i) code.g.rows[code.g.count++] = code.polynomial << (k - i - 1);
        code.h.count = d;
        for (int j = 0; j < code.n; ++j) {
            Word remainder = divide(bit(code.n, j), code.polynomial).remainder;
            for (int i = 0; i < d; ++i)
                code.h.rows[i] = (code.h.rows[i] << 1) | ((remainder >> (d - i - 1)) & 1);
        }
        explicit_h = true;
    } else if (command == DUAL) {
        code.n = a->n; code.g = a->h; code.h = a->g; explicit_h = true;
    } else if (command == EXTEND) {
        code.n = a->n + 1;
        for (int i = 0; i < a->g.count; ++i)
            code.g.rows[code.g.count++] = (a->g.rows[i] << 1) | (weight(a->g.rows[i]) & 1);
    } else if (command == PUNCTURE || command == SHORTEN || command == EXPURGATE) {
        int position = command == EXPURGATE ? 0 : atoi(args[2]);
        if (command != EXPURGATE) require(position >= 1 && position <= a->n, "bad position");
        code.n = a->n - (command != EXPURGATE);
        int removed = -1;
        if (command != PUNCTURE) {
            for (int i = 0; i < a->g.count; ++i) {
                bool selected = command == EXPURGATE ? (weight(a->g.rows[i]) & 1) != 0
                    : (a->g.rows[i] & bit(a->n, position - 1)) != 0;
                if (selected) { removed = i; break; }
            }
        }
        for (int i = 0; i < a->g.count; ++i) {
            if (i == removed) continue;
            Word row = a->g.rows[i];
            if (removed >= 0 && (command == EXPURGATE ? (weight(row) & 1) != 0
                    : (row & bit(a->n, position - 1)) != 0)) row ^= a->g.rows[removed];
            if (command != EXPURGATE) row = remove_bit(row, a->n, position);
            code.g.rows[code.g.count++] = row;
        }
        if (command == PUNCTURE) code.g = basis(code.g, code.n);
    } else if (command == AUGMENT) {
        code.n = a->n; code.g = a->g;
        code.g.rows[code.g.count++] = mask(code.n);
        code.g = basis(code.g, code.n);
    } else if (command == PERMUTE) {
        require(count - 2 == a->n, "bad permutation");
        bool used[25] = {false};
        for (int i = 2; i < count; ++i) {
            int position = atoi(args[i]);
            require(position >= 1 && position <= a->n && !used[position], "bad permutation");
            used[position] = true;
        }
        code.n = a->n;
        for (int i = 0; i < a->g.count; ++i) {
            Word row = 0;
            for (int j = 2; j < count; ++j)
                row = (row << 1) | ((a->g.rows[i] & bit(a->n, atoi(args[j]) - 1)) != 0);
            code.g.rows[code.g.count++] = row;
        }
    } else {
        if (command == UUV) require(a->n == b->n, "bad length");
        code.n = command == PRODUCT ? a->n * b->n : a->n + b->n;
        int k = command == PRODUCT ? a->g.count * b->g.count : a->g.count + b->g.count;
        check_dimension(code.n, k);
        if (command == PRODUCT) {
            for (int i = 0; i < a->g.count; ++i) for (int j = 0; j < b->g.count; ++j) {
                Word row = 0;
                for (int column = 0; column < a->n; ++column)
                    row = (row << b->n) | ((a->g.rows[i] & bit(a->n, column)) ? b->g.rows[j] : 0);
                code.g.rows[code.g.count++] = row;
            }
        } else {
            for (int i = 0; i < a->g.count; ++i)
                code.g.rows[code.g.count++] = (a->g.rows[i] << b->n) | (command == UUV ? a->g.rows[i] : 0);
            for (int i = 0; i < b->g.count; ++i) code.g.rows[code.g.count++] = b->g.rows[i];
        }
    }
    check_dimension(code.n, code.g.count);
    if (!explicit_h) code.h = null_space(code.g, code.n);
    return code;
}

static Word syndrome(const Code *code, Word row) {
    Word result = 0;
    for (int i = 0; i < code->h.count; ++i) result = (result << 1) | (weight(row & code->h.rows[i]) & 1);
    return result;
}

static Word encode(const Code *code, Word message) {
    if (code->polynomial) {
        Word shifted = message << code->h.count;
        return shifted | divide(shifted, code->polynomial).remainder;
    }
    Word result = 0;
    for (int i = 0; i < code->g.count; ++i)
        if (message & bit(code->g.count, i)) result ^= code->g.rows[i];
    return result;
}

static Word message_of(const Code *code, Word word) {
    for (Word message = 0; message < (UINT32_C(1) << code->g.count); ++message)
        if (encode(code, message) == word) return message;
    return 0;
}

static int span(Matrix matrix, Word words[4096]) {
    int count = 1;
    words[0] = 0;
    for (int i = 0; i < matrix.count; ++i) {
        for (int j = 0; j < count; ++j) words[count + j] = words[j] ^ matrix.rows[i];
        count *= 2;
    }
    return count;
}

static Leaders leaders(const Code *code) {
    Leaders result;
    result.count = 1 << code->h.count;
    for (int i = 0; i < result.count; ++i) result.words[i] = UINT32_MAX;
    result.words[0] = 0;
    int found = 1;
    Word limit = UINT32_C(1) << code->n;
    for (int w = 1; w <= code->n; ++w) {
        for (Word row = mask(w); row < limit;) {
            Word s = syndrome(code, row);
            if (result.words[s] == UINT32_MAX) {
                result.words[s] = row;
                if (++found == result.count) return result;
            }
            Word lowest = row & (0u - row), next = row + lowest;
            row = next | (((next ^ row) >> 2) / lowest);
        }
    }
    return result;
}

static void distribution(Matrix matrix, Word offset, int64_t counts[25]) {
    Word words[4096];
    int count = span(matrix, words);
    memset(counts, 0, 25 * sizeof(*counts));
    for (int i = 0; i < count; ++i) ++counts[weight(words[i] ^ offset)];
}

static void print_distribution(const int64_t counts[25], int n) {
    for (int i = 0; i <= n; ++i) if (counts[i]) printf(" %d:%" PRId64, i, counts[i]);
    putchar('\n');
}

static int64_t gcd(int64_t a, int64_t b) {
    if (a < 0) a = -a;
    while (b) { int64_t remainder = a % b; a = b; b = remainder; }
    return a;
}

static int64_t choose(int n, int k) { return k < 0 || k > n ? 0 : combinations[n][k]; }

static int64_t krawtchouk(int n, int j, int x) {
    int64_t sum = 0;
    for (int y = 0; y <= j; ++y) {
        int64_t term = choose(x, y) * choose(n - x, j - y);
        sum += y % 2 ? -term : term;
    }
    return sum;
}

static void print_matrix(char label, Matrix matrix, int n) {
    for (int i = 0; i < matrix.count; ++i) printf("%c %s\n", label, bits(matrix.rows[i], n).text);
}

static void systematic(const char *name, const Code *code) {
    Matrix matrix = code->g;
    int permutation[24];
    for (int i = 0; i < code->n; ++i) permutation[i] = i + 1;
    for (int r = 0; r < matrix.count; ++r) {
        int column = r, row;
        for (;;) {
            row = r;
            while (row < matrix.count && !(matrix.rows[row] & bit(code->n, column))) ++row;
            if (row < matrix.count) break;
            ++column;
        }
        if (column != r) {
            Word left = bit(code->n, r), right = bit(code->n, column);
            for (int i = 0; i < matrix.count; ++i)
                if (!!(matrix.rows[i] & left) != !!(matrix.rows[i] & right)) matrix.rows[i] ^= left | right;
            int temporary = permutation[r]; permutation[r] = permutation[column]; permutation[column] = temporary;
        }
        Word temporary = matrix.rows[r]; matrix.rows[r] = matrix.rows[row]; matrix.rows[row] = temporary;
        for (int i = 0; i < matrix.count; ++i)
            if (i != r && (matrix.rows[i] & bit(code->n, r))) matrix.rows[i] ^= matrix.rows[r];
    }
    printf("systematic %s perm", name);
    for (int i = 0; i < code->n; ++i) printf(" %d", permutation[i]);
    putchar('\n');
    print_matrix('G', matrix, code->n);
    for (int j = 0; j < code->h.count; ++j) {
        Word row = 0;
        for (int i = 0; i < matrix.count; ++i)
            row = (row << 1) | ((matrix.rows[i] & bit(code->n, matrix.count + j)) != 0);
        row = (row << code->h.count) | bit(code->h.count, j);
        printf("H %s\n", bits(row, code->n).text);
    }
}

static int burst_length(Word row) {
    while (!(row & 1)) row >>= 1;
    return length(row);
}

static int burst_correction(const Code *code) {
    bool seen[4096] = {true};
    for (int size = 1; size <= code->n; ++size) {
        Word variants = size == 1 ? 1 : UINT32_C(1) << (size - 2);
        for (int offset = 0; offset <= code->n - size; ++offset) for (Word middle = 0; middle < variants; ++middle) {
            Word row = size == 1 ? 1 : (UINT32_C(1) << (size - 1)) | (middle << 1) | 1;
            Word s = syndrome(code, row << offset);
            if (seen[s]) return size - 1;
            seen[s] = true;
        }
    }
    return code->n;
}

static int compare_entries(const void *left, const void *right) {
    const Entry *const *a = left, *const *b = right;
    return strcmp((*a)->name, (*b)->name);
}

static int compare_words(const void *left, const void *right) {
    Word a = *(const Word *)left, b = *(const Word *)right;
    return (a > b) - (a < b);
}

static int compare_cosets(const void *left, const void *right) {
    const Coset *a = left, *b = right;
    int difference = weight(a->leader) - weight(b->leader);
    return difference ? difference : (a->leader > b->leader) - (a->leader < b->leader);
}

static void decoded(const char *prefix, const char *name, const Code *code, Word word, Word error) {
    Word corrected = word ^ error;
    printf("%s %s codeword %s message %s error %s weight %d\n", prefix, name,
           bits(corrected, code->n).text, bits(message_of(code, corrected), code->g.count).text,
           bits(error, code->n).text, weight(error));
}

static void execute(Command command, char **args, int count) {
    const Format *format = &formats[command];
    require(count >= format->minimum && count <= format->maximum, "bad arguments");
    int type_count = (int)strlen(format->types);
    for (int i = 0; i < count; ++i)
        require(valid_word(args[i], format->types[i < type_count ? i : type_count - 1]), "bad arguments");
    const Code *a = NULL, *b = NULL;
    for (int i = 0; i < type_count; ++i) {
        char type = format->types[i];
        if (type != 'A' && type != 'B') continue;
        int index = find_code(args[i]);
        if (index < 0) {
            printf("error: no code %s\n", args[i]);
            longjmp(command_error, 1);
        }
        if (type == 'A') a = &registry[index].code; else b = &registry[index].code;
    }
    if (command <= PRODUCT) {
        Code code = construct(command, args, count, a, b);
        int index = find_code(args[0]);
        bool replacing = index >= 0;
        if (!replacing) { index = registry_count++; strcpy(registry[index].name, args[0]); }
        registry[index].code = code;
        printf("%s %s n %d k %d\n", replacing ? "redefined" : "defined", args[0], code.n, code.g.count);
        return;
    }
    switch (command) {
        case LIST: {
            const Entry *sorted[500];
            for (int i = 0; i < registry_count; ++i) sorted[i] = &registry[i];
            qsort(sorted, registry_count, sizeof(*sorted), compare_entries);
            printf("codes %d\n", registry_count);
            for (int i = 0; i < registry_count; ++i)
                printf("%s n %d k %d encoder %s\n", sorted[i]->name, sorted[i]->code.n,
                       sorted[i]->code.g.count, encoder(&sorted[i]->code));
            break;
        }
        case DELETE: {
            int index = find_code(args[0]);
            memmove(registry + index, registry + index + 1, (registry_count - index - 1) * sizeof(*registry));
            --registry_count;
            printf("deleted %s\n", args[0]);
            break;
        }
        case SHOW:
            printf("code %s n %d k %d encoder %s\n", args[0], a->n, a->g.count, encoder(a));
            if (a->polynomial) printf("poly g %s h %s\n", bits(a->polynomial, a->h.count + 1).text,
                bits(divide((UINT32_C(1) << a->n) | 1, a->polynomial).quotient, a->g.count + 1).text);
            print_matrix('G', a->g, a->n); print_matrix('H', a->h, a->n);
            break;
        case INFO: {
            Word words[4096], generator = UINT32_MAX;
            int total = span(a->g, words), distance = a->n;
            for (int i = 1; i < total; ++i) {
                int w = weight(words[i]);
                if (w < distance) distance = w;
                if (words[i] < generator) generator = words[i];
            }
            int t = (distance - 1) / 2;
            int64_t volume = 0, divisor = gcd(a->g.count, a->n);
            for (int i = 0; i <= t; ++i) volume += choose(a->n, i);
            bool cyclic = true;
            for (int i = 0; i < a->g.count; ++i) {
                Word row = a->g.rows[i];
                if (syndrome(a, ((row << 1) & mask(a->n)) | (row >> (a->n - 1)))) cyclic = false;
            }
            printf("info %s n %d k %d rate %" PRId64 "/%" PRId64 " d %d t %d perfect %s mds %s cyclic %s\n",
                   args[0], a->n, a->g.count, a->g.count / divisor, a->n / divisor, distance, t,
                   yes(volume == (INT64_C(1) << a->h.count)), yes(distance == a->h.count + 1),
                   cyclic ? bits(generator, length(generator)).text : "no");
            break;
        }
        case SYSTEMATIC: systematic(args[0], a); break;
        case WEIGHTS: {
            int64_t primary[25], dual[25];
            distribution(a->g, 0, primary); distribution(a->h, 0, dual);
            printf("weights %s", args[0]); print_distribution(primary, a->n);
            printf("dual %s", args[0]); print_distribution(dual, a->n);
            bool orthogonal = true, formal = true;
            for (int i = 0; i < a->g.count; ++i) for (int j = 0; j < a->g.count; ++j)
                if (weight(a->g.rows[i] & a->g.rows[j]) & 1) orthogonal = false;
            for (int i = 0; i <= a->n; ++i) if (primary[i] != dual[i]) formal = false;
            printf("duality %s self-orthogonal %s self-dual %s formally-self-dual %s\n",
                   args[0], yes(orthogonal), yes(orthogonal && a->n == 2 * a->g.count), yes(formal));
            break;
        }
        case COVERING: {
            Leaders table = leaders(a);
            int counts[25] = {0}, radius = 0;
            for (int i = 0; i < table.count; ++i) {
                int w = weight(table.words[i]); ++counts[w];
                if (w > radius) radius = w;
            }
            printf("covering %s radius %d leaders", args[0], radius);
            for (int i = 0; i <= radius; ++i) printf(" %d:%d", i, counts[i]);
            putchar('\n');
            break;
        }
        case BURST: {
            Word words[4096];
            int total = span(a->g, words), minimum = a->n;
            for (int i = 1; i < total; ++i) {
                int size = burst_length(words[i]);
                if (size < minimum) minimum = size;
            }
            printf("burst %s detect %d correct %d\n", args[0], minimum - 1, burst_correction(a));
            break;
        }
        case TRELLIS: {
            printf("trellis %s profile", args[0]);
            int maximum = 0;
            for (int i = 0; i <= a->n; ++i) {
                Matrix prefix = a->g, suffix = a->g;
                for (int j = 0; j < a->g.count; ++j) {
                    prefix.rows[j] >>= a->n - i;
                    suffix.rows[j] &= mask(a->n - i);
                }
                int states = basis(prefix, i).count + basis(suffix, a->n - i).count - a->g.count;
                if (states > maximum) maximum = states;
                printf(" %d", states);
            }
            printf(" max %d\n", maximum);
            break;
        }
        case STDARRAY: {
            require(a->h.count <= 6 && a->g.count <= 4, "too large");
            Leaders table = leaders(a);
            Coset ordered[64];
            for (int i = 0; i < table.count; ++i) ordered[i] = (Coset){(Word)i, table.words[i]};
            qsort(ordered, table.count, sizeof(*ordered), compare_cosets);
            Word words[4096];
            int total = span(a->g, words);
            qsort(words, total, sizeof(*words), compare_words);
            printf("stdarray %s rows %d columns %d\n", args[0], table.count, total);
            for (int i = 0; i < table.count; ++i) {
                printf("%s:", bits(ordered[i].syndrome, a->h.count).text);
                for (int j = 0; j < total; ++j) printf(" %s", bits(ordered[i].leader ^ words[j], a->n).text);
                putchar('\n');
            }
            break;
        }
        case EQUAL: {
            if (a->n != b->n) printf("equal %s %s no lengths %d %d\n", args[0], args[1], a->n, b->n);
            else {
                Matrix combined = a->g;
                for (int i = 0; i < b->g.count; ++i) combined.rows[combined.count++] = b->g.rows[i];
                int common = a->g.count + b->g.count - basis(combined, a->n).count;
                printf("equal %s %s %s intersection %d\n", args[0], args[1],
                       yes(a->g.count == common && b->g.count == common), common);
            }
            break;
        }
        case ENCODE:
            require((int)strlen(args[1]) == a->g.count, "bad length");
            printf("encode %s message %s codeword %s\n", args[0], args[1], bits(encode(a, parse_bits(args[1])), a->n).text);
            break;
        case SYNDROME: {
            require((int)strlen(args[1]) == a->n, "bad length");
            Word s = syndrome(a, parse_bits(args[1]));
            printf("syndrome %s %s codeword %s\n", args[0], bits(s, a->h.count).text, yes(s == 0));
            break;
        }
        case DECODE: case BOUNDED: case COSET: {
            const char *source = args[command == BOUNDED ? 2 : 1];
            require((int)strlen(source) == a->n, "bad length");
            Word word = parse_bits(source), s = syndrome(a, word);
            Leaders table = leaders(a);
            Word error = table.words[s];
            if (command == COSET) {
                int64_t counts[25]; distribution(a->g, word, counts);
                printf("coset %s syndrome %s leader %s weights", args[0], bits(s, a->h.count).text, bits(error, a->n).text);
                print_distribution(counts, a->n);
            } else if (command == BOUNDED && weight(error) > atoi(args[1]))
                printf("bounded %s fail weight %d\n", args[0], weight(error));
            else decoded(command == BOUNDED ? "bounded" : "decode", args[0], a, word, error);
            break;
        }
        case ERASURE: {
            require((int)strlen(args[1]) == a->n, "bad length");
            Word known = 0, value = 0, candidate = 0, message = 0;
            int erased = 0, candidates = 0;
            for (int i = 0; i < a->n; ++i) {
                if (args[1][i] == '?') ++erased;
                else { known |= bit(a->n, i); if (args[1][i] == '1') value |= bit(a->n, i); }
            }
            for (Word u = 0; u < (UINT32_C(1) << a->g.count); ++u) {
                Word word = encode(a, u);
                if ((word & known) == value) { ++candidates; candidate = word; message = u; }
            }
            printf("erasure %s erased %d candidates %d", args[0], erased, candidates);
            if (candidates == 1) printf(" codeword %s message %s", bits(candidate, a->n).text, bits(message, a->g.count).text);
            putchar('\n');
            break;
        }
        case INTERLEAVE: {
            int depth = count - 3, start = atoi(args[1]), size = atoi(args[2]);
            for (int i = 3; i < count; ++i) require((int)strlen(args[i]) == a->g.count, "bad length");
            require(start >= 1 && size >= 1 && start + size - 1 <= depth * a->n, "bad burst");
            Word sent_rows[8], received_rows[8] = {0};
            char sent[193], received[193];
            for (int i = 0; i < depth; ++i) sent_rows[i] = encode(a, parse_bits(args[i + 3]));
            for (int column = 0; column < a->n; ++column) for (int i = 0; i < depth; ++i) {
                int position = column * depth + i;
                bool value = (sent_rows[i] & bit(a->n, column)) != 0;
                sent[position] = value ? '1' : '0';
                if (position >= start - 1 && position < start - 1 + size) value = !value;
                received[position] = value ? '1' : '0';
                received_rows[i] = (received_rows[i] << 1) | value;
            }
            sent[depth * a->n] = received[depth * a->n] = '\0';
            printf("interleave %s depth %d burst %d %d\nsent %s\nrecv %s\n", args[0], depth, start, size, sent, received);
            Leaders table = leaders(a);
            int correct = 0;
            for (int i = 0; i < depth; ++i) {
                Word error = table.words[syndrome(a, received_rows[i])];
                Word message = message_of(a, received_rows[i] ^ error);
                bool ok = message == parse_bits(args[i + 3]);
                correct += ok;
                printf("row %d errors %d corrected %d message %s %s\n", i + 1,
                       weight(received_rows[i] ^ sent_rows[i]), weight(error), bits(message, a->g.count).text, ok ? "ok" : "wrong");
            }
            printf("result ok %d wrong %d\n", correct, depth - correct);
            break;
        }
        case CRC: case CRCCHECK: {
            int d = (int)strlen(args[0]) - 1;
            require(args[0][0] == '1' && d >= 1 && d <= 16, "bad parameter");
            Word polynomial = parse_bits(args[0]), value = parse_bits(args[1]);
            if (command == CRC) {
                require((int)strlen(args[1]) + d <= 30, "bad length");
                Word remainder = divide(value << d, polynomial).remainder;
                printf("crc remainder %s frame %s%s\n", bits(remainder, d).text, args[1], bits(remainder, d).text);
            } else {
                Word remainder = divide(value, polynomial).remainder;
                printf("crccheck %s remainder %s\n", remainder ? "error" : "ok", bits(remainder, d).text);
            }
            break;
        }
        case FACTOR: {
            int n = atoi(args[0]);
            require(n >= 1 && n <= 24, "bad parameter");
            Word remaining = (UINT32_C(1) << n) | 1;
            int64_t divisors = 1;
            printf("factor %d", n);
            for (Word factor = 3; 2 * (length(factor) - 1) <= length(remaining) - 1; factor += 2) {
                int exponent = 0;
                Division result = divide(remaining, factor);
                while (!result.remainder) {
                    ++exponent; remaining = result.quotient;
                    result = divide(remaining, factor);
                }
                if (exponent) {
                    printf(" %s^%d", bits(factor, length(factor)).text, exponent);
                    divisors *= exponent + 1;
                }
            }
            if (remaining != 1) { printf(" %s^1", bits(remaining, length(remaining)).text); divisors *= 2; }
            printf(" divisors %" PRId64 "\n", divisors);
            break;
        }
        case MACWILLIAMS: {
            int n = atoi(args[0]);
            require(n >= 1 && n <= 24, "bad parameter");
            require(count - 1 == n + 1, "bad length");
            require(atoi(args[1]) == 1, "bad parameter");
            int64_t size = 0;
            for (int i = 1; i < count; ++i) size += atoi(args[i]);
            bool feasible = (size & (size - 1)) == 0;
            printf("macwilliams n %d size %" PRId64 "\ndual", n, size);
            for (int j = 0; j <= n; ++j) {
                int64_t numerator = 0;
                for (int x = 0; x <= n; ++x) numerator += atoi(args[x + 1]) * krawtchouk(n, j, x);
                if (numerator < 0 || numerator % size) feasible = false;
                int64_t divisor = gcd(numerator, size), denominator = size / divisor;
                printf(" %" PRId64, numerator / divisor);
                if (denominator != 1) printf("/%" PRId64, denominator);
            }
            printf("\nfeasible %s\n", yes(feasible));
            break;
        }
        case BOUNDS: {
            int n = atoi(args[0]), d = atoi(args[1]);
            require(d >= 1 && d <= n && n <= 24, "bad parameter");
            int64_t volume = 0, sum = 0;
            for (int i = 0; i <= (d - 1) / 2; ++i) volume += choose(n, i);
            int hamming = 0, griesmer = 0;
            for (int k = 0; k <= n; ++k) if ((INT64_C(1) << k) * volume <= (INT64_C(1) << n)) hamming = k;
            for (int k = 1; k <= n; ++k) {
                int64_t denominator = INT64_C(1) << (k - 1);
                sum += (d + denominator - 1) / denominator;
                if (sum <= n) griesmer = k;
            }
            printf("bounds n %d d %d singleton %d hamming %d griesmer %d\n", n, d, n - d + 1, hamming, griesmer);
            break;
        }
        default: break;
    }
}

int main(void) {
    for (int n = 0; n <= 24; ++n) {
        combinations[n][0] = combinations[n][n] = 1;
        for (int k = 1; k < n; ++k) combinations[n][k] = combinations[n - 1][k - 1] + combinations[n - 1][k];
    }
    char line[1002];
    if (!fgets(line, sizeof(line), stdin)) return 0;
    int count = atoi(line);
    for (int i = 0; i < count && fgets(line, sizeof(line), stdin); ++i) {
        char *words[501];
        int word_count = 0;
        for (char *word = strtok(line, " \r\n"); word; word = strtok(NULL, " \r\n")) words[word_count++] = word;
        int command = 0;
        while (command < COMMAND_COUNT && strcmp(words[0], formats[command].name) != 0) ++command;
        if (command == COMMAND_COUNT) printf("error: unknown command %s\n", words[0]);
        else if (setjmp(command_error) == 0) execute((Command)command, words + 1, word_count - 1);
    }
    return 0;
}
