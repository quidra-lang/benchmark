import java.io.*;
import java.util.*;
import java.util.stream.Collectors;

public class Main {
    static final String[] CHANNEL = {"NOTE_OFF", "NOTE_ON",          "POLY_PRESSURE", "CONTROL",
                                     "PROGRAM",  "CHANNEL_PRESSURE", "PITCH_BEND"};
    static final String[] TEXT = {"TEXT_EVENT", "COPYRIGHT", "TRACK_NAME", "INSTRUMENT_NAME",
                                  "LYRIC",      "MARKER",    "CUE_POINT"};
    static final String[] MAJOR = "Cb Gb Db Ab Eb Bb F C G D A E B F# C#".split(" ");
    static final String[] MINOR = "Ab Eb Bb F C G D A E B F# C# G# D# A#".split(" ");
    static final String[] PITCH = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"};
    static final Map<Integer, String> META =
        Map.ofEntries(Map.entry(0, "SEQUENCE_NUMBER"), Map.entry(32, "CHANNEL_PREFIX"),
                      Map.entry(47, "END_OF_TRACK"), Map.entry(81, "TEMPO"),
                      Map.entry(84, "SMPTE_OFFSET"), Map.entry(88, "TIME_SIGNATURE"),
                      Map.entry(89, "KEY_SIGNATURE"), Map.entry(127, "SEQUENCER_SPECIFIC"));
    static class Event {
        long tick;
        int code;
        List<Integer> data;
        Event(long tick, int code, List<Integer> data) {
            this.tick = tick;
            this.code = code;
            this.data = new ArrayList<>(data);
        }
        Event copy() {
            return new Event(tick, code, data);
        }
        boolean channel() {
            return code >= 128 && code < 240;
        }
        int channelNumber() {
            return (code & 15) + 1;
        }
        boolean on() {
            return channel() && (code & 240) == 144 && data.get(1) > 0;
        }
        boolean off() {
            return channel() && ((code & 240) == 128 || (code & 240) == 144 && data.get(1) == 0);
        }
        boolean end() {
            return code == 303;
        }
        String kind() {
            if (channel())
                return CHANNEL[(code >> 4) - 8];
            if (code == 240)
                return "SYSEX";
            if (code == 247)
                return "SYSEX_ESCAPE";
            int meta = code - 256;
            if (meta >= 1 && meta <= 7)
                return TEXT[meta - 1];
            return META.getOrDefault(meta, "META");
        }
    }
    static class Song {
        int format, division;
        List<List<Event>> tracks;
        Song(int format, int division, List<List<Event>> tracks) {
            this.format = format;
            this.division = division;
            this.tracks = tracks;
        }
        Song copy() {
            List<List<Event>> result = new ArrayList<>();
            for (List<Event> track : tracks)
                result.add(track.stream()
                               .map(Event::copy)
                               .collect(Collectors.toCollection(ArrayList::new)));
            return new Song(format, division, result);
        }
        int count() {
            return tracks.stream().mapToInt(List::size).sum();
        }
        long length() {
            return tracks.stream().mapToLong(t -> t.get(t.size() - 1).tick).max().orElse(0);
        }
    }
    record Located(Event event, int track, int order) {}
    record Note(Located on, Located off) {
        long start() {
            return on.event.tick;
        }
        long length() {
            return off.event.tick - start();
        }
        int channel() {
            return on.event.channelNumber();
        }
        int pitch() {
            return on.event.data.get(0);
        }
    }
    record Pairing(List<Note> notes, List<Located> unmatched) {}
    static class Failure extends RuntimeException {
        Failure(String message) {
            super(message);
        }
    }
    static void fail(String message) {
        throw new Failure(message);
    }
    static StringBuilder output = new StringBuilder();
    static void emit(String text) {
        output.append(text).append('\n');
    }
    static Map<String, Song> songs = new TreeMap<>();
    static boolean running = true, zeroOff;
    static String noteName(int n) {
        return PITCH[n % 12] + (n / 12 - 1);
    }
    static int noteNumber(String text) {
        for (int p = 0; p < 128; p++)
            if (noteName(p).equals(text))
                return p;
        fail("bad value");
        return 0;
    }
    static String hex(int n, int width) {
        return String.format("%0" + width + "X", n);
    }
    static String dataHex(List<Integer> data) {
        return data.stream().map(x -> hex(x, 2)).collect(Collectors.joining());
    }
    static long value(List<Integer> data) {
        long n = 0;
        for (int b : data)
            n = n * 256 + b;
        return n;
    }
    static List<Integer> bytes(long value, int size) {
        List<Integer> result = new ArrayList<>();
        for (int i = size - 1; i >= 0; i--)
            result.add((int)(value >> (i * 8) & 255));
        return result;
    }
    static List<Located> global(Song song) {
        List<Located> result = new ArrayList<>();
        int order = 0;
        for (int t = 0; t < song.tracks.size(); t++)
            for (Event e : song.tracks.get(t))
                result.add(new Located(e, t, order++));
        result.sort(Comparator.comparingLong((Located e) -> e.event.tick)
                        .thenComparingInt(Located::track)
                        .thenComparingInt(Located::order));
        return result;
    }
    static String description(Song s) {
        return "format " + s.format + " tracks " + s.tracks.size() + " division " + s.division +
            " events " + s.count();
    }
    static String eventText(Event e, int track) {
        String head = e.tick + " " + track + " " + e.kind();
        List<Integer> d = e.data;
        int meta = e.code - 256;
        if (e.channel()) {
            String fields;
            if ((e.code >> 4) <= 10)
                fields = noteName(d.get(0)) + " " + d.get(1);
            else if ((e.code >> 4) == 14)
                fields = Integer.toString(d.get(0) + 128 * d.get(1) - 8192);
            else
                fields = d.stream().map(Object::toString).collect(Collectors.joining(" "));
            return head + " " + e.channelNumber() + " " + fields;
        }
        if (meta >= 1 && meta <= 7) {
            StringBuilder text = new StringBuilder();
            for (int b : d)
                text.append((char)b);
            return head + " \"" + text + "\"";
        }
        if (e.end())
            return head;
        if (e.code == 240 || e.code == 247 || meta == 127 || !META.containsKey(meta)) {
            return head + (e.kind().equals("META") ? " " + hex(meta, 2) : "") + " " + d.size() +
                (d.isEmpty() ? "" : " " + dataHex(d));
        }
        if (meta == 0 || meta == 81)
            return head + " " + value(d);
        if (meta == 32)
            return head + " " + (d.get(0) + 1);
        if (meta == 84)
            return head + " " + d.stream().map(Object::toString).collect(Collectors.joining(" "));
        if (meta == 88)
            return head + " " + d.get(0) + "/" + (1 << d.get(1)) + " " + d.get(2) + " " + d.get(3);
        int sf = d.get(0) >= 128 ? d.get(0) - 256 : d.get(0);
        return head + " " + (d.get(1) == 0 ? MAJOR[sf + 7] + " major" : MINOR[sf + 7] + " minor");
    }
    static class Parser {
        List<Integer> data;
        int position, end, eventStart;
        Parser(List<Integer> data) {
            this.data = data;
            end = data.size();
        }
        void error(int offset, String reason) {
            fail("byte " + offset + ": " + reason);
        }
        int read() {
            if (position >= end)
                error(eventStart, "truncated event");
            return data.get(position++);
        }
        long vlq() {
            int start = position;
            long v = 0;
            for (int i = 0; i < 4; i++) {
                int b = read();
                v = v * 128 + (b & 127);
                if (b < 128)
                    return v;
            }
            error(start, "variable-length value too long");
            return 0;
        }
        long integer(int p, int n) {
            return value(data.subList(p, p + n));
        }
        int chunk(String id) {
            int p = position;
            if (data.size() - p < 8)
                error(p, "truncated chunk");
            for (int i = 0; i < 4; i++)
                if (data.get(p + i) != id.charAt(i))
                    error(p, "bad chunk id");
            long len = integer(p + 4, 4);
            if (p + 8L + len > data.size())
                error(p, "truncated chunk");
            position += 8;
            return (int)len;
        }
        Song parse() {
            int len = chunk("MThd");
            if (len != 6)
                error(4, "bad header length");
            int f = (int)integer(8, 2), t = (int)integer(10, 2), d = (int)integer(12, 2);
            if (f > 2)
                error(8, "bad format");
            if (t == 0 || f == 0 && t != 1)
                error(10, "bad track count");
            if ((d & 32768) != 0)
                error(12, "smpte timing not supported");
            if (d == 0)
                error(12, "bad division");
            position = 14;
            List<List<Event>> tracks = new ArrayList<>();
            for (int track = 0; track < t; track++) {
                if (position == data.size())
                    error(position, "missing track");
                int length = chunk("MTrk");
                end = position + length;
                List<Event> events = new ArrayList<>();
                long tick = 0;
                int status = -1;
                while (position < end) {
                    if (!events.isEmpty() && events.get(events.size() - 1).end())
                        error(position, "event after end of track");
                    eventStart = position;
                    tick += vlq();
                    int statusPosition = position, b = read();
                    if (b < 128) {
                        if (status < 0)
                            error(statusPosition, "data byte without running status");
                        position--;
                    } else
                        status = b;
                    int code = status;
                    List<Integer> payload = new ArrayList<>();
                    if (status >= 128 && status <= 239) {
                        int count = (status >> 4) == 12 || (status >> 4) == 13 ? 1 : 2;
                        for (int i = 0; i < count; i++) {
                            int p = position, v = read();
                            if (v >= 128)
                                error(p, "bad data byte");
                            payload.add(v);
                        }
                    } else if (status == 240 || status == 247 || status == 255) {
                        boolean meta = status == 255;
                        if (meta)
                            code = 256 + read();
                        long count = vlq();
                        if (position + count > end)
                            error(eventStart, "truncated event");
                        payload.addAll(data.subList(position, position + (int)count));
                        position += (int)count;
                        if (meta)
                            validateMeta(code - 256, payload, statusPosition);
                        status = -1;
                    } else
                        error(statusPosition, "unknown status byte");
                    events.add(new Event(tick, code, payload));
                }
                if (events.isEmpty() || !events.get(events.size() - 1).end())
                    error(end, "missing end of track");
                tracks.add(events);
                end = data.size();
            }
            if (position < data.size())
                error(position, "extra data");
            return new Song(f, d, tracks);
        }
        void validateMeta(int type, List<Integer> d, int p) {
            int length = switch (type) {
                case 0, 89 -> 2;
                case 32 -> 1;
                case 47 -> 0;
                case 81 -> 3;
                case 84 -> 5;
                case 88 -> 4;
                default -> -1;
            };
            if (length >= 0 && d.size() != length)
                error(p, "bad meta length");
            boolean invalid = switch (type) {
                case 81 -> value(d) == 0;
                case 32 -> d.get(0) > 15;
                case 88 -> d.get(0) == 0 || d.get(1) > 6;
                case 89 -> {
                    int sf = d.get(0) >= 128 ? d.get(0) - 256 : d.get(0);
                    yield sf < -7 || sf > 7 || d.get(1) > 1;
                }
                default -> false;
            };
            if (invalid)
                error(p, "bad meta data");
        }
    }
    static long bounded(String text, long low, long high) {
        long n;
        try {
            n = Long.parseLong(text);
        } catch (NumberFormatException e) {
            fail("bad value");
            return 0;
        }
        if (n < low || n > high)
            fail("bad value");
        return n;
    }
    static void fields(String[] f, int n) {
        if (f.length != n)
            fail("bad value");
    }
    static List<Integer> blob(String[] fields, int start) {
        if (fields.length <= start)
            fail("bad value");
        int length = (int)bounded(fields[start], 0, 1000000);
        if (fields.length != start + (length == 0 ? 1 : 2))
            fail("bad value");
        if (length == 0)
            return List.of();
        String text = fields[start + 1];
        if (text.length() != length * 2 || !text.matches("[0-9A-F]*"))
            fail("bad value");
        List<Integer> data = new ArrayList<>();
        for (int i = 0; i < text.length(); i += 2)
            data.add(Integer.parseInt(text.substring(i, i + 2), 16));
        return data;
    }
    static Event parseEvent(String line) {
        String[] parts = line.split(" ", 4);
        long tick = Long.parseLong(parts[0]);
        String kind = parts[2];
        String tail = parts.length == 4 ? parts[3] : "";
        String[] f = tail.isEmpty() ? new String[0] : tail.split(" ", -1);
        int channelIndex = Arrays.asList(CHANNEL).indexOf(kind),
            textIndex = Arrays.asList(TEXT).indexOf(kind);
        int code;
        List<Integer> data = new ArrayList<>();
        if (channelIndex >= 0) {
            fields(f, channelIndex == 4 || channelIndex == 5 || channelIndex == 6 ? 2 : 3);
            int ch = (int)bounded(f[0], 1, 16);
            code = (channelIndex + 8) * 16 + ch - 1;
            if (channelIndex <= 2) {
                data.add(noteNumber(f[1]));
                data.add((int)bounded(f[2], 0, 127));
            } else if (channelIndex == 6) {
                int bend = (int)bounded(f[1], -8192, 8191) + 8192;
                data.add(bend % 128);
                data.add(bend / 128);
            } else
                for (int i = 1; i < f.length; i++)
                    data.add((int)bounded(f[i], 0, 127));
        } else if (textIndex >= 0) {
            if (tail.length() < 2 || tail.charAt(0) != '"' ||
                tail.charAt(tail.length() - 1) != '"' ||
                tail.substring(1, tail.length() - 1).contains("\""))
                fail("bad value");
            code = 257 + textIndex;
            for (int i = 1; i < tail.length() - 1; i++)
                data.add((int)tail.charAt(i));
        } else {
            Integer meta = META.entrySet()
                               .stream()
                               .filter(e -> e.getValue().equals(kind))
                               .map(Map.Entry::getKey)
                               .findFirst()
                               .orElse(null);
            if (kind.equals("SYSEX") || kind.equals("SYSEX_ESCAPE")) {
                code = kind.equals("SYSEX") ? 240 : 247;
                data = blob(f, 0);
            } else if (kind.equals("META")) {
                if (f.length < 2 || !f[0].matches("[0-9A-F]{2}"))
                    fail("bad value");
                int t = Integer.parseInt(f[0], 16);
                if (t <= 7 || META.containsKey(t))
                    fail("bad value");
                code = 256 + t;
                data = blob(f, 1);
            } else if (meta == null) {
                fail("unknown event type");
                return null;
            } else {
                code = 256 + meta;
                switch (meta) {
                case 0 -> {
                    fields(f, 1);
                    data = bytes(bounded(f[0], 0, 65535), 2);
                }
                case 32 -> {
                    fields(f, 1);
                    data.add((int)bounded(f[0], 1, 16) - 1);
                }
                case 47 -> fields(f, 0);
                case 81 -> {
                    fields(f, 1);
                    data = bytes(bounded(f[0], 1, 16777215), 3);
                }
                case 84 -> {
                    fields(f, 5);
                    for (String v : f)
                        data.add((int)bounded(v, 0, 255));
                }
                case 88 -> {
                    fields(f, 3);
                    String[] signature = f[0].split("/", -1);
                    if (signature.length != 2)
                        fail("bad value");
                    int numerator = (int)bounded(signature[0], 1, 255),
                        denominator = (int)bounded(signature[1], 1, 64);
                    if ((denominator & (denominator - 1)) != 0)
                        fail("bad value");
                    data.add(numerator);
                    data.add(Integer.numberOfTrailingZeros(denominator));
                    data.add((int)bounded(f[1], 0, 255));
                    data.add((int)bounded(f[2], 0, 255));
                }
                case 89 -> {
                    fields(f, 2);
                    boolean minor = f[1].equals("minor");
                    if (!minor && !f[1].equals("major"))
                        fail("bad value");
                    int index = Arrays.asList(minor ? MINOR : MAJOR).indexOf(f[0]);
                    if (index < 0)
                        fail("bad value");
                    data.add((index - 7 + 256) % 256);
                    data.add(minor ? 1 : 0);
                }
                case 127 -> data = blob(f, 0);
                }
            }
        }
        return new Event(tick, code, data);
    }
    static Song textSong(List<String> lines) {
        String[] h = lines.get(0).split(" ");
        int f, t, d;
        try {
            if (h.length != 4 || !h[0].equals("HEADER"))
                fail("bad header");
            f = (int)bounded(h[1], 0, 2);
            t = (int)bounded(h[2], 1, 65535);
            d = (int)bounded(h[3], 1, 32767);
            if (f == 0 && t != 1)
                fail("bad header");
        } catch (Failure e) {
            fail("line 1: bad header");
            return null;
        }
        List<List<Event>> tracks = new ArrayList<>();
        tracks.add(new ArrayList<>());
        int current = 0;
        for (int i = 1; i < lines.size(); i++) {
            try {
                Event e = parseEvent(lines.get(i));
                String[] words = lines.get(i).split(" ", 4);
                int track = Integer.parseInt(words[1]);
                if (track >= t)
                    fail("bad track");
                List<Event> events = tracks.get(current);
                boolean end = !events.isEmpty() && events.get(events.size() - 1).end();
                if (track < current)
                    fail("out of order");
                if (track > current && (!end || track > current + 1))
                    fail("missing end of track");
                if (track == current && end)
                    fail("event after end of track");
                if (track == current + 1) {
                    current++;
                    events = new ArrayList<>();
                    tracks.add(events);
                }
                if (!events.isEmpty() && e.tick < events.get(events.size() - 1).tick)
                    fail("out of order");
                events.add(e);
            } catch (Failure e) {
                fail("line " + (i + 1) + ": " + e.getMessage());
            }
        }
        List<Event> last = tracks.get(current);
        if (current + 1 < t || last.isEmpty() || !last.get(last.size() - 1).end())
            fail("line " + (lines.size() + 1) + ": missing end of track");
        return new Song(f, d, tracks);
    }
    static List<Integer> vlq(long n) {
        List<Integer> result = new ArrayList<>();
        result.add((int)(n & 127));
        while ((n >>= 7) > 0)
            result.add(0, (int)(n & 127) | 128);
        return result;
    }
    static void chunk(List<Integer> target, String id, List<Integer> data) {
        id.chars().forEach(target::add);
        target.addAll(bytes(data.size(), 4));
        target.addAll(data);
    }
    static void encode(Song s) {
        List<Integer> result = new ArrayList<>(), header = new ArrayList<>();
        header.addAll(bytes(s.format, 2));
        header.addAll(bytes(s.tracks.size(), 2));
        header.addAll(bytes(s.division, 2));
        chunk(result, "MThd", header);
        for (List<Event> track : s.tracks) {
            List<Integer> data = new ArrayList<>();
            long last = 0;
            int previous = -1;
            for (Event e : track) {
                data.addAll(vlq(e.tick - last));
                last = e.tick;
                if (e.channel()) {
                    int code = e.code;
                    List<Integer> payload = e.data;
                    if (zeroOff && (code & 240) == 128) {
                        code += 16;
                        payload = List.of(e.data.get(0), 0);
                    }
                    if (!running || previous != code)
                        data.add(code);
                    data.addAll(payload);
                    previous = code;
                } else {
                    previous = -1;
                    if (e.code < 256)
                        data.add(e.code);
                    else {
                        data.add(255);
                        data.add(e.code - 256);
                    }
                    data.addAll(vlq(e.data.size()));
                    data.addAll(e.data);
                }
            }
            chunk(result, "MTrk", data);
        }
        for (int i = 0; i < result.size(); i += 16)
            emit(hex(i, 4) + ": " +
                 result.subList(i, Math.min(i + 16, result.size()))
                     .stream()
                     .map(x -> hex(x, 2))
                     .collect(Collectors.joining(" ")));
        emit(result.size() + " bytes");
    }
    static Pairing pairing(Song s) {
        Map<Integer, Deque<Located>> queues = new HashMap<>();
        List<Note> notes = new ArrayList<>();
        List<Located> unmatched = new ArrayList<>();
        for (Located located : global(s)) {
            Event e = located.event;
            if (!e.on() && !e.off())
                continue;
            int key = e.channelNumber() * 128 + e.data.get(0);
            Deque<Located> queue = queues.computeIfAbsent(key, k -> new ArrayDeque<>());
            if (e.on())
                queue.addLast(located);
            else if (queue.isEmpty())
                unmatched.add(located);
            else
                notes.add(new Note(queue.removeFirst(), located));
        }
        for (Deque<Located> queue : queues.values())
            unmatched.addAll(queue);
        Map<Event, Integer> order = new IdentityHashMap<>();
        int i = 0;
        for (Located e : global(s))
            order.put(e.event, i++);
        notes.sort(Comparator.comparingLong(Note::start)
                       .thenComparingInt(Note::channel)
                       .thenComparingInt(Note::pitch)
                       .thenComparingInt(n -> order.get(n.on.event)));
        unmatched.sort(Comparator.comparingInt(e -> order.get(e.event)));
        return new Pairing(notes, unmatched);
    }
    static long micros(Song s, long tick) {
        long total = 0, last = 0, tempo = 500000;
        for (Located l : global(s))
            if (l.event.tick <= tick && l.event.code == 337) {
                total += (l.event.tick - last) * tempo;
                last = l.event.tick;
                tempo = value(l.event.data);
            }
        return (total + (tick - last) * tempo) / s.division;
    }
    static String time(Song s, long tick) {
        long us = micros(s, tick);
        return us / 1000 + "." + String.format(Locale.ROOT, "%03d", us % 1000);
    }
    static String bar(Song s, long tick) {
        long start = 0, number = 1, numerator = 4, beat = s.division;
        for (Located l : global(s))
            if (l.event.tick <= tick && l.event.code == 344) {
                long length = numerator * beat;
                number += (l.event.tick - start + length - 1) / length;
                start = l.event.tick;
                numerator = l.event.data.get(0);
                beat = s.division * 4L / (1L << l.event.data.get(1));
            }
        long x = tick - start, length = numerator * beat;
        return (number + x / length) + ":" + (x % length / beat + 1) + ":" + x % beat;
    }
    static void notes(Pairing p) {
        emit("notes " + p.notes.size() + " unmatched " + p.unmatched.size());
        for (Note n : p.notes)
            emit(n.start() + " " + n.length() + " " + n.channel() + " " + noteName(n.pitch()) +
                 " " + n.on.event.data.get(1));
        for (Located l : p.unmatched)
            emit("unmatched " + (l.event.on() ? "on" : "off") + " " + l.event.tick + " " + l.track +
                 " " + l.event.channelNumber() + " " + noteName(l.event.data.get(0)));
    }
    static boolean range(long n, long low, long high) {
        return n >= low && n <= high;
    }
    static void execute(String[] w, BufferedReader reader) throws IOException {
        String c = w[0];
        if (c.equals("HEX") || c.equals("TEXT")) {
            int k = Integer.parseInt(w[2]);
            List<String> lines = new ArrayList<>();
            for (int i = 0; i < k; i++)
                lines.add(reader.readLine());
            Song s;
            if (c.equals("TEXT"))
                s = textSong(lines);
            else {
                List<Integer> data = new ArrayList<>();
                for (String line : lines)
                    for (String b : line.split(" "))
                        data.add(Integer.parseInt(b, 16));
                s = new Parser(data).parse();
            }
            songs.put(w[1], s);
            emit("loaded " + w[1] + " " + description(s));
            return;
        }
        if (!Set.of("DECODE", "ENCODE", "TIMING", "NOTES", "STATS", "ROLL", "TRANSPOSE", "QUANTIZE",
                    "VELOCITY", "TEMPO", "FILTER", "MERGE", "SPLIT", "COPY", "LIST", "RUNNING",
                    "NOTEOFF")
                 .contains(c))
            fail("unknown command");
        if (c.equals("LIST")) {
            if (songs.isEmpty())
                emit("no songs");
            else
                songs.forEach((name, s) -> emit(name + " " + description(s)));
            return;
        }
        if (c.equals("RUNNING") || c.equals("NOTEOFF")) {
            if (!(c.equals("RUNNING") ? Set.of("ON", "OFF") : Set.of("ZERO", "KEEP"))
                     .contains(w[1]))
                fail("bad argument");
            if (c.equals("RUNNING"))
                running = w[1].equals("ON");
            else
                zeroOff = w[1].equals("ZERO");
            emit(c.toLowerCase(Locale.ROOT) + " " + w[1].toLowerCase(Locale.ROOT));
            return;
        }
        Song s = songs.get(w[1]);
        if (s == null)
            fail("no song " + w[1]);
        long a = 0, b = 0, d = 0;
        if (Set.of("TRANSPOSE", "QUANTIZE", "VELOCITY", "TEMPO", "ROLL").contains(c)) {
            a = Long.parseLong(w[2]);
            if (w.length > 3)
                b = Long.parseLong(w[3]);
            if (c.equals("ROLL"))
                d = Long.parseLong(w[4]);
            boolean valid = switch (c) {
                case "TRANSPOSE" -> range(a, -127, 127) && (w.length == 3 || range(b, 1, 16));
                case "QUANTIZE" -> range(a, 1, 1000000) && range(b, 0, 100);
                case "VELOCITY" -> range(a, 0, 1000) && range(b, -127, 127);
                case "TEMPO" -> range(a, 1, 1000) && range(b, 1, 1000);
                default ->
                    range(a, 0, 10000000) && range(b, 1, 10000000) && range(d, 1, 10000000) &&
                        b > a && (b - a + d - 1) / d <= 64;
            };
            if (!valid)
                fail("bad argument");
        }
        if (c.equals("FILTER"))
            for (int i = 2; i < w.length; i++)
                if (!range(Long.parseLong(w[i]), 1, 16))
                    fail("bad argument");
        if ((c.equals("TIMING") || c.equals("STATS")) && s.format == 2)
            fail("format 2 not supported");
        switch (c) {
        case "COPY" -> {
            songs.put(w[2], s.copy());
            emit("copied " + w[1] + " to " + w[2]);
        }
        case "DECODE" -> {
            emit("HEADER " + s.format + " " + s.tracks.size() + " " + s.division);
            for (int t = 0; t < s.tracks.size(); t++)
                for (Event e : s.tracks.get(t))
                    emit(eventText(e, t));
        }
        case "ENCODE" -> encode(s);
        case "TIMING" -> {
            for (Located l : global(s))
                emit(l.event.tick + " " + l.track + " " + l.event.kind() + " " +
                     time(s, l.event.tick) + " " + bar(s, l.event.tick));
            emit("end " + s.length() + " " + time(s, s.length()) + " " + bar(s, s.length()));
        }
        case "NOTES" -> notes(pairing(s));
        case "TRANSPOSE" -> {
            int kept = 0, dropped = 0;
            List<String> removed = new ArrayList<>();
            for (int t = 0; t < s.tracks.size(); t++) {
                List<Event> track = new ArrayList<>();
                for (Event e : s.tracks.get(t)) {
                    if (e.channel() && (e.code >> 4) <= 10 &&
                        (w.length == 3 || e.channelNumber() == b)) {
                        int original = e.data.get(0);
                        long pitch = original + a;
                        if (pitch < 0 || pitch > 127) {
                            dropped++;
                            removed.add("dropped " + e.tick + " " + t + " " + e.kind() + " " +
                                        e.channelNumber() + " " + noteName(original));
                            continue;
                        }
                        e.data.set(0, (int)pitch);
                        kept++;
                    }
                    track.add(e);
                }
                s.tracks.set(t, track);
            }
            emit("transposed " + kept + " dropped " + dropped);
            removed.forEach(Main::emit);
        }
        case "QUANTIZE" -> {
            Pairing p = pairing(s);
            List<Note> targets = new ArrayList<>(p.notes);
            for (Located l : p.unmatched)
                if (l.event.on())
                    targets.add(new Note(l, l));
            int moved = 0;
            for (Note n : targets) {
                long tick = n.start(), lower = tick / a * a,
                     g = tick - lower <= lower + a - tick ? lower : lower + a;
                long delta = Math.floorDiv(2 * (g - tick) * b + 100, 200);
                n.on.event.tick += delta;
                if (n.off.event != n.on.event)
                    n.off.event.tick += delta;
                if (delta != 0)
                    moved++;
            }
            for (List<Event> track : s.tracks) {
                Event end = track.remove(track.size() - 1);
                track.sort(Comparator.comparingLong(e -> e.tick));
                for (Event e : track)
                    end.tick = Math.max(end.tick, e.tick);
                track.add(end);
            }
            emit("quantized " + targets.size() + " moved " + moved);
        }
        case "VELOCITY" -> {
            int count = 0, clamped = 0;
            for (Located l : global(s))
                if (l.event.on()) {
                    long v = (l.event.data.get(1) * a + 50) / 100 + b;
                    count++;
                    if (v < 1 || v > 127)
                        clamped++;
                    l.event.data.set(1, (int)Math.max(1, Math.min(127, v)));
                }
            emit("velocity " + count + " clamped " + clamped);
        }
        case "TEMPO" -> {
            Song edited = s.copy();
            int count = 0;
            boolean atZero = false;
            for (Located l : global(edited))
                if (l.event.code == 337) {
                    long v = (2 * value(l.event.data) * b + a) / (2 * a);
                    if (!range(v, 1, 16777215))
                        fail("tempo out of range");
                    l.event.data = bytes(v, 3);
                    count++;
                    if (l.event.tick == 0)
                        atZero = true;
                }
            long inserted = (1000000 * b + a) / (2 * a);
            if (!atZero) {
                if (!range(inserted, 1, 16777215))
                    fail("tempo out of range");
                edited.tracks.get(0).add(0, new Event(0, 337, bytes(inserted, 3)));
            }
            songs.put(w[1], edited);
            emit("scaled " + count);
            if (!atZero)
                emit("inserted 0 0 TEMPO " + inserted);
        }
        case "FILTER" -> {
            Set<Integer> channels = new HashSet<>();
            for (int i = 2; i < w.length; i++)
                channels.add(Integer.parseInt(w[i]));
            int before = s.count();
            for (List<Event> track : s.tracks)
                track.removeIf(e -> e.channel() && !channels.contains(e.channelNumber()));
            emit("removed " + (before - s.count()));
        }
        case "MERGE" -> {
            if (s.format != 1)
                fail("not format 1");
            int original = s.tracks.size();
            long length = s.length();
            List<Event> track = new ArrayList<>();
            for (Located l : global(s))
                if (!l.event.end())
                    track.add(l.event);
            track.add(new Event(length, 303, List.of()));
            s.tracks = new ArrayList<>(List.of(track));
            s.format = 0;
            emit("merged " + original + " tracks events " + s.count());
        }
        case "SPLIT" -> {
            if (s.format != 0)
                fail("not format 0");
            long length = s.length();
            TreeMap<Integer, List<Event>> groups = new TreeMap<>();
            groups.put(0, new ArrayList<>());
            for (Event e : s.tracks.get(0))
                if (!e.end())
                    groups
                        .computeIfAbsent(e.channel() ? e.channelNumber() : 0,
                                         key -> new ArrayList<>())
                        .add(e);
            s.tracks = new ArrayList<>(groups.values());
            for (List<Event> track : s.tracks)
                track.add(new Event(length, 303, List.of()));
            s.format = 1;
            emit("split tracks " + s.tracks.size() + " events " + s.count());
        }
        case "STATS" -> {
            Pairing p = pairing(s);
            emit(description(s));
            emit("notes " + p.notes.size() + " unmatched " + p.unmatched.size());
            for (int ch = 1; ch <= 16; ch++) {
                int count = 0, low = 128, high = -1;
                for (Note n : p.notes)
                    if (n.channel() == ch) {
                        count++;
                        low = Math.min(low, n.pitch());
                        high = Math.max(high, n.pitch());
                    }
                if (count > 0)
                    emit("channel " + ch + " notes " + count + " range " + noteName(low) + " " +
                         noteName(high));
            }
            if (p.notes.isEmpty())
                emit("range none");
            else
                emit("range " +
                     noteName(p.notes.stream().mapToInt(Note::pitch).min().orElseThrow()) + " " +
                     noteName(p.notes.stream().mapToInt(Note::pitch).max().orElseThrow()));
            emit("length " + s.length() + " ticks " + time(s, s.length()) + " ms");
            TreeMap<Long, Integer> changes = new TreeMap<>();
            for (Note n : p.notes)
                if (n.length() > 0) {
                    changes.merge(n.start(), 1, Integer::sum);
                    changes.merge(n.start() + n.length(), -1, Integer::sum);
                }
            int active = 0, maximum = 0;
            long first = 0;
            for (Map.Entry<Long, Integer> change : changes.entrySet()) {
                active += change.getValue();
                if (active > maximum) {
                    maximum = active;
                    first = change.getKey();
                }
            }
            emit(maximum == 0 ? "polyphony 0" : "polyphony " + maximum + " at " + first);
        }
        case "ROLL" -> {
            Pairing p = pairing(s);
            int columns = (int)((b - a + d - 1) / d);
            boolean any = false;
            for (int pitch = 127; pitch >= 0; pitch--) {
                StringBuilder line = new StringBuilder();
                boolean visible = false;
                for (int i = 0; i < columns; i++) {
                    long tick = a + i * d;
                    boolean start = false, sustain = false;
                    for (Note n : p.notes)
                        if (n.pitch() == pitch) {
                            start |= tick <= n.start() && n.start() < tick + d;
                            sustain |= n.start() <= tick && tick < n.start() + n.length();
                        }
                    char mark = start ? '#' : sustain ? '=' : '.';
                    line.append(mark);
                    visible |= mark != '.';
                }
                if (visible) {
                    emit(String.format("%-4s", noteName(pitch)) + " " + line);
                    any = true;
                }
            }
            if (!any)
                emit("empty");
        }
        }
    }
    public static void main(String[] args) throws IOException {
        BufferedReader reader = new BufferedReader(new InputStreamReader(System.in));
        int n = Integer.parseInt(reader.readLine());
        for (int i = 0; i < n; i++) {
            String[] words = reader.readLine().split(" ");
            try {
                execute(words, reader);
            } catch (Failure error) {
                emit("error: " + error.getMessage());
            }
        }
        System.out.print(output);
    }
}
