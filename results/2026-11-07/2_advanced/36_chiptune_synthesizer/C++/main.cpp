#include "synthesizer.hpp"
static Integer magnitude(Integer value) {
    return value < 0 ? -value : value;
}
static void compute_output(const Song &song, Channel &channel, int tick) {
    channel.sounding = channel.note >= 0;
    if (!channel.sounding)
        return;
    const Instrument &i = song.instruments.at(channel.instrument);
    const Effect &e = channel.effect;
    int semitones = e.name == "0" ? (tick % 3 == 0 ? 0 : tick % 3 == 1 ? e.x : e.y) : 0;
    if (!i.arpeggio.empty())
        semitones += i.arpeggio[channel.age % i.arpeggio.size()];
    Integer f = transpose(channel.base, semitones) + channel.detune;
    if (e.name == "4" || e.name == "6")
        f += oscillation(channel.vibrato_position, channel.vibrato_depth, 4);
    if (i.vibrato && channel.age >= i.delay)
        f += oscillation(((channel.age - i.delay) * i.speed) % 64, i.depth, 4);
    channel.output_frequency = clamp(f, 1000, 50 * song.rate);
    channel.env = envelope(i, channel.age, channel.released, channel.release_age, channel.release_value);
    channel.output_volume =
        e.name == "7"
            ? clamp(channel.volume + oscillation(channel.tremolo_position, channel.tremolo_depth, 255), 0, 15)
            : channel.volume;
    channel.amplitude = channel.env * channel.output_volume;
    channel.increment = floor_div(channel.output_frequency * 65536, 100 * song.rate);
}
struct NoteRecord {
    int channel, position, row, instrument, note;
    Integer start, length = 0, release = -1;
    std::string end;
};
struct RowRecord {
    int position, pattern, row;
    Integer start;
    int speed, tempo;
    std::array<int, 4> notes;
};
struct ChannelStats {
    Integer notes = 0, retriggers = 0, cuts = 0, active = 0, audible = 0;
};
class Playback {
  public:
    const Song &song;
    const Params &params;
    std::array<Channel, 4> channels;
    std::array<ChannelStats, 4> channel_stats;
    std::array<std::vector<Integer>, 4> lanes;
    std::vector<int> samples;
    std::vector<NoteRecord> notes;
    std::vector<RowRecord> rows;
    Lines logs, warnings;
    std::array<Integer, 256> instrument_ticks{};
    std::map<std::string, Integer> effects;
    std::vector<std::array<int, 64>> played;
    std::vector<std::array<Integer, 64>> first;
    Integer ticks = 0, clipped = 0, loop_start = -1;
    std::string end;
    int position = 0, row = 0, speed, tempo;
    Playback(const Song &s, const Params &p)
        : song(s), params(p), played(s.order.size()), first(s.order.size()), speed(s.speed), tempo(s.tempo) {
        for (auto &values : first)
            values.fill(-1);
    }
    void warn(int channel, const std::string &message) {
        warnings.push_back("warning " + hexadecimal(position) + ":" + hexadecimal(row) + " ch" +
                           decimal(channel + 1) + " " + message);
    }
    void end_record(Channel &channel, const std::string &reason) {
        if (channel.record < 0)
            return;
        NoteRecord &record = notes[channel.record];
        record.length = Integer(samples.size()) - record.start;
        record.end = reason;
        channel.record = -1;
    }
    void note_on(int k, int note) {
        Channel &c = channels[k];
        end_record(c, "next");
        c.base = c.target = frequency(note);
        c.phase = c.age = c.vibrato_position = c.tremolo_position = 0;
        c.released = false;
        c.note = note;
        c.record = notes.size();
        notes.push_back({k, position, row, c.instrument, note, Integer(samples.size())});
        ++channel_stats[k].notes;
    }
    void key_off(Channel &c) {
        c.release_age = c.age;
        c.release_value = c.env;
        c.released = true;
        if (c.record >= 0)
            notes[c.record].release = Integer(samples.size()) - notes[c.record].start;
    }
    void content(int k, const Cell &cell, bool portamento) {
        Channel &c = channels[k];
        if (cell.instrument) {
            const auto found = song.instruments.find(cell.instrument);
            if (found == song.instruments.end())
                warn(k, "undefined instrument " + hexadecimal(cell.instrument));
            else {
                c.instrument = cell.instrument;
                c.volume = 15;
                c.mode = found->second.mode;
            }
        }
        if (cell.volume >= 0)
            c.volume = cell.volume;
        if (cell.note == -2) {
            if (c.note >= 0 && !c.released)
                key_off(c);
            else
                warn(k, "key off without note");
        } else if (cell.note >= 0) {
            if (c.instrument == 0)
                warn(k, "note without instrument");
            else if (portamento && c.note >= 0) {
                c.target = frequency(cell.note);
                c.note = cell.note;
            } else {
                if (portamento)
                    warn(k, "portamento without note");
                note_on(k, cell.note);
            }
        }
    }
    void approach(Channel &c, Integer step_) {
        c.base = c.base < c.target ? std::min(c.base + step_, c.target) : std::max(c.base - step_, c.target);
    }
    void effect_zero(int k, int &delay) {
        Channel &c = channels[k];
        const Effect &e = c.effect;
        const int argument = e.argument;
        if (e.name == "3") {
            if (argument > 0)
                c.portamento = argument;
        } else if (e.name == "4") {
            if (e.x > 0)
                c.vibrato_speed = e.x;
            if (e.y > 0)
                c.vibrato_depth = e.y;
        } else if (e.name == "7") {
            if (e.x > 0)
                c.tremolo_speed = e.x;
            if (e.y > 0)
                c.tremolo_depth = e.y;
        } else if (e.name == "C")
            c.volume = std::min(argument, 15);
        else if (e.name == "E1")
            c.base = clamp(c.base + 10 * argument, 1000, 50 * song.rate);
        else if (e.name == "E2")
            c.base = clamp(c.base - 10 * argument, 1000, 50 * song.rate);
        else if (e.name == "EA")
            c.volume = std::min(c.volume + argument, Integer(15));
        else if (e.name == "EB")
            c.volume = std::max(c.volume - argument, Integer(0));
        else if (e.name == "EE")
            delay = argument;
        else if (e.name == "F") {
            if (argument >= 1 && argument <= 31)
                speed = argument;
            else if (argument >= 32)
                tempo = argument;
        } else if (e.name == "P")
            c.detune = argument - 128;
        else if (e.name == "Q" || e.name == "R") {
            if (c.note < 0)
                warn(k, "slide without note");
            else {
                c.note = e.name == "Q" ? std::min(c.note + e.y, 95) : std::max(c.note - e.y, 12);
                c.target = frequency(c.note);
                c.slide = 2 * e.x + 1;
            }
        } else if (e.name == "V") {
            if (c.instrument && ((song.instruments.at(c.instrument).wave == "PULSE" && argument <= 3) ||
                                 (song.instruments.at(c.instrument).wave == "NOISE" && argument <= 1)))
                c.mode = argument;
            else
                warn(k, "invalid mode " + hexadecimal(argument));
        }
    }
    int row_start(const Row &cells) {
        int delay = 0;
        for (int k = 0; k < 4; ++k) {
            Channel &c = channels[k];
            c.effect = cells[k].effect;
            c.slide = 0;
            if (!c.effect.name.empty())
                ++effects[c.effect.name];
            if (c.effect.name != "ED" || c.effect.argument < 1)
                content(k, cells[k], c.effect.name == "3" || c.effect.name == "5");
            effect_zero(k, delay);
        }
        const int count = speed * (1 + delay);
        for (int k = 0; k < 4; ++k) {
            const Effect &e = channels[k].effect;
            if (e.name == "EC" && e.argument >= count)
                warn(k, "cut beyond row");
            if (e.name == "ED" && e.argument >= count)
                warn(k, "delay beyond row");
        }
        return count;
    }
    void process_tick(const Row &cells, int tick) {
        for (int k = 0; k < 4; ++k) {
            Channel &c = channels[k];
            const Effect &e = c.effect;
            if (c.note >= 0 && c.age >= 1) {
                const int sweep = song.instruments.at(c.instrument).sweep;
                if (sweep)
                    c.base = clamp(c.base + 10 * sweep, 1000, 50 * song.rate);
            }
            if (tick >= 1) {
                if (e.name == "1")
                    c.base = clamp(c.base + 10 * e.argument, 1000, 50 * song.rate);
                else if (e.name == "2")
                    c.base = clamp(c.base - 10 * e.argument, 1000, 50 * song.rate);
                else if (e.name == "3")
                    approach(c, 10 * c.portamento);
                else if (e.name == "5") {
                    approach(c, 10 * c.portamento);
                    c.volume = clamp(c.volume + e.x - e.y, 0, 15);
                } else if (e.name == "6" || e.name == "A")
                    c.volume = clamp(c.volume + e.x - e.y, 0, 15);
                else if ((e.name == "Q" || e.name == "R") && c.slide)
                    approach(c, 10 * c.slide);
            }
            if (e.name == "ED" && e.argument >= 1 && tick == e.argument)
                content(k, cells[k], false);
            if (e.name == "E9" && e.argument >= 1 && tick >= 1 && tick % e.argument == 0 && c.note >= 0) {
                c.phase = c.age = 0;
                c.released = false;
                ++channel_stats[k].retriggers;
            }
            if (e.name == "EC" && tick == e.argument && c.note >= 0) {
                c.note = -1;
                end_record(c, "cut");
                ++channel_stats[k].cuts;
            }
            compute_output(song, c, tick);
            if (c.sounding) {
                ++channel_stats[k].active;
                if (c.amplitude > 0)
                    ++channel_stats[k].audible;
                ++instrument_ticks[c.instrument];
            }
        }
    }
    std::string channel_line(const Channel &c) const {
        if (c.note < 0)
            return "--- --       - - " + hexadecimal(c.volume, 1) + " " + c.effect.text;
        return note_name(c.note) + " " + hexadecimal(c.instrument) + " " + aligned(c.output_frequency, 7) +
               " " + hexadecimal(c.env, 1) + " " + hexadecimal(c.output_volume, 1) + " " + c.effect.text;
    }
    std::string tick_line(const Channel &c) const {
        return c.sounding ? aligned(c.output_frequency, 7) + " " + aligned(c.increment, 5) + " " +
                                hexadecimal(c.env, 1) + hexadecimal(c.output_volume, 1)
                          : "      -     - --";
    }
    void run() {
        while (true) {
            const Integer start = samples.size();
            if (first[position][row] < 0)
                first[position][row] = start;
            ++played[position][row];
            const Row &cells = song.patterns.at(song.order[position])[row];
            const int count = row_start(cells), spt = samples_per_tick(song, tempo);
            RowRecord record{position, song.order[position], row, start, speed, tempo, {}};
            bool limited = false;
            for (int tick = 0; tick < count; ++tick) {
                process_tick(cells, tick);
                if (tick == 0) {
                    Lines states;
                    for (int k = 0; k < 4; ++k) {
                        states.push_back(channel_line(channels[k]));
                        record.notes[k] = channels[k].note;
                    }
                    logs.push_back(hexadecimal(position) + " " + hexadecimal(song.order[position]) + " " +
                                   hexadecimal(row) + " " + aligned(start, 7) + " " + aligned(speed, 2) +
                                   " " + aligned(tempo, 3) + " | " + join(states, " | "));
                }
                if (params.traces.count({position, row})) {
                    Lines states;
                    for (const Channel &c : channels)
                        states.push_back(tick_line(c));
                    logs.push_back("  tick " + aligned(tick, 3) + " " + aligned(samples.size(), 7) + " | " +
                                   join(states, " | "));
                }
                generate(song, channels, std::min(spt, params.maximum - int(samples.size())), params.muted,
                         samples, lanes, clipped);
                ++ticks;
                for (Channel &c : channels) {
                    if (c.note >= 0)
                        ++c.age;
                    if (c.effect.name == "4" || c.effect.name == "6")
                        c.vibrato_position = (c.vibrato_position + c.vibrato_speed) % 64;
                    if (c.effect.name == "7")
                        c.tremolo_position = (c.tremolo_position + c.tremolo_speed) % 64;
                }
                if (int(samples.size()) == params.maximum) {
                    end = "limit";
                    limited = true;
                    break;
                }
            }
            rows.push_back(record);
            if (limited)
                break;
            const NextRow next = next_row(song, position, row);
            if (next.stop) {
                end = "stop order=" + hexadecimal(position) + " row=" + hexadecimal(row);
                break;
            }
            if (next.position >= int(song.order.size())) {
                end = "finished";
                break;
            }
            if (played[next.position][next.row] >= params.loops) {
                loop_start = first[next.position][next.row];
                end = "loop order=" + hexadecimal(next.position) + " row=" + hexadecimal(next.row);
                break;
            }
            position = next.position;
            row = next.row;
        }
        for (Channel &c : channels)
            end_record(c, "end");
        if ((end == "limit" || end.rfind("loop ", 0) == 0) && params.fade > 0)
            fade(samples, params.fade);
    }
};
static Lines note_lines(const Playback &p) {
    Lines out;
    for (std::size_t i = 0; i < p.notes.size(); ++i) {
        const NoteRecord &r = p.notes[i];
        Integer peak = 0, cycles = 0;
        const auto &lane = p.lanes[r.channel];
        for (Integer sample = r.start; sample < r.start + r.length; ++sample) {
            peak = std::max(peak, magnitude(lane[sample]));
            if (sample > r.start && lane[sample - 1] < 0 && lane[sample] >= 0)
                ++cycles;
        }
        out.push_back(aligned(i + 1, 4) + " ch=" + decimal(r.channel + 1) + " at=" + hexadecimal(r.position) +
                      ":" + hexadecimal(r.row) + " ins=" + hexadecimal(r.instrument) + " note=" +
                      note_name(r.note) + " start=" + decimal(r.start) + " length=" + decimal(r.length) +
                      " release=" + (r.release < 0 ? "-" : decimal(r.release)) + " end=" + r.end +
                      " peak=" + decimal(peak) + " cycles=" + decimal(cycles));
    }
    return out;
}
static Lines roll_lines(const Playback &p) {
    const int first = std::min(p.params.roll_start, int(p.rows.size())),
              end = std::min(int(p.rows.size()), p.params.roll_start + p.params.roll_rows),
              count = end - first;
    std::set<int, std::greater<int>> pitches;
    for (int i = first; i < end; ++i)
        for (int note : p.rows[i].notes)
            if (note >= 0)
                pitches.insert(note);
    Lines out = {"ROLL start=" + decimal(p.params.roll_start) + " rows=" + decimal(count) +
                 " pitches=" + decimal(pitches.size())};
    for (int note : pitches) {
        std::string marks;
        for (int i = first; i < end; ++i) {
            int channel = -1, number = 0;
            for (int k = 0; k < 4; ++k)
                if (p.rows[i].notes[k] == note) {
                    channel = k;
                    ++number;
                }
            marks += number == 0 ? ' ' : number == 1 ? char('1' + channel) : '*';
        }
        out.push_back(note_name(note) + " |" + marks + "|");
    }
    std::string axis = "    +";
    for (int i = 0; i < count; ++i)
        axis += i % 16 == 0 ? '+' : '-';
    out.push_back(axis + "+");
    return out;
}
static std::string note_range(const std::vector<const NoteRecord *> &records) {
    if (records.empty())
        return "none";
    int lo = records[0]->note, hi = lo;
    for (const NoteRecord *record : records) {
        lo = std::min(lo, record->note);
        hi = std::max(hi, record->note);
    }
    return note_name(lo) + ".." + note_name(hi);
}
static Lines stats_lines(const Playback &p) {
    const Song &song = p.song;
    const SampleStats stats = sample_stats(p.samples);
    const Integer n = p.samples.size();
    Lines out = {"title=" + song.title,
                 "rate=" + decimal(song.rate),
                 "samples=" + decimal(n),
                 "duration_ms=" + decimal(n * 1000 / song.rate),
                 "end=" + p.end,
                 "loop_start=" + (p.loop_start < 0 ? "-" : decimal(p.loop_start)),
                 "loop_length=" + (p.loop_start < 0 ? "-" : decimal(n - p.loop_start)),
                 "rows=" + decimal(p.rows.size()),
                 "ticks=" + decimal(p.ticks),
                 "clipped=" + decimal(p.clipped),
                 "peak=" + decimal(stats.peak),
                 "min=" + decimal(stats.minimum),
                 "max=" + decimal(stats.maximum),
                 "rms=" + decimal(stats.rms),
                 "zero_crossings=" + decimal(stats.crossings),
                 "adler32=" + hexadecimal(adler32(p.samples), 8)};
    std::string route = "path";
    int previous = -1;
    for (const RowRecord &r : p.rows)
        if (r.position != previous) {
            route += " " + hexadecimal(r.position);
            previous = r.position;
        }
    out.push_back(route);
    int speed = -1, tempo = -1;
    for (const RowRecord &r : p.rows)
        if (r.speed != speed || r.tempo != tempo) {
            out.push_back("timing sample=" + decimal(r.start) + " order=" + hexadecimal(r.position) +
                          " row=" + hexadecimal(r.row) + " speed=" + decimal(r.speed) +
                          " tempo=" + decimal(r.tempo));
            speed = r.speed;
            tempo = r.tempo;
        }
    for (int k = 0; k < 4; ++k) {
        Integer peak = 0, squares = 0;
        for (Integer value : p.lanes[k]) {
            peak = std::max(peak, magnitude(value));
            squares += value * value;
        }
        const ChannelStats &s = p.channel_stats[k];
        out.push_back("channel " + decimal(k + 1) + " notes=" + decimal(s.notes) +
                      " retriggers=" + decimal(s.retriggers) + " cuts=" + decimal(s.cuts) +
                      " active=" + decimal(s.active) + " audible=" + decimal(s.audible) +
                      " peak=" + decimal(peak) + " rms=" + decimal(integer_sqrt(squares / n)));
    }
    std::map<int, std::vector<const NoteRecord *>> by_instrument;
    std::map<int, Integer> note_counts;
    for (const NoteRecord &r : p.notes) {
        by_instrument[r.instrument].push_back(&r);
        ++note_counts[r.note];
    }
    for (const auto &entry : song.instruments) {
        const Instrument &i = entry.second;
        const auto &records = by_instrument[entry.first];
        Integer total = 0;
        for (const NoteRecord *r : records)
            total += r->length;
        out.push_back("instrument " + hexadecimal(entry.first) + " " + i.name + " " + i.wave +
                      " notes=" + decimal(records.size()) +
                      " ticks=" + decimal(p.instrument_ticks[entry.first]) + " range=" + note_range(records) +
                      " average=" + (records.empty() ? "-" : decimal(total / Integer(records.size()))));
    }
    std::map<int, Integer> order_counts;
    for (int pattern : song.order)
        ++order_counts[pattern];
    for (const auto &entry : song.patterns) {
        Integer rows = 0, notes = 0;
        for (const Row &row : entry.second) {
            bool any = false;
            for (const Cell &cell : row) {
                if (!cell.empty())
                    any = true;
                if (cell.note != -1)
                    ++notes;
            }
            if (any)
                ++rows;
        }
        out.push_back("pattern " + hexadecimal(entry.first) + " rows=" + decimal(rows) +
                      " notes=" + decimal(notes) + " orders=" + decimal(order_counts[entry.first]));
    }
    const auto reachable_rows = reachable(song);
    for (int position = 0; position < int(song.order.size()); ++position) {
        Integer rows = 0, first = -1, dead = 0;
        for (int row = 0; row < 64; ++row) {
            rows += p.played[position][row];
            if (p.first[position][row] >= 0 && (first < 0 || p.first[position][row] < first))
                first = p.first[position][row];
            if (!reachable_rows[position][row]) {
                bool note = false;
                for (const Cell &cell : song.patterns.at(song.order[position])[row])
                    if (cell.note != -1)
                        note = true;
                if (note)
                    ++dead;
            }
        }
        out.push_back("order " + hexadecimal(position) + " pattern=" + hexadecimal(song.order[position]) +
                      " rows=" + decimal(rows) + " first=" + (first < 0 ? "-" : decimal(first)) +
                      " dead=" + decimal(dead));
    }
    for (const auto &entry : note_counts)
        out.push_back("note " + note_name(entry.first) + " count=" + decimal(entry.second));
    const Lines effect_order = {"0",  "1",  "2",  "3",  "4",  "5",  "6",  "7", "A", "B", "C", "D", "E1",
                                "E2", "E9", "EA", "EB", "EC", "ED", "EE", "F", "P", "Q", "R", "V"};
    std::string effects = "effects";
    for (const std::string &effect : effect_order) {
        const auto found = p.effects.find(effect);
        if (found != p.effects.end())
            effects += " " + effect + "=" + decimal(found->second);
    }
    out.push_back(effects == "effects" ? "effects none" : effects);
    Lines unused_instruments, unused_patterns, unreached_orders;
    for (const auto &entry : song.instruments)
        if (by_instrument[entry.first].empty())
            unused_instruments.push_back(hexadecimal(entry.first));
    for (const auto &entry : song.patterns)
        if (order_counts[entry.first] == 0)
            unused_patterns.push_back(hexadecimal(entry.first));
    for (int position = 0; position < int(song.order.size()); ++position)
        if (std::accumulate(p.played[position].begin(), p.played[position].end(), 0) == 0)
            unreached_orders.push_back(hexadecimal(position));
    out.push_back("unused_instruments=" +
                  (unused_instruments.empty() ? "none" : join(unused_instruments, " ")));
    out.push_back("unused_patterns=" + (unused_patterns.empty() ? "none" : join(unused_patterns, " ")));
    out.push_back("unreached_orders=" + (unreached_orders.empty() ? "none" : join(unreached_orders, " ")));
    std::array<Integer, 12> pitch_classes{};
    for (const NoteRecord &r : p.notes)
        if (song.instruments.at(r.instrument).wave != "NOISE")
            pitch_classes[r.note % 12] += r.length;
    const std::array<std::string, 12> tonics = {"C",  "C#", "D",  "D#", "E",  "F",
                                                "F#", "G",  "G#", "A",  "A#", "B"};
    std::string pitch_line = "pitch_classes";
    for (int j = 0; j < 12; ++j)
        pitch_line += " " + tonics[j] + "=" + decimal(pitch_classes[j]);
    out.push_back(pitch_line);
    const std::array<Integer, 12> major = {64, 22, 35, 23, 44, 41, 25, 52, 24, 37, 23, 29},
                                  minor = {64, 27, 35, 54, 27, 35, 25, 48, 40, 27, 34, 32};
    std::array<Integer, 24> scores{};
    std::vector<int> keys(24);
    std::iota(keys.begin(), keys.end(), 0);
    for (int key = 0; key < 24; ++key)
        for (int j = 0; j < 12; ++j)
            scores[key] += (key < 12 ? major : minor)[modulo(j - key % 12, 12)] * pitch_classes[j];
    std::sort(keys.begin(), keys.end(),
              [&](int a, int b) { return scores[a] != scores[b] ? scores[a] > scores[b] : a < b; });
    auto key_name = [&](int key) { return tonics[key % 12] + (key < 12 ? " major" : " minor"); };
    out.push_back("key=" + key_name(keys[0]) + " score=" + decimal(scores[keys[0]]) +
                  " runner_up=" + key_name(keys[1]) + " score=" + decimal(scores[keys[1]]));
    for (int k = 0; k < 4; ++k) {
        std::vector<const NoteRecord *> records;
        std::map<int, Integer> counts;
        for (const NoteRecord &r : p.notes)
            if (r.channel == k) {
                records.push_back(&r);
                ++counts[r.instrument];
            }
        std::string line = "usage ch" + decimal(k + 1) + " range=" + note_range(records);
        for (const auto &entry : song.instruments)
            line += " " + hexadecimal(entry.first) + "=" + decimal(counts[entry.first]);
        out.push_back(line);
    }
    out.insert(out.end(), p.warnings.begin(), p.warnings.end());
    return out;
}
static Lines waveform_plot(const std::vector<Integer> &values, Integer lo, Integer hi, Integer mid, int width,
                           int height) {
    auto row = [&](Integer value) {
        return int(floor_div(2 * (hi - value) * (height - 1) + (hi - lo), 2 * (hi - lo)));
    };
    const int middle = row(mid);
    std::vector<int> top(width), bottom(width);
    for (int col = 0; col < width; ++col) {
        const std::size_t first = std::size_t(col) * values.size() / width,
                          end = std::size_t(col + 1) * values.size() / width;
        Integer low = values[first], high = low;
        for (std::size_t i = first; i < end; ++i) {
            low = std::min(low, values[i]);
            high = std::max(high, values[i]);
        }
        top[col] = row(high);
        bottom[col] = row(low);
    }
    Lines out;
    for (int r = 0; r < height; ++r) {
        std::string label = r == 0            ? aligned(hi, 5)
                            : r == middle     ? aligned(mid, 5)
                            : r == height - 1 ? aligned(lo, 5)
                                              : std::string(5, ' '),
                    marks;
        for (int col = 0; col < width; ++col)
            marks += top[col] <= r && r <= bottom[col] ? '#' : r == middle ? '-' : ' ';
        out.push_back(label + " |" + marks + "|");
    }
    return out;
}
static Lines axes(const Song &song, const Params &p) {
    std::string first = "      +";
    for (int col = 0; col < p.width; ++col)
        first += col % 10 == 0 ? '+' : '-';
    first += '+';
    std::string second = "    ms";
    for (int col = 0; col < p.width; col += 10) {
        const std::string text =
            decimal((Integer(p.start) + Integer(col) * p.length / p.width) * 1000 / song.rate);
        const std::size_t position = 7 + col;
        second.resize(std::max(second.size(), position + text.size()), ' ');
        second.replace(position, text.size(), text);
    }
    return {first, second};
}
static Lines waveform_lines(const Playback &p) {
    Lines out = {"MIX start=" + decimal(p.params.start) + " length=" + decimal(p.params.length) +
                 " width=" + decimal(p.params.width) + " height=" + decimal(p.params.height)};
    std::vector<Integer> mix;
    for (int i = p.params.start; i < p.params.start + p.params.length; ++i)
        mix.push_back(p.samples[i]);
    const auto add = [&](const Lines &lines) { out.insert(out.end(), lines.begin(), lines.end()); };
    add(waveform_plot(mix, 0, 255, 128, p.params.width, p.params.height));
    add(axes(p.song, p.params));
    for (int k = 0; k < 4; ++k) {
        out.push_back("CHANNEL " + decimal(k + 1));
        const auto &lane = p.lanes[k];
        const std::vector<Integer> values(lane.begin() + p.params.start,
                                          lane.begin() + p.params.start + p.params.length);
        add(waveform_plot(values, -3375, 3375, 0, p.params.width, p.params.scope));
    }
    add(axes(p.song, p.params));
    return out;
}
static Lines preview_lines(const Song &song, const Params &p) {
    Lines out;
    const int spt = samples_per_tick(song, song.tempo);
    for (const auto &entry : song.instruments) {
        const Instrument &i = entry.second;
        std::array<Channel, 4> channels;
        Channel &c = channels[0];
        c.instrument = entry.first;
        c.mode = i.mode;
        c.note = p.preview_note;
        c.base = c.target = frequency(c.note);
        std::vector<int> samples;
        std::array<std::vector<Integer>, 4> lanes;
        Integer clipped = 0;
        std::string env;
        Lines frequencies;
        for (int tick = 0; tick < p.preview_ticks; ++tick) {
            if (tick == p.preview_release) {
                c.released = true;
                c.release_age = tick;
                c.release_value = c.env;
            }
            if (tick >= 1 && i.sweep)
                c.base = clamp(c.base + 10 * i.sweep, 1000, 50 * song.rate);
            c.age = tick;
            compute_output(song, c, tick);
            env += hexadecimal(c.env, 1);
            frequencies.push_back(decimal(c.output_frequency));
            generate(song, channels, spt, {}, samples, lanes, clipped);
        }
        const SampleStats stats = sample_stats(samples);
        out.push_back("instrument " + hexadecimal(entry.first) + " " + i.name + " wave=" + i.wave +
                      " samples=" + decimal(samples.size()) + " peak=" + decimal(stats.peak) +
                      " rms=" + decimal(stats.rms) + " adler32=" + hexadecimal(adler32(samples), 8));
        out.push_back("  env " + env);
        out.push_back("  freq " + join(frequencies, " "));
    }
    return out;
}
int main() {
    const Song song = read_song();
    const Params params = read_params();
    Playback playback(song, params);
    playback.run();
    write_lines("samples.txt", sample_dump(playback.samples));
    write_lines("channel_log.txt", playback.logs);
    write_lines("notes.txt", note_lines(playback));
    write_lines("roll.txt", roll_lines(playback));
    write_lines("stats.txt", stats_lines(playback));
    write_lines("waveform.txt", waveform_lines(playback));
    write_lines("instruments.txt", preview_lines(song, params));
}
