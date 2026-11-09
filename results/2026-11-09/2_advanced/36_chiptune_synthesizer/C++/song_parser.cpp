#include "synthesizer.hpp"
static int hex(const std::string &text) {
    return std::stoi(text, nullptr, 16);
}
static Lines words(const std::string &text) {
    std::istringstream in(text);
    Lines out;
    std::string word;
    while (in >> word)
        out.push_back(word);
    return out;
}
int note_number(const std::string &name) {
    const std::array<std::string, 12> names = {"C-", "C#", "D-", "D#", "E-", "F-",
                                               "F#", "G-", "G#", "A-", "A#", "B-"};
    for (int i = 0; i < 12; ++i)
        if (name.substr(0, 2) == names[i])
            return 12 * (name[2] - '0') + i;
    return -1;
}
std::string note_name(int note) {
    const std::array<std::string, 12> names = {"C-", "C#", "D-", "D#", "E-", "F-",
                                               "F#", "G-", "G#", "A-", "A#", "B-"};
    return names[note % 12] + decimal(note / 12);
}
bool Cell::empty() const {
    return note == -1 && instrument == 0 && volume < 0 && effect.name.empty();
}
static Effect effect(const std::string &text) {
    Effect out;
    out.text = text;
    if (text == "...")
        return out;
    if (text[0] == 'E') {
        out.name = text.substr(0, 2);
        out.argument = hex(text.substr(2, 1));
        out.x = out.argument;
    } else {
        out.name = text.substr(0, 1);
        out.argument = hex(text.substr(1, 2));
        out.x = out.argument / 16;
        out.y = out.argument % 16;
    }
    return out;
}
static Cell cell(const std::string &text) {
    Cell out;
    out.note = text.substr(0, 3) == "..."   ? -1
               : text.substr(0, 3) == "OFF" ? -2
                                            : note_number(text.substr(0, 3));
    out.instrument = text.substr(4, 2) == ".." ? 0 : hex(text.substr(4, 2));
    out.volume = text[7] == '.' ? -1 : hex(text.substr(7, 1));
    out.effect = effect(text.substr(9, 3));
    return out;
}
Song read_song() {
    Lines lines;
    for (const std::string &line : read_lines("input/song.txt"))
        if (!line.empty() && line[0] != '#')
            lines.push_back(line);
    Song out;
    out.title = lines[0].substr(6);
    out.rate = std::stoi(words(lines[1])[1]);
    out.speed = std::stoi(words(lines[2])[1]);
    out.tempo = std::stoi(words(lines[3])[1]);
    out.gain = std::stoi(words(lines[4])[1]);
    std::size_t i = 5;
    while (i < lines.size()) {
        const Lines header = words(lines[i++]);
        if (header[0] == "ORDER") {
            for (std::size_t j = 1; j < header.size(); ++j)
                out.order.push_back(hex(header[j]));
            continue;
        }
        if (header[0] == "PATTERN") {
            Pattern pattern;
            while (lines[i] != "END") {
                const std::string &line = lines[i++];
                const int row = hex(line.substr(0, 2));
                for (int channel = 0; channel < 4; ++channel)
                    pattern[row][channel] = cell(line.substr(3 + 15 * channel, 12));
            }
            ++i;
            out.patterns[hex(header[1])] = pattern;
            continue;
        }
        Instrument instrument;
        instrument.number = hex(header[1]);
        instrument.name = header[2];
        while (lines[i] != "END") {
            const Lines fields = words(lines[i++]);
            if (fields[0] == "WAVE") {
                instrument.wave = fields[1];
                if (fields[1] == "PULSE") {
                    const int duty = std::stoi(fields[2]);
                    instrument.mode = duty == 12 ? 0 : duty == 25 ? 1 : duty == 50 ? 2 : 3;
                } else if (fields[1] == "NOISE")
                    instrument.mode = fields[2] == "SHORT" ? 1 : 0;
                else if (fields[1] == "TABLE")
                    for (int j = 0; j < 32; ++j)
                        instrument.table[j] = hex(fields[2].substr(j, 1));
            } else if (fields[0] == "ENVELOPE") {
                instrument.attack = std::stoi(fields[1]);
                instrument.decay = std::stoi(fields[2]);
                instrument.sustain = std::stoi(fields[3]);
                instrument.release = std::stoi(fields[4]);
            } else if (fields[0] == "VIBRATO") {
                instrument.vibrato = true;
                instrument.delay = std::stoi(fields[1]);
                instrument.speed = std::stoi(fields[2]);
                instrument.depth = std::stoi(fields[3]);
            } else if (fields[0] == "ARPEGGIO")
                for (std::size_t j = 1; j < fields.size(); ++j)
                    instrument.arpeggio.push_back(std::stoi(fields[j]));
            else
                instrument.sweep = std::stoi(fields[1]);
        }
        ++i;
        out.instruments[instrument.number] = instrument;
    }
    return out;
}
Params read_params() {
    const Lines lines = read_lines("input/params.txt");
    Params out;
    for (std::size_t i = 0; i < lines.size(); ++i) {
        const Lines fields = words(lines[i]);
        if (i == 0)
            out.maximum = std::stoi(fields[1]);
        else if (i == 1)
            out.loops = std::stoi(fields[1]);
        else if (i == 2)
            out.fade = std::stoi(fields[1]);
        else if (i == 3)
            for (int j = 0; j < 4; ++j)
                out.muted[j] = fields[j + 1] == "1";
        else if (i == 4) {
            out.start = std::stoi(fields[1]);
            out.length = std::stoi(fields[2]);
            out.width = std::stoi(fields[3]);
            out.height = std::stoi(fields[4]);
            out.scope = std::stoi(fields[5]);
        } else if (i == 5) {
            out.roll_start = std::stoi(fields[1]);
            out.roll_rows = std::stoi(fields[2]);
        } else if (i == 6) {
            out.preview_note = note_number(fields[1]);
            out.preview_ticks = std::stoi(fields[2]);
            out.preview_release = std::stoi(fields[3]);
        } else
            out.traces.emplace(hex(fields[1]), hex(fields[2]));
    }
    return out;
}
