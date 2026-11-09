import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.io.IOException;
import java.util.*;
public final class Main {
    static final String[] EFFECT_ORDER = {"0",  "1",  "2", "3",  "4",  "5",  "6",  "7",  "A",
                                          "B",  "C",  "D", "E1", "E2", "E9", "EA", "EB", "EC",
                                          "ED", "EE", "F", "P",  "Q",  "R",  "V"};
    static final String[] TONICS = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"};
    static final int[] MAJOR = {64, 22, 35, 23, 44, 41, 25, 52, 24, 37, 23, 29},
                       MINOR = {64, 27, 35, 54, 27, 35, 25, 48, 40, 27, 34, 32};
    static final class Channel {
        SongParser.Instrument instrument;
        int note = -1, portamentoSpeed, slideSpeed, detune, vibratoSpeed, vibratoDepth, vibratoPosition,
            tremoloSpeed, tremoloDepth, tremoloPosition, volume = 15, mode, phase, shift = 1, age, releaseAge,
            releaseValue, envelope, outputVolume, amplitude, increment;
        long frequency, target, outputFrequency;
        boolean off, sounding;
        SongParser.Effect effect = SongParser.effect("...");
        SongParser.Cell cell;
        Note record;
    }
    static final class Note {
        int serial, channel, position, row, instrument, note, start, length, release = -1;
        String reason;
        Note(int serial, int channel, int position, int row, int instrument, int note, int start) {
            this.serial = serial;
            this.channel = channel;
            this.position = position;
            this.row = row;
            this.instrument = instrument;
            this.note = note;
            this.start = start;
        }
    }
    record Row(int position, int row, int start, int speed, int tempo, int[] notes) {}
    static void output(Channel c, int tick, int rate) {
        c.sounding = c.note >= 0;
        if (!c.sounding)
            return;
        SongParser.Instrument instrument = c.instrument;
        int semitones = c.effect.name().equals("0") ? tick % 3 == 1   ? c.effect.x()
                                                      : tick % 3 == 2 ? c.effect.y()
                                                                      : 0
                                                    : 0;
        if (instrument.arpeggio.length > 0)
            semitones += instrument.arpeggio[c.age % instrument.arpeggio.length];
        long frequency = Instruments.transpose(c.frequency, semitones) + c.detune;
        if (c.effect.name().equals("4") || c.effect.name().equals("6"))
            frequency += Instruments.oscillate(c.vibratoPosition, c.vibratoDepth, 4);
        if (instrument.vibratoDelay >= 0 && c.age >= instrument.vibratoDelay)
            frequency += Instruments.oscillate(
                (c.age - instrument.vibratoDelay) * instrument.vibratoSpeed % 64, instrument.vibratoDepth, 4);
        c.outputFrequency = Instruments.clamp(frequency, 1000, 50L * rate);
        c.envelope = Instruments.envelope(instrument, c.age, c.off, c.releaseAge, c.releaseValue);
        c.outputVolume =
            c.effect.name().equals("7")
                ? (int)Instruments.clamp(
                      c.volume + Instruments.oscillate(c.tremoloPosition, c.tremoloDepth, 255), 0, 15)
                : c.volume;
        c.amplitude = c.envelope * c.outputVolume;
        c.increment = (int)(c.outputFrequency * 65536 / (100L * rate));
    }
    static final class Player {
        final SongParser.Song song;
        final SongParser.Settings settings;
        final Channel[] channels = new Channel[4];
        final Mixer mixer;
        final List<Note> notes = new ArrayList<>();
        final List<Row> rows = new ArrayList<>();
        final List<String> warnings = new ArrayList<>(), log = new ArrayList<>();
        final long[] retriggers = new long[4], cuts = new long[4], active = new long[4],
                     audible = new long[4];
        final Map<Integer, Long> instrumentTicks = new HashMap<>();
        final Map<String, Integer> effects = new HashMap<>();
        int position, row, speed, tempo, delay, ticks;
        String reason = "finished";
        int loopStart = -1;
        Player(SongParser.Song song, SongParser.Settings settings) {
            this.song = song;
            this.settings = settings;
            speed = song.speed;
            tempo = song.tempo;
            for (int i = 0; i < 4; i++)
                channels[i] = new Channel();
            mixer = new Mixer(settings.integer("max_samples"), 4, song.gain, settings.numbers("mute"));
        }
        void warning(int channel, String message) {
            warnings.add("warning " + Report.hex2(position) + ":" + Report.hex2(row) + " ch" + (channel + 1) +
                         " " + message);
        }
        void finish(Channel channel, String reason) {
            if (channel.record != null) {
                channel.record.length = mixer.size - channel.record.start;
                channel.record.reason = reason;
                channel.record = null;
            }
        }
        void noteOn(int index, int note) {
            Channel c = channels[index];
            finish(c, "next");
            c.frequency = Instruments.frequency(note);
            c.target = c.frequency;
            c.phase = 0;
            c.age = 0;
            c.vibratoPosition = 0;
            c.tremoloPosition = 0;
            c.off = false;
            c.note = note;
            Note record =
                new Note(notes.size() + 1, index + 1, position, row, c.instrument.number, note, mixer.size);
            notes.add(record);
            c.record = record;
        }
        void content(int index, boolean portamento) {
            Channel c = channels[index];
            SongParser.Cell cell = c.cell;
            if (cell.instrument() != 0) {
                SongParser.Instrument instrument = song.instruments.get(cell.instrument());
                if (instrument == null)
                    warning(index, "undefined instrument " + Report.hex2(cell.instrument()));
                else {
                    c.instrument = instrument;
                    c.volume = 15;
                    c.mode = instrument.mode;
                }
            }
            if (cell.volume() >= 0)
                c.volume = cell.volume();
            if (cell.note() == -1) {
                if (c.note >= 0 && !c.off) {
                    c.off = true;
                    c.releaseAge = c.age;
                    c.releaseValue = c.envelope;
                    if (c.record != null)
                        c.record.release = mixer.size - c.record.start;
                } else
                    warning(index, "key off without note");
            } else if (cell.note() >= 0) {
                if (c.instrument == null)
                    warning(index, "note without instrument");
                else if (portamento && c.note >= 0) {
                    c.target = Instruments.frequency(cell.note());
                    c.note = cell.note();
                } else {
                    if (portamento && c.note < 0)
                        warning(index, "portamento without note");
                    noteOn(index, cell.note());
                }
            }
        }
        void tickZero(int index) {
            Channel c = channels[index];
            SongParser.Effect e = c.effect;
            int argument = e.argument(), x = e.x(), y = e.y();
            String name = e.name();
            if (name.equals("3")) {
                if (argument > 0)
                    c.portamentoSpeed = argument;
            } else if (name.equals("4")) {
                if (x > 0)
                    c.vibratoSpeed = x;
                if (y > 0)
                    c.vibratoDepth = y;
            } else if (name.equals("7")) {
                if (x > 0)
                    c.tremoloSpeed = x;
                if (y > 0)
                    c.tremoloDepth = y;
            } else if (name.equals("C"))
                c.volume = Math.min(argument, 15);
            else if (name.equals("E1"))
                c.frequency = Instruments.clamp(c.frequency + 10 * y, 1000, 50L * song.rate);
            else if (name.equals("E2"))
                c.frequency = Instruments.clamp(c.frequency - 10 * y, 1000, 50L * song.rate);
            else if (name.equals("EA"))
                c.volume = Math.min(c.volume + y, 15);
            else if (name.equals("EB"))
                c.volume = Math.max(c.volume - y, 0);
            else if (name.equals("EE"))
                delay = y;
            else if (name.equals("F")) {
                if (argument >= 1 && argument <= 31)
                    speed = argument;
                else if (argument >= 32)
                    tempo = argument;
            } else if (name.equals("P"))
                c.detune = argument - 128;
            else if (name.equals("Q") || name.equals("R")) {
                if (c.note < 0)
                    warning(index, "slide without note");
                else {
                    c.note = name.equals("Q") ? Math.min(c.note + y, 95) : Math.max(c.note - y, 12);
                    c.target = Instruments.frequency(c.note);
                    c.slideSpeed = 2 * x + 1;
                }
            } else if (name.equals("V")) {
                if (c.instrument != null && (c.instrument.wave.equals("PULSE") && argument <= 3 ||
                                             c.instrument.wave.equals("NOISE") && argument <= 1))
                    c.mode = argument;
                else
                    warning(index, "invalid mode " + Report.hex2(argument));
            }
        }
        int startRow(SongParser.Cell[] cells) {
            delay = 0;
            for (int i = 0; i < 4; i++) {
                Channel c = channels[i];
                c.cell = cells[i];
                c.effect = cells[i].effect();
                c.slideSpeed = 0;
                if (!c.effect.name().isEmpty())
                    effects.merge(c.effect.name(), 1, Integer::sum);
                if (!c.effect.name().equals("ED") || c.effect.y() == 0)
                    content(i, c.effect.name().equals("3") || c.effect.name().equals("5"));
                tickZero(i);
            }
            int count = speed * (1 + delay);
            for (int i = 0; i < 4; i++) {
                SongParser.Effect e = channels[i].effect;
                if (e.name().equals("EC") && e.y() >= count)
                    warning(i, "cut beyond row");
                if (e.name().equals("ED") && e.y() >= count)
                    warning(i, "delay beyond row");
            }
            return count;
        }
        void approach(Channel c, int step) {
            c.frequency = c.frequency < c.target ? Math.min(c.frequency + step, c.target)
                                                 : Math.max(c.frequency - step, c.target);
        }
        void tick(int tick) {
            for (int i = 0; i < 4; i++) {
                Channel c = channels[i];
                SongParser.Effect e = c.effect;
                String name = e.name();
                if (c.note >= 0 && c.age >= 1 && c.instrument.sweep != 0)
                    c.frequency =
                        Instruments.clamp(c.frequency + 10 * c.instrument.sweep, 1000, 50L * song.rate);
                if (tick >= 1) {
                    if (name.equals("1"))
                        c.frequency =
                            Instruments.clamp(c.frequency + 10 * e.argument(), 1000, 50L * song.rate);
                    else if (name.equals("2"))
                        c.frequency =
                            Instruments.clamp(c.frequency - 10 * e.argument(), 1000, 50L * song.rate);
                    if (name.equals("3") || name.equals("5"))
                        approach(c, 10 * c.portamentoSpeed);
                    if ((name.equals("Q") || name.equals("R")) && c.slideSpeed != 0)
                        approach(c, 10 * c.slideSpeed);
                    if (name.equals("5") || name.equals("6") || name.equals("A"))
                        c.volume = (int)Instruments.clamp(c.volume + e.x() - e.y(), 0, 15);
                }
                if (name.equals("ED") && e.y() >= 1 && tick == e.y())
                    content(i, false);
                if (name.equals("E9") && e.y() >= 1 && tick >= 1 && tick % e.y() == 0 && c.note >= 0) {
                    c.phase = 0;
                    c.age = 0;
                    c.off = false;
                    retriggers[i]++;
                }
                if (name.equals("EC") && tick == e.y() && c.note >= 0) {
                    finish(c, "cut");
                    c.note = -1;
                    cuts[i]++;
                }
                output(c, tick, song.rate);
                if (c.sounding) {
                    active[i]++;
                    if (c.amplitude > 0)
                        audible[i]++;
                    instrumentTicks.merge(c.instrument.number, 1L, Long::sum);
                }
            }
        }
        String channelText(Channel c) {
            return c.note < 0 ? "--- --       - - " + Report.hex1(c.volume) + " " + c.effect.text()
                              : SongParser.noteName(c.note) + " " + Report.hex2(c.instrument.number) + " " +
                                    Report.aligned(c.outputFrequency, 7) + " " + Report.hex1(c.envelope) +
                                    " " + Report.hex1(c.outputVolume) + " " + c.effect.text();
        }
        String tickText(Channel c) {
            return c.sounding ? Report.aligned(c.outputFrequency, 7) + " " + Report.aligned(c.increment, 5) +
                                    " " + Report.hex1(c.envelope) + Report.hex1(c.outputVolume)
                              : "      -     - --";
        }
        void play() {
            int[] counts = new int[song.order.length * 64], first = new int[counts.length];
            Arrays.fill(first, -1);
            boolean done = false;
            while (!done) {
                int key = position * 64 + row;
                if (first[key] < 0)
                    first[key] = mixer.size;
                counts[key]++;
                SongParser.Cell[] cells = song.patterns.get(song.order[position])[row];
                int start = mixer.size, count = startRow(cells),
                    spt = Sequencer.samplesPerTick(song.rate, tempo);
                for (int t = 0; t < count; t++) {
                    tick(t);
                    if (t == 0) {
                        int[] pitches = new int[4];
                        String text = Report.hex2(position) + " " + Report.hex2(song.order[position]) + " " +
                                      Report.hex2(row) + " " + Report.aligned(start, 7) + " " +
                                      Report.aligned(speed, 2) + " " + Report.aligned(tempo, 3);
                        for (int i = 0; i < 4; i++) {
                            pitches[i] = channels[i].note;
                            text += " | " + channelText(channels[i]);
                        }
                        log.add(text);
                        rows.add(new Row(position, row, start, speed, tempo, pitches));
                    }
                    if (settings.traces.contains(key)) {
                        String text = "  tick " + Report.aligned(t, 3) + " " + Report.aligned(mixer.size, 7);
                        for (Channel c : channels)
                            text += " | " + tickText(c);
                        log.add(text);
                    }
                    mixer.generate(channels, Math.min(spt, settings.integer("max_samples") - mixer.size));
                    ticks++;
                    for (Channel c : channels) {
                        if (c.note >= 0)
                            c.age++;
                        if (c.effect.name().equals("4") || c.effect.name().equals("6"))
                            c.vibratoPosition = (c.vibratoPosition + c.vibratoSpeed) % 64;
                        if (c.effect.name().equals("7"))
                            c.tremoloPosition = (c.tremoloPosition + c.tremoloSpeed) % 64;
                    }
                    if (mixer.size == settings.integer("max_samples")) {
                        reason = "limit";
                        done = true;
                        break;
                    }
                }
                if (done)
                    break;
                boolean stop = false;
                for (SongParser.Cell cell : cells)
                    if (cell.effect().name().equals("F") && cell.effect().argument() == 0)
                        stop = true;
                if (stop) {
                    reason = "stop order=" + Report.hex2(position) + " row=" + Report.hex2(row);
                    break;
                }
                Sequencer.Position next = Sequencer.next(position, row, cells, song.order.length);
                if (next == null) {
                    reason = "finished";
                    break;
                }
                key = next.order() * 64 + next.row();
                if (counts[key] >= settings.integer("loops")) {
                    loopStart = first[key];
                    reason = "loop order=" + Report.hex2(next.order()) + " row=" + Report.hex2(next.row());
                    break;
                }
                position = next.order();
                row = next.row();
            }
            for (Channel channel : channels)
                finish(channel, "end");
            if ((reason.equals("limit") || reason.startsWith("loop")) && settings.integer("fade") > 0)
                mixer.fade(settings.integer("fade"));
        }
    }
    static List<String> noteLines(Player p) {
        List<String> output = new ArrayList<>();
        for (Note note : p.notes) {
            int peak = 0, cycles = 0;
            int[] lane = p.mixer.lanes[note.channel - 1];
            for (int i = note.start; i < note.start + note.length; i++) {
                peak = Math.max(peak, Math.abs(lane[i]));
                if (i > note.start && lane[i - 1] < 0 && lane[i] >= 0)
                    cycles++;
            }
            output.add(Report.aligned(note.serial, 4) + " ch=" + note.channel +
                       " at=" + Report.hex2(note.position) + ":" + Report.hex2(note.row) +
                       " ins=" + Report.hex2(note.instrument) + " note=" + SongParser.noteName(note.note) +
                       " start=" + note.start + " length=" + note.length +
                       " release=" + (note.release < 0 ? "-" : Integer.toString(note.release)) +
                       " end=" + note.reason + " peak=" + peak + " cycles=" + cycles);
        }
        return output;
    }
    static List<String> rollLines(Player p) {
        int[] options = p.settings.numbers("roll");
        List<Row> rows = new ArrayList<>();
        for (int i = options[0]; i < Math.min(p.rows.size(), options[0] + options[1]); i++)
            rows.add(p.rows.get(i));
        SortedSet<Integer> pitches = new TreeSet<>(Comparator.reverseOrder());
        for (Row row : rows)
            for (int note : row.notes)
                if (note >= 0)
                    pitches.add(note);
        List<String> output = new ArrayList<>(
            List.of("ROLL start=" + options[0] + " rows=" + rows.size() + " pitches=" + pitches.size()));
        for (int note : pitches) {
            StringBuilder text = new StringBuilder(SongParser.noteName(note) + " |");
            for (Row row : rows) {
                int matches = 0, channel = 0;
                for (int c = 0; c < 4; c++)
                    if (row.notes[c] == note) {
                        matches++;
                        channel = c + 1;
                    }
                text.append(matches == 0 ? ' ' : matches == 1 ? (char)('0' + channel) : '*');
            }
            output.add(text.append('|').toString());
        }
        StringBuilder axis = new StringBuilder("    +");
        for (int i = 0; i < rows.size(); i++)
            axis.append(i % 16 == 0 ? '+' : '-');
        output.add(axis.append('+').toString());
        return output;
    }
    static List<Note> records(Player p, int channel, int instrument) {
        List<Note> result = new ArrayList<>();
        for (Note note : p.notes)
            if ((channel == 0 || note.channel == channel) &&
                (instrument == 0 || note.instrument == instrument))
                result.add(note);
        return result;
    }
    static String range(List<Note> records) {
        if (records.isEmpty())
            return "none";
        int low = 95, high = 12;
        for (Note record : records) {
            low = Math.min(low, record.note);
            high = Math.max(high, record.note);
        }
        return SongParser.noteName(low) + ".." + SongParser.noteName(high);
    }
    static String numbers(List<Integer> numbers) {
        if (numbers.isEmpty())
            return "none";
        List<String> values = new ArrayList<>();
        for (int number : numbers)
            values.add(Report.hex2(number));
        return String.join(" ", values);
    }
    static String keyName(int key) {
        return TONICS[key % 12] + (key < 12 ? " major" : " minor");
    }
    static List<String> statsLines(Player p) {
        SongParser.Song song = p.song;
        Mixer mixer = p.mixer;
        int n = mixer.size;
        Report.Statistics stats = Report.statistics(mixer.samples, 0, n, 128);
        List<String> output = new ArrayList<>(List.of(
            "title=" + song.title, "rate=" + song.rate, "samples=" + n,
            "duration_ms=" + (long)n * 1000 / song.rate, "end=" + p.reason,
            "loop_start=" + (p.loopStart < 0 ? "-" : Integer.toString(p.loopStart)),
            "loop_length=" + (p.loopStart < 0 ? "-" : Integer.toString(n - p.loopStart)),
            "rows=" + p.rows.size(), "ticks=" + p.ticks, "clipped=" + mixer.clipped, "peak=" + stats.peak(),
            "min=" + stats.minimum(), "max=" + stats.maximum(), "rms=" + stats.rms(),
            "zero_crossings=" + stats.crossings(), "adler32=" + Report.hex8(Report.adler(mixer.samples, n))));
        List<String> path = new ArrayList<>();
        int previousPosition = -1;
        Row previousRow = null;
        for (Row row : p.rows) {
            if (row.position != previousPosition) {
                path.add(Report.hex2(row.position));
                previousPosition = row.position;
            }
        }
        output.add("path " + String.join(" ", path));
        for (Row row : p.rows) {
            if (previousRow == null || row.speed != previousRow.speed || row.tempo != previousRow.tempo)
                output.add("timing sample=" + row.start + " order=" + Report.hex2(row.position) +
                           " row=" + Report.hex2(row.row) + " speed=" + row.speed + " tempo=" + row.tempo);
            previousRow = row;
        }
        for (int c = 0; c < 4; c++) {
            Report.Statistics lane = Report.statistics(mixer.lanes[c], 0, n, 0);
            output.add("channel " + (c + 1) + " notes=" + records(p, c + 1, 0).size() +
                       " retriggers=" + p.retriggers[c] + " cuts=" + p.cuts[c] + " active=" + p.active[c] +
                       " audible=" + p.audible[c] + " peak=" + lane.peak() + " rms=" + lane.rms());
        }
        List<Integer> unusedInstruments = new ArrayList<>(), unusedPatterns = new ArrayList<>(),
                      unreached = new ArrayList<>();
        for (SongParser.Instrument instrument : song.instruments.values()) {
            List<Note> notes = records(p, 0, instrument.number);
            long total = 0;
            for (Note note : notes)
                total += note.length;
            output.add("instrument " + Report.hex2(instrument.number) + " " + instrument.name + " " +
                       instrument.wave + " notes=" + notes.size() + " ticks=" +
                       p.instrumentTicks.getOrDefault(instrument.number, 0L) + " range=" + range(notes) +
                       " average=" + (notes.isEmpty() ? "-" : Long.toString(total / notes.size())));
            if (notes.isEmpty())
                unusedInstruments.add(instrument.number);
        }
        for (Map.Entry<Integer, SongParser.Cell[][]> entry : song.patterns.entrySet()) {
            int rows = 0, notes = 0, orders = 0;
            for (SongParser.Cell[] row : entry.getValue()) {
                boolean nonempty = false;
                for (SongParser.Cell cell : row) {
                    if (!cell.empty())
                        nonempty = true;
                    if (cell.note() != -2)
                        notes++;
                }
                if (nonempty)
                    rows++;
            }
            for (int pattern : song.order)
                if (pattern == entry.getKey())
                    orders++;
            output.add("pattern " + Report.hex2(entry.getKey()) + " rows=" + rows + " notes=" + notes +
                       " orders=" + orders);
            if (orders == 0)
                unusedPatterns.add(entry.getKey());
        }
        Set<Integer> reachable = Sequencer.reachable(song);
        for (int position = 0; position < song.order.length; position++) {
            int count = 0, first = -1, dead = 0;
            for (Row row : p.rows)
                if (row.position == position) {
                    count++;
                    if (first < 0)
                        first = row.start;
                }
            for (int r = 0; r < 64; r++)
                if (!reachable.contains(position * 64 + r)) {
                    boolean hasNote = false;
                    for (SongParser.Cell cell : song.patterns.get(song.order[position])[r])
                        if (cell.note() != -2)
                            hasNote = true;
                    if (hasNote)
                        dead++;
                }
            output.add("order " + Report.hex2(position) + " pattern=" + Report.hex2(song.order[position]) +
                       " rows=" + count + " first=" + (first < 0 ? "-" : Integer.toString(first)) +
                       " dead=" + dead);
            if (count == 0)
                unreached.add(position);
        }
        int[] noteCounts = new int[96];
        long[] duration = new long[12];
        for (Note note : p.notes) {
            noteCounts[note.note]++;
            if (!song.instruments.get(note.instrument).wave.equals("NOISE"))
                duration[note.note % 12] += note.length;
        }
        for (int note = 12; note < 96; note++)
            if (noteCounts[note] > 0)
                output.add("note " + SongParser.noteName(note) + " count=" + noteCounts[note]);
        String effects = "effects";
        for (String name : EFFECT_ORDER)
            if (p.effects.containsKey(name))
                effects += " " + name + "=" + p.effects.get(name);
        output.add(effects.equals("effects") ? "effects none" : effects);
        output.add("unused_instruments=" + numbers(unusedInstruments));
        output.add("unused_patterns=" + numbers(unusedPatterns));
        output.add("unreached_orders=" + numbers(unreached));
        String classes = "pitch_classes";
        for (int j = 0; j < 12; j++)
            classes += " " + TONICS[j] + "=" + duration[j];
        output.add(classes);
        long[] scores = new long[24];
        Integer[] keys = new Integer[24];
        for (int key = 0; key < 24; key++) {
            keys[key] = key;
            for (int j = 0; j < 12; j++)
                scores[key] += (key < 12 ? MAJOR : MINOR)[Math.floorMod(j - key % 12, 12)] * duration[j];
        }
        Arrays.sort(
            keys,
            Comparator.<Integer>comparingLong(key -> scores[key]).reversed().thenComparingInt(key -> key));
        output.add("key=" + keyName(keys[0]) + " score=" + scores[keys[0]] +
                   " runner_up=" + keyName(keys[1]) + " score=" + scores[keys[1]]);
        for (int c = 1; c <= 4; c++) {
            String usage = "usage ch" + c + " range=" + range(records(p, c, 0));
            for (int instrument : song.instruments.keySet())
                usage += " " + Report.hex2(instrument) + "=" + records(p, c, instrument).size();
            output.add(usage);
        }
        output.addAll(p.warnings);
        return output;
    }
    static int plotRow(int value, int low, int high, int height) {
        return (2 * (high - value) * (height - 1) + high - low) / (2 * (high - low));
    }
    static List<String> plot(int[] values, int start, int length, int width, int height, int low, int high,
                             int middle) {
        char[][] cells = new char[height][width];
        int center = plotRow(middle, low, high, height);
        for (int c = 0; c < width; c++) {
            int top = Integer.MIN_VALUE, bottom = Integer.MAX_VALUE;
            for (int j = c * length / width; j < (c + 1) * length / width; j++) {
                top = Math.max(top, values[start + j]);
                bottom = Math.min(bottom, values[start + j]);
            }
            int first = plotRow(top, low, high, height), last = plotRow(bottom, low, high, height);
            for (int r = 0; r < height; r++)
                cells[r][c] = first <= r && r <= last ? '#' : r == center ? '-' : ' ';
        }
        List<String> output = new ArrayList<>();
        for (int r = 0; r < height; r++) {
            String label = r == 0            ? Integer.toString(high)
                           : r == center     ? Integer.toString(middle)
                           : r == height - 1 ? Integer.toString(low)
                                             : "";
            output.add(" ".repeat(5 - label.length()) + label + " |" + new String(cells[r]) + "|");
        }
        return output;
    }
    static List<String> axes(int start, int length, int width, int rate) {
        StringBuilder first = new StringBuilder("      +"), second = new StringBuilder("    ms");
        for (int c = 0; c < width; c++)
            first.append(c % 10 == 0 ? '+' : '-');
        first.append('+');
        for (int c = 0; c < width; c += 10) {
            while (second.length() < 7 + c)
                second.append(' ');
            second.append((long)(start + c * length / width) * 1000 / rate);
        }
        return List.of(first.toString(), second.toString());
    }
    static List<String> waveformLines(Player p) {
        int[] options = p.settings.numbers("window");
        int start = options[0], length = options[1], width = options[2], height = options[3],
            scope = options[4];
        List<String> output = new ArrayList<>(
            List.of("MIX start=" + start + " length=" + length + " width=" + width + " height=" + height));
        output.addAll(plot(p.mixer.samples, start, length, width, height, 0, 255, 128));
        output.addAll(axes(start, length, width, p.song.rate));
        for (int c = 0; c < 4; c++) {
            output.add("CHANNEL " + (c + 1));
            output.addAll(plot(p.mixer.lanes[c], start, length, width, scope, -3375, 3375, 0));
        }
        output.addAll(axes(start, length, width, p.song.rate));
        return output;
    }
    static List<String> previewLines(SongParser.Song song, SongParser.Settings settings) {
        String[] options = settings.entries.get("preview");
        int note = SongParser.note(options[0]), ticks = Integer.parseInt(options[1]),
            release = Integer.parseInt(options[2]), spt = Sequencer.samplesPerTick(song.rate, song.tempo);
        List<String> output = new ArrayList<>();
        for (SongParser.Instrument instrument : song.instruments.values()) {
            Channel c = new Channel();
            c.instrument = instrument;
            c.mode = instrument.mode;
            c.note = note;
            c.frequency = Instruments.frequency(note);
            c.target = c.frequency;
            Mixer mixer = new Mixer(ticks * spt, 1, song.gain, new int[] {0});
            StringBuilder envelope = new StringBuilder();
            List<String> frequencies = new ArrayList<>();
            for (int t = 0; t < ticks; t++) {
                c.age = t;
                if (t == release) {
                    c.off = true;
                    c.releaseAge = t;
                    c.releaseValue = c.envelope;
                }
                if (t >= 1 && instrument.sweep != 0)
                    c.frequency =
                        Instruments.clamp(c.frequency + 10 * instrument.sweep, 1000, 50L * song.rate);
                output(c, t, song.rate);
                envelope.append(Report.hex1(c.envelope));
                frequencies.add(Long.toString(c.outputFrequency));
                mixer.generate(new Channel[] {c}, spt);
            }
            Report.Statistics stats = Report.statistics(mixer.samples, 0, mixer.size, 128);
            output.add("instrument " + Report.hex2(instrument.number) + " " + instrument.name +
                       " wave=" + instrument.wave + " samples=" + mixer.size + " peak=" + stats.peak() +
                       " rms=" + stats.rms() +
                       " adler32=" + Report.hex8(Report.adler(mixer.samples, mixer.size)));
            output.add("  env " + envelope);
            output.add("  freq " + String.join(" ", frequencies));
        }
        return output;
    }
    static void write(String name, List<String> lines) throws IOException {
        Files.writeString(Path.of("output", name), lines.isEmpty() ? "" : String.join("\n", lines) + "\n",
                          StandardCharsets.US_ASCII);
    }
    public static void main(String[] args) throws IOException {
        SongParser.Song song = SongParser.song();
        SongParser.Settings settings = SongParser.settings();
        Player player = new Player(song, settings);
        player.play();
        Files.createDirectories(Path.of("output"));
        write("samples.txt", Report.dump(player.mixer.samples, player.mixer.size));
        write("channel_log.txt", player.log);
        write("notes.txt", noteLines(player));
        write("roll.txt", rollLines(player));
        write("stats.txt", statsLines(player));
        write("waveform.txt", waveformLines(player));
        write("instruments.txt", previewLines(song, settings));
    }
}
