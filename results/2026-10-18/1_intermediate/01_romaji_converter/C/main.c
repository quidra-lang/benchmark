#include <stdbool.h>
#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CAP 256
#define OUT 16000
#define N 108
#define Q 109
#define L 110

typedef struct {
    char id[5], dan[3], spelling[5][5];
    int row, base, voice;
} Mora;
typedef struct { int id, col; } Token;
typedef struct {
    char original[CAP];
    int start, end, section, pattern, count;
    Token tokens[CAP];
} Word;
typedef struct { int id, voice, size; } Element;
typedef struct {
    char data[OUT];
    size_t size;
} Buffer;

static const char *systems[] = {"HEPBURN", "TRADITIONAL", "KUNREI", "NIHON", "WAPURO"};
static const char *rows[] = {"a", "ka", "sa", "ta", "na", "ha", "ma", "ya", "ra", "wa", "ga", "za", "da", "ba", "pa"};
static Mora table[108];
static int long_mode, case_mode, order_mode;
static char error_message[CAP];
static jmp_buf recovery;

static void append(Buffer *b, const char *s) {
    size_t n = strlen(s);
    memcpy(b->data + b->size, s, n + 1);
    b->size += n;
}
static void number(Buffer *b, int value) {
    char s[32];
    snprintf(s, sizeof s, "%d", value);
    append(b, s);
}
static void item(Buffer *b, const char *s, const char *separator) {
    if (b->size) append(b, separator);
    append(b, s);
}
static bool letter(char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
}
static bool vowel(char c) { return c && strchr("aiueo", c); }
static bool word_char(char c) { return letter(c) || c == '\'' || c == '-'; }
static char lower(char c) { return c >= 'A' && c <= 'Z' ? c + ('a' - 'A') : c; }
static char upper(char c) { return c >= 'a' && c <= 'z' ? c - ('a' - 'A') : c; }
static int lookup(const char *const *items, int count, const char *s) {
    for (int i = 0; i < count; ++i) {
        if (!strcmp(items[i], s)) return i;
    }
    return -1;
}
static int mora_id(const char *id) {
    for (int i = 0; i < N; ++i) {
        if (!strcmp(table[i].id, id)) return i;
    }
    return N;
}
static void fail(const char *message) {
    if (message != error_message) snprintf(error_message, sizeof error_message, "%s", message);
    longjmp(recovery, 1);
}
static bool column_problem(int col, const char *message) {
    snprintf(error_message, sizeof error_message, "col %d: %s", col, message);
    return false;
}
static void column_error(int col, const char *message) {
    column_problem(col, message);
    fail(error_message);
}
static void named_error(const char *kind, const char *name) {
    snprintf(error_message, sizeof error_message, "%s %s", kind, name);
    fail(error_message);
}
static void initialize(void) {
    const char *base[] = {
        "a i u e o", "ka ki ku ke ko", "sa si su se so", "ta ti tu te to",
        "na ni nu ne no", "ha hi hu he ho", "ma mi mu me mo", "ya yu yo",
        "ra ri ru re ro", "wa wi we wo", "ga gi gu ge go", "za zi zu ze zo",
        "da di du de do", "ba bi bu be bo", "pa pi pu pe po"
    };
    const int base_rows[] = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 1, 2, 3, 5, 5};
    const int contracted[] = {1, 2, 3, 4, 5, 6, 8, 10, 11, 12, 13, 14};
    int count = 0;
    for (int r = 0; r < 15; ++r) {
        char line[64];
        strcpy(line, base[r]);
        for (char *id = strtok(line, " "); id; id = strtok(NULL, " ")) {
            Mora *m = &table[count++];
            strcpy(m->id, id);
            m->dan[0] = id[strlen(id) - 1];
            m->row = r;
            m->base = base_rows[r];
            m->voice = r >= 10 ? (r == 14 ? 2 : 1) : 0;
        }
    }
    const char *dans[] = {"ya", "yu", "yo"};
    for (int j = 0; j < 12; ++j) {
        int r = contracted[j];
        for (int d = 0; d < 3; ++d) {
            Mora *m = &table[count++];
            m->id[0] = rows[r][0];
            strcpy(m->id + 1, dans[d]);
            strcpy(m->dan, dans[d]);
            m->row = r;
            m->base = base_rows[r];
            m->voice = r >= 10 ? (r == 14 ? 2 : 1) : 0;
        }
    }
    const char *special[] = {"si", "ti", "tu", "hu", "zi", "di", "du", "wi", "we", "wo"};
    const char *hepburn[] = {"shi", "chi", "tsu", "fu", "ji", "ji", "zu", "i", "e", "o"};
    const char *kunrei_from[] = {"di", "du", "wi", "we", "wo", "dya", "dyu", "dyo"};
    const char *kunrei_to[] = {"zi", "zu", "i", "e", "o", "zya", "zyu", "zyo"};
    for (int i = 0; i < N; ++i) {
        Mora *m = &table[i];
        for (int s = 0; s < 5; ++s) {
            char *p = m->spelling[s];
            strcpy(p, m->id);
            int k = lookup(special, 10, m->id);
            if ((s <= 1 || (s == 4 && k < 5)) && k >= 0) strcpy(p, hepburn[k]);
            k = lookup(kunrei_from, 8, m->id);
            if (s == 2 && k >= 0) strcpy(p, kunrei_to[k]);
            if (strlen(m->dan) == 2 && (s <= 1 || s == 4)) {
                if (!strncmp(m->id, "sy", 2)) snprintf(p, 5, "sh%s", m->id + 2);
                if (!strncmp(m->id, "ty", 2)) snprintf(p, 5, "ch%s", m->id + 2);
                if (!strncmp(m->id, "zy", 2) || (s <= 1 && !strncmp(m->id, "dy", 2))) snprintf(p, 5, "j%s", m->id + 2);
            }
        }
    }
}
static int lex(const char *text, Word *words) {
    int count = 0, section = 0;
    for (int i = 0; text[i];) {
        if (!word_char(text[i])) {
            if (text[i] == '/') ++section;
            ++i;
            continue;
        }
        Word *w = &words[count++];
        memset(w, 0, sizeof *w);
        w->start = i;
        w->section = section;
        while (word_char(text[i])) ++i;
        w->end = i;
        memcpy(w->original, text + w->start, i - w->start);
    }
    return count;
}
static void check_case(Word *w) {
    bool all_lower = true, all_upper = true;
    bool title = w->original[0] >= 'A' && w->original[0] <= 'Z';
    int letters = 0;
    for (int i = 0; w->original[i]; ++i) {
        char c = w->original[i];
        if (!letter(c)) continue;
        ++letters;
        if (c != lower(c)) all_lower = false;
        if (c != upper(c)) all_upper = false;
        if (i && c != lower(c)) title = false;
    }
    if (all_lower) w->pattern = 0;
    else if (title) w->pattern = 1;
    else if (letters >= 2 && all_upper) w->pattern = 2;
    else column_error(w->start + 1, "mixed case");
}
static int match(const char *s, int pos, int system, int *length) {
    int id = -1;
    *length = 0;
    for (int i = 0; i < N; ++i) {
        for (int t = 0; t < 5; ++t) {
            if (system >= 0 && system != t) continue;
            const char *p = table[i].spelling[t];
            int n = (int)strlen(p);
            if (n > *length && !strncmp(s + pos, p, n)) {
                id = i;
                *length = n;
            }
        }
    }
    return id;
}
static bool parse(Word *w, int system) {
    char s[CAP];
    strcpy(s, w->original);
    int n = (int)strlen(s);
    for (int i = 0; i < n; ++i) s[i] = lower(s[i]);
    w->count = 0;
    for (int p = 0; p < n;) {
        char c = s[p], c2 = s[p + 1];
        int id = -1, advance = 1, length;
        if (c == '-') {
            if (!w->count || w->tokens[w->count - 1].id >= N) return column_problem(w->start + p + 1, "misplaced long mark");
            id = L;
        } else if (c == '\'') return column_problem(w->start + p + 1, "misplaced apostrophe");
        else {
            id = match(s, p, system, &length);
            if (id >= 0) advance = length;
            else if ((system == 4 || system < 0) && !strncmp(s + p, "xtu", 3)) {
                id = Q;
                advance = 3;
            } else if (c == 'n') {
                id = N;
                if (system < 0) {
                    char c3 = p + 2 < n ? s[p + 2] : '\0';
                    if (c2 == '\'' || (c2 == 'n' && !vowel(c3) && c3 != 'y' && c3 != '\'')) advance = 2;
                } else if ((system == 4 && c2 == 'n') || (system != 4 && c2 == '\'')) advance = 2;
            } else if ((system == 1 || system < 0) && c == 'm' && c2 && strchr("bmp", c2)) id = N;
            else if (letter(c) && !vowel(c) && c != 'n' && c2 == c && match(s, p + 1, system, &length) >= 0) id = Q;
            else if (system <= 1 && c == 't' && !strncmp(s + p + 1, "ch", 2) && match(s, p + 1, system, &length) >= 0) id = Q;
            else return column_problem(w->start + p + 1, "unknown syllable");
        }
        w->tokens[w->count++] = (Token){id, w->start + p + 1};
        p += advance;
    }
    return true;
}
static void pairs(const Word *w, bool *result, bool long_only) {
    memset(result, 0, CAP * sizeof *result);
    for (int i = 0; i + 1 < w->count;) {
        int a = w->tokens[i].id, b = w->tokens[i + 1].id;
        if (a < N && b < 5) {
            char x = table[a].id[strlen(table[a].id) - 1], y = table[b].id[0];
            if (x == y || (x == 'o' && y == 'u') || (x == 'e' && y == 'i')) {
                result[i + 1] = !long_only || (x == 'o' && (y == 'o' || y == 'u')) || (x == 'u' && y == 'u');
                i += 2;
                continue;
            }
        }
        ++i;
    }
    if (long_only) {
        for (int i = 0; i < w->count; ++i) if (w->tokens[i].id == L) result[i] = true;
    }
}
static void parts(const Word *w, int system, int mode, char result[CAP][8]) {
    bool long_elements[CAP];
    pairs(w, long_elements, true);
    for (int i = 0; i < w->count; ++i) {
        char *s = result[i];
        s[0] = '\0';
        int id = w->tokens[i].id, next_id = i + 1 < w->count ? w->tokens[i + 1].id : -1;
        const char *next = next_id >= 0 && next_id < N ? table[next_id].spelling[system] : "";
        char first = next[0];
        if (long_elements[i]) {
            const char *previous = table[w->tokens[i - 1].id].id;
            char v = previous[strlen(previous) - 1];
            if (mode == 0) strcpy(s, id == L ? "-" : table[id].spelling[system]);
            if (mode == 2 && v == 'o' && !vowel(first)) strcpy(s, "h");
            if (mode == 3) strcpy(s, "-");
            if (mode == 4) {
                s[0] = v;
                s[1] = '\0';
            }
        } else if (id < N) strcpy(s, table[id].spelling[system]);
        else if (id == N) {
            if (system == 4) strcpy(s, next_id == N || vowel(first) || first == 'y' || first == 'n' ? "nn" : "n");
            else if (system == 1 && first && strchr("bmp", first)) strcpy(s, "m");
            else strcpy(s, vowel(first) || first == 'y' ? "n'" : "n");
        } else if (id == Q) {
            if (first && !vowel(first) && first != 'n') {
                s[0] = system <= 1 && !strncmp(next, "ch", 2) ? 't' : first;
                s[1] = '\0';
            } else if (system == 4) strcpy(s, "xtu");
            else column_error(w->tokens[i].col, "small tsu cannot be written");
        }
    }
}
static void write_word(const Word *w, int system, bool canonical, char *output) {
    char pieces[CAP][8];
    parts(w, system, canonical ? 0 : long_mode, pieces);
    output[0] = '\0';
    for (int i = 0; i < w->count; ++i) strcat(output, pieces[i]);
    int pattern = canonical || case_mode == 0 ? w->pattern : case_mode == 1 ? 0 : case_mode == 2 ? 2 : 1;
    if (pattern == 1) output[0] = upper(output[0]);
    if (pattern == 2) for (int i = 0; output[i]; ++i) output[i] = upper(output[i]);
}
static bool same_sequence(const Word *a, const Word *b, bool loose) {
    bool omit_a[CAP], omit_b[CAP];
    pairs(a, omit_a, true);
    pairs(b, omit_b, true);
    int i = 0, j = 0;
    for (;;) {
        while (loose && i < a->count && omit_a[i]) ++i;
        while (loose && j < b->count && omit_b[j]) ++j;
        if (i == a->count || j == b->count) return i == a->count && j == b->count;
        if (a->tokens[i++].id != b->tokens[j++].id) return false;
    }
}
static int elements(const Word *w, Element *result) {
    int count = 0;
    for (int i = 0; i < w->count; ++i) {
        int id = w->tokens[i].id;
        if (id == L) continue;
        if (id == N) result[count++] = (Element){N, 0, 0};
        else if (id == Q) result[count++] = (Element){mora_id("tu"), 0, 1};
        else {
            const Mora *m = &table[id];
            char base[5];
            strcpy(base, m->id);
            if (m->voice) base[0] = "ksthh"[m->row - 10];
            if (strlen(m->dan) == 2) {
                base[1] = 'i';
                base[2] = '\0';
                result[count++] = (Element){mora_id(base), m->voice, 0};
                result[count++] = (Element){mora_id(m->dan), 0, 1};
            } else result[count++] = (Element){mora_id(base), m->voice, 0};
        }
    }
    return count;
}
static int rank_of(int id) {
    const char *order = order_mode == 0
        ? "a i u e o ka ki ku ke ko sa si su se so ta ti tu te to na ni nu ne no ha hi hu he ho ma mi mu me mo ya yu yo ra ri ru re ro wa wi we wo N"
        : "i ro ha ni ho he to ti ri nu ru wo wa ka yo ta re so tu ne na ra mu u wi no o ku ya ma ke hu ko e te a sa ki yu me mi si we hi mo se su N";
    const char *name = id == N ? "N" : table[id].id;
    int rank = 0;
    for (const char *p = order; *p;) {
        const char *end = strchr(p, ' ');
        int n = end ? (int)(end - p) : (int)strlen(p);
        if ((int)strlen(name) == n && !strncmp(p, name, n)) return rank;
        ++rank;
        if (!end) break;
        p = end + 1;
    }
    return -1;
}
static int compare_words(const void *left, const void *right) {
    const Word *a = left, *b = right;
    Element ea[CAP * 2], eb[CAP * 2];
    int na = elements(a, ea), nb = elements(b, eb);
    for (int field = 0; field < 3; ++field) {
        for (int i = 0; i < na && i < nb; ++i) {
            int x = field == 0 ? rank_of(ea[i].id) : field == 1 ? ea[i].voice : ea[i].size;
            int y = field == 0 ? rank_of(eb[i].id) : field == 1 ? eb[i].voice : eb[i].size;
            if (x != y) return x < y ? -1 : 1;
        }
        if (na != nb) return na < nb ? -1 : 1;
    }
    for (int i = 0; i < a->count && i < b->count; ++i) {
        int x = a->tokens[i].id == L, y = b->tokens[i].id == L;
        if (x != y) return x < y ? -1 : 1;
    }
    if (a->count != b->count) return a->count < b->count ? -1 : 1;
    return a->start < b->start ? -1 : a->start > b->start;
}
static int pattern_tokens(const char *pattern, int system, int *result) {
    int count = 0, start = 0, n = (int)strlen(pattern);
    for (int i = 0; i <= n; ++i) {
        char c = pattern[i];
        if (!c || c == '?' || c == '*') {
            if (i > start) {
                Word w = {0};
                memcpy(w.original, pattern + start, i - start);
                if (!parse(&w, system)) fail("invalid pattern");
                for (int j = 0; j < w.count; ++j) result[count++] = w.tokens[j].id;
            }
            if (c) result[count++] = c == '?' ? -1 : -2;
            start = i + 1;
        } else if (!((c >= 'a' && c <= 'z') || c == '\'' || c == '-')) fail("invalid pattern");
    }
    return count;
}
static bool glob(const int *pattern, int length, const Word *w) {
    bool dp[CAP] = {true};
    for (int i = 0; i < length; ++i) {
        bool next[CAP] = {false};
        if (pattern[i] == -2) {
            next[0] = dp[0];
            for (int j = 1; j <= w->count; ++j) next[j] = dp[j] || next[j - 1];
        } else {
            for (int j = 1; j <= w->count; ++j) next[j] = dp[j - 1] && (pattern[i] == -1 || pattern[i] == w->tokens[j - 1].id);
        }
        memcpy(dp, next, sizeof dp);
    }
    return dp[w->count];
}
static void process(const char *line, Buffer *out) {
    const char *names[] = {"SET", "TABLE", "CONVERT", "NORMALIZE", "REVERSE", "VALID", "DETECT", "DIFF", "SAME", "MORAE", "SYLLABLES", "ROW", "STATS", "SORT", "INDEX", "FIND", "HAIKU", "KAIBUN", "SHIRITORI"};
    const int fixed[] = {2, 2, 2, 0, 1, 1, 0, 2, 2, 1, 1, 1, 1, 1, 1, 2, 1, 1, 1};
    char command[CAP], args[2][CAP] = {{0}}, text[CAP] = {0};
    const char *space = strchr(line, ' ');
    int name_length = space ? (int)(space - line) : (int)strlen(line);
    memcpy(command, line, name_length);
    command[name_length] = '\0';
    int cmd = lookup(names, 19, command);
    if (cmd < 0) named_error("unknown command", command);
    if (cmd <= 1) {
        int spaces = 0;
        for (const char *p = line; *p; ++p) if (*p == ' ') ++spaces;
        if (spaces < 2) fail("missing argument");
        if (spaces > 2) fail("too many arguments");
        const char *second = strchr(space + 1, ' ');
        memcpy(args[0], space + 1, second - space - 1);
        strcpy(args[1], second + 1);
    } else {
        const char *p = line;
        for (int i = 0; i <= fixed[cmd]; ++i) {
            const char *end = strchr(p, ' ');
            if (!end) fail("missing argument");
            if (i) memcpy(args[i - 1], p, end - p);
            p = end + 1;
        }
        strcpy(text, p);
    }
    if (cmd == 0) {
        const char *options[] = {"LONG", "CASE", "ORDER"};
        const char *values[3][5] = {{"KEEP", "DROP", "PASSPORT", "HYPHEN", "DOUBLE"}, {"KEEP", "LOWER", "UPPER", "TITLE"}, {"GOJUON", "IROHA"}};
        const int sizes[] = {5, 4, 2};
        int option = lookup(options, 3, args[0]);
        if (option < 0) named_error("unknown option", args[0]);
        int value = lookup(values[option], sizes[option], args[1]);
        if (value < 0) named_error("unknown value", args[1]);
        if (option == 0) long_mode = value;
        if (option == 1) case_mode = value;
        if (option == 2) order_mode = value;
        append(out, args[0]);
        append(out, "=");
        append(out, args[1]);
        return;
    }
    int system_count = cmd == 3 || cmd == 6 ? 0 : cmd == 2 || cmd == 7 || cmd == 8 ? 2 : 1;
    int sys[2] = {-1, -1};
    for (int i = 0; i < system_count; ++i) {
        sys[i] = lookup(systems, 5, args[i]);
        if (sys[i] < 0) named_error("unknown system", args[i]);
    }
    int source = sys[0];
    if (cmd == 1) {
        int row = lookup(rows, 15, args[1]);
        if (row < 0) named_error("unknown row", args[1]);
        for (int i = 0; i < N; ++i) if (table[i].row == row) item(out, table[i].spelling[source], " ");
        return;
    }
    int pattern[CAP], pattern_length = 0;
    if (cmd == 15) pattern_length = pattern_tokens(args[1], source, pattern);
    for (int i = 0; text[i]; ++i) {
        char c = text[i];
        if (!word_char(c) && !(c >= '0' && c <= '9') && !strchr(" .,!?;:()\"", c) && !((cmd == 8 || cmd == 16) && c == '/')) column_error(i + 1, "invalid character");
    }
    Word words[CAP];
    int count = lex(text, words), sections = 1, section_words[CAP] = {0};
    for (int i = 0; text[i]; ++i) if (text[i] == '/') ++sections;
    for (int i = 0; i < count; ++i) ++section_words[words[i].section];
    if (cmd == 8 && (sections != 2 || !section_words[0] || !section_words[1])) fail("expected two texts");
    if (cmd == 16) {
        if (sections != 3 && sections != 5) fail("expected 3 or 5 lines");
        for (int i = 0; i < sections; ++i) if (!section_words[i]) fail("expected 3 or 5 lines");
    }
    if (!count) fail("no words");
    for (int i = 0; i < count; ++i) check_case(&words[i]);
    if (cmd == 6) {
        for (int s = 0; s < 5; ++s) {
            bool readable = true, canonical = true;
            for (int i = 0; i < count; ++i) {
                if (!parse(&words[i], s)) {
                    readable = false;
                    break;
                }
            }
            if (readable) {
                for (int i = 0; i < count; ++i) {
                    char written[CAP * 4];
                    write_word(&words[i], s, true, written);
                    if (strcmp(written, words[i].original)) canonical = false;
                }
            }
            if (s) append(out, " ");
            append(out, systems[s]);
            append(out, "=");
            append(out, !readable ? "error" : canonical ? "canonical" : "readable");
        }
        return;
    }
    for (int i = 0; i < count; ++i) {
        if (!parse(&words[i], cmd == 8 && words[i].section == 1 ? sys[1] : source)) fail(error_message);
    }
    if (cmd == 2 || cmd == 3 || cmd == 4) {
        int pos = 0;
        for (int j = 0; j < count; ++j) {
            Word *w = &words[j];
            char separators[CAP] = {0}, written[CAP * 4];
            memcpy(separators, text + pos, w->start - pos);
            append(out, separators);
            if (cmd == 4) {
                for (int i = 0; i < w->count; ++i) {
                    if (w->tokens[i].id == L) {
                        const char *id = table[w->tokens[i - 1].id].id;
                        char v[] = {id[strlen(id) - 1], '\0'};
                        w->tokens[i].id = mora_id(v);
                    }
                }
                for (int i = 0; i < w->count / 2; ++i) {
                    Token t = w->tokens[i];
                    w->tokens[i] = w->tokens[w->count - 1 - i];
                    w->tokens[w->count - 1 - i] = t;
                }
            }
            write_word(w, cmd == 2 ? sys[1] : cmd == 3 ? 0 : source, false, written);
            append(out, written);
            pos = w->end;
        }
        append(out, text + pos);
        return;
    }
    if (cmd == 5) {
        for (int i = 0; i < count; ++i) {
            char canonical[CAP * 4];
            write_word(&words[i], source, true, canonical);
            if (strcmp(canonical, words[i].original)) {
                int p = 0;
                while (canonical[p] && words[i].original[p] && canonical[p] == words[i].original[p]) ++p;
                append(out, "INVALID col ");
                number(out, words[i].start + p + 1);
                append(out, ": expected ");
                append(out, canonical);
                return;
            }
        }
        append(out, "VALID");
        return;
    }
    if (cmd == 7 || cmd == 15) {
        Buffer selected = {{0}, 0};
        int matches = 0;
        for (int i = 0; i < count; ++i) {
            if (cmd == 7) {
                char a[CAP * 4], b[CAP * 4];
                write_word(&words[i], source, false, a);
                write_word(&words[i], sys[1], false, b);
                if (strcmp(a, b)) {
                    if (matches++) append(&selected, " ");
                    append(&selected, a);
                    append(&selected, ">");
                    append(&selected, b);
                }
            } else if (glob(pattern, pattern_length, &words[i])) {
                if (matches++) append(&selected, " ");
                append(&selected, words[i].original);
            }
        }
        number(out, matches);
        append(out, " of ");
        number(out, count);
        if (matches) {
            append(out, ": ");
            append(out, selected.data);
        }
        return;
    }
    if (cmd == 8) {
        int left = section_words[0], right = section_words[1];
        bool exact = true;
        for (int i = 0; i < left && i < right; ++i) {
            if (!same_sequence(&words[i], &words[left + i], true)) {
                append(out, "DIFFERENT at word ");
                number(out, i + 1);
                return;
            }
            if (!same_sequence(&words[i], &words[left + i], false)) exact = false;
        }
        if (left != right) {
            append(out, "DIFFERENT at word ");
            number(out, (left < right ? left : right) + 1);
        } else append(out, exact ? "EXACT" : "LOOSE");
        return;
    }
    if (cmd == 9 || cmd == 10) {
        Buffer body = {{0}, 0};
        int total = 0;
        for (int j = 0; j < count; ++j) {
            const Word *w = &words[j];
            char canonical[CAP][8];
            bool paired[CAP];
            if (cmd == 10) {
                parts(w, source, 0, canonical);
                pairs(w, paired, false);
            }
            if (j) append(&body, " ");
            for (int i = 0; i < w->count; ++i) {
                int id = w->tokens[i].id;
                bool starts = cmd == 9 || i == 0 || (id < N && !paired[i]);
                if (starts) {
                    if (i) append(&body, ".");
                    ++total;
                }
                append(&body, cmd == 10 ? canonical[i] : id < N ? table[id].spelling[source] : id == N ? "N" : id == Q ? "Q" : "-");
            }
        }
        number(out, total);
        append(out, ": ");
        append(out, body.data);
        return;
    }
    if (cmd == 11) {
        for (int j = 0; j < count; ++j) {
            for (int i = 0; i < words[j].count; ++i) {
                int id = words[j].tokens[i].id;
                if (out->size) append(out, ", ");
                append(out, id < N ? table[id].spelling[source] : id == N ? "N" : id == Q ? "Q" : "-");
                append(out, ": ");
                if (id < N) {
                    append(out, rows[table[id].row]);
                    append(out, " ");
                    append(out, table[id].dan);
                } else append(out, "special");
            }
        }
        return;
    }
    if (cmd == 12) {
        int row_counts[10] = {0}, other[6] = {0}, total = 0;
        for (int j = 0; j < count; ++j) {
            for (int i = 0; i < words[j].count; ++i) {
                int id = words[j].tokens[i].id;
                ++total;
                if (id < N) {
                    ++row_counts[table[id].base];
                    if (table[id].voice) ++other[table[id].voice - 1];
                    if (strlen(table[id].dan) == 2) ++other[2];
                } else ++other[id - N + 3];
            }
        }
        append(out, "morae=");
        number(out, total);
        for (int r = 0; r < 10; ++r) {
            if (row_counts[r]) {
                append(out, " ");
                append(out, rows[r]);
                append(out, "=");
                number(out, row_counts[r]);
            }
        }
        const char *labels[] = {"voiced", "semivoiced", "contracted", "N", "Q", "L"};
        for (int i = 0; i < 6; ++i) {
            append(out, " ");
            append(out, labels[i]);
            append(out, "=");
            number(out, other[i]);
        }
        return;
    }
    if (cmd == 13 || cmd == 14) {
        qsort(words, count, sizeof *words, compare_words);
        char previous[8] = "";
        for (int i = 0; i < count; ++i) {
            if (cmd == 13) item(out, words[i].original, " ");
            else {
                Element e[CAP * 2];
                elements(&words[i], e);
                int id = e[0].id;
                const char *heading = id == N ? "N" : order_mode == 1 ? table[id].id : rows[table[id].row];
                if (!strcmp(previous, heading)) append(out, " ");
                else {
                    if (i) append(out, "; ");
                    append(out, heading);
                    append(out, ": ");
                }
                append(out, words[i].original);
                strcpy(previous, heading);
            }
        }
        return;
    }
    if (cmd == 16) {
        int counts[5] = {0}, expected[] = {5, 7, 5, 7, 7};
        bool ok = true;
        for (int i = 0; i < count; ++i) counts[words[i].section] += words[i].count;
        for (int i = 0; i < sections; ++i) if (counts[i] != expected[i]) ok = false;
        append(out, ok ? "OK " : "NG ");
        append(out, sections == 3 ? "haiku " : "tanka ");
        for (int i = 0; i < sections; ++i) {
            if (i) append(out, "-");
            number(out, counts[i]);
        }
        return;
    }
    if (cmd == 17) {
        int kana[CAP * 2], length = 0;
        for (int i = 0; i < count; ++i) {
            Element e[CAP * 2];
            int n = elements(&words[i], e);
            for (int j = 0; j < n; ++j) kana[length++] = e[j].id;
        }
        bool palindrome = true;
        for (int i = 0; i < length / 2; ++i) if (kana[i] != kana[length - 1 - i]) palindrome = false;
        append(out, palindrome ? "YES " : "NO ");
        for (int i = 0; i < length; ++i) {
            if (i) append(out, ".");
            append(out, kana[i] == N ? "N" : table[kana[i]].id);
        }
        return;
    }
    int previous_tail = -1;
    for (int i = 0; i < count; ++i) {
        Element e[CAP * 2];
        int length = elements(&words[i], e), reason = 0;
        if (i && e[0].id != previous_tail) reason = 1;
        if (!reason) {
            for (int j = 0; j < i; ++j) {
                if (same_sequence(&words[i], &words[j], false)) {
                    reason = 2;
                    break;
                }
            }
        }
        if (!reason && e[length - 1].id == N) reason = 3;
        if (reason) {
            append(out, "NG ");
            number(out, i + 1);
            append(out, ": ");
            append(out, words[i].original);
            if (reason == 1) {
                append(out, " must start with ");
                append(out, table[previous_tail].spelling[source]);
            }
            if (reason == 2) append(out, " is repeated");
            if (reason == 3) append(out, " ends with N");
            return;
        }
        previous_tail = e[length - 1].id;
    }
    append(out, "OK ");
    number(out, count);
}
int main(void) {
    initialize();
    char line[CAP];
    if (!fgets(line, sizeof line, stdin)) return 0;
    int count = atoi(line);
    for (int i = 0; i < count; ++i) {
        if (!fgets(line, sizeof line, stdin)) break;
        line[strcspn(line, "\r\n")] = '\0';
        if (setjmp(recovery) == 0) {
            Buffer output = {{0}, 0};
            process(line, &output);
            puts(output.data);
        } else printf("ERROR %s\n", error_message);
    }
    return 0;
}
