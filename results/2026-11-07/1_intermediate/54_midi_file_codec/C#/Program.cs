using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

record Event(long Tick, int Status, int Meta, byte[] Data) {
    public bool Channel => Status < 0xF0;
    public int Ch => (Status & 15) + 1;
    public int Code => Status >> 4;
    public bool On => Channel && Code == 9 && Data[1] > 0;
    public bool Off => Channel && (Code == 8 || Code == 9 && Data[1] == 0);
    public bool End => Status == 255 && Meta == 47;
    public long Number => Data.Aggregate(0L, (a, b) => a * 256 + b);
    public Event Copy() => this with { Data = (byte[])Data.Clone() };
}
class Song {
    public int Format, Division;
    public List<List<Event>> Tracks = new();
    public int Count => Tracks.Sum(t => t.Count);
    public long Length => Tracks.Max(t => t.Last().Tick);
    public Song
    Copy() => new() { Format = Format, Division = Division,
                      Tracks = Tracks.Select(t => t.Select(e => e.Copy()).ToList()).ToList() };
    public List<(Event E, int Track, int Index)>
    Global() => Tracks.SelectMany((t, tr) => t.Select((e, i) => (E: e, Track: tr, Index: i)))
                    .OrderBy(x => x.E.Tick)
                    .ThenBy(x => x.Track)
                    .ThenBy(x => x.Index)
                    .ToList();
}
record Note(Event On, Event Off, int Order);
class MidiError : Exception {
    public MidiError(string message) : base(message) {
    }
}
class Program {
    static readonly string[] channelTypes = { "NOTE_OFF",  "NOTE_ON", "POLY_PRESSURE",
                                              "CONTROL",   "PROGRAM", "CHANNEL_PRESSURE",
                                              "PITCH_BEND" };
    static readonly string[] textTypes = { "TEXT_EVENT",      "COPYRIGHT", "TRACK_NAME",
                                           "INSTRUMENT_NAME", "LYRIC",     "MARKER",
                                           "CUE_POINT" };
    static readonly Dictionary<int, string> metaTypes =
        new() { [0] = "SEQUENCE_NUMBER", [32] = "CHANNEL_PREFIX",     [47] = "END_OF_TRACK",
                [81] = "TEMPO",          [84] = "SMPTE_OFFSET",       [88] = "TIME_SIGNATURE",
                [89] = "KEY_SIGNATURE",  [127] = "SEQUENCER_SPECIFIC" };
    static readonly string[] pitchNames = { "C",  "C#", "D",  "D#", "E",  "F",
                                            "F#", "G",  "G#", "A",  "A#", "B" };
    static readonly string[][] keys = { "Cb Gb Db Ab Eb Bb F C G D A E B F# C#".Split(' '),
                                        "Ab Eb Bb F C G D A E B F# C# G# D# A#".Split(' ') };
    static readonly SortedDictionary<string, Song> songs = new(StringComparer.Ordinal);
    static bool running = true, zeroOff;
    static void Fail(string message) => throw new MidiError(message);
    static bool Range(long x, long lo, long hi) => lo <= x && x <= hi;
    static long I(string text) => long.Parse(text);
    static byte[] Bytes(long value, int n) =>
        Enumerable.Range(0, n).Select(i => (byte)(value >> (8 * (n - 1 - i)) & 255)).ToArray();
    static string Pitch(int p) => pitchNames[p % 12] + (p / 12 - 1);
    static int
    ParsePitch(string text) => Enumerable.Range(0, 128).FirstOrDefault(p => Pitch(p) == text, -1);
    static string Type(Event e) => e.Channel         ? channelTypes[e.Code - 8]
                                   : e.Status == 240 ? "SYSEX"
                                   : e.Status == 247 ? "SYSEX_ESCAPE"
                                   : Range(e.Meta, 1, 7)
                                       ? textTypes[e.Meta - 1]
                                       : metaTypes.GetValueOrDefault(e.Meta, "META");
    static string DataText(byte[] data) => data.Length +
                                           (data.Length > 0 ? " " + Convert.ToHexString(data) : "");
    static string Fields(Event e) {
        byte[] d = e.Data;
        if (e.Channel) {
            string value = e.Code is 8 or 9 or 10 ? Pitch(d[0]) + " " + d[1]
                           : e.Code == 11         ? d[0] + " " + d[1]
                           : e.Code == 14         ? (d[0] + 128 * d[1] - 8192).ToString()
                                                  : d[0].ToString();
            return e.Ch + " " + value;
        }
        if (e.Status != 255)
            return DataText(d);
        if (Range(e.Meta, 1, 7))
            return "\"" + Encoding.ASCII.GetString(d) + "\"";
        return e.Meta switch { 0 or
                               81 => e.Number.ToString(),
                               32 => (d[0] + 1).ToString(),
                               47 => "",
                               84 => string.Join(" ", d),
                               88 => d[0] + "/" + (1 << d[1]) + " " + d[2] + " " + d[3],
                               89 =>
                                   keys[d[1]][(sbyte)d[0] + 7] + (d[1] == 0 ? " major" : " minor"),
                               127 => DataText(d),
                               _ => e.Meta.ToString("X2") + " " + DataText(d) };
    }
    static string Line(Event e, int track) => e.Tick + " " + track + " " + Type(e) +
                                              (Fields(e) == "" ? "" : " " + Fields(e));
    static void ValidateMeta(int meta, byte[] d, int position) {
        int length = meta switch {
            0 => 2,
            32 => 1,
            47 => 0,
            81 => 3,
            84 => 5,
            88 => 4,
            89 => 2,
            _ => -1
        };
        if (length >= 0 && d.Length != length)
            Fail("byte " + position + ": bad meta length");
        bool bad = meta == 81 && d.All(x => x == 0) || meta == 32 && d[0] > 15 ||
                   meta == 88 && (d[0] == 0 || d[1] > 6) ||
                   meta == 89 && ((sbyte)d[0] < -7 || (sbyte)d[0] > 7 || d[1] > 1);
        if (bad)
            Fail("byte " + position + ": bad meta data");
    }
    static Song ParseHex(byte[] data) {
        long ReadBig(int p, int n) {
            long v = 0;
            for (int i = 0; i < n; i++)
                v = v * 256 + data[p + i];
            return v;
        }
        int Chunk(int p, string id) {
            if (data.Length - p < 8) {
                Fail("byte " + p + ": truncated chunk");
            }
            if (Encoding.ASCII.GetString(data, p, 4) != id)
                Fail("byte " + p + ": bad chunk id");
            long end = p + 8L + ReadBig(p + 4, 4);
            if (end > data.Length)
                Fail("byte " + p + ": truncated chunk");
            return (int)end;
        }
        int headerEnd = Chunk(0, "MThd");
        if (headerEnd != 14)
            Fail("byte 4: bad header length");
        int f = (int)ReadBig(8, 2), tracks = (int)ReadBig(10, 2), division = (int)ReadBig(12, 2);
        if (f > 2)
            Fail("byte 8: bad format");
        if (tracks == 0 || f == 0 && tracks != 1)
            Fail("byte 10: bad track count");
        if ((division & 32768) != 0)
            Fail("byte 12: smpte timing not supported");
        if (division == 0)
            Fail("byte 12: bad division");
        Song song = new() { Format = f, Division = division };
        int p = 14;
        for (int track = 0; track < tracks; track++) {
            if (p == data.Length)
                Fail("byte " + p + ": missing track");
            int end = Chunk(p, "MTrk");
            p += 8;
            int status = 0;
            long tick = 0;
            var events = new List<Event>();
            while (p < end) {
                if (events.Count > 0 && events.Last().End)
                    Fail("byte " + p + ": event after end of track");
                int start = p;
                int ReadByte() {
                    if (p >= end)
                        Fail("byte " + start + ": truncated event");
                    return data[p++];
                }
                int Var() {
                    int at = p, value = 0;
                    for (int i = 0; i < 4; i++) {
                        int b = ReadByte();
                        value = value * 128 + (b & 127);
                        if (b < 128)
                            return value;
                    }
                    Fail("byte " + at + ": variable-length value too long");
                    return 0;
                }
                tick += Var();
                if (p >= end)
                    Fail("byte " + start + ": truncated event");
                int position = p, current;
                if (data[p] < 128) {
                    if (status == 0)
                        Fail("byte " + p + ": data byte without running status");
                    current = status;
                } else
                    current = ReadByte();
                int meta = -1;
                byte[] d;
                if (current < 240) {
                    status = current;
                    d = new byte[(current >> 4) is 12 or 13 ? 1 : 2];
                    for (int j = 0; j < d.Length; j++) {
                        int at = p, b = ReadByte();
                        if (b >= 128)
                            Fail("byte " + at + ": bad data byte");
                        d[j] = (byte)b;
                    }
                } else if (current is 240 or 247 or 255) {
                    status = 0;
                    if (current == 255)
                        meta = ReadByte();
                    int length = Var();
                    if (length > end - p)
                        Fail("byte " + start + ": truncated event");
                    d = data.Skip(p).Take(length).ToArray();
                    p += length;
                    if (current == 255)
                        ValidateMeta(meta, d, position);
                } else {
                    Fail("byte " + position + ": unknown status byte");
                    return song;
                }
                events.Add(new(tick, current, meta, d));
            }
            if (events.Count == 0 || !events.Last().End)
                Fail("byte " + end + ": missing end of track");
            song.Tracks.Add(events);
        }
        if (p != data.Length)
            Fail("byte " + p + ": extra data");
        return song;
    }
    static Event TextEvent(long tick, string type, string fields) {
        string[] a = fields == "" ? Array.Empty<string>() : fields.Split(' ');
        void Require(bool valid) {
            if (!valid)
                Fail("bad value");
        }
        long Num(int i, long lo, long hi) {
            if (i >= a.Length || !long.TryParse(a[i], out long v) || !Range(v, lo, hi)) {
                Fail("bad value");
                return 0;
            }
            return v;
        }
        byte[] Blob(int index) {
            long length = Num(index, 0, 1000000);
            Require(a.Length == index + (length == 0 ? 1 : 2));
            if (length == 0)
                return Array.Empty<byte>();
            string text = a[index + 1];
            Require(text.Length == length * 2 &&
                    text.All(c => c is >= '0' and <= '9' or >= 'A' and <= 'F'));
            return Convert.FromHexString(text);
        }
        int code = Array.IndexOf(channelTypes, type);
        if (code >= 0) {
            int high = code + 8;
            Require(a.Length == (high is 12 or 13 or 14 ? 2 : 3));
            int ch = (int)Num(0, 1, 16);
            byte[] d;
            if (high is 8 or 9 or 10) {
                int pitch = ParsePitch(a[1]);
                Require(pitch >= 0);
                d = new[] { (byte)pitch, (byte)Num(2, 0, 127) };
            } else if (high == 14) {
                int value = (int)Num(1, -8192, 8191) + 8192;
                d = new[] { (byte)(value & 127), (byte)(value >> 7) };
            } else
                d = high == 11 ? new[] { (byte)Num(1, 0, 127), (byte)Num(2, 0, 127) }
                               : new[] { (byte)Num(1, 0, 127) };
            return new(tick, (high << 4) + ch - 1, -1, d);
        }
        if (type is "SYSEX" or "SYSEX_ESCAPE")
            return new(tick, type == "SYSEX" ? 240 : 247, -1, Blob(0));
        int textIndex = Array.IndexOf(textTypes, type);
        if (textIndex >= 0) {
            Require(fields.Length >= 2 && fields[0] == '"' && fields[^1] == '"' &&
                    !fields[1.. ^ 1].Contains('"'));
            return new(tick, 255, textIndex + 1, Encoding.ASCII.GetBytes(fields[1.. ^ 1]));
        }
        int meta =
            metaTypes.FirstOrDefault(x => x.Value == type, new KeyValuePair<int, string>(-1, ""))
                .Key;
        if (type == "META") {
            Require(a.Length >= 2 && a[0].Length == 2 &&
                    a[0].All(c => c is >= '0' and <= '9' or >= 'A' and <= 'F'));
            meta = Convert.ToInt32(a[0], 16);
            Require(!metaTypes.ContainsKey(meta) && !Range(meta, 1, 7));
            return new(tick, 255, meta, Blob(1));
        }
        if (meta < 0) {
            Fail("unknown event type");
        }
        byte[] data = Array.Empty<byte>();
        switch (meta) {
        case 0:
            Require(a.Length == 1);
            data = Bytes(Num(0, 0, 65535), 2);
            break;
        case 32:
            Require(a.Length == 1);
            data = new[] { (byte)(Num(0, 1, 16) - 1) };
            break;
        case 47:
            Require(a.Length == 0);
            break;
        case 81:
            Require(a.Length == 1);
            data = Bytes(Num(0, 1, 16777215), 3);
            break;
        case 84:
            Require(a.Length == 5);
            data = Enumerable.Range(0, 5).Select(i => (byte)Num(i, 0, 255)).ToArray();
            break;
        case 88:
            Require(a.Length == 3);
            string[] signature = a[0].Split('/');
            Require(signature.Length == 2 && long.TryParse(signature[0], out _) &&
                    long.TryParse(signature[1], out _));
            long nn = I(signature[0]), dd = I(signature[1]);
            Require(Range(nn, 1, 255) && new long[] { 1, 2, 4, 8, 16, 32, 64 }.Contains(dd));
            int exponent = 0;
            while ((1L << exponent) != dd)
                exponent++;
            data = new[] { (byte)nn, (byte)exponent, (byte)Num(1, 0, 255), (byte)Num(2, 0, 255) };
            break;
        case 89:
            Require(a.Length == 2 && a[1] is "major" or "minor");
            int minor = a[1] == "minor" ? 1 : 0, key = Array.IndexOf(keys[minor], a[0]);
            Require(key >= 0);
            data = new[] { unchecked((byte)(key - 7)), (byte)minor };
            break;
        case 127:
            data = Blob(0);
            break;
        }
        return new(tick, 255, meta, data);
    }
    static Song ParseText(string[] lines) {
        string[] h = lines[0].Split(' ');
        if (h.Length != 4 || h[0] != "HEADER" || !int.TryParse(h[1], out int f) ||
            !int.TryParse(h[2], out int tracks) || !int.TryParse(h[3], out int division) ||
            !Range(f, 0, 2) || !Range(tracks, 1, 65535) || !Range(division, 1, 32767) ||
            f == 0 && tracks != 1) {
            Fail("line 1: bad header");
            return new();
        }
        Song s = new() { Format = f, Division = division, Tracks = new() { new() } };
        int current = 0;
        for (int i = 1; i < lines.Length; i++) {
            string[] a = lines[i].Split(' ', 4);
            long tick = I(a[0]);
            int track = (int)I(a[1]);
            Event e;
            try {
                e = TextEvent(tick, a[2], a.Length == 4 ? a[3] : "");
            } catch (MidiError error) {
                Fail("line " + (i + 1) + ": " + error.Message);
                return s;
            }
            void Bad(string reason) => Fail("line " + (i + 1) + ": " + reason);
            if (track >= tracks)
                Bad("bad track");
            bool end = s.Tracks[current].Count > 0 && s.Tracks[current].Last().End;
            if (track < current)
                Bad("out of order");
            if (track > current && (!end || track > current + 1))
                Bad("missing end of track");
            if (track == current && end)
                Bad("event after end of track");
            if (track == current + 1) {
                current++;
                s.Tracks.Add(new());
            }
            if (s.Tracks[current].Count > 0 && tick < s.Tracks[current].Last().Tick)
                Bad("out of order");
            s.Tracks[current].Add(e);
        }
        if (current + 1 < tracks || s.Tracks[current].Count == 0 || !s.Tracks[current].Last().End)
            Fail("line " + (lines.Length + 1) + ": missing end of track");
        return s;
    }
    static byte[] Var(long value) {
        List<byte> b = new() { (byte)(value & 127) };
        while ((value >>= 7) > 0)
            b.Insert(0, (byte)((value & 127) | 128));
        return b.ToArray();
    }
    static void Encode(Song song) {
        List<byte> all = new(Encoding.ASCII.GetBytes("MThd"));
        all.AddRange(Bytes(6, 4));
        all.AddRange(Bytes(song.Format, 2));
        all.AddRange(Bytes(song.Tracks.Count, 2));
        all.AddRange(Bytes(song.Division, 2));
        foreach (var track in song.Tracks) {
            List<byte> data = new();
            long previous = 0;
            int last = -1;
            foreach (Event e in track) {
                data.AddRange(Var(e.Tick - previous));
                previous = e.Tick;
                if (e.Channel) {
                    int status = e.Status;
                    byte[] d = e.Data;
                    if (zeroOff && e.Code == 8) {
                        status = 0x90 + e.Ch - 1;
                        d = new[] { d[0], (byte)0 };
                    }
                    if (!running || status != last)
                        data.Add((byte)status);
                    data.AddRange(d);
                    last = status;
                } else {
                    last = -1;
                    data.Add((byte)e.Status);
                    if (e.Status == 255)
                        data.Add((byte)e.Meta);
                    data.AddRange(Var(e.Data.Length));
                    data.AddRange(e.Data);
                }
            }
            all.AddRange(Encoding.ASCII.GetBytes("MTrk"));
            all.AddRange(Bytes(data.Count, 4));
            all.AddRange(data);
        }
        for (int i = 0; i < all.Count; i += 16)
            Console.WriteLine(i.ToString("X4") + ": " +
                              string.Join(" ", all.Skip(i).Take(16).Select(x => x.ToString("X2"))));
        Console.WriteLine(all.Count + " bytes");
    }
    static (List<Note> Notes, List<(Event E, int Track, int Index)> Unmatched) Pair(Song song) {
        var all = song.Global();
        var queues = new Dictionary<(int, int), Queue<(Event E, int Order)>>();
        var notes = new List<Note>();
        var paired = new HashSet<Event>(ReferenceEqualityComparer.Instance);
        for (int i = 0; i < all.Count; i++) {
            Event e = all[i].E;
            if (!e.On && !e.Off)
                continue;
            var key = (e.Ch, (int)e.Data[0]);
            if (!queues.ContainsKey(key))
                queues[key] = new();
            if (e.On)
                queues[key].Enqueue((e, i));
            else if (queues[key].Count > 0) {
                var on = queues[key].Dequeue();
                notes.Add(new(on.E, e, on.Order));
                paired.Add(on.E);
                paired.Add(e);
            }
        }
        notes = notes.OrderBy(n => n.On.Tick)
                    .ThenBy(n => n.On.Ch)
                    .ThenBy(n => n.On.Data[0])
                    .ThenBy(n => n.Order)
                    .ToList();
        return (notes, all.Where(x => (x.E.On || x.E.Off) && !paired.Contains(x.E)).ToList());
    }
    static (string Time, string Bar) Position(Song song, long tick, bool bars = true) {
        long sum = 0, last = 0, tempo = 500000, start = 0, bar = 1, nn = 4, beat = song.Division;
        foreach (var item in song.Global().Where(x => x.E.Tick <= tick)) {
            Event e = item.E;
            if (e.Status != 255)
                continue;
            if (e.Meta == 81) {
                sum += (e.Tick - last) * tempo;
                last = e.Tick;
                tempo = e.Number;
            }
            if (e.Meta == 88 && bars) {
                long size = nn * beat;
                bar += (e.Tick - start + size - 1) / size;
                start = e.Tick;
                nn = e.Data[0];
                beat = song.Division * 4 / (1 << e.Data[1]);
            }
        }
        long micro = (sum + (tick - last) * tempo) / song.Division, x = tick - start;
        return (micro / 1000 + "." + (micro % 1000).ToString("D3"),
                bars ? (bar + x / (nn * beat)) + ":" + (x % (nn * beat) / beat + 1) + ":" + x % beat
                     : "");
    }
    static void Notes(Song s) {
        var pair = Pair(s);
        Console.WriteLine("notes " + pair.Notes.Count + " unmatched " + pair.Unmatched.Count);
        foreach (Note n in pair.Notes)
            Console.WriteLine(n.On.Tick + " " + (n.Off.Tick - n.On.Tick) + " " + n.On.Ch + " " +
                              Pitch(n.On.Data[0]) + " " + n.On.Data[1]);
        foreach (var x in pair.Unmatched)
            Console.WriteLine("unmatched " + (x.E.On ? "on" : "off") + " " + x.E.Tick + " " +
                              x.Track + " " + x.E.Ch + " " + Pitch(x.E.Data[0]));
    }
    static string Summary(Song s) => "format " + s.Format + " tracks " + s.Tracks.Count +
                                     " division " + s.Division + " events " + s.Count;
    static long Floor(long x, long divisor) => x >= 0 ? x / divisor
                                                      : -((-x + divisor - 1) / divisor);
    static void Execute(string[] a) {
        string cmd = a[0];
        string[] known = { "DECODE",    "ENCODE",   "TIMING",   "NOTES",   "STATS",  "ROLL",
                           "TRANSPOSE", "QUANTIZE", "VELOCITY", "TEMPO",   "FILTER", "MERGE",
                           "SPLIT",     "COPY",     "LIST",     "RUNNING", "NOTEOFF" };
        if (!known.Contains(cmd))
            Fail("unknown command");
        if (cmd == "LIST") {
            if (songs.Count == 0)
                Console.WriteLine("no songs");
            foreach (var item in songs)
                Console.WriteLine(item.Key + " " + Summary(item.Value));
            return;
        }
        if (cmd is "RUNNING" or "NOTEOFF") {
            if (cmd == "RUNNING") {
                if (a[1] is not("ON" or "OFF"))
                    Fail("bad argument");
                running = a[1] == "ON";
            } else {
                if (a[1] is not("ZERO" or "KEEP"))
                    Fail("bad argument");
                zeroOff = a[1] == "ZERO";
            }
            Console.WriteLine(cmd.ToLowerInvariant() + " " + a[1].ToLowerInvariant());
            return;
        }
        if (!songs.ContainsKey(a[1]))
            Fail("no song " + a[1]);
        Song s = songs[a[1]];
        long n = 0, second = 0, third = 0;
        if (cmd is "TRANSPOSE" or "QUANTIZE" or "VELOCITY" or "TEMPO" or "ROLL")
            n = I(a[2]);
        if (cmd is "QUANTIZE" or "VELOCITY" or "TEMPO" or "ROLL")
            second = I(a[3]);
        if (cmd == "ROLL")
            third = I(a[4]);
        bool bad = cmd switch { "TRANSPOSE" =>
                                    !Range(n, -127, 127) || a.Length == 4 && !Range(I(a[3]), 1, 16),
                                "QUANTIZE" => !Range(n, 1, 1000000) || !Range(second, 0, 100),
                                "VELOCITY" => !Range(n, 0, 1000) || !Range(second, -127, 127),
                                "TEMPO" => !Range(n, 1, 1000) || !Range(second, 1, 1000),
                                "FILTER" => a.Skip(2).Any(x => !Range(I(x), 1, 16)),
                                "ROLL" => !Range(n, 0, 10000000) || !Range(second, 1, 10000000) ||
                                          !Range(third, 1, 10000000) || second <= n ||
                                          (second - n + third - 1) / third > 64,
                                _ => false };
        if (bad)
            Fail("bad argument");
        if (cmd is "TIMING" or "STATS" && s.Format == 2)
            Fail("format 2 not supported");
        switch (cmd) {
        case "DECODE":
            Console.WriteLine("HEADER " + s.Format + " " + s.Tracks.Count + " " + s.Division);
            for (int tr = 0; tr < s.Tracks.Count; tr++)
                foreach (Event e in s.Tracks[tr])
                    Console.WriteLine(Line(e, tr));
            break;
        case "ENCODE":
            Encode(s);
            break;
        case "TIMING":
            foreach (var x in s.Global()) {
                var p = Position(s, x.E.Tick);
                Console.WriteLine(x.E.Tick + " " + x.Track + " " + Type(x.E) + " " + p.Time + " " +
                                  p.Bar);
            }
            var end = Position(s, s.Length);
            Console.WriteLine("end " + s.Length + " " + end.Time + " " + end.Bar);
            break;
        case "NOTES":
            Notes(s);
            break;
        case "COPY":
            songs[a[2]] = s.Copy();
            Console.WriteLine("copied " + a[1] + " to " + a[2]);
            break;
        case "TRANSPOSE":
            int kept = 0;
            var dropped = new List<string>();
            for (int tr = 0; tr < s.Tracks.Count; tr++) {
                var track = new List<Event>();
                foreach (Event e in s.Tracks[tr]) {
                    if (e.Channel && e.Code is 8 or 9 or 10 && (a.Length == 3 || e.Ch == I(a[3]))) {
                        long pitch = e.Data[0] + n;
                        if (!Range(pitch, 0, 127)) {
                            dropped.Add("dropped " + e.Tick + " " + tr + " " + Type(e) + " " +
                                        e.Ch + " " + Pitch(e.Data[0]));
                            continue;
                        }
                        e.Data[0] = (byte)pitch;
                        kept++;
                    }
                    track.Add(e);
                }
                s.Tracks[tr] = track;
            }
            Console.WriteLine("transposed " + kept + " dropped " + dropped.Count);
            dropped.ForEach(Console.WriteLine);
            break;
        case "QUANTIZE":
            var pairs = Pair(s);
            var shifts = new Dictionary<Event, long>(ReferenceEqualityComparer.Instance);
            int targets = 0, moved = 0;
                void Shift(Event on, Event? off)
                {
                    long lo = on.Tick / n * n, g = on.Tick - lo <= lo + n - on.Tick ? lo : lo + n;
                    long delta = Floor(2 * (g - on.Tick) * second + 100, 200);
                    targets++;
                    if (delta != 0)
                        moved++;
                    shifts[on] = delta;
                    if (off != null)
                        shifts[off] = delta;
                }
                foreach (Note note in pairs.Notes)
                    Shift(note.On, note.Off);
                foreach (var x in pairs.Unmatched.Where(x => x.E.On))
                    Shift(x.E, null);
                for (int tr = 0; tr < s.Tracks.Count; tr++) {
                    Event eot = s.Tracks[tr].Last();
                    var track =
                        s.Tracks[tr]
                            .Where(e => !e.End)
                            .Select(e => e with { Tick = e.Tick + shifts.GetValueOrDefault(e) })
                            .OrderBy(e => e.Tick)
                            .ToList();
                    track.Add(eot with { Tick = Math.Max(
                                             eot.Tick, track.Count == 0 ? 0 : track.Last().Tick) });
                    s.Tracks[tr] = track;
                }
                Console.WriteLine("quantized " + targets + " moved " + moved);
                break;
        case "VELOCITY":
            int count = 0, clamped = 0;
            foreach (Event e in s.Tracks.SelectMany(t => t).Where(e => e.On)) {
                long value = (e.Data[1] * n + 50) / 100 + second;
                count++;
                if (!Range(value, 1, 127))
                    clamped++;
                e.Data[1] = (byte)Math.Clamp(value, 1, 127);
            }
            Console.WriteLine("velocity " + count + " clamped " + clamped);
            break;
        case "TEMPO":
            Song candidate = s.Copy();
            int scaled = 0;
            bool atZero = false;
            long Scale(long value) {
                long result = (2 * value * second + n) / (2 * n);
                if (!Range(result, 1, 16777215))
                    Fail("tempo out of range");
                return result;
            }
            foreach (var track in candidate.Tracks)
                for (int i = 0; i < track.Count; i++)
                    if (track[i].Status == 255 && track[i].Meta == 81) {
                        if (track[i].Tick == 0)
                            atZero = true;
                        scaled++;
                        track[i] = track[i] with { Data = Bytes(Scale(track[i].Number), 3) };
                    }
            Event? inserted = null;
            if (!atZero) {
                inserted = new(0, 255, 81, Bytes(Scale(500000), 3));
                candidate.Tracks[0].Insert(0, inserted);
            }
            songs[a[1]] = candidate;
            Console.WriteLine("scaled " + scaled);
            if (inserted != null)
                Console.WriteLine("inserted " + Line(inserted, 0));
            break;
        case "FILTER":
            var channels = a.Skip(2).Select(I).ToHashSet();
            int removed = 0;
            foreach (var track in s.Tracks)
                removed += track.RemoveAll(e => e.Channel && !channels.Contains(e.Ch));
            Console.WriteLine("removed " + removed);
            break;
        case "MERGE":
            if (s.Format != 1)
                Fail("not format 1");
            int old = s.Tracks.Count;
            long length = s.Length;
            var merged = s.Global().Where(x => !x.E.End).Select(x => x.E).ToList();
            merged.Add(new(length, 255, 47, Array.Empty<byte>()));
            s.Tracks = new() { merged };
            s.Format = 0;
            Console.WriteLine("merged " + old + " tracks events " + s.Count);
            break;
        case "SPLIT":
            if (s.Format != 0)
                Fail("not format 0");
            long lastTick = s.Length;
            var original = s.Tracks[0];
            var usedChannels =
                original.Where(e => e.Channel).Select(e => e.Ch).Distinct().Order().ToArray();
            var tracks =
                new List<List<Event>> { original.Where(e => !e.Channel && !e.End).ToList() };
            tracks.AddRange(
                usedChannels.Select(ch => original.Where(e => e.Channel && e.Ch == ch).ToList()));
            foreach (var track in tracks)
                track.Add(new(lastTick, 255, 47, Array.Empty<byte>()));
            s.Tracks = tracks;
            s.Format = 1;
            Console.WriteLine("split tracks " + tracks.Count + " events " + s.Count);
            break;
        case "STATS":
            Stats(s);
            break;
        case "ROLL":
            var notes = Pair(s).Notes;
            bool any = false;
            for (int pitch = 127; pitch >= 0; pitch--) {
                string row = "";
                for (long at = n; at < second; at += third)
                    row += notes.Any(note => note.On.Data[0] == pitch && at <= note.On.Tick &&
                                             note.On.Tick < at + third)
                               ? '#'
                           : notes.Any(note => note.On.Data[0] == pitch && note.On.Tick <= at &&
                                               at < note.Off.Tick)
                               ? '='
                               : '.';
                if (row.All(c => c == '.'))
                    continue;
                any = true;
                Console.WriteLine(Pitch(pitch).PadRight(4) + " " + row);
            }
            if (!any)
                Console.WriteLine("empty");
            break;
        }
    }
    static void Stats(Song s) {
        var pair = Pair(s);
        var notes = pair.Notes;
        Console.WriteLine(Summary(s));
        Console.WriteLine("notes " + notes.Count + " unmatched " + pair.Unmatched.Count);
        foreach (var group in notes.GroupBy(n => n.On.Ch).OrderBy(g => g.Key))
            Console.WriteLine("channel " + group.Key + " notes " + group.Count() + " range " +
                              Pitch(group.Min(n => n.On.Data[0])) + " " +
                              Pitch(group.Max(n => n.On.Data[0])));
        Console.WriteLine(notes.Count == 0 ? "range none"
                                           : "range " + Pitch(notes.Min(n => n.On.Data[0])) + " " +
                                                 Pitch(notes.Max(n => n.On.Data[0])));
        Console.WriteLine("length " + s.Length + " ticks " + Position(s, s.Length, false).Time +
                          " ms");
        var changes = new SortedDictionary<long, int>();
        foreach (Note n in notes.Where(n => n.Off.Tick > n.On.Tick)) {
            changes[n.On.Tick] = changes.GetValueOrDefault(n.On.Tick) + 1;
            changes[n.Off.Tick] = changes.GetValueOrDefault(n.Off.Tick) - 1;
        }
        int current = 0, maximum = 0;
        long at = 0;
        foreach (var item in changes) {
            current += item.Value;
            if (current > maximum) {
                maximum = current;
                at = item.Key;
            }
        }
        Console.WriteLine(maximum == 0 ? "polyphony 0" : "polyphony " + maximum + " at " + at);
    }
    static void Main() {
        int n = int.Parse(Console.ReadLine()!);
        for (int i = 0; i < n; i++) {
            string[] a = Console.ReadLine()!.Split(' ');
            try {
                if (a[0] is "HEX" or "TEXT") {
                    int k = int.Parse(a[2]);
                    string[] lines = new string[k];
                    for (int j = 0; j < k; j++)
                        lines[j] = Console.ReadLine()!;
                    Song s = a[0] == "HEX"
                                 ? ParseHex(lines
                                                .SelectMany(line => line.Split(' ').Select(
                                                                x => Convert.ToByte(x, 16)))
                                                .ToArray())
                                 : ParseText(lines);
                    songs[a[1]] = s;
                    Console.WriteLine("loaded " + a[1] + " " + Summary(s));
                } else
                    Execute(a);
            } catch (MidiError error) {
                Console.WriteLine("error: " + error.Message);
            }
        }
    }
}
