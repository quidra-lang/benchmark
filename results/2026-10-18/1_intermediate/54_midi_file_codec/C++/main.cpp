#include <algorithm>
#include <array>
#include <cstdint>
#include <deque>
#include <iomanip>
#include <iostream>
#include <map>
#include <sstream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <tuple>
#include <utility>
#include <vector>

using Tick = std::int64_t;
using Bytes = std::vector<unsigned char>;

enum class Kind {
    NoteOff, NoteOn, PolyPressure, Control, Program, ChannelPressure, PitchBend,
    Sysex, SysexEscape, SequenceNumber, Text, Copyright, TrackName,
    InstrumentName, Lyric, Marker, CuePoint, ChannelPrefix, End, Tempo,
    SmpteOffset, TimeSignature, KeySignature, SequencerSpecific, Meta
};

const std::array<std::string, 25> typeNames = {
    "NOTE_OFF", "NOTE_ON", "POLY_PRESSURE", "CONTROL", "PROGRAM",
    "CHANNEL_PRESSURE", "PITCH_BEND", "SYSEX", "SYSEX_ESCAPE",
    "SEQUENCE_NUMBER", "TEXT_EVENT", "COPYRIGHT", "TRACK_NAME",
    "INSTRUMENT_NAME", "LYRIC", "MARKER", "CUE_POINT", "CHANNEL_PREFIX",
    "END_OF_TRACK", "TEMPO", "SMPTE_OFFSET", "TIME_SIGNATURE",
    "KEY_SIGNATURE", "SEQUENCER_SPECIFIC", "META"
};
const std::array<std::string, 12> pitchNames = {
    "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"
};
const std::array<std::array<std::string, 15>, 2> keyNames = {{
    {"Cb", "Gb", "Db", "Ab", "Eb", "Bb", "F", "C", "G", "D", "A", "E", "B", "F#", "C#"},
    {"Ab", "Eb", "Bb", "F", "C", "G", "D", "A", "E", "B", "F#", "C#", "G#", "D#", "A#"}
}};

struct Event {
    Tick tick = 0;
    Kind kind = Kind::End;
    int channel = 0;
    std::vector<int> fields;
    Bytes data;
};

struct Song {
    int format = 0;
    int division = 0;
    std::vector<std::vector<Event>> tracks;

    std::size_t eventCount() const {
        std::size_t count = 0;
        for (const std::vector<Event>& track : tracks) count += track.size();
        return count;
    }

    Tick length() const {
        Tick result = 0;
        for (const std::vector<Event>& track : tracks) result = std::max(result, track.back().tick);
        return result;
    }
};

bool channelEvent(Kind kind) { return kind <= Kind::PitchBend; }
bool textEvent(Kind kind) { return kind >= Kind::Text && kind <= Kind::CuePoint; }
bool noteOn(const Event& event) { return event.kind == Kind::NoteOn && event.fields[1] > 0; }
bool noteOff(const Event& event) {
    return event.kind == Kind::NoteOff || (event.kind == Kind::NoteOn && event.fields[1] == 0);
}
bool inRange(Tick value, Tick low, Tick high) { return low <= value && value <= high; }

std::string pitchName(int pitch) {
    return pitchNames[pitch % 12] + std::to_string(pitch / 12 - 1);
}

int parsePitch(const std::string& name) {
    for (int pitch = 0; pitch < 128; ++pitch) if (pitchName(pitch) == name) return pitch;
    return -1;
}

std::string hex(Tick value, int width) {
    std::ostringstream out;
    out << std::uppercase << std::hex << std::setfill('0') << std::setw(width) << value;
    return out.str();
}

std::vector<std::string> words(const std::string& line) {
    std::istringstream input(line);
    std::vector<std::string> result;
    for (std::string word; input >> word;) result.push_back(word);
    return result;
}

[[noreturn]] void fail(const std::string& reason) { throw std::runtime_error(reason); }
[[noreturn]] void byteError(std::size_t position, const std::string& reason) {
    fail("byte " + std::to_string(position) + ": " + reason);
}
[[noreturn]] void lineError(std::size_t line, const std::string& reason) {
    fail("line " + std::to_string(line) + ": " + reason);
}

int metaType(Kind kind) {
    if (textEvent(kind)) return static_cast<int>(kind) - static_cast<int>(Kind::Text) + 1;
    switch (kind) {
        case Kind::SequenceNumber: return 0x00;
        case Kind::ChannelPrefix: return 0x20;
        case Kind::End: return 0x2F;
        case Kind::Tempo: return 0x51;
        case Kind::SmpteOffset: return 0x54;
        case Kind::TimeSignature: return 0x58;
        case Kind::KeySignature: return 0x59;
        case Kind::SequencerSpecific: return 0x7F;
        default: return -1;
    }
}

Kind metaKind(int type) {
    for (int i = static_cast<int>(Kind::SequenceNumber); i < static_cast<int>(Kind::Meta); ++i) {
        const Kind kind = static_cast<Kind>(i);
        if (metaType(kind) == type) return kind;
    }
    return Kind::Meta;
}

std::uint32_t bigEndian(const Bytes& data, std::size_t position, int count) {
    std::uint32_t value = 0;
    for (int i = 0; i < count; ++i) value = value * 256 + data[position + i];
    return value;
}

struct Chunk { std::size_t begin, end; };

Chunk readChunk(const Bytes& data, std::size_t position, std::string_view id) {
    if (data.size() - position < 8) byteError(position, "truncated chunk");
    for (std::size_t i = 0; i < 4; ++i) {
        if (data[position + i] != static_cast<unsigned char>(id[i])) byteError(position, "bad chunk id");
    }
    const std::uint64_t end = position + 8ULL + bigEndian(data, position + 4, 4);
    if (end > data.size()) byteError(position, "truncated chunk");
    return {position + 8, static_cast<std::size_t>(end)};
}

class TrackReader {
    const Bytes& bytes;
    std::size_t position;
    std::size_t end;
    std::size_t eventStart = 0;

    int take() {
        if (position == end) byteError(eventStart, "truncated event");
        return bytes[position++];
    }

    int variable() {
        const std::size_t start = position;
        int value = 0;
        for (int i = 0; i < 4; ++i) {
            const int next = take();
            value = value * 128 + (next & 127);
            if (next < 128) return value;
        }
        byteError(start, "variable-length value too long");
    }

    Bytes payload(int length) {
        if (static_cast<std::size_t>(length) > end - position) byteError(eventStart, "truncated event");
        Bytes result(bytes.begin() + position, bytes.begin() + position + length);
        position += length;
        return result;
    }

    Event meta(int type, Bytes data, Tick tick, std::size_t statusPosition) {
        const std::map<int, int> lengths = {
            {0x00, 2}, {0x20, 1}, {0x2F, 0}, {0x51, 3}, {0x54, 5}, {0x58, 4}, {0x59, 2}
        };
        const auto required = lengths.find(type);
        if (required != lengths.end() && data.size() != static_cast<std::size_t>(required->second)) {
            byteError(statusPosition, "bad meta length");
        }
        Event event;
        event.tick = tick;
        event.kind = metaKind(type);
        switch (event.kind) {
            case Kind::SequenceNumber: event.fields = {static_cast<int>(bigEndian(data, 0, 2))}; break;
            case Kind::ChannelPrefix:
                if (data[0] > 15) byteError(statusPosition, "bad meta data");
                event.fields = {data[0] + 1};
                break;
            case Kind::Tempo:
                event.fields = {static_cast<int>(bigEndian(data, 0, 3))};
                if (event.fields[0] == 0) byteError(statusPosition, "bad meta data");
                break;
            case Kind::SmpteOffset: event.fields.assign(data.begin(), data.end()); break;
            case Kind::TimeSignature:
                if (data[0] == 0 || data[1] > 6) byteError(statusPosition, "bad meta data");
                event.fields = {data[0], 1 << data[1], data[2], data[3]};
                break;
            case Kind::KeySignature: {
                const int sharps = data[0] < 128 ? data[0] : data[0] - 256;
                if (!inRange(sharps, -7, 7) || data[1] > 1) byteError(statusPosition, "bad meta data");
                event.fields = {sharps, data[1]};
                break;
            }
            case Kind::Meta: event.fields = {type}; event.data = std::move(data); break;
            default: event.data = std::move(data); break;
        }
        return event;
    }

public:
    TrackReader(const Bytes& data, Chunk chunk) : bytes(data), position(chunk.begin), end(chunk.end) {}

    std::vector<Event> read() {
        std::vector<Event> events;
        Tick tick = 0;
        int running = -1;
        while (position < end) {
            if (!events.empty() && events.back().kind == Kind::End) byteError(position, "event after end of track");
            eventStart = position;
            tick += variable();
            const std::size_t statusPosition = position;
            if (position == end) byteError(eventStart, "truncated event");
            int status = bytes[position];
            if (status < 128) {
                if (running < 0) byteError(position, "data byte without running status");
                status = running;
            } else {
                ++position;
            }
            Event event;
            event.tick = tick;
            if (status < 0xF0) {
                running = status;
                const int group = status >> 4;
                event.kind = static_cast<Kind>(group - 8);
                event.channel = (status & 15) + 1;
                const int count = group == 0xC || group == 0xD ? 1 : 2;
                for (int i = 0; i < count; ++i) {
                    const std::size_t dataPosition = position;
                    const int value = take();
                    if (value >= 128) byteError(dataPosition, "bad data byte");
                    event.fields.push_back(value);
                }
                if (event.kind == Kind::PitchBend) {
                    event.fields = {event.fields[0] + 128 * event.fields[1] - 8192};
                }
            } else if (status == 0xF0 || status == 0xF7) {
                running = -1;
                event.kind = status == 0xF0 ? Kind::Sysex : Kind::SysexEscape;
                const int length = variable();
                event.data = payload(length);
            } else if (status == 0xFF) {
                running = -1;
                const int type = take();
                const int length = variable();
                event = meta(type, payload(length), tick, statusPosition);
            } else {
                byteError(statusPosition, "unknown status byte");
            }
            events.push_back(std::move(event));
        }
        if (events.empty() || events.back().kind != Kind::End) byteError(end, "missing end of track");
        return events;
    }
};

Song parseHex(const std::vector<std::string>& lines) {
    Bytes bytes;
    for (const std::string& line : lines) {
        for (const std::string& value : words(line)) bytes.push_back(static_cast<unsigned char>(std::stoi(value, nullptr, 16)));
    }
    const Chunk header = readChunk(bytes, 0, "MThd");
    if (header.end - header.begin != 6) byteError(4, "bad header length");
    Song song;
    song.format = bigEndian(bytes, 8, 2);
    const int count = bigEndian(bytes, 10, 2);
    song.division = bigEndian(bytes, 12, 2);
    if (song.format > 2) byteError(8, "bad format");
    if (count == 0 || (song.format == 0 && count != 1)) byteError(10, "bad track count");
    if (song.division & 0x8000) byteError(12, "smpte timing not supported");
    if (song.division == 0) byteError(12, "bad division");
    std::size_t position = 14;
    for (int i = 0; i < count; ++i) {
        if (position == bytes.size()) byteError(position, "missing track");
        const Chunk chunk = readChunk(bytes, position, "MTrk");
        song.tracks.push_back(TrackReader(bytes, chunk).read());
        position = chunk.end;
    }
    if (position != bytes.size()) byteError(position, "extra data");
    return song;
}

bool uppercaseHex(const std::string& value) {
    return std::all_of(value.begin(), value.end(), [](char ch) {
        return (ch >= '0' && ch <= '9') || (ch >= 'A' && ch <= 'F');
    });
}

Event parseTextEvent(const std::string& line, std::size_t number, int& track) {
    const std::size_t first = line.find(' ');
    const std::size_t second = line.find(' ', first + 1);
    const std::size_t third = line.find(' ', second + 1);
    const std::string type = line.substr(second + 1, third == std::string::npos ? third : third - second - 1);
    const auto found = std::find(typeNames.begin(), typeNames.end(), type);
    if (found == typeNames.end()) lineError(number, "unknown event type");
    Event event;
    event.tick = std::stoll(line.substr(0, first));
    track = std::stoi(line.substr(first + 1, second - first - 1));
    event.kind = static_cast<Kind>(found - typeNames.begin());
    const std::string rest = third == std::string::npos ? "" : line.substr(third + 1);
    const std::vector<std::string> fields = words(rest);
    const auto bad = [number]() { lineError(number, "bad value"); };
    const auto need = [&fields, &bad](std::size_t count) { if (fields.size() != count) bad(); };
    const auto integer = [&fields, &bad](std::size_t index, int low, int high) {
        const int value = std::stoi(fields[index]);
        if (!inRange(value, low, high)) bad();
        return value;
    };
    const auto blob = [&fields, &event, &bad](std::size_t offset) {
        if (fields.size() < offset + 1) bad();
        const int length = std::stoi(fields[offset]);
        if (!inRange(length, 0, 1000000) || fields.size() != offset + (length == 0 ? 1 : 2)) bad();
        if (length > 0) {
            const std::string& data = fields[offset + 1];
            if (data.size() != static_cast<std::size_t>(2 * length) || !uppercaseHex(data)) bad();
            for (std::size_t i = 0; i < data.size(); i += 2) {
                event.data.push_back(static_cast<unsigned char>(std::stoi(data.substr(i, 2), nullptr, 16)));
            }
        }
    };
    if (channelEvent(event.kind)) {
        const bool single = event.kind == Kind::Program || event.kind == Kind::ChannelPressure || event.kind == Kind::PitchBend;
        need(single ? 2 : 3);
        event.channel = integer(0, 1, 16);
        if (event.kind <= Kind::PolyPressure) {
            const int pitch = parsePitch(fields[1]);
            if (pitch < 0) bad();
            event.fields = {pitch, integer(2, 0, 127)};
        } else if (event.kind == Kind::PitchBend) {
            event.fields = {integer(1, -8192, 8191)};
        } else {
            event.fields = {integer(1, 0, 127)};
            if (!single) event.fields.push_back(integer(2, 0, 127));
        }
    } else if (textEvent(event.kind)) {
        if (rest.size() < 2 || rest.front() != '"' || rest.back() != '"' || rest.substr(1, rest.size() - 2).find('"') != std::string::npos) bad();
        event.data.assign(rest.begin() + 1, rest.end() - 1);
    } else {
        switch (event.kind) {
            case Kind::Sysex: case Kind::SysexEscape: case Kind::SequencerSpecific: blob(0); break;
            case Kind::Meta:
                if (fields.empty() || fields[0].size() != 2 || !uppercaseHex(fields[0])) bad();
                event.fields = {std::stoi(fields[0], nullptr, 16)};
                if (metaKind(event.fields[0]) != Kind::Meta) bad();
                blob(1);
                break;
            case Kind::SequenceNumber: need(1); event.fields = {integer(0, 0, 65535)}; break;
            case Kind::ChannelPrefix: need(1); event.fields = {integer(0, 1, 16)}; break;
            case Kind::End: need(0); break;
            case Kind::Tempo: need(1); event.fields = {integer(0, 1, 16777215)}; break;
            case Kind::SmpteOffset:
                need(5);
                for (std::size_t i = 0; i < 5; ++i) event.fields.push_back(integer(i, 0, 255));
                break;
            case Kind::TimeSignature: {
                need(3);
                const std::size_t slash = fields[0].find('/');
                const int numerator = std::stoi(fields[0].substr(0, slash));
                const int denominator = std::stoi(fields[0].substr(slash + 1));
                if (!inRange(numerator, 1, 255) || !inRange(denominator, 1, 64) || (denominator & (denominator - 1)) != 0) bad();
                event.fields = {numerator, denominator, integer(1, 0, 255), integer(2, 0, 255)};
                break;
            }
            case Kind::KeySignature: {
                need(2);
                const int mode = fields[1] == "major" ? 0 : fields[1] == "minor" ? 1 : -1;
                if (mode < 0) bad();
                const auto key = std::find(keyNames[mode].begin(), keyNames[mode].end(), fields[0]);
                if (key == keyNames[mode].end()) bad();
                event.fields = {static_cast<int>(key - keyNames[mode].begin()) - 7, mode};
                break;
            }
            default: break;
        }
    }
    return event;
}

Song parseText(const std::vector<std::string>& lines) {
    const std::vector<std::string> header = words(lines[0]);
    if (header.size() != 4 || header[0] != "HEADER") lineError(1, "bad header");
    Song song;
    song.format = std::stoi(header[1]);
    const int count = std::stoi(header[2]);
    song.division = std::stoi(header[3]);
    if (!inRange(song.format, 0, 2) || !inRange(count, 1, 65535) || !inRange(song.division, 1, 32767) || (song.format == 0 && count != 1)) lineError(1, "bad header");
    song.tracks.resize(count);
    int current = 0;
    for (std::size_t i = 1; i < lines.size(); ++i) {
        int track = 0;
        Event event = parseTextEvent(lines[i], i + 1, track);
        if (track >= count) lineError(i + 1, "bad track");
        const bool ended = !song.tracks[current].empty() && song.tracks[current].back().kind == Kind::End;
        if (track < current) lineError(i + 1, "out of order");
        if (track > current && (!ended || track > current + 1)) lineError(i + 1, "missing end of track");
        if (track == current && ended) lineError(i + 1, "event after end of track");
        if (track > current) ++current;
        std::vector<Event>& events = song.tracks[current];
        if (!events.empty() && event.tick < events.back().tick) lineError(i + 1, "out of order");
        events.push_back(std::move(event));
    }
    if (current + 1 < count || song.tracks[current].empty() || song.tracks[current].back().kind != Kind::End) lineError(lines.size() + 1, "missing end of track");
    return song;
}

std::string eventText(const Event& event, std::size_t track) {
    std::ostringstream out;
    out << event.tick << ' ' << track << ' ' << typeNames[static_cast<int>(event.kind)];
    if (channelEvent(event.kind)) {
        out << ' ' << event.channel;
        for (std::size_t i = 0; i < event.fields.size(); ++i) {
            if (i == 0 && event.kind <= Kind::PolyPressure) out << ' ' << pitchName(event.fields[i]);
            else out << ' ' << event.fields[i];
        }
    } else if (textEvent(event.kind)) {
        out << " \"" << std::string(event.data.begin(), event.data.end()) << '"';
    } else if (event.kind == Kind::TimeSignature) {
        out << ' ' << event.fields[0] << '/' << event.fields[1] << ' ' << event.fields[2] << ' ' << event.fields[3];
    } else if (event.kind == Kind::KeySignature) {
        out << ' ' << keyNames[event.fields[1]][event.fields[0] + 7] << ' ' << (event.fields[1] == 0 ? "major" : "minor");
    } else if (event.kind == Kind::Sysex || event.kind == Kind::SysexEscape || event.kind == Kind::SequencerSpecific || event.kind == Kind::Meta) {
        if (event.kind == Kind::Meta) out << ' ' << hex(event.fields[0], 2);
        out << ' ' << event.data.size();
        if (!event.data.empty()) {
            out << ' ';
            for (unsigned char byte : event.data) out << hex(byte, 2);
        }
    } else {
        for (int field : event.fields) out << ' ' << field;
    }
    return out.str();
}

struct EventRef { std::size_t track, index, order; };
const Event& at(const Song& song, EventRef ref) { return song.tracks[ref.track][ref.index]; }
Event& at(Song& song, EventRef ref) { return song.tracks[ref.track][ref.index]; }

std::vector<EventRef> globalOrder(const Song& song) {
    std::vector<EventRef> result;
    for (std::size_t track = 0; track < song.tracks.size(); ++track) {
        for (std::size_t i = 0; i < song.tracks[track].size(); ++i) result.push_back({track, i, 0});
    }
    std::stable_sort(result.begin(), result.end(), [&song](EventRef a, EventRef b) { return at(song, a).tick < at(song, b).tick; });
    for (std::size_t i = 0; i < result.size(); ++i) result[i].order = i;
    return result;
}

struct Note {
    Tick start, length;
    int channel, pitch, velocity;
    EventRef on, off;
};
struct Pairing { std::vector<Note> notes; std::vector<EventRef> unmatched; };

Pairing pairNotes(const Song& song) {
    Pairing result;
    std::map<std::pair<int, int>, std::deque<EventRef>> pending;
    for (EventRef ref : globalOrder(song)) {
        const Event& event = at(song, ref);
        if (noteOn(event)) pending[{event.channel, event.fields[0]}].push_back(ref);
        else if (noteOff(event)) {
            std::deque<EventRef>& queue = pending[{event.channel, event.fields[0]}];
            if (queue.empty()) result.unmatched.push_back(ref);
            else {
                const EventRef onRef = queue.front();
                queue.pop_front();
                const Event& on = at(song, onRef);
                result.notes.push_back({on.tick, event.tick - on.tick, on.channel, on.fields[0], on.fields[1], onRef, ref});
            }
        }
    }
    for (const auto& entry : pending) {
        for (EventRef ref : entry.second) result.unmatched.push_back(ref);
    }
    std::sort(result.notes.begin(), result.notes.end(), [](const Note& a, const Note& b) {
        return std::tie(a.start, a.channel, a.pitch, a.on.order) < std::tie(b.start, b.channel, b.pitch, b.on.order);
    });
    std::sort(result.unmatched.begin(), result.unmatched.end(), [](EventRef a, EventRef b) { return a.order < b.order; });
    return result;
}

std::string milliseconds(const Song& song, Tick tick) {
    Tick sum = 0, last = 0, tempo = 500000;
    for (EventRef ref : globalOrder(song)) {
        const Event& event = at(song, ref);
        if (event.tick > tick) break;
        if (event.kind == Kind::Tempo) {
            sum += (event.tick - last) * tempo;
            last = event.tick;
            tempo = event.fields[0];
        }
    }
    const Tick micros = (sum + (tick - last) * tempo) / song.division;
    std::ostringstream out;
    out << micros / 1000 << '.' << std::setfill('0') << std::setw(3) << micros % 1000;
    return out.str();
}

std::string barPosition(const Song& song, Tick tick) {
    Tick start = 0, bar = 1, numerator = 4, beat = song.division;
    for (EventRef ref : globalOrder(song)) {
        const Event& event = at(song, ref);
        if (event.tick > tick) break;
        if (event.kind == Kind::TimeSignature) {
            const Tick barLength = numerator * beat;
            bar += (event.tick - start + barLength - 1) / barLength;
            start = event.tick;
            numerator = event.fields[0];
            beat = song.division * 4 / event.fields[1];
        }
    }
    const Tick offset = tick - start;
    return std::to_string(bar + offset / (numerator * beat)) + ':' + std::to_string(offset % (numerator * beat) / beat + 1) + ':' + std::to_string(offset % beat);
}

void appendBig(Bytes& bytes, std::uint64_t value, int count) {
    for (int i = count - 1; i >= 0; --i) bytes.push_back(static_cast<unsigned char>((value >> (8 * i)) & 255));
}

void appendVariable(Bytes& bytes, Tick value) {
    Bytes groups{static_cast<unsigned char>(value & 127)};
    while ((value >>= 7) != 0) groups.push_back(static_cast<unsigned char>((value & 127) | 128));
    bytes.insert(bytes.end(), groups.rbegin(), groups.rend());
}

Bytes metaData(const Event& event) {
    Bytes data;
    switch (event.kind) {
        case Kind::SequenceNumber: appendBig(data, event.fields[0], 2); break;
        case Kind::ChannelPrefix: data.push_back(static_cast<unsigned char>(event.fields[0] - 1)); break;
        case Kind::Tempo: appendBig(data, event.fields[0], 3); break;
        case Kind::SmpteOffset: data.assign(event.fields.begin(), event.fields.end()); break;
        case Kind::TimeSignature: {
            int exponent = 0;
            while ((1 << exponent) != event.fields[1]) ++exponent;
            data = {static_cast<unsigned char>(event.fields[0]), static_cast<unsigned char>(exponent), static_cast<unsigned char>(event.fields[2]), static_cast<unsigned char>(event.fields[3])};
            break;
        }
        case Kind::KeySignature: data = {static_cast<unsigned char>(event.fields[0]), static_cast<unsigned char>(event.fields[1])}; break;
        default: data = event.data; break;
    }
    return data;
}

Bytes encode(const Song& song, bool runningEnabled, bool zeroOff) {
    Bytes result{'M', 'T', 'h', 'd'};
    appendBig(result, 6, 4);
    appendBig(result, song.format, 2);
    appendBig(result, song.tracks.size(), 2);
    appendBig(result, song.division, 2);
    for (const std::vector<Event>& track : song.tracks) {
        Bytes data;
        Tick previous = 0;
        int running = -1;
        for (const Event& event : track) {
            appendVariable(data, event.tick - previous);
            previous = event.tick;
            if (channelEvent(event.kind)) {
                int group = static_cast<int>(event.kind) + 8;
                std::vector<int> fields = event.fields;
                if (event.kind == Kind::NoteOff && zeroOff) { group = 9; fields[1] = 0; }
                const int status = group * 16 + event.channel - 1;
                if (!runningEnabled || running != status) data.push_back(static_cast<unsigned char>(status));
                running = status;
                if (event.kind == Kind::PitchBend) {
                    const int value = fields[0] + 8192;
                    data.push_back(static_cast<unsigned char>(value % 128));
                    data.push_back(static_cast<unsigned char>(value / 128));
                } else {
                    for (int field : fields) data.push_back(static_cast<unsigned char>(field));
                }
            } else {
                running = -1;
                if (event.kind == Kind::Sysex || event.kind == Kind::SysexEscape) {
                    data.push_back(event.kind == Kind::Sysex ? 0xF0 : 0xF7);
                    appendVariable(data, event.data.size());
                    data.insert(data.end(), event.data.begin(), event.data.end());
                } else {
                    data.push_back(0xFF);
                    data.push_back(static_cast<unsigned char>(event.kind == Kind::Meta ? event.fields[0] : metaType(event.kind)));
                    const Bytes payload = metaData(event);
                    appendVariable(data, payload.size());
                    data.insert(data.end(), payload.begin(), payload.end());
                }
            }
        }
        result.insert(result.end(), {'M', 'T', 'r', 'k'});
        appendBig(result, data.size(), 4);
        result.insert(result.end(), data.begin(), data.end());
    }
    return result;
}

void printSummary(const Song& song) {
    std::cout << "format " << song.format << " tracks " << song.tracks.size() << " division " << song.division << " events " << song.eventCount();
}

Tick floorDiv(Tick value, Tick denominator) {
    Tick quotient = value / denominator;
    if (value % denominator < 0) --quotient;
    return quotient;
}

void transpose(Song& song, int shift, int channel) {
    std::vector<std::string> dropped;
    int kept = 0;
    for (std::size_t t = 0; t < song.tracks.size(); ++t) {
        std::vector<Event> track;
        for (Event event : song.tracks[t]) {
            if (event.kind <= Kind::PolyPressure && (channel == 0 || event.channel == channel)) {
                const int pitch = event.fields[0] + shift;
                if (!inRange(pitch, 0, 127)) {
                    dropped.push_back("dropped " + std::to_string(event.tick) + ' ' + std::to_string(t) + ' ' + typeNames[static_cast<int>(event.kind)] + ' ' + std::to_string(event.channel) + ' ' + pitchName(event.fields[0]));
                    continue;
                }
                event.fields[0] = pitch;
                ++kept;
            }
            track.push_back(std::move(event));
        }
        song.tracks[t] = std::move(track);
    }
    std::cout << "transposed " << kept << " dropped " << dropped.size() << '\n';
    for (const std::string& line : dropped) std::cout << line << '\n';
}

void quantize(Song& song, Tick grid, int strength) {
    const Pairing pairing = pairNotes(song);
    std::size_t targets = pairing.notes.size();
    int moved = 0;
    const auto delta = [grid, strength](Tick start) {
        const Tick lower = start / grid * grid;
        const Tick upper = lower + grid;
        const Tick target = start - lower <= upper - start ? lower : upper;
        return floorDiv(2 * (target - start) * strength + 100, 200);
    };
    for (const Note& note : pairing.notes) {
        const Tick shift = delta(note.start);
        at(song, note.on).tick += shift;
        at(song, note.off).tick += shift;
        if (shift != 0) ++moved;
    }
    for (EventRef ref : pairing.unmatched) {
        Event& event = at(song, ref);
        if (noteOn(event)) {
            ++targets;
            const Tick shift = delta(event.tick);
            event.tick += shift;
            if (shift != 0) ++moved;
        }
    }
    for (std::vector<Event>& track : song.tracks) {
        Event ending = track.back();
        track.pop_back();
        std::stable_sort(track.begin(), track.end(), [](const Event& a, const Event& b) { return a.tick < b.tick; });
        if (!track.empty()) ending.tick = std::max(ending.tick, track.back().tick);
        track.push_back(std::move(ending));
    }
    std::cout << "quantized " << targets << " moved " << moved << '\n';
}

void scaleTempo(Song& song, int numerator, int denominator) {
    Song scaled = song;
    int count = 0;
    bool atZero = false;
    const auto convert = [numerator, denominator](Tick value) {
        const Tick result = (2 * value * denominator + numerator) / (2 * numerator);
        if (!inRange(result, 1, 16777215)) fail("tempo out of range");
        return static_cast<int>(result);
    };
    for (std::vector<Event>& track : scaled.tracks) {
        for (Event& event : track) {
            if (event.kind == Kind::Tempo) {
                atZero = atZero || event.tick == 0;
                event.fields[0] = convert(event.fields[0]);
                ++count;
            }
        }
    }
    if (!atZero) {
        Event inserted;
        inserted.kind = Kind::Tempo;
        inserted.fields = {convert(500000)};
        scaled.tracks[0].insert(scaled.tracks[0].begin(), inserted);
    }
    song = std::move(scaled);
    std::cout << "scaled " << count << '\n';
    if (!atZero) std::cout << "inserted " << eventText(song.tracks[0][0], 0) << '\n';
}

void printStats(const Song& song) {
    const Pairing pairing = pairNotes(song);
    printSummary(song);
    std::cout << "\nnotes " << pairing.notes.size() << " unmatched " << pairing.unmatched.size() << '\n';
    int low = 128, high = -1;
    for (int channel = 1; channel <= 16; ++channel) {
        int count = 0, channelLow = 128, channelHigh = -1;
        for (const Note& note : pairing.notes) {
            if (note.channel == channel) {
                ++count;
                channelLow = std::min(channelLow, note.pitch);
                channelHigh = std::max(channelHigh, note.pitch);
            }
        }
        if (count > 0) {
            std::cout << "channel " << channel << " notes " << count << " range " << pitchName(channelLow) << ' ' << pitchName(channelHigh) << '\n';
            low = std::min(low, channelLow);
            high = std::max(high, channelHigh);
        }
    }
    if (high < 0) std::cout << "range none\n";
    else std::cout << "range " << pitchName(low) << ' ' << pitchName(high) << '\n';
    std::cout << "length " << song.length() << " ticks " << milliseconds(song, song.length()) << " ms\n";
    std::map<Tick, int> changes;
    for (const Note& note : pairing.notes) {
        if (note.length > 0) { ++changes[note.start]; --changes[note.start + note.length]; }
    }
    int current = 0, maximum = 0;
    Tick first = 0;
    for (const auto& change : changes) {
        current += change.second;
        if (current > maximum) { maximum = current; first = change.first; }
    }
    std::cout << "polyphony " << maximum;
    if (maximum > 0) std::cout << " at " << first;
    std::cout << '\n';
}

void printRoll(const Song& song, Tick from, Tick to, Tick step) {
    const Pairing pairing = pairNotes(song);
    bool printed = false;
    for (int pitch = 127; pitch >= 0; --pitch) {
        std::string row;
        for (Tick column = from; column < to; column += step) {
            char value = '.';
            for (const Note& note : pairing.notes) {
                if (note.pitch != pitch) continue;
                if (column <= note.start && note.start < column + step) { value = '#'; break; }
                if (note.start <= column && column < note.start + note.length) value = '=';
            }
            row.push_back(value);
        }
        if (row.find_first_not_of('.') != std::string::npos) {
            const std::string name = pitchName(pitch);
            std::cout << name << std::string(4 - name.size(), ' ') << ' ' << row << '\n';
            printed = true;
        }
    }
    if (!printed) std::cout << "empty\n";
}

int main() {
    std::ios::sync_with_stdio(false);
    std::cin.tie(nullptr);
    std::string line;
    if (!std::getline(std::cin, line)) return 0;
    const int commands = std::stoi(line);
    std::map<std::string, Song> songs;
    bool running = true, zeroOff = false;
    const std::vector<std::string> known = {
        "HEX", "TEXT", "DECODE", "ENCODE", "TIMING", "NOTES", "STATS", "ROLL",
        "TRANSPOSE", "QUANTIZE", "VELOCITY", "TEMPO", "FILTER", "MERGE", "SPLIT",
        "COPY", "LIST", "RUNNING", "NOTEOFF"
    };
    for (int command = 0; command < commands && std::getline(std::cin, line); ++command) {
        const std::vector<std::string> args = words(line);
        try {
            const std::string& op = args[0];
            if (std::find(known.begin(), known.end(), op) == known.end()) fail("unknown command");
            if (op == "HEX" || op == "TEXT") {
                const int count = std::stoi(args[2]);
                std::vector<std::string> data(count);
                for (std::string& dataLine : data) std::getline(std::cin, dataLine);
                Song song = op == "HEX" ? parseHex(data) : parseText(data);
                songs[args[1]] = std::move(song);
                std::cout << "loaded " << args[1] << ' ';
                printSummary(songs[args[1]]);
                std::cout << '\n';
                continue;
            }
            if (op == "LIST") {
                if (songs.empty()) std::cout << "no songs\n";
                for (const auto& entry : songs) { std::cout << entry.first << ' '; printSummary(entry.second); std::cout << '\n'; }
                continue;
            }
            if (op == "RUNNING" || op == "NOTEOFF") {
                if (op == "RUNNING") {
                    if (args[1] != "ON" && args[1] != "OFF") fail("bad argument");
                    running = args[1] == "ON";
                    std::cout << "running " << (running ? "on" : "off") << '\n';
                } else {
                    if (args[1] != "ZERO" && args[1] != "KEEP") fail("bad argument");
                    zeroOff = args[1] == "ZERO";
                    std::cout << "noteoff " << (zeroOff ? "zero" : "keep") << '\n';
                }
                continue;
            }
            const auto found = songs.find(args[1]);
            if (found == songs.end()) fail("no song " + args[1]);
            Song& song = found->second;
            const auto argument = [&args](std::size_t index, Tick low, Tick high) {
                const Tick value = std::stoll(args[index]);
                if (!inRange(value, low, high)) fail("bad argument");
                return value;
            };
            if (op == "DECODE") {
                std::cout << "HEADER " << song.format << ' ' << song.tracks.size() << ' ' << song.division << '\n';
                for (std::size_t t = 0; t < song.tracks.size(); ++t) {
                    for (const Event& event : song.tracks[t]) std::cout << eventText(event, t) << '\n';
                }
            } else if (op == "ENCODE") {
                const Bytes bytes = encode(song, running, zeroOff);
                for (std::size_t i = 0; i < bytes.size(); i += 16) {
                    std::cout << hex(i, 4) << ':';
                    for (std::size_t j = i; j < std::min(i + 16, bytes.size()); ++j) std::cout << ' ' << hex(bytes[j], 2);
                    std::cout << '\n';
                }
                std::cout << bytes.size() << " bytes\n";
            } else if (op == "TIMING") {
                if (song.format == 2) fail("format 2 not supported");
                for (EventRef ref : globalOrder(song)) {
                    const Event& event = at(song, ref);
                    std::cout << event.tick << ' ' << ref.track << ' ' << typeNames[static_cast<int>(event.kind)] << ' ' << milliseconds(song, event.tick) << ' ' << barPosition(song, event.tick) << '\n';
                }
                const Tick end = song.length();
                std::cout << "end " << end << ' ' << milliseconds(song, end) << ' ' << barPosition(song, end) << '\n';
            } else if (op == "NOTES") {
                const Pairing pairing = pairNotes(song);
                std::cout << "notes " << pairing.notes.size() << " unmatched " << pairing.unmatched.size() << '\n';
                for (const Note& note : pairing.notes) std::cout << note.start << ' ' << note.length << ' ' << note.channel << ' ' << pitchName(note.pitch) << ' ' << note.velocity << '\n';
                for (EventRef ref : pairing.unmatched) {
                    const Event& event = at(song, ref);
                    std::cout << "unmatched " << (noteOn(event) ? "on" : "off") << ' ' << event.tick << ' ' << ref.track << ' ' << event.channel << ' ' << pitchName(event.fields[0]) << '\n';
                }
            } else if (op == "TRANSPOSE") {
                const int shift = static_cast<int>(argument(2, -127, 127));
                const int channel = args.size() == 4 ? static_cast<int>(argument(3, 1, 16)) : 0;
                transpose(song, shift, channel);
            } else if (op == "QUANTIZE") {
                const Tick grid = argument(2, 1, 1000000);
                const int strength = static_cast<int>(argument(3, 0, 100));
                quantize(song, grid, strength);
            } else if (op == "VELOCITY") {
                const Tick percent = argument(2, 0, 1000);
                const int offset = static_cast<int>(argument(3, -127, 127));
                int count = 0, clamped = 0;
                for (std::vector<Event>& track : song.tracks) {
                    for (Event& event : track) {
                        if (!noteOn(event)) continue;
                        const int value = static_cast<int>((event.fields[1] * percent + 50) / 100 + offset);
                        if (!inRange(value, 1, 127)) ++clamped;
                        event.fields[1] = std::clamp(value, 1, 127);
                        ++count;
                    }
                }
                std::cout << "velocity " << count << " clamped " << clamped << '\n';
            } else if (op == "TEMPO") {
                const int numerator = static_cast<int>(argument(2, 1, 1000));
                const int denominator = static_cast<int>(argument(3, 1, 1000));
                scaleTempo(song, numerator, denominator);
            } else if (op == "FILTER") {
                std::array<bool, 17> keep{};
                for (std::size_t i = 2; i < args.size(); ++i) keep[argument(i, 1, 16)] = true;
                std::size_t removed = 0;
                for (std::vector<Event>& track : song.tracks) {
                    const std::size_t before = track.size();
                    track.erase(std::remove_if(track.begin(), track.end(), [&keep](const Event& event) { return channelEvent(event.kind) && !keep[event.channel]; }), track.end());
                    removed += before - track.size();
                }
                std::cout << "removed " << removed << '\n';
            } else if (op == "MERGE") {
                if (song.format != 1) fail("not format 1");
                const std::size_t count = song.tracks.size();
                const Tick length = song.length();
                std::vector<Event> track;
                for (EventRef ref : globalOrder(song)) if (at(song, ref).kind != Kind::End) track.push_back(at(song, ref));
                Event ending;
                ending.tick = length;
                track.push_back(ending);
                song.tracks = {std::move(track)};
                song.format = 0;
                std::cout << "merged " << count << " tracks events " << song.eventCount() << '\n';
            } else if (op == "SPLIT") {
                if (song.format != 0) fail("not format 0");
                const Tick length = song.length();
                std::vector<Event> other;
                std::map<int, std::vector<Event>> channels;
                for (const Event& event : song.tracks[0]) {
                    if (event.kind == Kind::End) continue;
                    if (channelEvent(event.kind)) channels[event.channel].push_back(event);
                    else other.push_back(event);
                }
                song.tracks = {std::move(other)};
                for (auto& entry : channels) song.tracks.push_back(std::move(entry.second));
                for (std::vector<Event>& track : song.tracks) { Event ending; ending.tick = length; track.push_back(ending); }
                song.format = 1;
                std::cout << "split tracks " << song.tracks.size() << " events " << song.eventCount() << '\n';
            } else if (op == "STATS") {
                if (song.format == 2) fail("format 2 not supported");
                printStats(song);
            } else if (op == "ROLL") {
                const Tick from = argument(2, 0, 10000000);
                const Tick to = argument(3, 1, 10000000);
                const Tick step = argument(4, 1, 10000000);
                if (to <= from || (to - from + step - 1) / step > 64) fail("bad argument");
                printRoll(song, from, to, step);
            } else if (op == "COPY") {
                songs[args[2]] = song;
                std::cout << "copied " << args[1] << " to " << args[2] << '\n';
            }
        } catch (const std::runtime_error& error) {
            std::cout << "error: " << error.what() << '\n';
        }
    }
}
