#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdarg.h>
#include <setjmp.h>

typedef int64_t Integer;
typedef struct {
    Integer tick;
    int status, meta;
    unsigned char *data;
    size_t length;
} Event;
typedef struct {
    Event *events;
    size_t count, capacity;
} Track;
typedef struct Song {
    char name[17];
    int format, division;
    Track *tracks;
    size_t count;
    struct Song *next;
} Song;
typedef struct {
    Event *event;
    int track;
    size_t index, order;
} Ref;
typedef struct {
    Ref on, off;
} Note;
typedef struct {
    Note *notes;
    size_t count;
    Ref *unmatched;
    size_t unmatched_count;
} Pairing;
typedef struct {
    unsigned char *data;
    size_t count, capacity;
} Buffer;
static Song *songs;
static Song *loading_song;
static Buffer loading_bytes;
static int running = 1, zero_off;
static jmp_buf failure;
static char error_message[256];
static const char *channel_types[] = {"NOTE_OFF", "NOTE_ON",          "POLY_PRESSURE", "CONTROL",
                                      "PROGRAM",  "CHANNEL_PRESSURE", "PITCH_BEND"};
static const char *text_types[] = {"TEXT_EVENT", "COPYRIGHT", "TRACK_NAME", "INSTRUMENT_NAME",
                                   "LYRIC",      "MARKER",    "CUE_POINT"};
static const char *pitches[] = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"};
static const char *keys[2][15] = {
    {"Cb", "Gb", "Db", "Ab", "Eb", "Bb", "F", "C", "G", "D", "A", "E", "B", "F#", "C#"},
    {"Ab", "Eb", "Bb", "F", "C", "G", "D", "A", "E", "B", "F#", "C#", "G#", "D#", "A#"}};
static void fail(const char *format, ...) {
    va_list args;
    va_start(args, format);
    vsnprintf(error_message, sizeof(error_message), format, args);
    va_end(args);
    longjmp(failure, 1);
}
static int range(Integer x, Integer low, Integer high) {
    return low <= x && x <= high;
}
static int channel(Event e) {
    return e.status < 240;
}
static int ch(Event e) {
    return (e.status & 15) + 1;
}
static int on(Event e) {
    return channel(e) && e.status >> 4 == 9 && e.data[1] > 0;
}
static int off(Event e) {
    return channel(e) && (e.status >> 4 == 8 || (e.status >> 4 == 9 && e.data[1] == 0));
}
static int end_event(Event e) {
    return e.status == 255 && e.meta == 47;
}
static Integer number(Event e) {
    Integer n = 0;
    for (size_t i = 0; i < e.length; ++i)
        n = n * 256 + e.data[i];
    return n;
}
static const char *meta_type(int meta) {
    switch (meta) {
    case 0:
        return "SEQUENCE_NUMBER";
    case 32:
        return "CHANNEL_PREFIX";
    case 47:
        return "END_OF_TRACK";
    case 81:
        return "TEMPO";
    case 84:
        return "SMPTE_OFFSET";
    case 88:
        return "TIME_SIGNATURE";
    case 89:
        return "KEY_SIGNATURE";
    case 127:
        return "SEQUENCER_SPECIFIC";
    default:
        return "META";
    }
}
static const char *type(Event e) {
    if (channel(e))
        return channel_types[(e.status >> 4) - 8];
    if (e.status == 240)
        return "SYSEX";
    if (e.status == 247)
        return "SYSEX_ESCAPE";
    if (range(e.meta, 1, 7))
        return text_types[e.meta - 1];
    return meta_type(e.meta);
}
static void pitch_name(int pitch, char *out) {
    sprintf(out, "%s%d", pitches[pitch % 12], pitch / 12 - 1);
}
static int parse_pitch(const char *text) {
    char name[8];
    for (int p = 0; p < 128; ++p) {
        pitch_name(p, name);
        if (!strcmp(name, text))
            return p;
    }
    return -1;
}
static Event event(Integer tick, int status, int meta, const unsigned char *data, size_t length) {
    Event e = {.tick = tick, .status = status, .meta = meta, .length = length};
    e.data = length ? malloc(length) : NULL;
    if (length)
        memcpy(e.data, data, length);
    return e;
}
static Event number_event(Integer tick, int meta, Integer value, int length) {
    unsigned char data[8];
    for (int i = length - 1; i >= 0; --i) {
        data[i] = value & 255;
        value >>= 8;
    }
    return event(tick, 255, meta, data, (size_t)length);
}
static void append(Track *t, Event e) {
    if (t->count == t->capacity) {
        t->capacity = t->capacity ? t->capacity * 2 : 8;
        t->events = realloc(t->events, t->capacity * sizeof(Event));
    }
    t->events[t->count++] = e;
}
static Song *new_song(int format, int tracks, int division) {
    Song *s = calloc(1, sizeof(*s));
    s->format = format;
    s->division = division;
    s->count = tracks;
    s->tracks = calloc((size_t)tracks, sizeof(Track));
    return s;
}
static void free_tracks(Song *s) {
    for (size_t tr = 0; tr < s->count; ++tr) {
        for (size_t i = 0; i < s->tracks[tr].count; ++i)
            free(s->tracks[tr].events[i].data);
        free(s->tracks[tr].events);
    }
    free(s->tracks);
}
static Song *copy_song(const Song *s) {
    Song *r = new_song(s->format, (int)s->count, s->division);
    for (size_t tr = 0; tr < s->count; ++tr)
        for (size_t i = 0; i < s->tracks[tr].count; ++i) {
            Event e = s->tracks[tr].events[i];
            append(&r->tracks[tr], event(e.tick, e.status, e.meta, e.data, e.length));
        }
    return r;
}
static Song *find_song(const char *name) {
    for (Song *s = songs; s; s = s->next)
        if (!strcmp(s->name, name))
            return s;
    return NULL;
}
static void register_song(Song *s, const char *name) {
    Song *old = find_song(name);
    if (old) {
        free_tracks(old);
        old->format = s->format;
        old->division = s->division;
        old->tracks = s->tracks;
        old->count = s->count;
        free(s);
    } else {
        strcpy(s->name, name);
        s->next = songs;
        songs = s;
    }
}
static size_t event_count(const Song *s) {
    size_t n = 0;
    for (size_t tr = 0; tr < s->count; ++tr)
        n += s->tracks[tr].count;
    return n;
}
static Integer song_length(const Song *s) {
    Integer length = 0;
    for (size_t tr = 0; tr < s->count; ++tr) {
        Track t = s->tracks[tr];
        if (t.events[t.count - 1].tick > length)
            length = t.events[t.count - 1].tick;
    }
    return length;
}
static void summary(const Song *s) {
    printf("format %d tracks %zu division %d events %zu", s->format, s->count, s->division,
           event_count(s));
}
static int compare_refs(const void *a, const void *b) {
    const Ref *x = a, *y = b;
    if (x->event->tick != y->event->tick)
        return x->event->tick < y->event->tick ? -1 : 1;
    if (x->track != y->track)
        return x->track - y->track;
    return x->index < y->index ? -1 : x->index > y->index;
}
static Ref *global(const Song *s, size_t *count) {
    *count = event_count(s);
    Ref *r = malloc(*count * sizeof(Ref));
    size_t n = 0;
    for (size_t tr = 0; tr < s->count; ++tr)
        for (size_t i = 0; i < s->tracks[tr].count; ++i)
            r[n++] = (Ref){&s->tracks[tr].events[i], (int)tr, i, 0};
    qsort(r, n, sizeof(Ref), compare_refs);
    for (size_t i = 0; i < n; ++i)
        r[i].order = i;
    return r;
}
static void print_blob(Event e) {
    printf("%zu", e.length);
    if (e.length) {
        putchar(' ');
        for (size_t i = 0; i < e.length; ++i)
            printf("%02X", e.data[i]);
    }
}
static void print_event(Event e, int track) {
    printf("%lld %d %s", (long long)e.tick, track, type(e));
    if (channel(e)) {
        int code = e.status >> 4;
        printf(" %d ", ch(e));
        if (range(code, 8, 10)) {
            char name[8];
            pitch_name(e.data[0], name);
            printf("%s %d", name, e.data[1]);
        } else if (code == 11)
            printf("%d %d", e.data[0], e.data[1]);
        else if (code == 14)
            printf("%d", e.data[0] + 128 * e.data[1] - 8192);
        else
            printf("%d", e.data[0]);
    } else if (e.status != 255) {
        putchar(' ');
        print_blob(e);
    } else if (range(e.meta, 1, 7)) {
        printf(" \"");
        fwrite(e.data, 1, e.length, stdout);
        putchar('"');
    } else
        switch (e.meta) {
        case 0:
        case 81:
            printf(" %lld", (long long)number(e));
            break;
        case 32:
            printf(" %d", e.data[0] + 1);
            break;
        case 47:
            break;
        case 84:
            for (size_t i = 0; i < 5; ++i)
                printf(" %d", e.data[i]);
            break;
        case 88:
            printf(" %d/%d %d %d", e.data[0], 1 << e.data[1], e.data[2], e.data[3]);
            break;
        case 89:
            printf(" %s %s", keys[e.data[1]][(int8_t)e.data[0] + 7], e.data[1] ? "minor" : "major");
            break;
        case 127:
            putchar(' ');
            print_blob(e);
            break;
        default:
            printf(" %02X ", e.meta);
            print_blob(e);
            break;
        }
    putchar('\n');
}
static Integer read_big(const unsigned char *data, size_t p, int n) {
    Integer value = 0;
    for (int i = 0; i < n; ++i)
        value = value * 256 + data[p + i];
    return value;
}
static size_t chunk(const unsigned char *data, size_t size, size_t p, const char *id) {
    if (size - p < 8)
        fail("byte %zu: truncated chunk", p);
    if (memcmp(data + p, id, 4))
        fail("byte %zu: bad chunk id", p);
    Integer end = (Integer)p + 8 + read_big(data, p + 4, 4);
    if (end > (Integer)size)
        fail("byte %zu: truncated chunk", p);
    return (size_t)end;
}
static int read_byte(const unsigned char *data, size_t *p, size_t end, size_t start) {
    if (*p >= end)
        fail("byte %zu: truncated event", start);
    return data[(*p)++];
}
static Integer read_var(const unsigned char *data, size_t *p, size_t end, size_t start) {
    size_t at = *p;
    Integer value = 0;
    for (int i = 0; i < 4; ++i) {
        int b = read_byte(data, p, end, start);
        value = value * 128 + (b & 127);
        if (b < 128)
            return value;
    }
    fail("byte %zu: variable-length value too long", at);
    return 0;
}
static void validate_meta(Event e, size_t position) {
    int length = -1;
    switch (e.meta) {
    case 0:
        length = 2;
        break;
    case 32:
        length = 1;
        break;
    case 47:
        length = 0;
        break;
    case 81:
        length = 3;
        break;
    case 84:
        length = 5;
        break;
    case 88:
        length = 4;
        break;
    case 89:
        length = 2;
        break;
    }
    if (length >= 0 && e.length != (size_t)length)
        fail("byte %zu: bad meta length", position);
    unsigned char *d = e.data;
    if ((e.meta == 81 && !number(e)) || (e.meta == 32 && d[0] > 15) ||
        (e.meta == 88 && (!d[0] || d[1] > 6)) ||
        (e.meta == 89 && (!range((int8_t)d[0], -7, 7) || d[1] > 1)))
        fail("byte %zu: bad meta data", position);
}
static Song *parse_hex(const unsigned char *data, size_t size) {
    size_t h = chunk(data, size, 0, "MThd");
    if (h != 14)
        fail("byte 4: bad header length");
    int f = (int)read_big(data, 8, 2), tracks = (int)read_big(data, 10, 2),
        division = (int)read_big(data, 12, 2);
    if (f > 2)
        fail("byte 8: bad format");
    if (!tracks || (!f && tracks != 1))
        fail("byte 10: bad track count");
    if (division & 32768)
        fail("byte 12: smpte timing not supported");
    if (!division)
        fail("byte 12: bad division");
    Song *s = new_song(f, tracks, division);
    loading_song = s;
    size_t p = 14;
    for (int tr = 0; tr < tracks; ++tr) {
        if (p == size)
            fail("byte %zu: missing track", p);
        size_t end = chunk(data, size, p, "MTrk");
        p += 8;
        Integer tick = 0;
        int running_status = 0;
        while (p < end) {
            Track *t = &s->tracks[tr];
            if (t->count && end_event(t->events[t->count - 1]))
                fail("byte %zu: event after end of track", p);
            size_t start = p;
            tick += read_var(data, &p, end, start);
            if (p >= end)
                fail("byte %zu: truncated event", start);
            size_t position = p;
            int status = data[p];
            if (status < 128) {
                if (!running_status)
                    fail("byte %zu: data byte without running status", p);
                status = running_status;
            } else
                ++p;
            Event e;
            if (status < 240) {
                running_status = status;
                int code = status >> 4, length = code == 12 || code == 13 ? 1 : 2;
                unsigned char d[2];
                for (int i = 0; i < length; ++i) {
                    size_t at = p;
                    int b = read_byte(data, &p, end, start);
                    if (b >= 128)
                        fail("byte %zu: bad data byte", at);
                    d[i] = (unsigned char)b;
                }
                e = event(tick, status, -1, d, (size_t)length);
            } else if (status == 240 || status == 247 || status == 255) {
                running_status = 0;
                int meta = status == 255 ? read_byte(data, &p, end, start) : -1;
                size_t length = (size_t)read_var(data, &p, end, start);
                if (length > end - p)
                    fail("byte %zu: truncated event", start);
                if (status == 255) {
                    Event view = {.tick = tick,
                                  .status = status,
                                  .meta = meta,
                                  .data = (unsigned char *)data + p,
                                  .length = length};
                    validate_meta(view, position);
                }
                e = event(tick, status, meta, data + p, length);
                p += length;
            } else {
                fail("byte %zu: unknown status byte", position);
                return s;
            }
            append(&s->tracks[tr], e);
        }
        Track *t = &s->tracks[tr];
        if (!t->count || !end_event(t->events[t->count - 1]))
            fail("byte %zu: missing end of track", end);
    }
    if (p < size)
        fail("byte %zu: extra data", p);
    return s;
}
static int hex_digit(char c) {
    return c >= '0' && c <= '9' ? c - '0' : c >= 'A' && c <= 'F' ? c - 'A' + 10 : -1;
}
static Integer text_num(char **a, int count, int i, Integer low, Integer high, int line) {
    if (i >= count)
        fail("line %d: bad value", line);
    char *end;
    Integer n = strtoll(a[i], &end, 10);
    if (*end || !range(n, low, high))
        fail("line %d: bad value", line);
    return n;
}
static Event text_event(Integer tick, const char *kind, char *fields, int line) {
    int text = -1, code = -1, meta = -1;
    for (int i = 0; i < 7; ++i) {
        if (!strcmp(kind, text_types[i]))
            text = i;
        if (!strcmp(kind, channel_types[i]))
            code = i + 8;
    }
    if (!strcmp(kind, "META"))
        meta = -2;
    for (int i = 0; i < 256; ++i)
        if (strcmp(meta_type(i), "META") && !strcmp(kind, meta_type(i)))
            meta = i;
    int sysex = !strcmp(kind, "SYSEX") ? 240 : !strcmp(kind, "SYSEX_ESCAPE") ? 247 : 0;
    if (text < 0 && code < 0 && meta == -1 && !sysex)
        fail("line %d: unknown event type", line);
    if (text >= 0) {
        size_t n = strlen(fields);
        if (n < 2 || fields[0] != '"' || fields[n - 1] != '"')
            fail("line %d: bad value", line);
        for (size_t i = 1; i + 1 < n; ++i)
            if (fields[i] == '"')
                fail("line %d: bad value", line);
        return event(tick, 255, text + 1, (unsigned char *)fields + 1, n - 2);
    }
    char *a[1002];
    int count = 0;
    for (char *p = strtok(fields, " "); p; p = strtok(NULL, " "))
        a[count++] = p;
    unsigned char d[8];
    size_t length = 0;
    if (code >= 0) {
        int required = code == 12 || code == 13 || code == 14 ? 2 : 3;
        if (count != required)
            fail("line %d: bad value", line);
        int channel = (int)text_num(a, count, 0, 1, 16, line);
        if (code <= 10) {
            int pitch = parse_pitch(a[1]);
            if (pitch < 0)
                fail("line %d: bad value", line);
            d[0] = (unsigned char)pitch;
            d[1] = (unsigned char)text_num(a, count, 2, 0, 127, line);
            length = 2;
        } else if (code == 14) {
            int value = (int)text_num(a, count, 1, -8192, 8191, line) + 8192;
            d[0] = value & 127;
            d[1] = value >> 7;
            length = 2;
        } else {
            d[0] = (unsigned char)text_num(a, count, 1, 0, 127, line);
            length = 1;
            if (code == 11) {
                d[1] = (unsigned char)text_num(a, count, 2, 0, 127, line);
                length = 2;
            }
        }
        return event(tick, (code << 4) + channel - 1, -1, d, length);
    }
    if (sysex || meta == 127 || meta == -2) {
        int index = meta == -2 ? 1 : 0;
        if (meta == -2) {
            if (!count || strlen(a[0]) != 2 || hex_digit(a[0][0]) < 0 || hex_digit(a[0][1]) < 0)
                fail("line %d: bad value", line);
            meta = hex_digit(a[0][0]) * 16 + hex_digit(a[0][1]);
            if (strcmp(meta_type(meta), "META") || range(meta, 1, 7))
                fail("line %d: bad value", line);
        }
        length = (size_t)text_num(a, count, index, 0, 1000000, line);
        if (count != index + (length ? 2 : 1) || (length && strlen(a[index + 1]) != 2 * length))
            fail("line %d: bad value", line);
        for (size_t i = 0; i < length; ++i) {
            int high = hex_digit(a[index + 1][2 * i]), low = hex_digit(a[index + 1][2 * i + 1]);
            if (high < 0 || low < 0)
                fail("line %d: bad value", line);
        }
        unsigned char *blob = length ? malloc(length) : NULL;
        for (size_t i = 0; i < length; ++i)
            blob[i] = hex_digit(a[index + 1][2 * i]) * 16 + hex_digit(a[index + 1][2 * i + 1]);
        Event e = event(tick, sysex ? sysex : 255, meta, blob, length);
        free(blob);
        return e;
    }
    int required = meta == 47 ? 0 : meta == 84 ? 5 : meta == 88 ? 3 : meta == 89 ? 2 : 1;
    if (count != required)
        fail("line %d: bad value", line);
    if (meta == 0 || meta == 81)
        return number_event(
            tick, meta,
            text_num(a, count, 0, meta == 81 ? 1 : 0, meta == 81 ? 16777215 : 65535, line),
            meta == 81 ? 3 : 2);
    if (meta == 32) {
        d[0] = (unsigned char)(text_num(a, count, 0, 1, 16, line) - 1);
        length = 1;
    }
    if (meta == 84) {
        length = 5;
        for (int i = 0; i < 5; ++i)
            d[i] = (unsigned char)text_num(a, count, i, 0, 255, line);
    }
    if (meta == 88) {
        char *slash = strchr(a[0], '/');
        if (!slash)
            fail("line %d: bad value", line);
        *slash = 0;
        Integer nn = strtoll(a[0], NULL, 10), dd = strtoll(slash + 1, NULL, 10);
        int exponent = -1;
        for (int i = 0; i <= 6; ++i)
            if ((1 << i) == dd)
                exponent = i;
        if (!range(nn, 1, 255) || exponent < 0)
            fail("line %d: bad value", line);
        d[0] = (unsigned char)nn;
        d[1] = (unsigned char)exponent;
        d[2] = (unsigned char)text_num(a, count, 1, 0, 255, line);
        d[3] = (unsigned char)text_num(a, count, 2, 0, 255, line);
        length = 4;
    }
    if (meta == 89) {
        int minor = !strcmp(a[1], "minor"), key = -1;
        if (strcmp(a[1], "major") && !minor)
            fail("line %d: bad value", line);
        for (int i = 0; i < 15; ++i)
            if (!strcmp(a[0], keys[minor][i]))
                key = i;
        if (key < 0)
            fail("line %d: bad value", line);
        d[0] = (unsigned char)(key - 7);
        d[1] = (unsigned char)minor;
        length = 2;
    }
    return event(tick, 255, meta, d, length);
}
static void reject_text_event(Event e, int line, const char *reason) {
    free(e.data);
    fail("line %d: %s", line, reason);
}
static Song *parse_text(char **lines, int count) {
    char h[1002], extra;
    long long f, tracks, division;
    if (sscanf(lines[0], "%1001s %lld %lld %lld %c", h, &f, &tracks, &division, &extra) != 4 ||
        strcmp(h, "HEADER") || !range(f, 0, 2) || !range(tracks, 1, 65535) ||
        !range(division, 1, 32767) || (!f && tracks != 1))
        fail("line 1: bad header");
    Song *s = new_song((int)f, (int)tracks, (int)division);
    loading_song = s;
    int current = 0;
    for (int i = 1; i < count; ++i) {
        char *p = lines[i], *tail;
        Integer tick = strtoll(p, &tail, 10);
        p = tail + 1;
        int tr = (int)strtol(p, &tail, 10);
        p = tail + 1;
        char *fields = strchr(p, ' ');
        if (fields)
            *fields++ = 0;
        else
            fields = p + strlen(p);
        Event e = text_event(tick, p, fields, i + 1);
        if (tr >= tracks)
            reject_text_event(e, i + 1, "bad track");
        Track *t = &s->tracks[current];
        int ended = t->count && end_event(t->events[t->count - 1]);
        if (tr < current)
            reject_text_event(e, i + 1, "out of order");
        if (tr > current && (!ended || tr > current + 1))
            reject_text_event(e, i + 1, "missing end of track");
        if (tr == current && ended)
            reject_text_event(e, i + 1, "event after end of track");
        if (tr == current + 1)
            t = &s->tracks[++current];
        if (t->count && tick < t->events[t->count - 1].tick)
            reject_text_event(e, i + 1, "out of order");
        append(t, e);
    }
    Track t = s->tracks[current];
    if (current + 1 < tracks || !t.count || !end_event(t.events[t.count - 1]))
        fail("line %d: missing end of track", count + 1);
    return s;
}
static void byte(Buffer *b, int value) {
    if (b->count == b->capacity) {
        b->capacity = b->capacity ? b->capacity * 2 : 64;
        b->data = realloc(b->data, b->capacity);
    }
    b->data[b->count++] = (unsigned char)value;
}
static void big(Buffer *b, Integer value, int n) {
    for (int i = n - 1; i >= 0; --i)
        byte(b, (int)(value >> (8 * i)) & 255);
}
static void bytes(Buffer *b, const unsigned char *data, size_t n) {
    for (size_t i = 0; i < n; ++i)
        byte(b, data[i]);
}
static void var(Buffer *b, Integer value) {
    unsigned char data[10];
    int n = 0;
    data[n++] = value & 127;
    while ((value >>= 7) > 0)
        data[n++] = (value & 127) | 128;
    while (n)
        byte(b, data[--n]);
}
static void encode(Song *s) {
    Buffer all = {0};
    bytes(&all, (unsigned char *)"MThd", 4);
    big(&all, 6, 4);
    big(&all, s->format, 2);
    big(&all, (Integer)s->count, 2);
    big(&all, s->division, 2);
    for (size_t tr = 0; tr < s->count; ++tr) {
        Buffer data = {0};
        Integer previous = 0;
        int last = -1;
        for (size_t i = 0; i < s->tracks[tr].count; ++i) {
            Event e = s->tracks[tr].events[i];
            var(&data, e.tick - previous);
            previous = e.tick;
            if (channel(e)) {
                int status = e.status, rewrite = zero_off && e.status >> 4 == 8;
                if (rewrite)
                    status = 0x90 + ch(e) - 1;
                if (!running || status != last)
                    byte(&data, status);
                byte(&data, e.data[0]);
                if (e.length > 1)
                    byte(&data, rewrite ? 0 : e.data[1]);
                last = status;
            } else {
                last = -1;
                byte(&data, e.status);
                if (e.status == 255)
                    byte(&data, e.meta);
                var(&data, (Integer)e.length);
                bytes(&data, e.data, e.length);
            }
        }
        bytes(&all, (unsigned char *)"MTrk", 4);
        big(&all, (Integer)data.count, 4);
        bytes(&all, data.data, data.count);
        free(data.data);
    }
    for (size_t i = 0; i < all.count; i += 16) {
        printf("%04zX:", i);
        for (size_t j = i; j < all.count && j < i + 16; ++j)
            printf(" %02X", all.data[j]);
        putchar('\n');
    }
    printf("%zu bytes\n", all.count);
    free(all.data);
}
static int compare_notes(const void *a, const void *b) {
    const Note *x = a, *y = b;
    Event e = *x->on.event, f = *y->on.event;
    if (e.tick != f.tick)
        return e.tick < f.tick ? -1 : 1;
    if (ch(e) != ch(f))
        return ch(e) - ch(f);
    if (e.data[0] != f.data[0])
        return e.data[0] - f.data[0];
    return x->on.order < y->on.order ? -1 : x->on.order > y->on.order;
}
static Pairing pair(Song *s) {
    size_t n;
    Ref *all = global(s, &n);
    unsigned char *matched = calloc(n, 1);
    Pairing p = {0};
    p.notes = malloc(n * sizeof(Note));
    p.unmatched = malloc(n * sizeof(Ref));
    for (size_t i = 0; i < n; ++i)
        if (off(*all[i].event))
            for (size_t j = 0; j < i; ++j)
                if (!matched[j] && on(*all[j].event) && ch(*all[j].event) == ch(*all[i].event) &&
                    all[j].event->data[0] == all[i].event->data[0]) {
                    matched[i] = matched[j] = 1;
                    p.notes[p.count++] = (Note){all[j], all[i]};
                    break;
                }
    for (size_t i = 0; i < n; ++i)
        if (!matched[i] && (on(*all[i].event) || off(*all[i].event)))
            p.unmatched[p.unmatched_count++] = all[i];
    qsort(p.notes, p.count, sizeof(Note), compare_notes);
    free(matched);
    free(all);
    return p;
}
static void free_pair(Pairing p) {
    free(p.notes);
    free(p.unmatched);
}
static void position(Song *s, Integer tick, char *time, char *bar_text) {
    size_t n;
    Ref *all = global(s, &n);
    Integer sum = 0, last = 0, tempo = 500000, start = 0, bar = 1, nn = 4, beat = s->division;
    for (size_t i = 0; i < n && all[i].event->tick <= tick; ++i) {
        Event e = *all[i].event;
        if (e.status != 255)
            continue;
        if (e.meta == 81) {
            sum += (e.tick - last) * tempo;
            last = e.tick;
            tempo = number(e);
        }
        if (e.meta == 88 && bar_text) {
            Integer size = nn * beat;
            bar += (e.tick - start + size - 1) / size;
            start = e.tick;
            nn = e.data[0];
            beat = s->division * 4 / (1 << e.data[1]);
        }
    }
    Integer micro = (sum + (tick - last) * tempo) / s->division, x = tick - start;
    sprintf(time, "%lld.%03lld", (long long)(micro / 1000), (long long)(micro % 1000));
    if (bar_text)
        sprintf(bar_text, "%lld:%lld:%lld", (long long)(bar + x / (nn * beat)),
                (long long)(x % (nn * beat) / beat + 1), (long long)(x % beat));
    free(all);
}
static void notes(Song *s) {
    Pairing p = pair(s);
    printf("notes %zu unmatched %zu\n", p.count, p.unmatched_count);
    for (size_t i = 0; i < p.count; ++i) {
        Event a = *p.notes[i].on.event, b = *p.notes[i].off.event;
        char pitch[8];
        pitch_name(a.data[0], pitch);
        printf("%lld %lld %d %s %d\n", (long long)a.tick, (long long)(b.tick - a.tick), ch(a),
               pitch, a.data[1]);
    }
    for (size_t i = 0; i < p.unmatched_count; ++i) {
        Ref r = p.unmatched[i];
        Event e = *r.event;
        char pitch[8];
        pitch_name(e.data[0], pitch);
        printf("unmatched %s %lld %d %d %s\n", on(e) ? "on" : "off", (long long)e.tick, r.track,
               ch(e), pitch);
    }
    free_pair(p);
}
static Integer floor_div(Integer n, Integer d) {
    return n >= 0 ? n / d : -((-n + d - 1) / d);
}
static int compare_tick(const void *a, const void *b) {
    const Ref *x = a, *y = b;
    if (x->event->tick != y->event->tick)
        return x->event->tick < y->event->tick ? -1 : 1;
    return x->index < y->index ? -1 : x->index > y->index;
}
static void quantize(Song *s, Integer grid, Integer strength) {
    Pairing p = pair(s);
    size_t targets = 0, moved = 0;
    for (size_t i = 0; i < p.count + p.unmatched_count; ++i) {
        Event *a, *b = NULL;
        if (i < p.count) {
            a = p.notes[i].on.event;
            b = p.notes[i].off.event;
        } else {
            a = p.unmatched[i - p.count].event;
            if (!on(*a))
                continue;
        }
        Integer lo = a->tick / grid * grid,
                g = a->tick - lo <= lo + grid - a->tick ? lo : lo + grid;
        Integer delta = floor_div(2 * (g - a->tick) * strength + 100, 200);
        ++targets;
        moved += delta != 0;
        a->tick += delta;
        if (b)
            b->tick += delta;
    }
    free_pair(p);
    for (size_t tr = 0; tr < s->count; ++tr) {
        Track *t = &s->tracks[tr];
        Event eot = t->events[t->count - 1];
        size_t n = t->count - 1;
        Ref *refs = malloc(n * sizeof(Ref));
        for (size_t i = 0; i < n; ++i)
            refs[i] = (Ref){&t->events[i], (int)tr, i, 0};
        qsort(refs, n, sizeof(Ref), compare_tick);
        Event *events = malloc(t->capacity * sizeof(Event));
        for (size_t i = 0; i < n; ++i)
            events[i] = *refs[i].event;
        if (n && events[n - 1].tick > eot.tick)
            eot.tick = events[n - 1].tick;
        events[n] = eot;
        free(refs);
        free(t->events);
        t->events = events;
    }
    printf("quantized %zu moved %zu\n", targets, moved);
}
static int compare_song_names(const void *a, const void *b) {
    return strcmp((*(Song *const *)a)->name, (*(Song *const *)b)->name);
}
static void stats(Song *s) {
    Pairing p = pair(s);
    summary(s);
    putchar('\n');
    printf("notes %zu unmatched %zu\n", p.count, p.unmatched_count);
    int minimum = 128, maximum = -1;
    for (int c = 1; c <= 16; ++c) {
        int low = 128, high = -1;
        size_t count = 0;
        for (size_t i = 0; i < p.count; ++i)
            if (ch(*p.notes[i].on.event) == c) {
                int pitch = p.notes[i].on.event->data[0];
                if (pitch < low)
                    low = pitch;
                if (pitch > high)
                    high = pitch;
                ++count;
            }
        if (count) {
            char a[8], b[8];
            pitch_name(low, a);
            pitch_name(high, b);
            printf("channel %d notes %zu range %s %s\n", c, count, a, b);
        }
        if (low < minimum)
            minimum = low;
        if (high > maximum)
            maximum = high;
    }
    if (!p.count)
        puts("range none");
    else {
        char a[8], b[8];
        pitch_name(minimum, a);
        pitch_name(maximum, b);
        printf("range %s %s\n", a, b);
    }
    char time[64];
    Integer length = song_length(s);
    position(s, length, time, NULL);
    printf("length %lld ticks %s ms\n", (long long)length, time);
    size_t best = 0;
    Integer best_at = 0;
    for (size_t i = 0; i < p.count; ++i) {
        Integer at = p.notes[i].on.event->tick;
        size_t current = 0;
        for (size_t j = 0; j < p.count; ++j)
            if (p.notes[j].on.event->tick <= at && at < p.notes[j].off.event->tick)
                ++current;
        if (current > best || (current == best && at < best_at)) {
            best = current;
            best_at = at;
        }
    }
    if (best)
        printf("polyphony %zu at %lld\n", best, (long long)best_at);
    else
        puts("polyphony 0");
    free_pair(p);
}
static void execute(char **a, int argc) {
    const char *cmd = a[0];
    const char *known[] = {"DECODE",    "ENCODE",   "TIMING",   "NOTES",   "STATS",  "ROLL",
                           "TRANSPOSE", "QUANTIZE", "VELOCITY", "TEMPO",   "FILTER", "MERGE",
                           "SPLIT",     "COPY",     "LIST",     "RUNNING", "NOTEOFF"};
    int found = 0;
    for (size_t i = 0; i < sizeof(known) / sizeof(*known); ++i)
        if (!strcmp(cmd, known[i]))
            found = 1;
    if (!found)
        fail("unknown command");
    if (!strcmp(cmd, "LIST")) {
        size_t n = 0;
        for (Song *s = songs; s; s = s->next)
            ++n;
        if (!n) {
            puts("no songs");
            return;
        }
        Song **sorted = malloc(n * sizeof(Song *));
        size_t i = 0;
        for (Song *s = songs; s; s = s->next)
            sorted[i++] = s;
        qsort(sorted, n, sizeof(Song *), compare_song_names);
        for (i = 0; i < n; ++i) {
            printf("%s ", sorted[i]->name);
            summary(sorted[i]);
            putchar('\n');
        }
        free(sorted);
        return;
    }
    if (!strcmp(cmd, "RUNNING") || !strcmp(cmd, "NOTEOFF")) {
        if (!strcmp(cmd, "RUNNING")) {
            if (strcmp(a[1], "ON") && strcmp(a[1], "OFF"))
                fail("bad argument");
            running = !strcmp(a[1], "ON");
            printf("running %s\n", running ? "on" : "off");
        } else {
            if (strcmp(a[1], "ZERO") && strcmp(a[1], "KEEP"))
                fail("bad argument");
            zero_off = !strcmp(a[1], "ZERO");
            printf("noteoff %s\n", zero_off ? "zero" : "keep");
        }
        return;
    }
    Song *s = find_song(a[1]);
    if (!s)
        fail("no song %s", a[1]);
    Integer first = argc > 2 ? strtoll(a[2], NULL, 10) : 0,
            second = argc > 3 ? strtoll(a[3], NULL, 10) : 0,
            third = argc > 4 ? strtoll(a[4], NULL, 10) : 0;
    if (!strcmp(cmd, "TRANSPOSE") &&
        (!range(first, -127, 127) || (argc == 4 && !range(second, 1, 16))))
        fail("bad argument");
    if (!strcmp(cmd, "QUANTIZE") && (!range(first, 1, 1000000) || !range(second, 0, 100)))
        fail("bad argument");
    if (!strcmp(cmd, "VELOCITY") && (!range(first, 0, 1000) || !range(second, -127, 127)))
        fail("bad argument");
    if (!strcmp(cmd, "TEMPO") && (!range(first, 1, 1000) || !range(second, 1, 1000)))
        fail("bad argument");
    if (!strcmp(cmd, "FILTER"))
        for (int i = 2; i < argc; ++i)
            if (!range(strtoll(a[i], NULL, 10), 1, 16))
                fail("bad argument");
    if (!strcmp(cmd, "ROLL") &&
        (!range(first, 0, 10000000) || !range(second, 1, 10000000) || !range(third, 1, 10000000) ||
         second <= first || (second - first + third - 1) / third > 64))
        fail("bad argument");
    if ((!strcmp(cmd, "TIMING") || !strcmp(cmd, "STATS")) && s->format == 2)
        fail("format 2 not supported");
    if (!strcmp(cmd, "DECODE")) {
        printf("HEADER %d %zu %d\n", s->format, s->count, s->division);
        for (size_t tr = 0; tr < s->count; ++tr)
            for (size_t i = 0; i < s->tracks[tr].count; ++i)
                print_event(s->tracks[tr].events[i], (int)tr);
    } else if (!strcmp(cmd, "ENCODE"))
        encode(s);
    else if (!strcmp(cmd, "NOTES"))
        notes(s);
    else if (!strcmp(cmd, "STATS"))
        stats(s);
    else if (!strcmp(cmd, "TIMING")) {
        size_t count;
        Ref *all = global(s, &count);
        char time[64], bar[64];
        for (size_t i = 0; i < count; ++i) {
            Event e = *all[i].event;
            position(s, e.tick, time, bar);
            printf("%lld %d %s %s %s\n", (long long)e.tick, all[i].track, type(e), time, bar);
        }
        Integer length = song_length(s);
        position(s, length, time, bar);
        printf("end %lld %s %s\n", (long long)length, time, bar);
        free(all);
    } else if (!strcmp(cmd, "COPY")) {
        Song *copy = copy_song(s);
        register_song(copy, a[2]);
        printf("copied %s to %s\n", a[1], a[2]);
    } else if (!strcmp(cmd, "TRANSPOSE")) {
        size_t kept = 0, dropped = 0;
        Track removed = {0};
        int *removed_tracks = malloc(event_count(s) * sizeof(int));
        for (size_t tr = 0; tr < s->count; ++tr) {
            Track *t = &s->tracks[tr];
            size_t write = 0;
            for (size_t i = 0; i < t->count; ++i) {
                Event e = t->events[i];
                if (channel(e) && range(e.status >> 4, 8, 10) && (argc == 3 || ch(e) == second)) {
                    Integer value = e.data[0] + first;
                    if (!range(value, 0, 127)) {
                        removed_tracks[dropped++] = (int)tr;
                        append(&removed, e);
                        continue;
                    }
                    e.data[0] = (unsigned char)value;
                    ++kept;
                }
                t->events[write++] = e;
            }
            t->count = write;
        }
        printf("transposed %zu dropped %zu\n", kept, dropped);
        for (size_t i = 0; i < dropped; ++i) {
            Event e = removed.events[i];
            char pitch[8];
            pitch_name(e.data[0], pitch);
            printf("dropped %lld %d %s %d %s\n", (long long)e.tick, removed_tracks[i], type(e),
                   ch(e), pitch);
            free(e.data);
        }
        free(removed.events);
        free(removed_tracks);
    } else if (!strcmp(cmd, "QUANTIZE"))
        quantize(s, first, second);
    else if (!strcmp(cmd, "VELOCITY")) {
        size_t count = 0, clamped = 0;
        for (size_t tr = 0; tr < s->count; ++tr)
            for (size_t i = 0; i < s->tracks[tr].count; ++i) {
                Event *e = &s->tracks[tr].events[i];
                if (!on(*e))
                    continue;
                Integer value = (e->data[1] * first + 50) / 100 + second;
                ++count;
                clamped += !range(value, 1, 127);
                e->data[1] = (unsigned char)(value < 1 ? 1 : value > 127 ? 127 : value);
            }
        printf("velocity %zu clamped %zu\n", count, clamped);
    } else if (!strcmp(cmd, "TEMPO")) {
        Song *candidate = copy_song(s);
        int at_zero = 0;
        size_t scaled = 0;
        for (size_t tr = 0; tr < candidate->count; ++tr)
            for (size_t i = 0; i < candidate->tracks[tr].count; ++i) {
                Event *e = &candidate->tracks[tr].events[i];
                if (e->status != 255 || e->meta != 81)
                    continue;
                Integer value = (2 * number(*e) * second + first) / (2 * first);
                if (!range(value, 1, 16777215)) {
                    free_tracks(candidate);
                    free(candidate);
                    fail("tempo out of range");
                }
                if (!e->tick)
                    at_zero = 1;
                ++scaled;
                free(e->data);
                *e = number_event(e->tick, 81, value, 3);
            }
        Integer inserted = (2 * 500000 * second + first) / (2 * first);
        if (!at_zero) {
            if (!range(inserted, 1, 16777215)) {
                free_tracks(candidate);
                free(candidate);
                fail("tempo out of range");
            }
            Track *t = &candidate->tracks[0];
            append(t, number_event(0, 81, inserted, 3));
            Event e = t->events[t->count - 1];
            memmove(t->events + 1, t->events, (t->count - 1) * sizeof(Event));
            t->events[0] = e;
        }
        register_song(candidate, a[1]);
        printf("scaled %zu\n", scaled);
        if (!at_zero)
            printf("inserted 0 0 TEMPO %lld\n", (long long)inserted);
    } else if (!strcmp(cmd, "FILTER")) {
        int allowed[17] = {0};
        for (int i = 2; i < argc; ++i)
            allowed[atoi(a[i])] = 1;
        size_t removed = 0;
        for (size_t tr = 0; tr < s->count; ++tr) {
            Track *t = &s->tracks[tr];
            size_t write = 0;
            for (size_t i = 0; i < t->count; ++i) {
                Event e = t->events[i];
                if (channel(e) && !allowed[ch(e)]) {
                    ++removed;
                    free(e.data);
                } else
                    t->events[write++] = e;
            }
            t->count = write;
        }
        printf("removed %zu\n", removed);
    } else if (!strcmp(cmd, "MERGE")) {
        if (s->format != 1)
            fail("not format 1");
        Integer length = song_length(s);
        size_t n, old = s->count;
        Ref *all = global(s, &n);
        Track merged = {0};
        for (size_t i = 0; i < n; ++i) {
            Event e = *all[i].event;
            if (!end_event(e))
                append(&merged, e);
            else
                free(e.data);
        }
        append(&merged, event(length, 255, 47, NULL, 0));
        free(all);
        for (size_t tr = 0; tr < s->count; ++tr)
            free(s->tracks[tr].events);
        free(s->tracks);
        s->tracks = malloc(sizeof(Track));
        s->tracks[0] = merged;
        s->count = 1;
        s->format = 0;
        printf("merged %zu tracks events %zu\n", old, event_count(s));
    } else if (!strcmp(cmd, "SPLIT")) {
        if (s->format != 0)
            fail("not format 0");
        Integer length = song_length(s);
        Track original = s->tracks[0];
        int channels[17] = {0}, mapping[17] = {0};
        size_t count = 1;
        for (size_t i = 0; i < original.count; ++i)
            if (channel(original.events[i]))
                channels[ch(original.events[i])] = 1;
        for (int c = 1; c <= 16; ++c)
            if (channels[c])
                mapping[c] = (int)count++;
        Track *tracks = calloc(count, sizeof(Track));
        for (size_t i = 0; i < original.count; ++i) {
            Event e = original.events[i];
            if (end_event(e)) {
                free(e.data);
                continue;
            }
            append(&tracks[channel(e) ? mapping[ch(e)] : 0], e);
        }
        for (size_t tr = 0; tr < count; ++tr)
            append(&tracks[tr], event(length, 255, 47, NULL, 0));
        free(original.events);
        free(s->tracks);
        s->tracks = tracks;
        s->count = count;
        s->format = 1;
        printf("split tracks %zu events %zu\n", count, event_count(s));
    } else if (!strcmp(cmd, "ROLL")) {
        Pairing p = pair(s);
        int any = 0;
        for (int pitch = 127; pitch >= 0; --pitch) {
            char row[65];
            size_t width = 0;
            int visible = 0;
            for (Integer at = first; at < second; at += third) {
                char cell = '.';
                for (size_t i = 0; i < p.count; ++i) {
                    Event on_event = *p.notes[i].on.event, off_event = *p.notes[i].off.event;
                    if (on_event.data[0] != pitch)
                        continue;
                    if (at <= on_event.tick && on_event.tick < at + third) {
                        cell = '#';
                        break;
                    }
                    if (on_event.tick <= at && at < off_event.tick)
                        cell = '=';
                }
                row[width++] = cell;
                visible |= cell != '.';
            }
            row[width] = 0;
            if (visible) {
                char name[8];
                pitch_name(pitch, name);
                printf("%-4s %s\n", name, row);
                any = 1;
            }
        }
        if (!any)
            puts("empty");
        free_pair(p);
    }
}
int main(void) {
    char line[1002];
    if (!fgets(line, sizeof(line), stdin))
        return 0;
    int commands = atoi(line);
    for (int command = 0; command < commands; ++command) {
        if (!fgets(line, sizeof(line), stdin))
            break;
        line[strcspn(line, "\r\n")] = 0;
        char *a[1002];
        int argc = 0;
        for (char *p = strtok(line, " "); p; p = strtok(NULL, " "))
            a[argc++] = p;
        if (!strcmp(a[0], "HEX") || !strcmp(a[0], "TEXT")) {
            int count = atoi(a[2]);
            char **lines = calloc((size_t)count, sizeof(char *));
            for (int i = 0; i < count; ++i) {
                char data[1002];
                fgets(data, sizeof(data), stdin);
                data[strcspn(data, "\r\n")] = 0;
                lines[i] = malloc(strlen(data) + 1);
                strcpy(lines[i], data);
            }
            if (!setjmp(failure)) {
                Song *s;
                if (!strcmp(a[0], "TEXT"))
                    s = parse_text(lines, count);
                else {
                    loading_bytes = (Buffer){0};
                    for (int i = 0; i < count; ++i)
                        for (char *p = strtok(lines[i], " "); p; p = strtok(NULL, " "))
                            byte(&loading_bytes, (int)strtol(p, NULL, 16));
                    s = parse_hex(loading_bytes.data, loading_bytes.count);
                    free(loading_bytes.data);
                    loading_bytes = (Buffer){0};
                }
                loading_song = NULL;
                register_song(s, a[1]);
                s = find_song(a[1]);
                printf("loaded %s ", a[1]);
                summary(s);
                putchar('\n');
            } else {
                if (loading_song) {
                    free_tracks(loading_song);
                    free(loading_song);
                    loading_song = NULL;
                }
                free(loading_bytes.data);
                loading_bytes = (Buffer){0};
                printf("error: %s\n", error_message);
            }
            for (int i = 0; i < count; ++i)
                free(lines[i]);
            free(lines);
        } else if (!setjmp(failure))
            execute(a, argc);
        else
            printf("error: %s\n", error_message);
    }
    while (songs) {
        Song *next = songs->next;
        free_tracks(songs);
        free(songs);
        songs = next;
    }
    return 0;
}
