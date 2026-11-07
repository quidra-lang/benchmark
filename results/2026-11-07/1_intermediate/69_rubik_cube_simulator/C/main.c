#include <setjmp.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define APPEND(a, n, v) do { (a) = resize((a), ((n) + 1) * sizeof(*(a))); (a)[(n)++] = (v); } while (0)
typedef struct {
    char *data;
    size_t length, capacity;
} Buffer;
typedef struct {
    char letter;
    int amount;
} Move;
typedef struct {
    Move *items;
    size_t count;
} Sequence;
typedef struct {
    char stickers[55];
} Cube;
typedef struct {
    int to[54];
} Permutation;
typedef struct {
    int v[3];
} Vector;
typedef struct {
    int piece[12], orientation[12], count;
} Pieces;
typedef struct {
    char *name;
    Sequence sequence;
} Macro;
typedef struct {
    char *name;
    Cube cube;
    Sequence history;
} Save;
typedef struct {
    const char *line;
    size_t position, length;
} Parser;
static const char *faces = "URFDLB", *colors = "WRGYOB", *letters = "URFDLBMESurfdlbxyz";
static const char *corner_names[] = {"URF", "UFL", "ULB", "UBR", "DFR", "DLF", "DBL", "DRB"};
static const char *edge_names[] = {"UR", "UF", "UL", "UB", "DR", "DF", "DL", "DB", "FR", "FL", "BL", "BR"};
static const int corner_stickers[8][3] = {
    {8,9,20},{6,18,38},{0,36,47},{2,45,11},{29,26,15},{27,44,24},{33,53,42},{35,17,51}
};
static const int edge_stickers[12][3] = {
    {5,10,0},{7,19,0},{3,37,0},{1,46,0},{32,16,0},{28,25,0},{30,43,0},{34,52,0},{23,12,0},{21,41,0},{50,39,0},{48,14,0}
};
static Permutation permutations[18][4];
static Sequence rotations[24];
static Macro *macros;
static size_t macro_count;
static Save *saves;
static size_t save_count;
static Cube state;
static Sequence history, redo;
static jmp_buf failure;
static char *error_reason;
static void *allocate(size_t n) {
    void *p = calloc(1, n ? n : 1);
    if (!p) exit(EXIT_FAILURE);
    return p;
}

static void *resize(void *p, size_t n) {
    p = realloc(p, n ? n : 1);
    if (!p) exit(EXIT_FAILURE);
    return p;
}

static char *slice(const char *s, size_t n) {
    char *p = allocate(n + 1);
    memcpy(p, s, n);
    return p;
}

static char *copy_text(const char *s) {
    return slice(s, strlen(s));
}

static char *format(const char *pattern, ...) {
    va_list args, saved;
    va_start(args, pattern);
    va_copy(saved, args);
    int n = vsnprintf(NULL, 0, pattern, args);
    va_end(args);
    char *s = allocate((size_t)n + 1);
    vsnprintf(s, (size_t)n + 1, pattern, saved);
    va_end(saved);
    return s;
}

static void error(const char *pattern, ...) {
    va_list args, saved;
    va_start(args, pattern);
    va_copy(saved, args);
    int n = vsnprintf(NULL, 0, pattern, args);
    va_end(args);
    error_reason = allocate((size_t)n + 1);
    vsnprintf(error_reason, (size_t)n + 1, pattern, saved);
    va_end(saved);
    longjmp(failure, 1);
}

static void append(Buffer *b, const char *text) {
    size_t n = strlen(text);
    if (b->length + n + 1 > b->capacity) {
        b->capacity = (b->length + n + 1) * 2;
        b->data = resize(b->data, b->capacity);
    }
    memcpy(b->data + b->length, text, n);
    b->length += n;
    b->data[b->length] = 0;
}

static char *finish(Buffer *b) {
    return b->data ? b->data : copy_text("");
}

static bool in_letters(const char *set, char letter) {
    return letter && strchr(set, letter);
}

static int axis(char letter) {
    return in_letters("RLMrlx", letter) ? 0 : in_letters("UDEudy", letter) ? 1 : 2;
}

static int letter_index(char letter) {
    return (int)(strchr(letters, letter) - letters);
}

static Move inverse_move(Move move) {
    return (Move){move.letter, 4 - move.amount};
}

static Permutation identity(void) {
    Permutation p;
    for (int i = 0; i < 54; i++) p.to[i] = i;
    return p;
}

static Permutation compose(Permutation first, Permutation second) {
    Permutation p;
    for (int i = 0; i < 54; i++) p.to[i] = second.to[first.to[i]];
    return p;
}

static Permutation inverse(Permutation p) {
    Permutation out;
    for (int i = 0; i < 54; i++) out.to[p.to[i]] = i;
    return out;
}

static bool same_permutation(Permutation a, Permutation b) {
    for (int i = 0; i < 54; i++) if (a.to[i] != b.to[i]) return false;
    return true;
}

static Permutation move_permutation(Move move) {
    return permutations[letter_index(move.letter)][move.amount];
}

static Cube solved_state(void) {
    Cube cube;
    for (int i = 0; i < 54; i++) cube.stickers[i] = colors[i / 9];
    cube.stickers[54] = 0;
    return cube;
}

static Cube apply_permutation(Cube input, Permutation p) {
    Cube out;
    for (int i = 0; i < 54; i++) out.stickers[p.to[i]] = input.stickers[i];
    out.stickers[54] = 0;
    return out;
}

static Cube apply(Cube input, Sequence sequence) {
    for (size_t i = 0; i < sequence.count; i++) input = apply_permutation(input, move_permutation(sequence.items[i]));
    return input;
}

static Permutation effect(Sequence sequence) {
    Permutation p = identity();
    for (size_t i = 0; i < sequence.count; i++) p = compose(p, move_permutation(sequence.items[i]));
    return p;
}

static void extend(Sequence *target, Sequence source) {
    for (size_t i = 0; i < source.count; i++) APPEND(target->items, target->count, source.items[i]);
}

static Sequence clone_sequence(Sequence sequence) {
    Sequence out = {0};
    extend(&out, sequence);
    return out;
}

static Sequence invert(Sequence sequence) {
    Sequence out = {0};
    for (size_t i = sequence.count; i; i--) APPEND(out.items, out.count, inverse_move(sequence.items[i - 1]));
    return out;
}

static char *move_text(Move move) {
    return format("%c%s", move.letter, move.amount == 1 ? "" : move.amount == 2 ? "2" : "'");
}

static char *moves_text(Sequence sequence) {
    Buffer b = {0};
    for (size_t i = 0; i < sequence.count; i++) {
        if (i) append(&b, " ");
        append(&b, move_text(sequence.items[i]));
    }
    return finish(&b);
}

static char *sequence_text(Sequence sequence) {
    return format("%zu%s%s", sequence.count, sequence.count ? " " : "", moves_text(sequence));
}

static Vector rotate_vector(Vector v, int axis) {
    if (axis == 0) return (Vector){{v.v[0], -v.v[2], v.v[1]}};
    if (axis == 1) return (Vector){{v.v[2], v.v[1], -v.v[0]}};
    return (Vector){{-v.v[1], v.v[0], v.v[2]}};
}

static bool same_vector(Vector a, Vector b) {
    return a.v[0] == b.v[0] && a.v[1] == b.v[1] && a.v[2] == b.v[2];
}

static void initialize(void) {
    Vector positions[54], normals[54], face_normals[6] = {
        {{0, 1, 0}}, {{1, 0, 0}}, {{0, 0, 1}},
        {{0, -1, 0}}, {{-1, 0, 0}}, {{0, 0, -1}}
    };
    for (int face = 0; face < 6; face++) for (int row = 0; row < 3; row++) for (int col = 0; col < 3; col++) {
        int i = face * 9 + row * 3 + col;
        normals[i] = face_normals[face];
        switch (face) {
            case 0:
                positions[i] = (Vector) {
                    {col-1,1,row-1}
                };
                break;
            case 1:
                positions[i] = (Vector) {
                    {1,1-row,1-col}
                };
                break;
            case 2:
                positions[i] = (Vector) {
                    {col-1,1-row,1}
                };
                break;
            case 3:
                positions[i] = (Vector) {
                    {col-1,-1,1-row}
                };
                break;
            case 4:
                positions[i] = (Vector) {
                    {-1,1-row,col-1}
                };
                break;
            default:
                positions[i] = (Vector) {
                    {1-col,1-row,-1}
                };
        }
    }
    for (int m = 0; m < 18; m++) {
        char letter = letters[m];
        int ax = axis(letter), direction = in_letters("URFSurfxyz", letter) ? -1 : 1, layer = in_letters("MES", letter) ? 0 : in_letters("URFurf", letter) ? 1 : -1;
        bool all = in_letters("xyz", letter), wide = in_letters("urfdlb", letter);
        Permutation p = identity();
        for (int i = 0; i < 54; i++) {
            if (!(all || (wide ? positions[i].v[ax] * layer >= 0 : positions[i].v[ax] == layer))) continue;
            Vector pos = positions[i], normal = normals[i];
            for (int n = 0; n < (direction == 1 ? 1 : 3); n++) {
                pos = rotate_vector(pos, ax);
                normal = rotate_vector(normal, ax);
            }
            for (int j = 0; j < 54; j++) if (same_vector(pos, positions[j]) && same_vector(normal, normals[j])) {
                p.to[i] = j;
                break;
            }
        }
        Permutation total = identity();
        for (int amount = 1; amount <= 3; amount++) {
            total = compose(total, p);
            permutations[m][amount] = total;
        }
    }
    for (int base = 0; base < 6; base++) for (int y = 0; y < 4; y++) {
        Sequence *rotation = rotations + base * 4 + y;
        if (base) APPEND(rotation->items, rotation->count, ((Move){base < 4 ? 'x' : 'z', base < 4 ? base : base == 4 ? 1 : 3}));
        if (y) APPEND(rotation->items, rotation->count, ((Move){'y', y}));
    }
    state = solved_state();
}

static char peek(Parser *p) {
    return p->position >= p->length ? 0 : p->line[p->position];
}

static void spaces(Parser *p) {
    while (peek(p) == ' ') p->position++;
}

static void syntax(Parser *p) {
    error("error: syntax at %zu", (p->position > p->length ? p->length : p->position) + 1);
}

static Macro *find_macro(const char *name) {
    for (size_t i = 0; i < macro_count; i++) if (!strcmp(macros[i].name, name)) return macros + i;
    return NULL;
}

static Sequence parse_sequence(Parser *p);
static Sequence power(Parser *p, Sequence sequence) {
    int count = 1;
    if (peek(p) >= '1' && peek(p) <= '9') {
        count = peek(p) - '0';
        p->position++;
        if (peek(p) >= '0' && peek(p) <= '9') {
            count = 10 * count + peek(p) - '0';
            p->position++;
        }
    }
    bool reverse = peek(p) == '\'';
    if (reverse) p->position++;
    Sequence out = {0};
    for (int i = 0; i < count; i++) extend(&out, sequence);
    return reverse ? invert(out) : out;
}

static Sequence parse_sequence(Parser *p) {
    Sequence out = {0};
    while (true) {
        spaces(p);
        char c = peek(p);
        if (in_letters(letters, c)) {
            p->position++;
            int amount = peek(p) == '2' ? 2 : peek(p) == '\'' ? 3 : 1;
            if (amount != 1) p->position++;
            APPEND(out.items, out.count, ((Move){c, amount}));
        } else if (c == '(') {
            p->position++;
            Sequence group = parse_sequence(p);
            spaces(p);
            if (peek(p) != ')') syntax(p);
            p->position++;
            extend(&out, power(p, group));
        } else if (c == '[') {
            p->position++;
            Sequence first = parse_sequence(p);
            spaces(p);
            char separator = peek(p);
            if (separator != ',' && separator != ':') syntax(p);
            p->position++;
            Sequence second = parse_sequence(p);
            spaces(p);
            if (peek(p) != ']') syntax(p);
            p->position++;
            Sequence group = clone_sequence(first);
            extend(&group, second);
            extend(&group, invert(first));
            if (separator == ',') extend(&group, invert(second));
            extend(&out, power(p, group));
        } else if (c == '{') {
            p->position++;
            size_t start = p->position;
            while (peek(p) >= 'a' && peek(p) <= 'z') p->position++;
            char *name = slice(p->line + start, p->position - start);
            if (!*name || peek(p) != '}') syntax(p);
            Macro *macro = find_macro(name);
            if (!macro) error("error: undefined %s", name);
            p->position++;
            extend(&out, power(p, macro->sequence));
        } else return out;
    }
}

static Sequence parse(const char *line, size_t start) {
    Parser p = {line, start, strlen(line)};
    Sequence out = parse_sequence(&p);
    spaces(&p);
    if (p.position < p.length) syntax(&p);
    if (out.count > 500) error("error: too long");
    return out;
}

static bool solved(Cube input) {
    for (int i = 0; i < 54; i++) if (input.stickers[i] != input.stickers[(i / 9) * 9 + 4]) return false;
    return true;
}

static int normalize(Cube input, Cube *output) {
    for (int i = 0; i < 24; i++) {
        Cube candidate = apply(input, rotations[i]);
        bool good = true;
        for (int face = 0; face < 6; face++) if (candidate.stickers[face * 9 + 4] != colors[face]) good = false;
        if (good) {
            *output = candidate;
            return i;
        }
    }
    return -1;
}

static Pieces identify(Cube input, const int stickers[][3], int width, const char **names, int count) {
    Pieces result = {.count = count};
    for (int i = 0; i < count; i++) result.piece[i] = -1;
    for (int q = 0; q < count; q++) for (int p = 0; p < count; p++) for (int t = 0; t < width; t++) {
        bool good = true;
        for (int i = 0; i < width; i++) if (input.stickers[stickers[q][(t + i) % width]] != colors[strchr(faces, names[p][i]) - faces]) good = false;
        if (good) {
            result.piece[q] = p;
            result.orientation[q] = t;
        }
    }
    return result;
}

static Pieces corners(Cube input) {
    return identify(input, corner_stickers, 3, corner_names, 8);
}

static Pieces edges(Cube input) {
    return identify(input, edge_stickers, 2, edge_names, 12);
}

static int parity(Pieces p) {
    int count = 0;
    for (int i = 0; i < p.count; i++) for (int j = i + 1; j < p.count; j++) if (p.piece[i] > p.piece[j]) count++;
    return count % 2;
}

static char *check(const char *text) {
    size_t length = strlen(text);
    if (length != 54) return format("length %zu", length);
    for (int i = 0; i < 54; i++) if (!strchr(colors, text[i])) return format("char %d", i + 1);
    for (int c = 0; c < 6; c++) {
        int count = 0;
        for (int i = 0; i < 54; i++) if (text[i] == colors[c]) count++;
        if (count != 9) return format("count %c %d", colors[c], count);
    }
    Cube input, normalized;
    memcpy(input.stickers, text, 55);
    if (normalize(input, &normalized) < 0) return "centers";
    Pieces c = corners(input), e = edges(input);
    for (int i = 0; i < 8; i++) if (c.piece[i] < 0) return format("corner %s", corner_names[i]);
    for (int i = 0; i < 12; i++) if (e.piece[i] < 0) return format("edge %s", edge_names[i]);
    for (int i = 0; i < 8; i++) {
        bool found = false;
        for (int q = 0; q < 8; q++) if (c.piece[q] == i) found = true;
        if (!found) return format("missing %s", corner_names[i]);
    }
    for (int i = 0; i < 12; i++) {
        bool found = false;
        for (int q = 0; q < 12; q++) if (e.piece[q] == i) found = true;
        if (!found) return format("missing %s", edge_names[i]);
    }
    c = corners(normalized);
    e = edges(normalized);
    int twist = 0, flip = 0;
    for (int i = 0; i < 8; i++) twist += c.orientation[i];
    for (int i = 0; i < 12; i++) flip += e.orientation[i];
    if (twist % 3) return "twist";
    if (flip % 2) return "flip";
    return parity(c) != parity(e) ? "parity" : NULL;
}

static char *cycle_text(Pieces pieces, const char **names, int base) {
    int destination[12] = {0}, orientation[12] = {0};
    bool seen[12] = {0};
    for (int q = 0; q < pieces.count; q++) {
        destination[pieces.piece[q]] = q;
        orientation[pieces.piece[q]] = pieces.orientation[q];
    }
    Buffer out = {0};
    for (int start = 0; start < pieces.count; start++) if (!seen[start]) {
        Buffer cycle = {0};
        int p = start, count = 0, sum = 0;
        do {
            seen[p] = true;
            if (count++) append(&cycle, " ");
            append(&cycle, names[p]);
            sum += orientation[p];
            p = destination[p];
        }
        while (p != start);
        char *mark = base == 3 ? sum % 3 == 1 ? "+" : sum % 3 == 2 ? "-" : "" : base == 2 && sum % 2 ? "+" : "";
        if (count >= 2 || *mark) {
            if (out.length) append(&out, " ");
            append(&out, format("(%s)%s", finish(&cycle), mark));
        }
    }
    return out.length ? finish(&out) : "none";
}

static void print_cycles(Cube input, bool centers) {
    printf("corners %s\nedges %s\n", cycle_text(corners(input), corner_names, 3), cycle_text(edges(input), edge_names, 2));
    if (centers) {
        Pieces pieces = {.count = 6};
        const char *names[] = {"U", "R", "F", "D", "L", "B"};
        for (int i = 0; i < 6; i++) pieces.piece[i] = (int)(strchr(colors, input.stickers[i * 9 + 4]) - colors);
        printf("centers %s\n", cycle_text(pieces, names, 1));
    }
}

static bool same_sequence(Sequence a, Sequence b) {
    if (a.count != b.count) return false;
    for (size_t i = 0; i < a.count; i++) if (a.items[i].letter != b.items[i].letter || a.items[i].amount != b.items[i].amount) return false;
    return true;
}

static Sequence simplify(Sequence input) {
    Sequence moves = input;
    while (true) {
        Sequence out = {0};
        for (size_t i = 0; i < moves.count;) {
            int ax = axis(moves.items[i].letter), totals[18] = {0};
            char order[18];
            size_t count = 0;
            while (i < moves.count && axis(moves.items[i].letter) == ax) {
                Move move = moves.items[i++];
                int index = letter_index(move.letter);
                bool present = false;
                for (size_t j = 0; j < count; j++) if (order[j] == move.letter) present = true;
                if (!present) order[count++] = move.letter;
                totals[index] += move.amount;
            }
            for (size_t j = 0; j < count; j++) {
                int amount = totals[letter_index(order[j])] % 4;
                if (amount) APPEND(out.items, out.count, ((Move){order[j], amount}));
            }
        }
        if (same_sequence(out, moves)) return out;
        moves = out;
    }
}

static Move conjugate(Permutation rotation, Move move) {
    Permutation target = compose(compose(rotation, move_permutation(move)), inverse(rotation));
    for (int i = 0; i < 18; i++) for (int amount = 1; amount <= 3; amount++) if (same_permutation(target, permutations[i][amount])) return (Move){letters[i], amount};
    exit(EXIT_FAILURE);
}

static Sequence replacement(Move move) {
    const char *text = NULL;
    int amounts[3] = {1,1,1};
    switch (move.letter) {
        case 'M':
            text = "RLx";
            amounts[1] = amounts[2] = 3;
            break;
        case 'E':
            text = "UDy";
            amounts[1] = amounts[2] = 3;
            break;
        case 'S':
            text = "FBz";
            amounts[0] = 3;
            break;
        case 'r':
            text = "Lx";
            break;
        case 'l':
            text = "Rx";
            amounts[1] = 3;
            break;
        case 'u':
            text = "Dy";
            break;
        case 'd':
            text = "Uy";
            amounts[1] = 3;
            break;
        case 'f':
            text = "Bz";
            break;
        case 'b':
            text = "Fz";
            amounts[1] = 3;
            break;
        default:
            break;
    }
    Sequence out = {0};
    if (!text) APPEND(out.items, out.count, move);
    else for (size_t i = 0; text[i]; i++) APPEND(out.items, out.count, ((Move){text[i], amounts[i] * move.amount % 4}));
    return out;
}

static Sequence unrotate(Sequence input) {
    Permutation rotation = identity();
    Sequence out = {0};
    for (size_t i = 0; i < input.count; i++) {
        Sequence expanded = replacement(input.items[i]);
        for (size_t j = 0; j < expanded.count; j++) {
            Move move = expanded.items[j];
            if (in_letters("xyz", move.letter)) rotation = compose(rotation, move_permutation(move));
            else APPEND(out.items, out.count, conjugate(rotation, move));
        }
    }
    for (int i = 0; i < 24; i++) if (same_permutation(effect(rotations[i]), rotation)) {
        extend(&out, rotations[i]);
        break;
    }
    return out;
}

static uint64_t gcd(uint64_t a, uint64_t b) {
    while (b) {
        uint64_t remainder = a % b;
        a = b;
        b = remainder;
    }
    return a;
}

static uint64_t order(Permutation p) {
    bool seen[54] = {0};
    uint64_t result = 1;
    for (int i = 0; i < 54; i++) if (!seen[i]) {
        int count = 0, at = i;
        do {
            seen[at] = true;
            count++;
            at = p.to[at];
        }
        while (at != i);
        result = result / gcd(result, (uint64_t)count) * (uint64_t)count;
    }
    return result;
}

static bool search(Cube input, int left, int previous, Sequence *path) {
    if (solved(input)) return true;
    if (!left) return false;
    for (int face = 0; face < 6; face++) {
        if (face == previous || (previous == 3 && face == 0) || (previous == 4 && face == 1) || (previous == 5 && face == 2)) continue;
        for (int amount = 1; amount <= 3; amount++) {
            Move move = {faces[face], amount};
            APPEND(path->items, path->count, move);
            if (search(apply_permutation(input, move_permutation(move)), left - 1, face, path)) return true;
            path->count--;
        }
    }
    return false;
}

static void apply_current(Sequence moves) {
    state = apply(state, moves);
    extend(&history, moves);
    redo.count = 0;
}

static bool one_of(const char *word, const char *set) {
    return *word && !strchr(word, ' ') && strstr(set, format(" %s ", word));
}

static uint64_t number(const char *word) {
    size_t n = strlen(word);
    if (!n || n > 10 || (n > 1 && *word == '0')) error("error: bad arguments");
    uint64_t value = 0;
    for (size_t i = 0; i < n; i++) {
        if (word[i] < '0' || word[i] > '9') error("error: bad arguments");
        value = value * 10 + (unsigned)(word[i] - '0');
    }
    return value;
}

static bool valid_name(const char *name) {
    size_t n = strlen(name);
    if (!n || n > 8) return false;
    for (size_t i = 0; i < n; i++) if (name[i] < 'a' || name[i] > 'z') return false;
    return true;
}

static int piece_index(const char *piece, const char **names, int count) {
    for (int i = 0; i < count; i++) if (!strcmp(piece, names[i])) return i;
    return -1;
}

static int macro_compare(const void *a, const void *b) {
    return strcmp((*(Macro *const *)a)->name, (*(Macro *const *)b)->name);
}

static char **words(const char *s, size_t *count) {
    char **out = NULL;
    *count = 0;
    if (!s) return out;
    size_t start = 0;
    for (size_t i = 0;; i++) if (!s[i] || s[i] == ' ') {
        APPEND(out, *count, slice(s + start, i - start));
        start = i + 1;
        if (!s[i]) break;
    }
    return out;
}

static void command(const char *line) {
    const char *space = strchr(line, ' '), *argument = space ? space + 1 : NULL;
    char *command = space ? slice(line, (size_t)(space - line)) : copy_text(line);
    bool no_args = one_of(command, " RESET  SHOW  STATE  ISSOLVED  HISTORY  SOLUTION  ANALYZE  STAGE  MACROS "), word_command = one_of(command, " CHECK  LOAD  UNDO  REDO  SEARCH  WHERE  SAVE  RESTORE  SCRAMBLE "), sequence_command = one_of(command, " APPLY  INVERT  SIMPLIFY  METRICS  ORDER  CYCLES  UNROTATE  UNTIL "), head_command = one_of(command, " DEFINE  MIRROR  ROTATE ");
    if (!no_args && !word_command && !sequence_command && !head_command) error("error: unknown command %s", command);
    size_t argc;
    char **args = words(argument, &argc);
    char *head = NULL;
    Sequence moves = {0};
    uint64_t n = 0, seed = 0;
    if (no_args && argument) error("error: bad arguments");
    if (word_command) {
        if (argc != (size_t)(!strcmp(command, "SCRAMBLE") ? 2 : 1)) error("error: bad arguments");
        if (one_of(command, " UNDO  REDO  SEARCH  SCRAMBLE ")) n = number(args[0]);
        if (!strcmp(command, "SCRAMBLE")) seed = number(args[1]);
        if (one_of(command, " SAVE  RESTORE ") && !valid_name(args[0])) error("error: bad arguments");
    }
    if (head_command) {
        if (!argument) error("error: bad arguments");
        head = args[0];
        bool valid = !strcmp(command, "DEFINE") ? valid_name(head) : !strcmp(command, "MIRROR") ? one_of(head, " LR  UD  FB ") : (strlen(head) == 1 || (strlen(head) == 2 && (head[1] == '2' || head[1] == '\''))) && in_letters("xyz", head[0]);
        if (!valid) error("error: bad arguments");
        moves = parse(line, strlen(command) + strlen(head) + 2);
    } else if (sequence_command) moves = parse(line, strlen(command) + 1);
    if (one_of(command, " UNDO  REDO ") && n < 1) error("error: bad value");
    if (!strcmp(command, "SEARCH") && n > 4) error("error: bad value");
    if (!strcmp(command, "SCRAMBLE") && (n < 1 || n > 50 || seed < 1 || seed > 2147483646ULL)) error("error: bad value");
    if (!strcmp(command, "WHERE") && piece_index(args[0], corner_names, 8) < 0 && piece_index(args[0], edge_names, 12) < 0) error("error: unknown piece %s", args[0]);
    if (!strcmp(command, "RESET")) {
        state = solved_state();
        history.count = redo.count = 0;
        puts("reset");
    } else if (!strcmp(command, "SHOW")) {
        for (int row = 0; row < 3; row++) printf("      %c %c %c\n", state.stickers[row * 3], state.stickers[row * 3 + 1], state.stickers[row * 3 + 2]);
        int net[] = {4,2,1,5};
        for (int row = 0; row < 3; row++) {
            bool first = true;
            for (int f = 0; f < 4; f++) for (int col = 0; col < 3; col++) {
                if (!first) putchar(' ');
                putchar(state.stickers[net[f] * 9 + row * 3 + col]);
                first = false;
            }
            putchar('\n');
        }
        for (int row = 0; row < 3; row++) printf("      %c %c %c\n", state.stickers[27 + row * 3], state.stickers[28 + row * 3], state.stickers[29 + row * 3]);
    } else if (!strcmp(command, "STATE")) printf("state %s\n", state.stickers);
    else if (!strcmp(command, "ISSOLVED")) {
        int count = 0;
        for (int i = 0; i < 54; i++) if (state.stickers[i] != state.stickers[(i / 9) * 9 + 4]) count++;
        if (!count) puts("solved");
        else printf("unsolved %d\n", count);
    } else if (!strcmp(command, "HISTORY")) printf("history %s\n", sequence_text(history));
    else if (!strcmp(command, "SOLUTION")) printf("solution %s\n", sequence_text(simplify(invert(history))));
    else if (!strcmp(command, "ANALYZE")) {
        Cube normalized;
        int rotation = normalize(state, &normalized);
        printf("rotation %s\n", rotations[rotation].count ? moves_text(rotations[rotation]) : "none");
        print_cycles(normalized, false);
    } else if (!strcmp(command, "STAGE")) {
        Cube normalized;
        normalize(state, &normalized);
        Pieces c = corners(normalized), e = edges(normalized);
        int cross = 0, slots = 0, top = 0;
        for (int i = 4; i < 8; i++) if (e.piece[i] == i && !e.orientation[i]) cross++;
        for (int i = 0; i < 4; i++) if (c.piece[i + 4] == i + 4 && !c.orientation[i + 4] && e.piece[i + 8] == i + 8 && !e.orientation[i + 8]) slots++;
        for (int i = 0; i < 9; i++) if (normalized.stickers[i] == 'W') top++;
        char *stage = solved(normalized) ? "solved" : cross == 4 && slots == 4 && top == 9 ? "oll" : cross == 4 && slots == 4 ? "f2l" : cross == 4 ? "cross" : "none";
        printf("stage %s cross %d slots %d top %d\n", stage, cross, slots, top);
    } else if (!strcmp(command, "MACROS")) {
        printf("macros %zu\n", macro_count);
        Macro **ordered = allocate(macro_count * sizeof(*ordered));
        for (size_t i = 0; i < macro_count; i++) ordered[i] = macros + i;
        qsort(ordered, macro_count, sizeof(*ordered), macro_compare);
        for (size_t i = 0; i < macro_count; i++) printf("macro %s %s\n", ordered[i]->name, sequence_text(ordered[i]->sequence));
    } else if (!strcmp(command, "CHECK") || !strcmp(command, "LOAD")) {
        char *reason = check(args[0]);
        if (!strcmp(command, "CHECK")) {
            if (reason) printf("invalid %s\n", reason);
            else puts("valid");
        } else {
            if (reason) error("error: invalid %s", reason);
            memcpy(state.stickers, args[0], 55);
            history.count = redo.count = 0;
            puts("loaded");
        }
    } else if (!strcmp(command, "UNDO") || !strcmp(command, "REDO")) {
        bool undo = !strcmp(command, "UNDO");
        Sequence *source = undo ? &history : &redo, *target = undo ? &redo : &history;
        if (!source->count) error("error: nothing to %s", undo ? "undo" : "redo");
        size_t count = n < source->count ? (size_t)n : source->count;
        for (size_t i = 0; i < count; i++) {
            Move move = source->items[--source->count];
            state = apply_permutation(state, move_permutation(undo ? inverse_move(move) : move));
            APPEND(target->items, target->count, move);
        }
        printf("%s %zu\n", undo ? "undone" : "redone", count);
    } else if (!strcmp(command, "SEARCH")) {
        Sequence solution = {0};
        bool found = false;
        for (int depth = 0; depth <= (int)n; depth++) {
            solution.count = 0;
            if (search(state, depth, -1, &solution)) {
                found = true;
                break;
            }
        }
        if (found) printf("found %s\n", sequence_text(solution));
        else puts("not found");
    } else if (!strcmp(command, "WHERE")) {
        Cube normalized;
        normalize(state, &normalized);
        int piece = piece_index(args[0], corner_names, 8);
        bool corner = piece >= 0;
        if (!corner) piece = piece_index(args[0], edge_names, 12);
        Pieces pieces = corner ? corners(normalized) : edges(normalized);
        const char **names = corner ? corner_names : edge_names;
        for (int q = 0; q < pieces.count; q++) if (pieces.piece[q] == piece) printf("%s at %s %s %d\n", args[0], names[q], corner ? "twist" : "flip", pieces.orientation[q]);
    } else if (!strcmp(command, "SAVE")) {
        Save *save = NULL;
        for (size_t i = 0; i < save_count; i++) if (!strcmp(saves[i].name, args[0])) save = saves + i;
        if (save) *save = (Save){args[0], state, clone_sequence(history)};
        else APPEND(saves, save_count, ((Save){args[0], state, clone_sequence(history)}));
        printf("saved %s\n", args[0]);
    } else if (!strcmp(command, "RESTORE")) {
        Save *save = NULL;
        for (size_t i = 0; i < save_count; i++) if (!strcmp(saves[i].name, args[0])) save = saves + i;
        if (!save) error("error: no save %s", args[0]);
        state = save->cube;
        history = clone_sequence(save->history);
        redo.count = 0;
        printf("restored %s\n", args[0]);
    } else if (!strcmp(command, "SCRAMBLE")) {
        Sequence scramble = {0};
        uint64_t random = seed;
        for (size_t i = 0; i < n; i++) {
            char usable[6];
            size_t count = 0;
            for (int f = 0; f < 6; f++) {
                char face = faces[f];
                if (i >= 1 && scramble.items[i - 1].letter == face) continue;
                if (i >= 2 && axis(scramble.items[i - 1].letter) == axis(scramble.items[i - 2].letter) && axis(face) == axis(scramble.items[i - 1].letter)) continue;
                usable[count++] = face;
            }
            random = 48271 * random % 2147483647;
            char face = usable[random % count];
            random = 48271 * random % 2147483647;
            int amounts[] = {1,3,2};
            APPEND(scramble.items, scramble.count, ((Move){face, amounts[random % 3]}));
        }
        apply_current(scramble);
        printf("scramble %s\n", moves_text(scramble));
    } else if (!strcmp(command, "APPLY")) {
        apply_current(moves);
        printf("applied %zu\n", moves.count);
    } else if (!strcmp(command, "INVERT")) printf("inverse %s\n", sequence_text(invert(moves)));
    else if (!strcmp(command, "SIMPLIFY")) printf("simplified %s\n", sequence_text(simplify(moves)));
    else if (!strcmp(command, "METRICS")) {
        int htm = 0, qtm = 0, stm = 0;
        for (size_t i = 0; i < moves.count; i++) {
            Move move = moves.items[i];
            if (in_letters("xyz", move.letter)) continue;
            int weight = in_letters("MES", move.letter) ? 2 : 1;
            htm += weight;
            qtm += weight * (move.amount == 2 ? 2 : 1);
            stm++;
        }
        printf("metrics htm %d qtm %d stm %d etm %zu\n", htm, qtm, stm, moves.count);
    } else if (!strcmp(command, "ORDER")) printf("order %llu\n", (unsigned long long)order(effect(moves)));
    else if (!strcmp(command, "CYCLES")) print_cycles(apply(solved_state(), moves), true);
    else if (!strcmp(command, "UNROTATE")) printf("unrotated %s\n", sequence_text(unrotate(moves)));
    else if (!strcmp(command, "UNTIL")) {
        Permutation p = effect(moves);
        uint64_t count = order(p), found = 0;
        Cube candidate = state;
        for (uint64_t k = 1; k <= count; k++) {
            candidate = apply_permutation(candidate, p);
            if (solved(candidate)) {
                found = k;
                break;
            }
        }
        if (found) printf("until %llu\n", (unsigned long long)found);
        else puts("until never");
    } else if (!strcmp(command, "DEFINE")) {
        Macro *macro = find_macro(head);
        if (macro) macro->sequence = clone_sequence(moves);
        else APPEND(macros, macro_count, ((Macro){head, clone_sequence(moves)}));
        printf("defined %s %zu\n", head, moves.count);
    } else if (!strcmp(command, "MIRROR")) {
        int mirror_axis = !strcmp(head, "LR") ? 0 : !strcmp(head, "UD") ? 1 : 2;
        const char *originals = "URFDLBurfdlb", *opposites = "DLBURFdlburf";
        Sequence out = {0};
        for (size_t i = 0; i < moves.count; i++) {
            Move move = moves.items[i];
            if (axis(move.letter) == mirror_axis) {
                const char *position = strchr(originals, move.letter);
                if (position) {
                    move.letter = opposites[position - originals];
                    move.amount = 4 - move.amount;
                }
            } else move.amount = 4 - move.amount;
            APPEND(out.items, out.count, move);
        }
        printf("mirror %s\n", sequence_text(out));
    } else {
        Move rotation = {head[0], !head[1] ? 1 : head[1] == '2' ? 2 : 3};
        Sequence out = {0};
        for (size_t i = 0; i < moves.count; i++) APPEND(out.items, out.count, conjugate(move_permutation(rotation), moves.items[i]));
        printf("rotated %s\n", sequence_text(out));
    }
}

static char *read_line(void) {
    Buffer b = {0};
    int c;
    while ((c = getchar()) != EOF && c != '\n') append(&b, (char[]){(char)c, 0});
    if (c == EOF && !b.length) return NULL;
    return finish(&b);
}

int main(void) {
    initialize();
    int count = atoi(read_line());
    for (int i = 0; i < count; i++) {
        char *line = read_line();
        if (setjmp(failure)) puts(error_reason);
        else command(line);
    }
    return 0;
}
