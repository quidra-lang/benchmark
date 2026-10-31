#include "synthesizer.h"
static Integer magnitude(Integer value) {
    return value < 0 ? -value : value;
}
Channel channel_create(void) {
    Channel c = {0};
    c.note = -1;
    c.volume = 15;
    c.noise = 1;
    c.record = -1;
    strcpy(c.effect.text, "...");
    return c;
}
static void compute_output(const Song *song, Channel *c, int tick) {
    c->sounding = c->note >= 0;
    if (!c->sounding)
        return;
    const Instrument *i = &song->instruments[c->instrument];
    const Effect *e = &c->effect;
    int semitones = !strcmp(e->name, "0") ? (tick % 3 == 0 ? 0 : tick % 3 == 1 ? e->x : e->y) : 0;
    if (i->arpeggio_count)
        semitones += i->arpeggio[c->age % i->arpeggio_count];
    Integer f = transpose(c->base, semitones) + c->detune;
    if (!strcmp(e->name, "4") || !strcmp(e->name, "6"))
        f += oscillation(c->vibrato_position, c->vibrato_depth, 4);
    if (i->vibrato && c->age >= i->delay)
        f += oscillation(((c->age - i->delay) * i->speed) % 64, i->depth, 4);
    c->output_frequency = clamp(f, 1000, 50 * song->rate);
    c->env = envelope(i, c->age, c->released, c->release_age, c->release_value);
    c->output_volume = !strcmp(e->name, "7")
                           ? clamp(c->volume + oscillation(c->tremolo_position, c->tremolo_depth, 255), 0, 15)
                           : c->volume;
    c->amplitude = c->env * c->output_volume;
    c->increment = floor_div(c->output_frequency * 65536, 100 * song->rate);
}
typedef struct {
    int channel, position, row, instrument, note;
    Integer start, length, release;
    const char *end;
} NoteRecord;
typedef struct {
    int position, pattern, row;
    Integer start;
    int speed, tempo, notes[4];
} RowRecord;
typedef struct {
    Integer notes, retriggers, cuts, active, audible;
} ChannelStats;
static const char *effect_order[25] = {"0",  "1",  "2", "3",  "4",  "5",  "6",  "7",  "A",
                                       "B",  "C",  "D", "E1", "E2", "E9", "EA", "EB", "EC",
                                       "ED", "EE", "F", "P",  "Q",  "R",  "V"};
typedef struct {
    const Song *song;
    Params params;
    Channel channels[4];
    ChannelStats channel_stats[4];
    Audio audio;
    NoteRecord *notes;
    size_t note_count, note_cap;
    RowRecord *rows;
    size_t row_count, row_cap;
    Lines logs, warnings;
    Integer instrument_ticks[256], effects[25], ticks, loop_start;
    int played[64][64];
    Integer first[64][64];
    char *end;
    int position, row, speed, tempo;
} Playback;
static Playback *playback_create(const Song *song, Params params) {
    Playback *p = allocate(1, sizeof *p);
    p->song = song;
    p->params = params;
    p->speed = song->speed;
    p->tempo = song->tempo;
    p->loop_start = -1;
    p->audio = audio_create(params.maximum);
    for (int k = 0; k < 4; ++k)
        p->channels[k] = channel_create();
    for (int i = 0; i < 64; ++i)
        for (int j = 0; j < 64; ++j)
            p->first[i][j] = -1;
    return p;
}
static void warn(Playback *p, int channel, const char *message) {
    line_add(&p->warnings, "warning %s:%s ch%d %s", hexadecimal(p->position, 2), hexadecimal(p->row, 2),
             channel + 1, message);
}
static void end_record(Playback *p, Channel *c, const char *reason) {
    if (c->record < 0)
        return;
    NoteRecord *r = &p->notes[c->record];
    r->length = (Integer)p->audio.count - r->start;
    r->end = reason;
    c->record = -1;
}
static void note_on(Playback *p, int channel, int note) {
    Channel *c = &p->channels[channel];
    end_record(p, c, "next");
    c->base = c->target = frequency(note);
    c->phase = c->age = c->vibrato_position = c->tremolo_position = 0;
    c->released = false;
    c->note = note;
    c->record = (int)p->note_count;
    grow((void **)&p->notes, &p->note_cap, p->note_count + 1, sizeof *p->notes);
    p->notes[p->note_count++] =
        (NoteRecord){channel, p->position, p->row, c->instrument, note, (Integer)p->audio.count, 0, -1, NULL};
    ++p->channel_stats[channel].notes;
}
static void key_off(Playback *p, Channel *c) {
    c->release_age = c->age;
    c->release_value = c->env;
    c->released = true;
    if (c->record >= 0)
        p->notes[c->record].release = (Integer)p->audio.count - p->notes[c->record].start;
}
static void content(Playback *p, int channel, const Cell *cell, bool portamento) {
    Channel *c = &p->channels[channel];
    if (cell->instrument) {
        const Instrument *i = &p->song->instruments[cell->instrument];
        if (!i->defined)
            warn(p, channel, format("undefined instrument %s", hexadecimal(cell->instrument, 2)));
        else {
            c->instrument = cell->instrument;
            c->volume = 15;
            c->mode = i->mode;
        }
    }
    if (cell->volume >= 0)
        c->volume = cell->volume;
    if (cell->note == -2) {
        if (c->note >= 0 && !c->released)
            key_off(p, c);
        else
            warn(p, channel, "key off without note");
    } else if (cell->note >= 0) {
        if (!c->instrument)
            warn(p, channel, "note without instrument");
        else if (portamento && c->note >= 0) {
            c->target = frequency(cell->note);
            c->note = cell->note;
        } else {
            if (portamento)
                warn(p, channel, "portamento without note");
            note_on(p, channel, cell->note);
        }
    }
}
static void approach(Channel *c, Integer step) {
    if (c->base < c->target)
        c->base = c->base + step < c->target ? c->base + step : c->target;
    else
        c->base = c->base - step > c->target ? c->base - step : c->target;
}
static void effect_zero(Playback *p, int k, int *delay) {
    Channel *c = &p->channels[k];
    const Effect *e = &c->effect;
    int a = e->argument;
    const Song *song = p->song;
    if (!strcmp(e->name, "3")) {
        if (a > 0)
            c->portamento = a;
    } else if (!strcmp(e->name, "4")) {
        if (e->x > 0)
            c->vibrato_speed = e->x;
        if (e->y > 0)
            c->vibrato_depth = e->y;
    } else if (!strcmp(e->name, "7")) {
        if (e->x > 0)
            c->tremolo_speed = e->x;
        if (e->y > 0)
            c->tremolo_depth = e->y;
    } else if (!strcmp(e->name, "C"))
        c->volume = a < 15 ? a : 15;
    else if (!strcmp(e->name, "E1"))
        c->base = clamp(c->base + 10 * a, 1000, 50 * song->rate);
    else if (!strcmp(e->name, "E2"))
        c->base = clamp(c->base - 10 * a, 1000, 50 * song->rate);
    else if (!strcmp(e->name, "EA"))
        c->volume = clamp(c->volume + a, 0, 15);
    else if (!strcmp(e->name, "EB"))
        c->volume = clamp(c->volume - a, 0, 15);
    else if (!strcmp(e->name, "EE"))
        *delay = a;
    else if (!strcmp(e->name, "F")) {
        if (a >= 1 && a <= 31)
            p->speed = a;
        else if (a >= 32)
            p->tempo = a;
    } else if (!strcmp(e->name, "P"))
        c->detune = a - 128;
    else if (!strcmp(e->name, "Q") || !strcmp(e->name, "R")) {
        if (c->note < 0)
            warn(p, k, "slide without note");
        else {
            c->note = !strcmp(e->name, "Q") ? (int)clamp(c->note + e->y, 12, 95)
                                            : (int)clamp(c->note - e->y, 12, 95);
            c->target = frequency(c->note);
            c->slide = 2 * e->x + 1;
        }
    } else if (!strcmp(e->name, "V")) {
        if (c->instrument && ((song->instruments[c->instrument].wave == PULSE && a <= 3) ||
                              (song->instruments[c->instrument].wave == NOISE && a <= 1)))
            c->mode = a;
        else
            warn(p, k, format("invalid mode %s", hexadecimal(a, 2)));
    }
}
static int row_start(Playback *p, const Cell *cells) {
    int delay = 0;
    for (int k = 0; k < 4; ++k) {
        Channel *c = &p->channels[k];
        c->effect = cells[k].effect;
        c->slide = 0;
        for (int i = 0; i < 25; ++i)
            if (!strcmp(c->effect.name, effect_order[i]))
                ++p->effects[i];
        if (strcmp(c->effect.name, "ED") || c->effect.argument < 1)
            content(p, k, &cells[k], !strcmp(c->effect.name, "3") || !strcmp(c->effect.name, "5"));
        effect_zero(p, k, &delay);
    }
    int count = p->speed * (1 + delay);
    for (int k = 0; k < 4; ++k) {
        Effect e = p->channels[k].effect;
        if (!strcmp(e.name, "EC") && e.argument >= count)
            warn(p, k, "cut beyond row");
        if (!strcmp(e.name, "ED") && e.argument >= count)
            warn(p, k, "delay beyond row");
    }
    return count;
}
static void process_tick(Playback *p, const Cell *cells, int tick) {
    const Song *song = p->song;
    for (int k = 0; k < 4; ++k) {
        Channel *c = &p->channels[k];
        const Effect *e = &c->effect;
        if (c->note >= 0 && c->age >= 1) {
            int sweep = song->instruments[c->instrument].sweep;
            if (sweep)
                c->base = clamp(c->base + 10 * sweep, 1000, 50 * song->rate);
        }
        if (tick >= 1) {
            if (!strcmp(e->name, "1"))
                c->base = clamp(c->base + 10 * e->argument, 1000, 50 * song->rate);
            else if (!strcmp(e->name, "2"))
                c->base = clamp(c->base - 10 * e->argument, 1000, 50 * song->rate);
            else if (!strcmp(e->name, "3"))
                approach(c, 10 * c->portamento);
            else if (!strcmp(e->name, "5")) {
                approach(c, 10 * c->portamento);
                c->volume = clamp(c->volume + e->x - e->y, 0, 15);
            } else if (!strcmp(e->name, "6") || !strcmp(e->name, "A"))
                c->volume = clamp(c->volume + e->x - e->y, 0, 15);
            else if ((!strcmp(e->name, "Q") || !strcmp(e->name, "R")) && c->slide)
                approach(c, 10 * c->slide);
        }
        if (!strcmp(e->name, "ED") && e->argument >= 1 && tick == e->argument)
            content(p, k, &cells[k], false);
        if (!strcmp(e->name, "E9") && e->argument >= 1 && tick >= 1 && tick % e->argument == 0 &&
            c->note >= 0) {
            c->phase = c->age = 0;
            c->released = false;
            ++p->channel_stats[k].retriggers;
        }
        if (!strcmp(e->name, "EC") && tick == e->argument && c->note >= 0) {
            c->note = -1;
            end_record(p, c, "cut");
            ++p->channel_stats[k].cuts;
        }
        compute_output(song, c, tick);
        if (c->sounding) {
            ++p->channel_stats[k].active;
            if (c->amplitude > 0)
                ++p->channel_stats[k].audible;
            ++p->instrument_ticks[c->instrument];
        }
    }
}
static char *channel_line(const Channel *c) {
    return c->note < 0 ? format("--- --       - - %s %s", hexadecimal(c->volume, 1), c->effect.text)
                       : format("%s %s %s %s %s %s", note_name(c->note), hexadecimal(c->instrument, 2),
                                aligned(c->output_frequency, 7), hexadecimal(c->env, 1),
                                hexadecimal(c->output_volume, 1), c->effect.text);
}
static char *tick_line(const Channel *c) {
    return c->sounding ? format("%s %s %s%s", aligned(c->output_frequency, 7), aligned(c->increment, 5),
                                hexadecimal(c->env, 1), hexadecimal(c->output_volume, 1))
                       : "      -     - --";
}
static void run(Playback *p) {
    const Song *song = p->song;
    for (;;) {
        Integer start = (Integer)p->audio.count;
        if (p->first[p->position][p->row] < 0)
            p->first[p->position][p->row] = start;
        ++p->played[p->position][p->row];
        const Cell *cells = song->patterns[song->order[p->position]]->rows[p->row];
        int count = row_start(p, cells), spt = samples_per_tick(song, p->tempo);
        RowRecord record = {p->position, song->order[p->position], p->row, start, p->speed, p->tempo, {0}};
        bool limited = false;
        for (int tick = 0; tick < count; ++tick) {
            process_tick(p, cells, tick);
            if (!tick) {
                for (int k = 0; k < 4; ++k)
                    record.notes[k] = p->channels[k].note;
                line_add(&p->logs, "%s %s %s %s %s %s | %s | %s | %s | %s", hexadecimal(p->position, 2),
                         hexadecimal(song->order[p->position], 2), hexadecimal(p->row, 2), aligned(start, 7),
                         aligned(p->speed, 2), aligned(p->tempo, 3), channel_line(&p->channels[0]),
                         channel_line(&p->channels[1]), channel_line(&p->channels[2]),
                         channel_line(&p->channels[3]));
            }
            if (p->params.traces[p->position][p->row])
                line_add(&p->logs, "  tick %s %s | %s | %s | %s | %s", aligned(tick, 3),
                         aligned((Integer)p->audio.count, 7), tick_line(&p->channels[0]),
                         tick_line(&p->channels[1]), tick_line(&p->channels[2]), tick_line(&p->channels[3]));
            int remaining = p->params.maximum - (int)p->audio.count;
            generate(song, p->channels, spt < remaining ? spt : remaining, p->params.muted, &p->audio);
            ++p->ticks;
            for (int k = 0; k < 4; ++k) {
                Channel *c = &p->channels[k];
                if (c->note >= 0)
                    ++c->age;
                if (!strcmp(c->effect.name, "4") || !strcmp(c->effect.name, "6"))
                    c->vibrato_position = (c->vibrato_position + c->vibrato_speed) % 64;
                if (!strcmp(c->effect.name, "7"))
                    c->tremolo_position = (c->tremolo_position + c->tremolo_speed) % 64;
            }
            if ((int)p->audio.count == p->params.maximum) {
                p->end = "limit";
                limited = true;
                break;
            }
        }
        grow((void **)&p->rows, &p->row_cap, p->row_count + 1, sizeof *p->rows);
        p->rows[p->row_count++] = record;
        if (limited)
            break;
        NextRow next = next_row(song, p->position, p->row);
        if (next.stop) {
            p->end = format("stop order=%s row=%s", hexadecimal(p->position, 2), hexadecimal(p->row, 2));
            break;
        }
        if (next.position >= song->order_count) {
            p->end = "finished";
            break;
        }
        if (p->played[next.position][next.row] >= p->params.loops) {
            p->loop_start = p->first[next.position][next.row];
            p->end = format("loop order=%s row=%s", hexadecimal(next.position, 2), hexadecimal(next.row, 2));
            break;
        }
        p->position = next.position;
        p->row = next.row;
    }
    for (int k = 0; k < 4; ++k)
        end_record(p, &p->channels[k], "end");
    if ((!strcmp(p->end, "limit") || !strncmp(p->end, "loop ", 5)) && p->params.fade > 0)
        fade(&p->audio, p->params.fade);
}
static Lines note_lines(const Playback *p) {
    Lines out = {0};
    for (size_t i = 0; i < p->note_count; ++i) {
        const NoteRecord *r = &p->notes[i];
        Integer peak = 0, cycles = 0;
        const Integer *lane = p->audio.lanes[r->channel];
        for (Integer s = r->start; s < r->start + r->length; ++s) {
            Integer value = magnitude(lane[s]);
            if (value > peak)
                peak = value;
            if (s > r->start && lane[s - 1] < 0 && lane[s] >= 0)
                ++cycles;
        }
        line_add(
            &out, "%s ch=%d at=%s:%s ins=%s note=%s start=%s length=%s release=%s end=%s peak=%s cycles=%s",
            aligned((Integer)i + 1, 4), r->channel + 1, hexadecimal(r->position, 2), hexadecimal(r->row, 2),
            hexadecimal(r->instrument, 2), note_name(r->note), decimal(r->start), decimal(r->length),
            r->release < 0 ? "-" : decimal(r->release), r->end, decimal(peak), decimal(cycles));
    }
    return out;
}
static Lines roll_lines(const Playback *p) {
    int first = p->params.roll_start < (int)p->row_count ? p->params.roll_start : (int)p->row_count,
        end = p->params.roll_start + p->params.roll_rows;
    if (end > (int)p->row_count)
        end = (int)p->row_count;
    int count = end - first;
    bool pitches[96] = {0};
    int pitch_count = 0;
    for (int i = first; i < end; ++i)
        for (int k = 0; k < 4; ++k) {
            int note = p->rows[i].notes[k];
            if (note >= 0 && !pitches[note]) {
                pitches[note] = true;
                ++pitch_count;
            }
        }
    Lines out = {0};
    line_add(&out, "ROLL start=%d rows=%d pitches=%d", p->params.roll_start, count, pitch_count);
    for (int note = 95; note >= 12; --note)
        if (pitches[note]) {
            Text marks = {0};
            for (int i = first; i < end; ++i) {
                int channel = -1, number = 0;
                for (int k = 0; k < 4; ++k)
                    if (p->rows[i].notes[k] == note) {
                        channel = k;
                        ++number;
                    }
                text_add(&marks, "%c", number == 0 ? ' ' : number == 1 ? '1' + channel : '*');
            }
            line_add(&out, "%s |%s|", note_name(note), marks.data ? marks.data : "");
        }
    Text axis = {0};
    text_add(&axis, "    +");
    for (int i = 0; i < count; ++i)
        text_add(&axis, "%c", i % 16 == 0 ? '+' : '-');
    text_add(&axis, "+");
    line_add(&out, "%s", axis.data);
    return out;
}
static char *note_range(const Playback *p, int channel, int instrument) {
    int lo = 96, hi = -1;
    for (size_t i = 0; i < p->note_count; ++i) {
        const NoteRecord *r = &p->notes[i];
        if ((channel >= 0 && r->channel != channel) || (instrument >= 0 && r->instrument != instrument))
            continue;
        if (r->note < lo)
            lo = r->note;
        if (r->note > hi)
            hi = r->note;
    }
    return hi < 0 ? "none" : format("%s..%s", note_name(lo), note_name(hi));
}
static Lines stats_lines(const Playback *p) {
    const Song *song = p->song;
    SampleStats s = sample_stats(p->audio.samples, p->audio.count);
    Integer n = (Integer)p->audio.count;
    Lines out = {0};
    line_add(&out, "title=%s", song->title);
    line_add(&out, "rate=%d", song->rate);
    line_add(&out, "samples=%s", decimal(n));
    line_add(&out, "duration_ms=%s", decimal(n * 1000 / song->rate));
    line_add(&out, "end=%s", p->end);
    line_add(&out, "loop_start=%s", p->loop_start < 0 ? "-" : decimal(p->loop_start));
    line_add(&out, "loop_length=%s", p->loop_start < 0 ? "-" : decimal(n - p->loop_start));
    line_add(&out, "rows=%zu", p->row_count);
    line_add(&out, "ticks=%s", decimal(p->ticks));
    line_add(&out, "clipped=%s", decimal(p->audio.clipped));
    line_add(&out, "peak=%s", decimal(s.peak));
    line_add(&out, "min=%d", s.minimum);
    line_add(&out, "max=%d", s.maximum);
    line_add(&out, "rms=%s", decimal(s.rms));
    line_add(&out, "zero_crossings=%s", decimal(s.crossings));
    line_add(&out, "adler32=%s", hexadecimal(adler32(p->audio.samples, p->audio.count), 8));
    Text path = {0};
    text_add(&path, "path");
    int previous = -1;
    for (size_t i = 0; i < p->row_count; ++i) {
        RowRecord r = p->rows[i];
        if (r.position != previous) {
            text_add(&path, " %s", hexadecimal(r.position, 2));
            previous = r.position;
        }
    }
    line_add(&out, "%s", path.data);
    int speed = -1, tempo = -1;
    for (size_t i = 0; i < p->row_count; ++i) {
        RowRecord r = p->rows[i];
        if (r.speed != speed || r.tempo != tempo) {
            line_add(&out, "timing sample=%s order=%s row=%s speed=%d tempo=%d", decimal(r.start),
                     hexadecimal(r.position, 2), hexadecimal(r.row, 2), r.speed, r.tempo);
            speed = r.speed;
            tempo = r.tempo;
        }
    }
    for (int k = 0; k < 4; ++k) {
        Integer peak = 0, squares = 0;
        for (size_t i = 0; i < p->audio.count; ++i) {
            Integer value = p->audio.lanes[k][i], absolute = magnitude(value);
            if (absolute > peak)
                peak = absolute;
            squares += value * value;
        }
        ChannelStats c = p->channel_stats[k];
        line_add(&out, "channel %d notes=%s retriggers=%s cuts=%s active=%s audible=%s peak=%s rms=%s", k + 1,
                 decimal(c.notes), decimal(c.retriggers), decimal(c.cuts), decimal(c.active),
                 decimal(c.audible), decimal(peak), decimal(integer_sqrt(squares / n)));
    }
    Integer instrument_counts[256] = {0}, instrument_lengths[256] = {0}, note_counts[96] = {0};
    for (size_t i = 0; i < p->note_count; ++i) {
        NoteRecord r = p->notes[i];
        ++instrument_counts[r.instrument];
        instrument_lengths[r.instrument] += r.length;
        ++note_counts[r.note];
    }
    for (int number = 1; number < 256; ++number)
        if (song->instruments[number].defined) {
            const Instrument *i = &song->instruments[number];
            line_add(&out, "instrument %s %s %s notes=%s ticks=%s range=%s average=%s",
                     hexadecimal(number, 2), i->name, wave_name(i->wave), decimal(instrument_counts[number]),
                     decimal(p->instrument_ticks[number]), note_range(p, -1, number),
                     instrument_counts[number]
                         ? decimal(instrument_lengths[number] / instrument_counts[number])
                         : "-");
        }
    Integer order_counts[256] = {0};
    for (int i = 0; i < song->order_count; ++i)
        ++order_counts[song->order[i]];
    for (int number = 0; number < 256; ++number)
        if (song->patterns[number]) {
            int rows = 0, notes = 0;
            for (int row = 0; row < 64; ++row) {
                bool any = false;
                for (int k = 0; k < 4; ++k) {
                    const Cell *cell = &song->patterns[number]->rows[row][k];
                    if (!cell_empty(cell))
                        any = true;
                    if (cell->note != -1)
                        ++notes;
                }
                if (any)
                    ++rows;
            }
            line_add(&out, "pattern %s rows=%d notes=%d orders=%s", hexadecimal(number, 2), rows, notes,
                     decimal(order_counts[number]));
        }
    bool reached[64][64] = {{0}};
    reachable(song, reached);
    Integer position_counts[64] = {0};
    for (int position = 0; position < song->order_count; ++position) {
        Integer first = -1;
        int dead = 0;
        for (int row = 0; row < 64; ++row) {
            position_counts[position] += p->played[position][row];
            if (p->first[position][row] >= 0 && (first < 0 || p->first[position][row] < first))
                first = p->first[position][row];
            if (!reached[position][row]) {
                bool note = false;
                for (int k = 0; k < 4; ++k)
                    if (song->patterns[song->order[position]]->rows[row][k].note != -1)
                        note = true;
                if (note)
                    ++dead;
            }
        }
        line_add(&out, "order %s pattern=%s rows=%s first=%s dead=%d", hexadecimal(position, 2),
                 hexadecimal(song->order[position], 2), decimal(position_counts[position]),
                 first < 0 ? "-" : decimal(first), dead);
    }
    for (int note = 12; note < 96; ++note)
        if (note_counts[note])
            line_add(&out, "note %s count=%s", note_name(note), decimal(note_counts[note]));
    Text effects = {0};
    text_add(&effects, "effects");
    bool any_effect = false;
    for (int i = 0; i < 25; ++i)
        if (p->effects[i]) {
            text_add(&effects, " %s=%s", effect_order[i], decimal(p->effects[i]));
            any_effect = true;
        }
    if (!any_effect)
        text_add(&effects, " none");
    line_add(&out, "%s", effects.data);
    Text unused_instruments = {0}, unused_patterns = {0}, unreached_orders = {0};
    for (int i = 1; i < 256; ++i)
        if (song->instruments[i].defined && !instrument_counts[i])
            text_add(&unused_instruments, "%s%s", unused_instruments.len ? " " : "", hexadecimal(i, 2));
    for (int i = 0; i < 256; ++i)
        if (song->patterns[i] && !order_counts[i])
            text_add(&unused_patterns, "%s%s", unused_patterns.len ? " " : "", hexadecimal(i, 2));
    for (int i = 0; i < song->order_count; ++i)
        if (!position_counts[i])
            text_add(&unreached_orders, "%s%s", unreached_orders.len ? " " : "", hexadecimal(i, 2));
    line_add(&out, "unused_instruments=%s", unused_instruments.len ? unused_instruments.data : "none");
    line_add(&out, "unused_patterns=%s", unused_patterns.len ? unused_patterns.data : "none");
    line_add(&out, "unreached_orders=%s", unreached_orders.len ? unreached_orders.data : "none");
    Integer pitch_classes[12] = {0};
    for (size_t i = 0; i < p->note_count; ++i) {
        NoteRecord r = p->notes[i];
        if (song->instruments[r.instrument].wave != NOISE)
            pitch_classes[r.note % 12] += r.length;
    }
    const char *tonics[12] = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"};
    Text pitch_line = {0};
    text_add(&pitch_line, "pitch_classes");
    for (int j = 0; j < 12; ++j)
        text_add(&pitch_line, " %s=%s", tonics[j], decimal(pitch_classes[j]));
    line_add(&out, "%s", pitch_line.data);
    const Integer major[12] = {64, 22, 35, 23, 44, 41, 25, 52, 24, 37, 23, 29},
                  minor[12] = {64, 27, 35, 54, 27, 35, 25, 48, 40, 27, 34, 32};
    Integer scores[24] = {0};
    int keys[24];
    for (int key = 0; key < 24; ++key) {
        keys[key] = key;
        for (int j = 0; j < 12; ++j)
            scores[key] += (key < 12 ? major : minor)[modulo(j - key % 12, 12)] * pitch_classes[j];
    }
    for (int i = 1; i < 24; ++i) {
        int value = keys[i], j = i;
        while (j > 0 && scores[keys[j - 1]] < scores[value]) {
            keys[j] = keys[j - 1];
            --j;
        }
        keys[j] = value;
    }
    line_add(&out, "key=%s %s score=%s runner_up=%s %s score=%s", tonics[keys[0] % 12],
             keys[0] < 12 ? "major" : "minor", decimal(scores[keys[0]]), tonics[keys[1] % 12],
             keys[1] < 12 ? "major" : "minor", decimal(scores[keys[1]]));
    for (int k = 0; k < 4; ++k) {
        Integer counts[256] = {0};
        for (size_t i = 0; i < p->note_count; ++i)
            if (p->notes[i].channel == k)
                ++counts[p->notes[i].instrument];
        Text usage = {0};
        text_add(&usage, "usage ch%d range=%s", k + 1, note_range(p, k, -1));
        for (int i = 1; i < 256; ++i)
            if (song->instruments[i].defined)
                text_add(&usage, " %s=%s", hexadecimal(i, 2), decimal(counts[i]));
        line_add(&out, "%s", usage.data);
    }
    extend(&out, p->warnings);
    return out;
}
static int plot_row(Integer value, Integer lo, Integer hi, int height) {
    return (int)floor_div(2 * (hi - value) * (height - 1) + (hi - lo), 2 * (hi - lo));
}
static Lines waveform_plot(const Integer *values, int length, Integer lo, Integer hi, Integer mid, int width,
                           int height) {
    int middle = plot_row(mid, lo, hi, height), *top = allocate(width, sizeof *top),
        *bottom = allocate(width, sizeof *bottom);
    for (int col = 0; col < width; ++col) {
        int first = col * length / width, end = (col + 1) * length / width;
        Integer low = values[first], high = low;
        for (int i = first; i < end; ++i) {
            if (values[i] < low)
                low = values[i];
            if (values[i] > high)
                high = values[i];
        }
        top[col] = plot_row(high, lo, hi, height);
        bottom[col] = plot_row(low, lo, hi, height);
    }
    Lines out = {0};
    for (int row = 0; row < height; ++row) {
        char *label = row == 0            ? aligned(hi, 5)
                      : row == middle     ? aligned(mid, 5)
                      : row == height - 1 ? aligned(lo, 5)
                                          : "     ";
        Text marks = {0};
        for (int col = 0; col < width; ++col)
            text_add(&marks, "%c", top[col] <= row && row <= bottom[col] ? '#' : row == middle ? '-' : ' ');
        line_add(&out, "%s |%s|", label, marks.data);
    }
    free(top);
    free(bottom);
    return out;
}
static Lines axes(const Song *song, const Params *p) {
    Text first = {0};
    text_add(&first, "      +");
    for (int c = 0; c < p->width; ++c)
        text_add(&first, "%c", c % 10 == 0 ? '+' : '-');
    text_add(&first, "+");
    char *second = allocate((size_t)p->width + 64, 1);
    memset(second, ' ', (size_t)p->width + 63);
    memcpy(second, "    ms", 6);
    size_t end = 6;
    for (int c = 0; c < p->width; c += 10) {
        char *text = decimal(((Integer)p->start + (Integer)c * p->length / p->width) * 1000 / song->rate);
        size_t position = (size_t)7 + c;
        memcpy(second + position, text, strlen(text));
        end = position + strlen(text);
    }
    second[end] = 0;
    Lines out = {0};
    line_add(&out, "%s", first.data);
    line_add(&out, "%s", second);
    return out;
}
static Lines waveform_lines(const Playback *p) {
    const Params *params = &p->params;
    Lines out = {0};
    line_add(&out, "MIX start=%d length=%d width=%d height=%d", params->start, params->length, params->width,
             params->height);
    Integer *mix = allocate(params->length, sizeof *mix);
    for (int i = 0; i < params->length; ++i)
        mix[i] = p->audio.samples[params->start + i];
    extend(&out, waveform_plot(mix, params->length, 0, 255, 128, params->width, params->height));
    extend(&out, axes(p->song, params));
    for (int k = 0; k < 4; ++k) {
        line_add(&out, "CHANNEL %d", k + 1);
        extend(&out, waveform_plot(p->audio.lanes[k] + params->start, params->length, -3375, 3375, 0,
                                   params->width, params->scope));
    }
    extend(&out, axes(p->song, params));
    free(mix);
    return out;
}
static Lines preview_lines(const Song *song, const Params *p) {
    Lines out = {0};
    int spt = samples_per_tick(song, song->tempo);
    for (int number = 1; number < 256; ++number)
        if (song->instruments[number].defined) {
            const Instrument *i = &song->instruments[number];
            Channel channels[4];
            for (int k = 0; k < 4; ++k)
                channels[k] = channel_create();
            Channel *c = &channels[0];
            c->instrument = number;
            c->mode = i->mode;
            c->note = p->preview_note;
            c->base = c->target = frequency(c->note);
            Audio audio = audio_create((size_t)p->preview_ticks * spt);
            Text env = {0}, frequencies = {0};
            for (int tick = 0; tick < p->preview_ticks; ++tick) {
                if (tick == p->preview_release) {
                    c->released = true;
                    c->release_age = tick;
                    c->release_value = c->env;
                }
                if (tick >= 1 && i->sweep)
                    c->base = clamp(c->base + 10 * i->sweep, 1000, 50 * song->rate);
                c->age = tick;
                compute_output(song, c, tick);
                text_add(&env, "%s", hexadecimal(c->env, 1));
                text_add(&frequencies, "%s%s", tick ? " " : "", decimal(c->output_frequency));
                bool muted[4] = {false, false, false, false};
                generate(song, channels, spt, muted, &audio);
            }
            SampleStats stats = sample_stats(audio.samples, audio.count);
            line_add(&out, "instrument %s %s wave=%s samples=%zu peak=%s rms=%s adler32=%s",
                     hexadecimal(number, 2), i->name, wave_name(i->wave), audio.count, decimal(stats.peak),
                     decimal(stats.rms), hexadecimal(adler32(audio.samples, audio.count), 8));
            line_add(&out, "  env %s", env.data);
            line_add(&out, "  freq %s", frequencies.data);
            free(audio.samples);
            for (int k = 0; k < 4; ++k)
                free(audio.lanes[k]);
        }
    return out;
}
int main(void) {
    Song *song = read_song();
    Params params = read_params();
    Playback *p = playback_create(song, params);
    run(p);
    write_lines("samples.txt", sample_dump(p->audio.samples, p->audio.count));
    write_lines("channel_log.txt", p->logs);
    write_lines("notes.txt", note_lines(p));
    write_lines("roll.txt", roll_lines(p));
    write_lines("stats.txt", stats_lines(p));
    write_lines("waveform.txt", waveform_lines(p));
    write_lines("instruments.txt", preview_lines(song, &params));
    return 0;
}
