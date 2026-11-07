#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_SIDE 64
#define MAX_PIXELS 4096
#define MAX_COMMANDS 500
#define MAX_ARGS 12

typedef struct {
    int w, h, m, p[MAX_PIXELS];
} Image;
typedef struct {
    char name[9];
    Image *image;
} Slot;
typedef struct {
    Image *current;
    Image *undo[MAX_COMMANDS + 1], *redo[MAX_COMMANDS + 1];
    int undo_count, redo_count;
    Slot slots[MAX_COMMANDS + 1];
    int slot_count;
} Editor;
typedef struct {
    int x, y;
} Point;
typedef struct {
    const char *name, *pattern;
} CommandSpec;

static const CommandSpec COMMANDS[] = {
    {"NEW", "iiii"},     {"OUTPUT", ""},     {"INVERT", ""},
    {"BRIGHTNESS", "i"}, {"CONTRAST", "ii"}, {"THRESHOLD", "i"},
    {"LEVELS", "ii"},    {"POSTERIZE", "i"}, {"MAXVAL", "i"},
    {"FLIPH", ""},       {"FLIPV", ""},      {"ROTATE", "i"},
    {"CROP", "iiii"},    {"PAD", "ii"},      {"SCALE", "ii"},
    {"SHIFT", "iii"},    {"TILE", "ii"},     {"BLUR", ""},
    {"GAUSS", ""},       {"SHARPEN", ""},    {"CONVOLVE", "iiiiiiiiii"},
    {"SOBEL", ""},       {"MEDIAN", ""},     {"ERODE", ""},
    {"DILATE", ""},      {"OPEN", ""},       {"CLOSE", ""},
    {"GRADIENT", ""},    {"LINE", "iiiii"},  {"RECT", "iiiii"},
    {"CIRCLE", "iiii"},  {"FLOOD", "iii"},   {"HISTOGRAM", ""},
    {"EQUALIZE", ""},    {"LABEL", "i"},     {"DISTANCE", "i"},
    {"STATS", ""},       {"REGION", "iiii"}, {"DITHER", ""},
    {"ASCIIART", ""},    {"STORE", "n"},     {"RECALL", "n"},
    {"DROP", "n"},       {"BLEND", "nii"},   {"DIFF", "n"},
    {"PASTE", "nii"},    {"SLOTS", ""},      {"INFO", ""},
    {"UNDO", ""},        {"REDO", ""}};

static int maximum(int a, int b) {
    return a > b ? a : b;
}
static int minimum(int a, int b) {
    return a < b ? a : b;
}
static int clamp(int v, int lo, int hi) {
    return minimum(maximum(v, lo), hi);
}
static int floor_div(int a, int b) {
    return a >= 0 ? a / b : -((-(long long)a + b - 1) / b);
}
static int contains(const Image *im, int x, int y) {
    return 0 <= x && x < im->w && 0 <= y && y < im->h;
}
static int pixel(const Image *im, int x, int y) {
    return im->p[y * im->w + x];
}
static void set_pixel(Image *im, int x, int y, int v) {
    im->p[y * im->w + x] = v;
}
static Image *make_image(int w, int h, int maxval) {
    Image *im = malloc(sizeof(*im));
    if (!im)
        exit(EXIT_FAILURE);
    im->w = w;
    im->h = h;
    im->m = maxval;
    return im;
}
static Image *copy_image(const Image *original) {
    Image *im = malloc(sizeof(*im));
    if (!im)
        exit(EXIT_FAILURE);
    memcpy(im, original, sizeof(*im));
    return im;
}
static void summary(const Image *im) {
    long long checksum = 0;
    for (int i = 0; i < im->w * im->h; ++i)
        checksum += (long long)(i + 1) * im->p[i];
    printf("%dx%d maxval %d checksum %lld", im->w, im->h, im->m, checksum);
}
static void error(const char *message) {
    printf("error: %s\n", message);
}
static void clear_images(Image **images, int *count) {
    for (int i = 0; i < *count; ++i)
        free(images[i]);
    *count = 0;
}
static void replace(Editor *ed, Image *im, const char *label) {
    free(ed->current);
    clear_images(ed->undo, &ed->undo_count);
    clear_images(ed->redo, &ed->redo_count);
    ed->current = im;
    printf("%s ", label);
    summary(im);
    putchar('\n');
}
static void commit(Editor *ed, Image *im, int painted) {
    ed->undo[ed->undo_count++] = ed->current;
    clear_images(ed->redo, &ed->redo_count);
    ed->current = im;
    printf("ok ");
    summary(im);
    if (painted >= 0)
        printf(" painted %d", painted);
    putchar('\n');
}
static int slot_index(const Editor *ed, const char *name) {
    for (int i = 0; i < ed->slot_count; ++i)
        if (strcmp(name, ed->slots[i].name) == 0)
            return i;
    return -1;
}
static int valid_integer(const char *s) {
    int i = 0, digits;
    if (s[0] == '-')
        ++i;
    digits = (int)strlen(s + i);
    if (digits < 1 || digits > 7 || (digits > 1 && s[i] == '0'))
        return 0;
    if (s[0] == '-' && s[1] == '0')
        return 0;
    for (; s[i]; ++i)
        if (s[i] < '0' || s[i] > '9')
            return 0;
    return 1;
}
static int valid_name(const char *s) {
    int n = (int)strlen(s);
    if (n < 1 || n > 8)
        return 0;
    for (; *s; ++s)
        if (*s < 'a' || *s > 'z')
            return 0;
    return 1;
}
static int valid_digits(const char *s) {
    if (!*s)
        return 0;
    for (; *s; ++s)
        if (*s < '0' || *s > '9')
            return 0;
    return 1;
}
static int load_pgm(Editor *ed, int k) {
    char line[256];
    char *all = malloc((size_t)k * sizeof(line));
    char **words = malloc((size_t)k * 210 * sizeof(*words));
    if (!all || !words)
        exit(EXIT_FAILURE);
    int count = 0;
    for (int i = 0; i < k; ++i) {
        if (!fgets(line, sizeof(line), stdin))
            line[0] = '\0';
        char *dest = all + (size_t)i * sizeof(line);
        strcpy(dest, line);
        char *hash = strchr(dest, '#');
        if (hash)
            *hash = '\0';
        for (char *part = strtok(dest, " \t\r\n"); part; part = strtok(NULL, " \t\r\n"))
            words[count++] = part;
    }
    int ok = 0;
    if (count == 0 || strcmp(words[0], "P2")) {
        error("load: bad magic");
        goto cleanup;
    }
    int header[3] = {0, 0, 0};
    for (int i = 0; i < 3; ++i) {
        if (i + 1 >= count) {
            error("load: truncated header");
            goto cleanup;
        }
        if (!valid_digits(words[i + 1])) {
            error("load: bad number");
            goto cleanup;
        }
        header[i] = atoi(words[i + 1]);
        if (header[i] < 1 || header[i] > (i == 2 ? 255 : 64)) {
            error(i == 2 ? "load: bad maxval" : "load: bad size");
            goto cleanup;
        }
    }
    {
        int w = header[0], h = header[1], maxval = header[2];
        int count_pixels = count - 4;
        Image *im = make_image(w, h, maxval);
        for (int i = 0; i < w * h; ++i) {
            int x = i % w, y = i / w;
            if (i >= count_pixels) {
                printf("error: load: too few pixels (%d of %d)\n", count_pixels, w * h);
                free(im);
                goto cleanup;
            }
            if (!valid_digits(words[i + 4])) {
                printf("error: load: bad pixel at %d,%d\n", x, y);
                free(im);
                goto cleanup;
            }
            int value = atoi(words[i + 4]);
            if (value > maxval) {
                printf("error: load: pixel out of range at %d,%d\n", x, y);
                free(im);
                goto cleanup;
            }
            im->p[i] = value;
        }
        if (count_pixels > w * h) {
            printf("error: load: too many pixels (%d of %d)\n", count_pixels, w * h);
            free(im);
            goto cleanup;
        }
        replace(ed, im, "loaded");
        ok = 1;
    }
cleanup:
    free(all);
    free(words);
    return ok;
}

static Image *rank_filter(const Image *im, int rank) {
    Image *out = copy_image(im);
    for (int y = 0; y < im->h; ++y)
        for (int x = 0; x < im->w; ++x) {
            int values[9], n = 0;
            for (int dy = -1; dy <= 1; ++dy)
                for (int dx = -1; dx <= 1; ++dx)
                    values[n++] =
                        pixel(im, clamp(x + dx, 0, im->w - 1), clamp(y + dy, 0, im->h - 1));
            for (int i = 1; i < 9; ++i) {
                int value = values[i], j = i;
                while (j > 0 && values[j - 1] > value) {
                    values[j] = values[j - 1];
                    --j;
                }
                values[j] = value;
            }
            set_pixel(out, x, y, values[rank]);
        }
    return out;
}
static Image *convoluted(const Image *im, const int kernel[9], int divisor) {
    Image *out = copy_image(im);
    for (int y = 0; y < im->h; ++y)
        for (int x = 0; x < im->w; ++x) {
            int total = 0, i = 0;
            for (int dy = -1; dy <= 1; ++dy)
                for (int dx = -1; dx <= 1; ++dx)
                    total += kernel[i++] *
                             pixel(im, clamp(x + dx, 0, im->w - 1), clamp(y + dy, 0, im->h - 1));
            set_pixel(out, x, y, clamp(floor_div(total, divisor), 0, im->m));
        }
    return out;
}
static int mark(Image *out, unsigned char painted[], int x, int y, int value) {
    if (!contains(out, x, y))
        return 0;
    int index = y * out->w + x;
    if (painted[index])
        return 0;
    painted[index] = 1;
    out->p[index] = value;
    return 1;
}
static int compare_int(const void *a, const void *b) {
    int x = *(const int *)a, y = *(const int *)b;
    return (x > y) - (x < y);
}
static void statistics(const Image *im, int left, int top, int width, int height) {
    int size = width * height, numbers[MAX_PIXELS], frequency[256] = {0};
    int total = 0, n = 0;
    for (int y = top; y < top + height; ++y)
        for (int x = left; x < left + width; ++x) {
            int p = pixel(im, x, y);
            total += p;
            numbers[n++] = p;
            frequency[p]++;
        }
    qsort(numbers, (size_t)size, sizeof(int), compare_int);
    int mode = 0;
    for (int i = 1; i <= im->m; ++i)
        if (frequency[i] > frequency[mode])
            mode = i;
    printf("min %d max %d mean %d median %d mode %d\n", numbers[0], numbers[size - 1], total / size,
           numbers[(size - 1) / 2], mode);
}
static void labels(const Image *im, int threshold) {
    int visited[MAX_PIXELS] = {0}, queue[MAX_PIXELS];
    int dx[8] = {-1, 0, 1, -1, 1, -1, 0, 1};
    int dy[8] = {-1, -1, -1, 0, 0, 1, 1, 1};
    int labels[MAX_PIXELS][8], components = 0;
    for (int start = 0; start < im->w * im->h; ++start) {
        if (visited[start] || im->p[start] < threshold)
            continue;
        int front = 0, back = 0, count = 0, minx = im->w, miny = im->h;
        int maxx = 0, maxy = 0, sumx = 0, sumy = 0, perimeter = 0;
        queue[back++] = start;
        visited[start] = 1;
        while (front < back) {
            int i = queue[front++], x = i % im->w, y = i / im->w;
            ++count;
            minx = minimum(minx, x);
            miny = minimum(miny, y);
            maxx = maximum(maxx, x);
            maxy = maximum(maxy, y);
            sumx += x;
            sumy += y;
            if (x == 0 || y == 0 || x == im->w - 1 || y == im->h - 1 ||
                pixel(im, x, y - 1) < threshold || pixel(im, x, y + 1) < threshold ||
                pixel(im, x - 1, y) < threshold || pixel(im, x + 1, y) < threshold)
                ++perimeter;
            for (int k = 0; k < 8; ++k) {
                int nx = x + dx[k], ny = y + dy[k];
                if (!contains(im, nx, ny))
                    continue;
                int j = ny * im->w + nx;
                if (!visited[j] && im->p[j] >= threshold) {
                    visited[j] = 1;
                    queue[back++] = j;
                }
            }
        }
        labels[components][0] = count;
        labels[components][1] = perimeter;
        labels[components][2] = minx;
        labels[components][3] = miny;
        labels[components][4] = maxx;
        labels[components][5] = maxy;
        labels[components][6] = sumx / count;
        labels[components][7] = sumy / count;
        ++components;
    }
    printf("labels %d\n", components);
    for (int i = 0; i < components; ++i) {
        int *v = labels[i];
        printf("label %d area %d perimeter %d box %d %d %d %d center %d %d\n", i + 1, v[0], v[1],
               v[2], v[3], v[4], v[5], v[6], v[7]);
    }
}

static void paint_circle(Image *out, unsigned char marked[], int cx, int cy, int radius, int fill,
                         int value, int *painted) {
    int left[MAX_SIDE], right[MAX_SIDE];
    for (int y = 0; y < MAX_SIDE; ++y) {
        left[y] = 100000;
        right[y] = -100000;
    }
    int a = radius, b = 0, e = 1 - radius;
    while (a >= b) {
        Point points[8] = {{cx + a, cy + b}, {cx + b, cy + a}, {cx - b, cy + a}, {cx - a, cy + b},
                           {cx - a, cy - b}, {cx - b, cy - a}, {cx + b, cy - a}, {cx + a, cy - b}};
        for (int k = 0; k < 8; ++k) {
            int x = points[k].x, y = points[k].y;
            if (!fill)
                *painted += mark(out, marked, x, y, value);
            else if (y >= 0 && y < out->h) {
                left[y] = minimum(left[y], x);
                right[y] = maximum(right[y], x);
            }
        }
        ++b;
        if (e < 0)
            e += 2 * b + 1;
        else {
            --a;
            e += 2 * (b - a) + 1;
        }
    }
    if (fill)
        for (int y = 0; y < out->h; ++y) {
            for (int x = maximum(left[y], 0); x <= minimum(right[y], out->w - 1); ++x)
                *painted += mark(out, marked, x, y, value);
        }
}
static void histogram(const Image *im) {
    int lo[16], hi[16], counts[16] = {0}, top = 0;
    for (int i = 0; i < 16; ++i) {
        lo[i] = -1;
        hi[i] = 0;
    }
    for (int v = 0; v <= im->m; ++v) {
        int bin = v * 16 / (im->m + 1);
        if (lo[bin] < 0)
            lo[bin] = v;
        hi[bin] = v;
    }
    for (int i = 0; i < im->w * im->h; ++i) {
        int bin = im->p[i] * 16 / (im->m + 1);
        ++counts[bin];
        top = maximum(top, counts[bin]);
    }
    for (int i = 0; i < 16; ++i)
        if (lo[i] >= 0) {
            printf("%3d-%3d %4d |", lo[i], hi[i], counts[i]);
            int count = counts[i] * 32 / top;
            for (int n = 0; n < count; ++n)
                putchar('#');
            putchar('\n');
        }
}
static void distance_transform(Image *out, int threshold) {
    int w = out->w, h = out->h, far = maximum(w + h, out->m);
    for (int i = 0; i < w * h; ++i)
        out->p[i] = out->p[i] < threshold ? 0 : far;
    for (int y = 0; y < h; ++y)
        for (int x = 0; x < w; ++x) {
            int i = y * w + x;
            if (x > 0)
                out->p[i] = minimum(out->p[i], out->p[i - 1] + 1);
            if (y > 0)
                out->p[i] = minimum(out->p[i], out->p[i - w] + 1);
        }
    for (int y = h - 1; y >= 0; --y)
        for (int x = w - 1; x >= 0; --x) {
            int i = y * w + x;
            if (x < w - 1)
                out->p[i] = minimum(out->p[i], out->p[i + 1] + 1);
            if (y < h - 1)
                out->p[i] = minimum(out->p[i], out->p[i + w] + 1);
            out->p[i] = minimum(out->p[i], out->m);
        }
}
static int imageless(int command) {
    return command == 0 || command == 41 || command == 42 || command == 46 || command == 47 ||
           command == 48 || command == 49;
}
static int requires_slot(int command) {
    return command == 41 || command == 42 || command == 43 || command == 44 || command == 45;
}
static int valid_crop(const Image *im, int x, int y, int w, int h) {
    return x >= 0 && y >= 0 && w >= 1 && h >= 1 && x + w <= im->w && y + h <= im->h;
}
static int slot_compare(const void *a, const void *b) {
    const Slot *x = a, *y = b;
    return strcmp(x->name, y->name);
}
static void execute(Editor *ed, char **tokens, int n) {
    const char *name = tokens[0];
    int index = -1;
    for (int i = 0; i < (int)(sizeof(COMMANDS) / sizeof(COMMANDS[0])); ++i)
        if (!strcmp(name, COMMANDS[i].name)) {
            index = i;
            break;
        }
    if (index < 0) {
        printf("error: unknown command %s\n", name);
        return;
    }
    const char *pattern = COMMANDS[index].pattern;
    int nargs = (int)strlen(pattern), fill = 0, count = n - 1;
    if ((index == 29 || index == 30) && count == nargs + 1 && !strcmp(tokens[n - 1], "FILL")) {
        fill = 1;
        --count;
    }
    if (count != nargs) {
        error("bad arguments");
        return;
    }
    int a[MAX_ARGS] = {0}, ai = 0;
    const char *slot = "";
    for (int i = 0; i < count; ++i) {
        if (pattern[i] == 'i') {
            if (!valid_integer(tokens[i + 1])) {
                error("bad arguments");
                return;
            }
            a[ai++] = atoi(tokens[i + 1]);
        } else {
            if (!valid_name(tokens[i + 1])) {
                error("bad arguments");
                return;
            }
            slot = tokens[i + 1];
        }
    }
    if (!imageless(index) && !ed->current) {
        error("no image");
        return;
    }
    int si = slot_index(ed, slot);
    if (requires_slot(index) && si < 0) {
        printf("error: no slot %s\n", slot);
        return;
    }
    Image *im = ed->current;
    int w = im ? im->w : 0, h = im ? im->h : 0, m = im ? im->m : 0;
    Image *out = NULL;
    switch (index) {
    case 0:
        if (a[0] < 1 || a[0] > 64 || a[1] < 1 || a[1] > 64 || a[2] < 1 || a[2] > 255 || a[3] < 0 ||
            a[3] > a[2]) {
            error("bad value");
            return;
        }
        out = make_image(a[0], a[1], a[2]);
        for (int i = 0; i < a[0] * a[1]; ++i)
            out->p[i] = a[3];
        replace(ed, out, "created");
        return;
    case 1:
        printf("P2\n%d %d\n%d\n", w, h, m);
        for (int y = 0; y < h; ++y) {
            for (int x = 0; x < w; ++x)
                printf("%s%d", x == 0 ? "" : " ", pixel(im, x, y));
            putchar('\n');
        }
        return;
    case 2:
        out = copy_image(im);
        for (int i = 0; i < w * h; ++i)
            out->p[i] = m - im->p[i];
        break;
    case 3:
        if (a[0] < -255 || a[0] > 255) {
            error("bad value");
            return;
        }
        out = copy_image(im);
        for (int i = 0; i < w * h; ++i)
            out->p[i] = clamp(im->p[i] + a[0], 0, m);
        break;
    case 4:
        if (a[0] < 0 || a[0] > 100 || a[1] < 1 || a[1] > 100) {
            error("bad value");
            return;
        }
        out = copy_image(im);
        for (int i = 0; i < w * h; ++i) {
            int center = (m + 1) / 2;
            out->p[i] = clamp(center + floor_div((im->p[i] - center) * a[0], a[1]), 0, m);
        }
        break;
    case 5:
        if (a[0] < 0 || a[0] > m) {
            error("bad value");
            return;
        }
        out = copy_image(im);
        for (int i = 0; i < w * h; ++i)
            out->p[i] = im->p[i] >= a[0] ? m : 0;
        break;
    case 6:
        if (a[0] < 0 || a[0] >= a[1] || a[1] > m) {
            error("bad value");
            return;
        }
        out = copy_image(im);
        for (int i = 0; i < w * h; ++i)
            out->p[i] = clamp(floor_div((im->p[i] - a[0]) * m, a[1] - a[0]), 0, m);
        break;
    case 7:
        if (a[0] < 2 || a[0] > m + 1) {
            error("bad value");
            return;
        }
        out = copy_image(im);
        for (int i = 0; i < w * h; ++i) {
            int q = im->p[i] * a[0] / (m + 1);
            out->p[i] = q * m / (a[0] - 1);
        }
        break;
    case 8:
        if (a[0] < 1 || a[0] > 255) {
            error("bad value");
            return;
        }
        out = make_image(w, h, a[0]);
        for (int i = 0; i < w * h; ++i)
            out->p[i] = (2 * im->p[i] * a[0] + m) / (2 * m);
        break;
    case 9:
    case 10:
        out = copy_image(im);
        for (int y = 0; y < h; ++y)
            for (int x = 0; x < w; ++x)
                set_pixel(out, x, y,
                          index == 9 ? pixel(im, w - 1 - x, y) : pixel(im, x, h - 1 - y));
        break;
    case 11:
        if (a[0] != 90 && a[0] != 180 && a[0] != 270) {
            error("bad value");
            return;
        }
        out = make_image(a[0] == 180 ? w : h, a[0] == 180 ? h : w, m);
        for (int y = 0; y < out->h; ++y)
            for (int x = 0; x < out->w; ++x) {
                int v = a[0] == 180  ? pixel(im, w - 1 - x, h - 1 - y)
                        : a[0] == 90 ? pixel(im, y, h - 1 - x)
                                     : pixel(im, w - 1 - y, x);
                set_pixel(out, x, y, v);
            }
        break;
    case 12:
        if (!valid_crop(im, a[0], a[1], a[2], a[3])) {
            error("bad value");
            return;
        }
        out = make_image(a[2], a[3], m);
        for (int y = 0; y < out->h; ++y)
            for (int x = 0; x < out->w; ++x)
                set_pixel(out, x, y, pixel(im, a[0] + x, a[1] + y));
        break;
    case 13:
        if (a[0] < 1 || a[1] < 0 || a[1] > m) {
            error("bad value");
            return;
        }
        if (w + 2 * a[0] > 64 || h + 2 * a[0] > 64) {
            error("too large");
            return;
        }
        out = make_image(w + 2 * a[0], h + 2 * a[0], m);
        for (int y = 0; y < out->h; ++y)
            for (int x = 0; x < out->w; ++x) {
                int px = x - a[0], py = y - a[0];
                set_pixel(out, x, y, contains(im, px, py) ? pixel(im, px, py) : a[1]);
            }
        break;
    case 14:
        if (a[0] < 1 || a[0] > 16 || a[1] < 1 || a[1] > 16) {
            error("bad value");
            return;
        }
        {
            int nw = w * a[0] / a[1], nh = h * a[0] / a[1];
            if (nw == 0 || nh == 0) {
                error("too small");
                return;
            }
            if (nw > 64 || nh > 64) {
                error("too large");
                return;
            }
            out = make_image(nw, nh, m);
            for (int y = 0; y < nh; ++y)
                for (int x = 0; x < nw; ++x)
                    set_pixel(out, x, y,
                              pixel(im, (2 * x + 1) * a[1] / (2 * a[0]),
                                    (2 * y + 1) * a[1] / (2 * a[0])));
        }
        break;
    case 15:
        if (a[0] < -1000 || a[0] > 1000 || a[1] < -1000 || a[1] > 1000 || a[2] < 0 || a[2] > m) {
            error("bad value");
            return;
        }
        out = copy_image(im);
        for (int y = 0; y < h; ++y)
            for (int x = 0; x < w; ++x) {
                int sx = x - a[0], sy = y - a[1];
                set_pixel(out, x, y, contains(im, sx, sy) ? pixel(im, sx, sy) : a[2]);
            }
        break;
    case 16:
        if (a[0] < 1 || a[1] < 1) {
            error("bad value");
            return;
        }
        if (w * a[0] > 64 || h * a[1] > 64) {
            error("too large");
            return;
        }
        out = make_image(w * a[0], h * a[1], m);
        for (int y = 0; y < out->h; ++y)
            for (int x = 0; x < out->w; ++x)
                set_pixel(out, x, y, pixel(im, x % w, y % h));
        break;
    case 17:
    case 18:
    case 19:
    case 20: {
        int kernel[9] = {1, 1, 1, 1, 1, 1, 1, 1, 1}, divisor = 9;
        if (index == 18) {
            int gaussian[9] = {1, 2, 1, 2, 4, 2, 1, 2, 1};
            memcpy(kernel, gaussian, sizeof(kernel));
            divisor = 16;
        } else if (index == 19) {
            int sharp[9] = {0, -1, 0, -1, 5, -1, 0, -1, 0};
            memcpy(kernel, sharp, sizeof(kernel));
            divisor = 1;
        } else if (index == 20) {
            for (int i = 0; i < 9; ++i)
                if (a[i] < -16 || a[i] > 16) {
                    error("bad value");
                    return;
                }
            if (a[9] < 1 || a[9] > 256) {
                error("bad value");
                return;
            }
            memcpy(kernel, a, sizeof(kernel));
            divisor = a[9];
        }
        out = convoluted(im, kernel, divisor);
    } break;
    case 21:
        out = copy_image(im);
        for (int y = 0; y < h; ++y)
            for (int x = 0; x < w; ++x) {
                int q[9], i = 0;
                for (int dy = -1; dy <= 1; ++dy)
                    for (int dx = -1; dx <= 1; ++dx)
                        q[i++] = pixel(im, clamp(x + dx, 0, w - 1), clamp(y + dy, 0, h - 1));
                int gx = q[2] + 2 * q[5] + q[8] - q[0] - 2 * q[3] - q[6];
                int gy = q[6] + 2 * q[7] + q[8] - q[0] - 2 * q[1] - q[2];
                set_pixel(out, x, y, clamp(abs(gx) + abs(gy), 0, m));
            }
        break;
    case 22:
    case 23:
    case 24:
        out = rank_filter(im, index == 22 ? 4 : index == 23 ? 0 : 8);
        break;
    case 25:
    case 26: {
        Image *middle = rank_filter(im, index == 25 ? 0 : 8);
        out = rank_filter(middle, index == 25 ? 8 : 0);
        free(middle);
    } break;
    case 27: {
        Image *high = rank_filter(im, 8), *low = rank_filter(im, 0);
        out = copy_image(im);
        for (int i = 0; i < w * h; ++i)
            out->p[i] = high->p[i] - low->p[i];
        free(high);
        free(low);
    } break;
    case 28:
    case 29:
    case 30:
    case 31: {
        int value = index == 30 ? a[3] : index == 31 ? a[2] : a[4];
        if (value < 0 || value > m) {
            error("bad value");
            return;
        }
        if (index == 28) {
            for (int i = 0; i < 4; ++i)
                if (a[i] < -1000 || a[i] > 1000) {
                    error("bad value");
                    return;
                }
        } else if (index == 29) {
            if (a[0] < -1000 || a[0] > 1000 || a[1] < -1000 || a[1] > 1000 || a[2] < 1 ||
                a[2] > 1000 || a[3] < 1 || a[3] > 1000) {
                error("bad value");
                return;
            }
        } else if (index == 30) {
            if (a[0] < -1000 || a[0] > 1000 || a[1] < -1000 || a[1] > 1000 || a[2] < 0 ||
                a[2] > 1000) {
                error("bad value");
                return;
            }
        } else if (!contains(im, a[0], a[1])) {
            error("bad value");
            return;
        }
        out = copy_image(im);
        unsigned char painted_mask[MAX_PIXELS] = {0};
        int painted = 0;
        if (index == 28) {
            int x = a[0], y = a[1], x1 = a[2], y1 = a[3];
            int dx = abs(x1 - x), dy = -abs(y1 - y);
            int sx = x < x1 ? 1 : -1, sy = y < y1 ? 1 : -1, e = dx + dy;
            for (;;) {
                painted += mark(out, painted_mask, x, y, value);
                if (x == x1 && y == y1)
                    break;
                int e2 = 2 * e;
                if (e2 >= dy) {
                    e += dy;
                    x += sx;
                }
                if (e2 <= dx) {
                    e += dx;
                    y += sy;
                }
            }
        } else if (index == 29) {
            int left = a[0], top = a[1], right = a[0] + a[2] - 1, bottom = a[1] + a[3] - 1;
            for (int y = maximum(0, top); y <= minimum(h - 1, bottom); ++y)
                for (int x = maximum(0, left); x <= minimum(w - 1, right); ++x)
                    if (fill || x == left || x == right || y == top || y == bottom)
                        painted += mark(out, painted_mask, x, y, value);
        } else if (index == 30) {
            paint_circle(out, painted_mask, a[0], a[1], a[2], fill, value, &painted);
        } else {
            int start = a[1] * w + a[0], target = im->p[start];
            int stack[MAX_PIXELS], top = 0;
            unsigned char seen[MAX_PIXELS] = {0};
            stack[top++] = start;
            seen[start] = 1;
            while (top > 0) {
                int i = stack[--top], x = i % w, y = i / w;
                painted += mark(out, painted_mask, x, y, value);
                const int dx[4] = {0, -1, 1, 0}, dy[4] = {-1, 0, 0, 1};
                for (int j = 0; j < 4; ++j) {
                    int nx = x + dx[j], ny = y + dy[j];
                    if (!contains(im, nx, ny))
                        continue;
                    int ni = ny * w + nx;
                    if (!seen[ni] && im->p[ni] == target) {
                        seen[ni] = 1;
                        stack[top++] = ni;
                    }
                }
            }
        }
        commit(ed, out, painted);
    }
        return;
    case 32:
        histogram(im);
        return;
    case 33: {
        int counts[256] = {0}, cdf[256] = {0}, total = 0;
        for (int i = 0; i < w * h; ++i)
            ++counts[im->p[i]];
        int u0 = 0;
        for (int u = 0; u <= m; ++u) {
            total += counts[u];
            cdf[u] = total;
            if (counts[u] && !counts[u0])
                u0 = u;
        }
        int cmin = cdf[u0], span = w * h - cmin;
        out = copy_image(im);
        if (span != 0)
            for (int i = 0; i < w * h; ++i)
                out->p[i] = (2 * (cdf[im->p[i]] - cmin) * m + span) / (2 * span);
    } break;
    case 34:
        if (a[0] < 0 || a[0] > m) {
            error("bad value");
            return;
        }
        labels(im, a[0]);
        return;
    case 35:
        if (a[0] < 0 || a[0] > m) {
            error("bad value");
            return;
        }
        out = copy_image(im);
        distance_transform(out, a[0]);
        break;
    case 36:
        statistics(im, 0, 0, w, h);
        return;
    case 37:
        if (!valid_crop(im, a[0], a[1], a[2], a[3])) {
            error("bad value");
            return;
        }
        statistics(im, a[0], a[1], a[2], a[3]);
        return;
    case 38: {
        int e[MAX_PIXELS];
        memcpy(e, im->p, (size_t)w * h * sizeof(int));
        out = copy_image(im);
        const int dx[4] = {1, -1, 0, 1}, dy[4] = {0, 1, 1, 1}, weight[4] = {7, 3, 5, 1};
        for (int y = 0; y < h; ++y)
            for (int x = 0; x < w; ++x) {
                int i = y * w + x, old = e[i], next = 2 * old >= m ? m : 0, err = old - next;
                out->p[i] = next;
                for (int j = 0; j < 4; ++j) {
                    int nx = x + dx[j], ny = y + dy[j];
                    if (contains(im, nx, ny))
                        e[ny * w + nx] += floor_div(err * weight[j], 16);
                }
            }
    } break;
    case 39: {
        const char *shades = "@#*+=~-:,.";
        for (int y = 0; y < h; ++y) {
            for (int x = 0; x < w; ++x)
                putchar(shades[pixel(im, x, y) * 10 / (m + 1)]);
            putchar('\n');
        }
    }
        return;
    case 40: {
        int existing = slot_index(ed, slot);
        if (existing < 0) {
            existing = ed->slot_count++;
            strcpy(ed->slots[existing].name, slot);
            ed->slots[existing].image = NULL;
        }
        free(ed->slots[existing].image);
        ed->slots[existing].image = copy_image(im);
        printf("stored %s ", slot);
        summary(ed->slots[existing].image);
        putchar('\n');
    }
        return;
    case 41: {
        char label[40];
        snprintf(label, sizeof(label), "recalled %s", slot);
        replace(ed, copy_image(ed->slots[si].image), label);
    }
        return;
    case 42:
        free(ed->slots[si].image);
        memmove(&ed->slots[si], &ed->slots[si + 1],
                (size_t)(ed->slot_count - si - 1) * sizeof(Slot));
        --ed->slot_count;
        printf("dropped %s\n", slot);
        return;
    case 43:
    case 44: {
        const Image *other = ed->slots[si].image;
        if (index == 43 && (a[1] < 1 || a[1] > 100 || a[0] < 0 || a[0] > a[1])) {
            error("bad value");
            return;
        }
        if (other->w != w || other->h != h) {
            error("size mismatch");
            return;
        }
        if (other->m != m) {
            error("maxval mismatch");
            return;
        }
        out = copy_image(im);
        for (int i = 0; i < w * h; ++i)
            out->p[i] = index == 43 ? (im->p[i] * (a[1] - a[0]) + other->p[i] * a[0]) / a[1]
                                    : abs(im->p[i] - other->p[i]);
    } break;
    case 45: {
        if (a[0] < -1000 || a[0] > 1000 || a[1] < -1000 || a[1] > 1000) {
            error("bad value");
            return;
        }
        const Image *other = ed->slots[si].image;
        if (other->m != m) {
            error("maxval mismatch");
            return;
        }
        int painted = 0;
        out = copy_image(im);
        for (int y = 0; y < other->h; ++y)
            for (int x = 0; x < other->w; ++x)
                if (contains(im, x + a[0], y + a[1])) {
                    set_pixel(out, x + a[0], y + a[1], pixel(other, x, y));
                    ++painted;
                }
        commit(ed, out, painted);
    }
        return;
    case 46:
        if (!ed->slot_count) {
            puts("no slots");
            return;
        }
        qsort(ed->slots, (size_t)ed->slot_count, sizeof(Slot), slot_compare);
        for (int i = 0; i < ed->slot_count; ++i) {
            printf("%s ", ed->slots[i].name);
            summary(ed->slots[i].image);
            putchar('\n');
        }
        return;
    case 47:
        printf("image ");
        if (!im)
            printf("none");
        else
            summary(im);
        printf(" undo %d redo %d slots %d\n", ed->undo_count, ed->redo_count, ed->slot_count);
        return;
    case 48:
        if (!ed->undo_count) {
            error("nothing to undo");
            return;
        }
        ed->redo[ed->redo_count++] = ed->current;
        ed->current = ed->undo[--ed->undo_count];
        printf("undo ");
        summary(ed->current);
        putchar('\n');
        return;
    case 49:
        if (!ed->redo_count) {
            error("nothing to redo");
            return;
        }
        ed->undo[ed->undo_count++] = ed->current;
        ed->current = ed->redo[--ed->redo_count];
        printf("redo ");
        summary(ed->current);
        putchar('\n');
        return;
    }
    commit(ed, out, -1);
}

int main(void) {
    int count;
    if (scanf("%d\n", &count) != 1)
        return 0;
    Editor *ed = calloc(1, sizeof(*ed));
    if (!ed)
        return EXIT_FAILURE;
    for (int command = 0; command < count; ++command) {
        char line[512];
        char *tokens[MAX_ARGS + 2];
        int n = 0;
        if (!fgets(line, sizeof(line), stdin))
            break;
        for (char *part = strtok(line, " \t\r\n"); part && n < MAX_ARGS + 2;
             part = strtok(NULL, " \t\r\n"))
            tokens[n++] = part;
        if (!n)
            continue;
        if (!strcmp(tokens[0], "LOAD"))
            load_pgm(ed, atoi(tokens[1]));
        else
            execute(ed, tokens, n);
    }
    free(ed->current);
    clear_images(ed->undo, &ed->undo_count);
    clear_images(ed->redo, &ed->redo_count);
    for (int i = 0; i < ed->slot_count; ++i)
        free(ed->slots[i].image);
    free(ed);
    return 0;
}
