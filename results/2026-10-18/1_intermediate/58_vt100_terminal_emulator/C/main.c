#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

typedef struct { char *data; size_t length, capacity; } String;
static void append(String *s, char c) {
    if (s->length + 2 > s->capacity) {
        s->capacity = s->capacity ? s->capacity * 2 : 64;
        s->data = realloc(s->data, s->capacity);
        if (!s->data) exit(1);
    }
    s->data[s->length++] = c;
    s->data[s->length] = 0;
}
static void clear(String *s) { s->length = 0; if (s->data) s->data[0] = 0; }
static const char *text(const String *s) { return s->data ? s->data : ""; }
static char *copy_text(const char *s) {
    char *r = malloc(strlen(s) + 1);
    if (!r) exit(1);
    strcpy(r, s);
    return r;
}
static int minimum(int a, int b) { return a < b ? a : b; }
static int maximum(int a, int b) { return a > b ? a : b; }

typedef struct { unsigned flags; char fg[20], bg[20]; } Attributes;
typedef struct { char ch; Attributes attr; } Cell;
typedef struct {
    bool present, origin, g0, g1, gl;
    int row, col;
    Attributes attr;
} Saved;
typedef enum { GROUND, ESCAPE, ESC_INTER, CSI_ENTRY, CSI_PARAM,
               CSI_INTER, CSI_IGNORE, OSC } ParserState;
typedef struct {
    int width, height, row, col, top, bottom, screen, shape;
    Cell cells[2][30][80];
    bool pending, modes[9], g0, g1, gl, tabs[81];
    Attributes attr;
    Saved saved[2];
    char *back[100], *title;
    int back_count, last;
    ParserState parser;
    String inter, osc;
    char marker;
    int params[16], field, value;
    bool has_params;
    int bytes, printed, sequences, bells, replies, dumps, ignored[4];
} Terminal;
enum { IRM, LNM, CKM, SCNM, ORIGIN, WRAP, VISIBLE, KEYPAD, BRACKETED };
static Attributes defaults(void) {
    Attributes a = {0};
    strcpy(a.fg, "default"); strcpy(a.bg, "default");
    return a;
}
static Cell blank(void) { Cell c = {' ', {0}}; c.attr = defaults(); return c; }
static bool equal_attr(Attributes a, Attributes b) {
    return a.flags == b.flags && !strcmp(a.fg, b.fg) && !strcmp(a.bg, b.bg);
}
static void erase_row(Terminal *t, int r, int first, int last) {
    for (int c = first; c <= last; ++c) t->cells[t->screen][r-1][c-1] = blank();
}
static void erase_screen(Terminal *t, int screen) {
    for (int r = 0; r < t->height; ++r)
        for (int c = 0; c < t->width; ++c) t->cells[screen][r][c] = blank();
}
static void clear_back(Terminal *t) {
    for (int i = 0; i < t->back_count; ++i) free(t->back[i]);
    t->back_count = 0;
}
static void reset(Terminal *t) {
    erase_screen(t, 0); erase_screen(t, 1);
    t->screen = 0; t->row = t->col = t->top = t->shape = 1;
    t->bottom = t->height; t->pending = false; t->attr = defaults();
    memset(t->modes, 0, sizeof t->modes);
    t->modes[WRAP] = t->modes[VISIBLE] = true;
    t->g0 = t->g1 = t->gl = false;
    memset(t->tabs, 0, sizeof t->tabs);
    for (int c = 9; c <= t->width; c += 8) t->tabs[c] = true;
    memset(t->saved, 0, sizeof t->saved);
    clear_back(t); free(t->title); t->title = NULL; t->last = -1;
    t->parser = GROUND; clear(&t->inter); clear(&t->osc);
    t->marker = 0; t->has_params = false; t->field = t->value = 0;
}
static void row_text(Terminal *t, int row, char out[81]) {
    for (int c = 0; c < t->width; ++c) out[c] = t->cells[t->screen][row-1][c].ch;
    int end = t->width;
    while (end && out[end-1] == ' ') --end;
    out[end] = 0;
}
static void scroll(Terminal *t, bool up, int count) {
    for (int k = 0; k < count; ++k) {
        if (up) {
            if (!t->screen && t->top == 1) {
                char line[81]; row_text(t, t->top, line);
                if (t->back_count == 100) {
                    free(t->back[0]);
                    memmove(t->back, t->back + 1, 99 * sizeof(char *));
                    --t->back_count;
                }
                t->back[t->back_count++] = copy_text(line);
            }
            for (int r = t->top; r < t->bottom; ++r)
                memcpy(t->cells[t->screen][r-1], t->cells[t->screen][r], sizeof t->cells[0][0]);
            erase_row(t, t->bottom, 1, t->width);
        } else {
            for (int r = t->bottom; r > t->top; --r)
                memcpy(t->cells[t->screen][r-1], t->cells[t->screen][r-2], sizeof t->cells[0][0]);
            erase_row(t, t->top, 1, t->width);
        }
    }
}
static void line_feed(Terminal *t) {
    if (t->row == t->bottom) scroll(t, true, 1);
    else if (t->row < t->height) ++t->row;
}
static void tab(Terminal *t, bool reverse) {
    int c = t->col + (reverse ? -1 : 1);
    while (c >= 1 && c <= t->width && !t->tabs[c]) c += reverse ? -1 : 1;
    t->col = maximum(1, minimum(c, t->width));
}
static int address(Terminal *t, int v) {
    return t->modes[ORIGIN] ? minimum(t->top + v - 1, t->bottom) : minimum(v, t->height);
}
static void home(Terminal *t) { t->row = address(t, 1); t->col = 1; }
static void save(Terminal *t) {
    t->saved[t->screen] = (Saved){true, t->modes[ORIGIN], t->g0, t->g1, t->gl,
                                 t->row, t->col, t->attr};
}
static void restore(Terminal *t) {
    Saved s = t->saved[t->screen];
    t->pending = false;
    t->row = s.present ? s.row : 1; t->col = s.present ? s.col : 1;
    t->attr = s.present ? s.attr : defaults();
    t->modes[ORIGIN] = s.present && s.origin;
    t->g0 = s.present && s.g0; t->g1 = s.present && s.g1; t->gl = s.present && s.gl;
}
static void write_char(Terminal *t, char c) {
    ++t->printed; t->last = (unsigned char)c;
    if (t->pending) { t->pending = false; t->col = 1; line_feed(t); }
    Cell *row = t->cells[t->screen][t->row-1];
    if (t->modes[IRM])
        for (int x = t->width-1; x >= t->col; --x) row[x] = row[x-1];
    row[t->col-1] = (Cell){c, t->attr};
    if (t->col < t->width) ++t->col;
    else if (t->modes[WRAP]) t->pending = true;
}
static void print_char(Terminal *t, char c) {
    if (t->gl ? t->g1 : t->g0) {
        if (c == '`') c = '*';
        else if (c == 'a') c = '#';
        else if (strchr("jklmntuvw", c)) c = '+';
        else if (c == 'q') c = '-';
        else if (c == 'x') c = '|';
        else if (c == '~') c = 'o';
    }
    write_char(t, c);
}
static void control(Terminal *t, int b) {
    if (b >= 8 && b <= 13) t->pending = false;
    switch (b) {
        case 7: ++t->bells; break;
        case 8: t->col = maximum(1, t->col-1); break;
        case 9: tab(t, false); break;
        case 10: case 11: case 12:
            line_feed(t); if (t->modes[LNM]) t->col = 1; break;
        case 13: t->col = 1; break;
        case 14: t->gl = true; break;
        case 15: t->gl = false; break;
    }
}
static void palette(int n, char out[20]) {
    static const char *names[] = {"black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"};
    if (n < 8) strcpy(out, names[n]);
    else if (n < 16) snprintf(out, 20, "bright-%s", names[n-8]);
    else snprintf(out, 20, "%d", n);
}
static bool sgr(Terminal *t, const int *p, int count) {
    Attributes a = t->attr;
    for (int i = 0; i < count; ++i) {
        int v = p[i], bit = -1;
        if (v >= 1 && v <= 5) bit = v-1;
        else if (v >= 7 && v <= 9) bit = v-2;
        if (v == 0) a = defaults();
        else if (bit >= 0) a.flags |= 1u << bit;
        else if (v == 22) a.flags &= ~3u;
        else if (v >= 23 && v <= 25) a.flags &= ~(1u << (v-21));
        else if (v >= 27 && v <= 29) a.flags &= ~(1u << (v-22));
        else if (v >= 30 && v <= 37) palette(v-30, a.fg);
        else if (v >= 90 && v <= 97) palette(v-82, a.fg);
        else if (v >= 40 && v <= 47) palette(v-40, a.bg);
        else if (v >= 100 && v <= 107) palette(v-92, a.bg);
        else if (v == 39) strcpy(a.fg, "default");
        else if (v == 49) strcpy(a.bg, "default");
        else if (v == 38 || v == 48) {
            char color[20];
            if (i+2 < count && p[i+1] == 5 && p[i+2] <= 255) {
                palette(p[i+2], color); i += 2;
            } else if (i+4 < count && p[i+1] == 2 && p[i+2] <= 255 && p[i+3] <= 255 && p[i+4] <= 255) {
                snprintf(color, sizeof color, "#%02x%02x%02x", p[i+2], p[i+3], p[i+4]); i += 4;
            } else return false;
            strcpy(v == 38 ? a.fg : a.bg, color);
        } else return false;
    }
    t->attr = a;
    return true;
}
static int mode_index(int p, bool dec) {
    if (!dec) return p == 4 ? IRM : p == 20 ? LNM : -1;
    switch (p) {
        case 1: return CKM; case 5: return SCNM; case 6: return ORIGIN;
        case 7: return WRAP; case 25: return VISIBLE; case 2004: return BRACKETED;
        default: return -1;
    }
}
static bool set_modes(Terminal *t, int *p, int count, bool dec, bool on) {
    for (int i = 0; i < count; ++i)
        if (mode_index(p[i], dec) < 0 && !(dec && (p[i] == 47 || p[i] == 1047 || p[i] == 1048 || p[i] == 1049))) return false;
    for (int i = 0; i < count; ++i) {
        int v = p[i], index = mode_index(v, dec);
        if (index >= 0) {
            t->modes[index] = on;
            if (index == ORIGIN) { t->pending = false; home(t); }
            if (index == WRAP && !on) t->pending = false;
        } else if (v == 1048) {
            if (on) save(t); else restore(t);
        } else {
            t->pending = false;
            if (on && t->screen == 0) {
                if (v == 1049) save(t);
                t->screen = 1;
                if (v == 1049) erase_screen(t, 1);
            } else if (!on && t->screen == 1) {
                if (v == 1047) erase_screen(t, 1);
                t->screen = 0;
                if (v == 1049) restore(t);
            }
        }
    }
    return true;
}
static void execute_osc(Terminal *t) {
    const char *s = text(&t->osc);
    if (!strncmp(s, "0;", 2) || !strncmp(s, "2;", 2)) {
        free(t->title); t->title = copy_text(s+2); ++t->sequences;
    } else ++t->ignored[0];
}
static void execute_escape(Terminal *t, char final) {
    append(&t->inter, final);
    const char *key = text(&t->inter);
    if (!strcmp(key, "7")) save(t);
    else if (!strcmp(key, "8")) restore(t);
    else if (!strcmp(key, "D") || !strcmp(key, "E")) {
        t->pending = false; if (final == 'E') t->col = 1; line_feed(t);
    } else if (!strcmp(key, "M")) {
        t->pending = false;
        if (t->row == t->top) scroll(t, false, 1); else t->row = maximum(1, t->row-1);
    } else if (!strcmp(key, "H")) t->tabs[t->col] = true;
    else if (!strcmp(key, "c")) reset(t);
    else if (!strcmp(key, "=")) t->modes[KEYPAD] = true;
    else if (!strcmp(key, ">")) t->modes[KEYPAD] = false;
    else if (!strcmp(key, "\\")) { }
    else if (!strcmp(key, "(0")) t->g0 = true;
    else if (!strcmp(key, "(B")) t->g0 = false;
    else if (!strcmp(key, ")0")) t->g1 = true;
    else if (!strcmp(key, ")B")) t->g1 = false;
    else if (!strcmp(key, "#8")) {
        for (int r = 0; r < t->height; ++r)
            for (int c = 0; c < t->width; ++c) t->cells[t->screen][r][c] = (Cell){'E', defaults()};
        t->top = 1; t->bottom = t->height; t->modes[ORIGIN] = false;
        t->row = t->col = 1; t->pending = false;
    } else { ++t->ignored[0]; return; }
    ++t->sequences;
}
static void reply(Terminal *t, const char *s) { ++t->replies; printf("REPLY %s\n", s); }
static void execute_csi(Terminal *t, char final) {
    if (t->has_params && t->field >= 16) { ++t->ignored[3]; return; }
    int count = t->has_params ? t->field + 1 : 0;
    if (count) t->params[t->field] = t->value;
    int p = count ? t->params[0] : 0, p2 = count > 1 ? t->params[1] : 0, n = maximum(p, 1);
    String key = {0};
    if (t->marker) append(&key, t->marker);
    for (size_t i = 0; i < t->inter.length; ++i) append(&key, t->inter.data[i]);
    append(&key, final);
    const char *k = text(&key);
    bool supported = true, invalid = false;
    if (strlen(k) == 1 && strchr("ABCDEFGH IJKLM PSTXZ`adef@", final) && final != ' '
        && (final != 'J' || p <= 3) && (final != 'K' || p <= 2))
        t->pending = false;
    switch (strlen(k) == 1 ? final : 0) {
        case 'A': case 'F':
            t->row = maximum(t->row-n, t->row >= t->top ? t->top : 1);
            if (final == 'F') t->col = 1; break;
        case 'B': case 'e': case 'E':
            t->row = minimum(t->row+n, t->row <= t->bottom ? t->bottom : t->height);
            if (final == 'E') t->col = 1; break;
        case 'C': case 'a': t->col = minimum(t->col+n, t->width); break;
        case 'D': t->col = maximum(t->col-n, 1); break;
        case 'G': case '`': t->col = minimum(n, t->width); break;
        case 'H': case 'f': t->row = address(t, n); t->col = minimum(maximum(p2, 1), t->width); break;
        case 'd': t->row = address(t, n); break;
        case 'I': case 'Z': for (int i = 0; i < n; ++i) tab(t, final == 'Z'); break;
        case 'J':
            if (p > 3) { supported = false; break; }
            if (p == 3) clear_back(t);
            else for (int r = 1; r <= t->height; ++r) {
                if (p == 2 || (p == 0 && r > t->row) || (p == 1 && r < t->row)) erase_row(t, r, 1, t->width);
                else if (r == t->row) erase_row(t, r, p == 0 ? t->col : 1, p == 1 ? t->col : t->width);
            }
            break;
        case 'K':
            if (p > 2) supported = false;
            else erase_row(t, t->row, p == 0 ? t->col : 1, p == 1 ? t->col : t->width);
            break;
        case 'X': erase_row(t, t->row, t->col, minimum(t->col+n-1, t->width)); break;
        case '@': case 'P': {
            int amount = minimum(n, t->width-t->col+1);
            Cell *row = t->cells[t->screen][t->row-1];
            if (final == '@') {
                for (int c = t->width-1; c >= t->col-1+amount; --c) row[c] = row[c-amount];
                erase_row(t, t->row, t->col, t->col+amount-1);
            } else {
                for (int c = t->col-1; c < t->width-amount; ++c) row[c] = row[c+amount];
                erase_row(t, t->row, t->width-amount+1, t->width);
            }
            break;
        }
        case 'L': case 'M':
            if (t->row >= t->top && t->row <= t->bottom) {
                int amount = minimum(n, t->bottom-t->row+1);
                if (final == 'L') {
                    for (int r = t->bottom; r >= t->row+amount; --r)
                        memcpy(t->cells[t->screen][r-1], t->cells[t->screen][r-amount-1], sizeof t->cells[0][0]);
                    for (int r = t->row; r < t->row+amount; ++r) erase_row(t, r, 1, t->width);
                } else {
                    for (int r = t->row; r <= t->bottom-amount; ++r)
                        memcpy(t->cells[t->screen][r-1], t->cells[t->screen][r+amount-1], sizeof t->cells[0][0]);
                    for (int r = t->bottom-amount+1; r <= t->bottom; ++r) erase_row(t, r, 1, t->width);
                }
                t->col = 1;
            }
            break;
        case 'S': case 'T': scroll(t, final == 'S', minimum(n, t->bottom-t->top+1)); break;
        case 'b': if (t->last >= 0) { char c = (char)t->last; for (int i = 0; i < n; ++i) write_char(t, c); } break;
        case 'g':
            if (p == 0) t->tabs[t->col] = false;
            else if (p == 3) memset(t->tabs, 0, sizeof t->tabs);
            else supported = false;
            break;
        case 'm': { int zero = 0; supported = sgr(t, count ? t->params : &zero, count ? count : 1); break; }
        case 'h': case 'l': { int zero = 0; supported = set_modes(t, count ? t->params : &zero, count ? count : 1, false, final == 'h'); break; }
        case 'r': {
            int top = p ? p : 1, bottom = minimum(p2 ? p2 : t->height, t->height);
            if (top >= bottom) invalid = true;
            else { t->top = top; t->bottom = bottom; t->pending = false; home(t); }
            break;
        }
        case 's': save(t); break;
        case 'u': restore(t); break;
        case 'n': {
            char answer[80]; int row = t->modes[ORIGIN] ? maximum(t->row-t->top+1, 1) : t->row;
            if (p == 5) reply(t, "^[[0n");
            else if (p == 6) { snprintf(answer, sizeof answer, "^[[%d;%dR", row, t->col); reply(t, answer); }
            else supported = false;
            break;
        }
        case 'c': if (p == 0) reply(t, "^[[?1;2c"); else supported = false; break;
        case 't': {
            char answer[80];
            if (p == 18) { snprintf(answer, sizeof answer, "^[[8;%d;%dt", t->height, t->width); reply(t, answer); }
            else supported = false;
            break;
        }
        default:
            if (!strcmp(k, "?h") || !strcmp(k, "?l")) {
                int zero = 0; supported = set_modes(t, count ? t->params : &zero, count ? count : 1, true, final == 'h');
            } else if (!strcmp(k, " q")) {
                if (p <= 6) t->shape = n; else supported = false;
            } else if (!strcmp(k, "!p")) {
                t->pending = false;
                t->modes[IRM] = t->modes[CKM] = t->modes[ORIGIN] = t->modes[KEYPAD] = false;
                t->modes[WRAP] = t->modes[VISIBLE] = true;
                t->top = 1; t->bottom = t->height; t->attr = defaults();
                t->g0 = t->g1 = t->gl = false; t->saved[t->screen].present = false;
            } else if (!strcmp(k, "?n") && p == 6) {
                char answer[80]; int row = t->modes[ORIGIN] ? maximum(t->row-t->top+1, 1) : t->row;
                snprintf(answer, sizeof answer, "^[[?%d;%d;1R", row, t->col); reply(t, answer);
            } else if (!strcmp(k, ">c") && p == 0) reply(t, "^[[>0;95;0c");
            else if (!strcmp(k, "$p") || !strcmp(k, "?$p")) {
                bool dec = k[0] == '?'; int index = mode_index(p, dec), state = 0;
                if (index >= 0) state = t->modes[index] ? 1 : 2;
                else if (dec && (p == 47 || p == 1047 || p == 1049)) state = t->screen ? 1 : 2;
                char answer[80]; snprintf(answer, sizeof answer, "^[[%s%d;%d$y", dec ? "?" : "", p, state); reply(t, answer);
            } else supported = false;
    }
    /* Unsupported ED/EL must not clear pending wrap. */
    if (invalid) ++t->ignored[3];
    else if (!supported) ++t->ignored[0];
    else ++t->sequences;
    free(key.data);
}
static void feed(Terminal *t, int b) {
    ++t->bytes;
    if (b == 27) {
        if (t->parser == OSC) execute_osc(t);
        else if (t->parser != GROUND) ++t->ignored[2];
        clear(&t->inter); clear(&t->osc); t->marker = 0;
        t->has_params = false; t->field = t->value = 0; t->parser = ESCAPE;
        return;
    }
    if (b == 24 || b == 26) {
        if (t->parser != GROUND) ++t->ignored[2];
        t->parser = GROUND; return;
    }
    if (b < 32) {
        if (t->parser == OSC) {
            if (b == 7) { execute_osc(t); t->parser = GROUND; }
        } else control(t, b);
        return;
    }
    switch (t->parser) {
        case GROUND: print_char(t, (char)b); break;
        case OSC: append(&t->osc, (char)b); break;
        case ESCAPE:
            if (b >= 32 && b <= 47) { append(&t->inter, (char)b); t->parser = ESC_INTER; }
            else if (b == '[') t->parser = CSI_ENTRY;
            else if (b == ']') t->parser = OSC;
            else { execute_escape(t, (char)b); t->parser = GROUND; }
            break;
        case ESC_INTER:
            if (b <= 47) append(&t->inter, (char)b);
            else { execute_escape(t, (char)b); t->parser = GROUND; }
            break;
        case CSI_ENTRY:
            if (b >= 60 && b <= 63) { t->marker = (char)b; t->parser = CSI_PARAM; break; }
            t->parser = CSI_PARAM;
            /* fall through */
        case CSI_PARAM:
            if (b >= '0' && b <= '9') { t->has_params = true; t->value = minimum(9999, t->value*10+b-'0'); }
            else if (b == ';') {
                t->has_params = true;
                if (t->field < 16) t->params[t->field] = t->value;
                if (t->field < 16) ++t->field;
                t->value = 0;
            } else if (b <= 47) { append(&t->inter, (char)b); t->parser = CSI_INTER; }
            else if (b < 64) t->parser = CSI_IGNORE;
            else { execute_csi(t, (char)b); t->parser = GROUND; }
            break;
        case CSI_INTER:
            if (b <= 47) append(&t->inter, (char)b);
            else if (b < 64) t->parser = CSI_IGNORE;
            else { execute_csi(t, (char)b); t->parser = GROUND; }
            break;
        case CSI_IGNORE:
            if (b >= 64) { ++t->ignored[1]; t->parser = GROUND; }
            break;
    }
}
static void dump(Terminal *t, const char *label) {
    printf("%s %s cursor %d,%d scrollback %d%s\n", label, t->screen ? "alt" : "main", t->row, t->col, t->back_count, t->pending ? " pending" : "");
    for (int r = 1; r <= t->height; ++r) { char line[81]; row_text(t, r, line); printf("|%s\n", line); }
}
static void key(Terminal *t, const char *name) {
    static const char *navigation[] = {"UP", "DOWN", "RIGHT", "LEFT", "HOME", "END"};
    char answer[80] = "";
    for (int i = 0; i < 6; ++i)
        if (!strcmp(name, navigation[i])) snprintf(answer, sizeof answer, "^[%c%c", t->modes[CKM] ? 'O' : '[', "ABCDHF"[i]);
    if (!strcmp(name, "INSERT")) strcpy(answer, "^[[2~");
    else if (!strcmp(name, "DELETE")) strcpy(answer, "^[[3~");
    else if (!strcmp(name, "PAGEUP")) strcpy(answer, "^[[5~");
    else if (!strcmp(name, "PAGEDOWN")) strcpy(answer, "^[[6~");
    else if (name[0] == 'F') {
        int f = atoi(name+1); const int codes[] = {15,17,18,19,20,21,23,24};
        if (f <= 4) snprintf(answer, sizeof answer, "^[O%c", 'P'+f-1);
        else snprintf(answer, sizeof answer, "^[[%d~", codes[f-5]);
    } else if (!strcmp(name, "TAB")) strcpy(answer, "^I");
    else if (!strcmp(name, "BACKSPACE")) strcpy(answer, "^?");
    else if (!strcmp(name, "ESCAPE")) strcpy(answer, "^[");
    else if (!strcmp(name, "ENTER") || !strcmp(name, "KPENTER")) {
        strcpy(answer, !strcmp(name, "KPENTER") && t->modes[KEYPAD] ? "^[OM" : t->modes[LNM] ? "^M^J" : "^M");
    } else if (!strncmp(name, "KP", 2) && strlen(name) == 3) {
        if (t->modes[KEYPAD]) snprintf(answer, sizeof answer, "^[O%c", 'p'+name[2]-'0');
        else snprintf(answer, sizeof answer, "%c", name[2]);
    }
    printf("KEY %s %s\n", name, answer);
}
static void attr_text(Attributes a) {
    static const char *names[] = {"bold", "dim", "italic", "underline", "blink", "reverse", "hidden", "strike"};
    bool first = true;
    for (int i = 0; i < 8; ++i) if (a.flags & (1u << i)) {
        printf("%s%s", first ? "" : " ", names[i]); first = false;
    }
    if (strcmp(a.fg, "default")) { printf("%sfg=%s", first ? "" : " ", a.fg); first = false; }
    if (strcmp(a.bg, "default")) printf("%sbg=%s", first ? "" : " ", a.bg);
}
static void final_output(Terminal *t) {
    if (t->parser != GROUND) ++t->ignored[2];
    dump(t, "FINAL");
    if (t->title) printf("TITLE \"%s\"\n", t->title); else puts("TITLE none");
    static const char *names[] = {"IRM","LNM","DECCKM","DECSCNM","DECOM","DECAWM","DECTCEM","DECKPAM","BRACKETED"};
    bool changed = false;
    printf("MODES");
    for (int i = 0; i < 9; ++i) if (t->modes[i] != (i == WRAP || i == VISIBLE)) {
        printf(" %s=%s", names[i], t->modes[i] ? "on" : "off"); changed = true;
    }
    if (t->g0) { printf(" G0=graphics"); changed = true; }
    if (t->g1) { printf(" G1=graphics"); changed = true; }
    if (t->gl) { printf(" GL=G1"); changed = true; }
    if (t->shape != 1) { printf(" CURSOR=%d", t->shape); changed = true; }
    puts(changed ? "" : " default");
    printf("REGION %d-%d\nTABS ", t->top, t->bottom);
    bool first = true;
    for (int c = 1; c <= t->width; ++c) if (t->tabs[c]) { printf("%s%d", first ? "" : ",", c); first = false; }
    puts(first ? "none" : "");
    printf("SCROLLBACK %d\n", t->back_count);
    for (int i = maximum(0, t->back_count-5); i < t->back_count; ++i) printf("|%s\n", t->back[i]);
    int runs = 0;
    for (int r = 0; r < t->height; ++r) for (int c = 0; c < t->width;) {
        Attributes a = t->cells[t->screen][r][c].attr;
        int end = c+1;
        while (end < t->width && equal_attr(a, t->cells[t->screen][r][end].attr)) ++end;
        if (!equal_attr(a, defaults())) ++runs;
        c = end;
    }
    printf("ATTRS %d\n", runs);
    for (int r = 0; r < t->height; ++r) for (int c = 0; c < t->width;) {
        Attributes a = t->cells[t->screen][r][c].attr;
        int end = c+1;
        while (end < t->width && equal_attr(a, t->cells[t->screen][r][end].attr)) ++end;
        if (!equal_attr(a, defaults())) { printf("row %d col %d-%d ", r+1, c+1, end); attr_text(a); putchar('\n'); }
        c = end;
    }
    printf("BELL %d\nREPLIES %d\nSTATS bytes=%d printed=%d sequences=%d\n", t->bells, t->replies, t->bytes, t->printed, t->sequences);
    printf("IGNORED %d unsupported=%d malformed=%d canceled=%d invalid=%d\n", t->ignored[0]+t->ignored[1]+t->ignored[2]+t->ignored[3], t->ignored[0], t->ignored[1], t->ignored[2], t->ignored[3]);
}
int main(void) {
    Terminal *t = calloc(1, sizeof *t);
    if (!t) return 1;
    scanf("%d %d", &t->width, &t->height);
    int b; while ((b = getchar()) != '\n' && b != EOF) { }
    reset(t);
    String line = {0};
    while ((b = getchar()) != EOF) {
        if (b != '\n') { append(&line, (char)b); continue; }
        const char *s = text(&line);
        if (!strcmp(s, "%%END")) { final_output(t); break; }
        if (!strcmp(s, "%%DUMP")) { char label[40]; snprintf(label, sizeof label, "DUMP %d", ++t->dumps); dump(t, label); }
        else if (!strncmp(s, "%%KEY ", 6)) key(t, s+6);
        else if (!strncmp(s, "%%PASTE ", 8)) {
            printf("PASTE %s", t->modes[BRACKETED] ? "^[[200~" : "");
            for (const char *p = s+8; *p; ++p) { putchar(*p); if (*p == '^') putchar('^'); }
            printf("%s\n", t->modes[BRACKETED] ? "^[[201~" : "");
        } else for (size_t i = 0; i < line.length; ++i) {
            int value = (unsigned char)s[i];
            if (value == '^') { value = (unsigned char)s[++i]; if (value != '^') value -= 64; }
            feed(t, value);
        }
        clear(&line);
    }
    if (b == EOF && !strcmp(text(&line), "%%END")) final_output(t);
    clear_back(t); free(t->title); free(t->inter.data); free(t->osc.data); free(line.data); free(t);
    return 0;
}
