#include "synthesizer.h"
static int hex(const char *text) {
    return (int)strtol(text, NULL, 16);
}
int note_number(const char *name) {
    const char *names[12] = {"C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#", "B-"};
    for (int i = 0; i < 12; ++i)
        if (!strncmp(name, names[i], 2))
            return 12 * (name[2] - '0') + i;
    return -1;
}
char *note_name(int note) {
    const char *names[12] = {"C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#", "B-"};
    return format("%s%d", names[note % 12], note / 12);
}
bool cell_empty(const Cell *c) {
    return c->note == -1 && c->instrument == 0 && c->volume < 0 && !c->effect.name[0];
}
static Effect effect(const char *text) {
    Effect out = {0};
    memcpy(out.text, text, 3);
    if (!strncmp(text, "...", 3))
        return out;
    if (text[0] == 'E') {
        memcpy(out.name, text, 2);
        out.argument = hex(format("%c", text[2]));
        out.x = out.argument;
    } else {
        out.name[0] = text[0];
        out.argument = hex(format("%c%c", text[1], text[2]));
        out.x = out.argument / 16;
        out.y = out.argument % 16;
    }
    return out;
}
static Cell cell(const char *text) {
    Cell out = {0};
    out.note = !strncmp(text, "...", 3) ? -1 : !strncmp(text, "OFF", 3) ? -2 : note_number(text);
    out.instrument = !strncmp(text + 4, "..", 2) ? 0 : hex(format("%.2s", text + 4));
    out.volume = text[7] == '.' ? -1 : hex(format("%c", text[7]));
    out.effect = effect(text + 9);
    return out;
}
Song *read_song(void) {
    Lines all = read_lines("input/song.txt"), lines = {0};
    for (size_t i = 0; i < all.len; ++i)
        if (*all.data[i] && *all.data[i] != '#')
            line_add(&lines, "%s", all.data[i]);
    Song *out = allocate(1, sizeof *out);
    out->title = format("%s", lines.data[0] + 6);
    out->rate = atoi(words(lines.data[1]).data[1]);
    out->speed = atoi(words(lines.data[2]).data[1]);
    out->tempo = atoi(words(lines.data[3]).data[1]);
    out->gain = atoi(words(lines.data[4]).data[1]);
    size_t i = 5;
    while (i < lines.len) {
        Lines header = words(lines.data[i++]);
        if (!strcmp(header.data[0], "ORDER")) {
            for (size_t j = 1; j < header.len; ++j)
                out->order[out->order_count++] = hex(header.data[j]);
            continue;
        }
        if (!strcmp(header.data[0], "PATTERN")) {
            Pattern *pattern = allocate(1, sizeof *pattern);
            for (int row = 0; row < 64; ++row)
                for (int k = 0; k < 4; ++k) {
                    pattern->rows[row][k].note = -1;
                    pattern->rows[row][k].volume = -1;
                    strcpy(pattern->rows[row][k].effect.text, "...");
                }
            while (strcmp(lines.data[i], "END")) {
                char *line = lines.data[i++];
                int row = hex(format("%.2s", line));
                for (int k = 0; k < 4; ++k)
                    pattern->rows[row][k] = cell(line + 3 + 15 * k);
            }
            ++i;
            out->patterns[hex(header.data[1])] = pattern;
            continue;
        }
        Instrument instrument = {0};
        instrument.defined = true;
        instrument.number = hex(header.data[1]);
        instrument.name = header.data[2];
        while (strcmp(lines.data[i], "END")) {
            Lines fields = words(lines.data[i++]);
            if (!strcmp(fields.data[0], "WAVE")) {
                if (!strcmp(fields.data[1], "PULSE")) {
                    instrument.wave = PULSE;
                    int duty = atoi(fields.data[2]);
                    instrument.mode = duty == 12 ? 0 : duty == 25 ? 1 : duty == 50 ? 2 : 3;
                } else if (!strcmp(fields.data[1], "TRIANGLE"))
                    instrument.wave = TRIANGLE;
                else if (!strcmp(fields.data[1], "SAW"))
                    instrument.wave = SAW;
                else if (!strcmp(fields.data[1], "NOISE")) {
                    instrument.wave = NOISE;
                    instrument.mode = !strcmp(fields.data[2], "SHORT") ? 1 : 0;
                } else {
                    instrument.wave = TABLE;
                    for (int j = 0; j < 32; ++j)
                        instrument.table[j] = hex(format("%c", fields.data[2][j]));
                }
            } else if (!strcmp(fields.data[0], "ENVELOPE")) {
                instrument.attack = atoi(fields.data[1]);
                instrument.decay = atoi(fields.data[2]);
                instrument.sustain = atoi(fields.data[3]);
                instrument.release = atoi(fields.data[4]);
            } else if (!strcmp(fields.data[0], "VIBRATO")) {
                instrument.vibrato = true;
                instrument.delay = atoi(fields.data[1]);
                instrument.speed = atoi(fields.data[2]);
                instrument.depth = atoi(fields.data[3]);
            } else if (!strcmp(fields.data[0], "ARPEGGIO"))
                for (size_t j = 1; j < fields.len; ++j)
                    instrument.arpeggio[instrument.arpeggio_count++] = atoi(fields.data[j]);
            else
                instrument.sweep = atoi(fields.data[1]);
        }
        ++i;
        out->instruments[instrument.number] = instrument;
    }
    return out;
}
Params read_params(void) {
    Lines lines = read_lines("input/params.txt");
    Params out = {0};
    for (size_t i = 0; i < lines.len; ++i) {
        Lines fields = words(lines.data[i]);
        if (i == 0)
            out.maximum = atoi(fields.data[1]);
        else if (i == 1)
            out.loops = atoi(fields.data[1]);
        else if (i == 2)
            out.fade = atoi(fields.data[1]);
        else if (i == 3)
            for (int j = 0; j < 4; ++j)
                out.muted[j] = atoi(fields.data[j + 1]) != 0;
        else if (i == 4) {
            out.start = atoi(fields.data[1]);
            out.length = atoi(fields.data[2]);
            out.width = atoi(fields.data[3]);
            out.height = atoi(fields.data[4]);
            out.scope = atoi(fields.data[5]);
        } else if (i == 5) {
            out.roll_start = atoi(fields.data[1]);
            out.roll_rows = atoi(fields.data[2]);
        } else if (i == 6) {
            out.preview_note = note_number(fields.data[1]);
            out.preview_ticks = atoi(fields.data[2]);
            out.preview_release = atoi(fields.data[3]);
        } else
            out.traces[hex(fields.data[1])][hex(fields.data[2])] = true;
    }
    return out;
}
