using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Program {

    public static readonly string[] EFFECT_ORDER = { "0",  "1",  "2", "3",  "4",  "5",  "6",  "7",  "A",
                                                     "B",  "C",  "D", "E1", "E2", "E9", "EA", "EB", "EC",
                                                     "ED", "EE", "F", "P",  "Q",  "R",  "V" };
    public static readonly string[] TONICS = { "C",  "C#", "D",  "D#", "E",  "F",
                                               "F#", "G",  "G#", "A",  "A#", "B" };
    public static readonly int[] MAJOR = { 64, 22, 35, 23, 44, 41, 25, 52, 24, 37, 23, 29 },
                                 MINOR = { 64, 27, 35, 54, 27, 35, 25, 48, 40, 27, 34, 32 };
    public sealed class Channel {
        public SongParser.Instrument instrument;
        public int note = -1, portamentoSpeed, slideSpeed, detune, vibratoSpeed, vibratoDepth,
                   vibratoPosition, tremoloSpeed, tremoloDepth, tremoloPosition, volume = 15, mode, phase,
                   shift = 1, age, releaseAge, releaseValue, envelope, outputVolume, amplitude, increment;
        public long frequency, target, outputFrequency;
        public bool off, sounding;
        public SongParser.Effect effect = SongParser.ParseEffect("...");
        public SongParser.Cell cell;
        public Note record;
    }
    public sealed class Note {
        public int serial, channel, position, row, instrument, note, start, length, release = -1;
        public string reason;
        public Note(int serial, int channel, int position, int row, int instrument, int note, int start) {
            this.serial = serial;
            this.channel = channel;
            this.position = position;
            this.row = row;
            this.instrument = instrument;
            this.note = note;
            this.start = start;
        }
    }
    public sealed record Row(int position, int row, int start, int speed, int tempo, int[] notes);
    public static void Output(Channel c, int tick, int rate) {
        c.sounding = c.note >= 0;
        if (!c.sounding)
            return;
        SongParser.Instrument instrument = c.instrument;
        int semitones = c.effect.name.Equals("0") ? tick % 3 == 1   ? c.effect.x
                                                    : tick % 3 == 2 ? c.effect.y
                                                                    : 0
                                                  : 0;
        if (instrument.arpeggio.Length > 0)
            semitones += instrument.arpeggio[c.age % instrument.arpeggio.Length];
        long frequency = Instruments.Transpose(c.frequency, semitones) + c.detune;
        if (c.effect.name.Equals("4") || c.effect.name.Equals("6"))
            frequency += Instruments.Oscillate(c.vibratoPosition, c.vibratoDepth, 4);
        if (instrument.vibratoDelay >= 0 && c.age >= instrument.vibratoDelay)
            frequency += Instruments.Oscillate(
                (c.age - instrument.vibratoDelay) * instrument.vibratoSpeed % 64, instrument.vibratoDepth, 4);
        c.outputFrequency = Instruments.Clamp(frequency, 1000, 50L * rate);
        c.envelope = Instruments.Envelope(instrument, c.age, c.off, c.releaseAge, c.releaseValue);
        c.outputVolume =
            c.effect.name.Equals("7")
                ? (int)Instruments.Clamp(
                      c.volume + Instruments.Oscillate(c.tremoloPosition, c.tremoloDepth, 255), 0, 15)
                : c.volume;
        c.amplitude = c.envelope * c.outputVolume;
        c.increment = (int)(c.outputFrequency * 65536 / (100L * rate));
    }
    public sealed class Player {
        public readonly SongParser.Song song;
        public readonly SongParser.Settings settings;
        public readonly Channel[] channels = new Channel[4];
        public readonly Mixer mixer;
        public readonly List<Note> notes = new();
        public readonly List<Row> rows = new();
        public readonly List<string> warnings = new(), log = new();
        public readonly long[] retriggers = new long[4], cuts = new long[4], active = new long[4],
                               audible = new long[4];
        public readonly Dictionary<int, long> instrumentTicks = new();
        public readonly Dictionary<string, int> effects = new();
        public int position, row, speed, tempo, delay, ticks;
        public string reason = "finished";
        public int loopStart = -1;
        public Player(SongParser.Song song, SongParser.Settings settings) {
            this.song = song;
            this.settings = settings;
            speed = song.speed;
            tempo = song.tempo;
            for (int i = 0; i < 4; i++)
                channels[i] = new Channel();
            mixer = new Mixer(settings.Integer("max_samples"), 4, song.gain, settings.Numbers("mute"));
        }
        public void Warning(int channel, string message) {
            warnings.Add("warning " + Report.Hex2(position) + ":" + Report.Hex2(row) + " ch" + (channel + 1) +
                         " " + message);
        }
        public void Finish(Channel channel, string reason) {
            if (channel.record != null) {
                channel.record.length = mixer.size - channel.record.start;
                channel.record.reason = reason;
                channel.record = null;
            }
        }
        public void NoteOn(int index, int note) {
            Channel c = channels[index];
            Finish(c, "next");
            c.frequency = Instruments.Frequency(note);
            c.target = c.frequency;
            c.phase = 0;
            c.age = 0;
            c.vibratoPosition = 0;
            c.tremoloPosition = 0;
            c.off = false;
            c.note = note;
            Note record =
                new Note(notes.Count + 1, index + 1, position, row, c.instrument.number, note, mixer.size);
            notes.Add(record);
            c.record = record;
        }
        public void Content(int index, bool portamento) {
            Channel c = channels[index];
            SongParser.Cell cell = c.cell;
            if (cell.instrument != 0) {
                SongParser.Instrument instrument = song.instruments.GetValueOrDefault(cell.instrument);
                if (instrument == null)
                    Warning(index, "undefined instrument " + Report.Hex2(cell.instrument));
                else {
                    c.instrument = instrument;
                    c.volume = 15;
                    c.mode = instrument.mode;
                }
            }
            if (cell.volume >= 0)
                c.volume = cell.volume;
            if (cell.note == -1) {
                if (c.note >= 0 && !c.off) {
                    c.off = true;
                    c.releaseAge = c.age;
                    c.releaseValue = c.envelope;
                    if (c.record != null)
                        c.record.release = mixer.size - c.record.start;
                } else
                    Warning(index, "key off without note");
            } else if (cell.note >= 0) {
                if (c.instrument == null)
                    Warning(index, "note without instrument");
                else if (portamento && c.note >= 0) {
                    c.target = Instruments.Frequency(cell.note);
                    c.note = cell.note;
                } else {
                    if (portamento && c.note < 0)
                        Warning(index, "portamento without note");
                    NoteOn(index, cell.note);
                }
            }
        }
        public void TickZero(int index) {
            Channel c = channels[index];
            SongParser.Effect e = c.effect;
            int argument = e.argument, x = e.x, y = e.y;
            string name = e.name;
            if (name.Equals("3")) {
                if (argument > 0)
                    c.portamentoSpeed = argument;
            } else if (name.Equals("4")) {
                if (x > 0)
                    c.vibratoSpeed = x;
                if (y > 0)
                    c.vibratoDepth = y;
            } else if (name.Equals("7")) {
                if (x > 0)
                    c.tremoloSpeed = x;
                if (y > 0)
                    c.tremoloDepth = y;
            } else if (name.Equals("C"))
                c.volume = Math.Min(argument, 15);
            else if (name.Equals("E1"))
                c.frequency = Instruments.Clamp(c.frequency + 10 * y, 1000, 50L * song.rate);
            else if (name.Equals("E2"))
                c.frequency = Instruments.Clamp(c.frequency - 10 * y, 1000, 50L * song.rate);
            else if (name.Equals("EA"))
                c.volume = Math.Min(c.volume + y, 15);
            else if (name.Equals("EB"))
                c.volume = Math.Max(c.volume - y, 0);
            else if (name.Equals("EE"))
                delay = y;
            else if (name.Equals("F")) {
                if (argument >= 1 && argument <= 31)
                    speed = argument;
                else if (argument >= 32)
                    tempo = argument;
            } else if (name.Equals("P"))
                c.detune = argument - 128;
            else if (name.Equals("Q") || name.Equals("R")) {
                if (c.note < 0)
                    Warning(index, "slide without note");
                else {
                    c.note = name.Equals("Q") ? Math.Min(c.note + y, 95) : Math.Max(c.note - y, 12);
                    c.target = Instruments.Frequency(c.note);
                    c.slideSpeed = 2 * x + 1;
                }
            } else if (name.Equals("V")) {
                if (c.instrument != null && (c.instrument.wave.Equals("PULSE") && argument <= 3 ||
                                             c.instrument.wave.Equals("NOISE") && argument <= 1))
                    c.mode = argument;
                else
                    Warning(index, "invalid mode " + Report.Hex2(argument));
            }
        }
        public int StartRow(SongParser.Cell[] cells) {
            delay = 0;
            for (int i = 0; i < 4; i++) {
                Channel c = channels[i];
                c.cell = cells[i];
                c.effect = cells[i].effect;
                c.slideSpeed = 0;
                if (c.effect.name.Length != 0)
                    effects[c.effect.name] = effects.GetValueOrDefault(c.effect.name) + 1;
                if (!c.effect.name.Equals("ED") || c.effect.y == 0)
                    Content(i, c.effect.name.Equals("3") || c.effect.name.Equals("5"));
                TickZero(i);
            }
            int count = speed * (1 + delay);
            for (int i = 0; i < 4; i++) {
                SongParser.Effect e = channels[i].effect;
                if (e.name.Equals("EC") && e.y >= count)
                    Warning(i, "cut beyond row");
                if (e.name.Equals("ED") && e.y >= count)
                    Warning(i, "delay beyond row");
            }
            return count;
        }
        public void Approach(Channel c, int step) {
            c.frequency = c.frequency < c.target ? Math.Min(c.frequency + step, c.target)
                                                 : Math.Max(c.frequency - step, c.target);
        }
        public void Tick(int tick) {
            for (int i = 0; i < 4; i++) {
                Channel c = channels[i];
                SongParser.Effect e = c.effect;
                string name = e.name;
                if (c.note >= 0 && c.age >= 1 && c.instrument.sweep != 0)
                    c.frequency =
                        Instruments.Clamp(c.frequency + 10 * c.instrument.sweep, 1000, 50L * song.rate);
                if (tick >= 1) {
                    if (name.Equals("1"))
                        c.frequency = Instruments.Clamp(c.frequency + 10 * e.argument, 1000, 50L * song.rate);
                    else if (name.Equals("2"))
                        c.frequency = Instruments.Clamp(c.frequency - 10 * e.argument, 1000, 50L * song.rate);
                    if (name.Equals("3") || name.Equals("5"))
                        Approach(c, 10 * c.portamentoSpeed);
                    if ((name.Equals("Q") || name.Equals("R")) && c.slideSpeed != 0)
                        Approach(c, 10 * c.slideSpeed);
                    if (name.Equals("5") || name.Equals("6") || name.Equals("A"))
                        c.volume = (int)Instruments.Clamp(c.volume + e.x - e.y, 0, 15);
                }
                if (name.Equals("ED") && e.y >= 1 && tick == e.y)
                    Content(i, false);
                if (name.Equals("E9") && e.y >= 1 && tick >= 1 && tick % e.y == 0 && c.note >= 0) {
                    c.phase = 0;
                    c.age = 0;
                    c.off = false;
                    retriggers[i]++;
                }
                if (name.Equals("EC") && tick == e.y && c.note >= 0) {
                    Finish(c, "cut");
                    c.note = -1;
                    cuts[i]++;
                }
                Output(c, tick, song.rate);
                if (c.sounding) {
                    active[i]++;
                    if (c.amplitude > 0)
                        audible[i]++;
                    instrumentTicks[c.instrument.number] =
                        instrumentTicks.GetValueOrDefault(c.instrument.number) + 1;
                }
            }
        }
        public string ChannelText(Channel c) {
            return c.note < 0 ? "--- --       - - " + Report.Hex1(c.volume) + " " + c.effect.text
                              : SongParser.NoteName(c.note) + " " + Report.Hex2(c.instrument.number) + " " +
                                    Report.Aligned(c.outputFrequency, 7) + " " + Report.Hex1(c.envelope) +
                                    " " + Report.Hex1(c.outputVolume) + " " + c.effect.text;
        }
        public string TickText(Channel c) {
            return c.sounding ? Report.Aligned(c.outputFrequency, 7) + " " + Report.Aligned(c.increment, 5) +
                                    " " + Report.Hex1(c.envelope) + Report.Hex1(c.outputVolume)
                              : "      -     - --";
        }
        public void Play() {
            int[] counts = new int[song.order.Length * 64], first = new int[counts.Length];
            Array.Fill(first, -1);
            bool done = false;
            while (!done) {
                int key = position * 64 + row;
                if (first[key] < 0)
                    first[key] = mixer.size;
                counts[key]++;
                SongParser.Cell[] cells = song.patterns[song.order[position]][row];
                int start = mixer.size, count = StartRow(cells),
                    spt = Sequencer.SamplesPerTick(song.rate, tempo);
                for (int t = 0; t < count; t++) {
                    Tick(t);
                    if (t == 0) {
                        int[] pitches = new int[4];
                        string text = Report.Hex2(position) + " " + Report.Hex2(song.order[position]) + " " +
                                      Report.Hex2(row) + " " + Report.Aligned(start, 7) + " " +
                                      Report.Aligned(speed, 2) + " " + Report.Aligned(tempo, 3);
                        for (int i = 0; i < 4; i++) {
                            pitches[i] = channels[i].note;
                            text += " | " + ChannelText(channels[i]);
                        }
                        log.Add(text);
                        rows.Add(new Row(position, row, start, speed, tempo, pitches));
                    }
                    if (settings.traces.Contains(key)) {
                        string text = "  tick " + Report.Aligned(t, 3) + " " + Report.Aligned(mixer.size, 7);
                        foreach (Channel c in channels)
                            text += " | " + TickText(c);
                        log.Add(text);
                    }
                    mixer.Generate(channels, Math.Min(spt, settings.Integer("max_samples") - mixer.size));
                    ticks++;
                    foreach (Channel c in channels) {
                        if (c.note >= 0)
                            c.age++;
                        if (c.effect.name.Equals("4") || c.effect.name.Equals("6"))
                            c.vibratoPosition = (c.vibratoPosition + c.vibratoSpeed) % 64;
                        if (c.effect.name.Equals("7"))
                            c.tremoloPosition = (c.tremoloPosition + c.tremoloSpeed) % 64;
                    }
                    if (mixer.size == settings.Integer("max_samples")) {
                        reason = "limit";
                        done = true;
                        break;
                    }
                }
                if (done)
                    break;
                bool stop = false;
                foreach (SongParser.Cell cell in cells)
                    if (cell.effect.name.Equals("F") && cell.effect.argument == 0)
                        stop = true;
                if (stop) {
                    reason = "stop order=" + Report.Hex2(position) + " row=" + Report.Hex2(row);
                    break;
                }
                Sequencer.Position next = Sequencer.Next(position, row, cells, song.order.Length);
                if (next == null) {
                    reason = "finished";
                    break;
                }
                key = next.order * 64 + next.row;
                if (counts[key] >= settings.Integer("loops")) {
                    loopStart = first[key];
                    reason = "loop order=" + Report.Hex2(next.order) + " row=" + Report.Hex2(next.row);
                    break;
                }
                position = next.order;
                row = next.row;
            }
            foreach (Channel channel in channels)
                Finish(channel, "end");
            if ((reason.Equals("limit") || reason.StartsWith("loop")) && settings.Integer("fade") > 0)
                mixer.Fade(settings.Integer("fade"));
        }
    }
    public static List<string> NoteLines(Player p) {
        List<string> output = new();
        foreach (Note note in p.notes) {
            int peak = 0, cycles = 0;
            int[] lane = p.mixer.lanes[note.channel - 1];
            for (int i = note.start; i < note.start + note.length; i++) {
                peak = Math.Max(peak, Math.Abs(lane[i]));
                if (i > note.start && lane[i - 1] < 0 && lane[i] >= 0)
                    cycles++;
            }
            output.Add(Report.Aligned(note.serial, 4) + " ch=" + note.channel +
                       " at=" + Report.Hex2(note.position) + ":" + Report.Hex2(note.row) +
                       " ins=" + Report.Hex2(note.instrument) + " note=" + SongParser.NoteName(note.note) +
                       " start=" + note.start + " length=" + note.length +
                       " release=" + (note.release < 0 ? "-" : Convert.ToString(note.release)) +
                       " end=" + note.reason + " peak=" + peak + " cycles=" + cycles);
        }
        return output;
    }
    public static List<string> RollLines(Player p) {
        int[] options = p.settings.Numbers("roll");
        List<Row> rows = new();
        for (int i = options[0]; i < Math.Min(p.rows.Count, options[0] + options[1]); i++)
            rows.Add(p.rows[i]);
        SortedSet<int> pitches = new SortedSet<int>(Comparer<int>.Create((a, b) => b.CompareTo(a)));
        foreach (Row row in rows)
            foreach (int note in row.notes)
                if (note >= 0)
                    pitches.Add(note);
        List<string> output =
            new(["ROLL start=" + options[0] + " rows=" + rows.Count + " pitches=" + pitches.Count]);
        foreach (int note in pitches) {
            StringBuilder text = new StringBuilder(SongParser.NoteName(note) + " |");
            foreach (Row row in rows) {
                int matches = 0, channel = 0;
                for (int c = 0; c < 4; c++)
                    if (row.notes[c] == note) {
                        matches++;
                        channel = c + 1;
                    }
                text.Append(matches == 0 ? ' ' : matches == 1 ? (char)('0' + channel) : '*');
            }
            output.Add(text.Append('|').ToString());
        }
        StringBuilder axis = new StringBuilder("    +");
        for (int i = 0; i < rows.Count; i++)
            axis.Append(i % 16 == 0 ? '+' : '-');
        output.Add(axis.Append('+').ToString());
        return output;
    }
    public static List<Note> Records(Player p, int channel, int instrument) {
        List<Note> result = new();
        foreach (Note note in p.notes)
            if ((channel == 0 || note.channel == channel) &&
                (instrument == 0 || note.instrument == instrument))
                result.Add(note);
        return result;
    }
    public static string Range(List<Note> records) {
        if (records.Count == 0)
            return "none";
        int low = 95, high = 12;
        foreach (Note record in records) {
            low = Math.Min(low, record.note);
            high = Math.Max(high, record.note);
        }
        return SongParser.NoteName(low) + ".." + SongParser.NoteName(high);
    }
    public static string Numbers(List<int> numbers) {
        if (numbers.Count == 0)
            return "none";
        List<string> values = new();
        foreach (int number in numbers)
            values.Add(Report.Hex2(number));
        return string.Join(" ", values);
    }
    public static string KeyName(int key) {
        return TONICS[key % 12] + (key < 12 ? " major" : " minor");
    }
    public static List<string> StatsLines(Player p) {
        SongParser.Song song = p.song;
        Mixer mixer = p.mixer;
        int n = mixer.size;
        Report.Statistics stats = Report.Inspect(mixer.samples, 0, n, 128);
        List<string> output = new([
            "title=" + song.title, "rate=" + song.rate, "samples=" + n,
            "duration_ms=" + (long)n * 1000 / song.rate, "end=" + p.reason,
            "loop_start=" + (p.loopStart < 0 ? "-" : Convert.ToString(p.loopStart)),
            "loop_length=" + (p.loopStart < 0 ? "-" : Convert.ToString(n - p.loopStart)),
            "rows=" + p.rows.Count, "ticks=" + p.ticks, "clipped=" + mixer.clipped, "peak=" + stats.peak,
            "min=" + stats.minimum, "max=" + stats.maximum, "rms=" + stats.rms,
            "zero_crossings=" + stats.crossings, "adler32=" + Report.Hex8(Report.Adler(mixer.samples, n))
        ]);
        List<string> path = new();
        int previousPosition = -1;
        Row previousRow = null;
        foreach (Row row in p.rows) {
            if (row.position != previousPosition) {
                path.Add(Report.Hex2(row.position));
                previousPosition = row.position;
            }
        }
        output.Add("path " + string.Join(" ", path));
        foreach (Row row in p.rows) {
            if (previousRow == null || row.speed != previousRow.speed || row.tempo != previousRow.tempo)
                output.Add("timing sample=" + row.start + " order=" + Report.Hex2(row.position) +
                           " row=" + Report.Hex2(row.row) + " speed=" + row.speed + " tempo=" + row.tempo);
            previousRow = row;
        }
        for (int c = 0; c < 4; c++) {
            Report.Statistics lane = Report.Inspect(mixer.lanes[c], 0, n, 0);
            output.Add("channel " + (c + 1) + " notes=" + Records(p, c + 1, 0).Count +
                       " retriggers=" + p.retriggers[c] + " cuts=" + p.cuts[c] + " active=" + p.active[c] +
                       " audible=" + p.audible[c] + " peak=" + lane.peak + " rms=" + lane.rms);
        }
        List<int> unusedInstruments = new(), unusedPatterns = new(), unreached = new();
        foreach (SongParser.Instrument instrument in song.instruments.Values) {
            List<Note> notes = Records(p, 0, instrument.number);
            long total = 0;
            foreach (Note note in notes)
                total += note.length;
            output.Add("instrument " + Report.Hex2(instrument.number) + " " + instrument.name + " " +
                       instrument.wave + " notes=" + notes.Count + " ticks=" +
                       p.instrumentTicks.GetValueOrDefault(instrument.number) + " range=" + Range(notes) +
                       " average=" + (notes.Count == 0 ? "-" : Convert.ToString(total / notes.Count)));
            if (notes.Count == 0)
                unusedInstruments.Add(instrument.number);
        }
        foreach (KeyValuePair<int, SongParser.Cell[][]> entry in song.patterns) {
            int rows = 0, notes = 0, orders = 0;
            foreach (SongParser.Cell[] row in entry.Value) {
                bool nonempty = false;
                foreach (SongParser.Cell cell in row) {
                    if (!cell.Empty())
                        nonempty = true;
                    if (cell.note != -2)
                        notes++;
                }
                if (nonempty)
                    rows++;
            }
            foreach (int pattern in song.order)
                if (pattern == entry.Key)
                    orders++;
            output.Add("pattern " + Report.Hex2(entry.Key) + " rows=" + rows + " notes=" + notes +
                       " orders=" + orders);
            if (orders == 0)
                unusedPatterns.Add(entry.Key);
        }
        HashSet<int> reachable = Sequencer.Reachable(song);
        for (int position = 0; position < song.order.Length; position++) {
            int count = 0, first = -1, dead = 0;
            foreach (Row row in p.rows)
                if (row.position == position) {
                    count++;
                    if (first < 0)
                        first = row.start;
                }
            for (int r = 0; r < 64; r++)
                if (!reachable.Contains(position * 64 + r)) {
                    bool hasNote = false;
                    foreach (SongParser.Cell cell in song.patterns[song.order[position]][r])
                        if (cell.note != -2)
                            hasNote = true;
                    if (hasNote)
                        dead++;
                }
            output.Add("order " + Report.Hex2(position) + " pattern=" + Report.Hex2(song.order[position]) +
                       " rows=" + count + " first=" + (first < 0 ? "-" : Convert.ToString(first)) +
                       " dead=" + dead);
            if (count == 0)
                unreached.Add(position);
        }
        int[] noteCounts = new int[96];
        long[] duration = new long[12];
        foreach (Note note in p.notes) {
            noteCounts[note.note]++;
            if (!song.instruments[note.instrument].wave.Equals("NOISE"))
                duration[note.note % 12] += note.length;
        }
        for (int note = 12; note < 96; note++)
            if (noteCounts[note] > 0)
                output.Add("note " + SongParser.NoteName(note) + " count=" + noteCounts[note]);
        string effects = "effects";
        foreach (string name in EFFECT_ORDER)
            if (p.effects.ContainsKey(name))
                effects += " " + name + "=" + p.effects[name];
        output.Add(effects.Equals("effects") ? "effects none" : effects);
        output.Add("unused_instruments=" + Numbers(unusedInstruments));
        output.Add("unused_patterns=" + Numbers(unusedPatterns));
        output.Add("unreached_orders=" + Numbers(unreached));
        string classes = "pitch_classes";
        for (int j = 0; j < 12; j++)
            classes += " " + TONICS[j] + "=" + duration[j];
        output.Add(classes);
        long[] scores = new long[24];
        int[] keys = new int[24];
        for (int key = 0; key < 24; key++) {
            keys[key] = key;
            for (int j = 0; j < 12; j++)
                scores[key] += (key < 12 ? MAJOR : MINOR)[((j - key % 12) % 12 + 12) % 12] * duration[j];
        }
        Array.Sort(keys,
                   Comparer<int>.Create((a, b) => scores[a] != scores[b] ? scores[b].CompareTo(scores[a])
                                                                         : a.CompareTo(b)));
        output.Add("key=" + KeyName(keys[0]) + " score=" + scores[keys[0]] +
                   " runner_up=" + KeyName(keys[1]) + " score=" + scores[keys[1]]);
        for (int c = 1; c <= 4; c++) {
            string usage = "usage ch" + c + " range=" + Range(Records(p, c, 0));
            foreach (int instrument in song.instruments.Keys)
                usage += " " + Report.Hex2(instrument) + "=" + Records(p, c, instrument).Count;
            output.Add(usage);
        }
        output.AddRange(p.warnings);
        return output;
    }
    public static int PlotRow(int value, int low, int high, int height) {
        return (2 * (high - value) * (height - 1) + high - low) / (2 * (high - low));
    }
    public static List<string> Plot(int[] values, int start, int length, int width, int height, int low,
                                    int high, int middle) {
        char[][] cells = Enumerable.Range(0, height)
                             .Select(
                                 _ => new char[width])
                             .ToArray();
        int center = PlotRow(middle, low, high, height);
        for (int c = 0; c < width; c++) {
            int top = int.MinValue, bottom = int.MaxValue;
            for (int j = c * length / width; j < (c + 1) * length / width; j++) {
                top = Math.Max(top, values[start + j]);
                bottom = Math.Min(bottom, values[start + j]);
            }
            int first = PlotRow(top, low, high, height), last = PlotRow(bottom, low, high, height);
            for (int r = 0; r < height; r++)
                cells[r][c] = first <= r && r <= last ? '#' : r == center ? '-' : ' ';
        }
        List<string> output = new();
        for (int r = 0; r < height; r++) {
            string label = r == 0            ? Convert.ToString(high)
                           : r == center     ? Convert.ToString(middle)
                           : r == height - 1 ? Convert.ToString(low)
                                             : "";
            output.Add(new string(' ', 5 - label.Length) + label + " |" + new string(cells[r]) + "|");
        }
        return output;
    }
    public static List<string> Axes(int start, int length, int width, int rate) {
        StringBuilder first = new StringBuilder("      +"), second = new StringBuilder("    ms");
        for (int c = 0; c < width; c++)
            first.Append(c % 10 == 0 ? '+' : '-');
        first.Append('+');
        for (int c = 0; c < width; c += 10) {
            while (second.Length < 7 + c)
                second.Append(' ');
            second.Append((long)(start + c * length / width) * 1000 / rate);
        }
        return [first.ToString(), second.ToString()];
    }
    public static List<string> WaveformLines(Player p) {
        int[] options = p.settings.Numbers("window");
        int start = options[0], length = options[1], width = options[2], height = options[3],
            scope = options[4];
        List<string> output =
            new(["MIX start=" + start + " length=" + length + " width=" + width + " height=" + height]);
        output.AddRange(Plot(p.mixer.samples, start, length, width, height, 0, 255, 128));
        output.AddRange(Axes(start, length, width, p.song.rate));
        for (int c = 0; c < 4; c++) {
            output.Add("CHANNEL " + (c + 1));
            output.AddRange(Plot(p.mixer.lanes[c], start, length, width, scope, -3375, 3375, 0));
        }
        output.AddRange(Axes(start, length, width, p.song.rate));
        return output;
    }
    public static List<string> PreviewLines(SongParser.Song song, SongParser.Settings settings) {
        string[] options = settings.entries["preview"];
        int note = SongParser.Note(options[0]), ticks = int.Parse(options[1]),
            release = int.Parse(options[2]), spt = Sequencer.SamplesPerTick(song.rate, song.tempo);
        List<string> output = new();
        foreach (SongParser.Instrument instrument in song.instruments.Values) {
            Channel c = new Channel();
            c.instrument = instrument;
            c.mode = instrument.mode;
            c.note = note;
            c.frequency = Instruments.Frequency(note);
            c.target = c.frequency;
            Mixer mixer = new Mixer(ticks * spt, 1, song.gain, new int[] { 0 });
            StringBuilder envelope = new StringBuilder();
            List<string> frequencies = new();
            for (int t = 0; t < ticks; t++) {
                c.age = t;
                if (t == release) {
                    c.off = true;
                    c.releaseAge = t;
                    c.releaseValue = c.envelope;
                }
                if (t >= 1 && instrument.sweep != 0)
                    c.frequency =
                        Instruments.Clamp(c.frequency + 10 * instrument.sweep, 1000, 50L * song.rate);
                Output(c, t, song.rate);
                envelope.Append(Report.Hex1(c.envelope));
                frequencies.Add(Convert.ToString(c.outputFrequency));
                mixer.Generate(new Channel[] { c }, spt);
            }
            Report.Statistics stats = Report.Inspect(mixer.samples, 0, mixer.size, 128);
            output.Add("instrument " + Report.Hex2(instrument.number) + " " + instrument.name +
                       " wave=" + instrument.wave + " samples=" + mixer.size + " peak=" + stats.peak +
                       " rms=" + stats.rms +
                       " adler32=" + Report.Hex8(Report.Adler(mixer.samples, mixer.size)));
            output.Add("  env " + envelope);
            output.Add("  freq " + string.Join(" ", frequencies));
        }
        return output;
    }
    public static void Write(string name, List<string> lines) {
        File.WriteAllText(Path.Combine("output", name),
                          lines.Count == 0 ? "" : string.Join("\n", lines) + "\n", Encoding.ASCII);
    }
    public static void Main(string[] args) {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        SongParser.Song song = SongParser.ReadSong();
        SongParser.Settings settings = SongParser.ReadSettings();
        Player player = new Player(song, settings);
        player.Play();
        Directory.CreateDirectory(Path.Combine("output"));
        Write("samples.txt", Report.Dump(player.mixer.samples, player.mixer.size));
        Write("channel_log.txt", player.log);
        Write("notes.txt", NoteLines(player));
        Write("roll.txt", RollLines(player));
        Write("stats.txt", StatsLines(player));
        Write("waveform.txt", WaveformLines(player));
        Write("instruments.txt", PreviewLines(song, settings));
    }
}
