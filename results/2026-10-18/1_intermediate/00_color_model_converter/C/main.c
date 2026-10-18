#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>

typedef long long Int;
typedef struct { Int x[3]; } Color;
typedef struct { Int h, s, l; } Hsl;
typedef struct { Int ratio; const char *verdict; } Contrast;
typedef struct { Color colors[32]; int count; } Box;
typedef struct {
    const char *name, *signature;
    int minimum, maximum;
    Int low[4], high[4];
    const char *keywords;
} Spec;
typedef struct { Color colors[33]; Int numbers[33]; int keyword; } Arguments;

typedef struct { char name[13]; Color color; } Entry;
typedef struct { Entry entries[500]; int count; } State;
typedef struct { char data[32768]; size_t length; } Text;
static const char *entry_name(const Entry *entry) { return entry->name; }
static int registered_count(const State *state) { return state->count; }
static const Entry *registered_entry(const State *state, int i) { return &state->entries[i]; }
static void registry_set(State *state, const char *name, Color color) {
    int i = 0;
    while (i < state->count && strcmp(state->entries[i].name, name) != 0) ++i;
    if (i == state->count) {
        strcpy(state->entries[i].name, name);
        ++state->count;
    }
    state->entries[i].color = color;
}
static void registry_delete(State *state, int index) {
    for (int i = index; i + 1 < state->count; ++i) state->entries[i] = state->entries[i + 1];
    --state->count;
}
static void wordf(Text *output, const char *format, ...) {
    if (output->length != 0) output->data[output->length++] = ' ';
    va_list arguments;
    va_start(arguments, format);
    int written = vsnprintf(output->data + output->length, sizeof output->data - output->length,
                            format, arguments);
    va_end(arguments);
    output->length += (size_t)written;
}

enum Operation {
    OP_PARSE,
    OP_DEFINE,
    OP_UNDEFINE,
    OP_LIST,
    OP_HSL,
    OP_FROMHSL,
    OP_HSV,
    OP_FROMHSV,
    OP_HWB,
    OP_FROMHWB,
    OP_CMYK,
    OP_FROMCMYK,
    OP_YCBCR,
    OP_FROMYCBCR,
    OP_YIQ,
    OP_FROMYIQ,
    OP_RGB565,
    OP_FROM565,
    OP_ANSI,
    OP_FROMANSI,
    OP_WEBSAFE,
    OP_GRAY,
    OP_INVERT,
    OP_MIX,
    OP_MIXHSL,
    OP_GRADIENT,
    OP_TINTS,
    OP_SHADES,
    OP_TONES,
    OP_BLEND,
    OP_ALPHA,
    OP_SIMULATE,
    OP_ROTATE,
    OP_COMPLEMENT,
    OP_TRIADIC,
    OP_TETRADIC,
    OP_SPLITCOMP,
    OP_ANALOGOUS,
    OP_LIGHTEN,
    OP_DARKEN,
    OP_SATURATE,
    OP_DESATURATE,
    OP_NEAREST,
    OP_DISTANCE,
    OP_CONTRAST,
    OP_ACCESSIBLE,
    OP_BEST,
    OP_DESCRIBE,
    OP_PALETTE,
    OP_KMEANS,
    OP_SORT,
    OP_DITHER,
    OP_RANDOM
};

static const Spec specifications[] = {
    {"PARSE", "C", 1, 1, {0,0,0,0}, {0,0,0,0}, ""},
    {"DEFINE", "NC", 2, 2, {0,0,0,0}, {0,0,0,0}, ""},
    {"UNDEFINE", "N", 1, 1, {0,0,0,0}, {0,0,0,0}, ""},
    {"LIST", "", 0, 0, {0,0,0,0}, {0,0,0,0}, ""},
    {"HSL", "C", 1, 1, {0,0,0,0}, {0,0,0,0}, ""},
    {"FROMHSL", "III", 3, 3, {0,0,0,0}, {359,100,100,0}, ""},
    {"HSV", "C", 1, 1, {0,0,0,0}, {0,0,0,0}, ""},
    {"FROMHSV", "III", 3, 3, {0,0,0,0}, {359,100,100,0}, ""},
    {"HWB", "C", 1, 1, {0,0,0,0}, {0,0,0,0}, ""},
    {"FROMHWB", "III", 3, 3, {0,0,0,0}, {359,100,100,0}, ""},
    {"CMYK", "C", 1, 1, {0,0,0,0}, {0,0,0,0}, ""},
    {"FROMCMYK", "IIII", 4, 4, {0,0,0,0}, {100,100,100,100}, ""},
    {"YCBCR", "C", 1, 1, {0,0,0,0}, {0,0,0,0}, ""},
    {"FROMYCBCR", "III", 3, 3, {0,0,0,0}, {255,255,255,0}, ""},
    {"YIQ", "C", 1, 1, {0,0,0,0}, {0,0,0,0}, ""},
    {"FROMYIQ", "III", 3, 3, {0,-255,-255,0}, {255,255,255,0}, ""},
    {"RGB565", "C", 1, 1, {0,0,0,0}, {0,0,0,0}, ""},
    {"FROM565", "W", 1, 1, {0,0,0,0}, {0,0,0,0}, ""},
    {"ANSI", "C", 1, 1, {0,0,0,0}, {0,0,0,0}, ""},
    {"FROMANSI", "I", 1, 1, {0,0,0,0}, {255,0,0,0}, ""},
    {"WEBSAFE", "C", 1, 1, {0,0,0,0}, {0,0,0,0}, ""},
    {"GRAY", "CK", 2, 2, {0,0,0,0}, {0,0,0,0}, "LUMA|AVERAGE|LIGHTNESS|HSP"},
    {"INVERT", "C", 1, 1, {0,0,0,0}, {0,0,0,0}, ""},
    {"MIX", "CCI", 3, 3, {0,0,0,0}, {0,0,100,0}, ""},
    {"MIXHSL", "CCI", 3, 3, {0,0,0,0}, {0,0,100,0}, ""},
    {"GRADIENT", "CCI", 3, 3, {0,0,2,0}, {0,0,16,0}, ""},
    {"TINTS", "CI", 2, 2, {0,1,0,0}, {0,10,0,0}, ""},
    {"SHADES", "CI", 2, 2, {0,1,0,0}, {0,10,0,0}, ""},
    {"TONES", "CI", 2, 2, {0,1,0,0}, {0,10,0,0}, ""},
    {"BLEND", "KCC", 3, 3, {0,0,0,0}, {0,0,0,0}, "MULTIPLY|SCREEN|OVERLAY|HARDLIGHT|SOFTLIGHT|DARKEN|LIGHTEN|DIFFERENCE|EXCLUSION|ADD|SUBTRACT|COLORDODGE|COLORBURN|HUE|SATURATION|COLOR|LUMINOSITY"},
    {"ALPHA", "CICI", 4, 4, {0,0,0,0}, {0,100,0,100}, ""},
    {"SIMULATE", "CK", 2, 2, {0,0,0,0}, {0,0,0,0}, "PROTANOPIA|DEUTERANOPIA|TRITANOPIA|ACHROMATOPSIA"},
    {"ROTATE", "CI", 2, 2, {0,-720,0,0}, {0,720,0,0}, ""},
    {"COMPLEMENT", "C", 1, 1, {0,0,0,0}, {0,0,0,0}, ""},
    {"TRIADIC", "C", 1, 1, {0,0,0,0}, {0,0,0,0}, ""},
    {"TETRADIC", "C", 1, 1, {0,0,0,0}, {0,0,0,0}, ""},
    {"SPLITCOMP", "C", 1, 1, {0,0,0,0}, {0,0,0,0}, ""},
    {"ANALOGOUS", "CII", 3, 3, {0,1,1,0}, {0,6,60,0}, ""},
    {"LIGHTEN", "CI", 2, 2, {0,0,0,0}, {0,100,0,0}, ""},
    {"DARKEN", "CI", 2, 2, {0,0,0,0}, {0,100,0,0}, ""},
    {"SATURATE", "CI", 2, 2, {0,0,0,0}, {0,100,0,0}, ""},
    {"DESATURATE", "CI", 2, 2, {0,0,0,0}, {0,100,0,0}, ""},
    {"NEAREST", "C", 1, 1, {0,0,0,0}, {0,0,0,0}, ""},
    {"DISTANCE", "CC", 2, 2, {0,0,0,0}, {0,0,0,0}, ""},
    {"CONTRAST", "CC", 2, 2, {0,0,0,0}, {0,0,0,0}, ""},
    {"ACCESSIBLE", "CC", 2, 2, {0,0,0,0}, {0,0,0,0}, ""},
    {"BEST", "*", 2, 33, {0,0,0,0}, {0,0,0,0}, ""},
    {"DESCRIBE", "C", 1, 1, {0,0,0,0}, {0,0,0,0}, ""},
    {"PALETTE", "P", 2, 33, {0,0,0,0}, {0,0,0,0}, ""},
    {"KMEANS", "P", 2, 33, {0,0,0,0}, {0,0,0,0}, ""},
    {"SORT", "*", 1, 32, {0,0,0,0}, {0,0,0,0}, ""},
    {"DITHER", "*", 1, 32, {0,0,0,0}, {0,0,0,0}, ""},
    {"RANDOM", "II", 2, 2, {1,1,0,0}, {999999999,16,0,0}, ""},
};

static const Entry builtins[] = {
    {"black", {{0, 0, 0}}},
    {"maroon", {{128, 0, 0}}},
    {"green", {{0, 128, 0}}},
    {"olive", {{128, 128, 0}}},
    {"navy", {{0, 0, 128}}},
    {"purple", {{128, 0, 128}}},
    {"teal", {{0, 128, 128}}},
    {"silver", {{192, 192, 192}}},
    {"gray", {{128, 128, 128}}},
    {"red", {{255, 0, 0}}},
    {"lime", {{0, 255, 0}}},
    {"yellow", {{255, 255, 0}}},
    {"blue", {{0, 0, 255}}},
    {"magenta", {{255, 0, 255}}},
    {"cyan", {{0, 255, 255}}},
    {"white", {{255, 255, 255}}},
    {"orange", {{255, 165, 0}}},
    {"pink", {{255, 192, 203}}},
    {"brown", {{165, 42, 42}}},
    {"gold", {{255, 215, 0}}},
    {"coral", {{255, 127, 80}}},
    {"salmon", {{250, 128, 114}}},
    {"violet", {{238, 130, 238}}},
    {"indigo", {{75, 0, 130}}},
};

static Int smaller(Int a, Int b) { return a < b ? a : b; }
static Int larger(Int a, Int b) { return a > b ? a : b; }
static Int magnitude(Int x) { return x < 0 ? -x : x; }
static Int clamp(Int x) { return smaller(255, larger(0, x)); }

static Int floor_div(Int a, Int b) {
    Int q = a / b;
    return q - (a < 0 && a % b != 0);
}

static Int rounded(Int numerator, Int denominator) {
    return floor_div(2 * numerator + denominator, 2 * denominator);
}

static Int away(Int numerator, Int denominator) {
    return numerator < 0 ? -rounded(-numerator, denominator)
                         : rounded(numerator, denominator);
}

static Int modulo(Int value, Int modulus) {
    Int remainder = value % modulus;
    return remainder < 0 ? remainder + modulus : remainder;
}

static Color rgb(Int r, Int g, Int b) {
    Color result = {{r, g, b}};
    return result;
}

static int equal_color(Color a, Color b) {
    return a.x[0] == b.x[0] && a.x[1] == b.x[1] && a.x[2] == b.x[2];
}

static Int distance(Color a, Color b) {
    Int result = 0;
    for (int j = 0; j < 3; ++j) {
        Int difference = a.x[j] - b.x[j];
        result += difference * difference;
    }
    return result;
}

static void extrema(Color c, Int *maximum, Int *minimum) {
    *maximum = larger(c.x[0], larger(c.x[1], c.x[2]));
    *minimum = smaller(c.x[0], smaller(c.x[1], c.x[2]));
}

static Int hue(Color c) {
    Int maximum, minimum;
    extrema(c, &maximum, &minimum);
    Int delta = maximum - minimum;
    if (delta == 0) return 0;
    Int numerator;
    if (maximum == c.x[0]) {
        numerator = 60 * (c.x[1] - c.x[2]);
        if (numerator < 0) numerator += 360 * delta;
    } else if (maximum == c.x[1]) {
        numerator = 60 * (c.x[2] - c.x[0]) + 120 * delta;
    } else {
        numerator = 60 * (c.x[0] - c.x[1]) + 240 * delta;
    }
    return rounded(numerator, delta) % 360;
}

static Hsl hsl(Color c) {
    Int maximum, minimum;
    extrema(c, &maximum, &minimum);
    Int delta = maximum - minimum;
    Hsl result = {hue(c), 0, rounded(100 * (maximum + minimum), 510)};
    if (delta != 0)
        result.s = rounded(100 * delta, 255 - magnitude(maximum + minimum - 255));
    return result;
}

/* The sector components are numerators with common denominator 60. */
static Color sector(Int h) {
    Int q = h / 60;
    Int f = h % 60;
    Int x = q % 2 == 0 ? f : 60 - f;
    switch (q) {
        case 0: return rgb(60, x, 0);
        case 1: return rgb(x, 60, 0);
        case 2: return rgb(0, 60, x);
        case 3: return rgb(0, x, 60);
        case 4: return rgb(x, 0, 60);
        default: return rgb(60, 0, x);
    }
}

static Color from_hsl(Int h, Int s, Int l) {
    Int chroma = (100 - magnitude(2 * l - 100)) * s;
    Int offset = 30 * (200 * l - chroma);
    Color result = sector(h);
    for (int j = 0; j < 3; ++j)
        result.x[j] = rounded(255 * (result.x[j] * chroma + offset), 600000);
    return result;
}

static Color from_hsv(Int h, Int s, Int v) {
    Int chroma = v * s;
    Int offset = 60 * (100 * v - chroma);
    Color result = sector(h);
    for (int j = 0; j < 3; ++j)
        result.x[j] = rounded(255 * (result.x[j] * chroma + offset), 600000);
    return result;
}

static Color from_hwb(Int h, Int w, Int k) {
    if (w + k >= 100) {
        Int value = rounded(255 * w, w + k);
        return rgb(value, value, value);
    }
    Color result = sector(h);
    for (int j = 0; j < 3; ++j)
        result.x[j] = rounded(255 * (result.x[j] * (100 - w - k) + 60 * w), 6000);
    return result;
}

static Int integer_root(Int value) {
    Int low = 0, high = 1;
    while (high * high <= value) high *= 2;
    while (low + 1 < high) {
        Int middle = (low + high) / 2;
        if (middle * middle <= value) low = middle;
        else high = middle;
    }
    return low;
}

static Color ansi_color(int index) {
    static const Int levels[] = {0, 95, 135, 175, 215, 255};
    if (index < 16) return builtins[index].color;
    if (index >= 232) {
        Int value = 8 + 10 * (index - 232);
        return rgb(value, value, value);
    }
    int code = index - 16;
    return rgb(levels[code / 36], levels[(code / 6) % 6], levels[code % 6]);
}

static Int luminance(Color c) {
    return 2126 * c.x[0] * c.x[0] + 7152 * c.x[1] * c.x[1]
         + 722 * c.x[2] * c.x[2];
}

static Contrast contrast(Color a, Color b) {
    Int y1 = luminance(a), y2 = luminance(b);
    Int high = larger(y1, y2) + 32512500;
    Int low = smaller(y1, y2) + 32512500;
    Contrast result = {rounded(100 * high, low), "FAIL"};
    if (high >= 7 * low) result.verdict = "AAA";
    else if (2 * high >= 9 * low) result.verdict = "AA";
    return result;
}

static Color interpolate(Color first, Color last, Int position, Int denominator) {
    Color result = first;
    for (int j = 0; j < 3; ++j)
        result.x[j] += away((last.x[j] - first.x[j]) * position, denominator);
    return result;
}

static Color rotate(Color c, Int degrees) {
    Hsl value = hsl(c);
    return from_hsl(modulo(value.h + degrees, 360), value.s, value.l);
}

static Color blend(int mode, Color base, Color top) {
    if (mode >= 13) {
        Hsl a = hsl(base), b = hsl(top);
        if (mode == 13 || mode == 15) a.h = b.h;
        if (mode == 14 || mode == 15) a.s = b.s;
        if (mode == 16) a.l = b.l;
        return from_hsl(a.h, a.s, a.l);
    }
    Color result = base;
    for (int j = 0; j < 3; ++j) {
        Int x = base.x[j], y = top.x[j], value = 0;
        switch (mode) {
            case 0: value = x * y / 255; break;
            case 1: value = 255 - (255 - x) * (255 - y) / 255; break;
            case 2:
            case 3:
                if ((mode == 2 ? x : y) < 128) value = 2 * x * y / 255;
                else value = 255 - 2 * (255 - x) * (255 - y) / 255;
                break;
            case 4: {
                Int multiply = x * y / 255;
                Int screen = 255 - (255 - x) * (255 - y) / 255;
                value = ((255 - x) * multiply + x * screen) / 255;
                break;
            }
            case 5: value = smaller(x, y); break;
            case 6: value = larger(x, y); break;
            case 7: value = magnitude(x - y); break;
            case 8: value = x + y - 2 * x * y / 255; break;
            case 9: value = smaller(255, x + y); break;
            case 10: value = larger(0, x - y); break;
            case 11: value = y == 255 ? 255 : smaller(255, 255 * x / (255 - y)); break;
            case 12: value = y == 0 ? 0 : larger(0, 255 - 255 * (255 - x) / y); break;
        }
        result.x[j] = value;
    }
    return result;
}

static void palette(const Color *colors, int count, int wanted, Color *means, int *sizes) {
    Box boxes[32] = {0};
    boxes[0].count = count;
    for (int i = 0; i < count; ++i) boxes[0].colors[i] = colors[i];
    int box_count = 1;
    while (box_count < wanted) {
        int chosen = -1, channel = 0;
        Int best_width = -1;
        for (int i = 0; i < box_count; ++i) {
            if (boxes[i].count < 2) continue;
            Int width = -1;
            int component = 0;
            for (int j = 0; j < 3; ++j) {
                Int minimum = 255, maximum = 0;
                for (int p = 0; p < boxes[i].count; ++p) {
                    minimum = smaller(minimum, boxes[i].colors[p].x[j]);
                    maximum = larger(maximum, boxes[i].colors[p].x[j]);
                }
                if (maximum - minimum > width) {
                    width = maximum - minimum;
                    component = j;
                }
            }
            if (width > best_width) {
                chosen = i;
                channel = component;
                best_width = width;
            }
        }
        Box sorted = boxes[chosen];
        for (int i = 1; i < sorted.count; ++i) {
            Color value = sorted.colors[i];
            int position = i;
            while (position > 0 && sorted.colors[position - 1].x[channel] > value.x[channel]) {
                sorted.colors[position] = sorted.colors[position - 1];
                --position;
            }
            sorted.colors[position] = value;
        }
        for (int i = box_count; i > chosen + 1; --i) boxes[i] = boxes[i - 1];
        int middle = sorted.count / 2;
        boxes[chosen].count = middle;
        boxes[chosen + 1].count = sorted.count - middle;
        for (int i = 0; i < middle; ++i) boxes[chosen].colors[i] = sorted.colors[i];
        for (int i = middle; i < sorted.count; ++i)
            boxes[chosen + 1].colors[i - middle] = sorted.colors[i];
        ++box_count;
    }
    for (int i = 0; i < wanted; ++i) {
        sizes[i] = boxes[i].count;
        means[i] = rgb(0, 0, 0);
        for (int p = 0; p < boxes[i].count; ++p)
            for (int j = 0; j < 3; ++j) means[i].x[j] += boxes[i].colors[p].x[j];
        for (int j = 0; j < 3; ++j) means[i].x[j] = rounded(means[i].x[j], sizes[i]);
    }
}

static int kmeans(const Color *colors, int count, int wanted, Color *means, int *sizes) {
    palette(colors, count, wanted, means, sizes);
    for (int iteration = 1; iteration <= 20; ++iteration) {
        Color sums[32];
        for (int j = 0; j < wanted; ++j) {
            sums[j] = rgb(0, 0, 0);
            sizes[j] = 0;
        }
        for (int i = 0; i < count; ++i) {
            int closest = 0;
            for (int j = 1; j < wanted; ++j)
                if (distance(colors[i], means[j]) < distance(colors[i], means[closest])) closest = j;
            ++sizes[closest];
            for (int j = 0; j < 3; ++j) sums[closest].x[j] += colors[i].x[j];
        }
        int unchanged = 1;
        for (int i = 0; i < wanted; ++i) {
            if (sizes[i] == 0) continue;
            for (int j = 0; j < 3; ++j) sums[i].x[j] = rounded(sums[i].x[j], sizes[i]);
            if (!equal_color(means[i], sums[i])) unchanged = 0;
            means[i] = sums[i];
        }
        if (unchanged || iteration == 20) return iteration;
    }
    return 20;
}

static int hex_digit(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

static int parse_integer(const char *text, Int low, Int high, Int *value) {
    int negative = text[0] == '-';
    int digits = 0;
    Int result = 0;
    for (int i = negative; text[i]; ++i) {
        if (text[i] < '0' || text[i] > '9' || ++digits > 9) return 0;
        result = result * 10 + text[i] - '0';
    }
    if (digits == 0) return 0;
    if (negative) result = -result;
    if (result < low || result > high) return 0;
    *value = result;
    return 1;
}

static int valid_name(const char *text) {
    size_t length = strlen(text);
    if (length < 1 || length > 12) return 0;
    for (size_t i = 0; i < length; ++i)
        if (text[i] < 'a' || text[i] > 'z') return 0;
    return 1;
}

static int registry_find(const State *state, const char *name) {
    for (int i = 0; i < registered_count(state); ++i)
        if (strcmp(entry_name(registered_entry(state, i)), name) == 0) return i;
    return -1;
}

static const Entry *table_entry(const State *state, int index) {
    return index < 24 ? &builtins[index] : registered_entry(state, index - 24);
}

static int parse_color(const State *state, const char *text, Color *result) {
    size_t length = strlen(text);
    if (text[0] == '#') {
        if (length != 4 && length != 7) return 0;
        for (size_t i = 1; i < length; ++i) if (hex_digit(text[i]) < 0) return 0;
        for (int j = 0; j < 3; ++j) {
            if (length == 4) result->x[j] = 17 * hex_digit(text[j + 1]);
            else result->x[j] = 16 * hex_digit(text[2 * j + 1]) + hex_digit(text[2 * j + 2]);
        }
        return 1;
    }
    if (length >= 4 && strncmp(text, "rgb(", 4) == 0) {
        size_t position = 4;
        for (int j = 0; j < 3; ++j) {
            Int value = 0;
            int digits = 0;
            while (text[position] >= '0' && text[position] <= '9') {
                if (++digits > 3) return 0;
                value = value * 10 + text[position++] - '0';
            }
            if (digits == 0 || value > 255) return 0;
            char expected = j == 2 ? ')' : ',';
            if (text[position] != expected) return 0;
            ++position;
            result->x[j] = value;
        }
        return text[position] == '\0';
    }
    for (int i = 0; i < 24 + registered_count(state); ++i) {
        const Entry *entry = table_entry(state, i);
        if (strcmp(entry_name(entry), text) == 0) {
            *result = entry->color;
            return 1;
        }
    }
    return 0;
}

static int keyword_index(const char *word, const char *choices) {
    const char *start = choices;
    int index = 0;
    while (*start) {
        const char *end = strchr(start, '|');
        size_t length = end ? (size_t)(end - start) : strlen(start);
        if (strlen(word) == length && strncmp(word, start, length) == 0) return index;
        if (!end) break;
        start = end + 1;
        ++index;
    }
    return -1;
}

static int prepare(const State *state, const Spec *spec, int operation,
                   const char **words, int count, Arguments *arguments) {
    if (count < spec->minimum || count > spec->maximum) return 0;
    for (int i = 0; i < count; ++i) {
        char kind;
        if (spec->signature[0] == '*') kind = 'C';
        else if (spec->signature[0] == 'P') kind = i == 0 ? 'I' : 'C';
        else kind = spec->signature[i];
        if (kind == 'C') {
            if (!parse_color(state, words[i], &arguments->colors[i])) return 0;
        } else if (kind == 'I') {
            Int low = spec->signature[0] == 'P' ? 1 : spec->low[i];
            Int high = spec->signature[0] == 'P' ? 32 : spec->high[i];
            if (!parse_integer(words[i], low, high, &arguments->numbers[i])) return 0;
        } else if (kind == 'N') {
            if (!valid_name(words[i])) return 0;
        } else if (kind == 'K') {
            arguments->keyword = keyword_index(words[i], spec->keywords);
            if (arguments->keyword < 0) return 0;
        } else if (kind == 'W') {
            if (strlen(words[i]) != 6 || strncmp(words[i], "0x", 2) != 0) return 0;
            Int value = 0;
            for (int j = 2; j < 6; ++j) {
                int digit = hex_digit(words[i][j]);
                if (digit < 0) return 0;
                value = 16 * value + digit;
            }
            arguments->numbers[i] = value;
        }
    }
    if (spec->signature[0] == 'P' && arguments->numbers[0] > count - 1) return 0;
    if (operation == OP_DEFINE) {
        for (int i = 0; i < 24; ++i)
            if (strcmp(words[0], entry_name(&builtins[i])) == 0) return 0;
    }
    if (operation == OP_UNDEFINE && registry_find(state, words[0]) < 0) return 0;
    return 1;
}

static void color_text(Color c, char *text) {
    snprintf(text, 8, "#%02X%02X%02X", (unsigned)c.x[0], (unsigned)c.x[1], (unsigned)c.x[2]);
}

static void output_color(Text *output, Color c) {
    char text[8];
    color_text(c, text);
    wordf(output, "%s", text);
}

static void output_contrast(Text *output, Color c, Color background) {
    Contrast value = contrast(c, background);
    wordf(output, "%lld.%02lld %s", value.ratio / 100, value.ratio % 100, value.verdict);
}

static void output_model(Text *output, int operation, Color c) {
    Int maximum, minimum;
    extrema(c, &maximum, &minimum);
    Int r = c.x[0], g = c.x[1], b = c.x[2];
    if (operation == OP_HSL) {
        Hsl value = hsl(c);
        wordf(output, "hsl(%lld,%lld%%,%lld%%)", value.h, value.s, value.l);
    } else if (operation == OP_HSV) {
        wordf(output, "hsv(%lld,%lld%%,%lld%%)", hue(c),
              maximum == 0 ? 0 : rounded(100 * (maximum - minimum), maximum), rounded(100 * maximum, 255));
    } else if (operation == OP_HWB) {
        wordf(output, "hwb(%lld,%lld%%,%lld%%)", hue(c), rounded(100 * minimum, 255),
              rounded(100 * (255 - maximum), 255));
    } else if (operation == OP_CMYK) {
        wordf(output, "cmyk(%lld%%,%lld%%,%lld%%,%lld%%)",
              maximum == 0 ? 0 : rounded(100 * (maximum - r), maximum),
              maximum == 0 ? 0 : rounded(100 * (maximum - g), maximum),
              maximum == 0 ? 0 : rounded(100 * (maximum - b), maximum),
              rounded(100 * (255 - maximum), 255));
    } else if (operation == OP_YCBCR) {
        wordf(output, "ycbcr(%lld,%lld,%lld)", clamp(rounded(299 * r + 587 * g + 114 * b, 1000)),
              clamp(rounded(128000 - 169 * r - 331 * g + 500 * b, 1000)),
              clamp(rounded(128000 + 500 * r - 419 * g - 81 * b, 1000)));
    } else {
        wordf(output, "yiq(%lld,%lld,%lld)", rounded(299 * r + 587 * g + 114 * b, 1000),
              rounded(596 * r - 274 * g - 322 * b, 1000), rounded(211 * r - 523 * g + 312 * b, 1000));
    }
}

static void execute(State *state, int operation, const char **words, int count,
                    const Arguments *args, Text *output) {
    Color c = args->colors[0];
    Int a = args->numbers[0], b = args->numbers[1], d = args->numbers[2];
    switch (operation) {
        case OP_DEFINE:
            wordf(output, "%s", words[0]);
            output_color(output, args->colors[1]);
            registry_set(state, words[0], args->colors[1]);
            break;
        case OP_UNDEFINE:
            wordf(output, "%s removed", words[0]);
            registry_delete(state, registry_find(state, words[0]));
            break;
        case OP_LIST: {
            int indices[500], length = registered_count(state);
            for (int i = 0; i < length; ++i) indices[i] = i;
            for (int i = 1; i < length; ++i) {
                int value = indices[i], j = i;
                while (j > 0 && strcmp(entry_name(registered_entry(state, indices[j - 1])),
                                       entry_name(registered_entry(state, value))) > 0) {
                    indices[j] = indices[j - 1];
                    --j;
                }
                indices[j] = value;
            }
            if (length == 0) wordf(output, "NONE");
            for (int i = 0; i < length; ++i) {
                const Entry *entry = registered_entry(state, indices[i]);
                char text[8];
                color_text(entry->color, text);
                wordf(output, "%s=%s", entry_name(entry), text);
            }
            break;
        }
        case OP_PARSE: {
            output_color(output, c);
            wordf(output, "rgb(%lld,%lld,%lld)", c.x[0], c.x[1], c.x[2]);
            const int models[] = {OP_HSL, OP_HSV, OP_HWB, OP_CMYK, OP_YCBCR, OP_YIQ};
            for (int i = 0; i < 6; ++i) output_model(output, models[i], c);
            const char *name = "-";
            for (int i = 0; i < 24 + registered_count(state); ++i) {
                const Entry *entry = table_entry(state, i);
                if (equal_color(c, entry->color)) {
                    name = entry_name(entry);
                    break;
                }
            }
            wordf(output, "%s", name);
            break;
        }
        case OP_HSL: case OP_HSV: case OP_HWB: case OP_CMYK: case OP_YCBCR: case OP_YIQ:
            output_model(output, operation, c);
            break;
        case OP_FROMHSL: output_color(output, from_hsl(a, b, d)); break;
        case OP_FROMHSV: output_color(output, from_hsv(a, b, d)); break;
        case OP_FROMHWB: output_color(output, from_hwb(a, b, d)); break;
        case OP_FROMCMYK: {
            Color result = rgb(0, 0, 0);
            for (int j = 0; j < 3; ++j)
                result.x[j] = rounded(255 * (100 - args->numbers[j]) * (100 - args->numbers[3]), 10000);
            output_color(output, result);
            break;
        }
        case OP_FROMYCBCR:
            output_color(output, rgb(clamp(rounded(1000 * a + 1402 * (d - 128), 1000)),
                                     clamp(rounded(1000 * a - 344 * (b - 128) - 714 * (d - 128), 1000)),
                                     clamp(rounded(1000 * a + 1772 * (b - 128), 1000))));
            break;
        case OP_FROMYIQ:
            output_color(output, rgb(clamp(rounded(1000 * a + 956 * b + 619 * d, 1000)),
                                     clamp(rounded(1000 * a - 272 * b - 647 * d, 1000)),
                                     clamp(rounded(1000 * a - 1106 * b + 1703 * d, 1000))));
            break;
        case OP_RGB565: {
            Int code = 2048 * rounded(31 * c.x[0], 255) + 32 * rounded(63 * c.x[1], 255)
                     + rounded(31 * c.x[2], 255);
            wordf(output, "0x%04X", (unsigned)code);
            break;
        }
        case OP_FROM565:
            output_color(output, rgb(rounded(255 * (a / 2048), 31),
                                     rounded(255 * ((a / 32) % 64), 63), rounded(255 * (a % 32), 31)));
            break;
        case OP_FROMANSI: output_color(output, ansi_color((int)a)); break;
        case OP_ANSI: {
            int best = 16;
            for (int i = 17; i <= 255; ++i)
                if (distance(c, ansi_color(i)) < distance(c, ansi_color(best))) best = i;
            wordf(output, "%d", best);
            output_color(output, ansi_color(best));
            wordf(output, "%lld", distance(c, ansi_color(best)));
            break;
        }
        case OP_WEBSAFE: {
            Color result = c;
            for (int j = 0; j < 3; ++j) result.x[j] = 51 * rounded(c.x[j], 51);
            output_color(output, result);
            break;
        }
        case OP_GRAY: {
            Int maximum, minimum, value;
            extrema(c, &maximum, &minimum);
            if (args->keyword == 0) value = rounded(299 * c.x[0] + 587 * c.x[1] + 114 * c.x[2], 1000);
            else if (args->keyword == 1) value = rounded(c.x[0] + c.x[1] + c.x[2], 3);
            else if (args->keyword == 2) value = rounded(maximum + minimum, 2);
            else value = integer_root((299 * c.x[0] * c.x[0] + 587 * c.x[1] * c.x[1]
                                     + 114 * c.x[2] * c.x[2]) / 1000);
            output_color(output, rgb(value, value, value));
            break;
        }
        case OP_INVERT:
            output_color(output, rgb(255 - c.x[0], 255 - c.x[1], 255 - c.x[2]));
            break;
        case OP_MIX: {
            Color result = c;
            for (int j = 0; j < 3; ++j)
                result.x[j] = rounded(c.x[j] * (100 - d) + args->colors[1].x[j] * d, 100);
            output_color(output, result);
            break;
        }
        case OP_MIXHSL: {
            Hsl first = hsl(c), last = hsl(args->colors[1]);
            Int delta = modulo(last.h - first.h, 360);
            if (delta > 180) delta -= 360;
            output_color(output, from_hsl(modulo(first.h + away(delta * d, 100), 360),
                first.s + away((last.s - first.s) * d, 100), first.l + away((last.l - first.l) * d, 100)));
            break;
        }
        case OP_GRADIENT:
            for (Int i = 0; i < d; ++i) output_color(output, interpolate(c, args->colors[1], i, d - 1));
            break;
        case OP_TINTS: case OP_SHADES: case OP_TONES: {
            Int target = operation == OP_TINTS ? 255 : operation == OP_SHADES ? 0 : 128;
            for (Int i = 1; i <= b; ++i) output_color(output, interpolate(c, rgb(target, target, target), i, b + 1));
            break;
        }
        case OP_BLEND: output_color(output, blend(args->keyword, args->colors[1], args->colors[2])); break;
        case OP_ALPHA: {
            Int q = args->numbers[3];
            Int alpha = 100 * b + q * (100 - b);
            Color result = rgb(0, 0, 0);
            if (alpha > 0)
                for (int j = 0; j < 3; ++j)
                    result.x[j] = rounded(100 * b * c.x[j] + q * (100 - b) * args->colors[2].x[j], alpha);
            output_color(output, result);
            wordf(output, "%lld%%", rounded(alpha, 100));
            break;
        }
        case OP_SIMULATE: {
            static const Int coefficients[4][3][3] = {
                {{567,433,0},{558,442,0},{0,242,758}},
                {{625,375,0},{700,300,0},{0,300,700}},
                {{950,50,0},{0,433,567},{0,475,525}},
                {{299,587,114},{299,587,114},{299,587,114}}
            };
            Color result = rgb(0, 0, 0);
            for (int j = 0; j < 3; ++j) {
                Int sum = 0;
                for (int k = 0; k < 3; ++k) sum += coefficients[args->keyword][j][k] * c.x[k];
                result.x[j] = rounded(sum, 1000);
            }
            output_color(output, result);
            break;
        }
        case OP_ROTATE: output_color(output, rotate(c, b)); break;
        case OP_COMPLEMENT: output_color(output, rotate(c, 180)); break;
        case OP_TRIADIC: output_color(output, rotate(c, 120)); output_color(output, rotate(c, 240)); break;
        case OP_TETRADIC:
            for (Int shift = 90; shift <= 270; shift += 90) output_color(output, rotate(c, shift));
            break;
        case OP_SPLITCOMP: output_color(output, rotate(c, 150)); output_color(output, rotate(c, 210)); break;
        case OP_ANALOGOUS:
            for (Int i = -b; i <= b; ++i) if (i != 0) output_color(output, rotate(c, i * d));
            break;
        case OP_LIGHTEN: case OP_DARKEN: case OP_SATURATE: case OP_DESATURATE: {
            Hsl value = hsl(c);
            if (operation == OP_LIGHTEN) value.l = smaller(100, value.l + b);
            else if (operation == OP_DARKEN) value.l = larger(0, value.l - b);
            else if (operation == OP_SATURATE) value.s = smaller(100, value.s + b);
            else value.s = larger(0, value.s - b);
            output_color(output, from_hsl(value.h, value.s, value.l));
            break;
        }
        case OP_NEAREST: {
            int best = 0;
            for (int i = 1; i < 24 + registered_count(state); ++i)
                if (distance(c, table_entry(state, i)->color) < distance(c, table_entry(state, best)->color)) best = i;
            const Entry *entry = table_entry(state, best);
            wordf(output, "%s", entry_name(entry));
            output_color(output, entry->color);
            wordf(output, "%lld", distance(c, entry->color));
            break;
        }
        case OP_DISTANCE: {
            Color other = args->colors[1];
            Int r = c.x[0] - other.x[0], g = c.x[1] - other.x[1], blue = c.x[2] - other.x[2];
            Int weight = (1024 + c.x[0] + other.x[0]) * r * r + 2048 * g * g
                       + (1534 - c.x[0] - other.x[0]) * blue * blue;
            wordf(output, "%lld %lld", distance(c, other), integer_root(weight / 512));
            break;
        }
        case OP_CONTRAST: output_contrast(output, c, args->colors[1]); break;
        case OP_ACCESSIBLE: {
            Color result = c, background = args->colors[1];
            if (strcmp(contrast(c, background).verdict, "FAIL") == 0) {
                Hsl value = hsl(c);
                int found = 0;
                for (Int step = 1; step <= 100 && !found; ++step)
                    for (int sign = -1; sign <= 1; sign += 2) {
                        Int lightness = value.l + sign * step;
                        if (lightness < 0 || lightness > 100) continue;
                        Color candidate = from_hsl(value.h, value.s, lightness);
                        if (strcmp(contrast(candidate, background).verdict, "FAIL") != 0) {
                            result = candidate;
                            found = 1;
                            break;
                        }
                    }
            }
            output_color(output, result);
            output_contrast(output, result, background);
            break;
        }
        case OP_BEST: {
            int best = 1;
            for (int i = 2; i < count; ++i)
                if (contrast(args->colors[i], c).ratio > contrast(args->colors[best], c).ratio) best = i;
            output_color(output, args->colors[best]);
            output_contrast(output, args->colors[best], c);
            break;
        }
        case OP_DESCRIBE: {
            Hsl value = hsl(c);
            if (value.l <= 5) wordf(output, "black");
            else if (value.l >= 95) wordf(output, "white");
            else {
                const char *lightness = value.l <= 20 ? "very dark" : value.l <= 40 ? "dark"
                                      : value.l <= 60 ? "medium" : value.l <= 80 ? "light" : "very light";
                wordf(output, "%s", lightness);
                if (value.s < 10) wordf(output, "gray");
                else {
                    static const char *names[] = {"red","orange","yellow","chartreuse","green","spring-green",
                                                  "cyan","azure","blue","violet","magenta","rose"};
                    wordf(output, "%s %s", value.s < 40 ? "muted" : value.s < 80 ? "moderate" : "vivid",
                          names[((value.h + 15) % 360) / 30]);
                }
            }
            break;
        }
        case OP_PALETTE: case OP_KMEANS: {
            Color means[32];
            int sizes[32], wanted = (int)a;
            if (operation == OP_PALETTE) palette(args->colors + 1, count - 1, wanted, means, sizes);
            else wordf(output, "%d", kmeans(args->colors + 1, count - 1, wanted, means, sizes));
            for (int i = 0; i < wanted; ++i) {
                char text[8];
                color_text(means[i], text);
                wordf(output, "%s:%d", text, sizes[i]);
            }
            break;
        }
        case OP_SORT: {
            Color colors[32];
            for (int i = 0; i < count; ++i) colors[i] = args->colors[i];
            for (int i = 1; i < count; ++i) {
                Color value = colors[i];
                Hsl key = hsl(value);
                int j = i;
                while (j > 0) {
                    Hsl previous = hsl(colors[j - 1]);
                    int greater = previous.h > key.h || (previous.h == key.h &&
                        (previous.s > key.s || (previous.s == key.s && previous.l > key.l)));
                    if (!greater) break;
                    colors[j] = colors[j - 1];
                    --j;
                }
                colors[j] = value;
            }
            for (int i = 0; i < count; ++i) output_color(output, colors[i]);
            break;
        }
        case OP_DITHER: {
            Color error = rgb(0, 0, 0);
            for (int i = 0; i < count; ++i) {
                Color target = args->colors[i];
                for (int j = 0; j < 3; ++j) target.x[j] = clamp(target.x[j] + error.x[j]);
                int best = 0;
                for (int j = 1; j < 16; ++j)
                    if (distance(target, builtins[j].color) < distance(target, builtins[best].color)) best = j;
                wordf(output, "%s", entry_name(&builtins[best]));
                for (int j = 0; j < 3; ++j) error.x[j] = target.x[j] - builtins[best].color.x[j];
            }
            break;
        }
        case OP_RANDOM: {
            Int state_value = a;
            for (Int i = 0; i < b; ++i) {
                state_value = state_value * 48271 % 2147483647;
                Int h = state_value % 360;
                state_value = state_value * 48271 % 2147483647;
                Int s = 40 + state_value % 61;
                state_value = state_value * 48271 % 2147483647;
                Int l = 25 + state_value % 51;
                output_color(output, from_hsl(h, s, l));
            }
            break;
        }
    }
}

static int process(State *state, const char **tokens, int count, Text *output) {
    int operation = -1;
    for (int i = 0; i < 53; ++i)
        if (strcmp(tokens[0], specifications[i].name) == 0) {
            operation = i;
            break;
        }
    if (operation < 0) return 0;
    Arguments arguments = {0};
    if (!prepare(state, &specifications[operation], operation, tokens + 1, count - 1, &arguments)) return 0;
    execute(state, operation, tokens + 1, count - 1, &arguments, output);
    return 1;
}

int main(void) {
    char line[1004];
    if (!fgets(line, sizeof line, stdin)) return 0;
    int commands = atoi(line);
    State state = {0};
    for (int i = 0; i < commands; ++i) {
        if (!fgets(line, sizeof line, stdin)) break;
        line[strcspn(line, "\n")] = '\0';
        const char *tokens[501];
        int count = 0;
        for (char *word = strtok(line, " "); word; word = strtok(NULL, " ")) tokens[count++] = word;
        Text output = {{0}, 0};
        if (process(&state, tokens, count, &output)) puts(output.data);
        else puts("INVALID");
    }
    return 0;
}
