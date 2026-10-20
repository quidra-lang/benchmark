#include <math.h>
#include <setjmp.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { int letter, alteration; } Pitch;
typedef struct { Pitch pitch; int octave; } Note;
typedef enum { PERFECT, MAJOR, MINOR, AUGMENTED, DIMINISHED, DOUBLE_AUGMENTED, DOUBLE_DIMINISHED } Quality;
typedef struct { Quality quality; int number; } Interval;
typedef struct { int letters, semitones; } Tone;
typedef struct { Interval interval; bool down; int semitones; } IntervalResult;
typedef struct { char text[32]; } Text;
typedef struct { const char *name; int count; Tone tones[7]; } Scale;
typedef struct {
    const char *name, *suffix, *numeral_suffix;
    bool lower;
    int count;
    Tone tones[5];
} Chord;
typedef struct { const char *name; int scale, offset; } Mode;
typedef struct { Pitch tonic; int mode, fifths; Pitch scale[7]; } Key;
typedef struct { int alteration, degree, quality; } Numeral;
typedef struct { Pitch root; int quality; } Symbol;

static const int natural[] = {0, 2, 4, 5, 7, 9, 11};
static const char letter_names[] = "CDEFGAB";
static const int fifth_values[] = {0, 2, 4, -1, 1, 3, 5};
static const char *accidentals[] = {"bb", "b", "", "#", "x"};
static const char *quality_names[] = {"P", "M", "m", "A", "d", "AA", "dd"};
static const char *sharp_names[] = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"};
static const char *flat_names[] = {"C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"};
static const char *roman_upper[] = {"I", "II", "III", "IV", "V", "VI", "VII"};
static const char *roman_lower[] = {"i", "ii", "iii", "iv", "v", "vi", "vii"};
static const Scale scales[] = {
    {"major", 7, {{0,0},{1,2},{2,4},{3,5},{4,7},{5,9},{6,11}}},
    {"natural_minor", 7, {{0,0},{1,2},{2,3},{3,5},{4,7},{5,8},{6,10}}},
    {"harmonic_minor", 7, {{0,0},{1,2},{2,3},{3,5},{4,7},{5,8},{6,11}}},
    {"melodic_minor", 7, {{0,0},{1,2},{2,3},{3,5},{4,7},{5,9},{6,11}}},
    {"ionian", 7, {{0,0},{1,2},{2,4},{3,5},{4,7},{5,9},{6,11}}},
    {"dorian", 7, {{0,0},{1,2},{2,3},{3,5},{4,7},{5,9},{6,10}}},
    {"phrygian", 7, {{0,0},{1,1},{2,3},{3,5},{4,7},{5,8},{6,10}}},
    {"lydian", 7, {{0,0},{1,2},{2,4},{3,6},{4,7},{5,9},{6,11}}},
    {"mixolydian", 7, {{0,0},{1,2},{2,4},{3,5},{4,7},{5,9},{6,10}}},
    {"aeolian", 7, {{0,0},{1,2},{2,3},{3,5},{4,7},{5,8},{6,10}}},
    {"locrian", 7, {{0,0},{1,1},{2,3},{3,5},{4,6},{5,8},{6,10}}},
    {"major_pentatonic", 5, {{0,0},{1,2},{2,4},{4,7},{5,9}}},
    {"minor_pentatonic", 5, {{0,0},{2,3},{3,5},{4,7},{6,10}}},
    {"blues", 6, {{0,0},{2,3},{3,5},{3,6},{4,7},{6,10}}},
    {"whole_tone", 6, {{0,0},{1,2},{2,4},{3,6},{4,8},{5,10}}}
};
static const Chord chords[] = {
    {"maj", "", "", false, 3, {{0,0},{2,4},{4,7}}},
    {"min", "m", "", true, 3, {{0,0},{2,3},{4,7}}},
    {"dim", "dim", "o", true, 3, {{0,0},{2,3},{4,6}}},
    {"aug", "aug", "+", false, 3, {{0,0},{2,4},{4,8}}},
    {"sus2", "sus2", "sus2", false, 3, {{0,0},{1,2},{4,7}}},
    {"sus4", "sus4", "sus4", false, 3, {{0,0},{3,5},{4,7}}},
    {"6", "6", "6", false, 4, {{0,0},{2,4},{4,7},{5,9}}},
    {"m6", "m6", "6", true, 4, {{0,0},{2,3},{4,7},{5,9}}},
    {"7", "7", "7", false, 4, {{0,0},{2,4},{4,7},{6,10}}},
    {"maj7", "maj7", "maj7", false, 4, {{0,0},{2,4},{4,7},{6,11}}},
    {"m7", "m7", "7", true, 4, {{0,0},{2,3},{4,7},{6,10}}},
    {"mMaj7", "mMaj7", "maj7", true, 4, {{0,0},{2,3},{4,7},{6,11}}},
    {"m7b5", "m7b5", "h7", true, 4, {{0,0},{2,3},{4,6},{6,10}}},
    {"dim7", "dim7", "o7", true, 4, {{0,0},{2,3},{4,6},{6,9}}},
    {"9", "9", "9", false, 5, {{0,0},{2,4},{4,7},{6,10},{8,14}}},
    {"add9", "add9", "add9", false, 4, {{0,0},{2,4},{4,7},{8,14}}}
};
static const Mode modes[] = {
    {"major",0,0}, {"minor",1,-3}, {"ionian",4,0}, {"dorian",5,-2},
    {"phrygian",6,-4}, {"lydian",7,1}, {"mixolydian",8,-1}, {"aeolian",9,-3}, {"locrian",10,-5}
};

static jmp_buf command_error;
static char response[4096];
static size_t response_length;
static int tuning = 44000;

static void out(const char *format, ...) {
    va_list args;
    va_start(args, format);
    response_length += (size_t)vsnprintf(response + response_length, sizeof response - response_length, format, args);
    va_end(args);
}
static _Noreturn void fail(const char *format, ...) {
    response_length = 0;
    out("ERROR ");
    va_list args;
    va_start(args, format);
    response_length += (size_t)vsnprintf(response + response_length, sizeof response - response_length, format, args);
    va_end(args);
    out("\n");
    longjmp(command_error, 1);
}
static int mod(int value, int divisor) { int r = value % divisor; return r < 0 ? r + divisor : r; }
static int floor_div(int value, int divisor) { return (value - mod(value, divisor)) / divisor; }
static bool canonical(const char *text, int low, int high, int *value) {
    if (!*text || (text[0] == '0' && text[1])) return false;
    int n = 0;
    for (const char *p = text; *p; ++p) {
        if (*p < '0' || *p > '9' || n > (high - (*p - '0')) / 10) return false;
        n = n * 10 + *p - '0';
        if (n > high) return false;
    }
    if (n < low) return false;
    *value = n;
    return true;
}
static int pitch_prefix(const char *text, Pitch *pitch) {
    if (!text[0]) return 0;
    const char *letter = strchr(letter_names, text[0]);
    if (!letter) return 0;
    *pitch = (Pitch){(int)(letter - letter_names), 0};
    int end = 1;
    if (text[end] == 'b') {
        pitch->alteration = -1;
        if (text[++end] == 'b') { pitch->alteration = -2; ++end; }
    } else if (text[end] == '#') { pitch->alteration = 1; ++end; }
    else if (text[end] == 'x') { pitch->alteration = 2; ++end; }
    return end;
}
static Pitch read_pitch(const char *text) {
    Pitch pitch;
    int end = pitch_prefix(text, &pitch);
    if (!end || text[end]) fail("BAD PITCH %s", text);
    return pitch;
}
static int midi(Note note) { return 12 * (note.octave + 1) + natural[note.pitch.letter] + note.pitch.alteration; }
static int position(Note note) { return 7 * note.octave + note.pitch.letter; }
static int pitch_class(Pitch pitch) { return mod(natural[pitch.letter] + pitch.alteration, 12); }
static bool valid_note(Note note) { return note.octave >= -1 && note.octave <= 9 && midi(note) >= 0 && midi(note) <= 127; }
static Note read_note(const char *text) {
    Note note;
    int end = pitch_prefix(text, &note.pitch);
    if (!end) fail("BAD NOTE %s", text);
    const char *octave = text + end;
    if (!strcmp(octave, "-1")) note.octave = -1;
    else if (octave[0] >= '0' && octave[0] <= '9' && !octave[1]) note.octave = octave[0] - '0';
    else fail("BAD NOTE %s", text);
    if (!valid_note(note)) fail("BAD NOTE %s", text);
    return note;
}
static int read_number(const char *text) {
    int result;
    if (!canonical(text, 0, 127, &result)) fail("BAD NUMBER %s", text);
    return result;
}
static int read_frequency(const char *text, bool is_tuning) {
    int i = 0, whole = 0;
    while (text[i] >= '0' && text[i] <= '9') {
        if (i == 5) fail("BAD FREQUENCY %s", text);
        whole = whole * 10 + text[i++] - '0';
    }
    if (!i) fail("BAD FREQUENCY %s", text);
    int cents = whole * 100;
    if (text[i] == '.') {
        ++i;
        int start = i, fraction = 0;
        while (text[i] >= '0' && text[i] <= '9') {
            if (i - start == 2) fail("BAD FREQUENCY %s", text);
            fraction = fraction * 10 + text[i++] - '0';
        }
        if (i == start) fail("BAD FREQUENCY %s", text);
        cents += i - start == 1 ? fraction * 10 : fraction;
    }
    if (text[i] || cents == 0 || (is_tuning && (cents < 40000 || cents > 48000))) fail("BAD FREQUENCY %s", text);
    return cents;
}
static Text pitch_text(Pitch pitch) {
    Text result;
    snprintf(result.text, sizeof result.text, "%c%s", "CDEFGAB"[pitch.letter], accidentals[pitch.alteration + 2]);
    return result;
}
static Text note_text(Note note) {
    Text result;
    snprintf(result.text, sizeof result.text, "%s%d", pitch_text(note.pitch).text, note.octave);
    return result;
}
static Note make_note(Pitch pitch, int value) {
    return (Note){pitch, (value - natural[pitch.letter] - pitch.alteration) / 12 - 1};
}
static Text spelling(int value, bool flat) {
    Text result;
    snprintf(result.text, sizeof result.text, "%s%d", (flat ? flat_names : sharp_names)[value % 12], value / 12 - 1);
    return result;
}
static bool quality_delta(Quality quality, bool perfect, int *delta) {
    if (quality == PERFECT) { if (!perfect) return false; *delta = 0; }
    else if (quality == MAJOR || quality == MINOR) { if (perfect) return false; *delta = quality == MAJOR ? 0 : -1; }
    else if (quality == AUGMENTED || quality == DOUBLE_AUGMENTED) *delta = quality == AUGMENTED ? 1 : 2;
    else *delta = (quality == DIMINISHED ? -1 : -2) - !perfect;
    return true;
}
static bool perfect_type(int number) { int r = (number - 1) % 7; return r == 0 || r == 3 || r == 4; }
static Tone interval_tone(Interval interval) {
    int s = interval.number - 1, delta;
    quality_delta(interval.quality, perfect_type(interval.number), &delta);
    return (Tone){s, 12 * (s / 7) + natural[s % 7] + delta};
}
static Interval read_interval(const char *text) {
    for (int q = PERFECT; q <= DOUBLE_DIMINISHED; ++q) {
        size_t length = strlen(quality_names[q]);
        int number, delta;
        if (!strncmp(text, quality_names[q], length) && canonical(text + length, 1, 99, &number)
            && quality_delta((Quality)q, perfect_type(number), &delta)
            && !(number == 1 && (q == DIMINISHED || q == DOUBLE_DIMINISHED))) return (Interval){(Quality)q, number};
    }
    fail("BAD INTERVAL %s", text);
}
static Text interval_text(Interval interval) {
    Text result;
    snprintf(result.text, sizeof result.text, "%s%d", quality_names[interval.quality], interval.number);
    return result;
}
static Interval simple_interval(Interval interval) {
    while (interval.number > 8) interval.number -= 7;
    return interval;
}
static IntervalResult between(Note a, Note b) {
    int distance = position(b) - position(a), semitones = midi(b) - midi(a);
    bool down = distance < 0 || (distance == 0 && semitones < 0);
    if (down) { distance = -distance; semitones = -semitones; }
    int difference = semitones - 12 * (distance / 7) - natural[distance % 7];
    for (int q = PERFECT; q <= DOUBLE_DIMINISHED; ++q) {
        int delta;
        if (quality_delta((Quality)q, perfect_type(distance + 1), &delta) && delta == difference)
            return (IntervalResult){{(Quality)q, distance + 1}, down, semitones};
    }
    fail("UNNAMEABLE INTERVAL");
}
static Pitch raise_pitch(Pitch root, Tone tone) {
    int target = root.letter + tone.letters;
    int alteration = natural[root.letter] + root.alteration + tone.semitones - natural[target % 7] - 12 * (target / 7);
    if (alteration < -2 || alteration > 2) fail("CANNOT SPELL");
    return (Pitch){target % 7, alteration};
}
static void build(Pitch root, const Tone *tones, int count, Pitch *result) {
    for (int i = 0; i < count; ++i) result[i] = raise_pitch(root, tones[i]);
}
static int read_scale(const char *text) {
    for (int i = 0; i < 15; ++i) if (!strcmp(text, scales[i].name)) return i;
    fail("BAD SCALE %s", text);
}
static int read_quality(const char *text) {
    for (int i = 0; i < 16; ++i) if (!strcmp(text, chords[i].name)) return i;
    fail("BAD QUALITY %s", text);
}
static int read_mode(const char *text) {
    for (int i = 0; i < 9; ++i) if (!strcmp(text, modes[i].name)) return i;
    fail("BAD MODE %s", text);
}
static Key make_key(Pitch tonic, int mode) {
    Key key = {.tonic = tonic, .mode = mode, .fifths = fifth_values[tonic.letter] + 7 * tonic.alteration + modes[mode].offset};
    if (key.fifths < -7 || key.fifths > 7) fail("THEORETICAL KEY");
    build(tonic, scales[modes[mode].scale].tones, 7, key.scale);
    return key;
}
static Key read_key(char **words) {
    Pitch tonic = read_pitch(words[0]);
    int mode = read_mode(words[1]);
    return make_key(tonic, mode);
}
static Pitch fifth_pitch(int fifths) {
    static const int letters[] = {3, 0, 4, 1, 5, 2, 6};
    return (Pitch){letters[mod(fifths + 1, 7)], floor_div(fifths + 1, 7)};
}
static Numeral read_numeral(const char *text) {
    int start = text[0] == 'b' || text[0] == '#' ? 1 : 0;
    int end = start;
    while (text[end] && strchr("IViv", text[end])) ++end;
    for (int degree = 0; degree < 7; ++degree) {
        for (int q = 0; q < 16; ++q) {
            const char *part = (chords[q].lower ? roman_lower : roman_upper)[degree];
            if (end - start == (int)strlen(part) && !strncmp(text + start, part, (size_t)(end - start))
                && !strcmp(text + end, chords[q].numeral_suffix))
                return (Numeral){start ? (text[0] == 'b' ? -1 : 1) : 0, degree, q};
        }
    }
    fail("BAD NUMERAL %s", text);
}
static Symbol read_symbol(const char *text) {
    Pitch root;
    int end = pitch_prefix(text, &root);
    if (end) for (int i = 0; i < 16; ++i) if (!strcmp(text + end, chords[i].suffix)) return (Symbol){root, i};
    fail("BAD SYMBOL %s", text);
}
static Text symbol_text(Pitch root, int quality, const Pitch *bass) {
    Text result;
    snprintf(result.text, sizeof result.text, "%s%s", pitch_text(root).text, chords[quality].suffix);
    if (bass) {
        size_t length = strlen(result.text);
        snprintf(result.text + length, sizeof result.text - length, "/%s", pitch_text(*bass).text);
    }
    return result;
}
static Text roman_text(int degree, int quality) {
    Text result;
    snprintf(result.text, sizeof result.text, "%s%s", (chords[quality].lower ? roman_lower : roman_upper)[degree], chords[quality].numeral_suffix);
    return result;
}
static int degree_of(Key key, Pitch pitch) { return mod(pitch.letter - key.tonic.letter, 7); }
static Text degree_prefix(Key key, Pitch pitch) {
    int difference = pitch.alteration - key.scale[degree_of(key, pitch)].alteration;
    Text result = {{0}};
    for (int i = 0; i < abs(difference); ++i) result.text[i] = difference < 0 ? 'b' : '#';
    return result;
}
static Text degree_label(Key key, Pitch pitch) {
    Text result;
    snprintf(result.text, sizeof result.text, "%s%d", degree_prefix(key, pitch).text, degree_of(key, pitch) + 1);
    return result;
}
static unsigned key_set(Key key) {
    unsigned mask = 0;
    for (int i = 0; i < 7; ++i) mask |= 1u << pitch_class(key.scale[i]);
    return mask;
}
static void print_pitches(const Pitch *pitches, int count) {
    for (int i = 0; i < count; ++i) out(" %s", pitch_text(pitches[i]).text);
}

typedef enum {
    MIDI, NOTE, FREQ, TUNING, PITCH, INTERVAL, INVERT, TRANSPOSE, SCALE, CHORD, VOICE,
    IDENTIFY, MELODY, ENHARMONIC, KEYSIG, RELATIVE, CIRCLE, DIATONIC, PROGRESSION,
    ANALYZE, FINDKEY, DEGREE, SPELL, KEYDIST
} Command;
typedef struct { const char *name; int minimum, maximum; } CommandSpec;
static const CommandSpec commands[] = {
    {"MIDI",1,1}, {"NOTE",1,1}, {"FREQ",1,1}, {"TUNING",1,1}, {"PITCH",1,1},
    {"INTERVAL",2,2}, {"INVERT",1,1}, {"TRANSPOSE",3,3}, {"SCALE",2,2},
    {"CHORD",2,3}, {"VOICE",2,3}, {"IDENTIFY",2,15}, {"MELODY",2,15},
    {"ENHARMONIC",1,1}, {"KEYSIG",2,2}, {"RELATIVE",2,2}, {"CIRCLE",1,1},
    {"DIATONIC",2,2}, {"PROGRESSION",3,15}, {"ANALYZE",3,15}, {"FINDKEY",1,15},
    {"DEGREE",3,3}, {"SPELL",3,3}, {"KEYDIST",4,4}
};

static void execute(int word_count, char **words) {
    int command = -1;
    for (int i = 0; i < 24; ++i) if (!strcmp(words[0], commands[i].name)) { command = i; break; }
    if (command < 0) fail("UNKNOWN COMMAND %s", words[0]);
    int count = word_count - 1;
    char **a = words + 1;
    if (count < commands[command].minimum || count > commands[command].maximum) fail("ARGUMENT COUNT");
    switch ((Command)command) {
    case MIDI: case FREQ: case ENHARMONIC: {
        Note note = read_note(a[0]);
        int value = midi(note);
        if (command == MIDI) out("MIDI %s %d\n", a[0], value);
        else if (command == FREQ) {
            int cents = (int)floor(tuning * exp2((value - 69) / 12.0) + 0.5);
            out("FREQ %s %d.%02d\n", a[0], cents / 100, cents % 100);
        } else {
            out("ENHARMONIC %s", a[0]);
            for (int octave = -1; octave <= 9; ++octave) for (int letter = 0; letter < 7; ++letter) {
                int alteration = value - 12 * (octave + 1) - natural[letter];
                if (alteration >= -2 && alteration <= 2) out(" %s", note_text((Note){{letter, alteration}, octave}).text);
            }
            out("\n");
        }
        break;
    }
    case NOTE: {
        int value = read_number(a[0]);
        out("NOTE %d %s %s\n", value, spelling(value, false).text, spelling(value, true).text);
        break;
    }
    case TUNING: case PITCH: {
        int frequency = read_frequency(a[0], command == TUNING);
        if (command == TUNING) {
            tuning = frequency;
            out("TUNING %d.%02d\n", frequency / 100, frequency % 100);
        } else {
            double x = 69 + 12 * log2((double)frequency / tuning);
            int value = (int)floor(x + 0.5);
            if (value < 0 || value > 127) fail("OUT OF RANGE");
            int cents = (int)floor(100 * (x - value) + 0.5);
            out("PITCH %d.%02d %s %+d\n", frequency / 100, frequency % 100, spelling(value, false).text, cents);
        }
        break;
    }
    case INTERVAL: {
        Note first = read_note(a[0]);
        Note second = read_note(a[1]);
        IntervalResult result = between(first, second);
        Interval simple = simple_interval(result.interval);
        const char *class = "dissonant";
        if (simple.quality == PERFECT && (simple.number == 1 || simple.number == 5 || simple.number == 8)) class = "perfect";
        else if ((simple.quality == MAJOR || simple.quality == MINOR) && (simple.number == 3 || simple.number == 6)) class = "imperfect";
        out("INTERVAL %s %s %s %s semitones=%d simple=%s class=%s\n", a[0], a[1], interval_text(result.interval).text,
            result.down ? "down" : "up", result.semitones, interval_text(simple).text, class);
        break;
    }
    case INVERT: {
        Interval simple = simple_interval(read_interval(a[0]));
        static const Quality inversions[] = {PERFECT, MINOR, MAJOR, DIMINISHED, AUGMENTED, DOUBLE_DIMINISHED, DOUBLE_AUGMENTED};
        Interval inverse = {inversions[simple.quality], 9 - simple.number};
        if (inverse.number == 1 && (inverse.quality == DIMINISHED || inverse.quality == DOUBLE_DIMINISHED)) fail("CANNOT INVERT");
        out("INVERT %s %s %s\n", a[0], interval_text(simple).text, interval_text(inverse).text);
        break;
    }
    case TRANSPOSE: {
        Note note = read_note(a[0]);
        Tone tone = interval_tone(read_interval(a[1]));
        if (strcmp(a[2], "UP") && strcmp(a[2], "DOWN")) fail("BAD DIRECTION %s", a[2]);
        int sign = !strcmp(a[2], "UP") ? 1 : -1;
        int target = position(note) + sign * tone.letters, value = midi(note) + sign * tone.semitones;
        int letter = mod(target, 7), octave = floor_div(target, 7);
        int alteration = value - 12 * (octave + 1) - natural[letter];
        if (alteration < -2 || alteration > 2) fail("CANNOT SPELL");
        Note result = {{letter, alteration}, octave};
        if (!valid_note(result)) fail("OUT OF RANGE");
        out("TRANSPOSE %s %s %s %s\n", a[0], a[1], a[2], note_text(result).text);
        break;
    }
    case SCALE: {
        Pitch root = read_pitch(a[0]);
        const Scale *scale = &scales[read_scale(a[1])];
        Pitch pitches[7];
        build(root, scale->tones, scale->count, pitches);
        out("SCALE %s %s", a[0], a[1]);
        print_pitches(pitches, scale->count);
        out(" steps=");
        for (int i = 0; i < scale->count; ++i) {
            int next = i + 1 == scale->count ? 12 : scale->tones[i + 1].semitones;
            out("%s%d", i ? "," : "", next - scale->tones[i].semitones);
        }
        out("\n");
        break;
    }
    case CHORD: case VOICE: {
        Note note = {{0,0}, 0};
        Pitch root;
        if (command == VOICE) { note = read_note(a[0]); root = note.pitch; }
        else root = read_pitch(a[0]);
        int quality = read_quality(a[1]), inversion = 0;
        const Chord *chord = &chords[quality];
        if (count == 3 && !canonical(a[2], 0, chord->count - 1, &inversion)) fail("BAD INVERSION %s", a[2]);
        Pitch pitches[5], ordered[5];
        build(root, chord->tones, chord->count, pitches);
        for (int i = 0; i < chord->count; ++i) ordered[i] = pitches[(i + inversion) % chord->count];
        Text symbol = symbol_text(root, quality, inversion ? &ordered[0] : NULL);
        if (command == CHORD) {
            out("CHORD %s", symbol.text);
            print_pitches(ordered, chord->count);
            out("\n");
        } else {
            Note voiced[5];
            int value = midi(note);
            for (int i = 0; i < chord->count; ++i) {
                if (i || inversion) {
                    int difference = mod(pitch_class(ordered[i]) - value, 12);
                    value += difference ? difference : 12;
                }
                voiced[i] = make_note(ordered[i], value);
                if (!valid_note(voiced[i])) fail("OUT OF RANGE");
            }
            out("VOICE %s", symbol.text);
            for (int i = 0; i < chord->count; ++i) out(" %s", note_text(voiced[i]).text);
            out(" midi=");
            for (int i = 0; i < chord->count; ++i) out("%s%d", i ? "," : "", midi(voiced[i]));
            out("\n");
        }
        break;
    }
    case IDENTIFY: case MELODY: {
        Note notes[15];
        for (int i = 0; i < count; ++i) notes[i] = read_note(a[i]);
        if (command == MELODY) {
            int low = 0, high = 0, leaps = 0;
            for (int i = 1; i < count; ++i) {
                if (midi(notes[i]) < midi(notes[low])) low = i;
                if (midi(notes[i]) > midi(notes[high])) high = i;
                if (abs(midi(notes[i]) - midi(notes[i - 1])) >= 3) ++leaps;
            }
            Interval range = between(notes[low], notes[high]).interval;
            IntervalResult steps[14];
            for (int i = 1; i < count; ++i) steps[i - 1] = between(notes[i - 1], notes[i]);
            out("MELODY n=%d low=%s high=%s range=%s leaps=%d steps=", count, a[low], a[high], interval_text(range).text, leaps);
            for (int i = 0; i < count - 1; ++i) out("%s%c%s", i ? "," : "", steps[i].down ? '-' : '+', interval_text(steps[i].interval).text);
            out("\n");
        } else {
            for (int i = 1; i < count; ++i) {
                Note value = notes[i];
                int j = i;
                while (j > 0 && midi(notes[j - 1]) > midi(value)) { notes[j] = notes[j - 1]; --j; }
                notes[j] = value;
            }
            unsigned set = 0;
            int unique = 0;
            for (int i = 0; i < count; ++i) {
                unsigned bit = 1u << pitch_class(notes[i].pitch);
                if (!(set & bit)) { set |= bit; notes[unique++] = notes[i]; }
            }
            for (int i = 0; i < unique; ++i) for (int q = 0; q < 16; ++q) {
                unsigned candidate = 0;
                for (int j = 0; j < chords[q].count; ++j) candidate |= 1u << mod(midi(notes[i]) + chords[q].tones[j].semitones, 12);
                if (candidate != set) continue;
                int inversion = 0;
                while (mod(midi(notes[i]) + chords[q].tones[inversion].semitones, 12) != pitch_class(notes[0].pitch)) ++inversion;
                out("IDENTIFY %s root=%s quality=%s inversion=%d\n", symbol_text(notes[i].pitch, q, inversion ? &notes[0].pitch : NULL).text,
                    pitch_text(notes[i].pitch).text, chords[q].name, inversion);
                return;
            }
            out("IDENTIFY UNKNOWN\n");
        }
        break;
    }
    case CIRCLE: {
        int mode = read_mode(a[0]);
        out("CIRCLE %s", a[0]);
        for (int p = -7; p <= 7; ++p) out(" %s", pitch_text(fifth_pitch(p - modes[mode].offset)).text);
        out("\n");
        break;
    }
    case FINDKEY: {
        Pitch pitches[15];
        for (int i = 0; i < count; ++i) pitches[i] = read_pitch(a[i]);
        Key matches[30];
        int matched = 0;
        for (int p = -7; p <= 7; ++p) for (int mode = 0; mode < 2; ++mode) {
            Key key = make_key(fifth_pitch(p - modes[mode].offset), mode);
            bool match = true;
            for (int i = 0; i < count; ++i) {
                Pitch degree = key.scale[degree_of(key, pitches[i])];
                if (degree.alteration != pitches[i].alteration) match = false;
            }
            if (match) matches[matched++] = key;
        }
        out("FINDKEY %d", matched);
        for (int i = 0; i < matched; ++i) out("%s%s %s", i ? ", " : " ", pitch_text(matches[i].tonic).text, modes[matches[i].mode].name);
        out("\n");
        break;
    }
    case SPELL: {
        int value = read_number(a[0]);
        Key key = read_key(a + 1);
        Pitch pitch = read_pitch((key.fifths < 0 ? flat_names : sharp_names)[value % 12]);
        for (int i = 0; i < 7; ++i) if (pitch_class(key.scale[i]) == value % 12) { pitch = key.scale[i]; break; }
        Note note = make_note(pitch, value);
        if (!valid_note(note)) fail("OUT OF RANGE");
        out("SPELL %d %s %s %s %s\n", value, a[1], a[2], note_text(note).text, degree_label(key, pitch).text);
        break;
    }
    case KEYSIG: case RELATIVE: case DIATONIC: case PROGRESSION: case ANALYZE: case DEGREE: case KEYDIST: {
        Key key = read_key(a);
        if (command == KEYSIG) {
            out("KEYSIG %s %s", a[0], a[1]);
            if (!key.fifths) out(" none");
            else {
                static const char *sharps[] = {"F#", "C#", "G#", "D#", "A#", "E#", "B#"};
                static const char *flats[] = {"Bb", "Eb", "Ab", "Db", "Gb", "Cb", "Fb"};
                out(" %s=%d", key.fifths > 0 ? "sharps" : "flats", abs(key.fifths));
                for (int i = 0; i < abs(key.fifths); ++i) out(" %s", (key.fifths > 0 ? sharps : flats)[i]);
            }
            out("\n");
        } else if (command == RELATIVE) {
            out("RELATIVE %s %s major=%s minor=%s\n", a[0], a[1], pitch_text(fifth_pitch(key.fifths)).text, pitch_text(fifth_pitch(key.fifths + 3)).text);
        } else if (command == DEGREE) {
            Pitch pitch = read_pitch(a[2]);
            out("DEGREE %s %s %s %s\n", a[0], a[1], a[2], degree_label(key, pitch).text);
        } else if (command == KEYDIST) {
            Key other = read_key(a + 2);
            unsigned first = key_set(key), second = key_set(other), common = first & second;
            int r = mod(other.fifths - key.fifths, 12), fifths = r > 6 ? r - 12 : r, count_common = 0;
            while (common) { count_common += common & 1u; common >>= 1; }
            bool same_tonic = pitch_class(key.tonic) == pitch_class(other.tonic);
            const char *relation = first == second ? (same_tonic ? "same" : "relative")
                : same_tonic ? "parallel" : abs(fifths) == 1 ? "close" : "distant";
            out("KEYDIST %s %s %s %s fifths=", a[0], a[1], a[2], a[3]);
            out(fifths > 0 ? "+%d" : "%d", fifths);
            out(" common=%d relation=%s\n", count_common, relation);
        } else if (command == DIATONIC) {
            out("DIATONIC %s %s\n", a[0], a[1]);
            for (int size = 3; size <= 4; ++size) {
                out(size == 3 ? "TRIADS" : "SEVENTHS");
                for (int i = 0; i < 7; ++i) {
                    int root = pitch_class(key.scale[i]);
                    int third = mod(pitch_class(key.scale[(i + 2) % 7]) - root, 12);
                    int fifth = mod(pitch_class(key.scale[(i + 4) % 7]) - root, 12);
                    int quality;
                    if (size == 3) quality = third == 4 ? 0 : fifth == 7 ? 1 : 2;
                    else {
                        int seventh = mod(pitch_class(key.scale[(i + 6) % 7]) - root, 12);
                        quality = third == 4 ? (seventh == 11 ? 9 : 8) : fifth == 7 ? 10 : 12;
                    }
                    out(" %s=%s", roman_text(i, quality).text, symbol_text(key.scale[i], quality, NULL).text);
                }
                out("\n");
            }
        } else if (command == ANALYZE) {
            Symbol symbols[13];
            for (int i = 2; i < count; ++i) symbols[i - 2] = read_symbol(a[i]);
            out("ANALYZE %s %s", a[0], a[1]);
            for (int i = 0; i < count - 2; ++i) out(" %s%s", degree_prefix(key, symbols[i].root).text,
                roman_text(degree_of(key, symbols[i].root), symbols[i].quality).text);
            out("\n");
        } else {
            int length = count - 2;
            Numeral numerals[13];
            Pitch roots[13], tones[13][5];
            for (int i = 0; i < length; ++i) numerals[i] = read_numeral(a[i + 2]);
            for (int i = 0; i < length; ++i) {
                Numeral numeral = numerals[i];
                roots[i] = key.scale[numeral.degree];
                roots[i].alteration += numeral.alteration;
                build(roots[i], chords[numeral.quality].tones, chords[numeral.quality].count, tones[i]);
            }
            out("PROGRESSION %s %s %d\n", a[0], a[1], length);
            for (int i = 0; i < length; ++i) {
                out("%s %s", a[i + 2], symbol_text(roots[i], numerals[i].quality, NULL).text);
                print_pitches(tones[i], chords[numerals[i].quality].count);
                out("\n");
            }
            const char *cadence = "none";
            if (length >= 2) {
                Numeral x = numerals[length - 2], y = numerals[length - 1];
                if (!x.alteration && !y.alteration && x.degree == 4 && y.degree == 0) cadence = "authentic";
                else if (!x.alteration && !y.alteration && x.degree == 3 && y.degree == 0) cadence = "plagal";
                else if (!x.alteration && !y.alteration && x.degree == 4 && y.degree == 5) cadence = "deceptive";
                else if (!y.alteration && y.degree == 4) cadence = "half";
            }
            out("CADENCE %s\n", cadence);
        }
        break;
    }
    }
}

int main(void) {
    char line[512];
    if (!fgets(line, sizeof line, stdin)) return 0;
    int count = (int)strtol(line, NULL, 10);
    for (int i = 0; i < count; ++i) {
        if (!fgets(line, sizeof line, stdin)) break;
        char *words[16];
        int length = 0;
        for (char *word = strtok(line, " \r\n"); word; word = strtok(NULL, " \r\n")) words[length++] = word;
        response_length = 0;
        if (!setjmp(command_error)) execute(length, words);
        fputs(response, stdout);
    }
    return 0;
}
