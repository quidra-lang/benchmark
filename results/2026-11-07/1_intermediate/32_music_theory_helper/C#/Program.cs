using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.RegularExpressions;

sealed class CommandError(string message) : Exception("ERROR " + message);

readonly record struct Pitch(int Letter, int Alteration)
{
    public static readonly int[] Naturals = [0, 2, 4, 5, 7, 9, 11];
    public int Natural => Naturals[Letter];
    public int Class => Music.Mod(Natural + Alteration, 12);
    public override string ToString() => "CDEFGAB"[Letter] + new[] { "bb", "b", "", "#", "x" }[Alteration + 2];
}

readonly record struct Note(Pitch Pitch, int Octave)
{
    public int Midi => 12 * (Octave + 1) + Pitch.Natural + Pitch.Alteration;
    public int Position => 7 * Octave + Pitch.Letter;
    public bool Valid => Octave is >= -1 and <= 9 && Midi is >= 0 and <= 127;
    public override string ToString() => $"{Pitch}{Octave}";
}

readonly record struct Interval(string Quality, int Number)
{
    public int Letters => Number - 1;
    public bool PerfectType => Letters % 7 is 0 or 3 or 4;
    public int Semitones => 12 * (Letters / 7) + Pitch.Naturals[Letters % 7] + Difference(Quality, PerfectType);
    public Interval Simple
    {
        get
        {
            int number = Number;
            while (number > 8) number -= 7;
            return new(Quality, number);
        }
    }
    public string Consonance => Simple.ToString() switch
    {
        "P1" or "P5" or "P8" => "perfect",
        "m3" or "M3" or "m6" or "M6" => "imperfect",
        _ => "dissonant"
    };
    public static int Difference(string quality, bool perfect) => quality switch
    {
        "dd" => perfect ? -2 : -3, "d" => perfect ? -1 : -2,
        "m" => -1, "A" => 1, "AA" => 2, _ => 0
    };
    public override string ToString() => Quality + Number;
}

sealed record Quality(string Name, Interval[] Intervals, string Suffix, string Numeral)
{
    public bool Lower => Numeral[0] == 'i';
    public string NumeralSuffix => Numeral[1..];
}
sealed record Mode(string Name, string Scale, int Offset);
readonly record struct Key(Pitch Tonic, Mode Mode)
{
    public int Fifths => new[] { 0, 2, 4, -1, 1, 3, 5 }[Tonic.Letter] + 7 * Tonic.Alteration + Mode.Offset;
    public override string ToString() => $"{Tonic} {Mode.Name}";
}
readonly record struct Numeral(int Degree, int Alteration, Quality Quality);
readonly record struct Chord(Pitch Root, Quality Quality)
{
    public override string ToString() => Root + Quality.Suffix;
}
readonly record struct Motion(Interval Interval, bool Down, int Semitones);
readonly record struct Degree(int Index, string Prefix)
{
    public override string ToString() => Prefix + (Index + 1);
}

static class Music
{
    private static readonly string[] Sharps = "C C# D D# E F F# G G# A A# B".Split(' ');
    private static readonly string[] Flats = "C Db D Eb E F Gb G Ab A Bb B".Split(' ');
    private static readonly string[] Romans = ["I", "II", "III", "IV", "V", "VI", "VII"];
    private static readonly string[] LowerRomans = ["i", "ii", "iii", "iv", "v", "vi", "vii"];
    public static readonly Dictionary<string, Interval[]> Scales = new(StringComparer.Ordinal)
    {
        ["major"] = Intervals("P1 M2 M3 P4 P5 M6 M7"),
        ["natural_minor"] = Intervals("P1 M2 m3 P4 P5 m6 m7"),
        ["harmonic_minor"] = Intervals("P1 M2 m3 P4 P5 m6 M7"),
        ["melodic_minor"] = Intervals("P1 M2 m3 P4 P5 M6 M7"),
        ["ionian"] = Intervals("P1 M2 M3 P4 P5 M6 M7"),
        ["dorian"] = Intervals("P1 M2 m3 P4 P5 M6 m7"),
        ["phrygian"] = Intervals("P1 m2 m3 P4 P5 m6 m7"),
        ["lydian"] = Intervals("P1 M2 M3 A4 P5 M6 M7"),
        ["mixolydian"] = Intervals("P1 M2 M3 P4 P5 M6 m7"),
        ["aeolian"] = Intervals("P1 M2 m3 P4 P5 m6 m7"),
        ["locrian"] = Intervals("P1 m2 m3 P4 d5 m6 m7"),
        ["major_pentatonic"] = Intervals("P1 M2 M3 P5 M6"),
        ["minor_pentatonic"] = Intervals("P1 m3 P4 P5 m7"),
        ["blues"] = Intervals("P1 m3 P4 A4 P5 m7"),
        ["whole_tone"] = Intervals("P1 M2 M3 A4 A5 A6")
    };
    public static readonly Quality[] Qualities =
    [
        new("maj", Intervals("P1 M3 P5"), "", "I"),
        new("min", Intervals("P1 m3 P5"), "m", "i"),
        new("dim", Intervals("P1 m3 d5"), "dim", "io"),
        new("aug", Intervals("P1 M3 A5"), "aug", "I+"),
        new("sus2", Intervals("P1 M2 P5"), "sus2", "Isus2"),
        new("sus4", Intervals("P1 P4 P5"), "sus4", "Isus4"),
        new("6", Intervals("P1 M3 P5 M6"), "6", "I6"),
        new("m6", Intervals("P1 m3 P5 M6"), "m6", "i6"),
        new("7", Intervals("P1 M3 P5 m7"), "7", "I7"),
        new("maj7", Intervals("P1 M3 P5 M7"), "maj7", "Imaj7"),
        new("m7", Intervals("P1 m3 P5 m7"), "m7", "i7"),
        new("mMaj7", Intervals("P1 m3 P5 M7"), "mMaj7", "imaj7"),
        new("m7b5", Intervals("P1 m3 d5 m7"), "m7b5", "ih7"),
        new("dim7", Intervals("P1 m3 d5 d7"), "dim7", "io7"),
        new("9", Intervals("P1 M3 P5 m7 M9"), "9", "I9"),
        new("add9", Intervals("P1 M3 P5 M9"), "add9", "Iadd9")
    ];
    public static readonly Mode[] Modes =
    [
        new("major", "major", 0), new("minor", "natural_minor", -3), new("ionian", "ionian", 0),
        new("dorian", "dorian", -2), new("phrygian", "phrygian", -4), new("lydian", "lydian", 1),
        new("mixolydian", "mixolydian", -1), new("aeolian", "aeolian", -3), new("locrian", "locrian", -5)
    ];

    public static int Mod(int value, int divisor) => (value % divisor + divisor) % divisor;
    public static int FloorDiv(int value, int divisor) => (value - Mod(value, divisor)) / divisor;
    public static string Join<T>(IEnumerable<T> values) => string.Join(' ', values);
    public static string Frequency(int cents) => $"{cents / 100}.{cents % 100:D2}";
    public static string Signed(int value, bool positiveZero = false) => value > 0 || value == 0 && positiveZero ? "+" + value : value.ToString(CultureInfo.InvariantCulture);
    private static Interval[] Intervals(string text) => text.Split(' ').Select(ParseInterval).ToArray();
    private static int Alteration(string text) => text switch { "bb" => -2, "b" => -1, "#" => 1, "x" => 2, _ => 0 };
    public static Pitch ParsePitch(string text)
    {
        Match match = Regex.Match(text, @"\A([A-G])(bb|b|#|x)?\z");
        if (!match.Success) throw new CommandError("BAD PITCH " + text);
        return new("CDEFGAB".IndexOf(match.Groups[1].Value[0]), Alteration(match.Groups[2].Value));
    }
    public static Note ParseNote(string text)
    {
        Match match = Regex.Match(text, @"\A([A-G])(bb|b|#|x)?(-1|[0-9])\z");
        if (!match.Success) throw new CommandError("BAD NOTE " + text);
        Note note = new(new("CDEFGAB".IndexOf(match.Groups[1].Value[0]), Alteration(match.Groups[2].Value)),
                        int.Parse(match.Groups[3].Value, CultureInfo.InvariantCulture));
        if (!note.Valid) throw new CommandError("BAD NOTE " + text);
        return note;
    }
    public static int ParseNumber(string text)
    {
        if (!Regex.IsMatch(text, @"\A(?:0|[1-9][0-9]*)\z") || !int.TryParse(text, out int number) || number > 127)
            throw new CommandError("BAD NUMBER " + text);
        return number;
    }
    public static int ParseFrequency(string text, bool tuning)
    {
        Match match = Regex.Match(text, @"\A([0-9]{1,5})(?:\.([0-9]{1,2}))?\z");
        if (!match.Success) throw new CommandError("BAD FREQUENCY " + text);
        int cents = int.Parse(match.Groups[1].Value, CultureInfo.InvariantCulture) * 100;
        string tail = match.Groups[2].Value;
        if (tail.Length > 0) cents += int.Parse(tail.PadRight(2, '0'), CultureInfo.InvariantCulture);
        if (tuning ? cents is < 40000 or > 48000 : cents == 0) throw new CommandError("BAD FREQUENCY " + text);
        return cents;
    }
    public static Interval ParseInterval(string text)
    {
        Match match = Regex.Match(text, @"\A(AA|dd|P|M|m|A|d)([1-9][0-9]?)\z");
        if (!match.Success) throw new CommandError("BAD INTERVAL " + text);
        Interval interval = new(match.Groups[1].Value, int.Parse(match.Groups[2].Value, CultureInfo.InvariantCulture));
        if ((interval.PerfectType ? interval.Quality is "M" or "m" : interval.Quality == "P") ||
            interval.Number == 1 && (interval.Quality is "d" or "dd")) throw new CommandError("BAD INTERVAL " + text);
        return interval;
    }
    public static Quality ParseQuality(string text) => Qualities.FirstOrDefault(q => q.Name == text) ?? throw new CommandError("BAD QUALITY " + text);
    public static Mode ParseMode(string text) => Modes.FirstOrDefault(m => m.Name == text) ?? throw new CommandError("BAD MODE " + text);
    public static Key ParseKey(string tonic, string mode)
    {
        Pitch pitch = ParsePitch(tonic);
        Mode parsedMode = ParseMode(mode);
        Key key = new(pitch, parsedMode);
        if (key.Fifths is < -7 or > 7) throw new CommandError("THEORETICAL KEY");
        return key;
    }
    public static Interval[] ParseScale(string text) => Scales.TryGetValue(text, out Interval[]? scale) ? scale : throw new CommandError("BAD SCALE " + text);
    public static int ParseInversion(string text, Quality quality)
    {
        if (text.Length != 1 || text[0] < '0' || text[0] >= '0' + quality.Intervals.Length) throw new CommandError("BAD INVERSION " + text);
        return text[0] - '0';
    }
    public static Numeral ParseNumeral(string text)
    {
        int start = text[0] is 'b' or '#' ? 1 : 0;
        int alteration = start == 0 ? 0 : text[0] == 'b' ? -1 : 1;
        int end = start;
        while (end < text.Length && "IViv".Contains(text[end])) end++;
        string roman = text[start..end], suffix = text[end..];
        int degree = Array.IndexOf(Romans, roman);
        bool lower = false;
        if (degree < 0) { degree = Array.IndexOf(LowerRomans, roman); lower = true; }
        Quality? quality = Qualities.FirstOrDefault(q => q.Lower == lower && q.NumeralSuffix == suffix);
        if (degree < 0 || quality is null) throw new CommandError("BAD NUMERAL " + text);
        return new(degree, alteration, quality);
    }
    public static Chord ParseSymbol(string text)
    {
        Match match = Regex.Match(text, @"\A([A-G])(bb|b|#|x)?(.*)\z");
        if (!match.Success) throw new CommandError("BAD SYMBOL " + text);
        Quality? quality = Qualities.FirstOrDefault(q => q.Suffix == match.Groups[3].Value);
        if (quality is null) throw new CommandError("BAD SYMBOL " + text);
        Pitch root = new("CDEFGAB".IndexOf(match.Groups[1].Value[0]), Alteration(match.Groups[2].Value));
        return new(root, quality);
    }
    public static Pitch Raise(Pitch root, Interval interval)
    {
        int letter = Mod(root.Letter + interval.Letters, 7);
        int alteration = root.Natural + root.Alteration + interval.Semitones - Pitch.Naturals[letter] - 12 * FloorDiv(root.Letter + interval.Letters, 7);
        if (alteration is < -2 or > 2) throw new CommandError("CANNOT SPELL");
        return new(letter, alteration);
    }
    public static Pitch[] Build(Pitch root, Interval[] intervals) => intervals.Select(interval => Raise(root, interval)).ToArray();
    public static Pitch[] Scale(Key key) => Build(key.Tonic, Scales[key.Mode.Scale]);
    public static Note FromMidi(Pitch pitch, int midi) => new(pitch, (midi - pitch.Natural - pitch.Alteration) / 12 - 1);
    public static Note StandardNote(int midi, bool flat = false) => new(ParsePitch((flat ? Flats : Sharps)[Mod(midi, 12)]), midi / 12 - 1);
    public static Pitch FifthsPitch(int fifths)
    {
        int index = Mod(fifths + 1, 7);
        return new("CDEFGAB".IndexOf("FCGDAEB"[index]), FloorDiv(fifths + 1, 7));
    }
    public static Key KeyAt(int fifths, Mode mode) => new(FifthsPitch(fifths - mode.Offset), mode);
    public static Degree Label(Key key, Pitch pitch)
    {
        int index = Mod(pitch.Letter - key.Tonic.Letter, 7);
        int alteration = pitch.Alteration - Scale(key)[index].Alteration;
        return new(index, new string(alteration < 0 ? 'b' : '#', Math.Abs(alteration)));
    }
    public static string Roman(int degree, Quality quality) => (quality.Lower ? LowerRomans : Romans)[degree] + quality.NumeralSuffix;
    public static Motion Between(Note first, Note second)
    {
        int letters = second.Position - first.Position, semitones = second.Midi - first.Midi;
        bool down = letters < 0 || letters == 0 && semitones < 0;
        if (down) { letters = -letters; semitones = -semitones; }
        int difference = semitones - (12 * (letters / 7) + Pitch.Naturals[letters % 7]);
        bool perfect = letters % 7 is 0 or 3 or 4;
        string? quality = perfect ? difference switch { -2 => "dd", -1 => "d", 0 => "P", 1 => "A", 2 => "AA", _ => null }
                                  : difference switch { -3 => "dd", -2 => "d", -1 => "m", 0 => "M", 1 => "A", 2 => "AA", _ => null };
        if (quality is null) throw new CommandError("UNNAMEABLE INTERVAL");
        return new(new(quality, letters + 1), down, semitones);
    }
    public static int PitchMask(IEnumerable<Pitch> pitches)
    {
        int mask = 0;
        foreach (Pitch pitch in pitches) mask |= 1 << pitch.Class;
        return mask;
    }
    public static int ChordMask(Note root, Quality quality)
    {
        int mask = 0;
        foreach (Interval interval in quality.Intervals) mask |= 1 << Mod(root.Midi + interval.Semitones, 12);
        return mask;
    }
    public static string Cadence(Numeral[] numerals)
    {
        if (numerals.Length < 2) return "none";
        Numeral a = numerals[^2], b = numerals[^1];
        if (a.Alteration == 0 && b.Alteration == 0)
        {
            if (a.Degree == 4 && b.Degree == 0) return "authentic";
            if (a.Degree == 3 && b.Degree == 0) return "plagal";
            if (a.Degree == 4 && b.Degree == 5) return "deceptive";
        }
        return b.Alteration == 0 && b.Degree == 4 ? "half" : "none";
    }
}

sealed class Calculator
{
    private int tuning = 44000;
    private static readonly Dictionary<string, (int Min, int Max)> Arity = new(StringComparer.Ordinal)
    {
        ["MIDI"] = (1, 1), ["NOTE"] = (1, 1), ["FREQ"] = (1, 1), ["TUNING"] = (1, 1), ["PITCH"] = (1, 1),
        ["INTERVAL"] = (2, 2), ["INVERT"] = (1, 1), ["TRANSPOSE"] = (3, 3), ["SCALE"] = (2, 2),
        ["CHORD"] = (2, 3), ["VOICE"] = (2, 3), ["IDENTIFY"] = (2, 15), ["MELODY"] = (2, 15),
        ["ENHARMONIC"] = (1, 1), ["KEYSIG"] = (2, 2), ["RELATIVE"] = (2, 2), ["CIRCLE"] = (1, 1),
        ["DIATONIC"] = (2, 2), ["PROGRESSION"] = (3, 15), ["ANALYZE"] = (3, 15), ["FINDKEY"] = (1, 15),
        ["DEGREE"] = (3, 3), ["SPELL"] = (3, 3), ["KEYDIST"] = (4, 4)
    };
    public string Execute(string line)
    {
        string[] w = line.Split(' ');
        string command = w[0];
        if (!Arity.TryGetValue(command, out var arity)) throw new CommandError("UNKNOWN COMMAND " + command);
        if (w.Length - 1 < arity.Min || w.Length - 1 > arity.Max) throw new CommandError("ARGUMENT COUNT");
        switch (command)
        {
            case "MIDI": return $"MIDI {w[1]} {Music.ParseNote(w[1]).Midi}";
            case "NOTE":
            {
                int number = Music.ParseNumber(w[1]);
                return $"NOTE {number} {Music.StandardNote(number)} {Music.StandardNote(number, true)}";
            }
            case "FREQ":
            {
                Note note = Music.ParseNote(w[1]);
                double value = (tuning / 100.0) * Math.Pow(2, (note.Midi - 69) / 12.0);
                return $"FREQ {w[1]} {Music.Frequency((int)Math.Floor(value * 100 + 0.5))}";
            }
            case "TUNING":
            {
                int value = Music.ParseFrequency(w[1], true);
                tuning = value;
                return "TUNING " + Music.Frequency(value);
            }
            case "PITCH":
            {
                int value = Music.ParseFrequency(w[1], false);
                double x = 69 + 12 * Math.Log2((double)value / tuning);
                int number = (int)Math.Floor(x + 0.5);
                if (number is < 0 or > 127) throw new CommandError("OUT OF RANGE");
                int cents = (int)Math.Floor(100 * (x - number) + 0.5);
                return $"PITCH {Music.Frequency(value)} {Music.StandardNote(number)} {Music.Signed(cents, true)}";
            }
            case "INTERVAL":
            {
                Note a = Music.ParseNote(w[1]);
                Note b = Music.ParseNote(w[2]);
                Motion motion = Music.Between(a, b);
                return $"INTERVAL {w[1]} {w[2]} {motion.Interval} {(motion.Down ? "down" : "up")} semitones={motion.Semitones} simple={motion.Interval.Simple} class={motion.Interval.Consonance}";
            }
            case "INVERT":
            {
                Interval original = Music.ParseInterval(w[1]), simple = original.Simple;
                string quality = simple.Quality switch { "P" => "P", "M" => "m", "m" => "M", "A" => "d", "d" => "A", "AA" => "dd", _ => "AA" };
                Interval inverted = new(quality, 9 - simple.Number);
                if (inverted.Number == 1 && (quality is "d" or "dd")) throw new CommandError("CANNOT INVERT");
                return $"INVERT {w[1]} {simple} {inverted}";
            }
            case "TRANSPOSE":
            {
                Note note = Music.ParseNote(w[1]);
                Interval interval = Music.ParseInterval(w[2]);
                if (w[3] is not ("UP" or "DOWN")) throw new CommandError("BAD DIRECTION " + w[3]);
                int sign = w[3] == "UP" ? 1 : -1;
                int position = note.Position + sign * interval.Letters, midi = note.Midi + sign * interval.Semitones;
                int letter = Music.Mod(position, 7), octave = Music.FloorDiv(position, 7);
                int alteration = midi - (12 * (octave + 1) + Pitch.Naturals[letter]);
                if (alteration is < -2 or > 2) throw new CommandError("CANNOT SPELL");
                Note result = new(new(letter, alteration), octave);
                if (!result.Valid) throw new CommandError("OUT OF RANGE");
                return $"TRANSPOSE {w[1]} {w[2]} {w[3]} {result}";
            }
            case "SCALE":
            {
                Pitch root = Music.ParsePitch(w[1]);
                Interval[] intervals = Music.ParseScale(w[2]);
                Pitch[] notes = Music.Build(root, intervals);
                int[] steps = intervals.Select((interval, i) => (i + 1 == intervals.Length ? 12 : intervals[i + 1].Semitones) - interval.Semitones).ToArray();
                return $"SCALE {w[1]} {w[2]} {Music.Join(notes)} steps={string.Join(',', steps)}";
            }
            case "CHORD": case "VOICE":
            {
                Note? input = null;
                Pitch root;
                if (command == "VOICE") { input = Music.ParseNote(w[1]); root = input.Value.Pitch; }
                else root = Music.ParsePitch(w[1]);
                Quality quality = Music.ParseQuality(w[2]);
                int inversion = w.Length == 4 ? Music.ParseInversion(w[3], quality) : 0;
                Pitch[] tones = Music.Build(root, quality.Intervals);
                Pitch[] reordered = tones.Skip(inversion).Concat(tones.Take(inversion)).ToArray();
                string symbol = new Chord(root, quality).ToString() + (inversion == 0 ? "" : "/" + reordered[0]);
                if (command == "CHORD") return $"CHORD {symbol} {Music.Join(reordered)}";
                var notes = new List<Note>();
                int previous = input!.Value.Midi;
                for (int i = 0; i < reordered.Length; i++)
                {
                    int midi = previous;
                    if (i != 0 || inversion != 0)
                    {
                        midi += Music.Mod(reordered[i].Class - previous, 12);
                        if (midi == previous) midi += 12;
                    }
                    Note made = Music.FromMidi(reordered[i], midi);
                    if (!made.Valid) throw new CommandError("OUT OF RANGE");
                    notes.Add(made);
                    previous = midi;
                }
                return $"VOICE {symbol} {Music.Join(notes)} midi={string.Join(',', notes.Select(n => n.Midi))}";
            }
            case "IDENTIFY":
            {
                Note[] notes = w.Skip(1).Select(Music.ParseNote).ToArray();
                var seen = new HashSet<int>();
                Note[] candidates = notes.OrderBy(note => note.Midi).Where(note => seen.Add(note.Pitch.Class)).ToArray();
                int mask = Music.PitchMask(notes.Select(note => note.Pitch));
                Note bass = candidates[0];
                foreach (Note root in candidates)
                    foreach (Quality quality in Music.Qualities)
                    {
                        if (Music.ChordMask(root, quality) != mask) continue;
                        int inversion = Array.FindIndex(quality.Intervals, interval => Music.Mod(root.Midi + interval.Semitones, 12) == bass.Pitch.Class);
                        string symbol = new Chord(root.Pitch, quality).ToString() + (inversion == 0 ? "" : "/" + bass.Pitch);
                        return $"IDENTIFY {symbol} root={root.Pitch} quality={quality.Name} inversion={inversion}";
                    }
                return "IDENTIFY UNKNOWN";
            }
            case "MELODY":
            {
                Note[] notes = w.Skip(1).Select(Music.ParseNote).ToArray();
                Note low = notes[0], high = notes[0];
                foreach (Note note in notes)
                {
                    if (note.Midi < low.Midi) low = note;
                    if (note.Midi > high.Midi) high = note;
                }
                Interval range = Music.Between(low, high).Interval;
                var steps = new List<string>();
                int leaps = 0;
                for (int i = 1; i < notes.Length; i++)
                {
                    Motion motion = Music.Between(notes[i - 1], notes[i]);
                    steps.Add((motion.Down ? "-" : "+") + motion.Interval);
                    if (Math.Abs(notes[i].Midi - notes[i - 1].Midi) >= 3) leaps++;
                }
                return $"MELODY n={notes.Length} low={low} high={high} range={range} leaps={leaps} steps={string.Join(',', steps)}";
            }
            case "ENHARMONIC":
            {
                Note input = Music.ParseNote(w[1]);
                var notes = new List<Note>();
                for (int letter = 0; letter < 7; letter++)
                    for (int alteration = -2; alteration <= 2; alteration++)
                    {
                        Pitch pitch = new(letter, alteration);
                        if (pitch.Class != input.Pitch.Class) continue;
                        Note note = Music.FromMidi(pitch, input.Midi);
                        if (note.Valid) notes.Add(note);
                    }
                return $"ENHARMONIC {w[1]} {Music.Join(notes.OrderBy(note => note.Position))}";
            }
            case "KEYSIG": case "RELATIVE": case "DIATONIC": case "PROGRESSION": case "ANALYZE": case "DEGREE":
            {
                Key key = Music.ParseKey(w[1], w[2]);
                if (command == "KEYSIG")
                {
                    int fifths = key.Fifths;
                    if (fifths == 0) return $"KEYSIG {key} none";
                    string[] names = (fifths > 0 ? "F# C# G# D# A# E# B#" : "Bb Eb Ab Db Gb Cb Fb").Split(' ');
                    return $"KEYSIG {key} {(fifths > 0 ? "sharps" : "flats")}={Math.Abs(fifths)} {Music.Join(names.Take(Math.Abs(fifths)))}";
                }
                if (command == "RELATIVE") return $"RELATIVE {key} major={Music.KeyAt(key.Fifths, Music.Modes[0]).Tonic} minor={Music.KeyAt(key.Fifths, Music.Modes[1]).Tonic}";
                if (command == "DEGREE")
                {
                    Pitch pitch = Music.ParsePitch(w[3]);
                    return $"DEGREE {key} {w[3]} {Music.Label(key, pitch)}";
                }
                if (command == "ANALYZE")
                {
                    Chord[] chords = w.Skip(3).Select(Music.ParseSymbol).ToArray();
                    string[] results = chords.Select(chord =>
                    {
                        Degree degree = Music.Label(key, chord.Root);
                        return degree.Prefix + Music.Roman(degree.Index, chord.Quality);
                    }).ToArray();
                    return $"ANALYZE {key} {Music.Join(results)}";
                }
                if (command == "PROGRESSION")
                {
                    Numeral[] numerals = w.Skip(3).Select(Music.ParseNumeral).ToArray();
                    Pitch[] keyScale = Music.Scale(key);
                    var lines = new List<string> { $"PROGRESSION {key} {numerals.Length}" };
                    for (int i = 0; i < numerals.Length; i++)
                    {
                        Numeral numeral = numerals[i];
                        Pitch degree = keyScale[numeral.Degree];
                        Pitch root = new(degree.Letter, degree.Alteration + numeral.Alteration);
                        Pitch[] tones = Music.Build(root, numeral.Quality.Intervals);
                        lines.Add($"{w[i + 3]} {new Chord(root, numeral.Quality)} {Music.Join(tones)}");
                    }
                    lines.Add("CADENCE " + Music.Cadence(numerals));
                    return string.Join('\n', lines);
                }
                Pitch[] scale = Music.Scale(key);
                var triads = new List<string>();
                var sevenths = new List<string>();
                for (int i = 0; i < 7; i++)
                {
                    int third = Music.Mod(scale[(i + 2) % 7].Class - scale[i].Class, 12);
                    int fifth = Music.Mod(scale[(i + 4) % 7].Class - scale[i].Class, 12);
                    int seventh = Music.Mod(scale[(i + 6) % 7].Class - scale[i].Class, 12);
                    Quality triad = Music.ParseQuality(third == 4 ? "maj" : fifth == 7 ? "min" : "dim");
                    Quality tetrad = Music.ParseQuality(third == 4 ? seventh == 11 ? "maj7" : "7" : fifth == 7 ? "m7" : "m7b5");
                    triads.Add($"{Music.Roman(i, triad)}={new Chord(scale[i], triad)}");
                    sevenths.Add($"{Music.Roman(i, tetrad)}={new Chord(scale[i], tetrad)}");
                }
                return $"DIATONIC {key}\nTRIADS {Music.Join(triads)}\nSEVENTHS {Music.Join(sevenths)}";
            }
            case "CIRCLE":
            {
                Mode mode = Music.ParseMode(w[1]);
                return $"CIRCLE {w[1]} {Music.Join(Enumerable.Range(-7, 15).Select(p => Music.KeyAt(p, mode).Tonic))}";
            }
            case "FINDKEY":
            {
                Pitch[] pitches = w.Skip(1).Select(Music.ParsePitch).ToArray();
                var keys = new List<Key>();
                for (int fifths = -7; fifths <= 7; fifths++)
                    for (int m = 0; m < 2; m++)
                    {
                        Key key = Music.KeyAt(fifths, Music.Modes[m]);
                        Pitch[] scale = Music.Scale(key);
                        if (pitches.All(scale.Contains)) keys.Add(key);
                    }
                return "FINDKEY " + keys.Count + (keys.Count == 0 ? "" : " " + string.Join(", ", keys));
            }
            case "SPELL":
            {
                int midi = Music.ParseNumber(w[1]);
                Key key = Music.ParseKey(w[2], w[3]);
                Pitch pitch = Music.StandardNote(midi, key.Fifths < 0).Pitch;
                foreach (Pitch candidate in Music.Scale(key))
                    if (candidate.Class == midi % 12) { pitch = candidate; break; }
                Note note = Music.FromMidi(pitch, midi);
                if (!note.Valid) throw new CommandError("OUT OF RANGE");
                return $"SPELL {midi} {key} {note} {Music.Label(key, pitch)}";
            }
            case "KEYDIST":
            {
                Key a = Music.ParseKey(w[1], w[2]);
                Key b = Music.ParseKey(w[3], w[4]);
                int difference = Music.Mod(b.Fifths - a.Fifths, 12);
                if (difference > 6) difference -= 12;
                int first = Music.PitchMask(Music.Scale(a)), second = Music.PitchMask(Music.Scale(b));
                int common = Enumerable.Range(0, 12).Count(i => ((first & second) & (1 << i)) != 0);
                bool sameTonic = a.Tonic.Class == b.Tonic.Class;
                string relation = first == second ? sameTonic ? "same" : "relative" : sameTonic ? "parallel" : Math.Abs(difference) == 1 ? "close" : "distant";
                return $"KEYDIST {a} {b} fifths={Music.Signed(difference)} common={common} relation={relation}";
            }
            default: throw new InvalidOperationException();
        }
    }
}

static class Program
{
    public static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        var calculator = new Calculator();
        int count = int.Parse(Console.ReadLine()!, CultureInfo.InvariantCulture);
        for (int i = 0; i < count; i++)
        {
            string line = Console.ReadLine()!;
            try { Console.WriteLine(calculator.Execute(line)); }
            catch (CommandError error) { Console.WriteLine(error.Message); }
        }
    }
}
