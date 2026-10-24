#include <algorithm>
#include <array>
#include <cmath>
#include <iostream>
#include <map>
#include <optional>
#include <regex>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

using std::string;
using std::to_string;
using std::vector;

struct CommandError : std::runtime_error { using std::runtime_error::runtime_error; };
[[noreturn]] void fail(const string& message) { throw CommandError(message); }
[[noreturn]] void bad(const string& kind, const string& text) { fail("BAD " + kind + " " + text); }
int mod(int value, int divisor) { return (value % divisor + divisor) % divisor; }
int floor_div(int value, int divisor) { return (value - mod(value, divisor)) / divisor; }
const string letters = "CDEFGAB";
const std::array<int, 7> naturals{0, 2, 4, 5, 7, 9, 11}, fifth_values{0, 2, 4, -1, 1, 3, 5};
const std::array<string, 5> accidentals{"bb", "b", "", "#", "x"};
const std::array<string, 12> sharps{"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"};
const std::array<string, 12> flats{"C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"};
const std::array<string, 7> romans{"I", "II", "III", "IV", "V", "VI", "VII"};

vector<string> words(const string& text) {
    std::istringstream stream(text);
    vector<string> result;
    for (string word; stream >> word;) result.push_back(word);
    return result;
}
string join(const vector<string>& items, const string& separator = " ") {
    string result;
    for (std::size_t i = 0; i < items.size(); ++i) {
        if (i) result += separator;
        result += items[i];
    }
    return result;
}
int integer(const string& text, const string& kind, int low, int high) {
    static const std::regex form("0|[1-9][0-9]*");
    if (text.size() > 3 || !std::regex_match(text, form)) bad(kind, text);
    int value = std::stoi(text);
    if (value < low || value > high) bad(kind, text);
    return value;
}
int frequency(const string& text, bool tuning) {
    static const std::regex form("[0-9]{1,5}(\\.[0-9]{1,2})?");
    if (!std::regex_match(text, form)) bad("FREQUENCY", text);
    auto dot = text.find('.');
    string fraction = dot == string::npos ? "" : text.substr(dot + 1);
    fraction.append(2 - fraction.size(), '0');
    int value = std::stoi(text.substr(0, dot)) * 100 + std::stoi(fraction);
    if (value == 0 || (tuning && (value < 40000 || value > 48000))) bad("FREQUENCY", text);
    return value;
}
string frequency_text(int cents) {
    return to_string(cents / 100) + "." + (cents % 100 < 10 ? "0" : "") + to_string(cents % 100);
}

struct Tone { int letters, semitones; };
struct Pitch {
    int letter, alteration;
    int pitch_class() const { return mod(naturals[letter] + alteration, 12); }
    string text() const { return string(1, letters[letter]) + accidentals[alteration + 2]; }
    bool operator==(const Pitch& other) const { return letter == other.letter && alteration == other.alteration; }
    Pitch raise(Tone tone) const {
        int target = letter + tone.letters;
        int value = naturals[letter] + alteration + tone.semitones - naturals[mod(target, 7)] - 12 * floor_div(target, 7);
        if (value < -2 || value > 2) fail("CANNOT SPELL");
        return {mod(target, 7), value};
    }
};
std::pair<Pitch, string> pitch_prefix(const string& text, const string& kind) {
    static const std::regex form("^([A-G])(bb|b|#|x)?");
    std::smatch match;
    if (!std::regex_search(text, match, form)) bad(kind, text);
    int letter = static_cast<int>(letters.find(match[1].str()));
    int alteration = static_cast<int>(std::find(accidentals.begin(), accidentals.end(), match[2].str()) - accidentals.begin()) - 2;
    return {{letter, alteration}, text.substr(match.length())};
}
Pitch parse_pitch(const string& text) {
    auto [pitch, rest] = pitch_prefix(text, "PITCH");
    if (!rest.empty()) bad("PITCH", text);
    return pitch;
}
Pitch fifth_pitch(int value) {
    const std::array<int, 7> order{3, 0, 4, 1, 5, 2, 6};
    return {order[mod(value + 1, 7)], floor_div(value + 1, 7)};
}
struct Note {
    Pitch pitch;
    int octave;
    int midi() const { return 12 * (octave + 1) + naturals[pitch.letter] + pitch.alteration; }
    int position() const { return 7 * octave + pitch.letter; }
    bool valid() const { return octave >= -1 && octave <= 9 && midi() >= 0 && midi() <= 127; }
    string text() const { return pitch.text() + to_string(octave); }
};
Note parse_note(const string& text) {
    auto [pitch, rest] = pitch_prefix(text, "NOTE");
    static const std::regex form("-1|[0-9]");
    if (!std::regex_match(rest, form)) bad("NOTE", text);
    Note note{pitch, std::stoi(rest)};
    if (!note.valid()) bad("NOTE", text);
    return note;
}
Note make_note(Pitch pitch, int midi) { return {pitch, (midi - naturals[pitch.letter] - pitch.alteration) / 12 - 1}; }
Note spelling(int midi, bool flat = false) { return {parse_pitch((flat ? flats : sharps)[mod(midi, 12)]), floor_div(midi, 12) - 1}; }

const std::array<string, 7> interval_qualities{"P", "M", "m", "A", "d", "AA", "dd"};
std::optional<int> quality_delta(const string& quality, int number) {
    int remainder = (number - 1) % 7;
    bool perfect = remainder == 0 || remainder == 3 || remainder == 4;
    if (quality == "P" && perfect) return 0;
    if (quality == "M" && !perfect) return 0;
    if (quality == "m" && !perfect) return -1;
    if (quality == "A") return 1;
    if (quality == "AA") return 2;
    if (quality == "d") return perfect ? -1 : -2;
    if (quality == "dd") return perfect ? -2 : -3;
    return std::nullopt;
}
struct Interval {
    string quality;
    int number;
    string text() const { return quality + to_string(number); }
    bool forbidden() const { return number == 1 && (quality == "d" || quality == "dd"); }
    Tone tone() const { return {number - 1, 12 * ((number - 1) / 7) + naturals[(number - 1) % 7] + *quality_delta(quality, number)}; }
    Interval simple() const {
        int result = number;
        while (result > 8) result -= 7;
        return {quality, result};
    }
    string consonance() const {
        int n = simple().number;
        if (quality == "P" && (n == 1 || n == 5 || n == 8)) return "perfect";
        if ((quality == "m" || quality == "M") && (n == 3 || n == 6)) return "imperfect";
        return "dissonant";
    }
};
Interval parse_interval(const string& text) {
    static const std::regex form("(AA|dd|P|M|m|A|d)([1-9][0-9]?)");
    std::smatch match;
    if (!std::regex_match(text, match, form)) bad("INTERVAL", text);
    Interval interval{match[1].str(), std::stoi(match[2].str())};
    if (!quality_delta(interval.quality, interval.number) || interval.forbidden()) bad("INTERVAL", text);
    return interval;
}
struct Motion { Interval interval; bool down; int semitones; };
Motion between(Note first, Note second) {
    int distance = second.position() - first.position(), semitones = second.midi() - first.midi();
    bool down = distance < 0 || (distance == 0 && semitones < 0);
    if (down) { distance = -distance; semitones = -semitones; }
    int difference = semitones - 12 * (distance / 7) - naturals[distance % 7];
    for (const auto& quality : interval_qualities) {
        if (quality_delta(quality, distance + 1) == difference) return {{quality, distance + 1}, down, semitones};
    }
    fail("UNNAMEABLE INTERVAL");
}
vector<Tone> tones(const string& pattern) {
    vector<Tone> result;
    for (const auto& text : words(pattern)) result.push_back(parse_interval(text).tone());
    return result;
}
vector<Pitch> build(Pitch root, const vector<Tone>& pattern) {
    vector<Pitch> result;
    for (auto tone : pattern) result.push_back(root.raise(tone));
    return result;
}
vector<string> pitch_names(const vector<Pitch>& pitches) {
    vector<string> result;
    for (auto pitch : pitches) result.push_back(pitch.text());
    return result;
}

struct Scale { string name; vector<Tone> tones; };
const vector<Scale> scales{
    {"major", tones("P1 M2 M3 P4 P5 M6 M7")}, {"natural_minor", tones("P1 M2 m3 P4 P5 m6 m7")},
    {"harmonic_minor", tones("P1 M2 m3 P4 P5 m6 M7")}, {"melodic_minor", tones("P1 M2 m3 P4 P5 M6 M7")},
    {"ionian", tones("P1 M2 M3 P4 P5 M6 M7")}, {"dorian", tones("P1 M2 m3 P4 P5 M6 m7")},
    {"phrygian", tones("P1 m2 m3 P4 P5 m6 m7")}, {"lydian", tones("P1 M2 M3 A4 P5 M6 M7")},
    {"mixolydian", tones("P1 M2 M3 P4 P5 M6 m7")}, {"aeolian", tones("P1 M2 m3 P4 P5 m6 m7")},
    {"locrian", tones("P1 m2 m3 P4 d5 m6 m7")}, {"major_pentatonic", tones("P1 M2 M3 P5 M6")},
    {"minor_pentatonic", tones("P1 m3 P4 P5 m7")}, {"blues", tones("P1 m3 P4 A4 P5 m7")},
    {"whole_tone", tones("P1 M2 M3 A4 A5 A6")},
};
struct Chord {
    string name, suffix;
    bool lower;
    string numeral_suffix;
    vector<Tone> tones;
    Chord(string name, string suffix, const string& numeral, const string& pattern)
        : name(std::move(name)), suffix(std::move(suffix)), lower(numeral[0] == 'i'),
          numeral_suffix(numeral.substr(1)), tones(::tones(pattern)) {}
    string symbol(Pitch root, std::optional<Pitch> bass = std::nullopt) const {
        return root.text() + suffix + (bass ? "/" + bass->text() : "");
    }
    string roman(int degree) const {
        string result = romans[degree];
        if (lower) for (char& letter : result) letter = letter == 'I' ? 'i' : 'v';
        return result + numeral_suffix;
    }
};
const vector<Chord> chords{
    {"maj", "", "I", "P1 M3 P5"}, {"min", "m", "i", "P1 m3 P5"},
    {"dim", "dim", "io", "P1 m3 d5"}, {"aug", "aug", "I+", "P1 M3 A5"},
    {"sus2", "sus2", "Isus2", "P1 M2 P5"}, {"sus4", "sus4", "Isus4", "P1 P4 P5"},
    {"6", "6", "I6", "P1 M3 P5 M6"}, {"m6", "m6", "i6", "P1 m3 P5 M6"},
    {"7", "7", "I7", "P1 M3 P5 m7"}, {"maj7", "maj7", "Imaj7", "P1 M3 P5 M7"},
    {"m7", "m7", "i7", "P1 m3 P5 m7"}, {"mMaj7", "mMaj7", "imaj7", "P1 m3 P5 M7"},
    {"m7b5", "m7b5", "ih7", "P1 m3 d5 m7"}, {"dim7", "dim7", "io7", "P1 m3 d5 d7"},
    {"9", "9", "I9", "P1 M3 P5 m7 M9"}, {"add9", "add9", "Iadd9", "P1 M3 P5 M9"},
};
struct Mode { string name, scale; int offset; };
const vector<Mode> modes{
    {"major", "major", 0}, {"minor", "natural_minor", -3}, {"ionian", "ionian", 0},
    {"dorian", "dorian", -2}, {"phrygian", "phrygian", -4}, {"lydian", "lydian", 1},
    {"mixolydian", "mixolydian", -1}, {"aeolian", "aeolian", -3}, {"locrian", "locrian", -5},
};
template<class T> const T& named(const string& text, const string& kind, const vector<T>& choices) {
    for (const T& item : choices) if (item.name == text) return item;
    bad(kind, text);
}
struct Key {
    Pitch tonic;
    Mode mode;
    int fifths;
    vector<Pitch> scale;
    Key(Pitch tonic, Mode mode) : tonic(tonic), mode(std::move(mode)),
        fifths(fifth_values[tonic.letter] + 7 * tonic.alteration + this->mode.offset) {
        if (fifths < -7 || fifths > 7) fail("THEORETICAL KEY");
        scale = build(tonic, named(this->mode.scale, "SCALE", scales).tones);
    }
    string text() const { return tonic.text() + " " + mode.name; }
    int degree(Pitch pitch) const { return mod(pitch.letter - tonic.letter, 7); }
    string prefix(Pitch pitch) const {
        int difference = pitch.alteration - scale[degree(pitch)].alteration;
        return string(std::abs(difference), difference < 0 ? 'b' : '#');
    }
    string label(Pitch pitch) const { return prefix(pitch) + to_string(degree(pitch) + 1); }
    std::set<int> pitch_classes() const {
        std::set<int> result;
        for (auto pitch : scale) result.insert(pitch.pitch_class());
        return result;
    }
};
Key parse_key(const vector<string>& args, std::size_t start = 0) {
    Pitch tonic = parse_pitch(args[start]);
    const Mode& mode = named(args[start + 1], "MODE", modes);
    return {tonic, mode};
}
struct Numeral { int alteration, degree; const Chord* chord; };
Numeral parse_numeral(const string& text) {
    std::size_t start = text[0] == 'b' || text[0] == '#' ? 1 : 0, end = start;
    int alteration = start == 0 ? 0 : text[0] == 'b' ? -1 : 1;
    while (end < text.size() && string("IViv").find(text[end]) != string::npos) ++end;
    string part = text.substr(start, end - start), suffix = text.substr(end);
    for (int degree = 0; degree < 7; ++degree) {
        for (const Chord& chord : chords) {
            string expected = romans[degree];
            if (chord.lower) for (char& letter : expected) letter = letter == 'I' ? 'i' : 'v';
            if (part == expected && suffix == chord.numeral_suffix) return {alteration, degree, &chord};
        }
    }
    bad("NUMERAL", text);
}
struct Symbol { Pitch root; const Chord* chord; };
Symbol parse_symbol(const string& text) {
    auto [pitch, rest] = pitch_prefix(text, "SYMBOL");
    for (const Chord& chord : chords) if (chord.suffix == rest) return {pitch, &chord};
    bad("SYMBOL", text);
}
string identify(vector<Note> notes) {
    std::stable_sort(notes.begin(), notes.end(), [](Note a, Note b) { return a.midi() < b.midi(); });
    std::set<int> present;
    vector<Note> candidates;
    for (auto note : notes) if (present.insert(note.pitch.pitch_class()).second) candidates.push_back(note);
    Pitch bass = candidates.front().pitch;
    for (auto root : candidates) {
        for (const Chord& chord : chords) {
            vector<int> classes;
            for (auto tone : chord.tones) classes.push_back(mod(root.midi() + tone.semitones, 12));
            if (std::set<int>(classes.begin(), classes.end()) != present) continue;
            int inversion = static_cast<int>(std::find(classes.begin(), classes.end(), bass.pitch_class()) - classes.begin());
            std::optional<Pitch> slash = inversion == 0 ? std::nullopt : std::optional<Pitch>(bass);
            return "IDENTIFY " + chord.symbol(root.pitch, slash) + " root=" + root.pitch.text()
                + " quality=" + chord.name + " inversion=" + to_string(inversion);
        }
    }
    return "IDENTIFY UNKNOWN";
}
string melody(const vector<Note>& notes, const vector<string>& args) {
    std::size_t low = 0, high = 0;
    for (std::size_t i = 1; i < notes.size(); ++i) {
        if (notes[i].midi() < notes[low].midi()) low = i;
        if (notes[i].midi() > notes[high].midi()) high = i;
    }
    Interval range = between(notes[low], notes[high]).interval;
    vector<string> steps;
    int leaps = 0;
    for (std::size_t i = 1; i < notes.size(); ++i) {
        Motion motion = between(notes[i - 1], notes[i]);
        steps.push_back(string(motion.down ? "-" : "+") + motion.interval.text());
        if (std::abs(notes[i].midi() - notes[i - 1].midi()) >= 3) ++leaps;
    }
    return "MELODY n=" + to_string(notes.size()) + " low=" + args[low] + " high=" + args[high]
        + " range=" + range.text() + " leaps=" + to_string(leaps) + " steps=" + join(steps, ",");
}
string cadence(const vector<Numeral>& numerals) {
    if (numerals.size() < 2) return "none";
    const Numeral& first = numerals[numerals.size() - 2];
    const Numeral& last = numerals.back();
    if (first.alteration == 0 && last.alteration == 0) {
        if (first.degree == 4 && last.degree == 0) return "authentic";
        if (first.degree == 3 && last.degree == 0) return "plagal";
        if (first.degree == 4 && last.degree == 5) return "deceptive";
    }
    return last.alteration == 0 && last.degree == 4 ? "half" : "none";
}

vector<string> diatonic(const Key& key) {
    vector<string> result{"DIATONIC " + key.text()};
    for (int size : {3, 4}) {
        vector<string> items;
        for (int degree = 0; degree < 7; ++degree) {
            int root = key.scale[degree].pitch_class();
            int third = mod(key.scale[(degree + 2) % 7].pitch_class() - root, 12);
            int fifth = mod(key.scale[(degree + 4) % 7].pitch_class() - root, 12);
            string quality;
            if (size == 3) quality = third == 4 ? "maj" : fifth == 7 ? "min" : "dim";
            else {
                int seventh = mod(key.scale[(degree + 6) % 7].pitch_class() - root, 12);
                quality = third == 4 ? (seventh == 11 ? "maj7" : "7") : fifth == 7 ? "m7" : "m7b5";
            }
            const Chord& chord = named(quality, "QUALITY", chords);
            items.push_back(chord.roman(degree) + "=" + chord.symbol(key.scale[degree]));
        }
        result.push_back(string(size == 3 ? "TRIADS " : "SEVENTHS ") + join(items));
    }
    return result;
}
vector<string> execute_key(const string& command, const vector<string>& args) {
    Key key = parse_key(args);
    if (command == "KEYSIG") {
        if (key.fifths == 0) return {"KEYSIG " + key.text() + " none"};
        vector<string> names = words(key.fifths > 0 ? "F# C# G# D# A# E# B#" : "Bb Eb Ab Db Gb Cb Fb");
        names.resize(std::abs(key.fifths));
        return {"KEYSIG " + key.text() + (key.fifths > 0 ? " sharps=" : " flats=") + to_string(std::abs(key.fifths)) + " " + join(names)};
    }
    if (command == "RELATIVE") return {"RELATIVE " + key.text() + " major=" + fifth_pitch(key.fifths).text() + " minor=" + fifth_pitch(key.fifths + 3).text()};
    if (command == "DIATONIC") return diatonic(key);
    if (command == "DEGREE") {
        Pitch pitch = parse_pitch(args[2]);
        return {"DEGREE " + key.text() + " " + args[2] + " " + key.label(pitch)};
    }
    if (command == "KEYDIST") {
        Key other = parse_key(args, 2);
        int distance = mod(other.fifths - key.fifths, 12);
        if (distance > 6) distance -= 12;
        std::set<int> first = key.pitch_classes(), second = other.pitch_classes();
        bool same_tonic = key.tonic.pitch_class() == other.tonic.pitch_class();
        string relation = first == second ? (same_tonic ? "same" : "relative")
            : same_tonic ? "parallel" : std::abs(distance) == 1 ? "close" : "distant";
        int common = 0;
        for (int pitch : first) if (second.count(pitch)) ++common;
        return {"KEYDIST " + key.text() + " " + other.text() + " fifths=" + (distance > 0 ? "+" : "")
            + to_string(distance) + " common=" + to_string(common) + " relation=" + relation};
    }
    if (command == "ANALYZE") {
        vector<Symbol> symbols;
        for (std::size_t i = 2; i < args.size(); ++i) symbols.push_back(parse_symbol(args[i]));
        vector<string> results;
        for (const Symbol& symbol : symbols) results.push_back(key.prefix(symbol.root) + symbol.chord->roman(key.degree(symbol.root)));
        return {"ANALYZE " + key.text() + " " + join(results)};
    }
    vector<Numeral> numerals;
    for (std::size_t i = 2; i < args.size(); ++i) numerals.push_back(parse_numeral(args[i]));
    vector<string> result{"PROGRESSION " + key.text() + " " + to_string(numerals.size())};
    for (std::size_t i = 0; i < numerals.size(); ++i) {
        const Numeral& numeral = numerals[i];
        Pitch root = key.scale[numeral.degree];
        root.alteration += numeral.alteration;
        vector<Pitch> pitches = build(root, numeral.chord->tones);
        result.push_back(args[i + 2] + " " + numeral.chord->symbol(root) + " " + join(pitch_names(pitches)));
    }
    result.push_back("CADENCE " + cadence(numerals));
    return result;
}

const std::map<string, std::pair<int, int>> arities{
    {"MIDI", {1, 1}}, {"NOTE", {1, 1}}, {"FREQ", {1, 1}}, {"TUNING", {1, 1}}, {"PITCH", {1, 1}},
    {"INTERVAL", {2, 2}}, {"INVERT", {1, 1}}, {"TRANSPOSE", {3, 3}}, {"SCALE", {2, 2}},
    {"CHORD", {2, 3}}, {"VOICE", {2, 3}}, {"IDENTIFY", {2, 15}}, {"MELODY", {2, 15}},
    {"ENHARMONIC", {1, 1}}, {"KEYSIG", {2, 2}}, {"RELATIVE", {2, 2}}, {"CIRCLE", {1, 1}},
    {"DIATONIC", {2, 2}}, {"PROGRESSION", {3, 15}}, {"ANALYZE", {3, 15}}, {"FINDKEY", {1, 15}},
    {"DEGREE", {3, 3}}, {"SPELL", {3, 3}}, {"KEYDIST", {4, 4}},
};
class Calculator {
    int tuning_ = 44000;
public:
    vector<string> execute(const string& line) {
        vector<string> args = words(line);
        string command = args.front();
        auto entry = arities.find(command);
        if (entry == arities.end()) fail("UNKNOWN COMMAND " + command);
        args.erase(args.begin());
        auto [low, high] = entry->second;
        if (args.size() < static_cast<std::size_t>(low) || args.size() > static_cast<std::size_t>(high)) fail("ARGUMENT COUNT");
        if (command == "MIDI" || command == "FREQ" || command == "ENHARMONIC") {
            Note note = parse_note(args[0]);
            int value = note.midi();
            if (command == "MIDI") return {"MIDI " + args[0] + " " + to_string(value)};
            if (command == "FREQ") {
                int cents = static_cast<int>(std::floor(tuning_ * std::exp2((value - 69) / 12.0) + 0.5));
                return {"FREQ " + args[0] + " " + frequency_text(cents)};
            }
            vector<string> equivalents;
            for (int octave = -1; octave <= 9; ++octave) {
                for (int letter = 0; letter < 7; ++letter) {
                    int alteration = value - 12 * (octave + 1) - naturals[letter];
                    if (alteration >= -2 && alteration <= 2) equivalents.push_back(Note{{letter, alteration}, octave}.text());
                }
            }
            return {"ENHARMONIC " + args[0] + " " + join(equivalents)};
        }
        if (command == "NOTE") {
            int value = integer(args[0], "NUMBER", 0, 127);
            return {"NOTE " + to_string(value) + " " + spelling(value).text() + " " + spelling(value, true).text()};
        }
        if (command == "TUNING" || command == "PITCH") {
            int value = frequency(args[0], command == "TUNING");
            if (command == "TUNING") {
                tuning_ = value;
                return {"TUNING " + frequency_text(value)};
            }
            double height = 69 + 12 * std::log2(static_cast<double>(value) / tuning_);
            int nearest = static_cast<int>(std::floor(height + 0.5));
            if (nearest < 0 || nearest > 127) fail("OUT OF RANGE");
            int cents = static_cast<int>(std::floor(100 * (height - nearest) + 0.5));
            return {"PITCH " + frequency_text(value) + " " + spelling(nearest).text() + " " + (cents >= 0 ? "+" : "") + to_string(cents)};
        }
        if (command == "INTERVAL") {
            Note first = parse_note(args[0]);
            Note second = parse_note(args[1]);
            Motion motion = between(first, second);
            return {"INTERVAL " + args[0] + " " + args[1] + " " + motion.interval.text() + (motion.down ? " down" : " up")
                + " semitones=" + to_string(motion.semitones) + " simple=" + motion.interval.simple().text() + " class=" + motion.interval.consonance()};
        }
        if (command == "INVERT") {
            Interval simple = parse_interval(args[0]).simple();
            const std::map<string, string> inverse_qualities{{"P", "P"}, {"M", "m"}, {"m", "M"}, {"A", "d"}, {"d", "A"}, {"AA", "dd"}, {"dd", "AA"}};
            Interval inverse{inverse_qualities.at(simple.quality), 9 - simple.number};
            if (inverse.forbidden()) fail("CANNOT INVERT");
            return {"INVERT " + args[0] + " " + simple.text() + " " + inverse.text()};
        }
        if (command == "TRANSPOSE") {
            Note note = parse_note(args[0]);
            Interval interval = parse_interval(args[1]);
            const string& direction = args[2];
            if (direction != "UP" && direction != "DOWN") bad("DIRECTION", direction);
            int sign = direction == "UP" ? 1 : -1;
            Tone tone = interval.tone();
            int target = note.position() + sign * tone.letters, value = note.midi() + sign * tone.semitones;
            int letter = mod(target, 7), octave = floor_div(target, 7), alteration = value - 12 * (octave + 1) - naturals[letter];
            if (alteration < -2 || alteration > 2) fail("CANNOT SPELL");
            Note result{{letter, alteration}, octave};
            if (!result.valid()) fail("OUT OF RANGE");
            return {"TRANSPOSE " + args[0] + " " + args[1] + " " + direction + " " + result.text()};
        }
        if (command == "SCALE") {
            Pitch root = parse_pitch(args[0]);
            const Scale& scale = named(args[1], "SCALE", scales);
            vector<Pitch> pitches = build(root, scale.tones);
            vector<string> steps;
            for (std::size_t i = 0; i < scale.tones.size(); ++i) {
                int next = i + 1 == scale.tones.size() ? 12 : scale.tones[i + 1].semitones;
                steps.push_back(to_string(next - scale.tones[i].semitones));
            }
            return {"SCALE " + args[0] + " " + args[1] + " " + join(pitch_names(pitches)) + " steps=" + join(steps, ",")};
        }
        if (command == "CHORD" || command == "VOICE") {
            std::optional<Note> input;
            if (command == "VOICE") input = parse_note(args[0]);
            Pitch root = input ? input->pitch : parse_pitch(args[0]);
            const Chord& chord = named(args[1], "QUALITY", chords);
            int inversion = args.size() == 3 ? integer(args[2], "INVERSION", 0, static_cast<int>(chord.tones.size()) - 1) : 0;
            vector<Pitch> pitches = build(root, chord.tones);
            std::rotate(pitches.begin(), pitches.begin() + inversion, pitches.end());
            std::optional<Pitch> bass = inversion == 0 ? std::nullopt : std::optional<Pitch>(pitches.front());
            string symbol = chord.symbol(root, bass);
            if (command == "CHORD") return {"CHORD " + symbol + " " + join(pitch_names(pitches))};
            int value = input->midi();
            vector<string> notes, numbers;
            for (std::size_t i = 0; i < pitches.size(); ++i) {
                if (i > 0 || inversion > 0) {
                    int difference = mod(pitches[i].pitch_class() - value, 12);
                    value += difference == 0 ? 12 : difference;
                }
                Note note = make_note(pitches[i], value);
                if (!note.valid()) fail("OUT OF RANGE");
                notes.push_back(note.text());
                numbers.push_back(to_string(value));
            }
            return {"VOICE " + symbol + " " + join(notes) + " midi=" + join(numbers, ",")};
        }
        if (command == "IDENTIFY" || command == "MELODY") {
            vector<Note> notes;
            for (const string& arg : args) notes.push_back(parse_note(arg));
            return {command == "IDENTIFY" ? identify(notes) : melody(notes, args)};
        }
        if (command == "CIRCLE") {
            const Mode& mode = named(args[0], "MODE", modes);
            vector<string> names;
            for (int fifths = -7; fifths <= 7; ++fifths) names.push_back(fifth_pitch(fifths - mode.offset).text());
            return {"CIRCLE " + args[0] + " " + join(names)};
        }
        if (command == "FINDKEY") {
            vector<Pitch> pitches;
            for (const string& arg : args) pitches.push_back(parse_pitch(arg));
            vector<string> keys;
            for (int fifths = -7; fifths <= 7; ++fifths) {
                for (int i = 0; i < 2; ++i) {
                    Key key(fifth_pitch(fifths - modes[i].offset), modes[i]);
                    bool contains = std::all_of(pitches.begin(), pitches.end(), [&](Pitch pitch) {
                        return std::find(key.scale.begin(), key.scale.end(), pitch) != key.scale.end();
                    });
                    if (contains) keys.push_back(key.text());
                }
            }
            return {"FINDKEY " + to_string(keys.size()) + (keys.empty() ? "" : " " + join(keys, ", "))};
        }
        if (command == "SPELL") {
            int value = integer(args[0], "NUMBER", 0, 127);
            Key key = parse_key(args, 1);
            Pitch pitch = spelling(value, key.fifths < 0).pitch;
            for (auto candidate : key.scale) if (candidate.pitch_class() == value % 12) { pitch = candidate; break; }
            Note note = make_note(pitch, value);
            if (!note.valid()) fail("OUT OF RANGE");
            return {"SPELL " + to_string(value) + " " + key.text() + " " + note.text() + " " + key.label(pitch)};
        }
        return execute_key(command, args);
    }
};

int main() {
    std::ios::sync_with_stdio(false);
    std::cin.tie(nullptr);
    int count;
    std::cin >> count;
    string line;
    std::getline(std::cin, line);
    Calculator calculator;
    for (int i = 0; i < count; ++i) {
        std::getline(std::cin, line);
        try {
            for (const string& result : calculator.execute(line)) std::cout << result << '\n';
        } catch (const CommandError& error) {
            std::cout << "ERROR " << error.what() << '\n';
        }
    }
}
