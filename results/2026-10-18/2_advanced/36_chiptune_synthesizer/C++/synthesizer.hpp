#ifndef SYNTHESIZER_HPP
#define SYNTHESIZER_HPP
#include <algorithm>
#include <array>
#include <cstdint>
#include <fstream>
#include <functional>
#include <iomanip>
#include <map>
#include <numeric>
#include <set>
#include <sstream>
#include <string>
#include <utility>
#include <vector>
using Integer = std::int64_t;
using Lines = std::vector<std::string>;
Integer floor_div(Integer a, Integer b);
Integer modulo(Integer a, Integer b);
Integer clamp(Integer value, Integer lo, Integer hi);
std::string decimal(Integer value);
std::string hexadecimal(Integer value, int width = 2);
std::string join(const Lines &values, const std::string &delimiter);
std::string aligned(Integer value, int width);
Lines read_lines(const std::string &path);
void write_lines(const std::string &name, const Lines &lines);
int note_number(const std::string &name);
std::string note_name(int note);
struct Effect {
    std::string text = "...", name;
    int argument = 0, x = 0, y = 0;
};
struct Cell {
    int note = -1, instrument = 0, volume = -1;
    Effect effect;
    bool empty() const;
};
using Row = std::array<Cell, 4>;
using Pattern = std::array<Row, 64>;
struct Instrument {
    int number = 0;
    std::string name, wave;
    int mode = 0;
    std::array<int, 32> table{};
    int attack = 0, decay = 0, sustain = 0, release = 0;
    bool vibrato = false;
    int delay = 0, speed = 0, depth = 0;
    std::vector<int> arpeggio;
    int sweep = 0;
};
struct Song {
    std::string title;
    int rate = 0, speed = 0, tempo = 0, gain = 0;
    std::map<int, Instrument> instruments;
    std::map<int, Pattern> patterns;
    std::vector<int> order;
};
struct Params {
    int maximum = 0, loops = 0, fade = 0;
    std::array<bool, 4> muted{};
    int start = 0, length = 0, width = 0, height = 0, scope = 0, roll_start = 0, roll_rows = 0,
        preview_note = 0, preview_ticks = 0, preview_release = 0;
    std::set<std::pair<int, int>> traces;
};
Song read_song();
Params read_params();
Integer frequency(int note);
Integer transpose(Integer frequency, int semitones);
Integer oscillation(Integer position, Integer depth, Integer divisor);
Integer envelope(const Instrument &instrument, Integer age, bool released, Integer release_age,
                 Integer release_value);
Integer waveform(const Instrument &instrument, int mode, Integer phase, Integer noise);
void clock_noise(Integer &noise, int mode);
struct Channel {
    int instrument = 0, note = -1;
    Integer base = 0, target = 0, portamento = 0, slide = 0, detune = 0, vibrato_speed = 0, vibrato_depth = 0,
            vibrato_position = 0, tremolo_speed = 0, tremolo_depth = 0, tremolo_position = 0, volume = 15;
    int mode = 0;
    Integer phase = 0, noise = 1, age = 0;
    bool released = false;
    Integer release_age = 0, release_value = 0, env = 0, output_frequency = 0, output_volume = 0,
            amplitude = 0, increment = 0;
    Effect effect;
    bool sounding = false;
    int record = -1;
};
struct NextRow {
    int position, row;
    bool stop = false;
};
int samples_per_tick(const Song &song, int tempo);
NextRow next_row(const Song &song, int position, int row);
std::vector<std::array<bool, 64>> reachable(const Song &song);
void generate(const Song &song, std::array<Channel, 4> &channels, int count, const std::array<bool, 4> &muted,
              std::vector<int> &samples, std::array<std::vector<Integer>, 4> &lanes, Integer &clipped);
void fade(std::vector<int> &samples, int count);
Integer adler32(const std::vector<int> &samples);
Integer integer_sqrt(Integer value);
struct SampleStats {
    Integer peak = 0, rms = 0, crossings = 0;
    int minimum = 0, maximum = 0;
};
SampleStats sample_stats(const std::vector<int> &samples);
Lines sample_dump(const std::vector<int> &samples);
#endif
