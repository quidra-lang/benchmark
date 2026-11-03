import java.io.*;
import java.util.*;

public class Main {
    static final String LETTERS = "CDEFGAB";
    static final int[] NATURALS = {0, 2, 4, 5, 7, 9, 11};
    static final int[] FIFTHS = {0, 2, 4, -1, 1, 3, 5};
    static final String[] ACCIDENTALS = {"bb", "b", "", "#", "x"};
    static final String[] SHARPS = "C C# D D# E F F# G G# A A# B".split(" ");
    static final String[] FLATS = "C Db D Eb E F Gb G Ab A Bb B".split(" ");
    static final String[] ROMANS = {"I", "II", "III", "IV", "V", "VI", "VII"};

    static class CommandError extends RuntimeException {
        CommandError(String message) { super("ERROR " + message); }
    }
    static CommandError bad(String kind, String word) { return new CommandError("BAD " + kind + " " + word); }
    static String format(String pattern, Object... values) { return String.format(Locale.ROOT, pattern, values); }
    static String join(Collection<?> values, String separator) {
        return String.join(separator, values.stream().map(Object::toString).toList());
    }
    static int canonical(String text, int low, int high) {
        if (!text.matches("0|[1-9][0-9]*")) return -1;
        try {
            int value = Integer.parseInt(text);
            return value >= low && value <= high ? value : -1;
        } catch (NumberFormatException e) {
            return -1;
        }
    }
    static int number(String text) {
        int result = canonical(text, 0, 127);
        if (result < 0) throw bad("NUMBER", text);
        return result;
    }
    static int frequency(String text, boolean tuning) {
        if (!text.matches("[0-9]{1,5}(\\.[0-9]{1,2})?")) throw bad("FREQUENCY", text);
        String[] parts = text.split("\\.");
        int cents = Integer.parseInt(parts[0]) * 100;
        if (parts.length == 2) cents += Integer.parseInt(parts[1]) * (parts[1].length() == 1 ? 10 : 1);
        if (cents == 0 || tuning && (cents < 40000 || cents > 48000)) throw bad("FREQUENCY", text);
        return cents;
    }
    static String frequencyText(int cents) { return format("%d.%02d", cents / 100, cents % 100); }

    record Pitch(int letter, int alteration) {
        int pitchClass() { return Math.floorMod(NATURALS[letter] + alteration, 12); }
        Pitch raise(Tone tone) {
            int target = letter + tone.letters;
            int change = NATURALS[letter] + alteration + tone.semitones - NATURALS[target % 7] - 12 * (target / 7);
            if (change < -2 || change > 2) throw new CommandError("CANNOT SPELL");
            return new Pitch(target % 7, change);
        }
        @Override public String toString() { return LETTERS.charAt(letter) + ACCIDENTALS[alteration + 2]; }
    }
    record PitchPrefix(Pitch pitch, int end) {}
    static PitchPrefix pitchPrefix(String text) {
        int letter = LETTERS.indexOf(text.charAt(0));
        if (letter < 0) return null;
        int end = 1, alteration = 0;
        if (end < text.length()) {
            switch (text.charAt(end)) {
                case 'b' -> {
                    alteration = -1;
                    end++;
                    if (end < text.length() && text.charAt(end) == 'b') { alteration = -2; end++; }
                }
                case '#' -> { alteration = 1; end++; }
                case 'x' -> { alteration = 2; end++; }
            }
        }
        return new PitchPrefix(new Pitch(letter, alteration), end);
    }
    static Pitch pitch(String text) {
        PitchPrefix prefix = pitchPrefix(text);
        if (prefix == null || prefix.end != text.length()) throw bad("PITCH", text);
        return prefix.pitch;
    }
    static Pitch fifthPitch(int fifths) {
        return new Pitch(LETTERS.indexOf("FCGDAEB".charAt(Math.floorMod(fifths + 1, 7))), Math.floorDiv(fifths + 1, 7));
    }
    record Note(Pitch pitch, int octave) {
        int midi() { return 12 * (octave + 1) + NATURALS[pitch.letter] + pitch.alteration; }
        int position() { return 7 * octave + pitch.letter; }
        boolean valid() { return octave >= -1 && octave <= 9 && midi() >= 0 && midi() <= 127; }
        @Override public String toString() { return pitch.toString() + octave; }
    }
    static Note note(String text) {
        PitchPrefix prefix = pitchPrefix(text);
        if (prefix == null) throw bad("NOTE", text);
        String rest = text.substring(prefix.end);
        int octave;
        if (rest.equals("-1")) octave = -1;
        else if (rest.length() == 1 && rest.charAt(0) >= '0' && rest.charAt(0) <= '9') octave = rest.charAt(0) - '0';
        else throw bad("NOTE", text);
        Note result = new Note(prefix.pitch, octave);
        if (!result.valid()) throw bad("NOTE", text);
        return result;
    }
    static Note fromPitch(Pitch pitch, int midi) {
        return new Note(pitch, (midi - NATURALS[pitch.letter] - pitch.alteration) / 12 - 1);
    }
    static Note spelling(int midi, boolean flat) {
        return new Note(pitch((flat ? FLATS : SHARPS)[midi % 12]), midi / 12 - 1);
    }
    static List<Note> notes(List<String> words) {
        List<Note> result = new ArrayList<>();
        for (String word : words) result.add(note(word));
        return result;
    }

    enum Quality {
        PERFECT("P"), MAJOR("M"), MINOR("m"), AUGMENTED("A"), DIMINISHED("d"), DOUBLE_AUGMENTED("AA"), DOUBLE_DIMINISHED("dd");
        final String text;
        Quality(String text) { this.text = text; }
        Integer delta(boolean perfect) {
            return switch (this) {
                case PERFECT -> perfect ? 0 : null;
                case MAJOR -> perfect ? null : 0;
                case MINOR -> perfect ? null : -1;
                case AUGMENTED -> 1;
                case DIMINISHED -> perfect ? -1 : -2;
                case DOUBLE_AUGMENTED -> 2;
                case DOUBLE_DIMINISHED -> perfect ? -2 : -3;
            };
        }
        Quality inverse() {
            return switch (this) {
                case PERFECT -> PERFECT;
                case MAJOR -> MINOR;
                case MINOR -> MAJOR;
                case AUGMENTED -> DIMINISHED;
                case DIMINISHED -> AUGMENTED;
                case DOUBLE_AUGMENTED -> DOUBLE_DIMINISHED;
                case DOUBLE_DIMINISHED -> DOUBLE_AUGMENTED;
            };
        }
    }
    static boolean perfectType(int number) {
        int remainder = (number - 1) % 7;
        return remainder == 0 || remainder == 3 || remainder == 4;
    }
    record Tone(int letters, int semitones) {}
    record Interval(Quality quality, int number) {
        boolean forbidden() { return number == 1 && (quality == Quality.DIMINISHED || quality == Quality.DOUBLE_DIMINISHED); }
        Tone tone() {
            int distance = number - 1;
            return new Tone(distance, 12 * (distance / 7) + NATURALS[distance % 7] + quality.delta(perfectType(number)));
        }
        Interval simple() {
            int n = number;
            while (n > 8) n -= 7;
            return new Interval(quality, n);
        }
        String consonance() {
            Interval simple = simple();
            if (quality == Quality.PERFECT && (simple.number == 1 || simple.number == 5 || simple.number == 8)) return "perfect";
            if ((quality == Quality.MAJOR || quality == Quality.MINOR) && (simple.number == 3 || simple.number == 6)) return "imperfect";
            return "dissonant";
        }
        @Override public String toString() { return quality.text + number; }
    }
    static Interval interval(String text) {
        for (Quality quality : Quality.values()) {
            if (!text.startsWith(quality.text)) continue;
            int n = canonical(text.substring(quality.text.length()), 1, 99);
            if (n < 0 || quality.delta(perfectType(n)) == null) continue;
            Interval result = new Interval(quality, n);
            if (!result.forbidden()) return result;
        }
        throw bad("INTERVAL", text);
    }
    record Motion(Interval interval, boolean down, int semitones) {}
    static Motion between(Note first, Note second) {
        int distance = second.position() - first.position(), semitones = second.midi() - first.midi();
        boolean down = distance < 0 || distance == 0 && semitones < 0;
        if (down) { distance = -distance; semitones = -semitones; }
        int difference = semitones - 12 * (distance / 7) - NATURALS[distance % 7];
        for (Quality quality : Quality.values()) {
            Integer delta = quality.delta(perfectType(distance + 1));
            if (delta != null && delta == difference) return new Motion(new Interval(quality, distance + 1), down, semitones);
        }
        throw new CommandError("UNNAMEABLE INTERVAL");
    }

    record Scale(String name, List<Tone> tones) {}
    record Chord(String name, String suffix, String numeralSuffix, boolean lower, List<Tone> tones) {}
    record Mode(String name, int scale, int offset) {}
    static List<Tone> tones(String text) { return Arrays.stream(text.split(" ")).map(Main::interval).map(Interval::tone).toList(); }
    static final List<Scale> SCALES = List.of(
        new Scale("major", tones("P1 M2 M3 P4 P5 M6 M7")),
        new Scale("natural_minor", tones("P1 M2 m3 P4 P5 m6 m7")),
        new Scale("harmonic_minor", tones("P1 M2 m3 P4 P5 m6 M7")),
        new Scale("melodic_minor", tones("P1 M2 m3 P4 P5 M6 M7")),
        new Scale("ionian", tones("P1 M2 M3 P4 P5 M6 M7")),
        new Scale("dorian", tones("P1 M2 m3 P4 P5 M6 m7")),
        new Scale("phrygian", tones("P1 m2 m3 P4 P5 m6 m7")),
        new Scale("lydian", tones("P1 M2 M3 A4 P5 M6 M7")),
        new Scale("mixolydian", tones("P1 M2 M3 P4 P5 M6 m7")),
        new Scale("aeolian", tones("P1 M2 m3 P4 P5 m6 m7")),
        new Scale("locrian", tones("P1 m2 m3 P4 d5 m6 m7")),
        new Scale("major_pentatonic", tones("P1 M2 M3 P5 M6")),
        new Scale("minor_pentatonic", tones("P1 m3 P4 P5 m7")),
        new Scale("blues", tones("P1 m3 P4 A4 P5 m7")),
        new Scale("whole_tone", tones("P1 M2 M3 A4 A5 A6"))
    );
    static final List<Chord> CHORDS = List.of(
        new Chord("maj", "", "", false, tones("P1 M3 P5")),
        new Chord("min", "m", "", true, tones("P1 m3 P5")),
        new Chord("dim", "dim", "o", true, tones("P1 m3 d5")),
        new Chord("aug", "aug", "+", false, tones("P1 M3 A5")),
        new Chord("sus2", "sus2", "sus2", false, tones("P1 M2 P5")),
        new Chord("sus4", "sus4", "sus4", false, tones("P1 P4 P5")),
        new Chord("6", "6", "6", false, tones("P1 M3 P5 M6")),
        new Chord("m6", "m6", "6", true, tones("P1 m3 P5 M6")),
        new Chord("7", "7", "7", false, tones("P1 M3 P5 m7")),
        new Chord("maj7", "maj7", "maj7", false, tones("P1 M3 P5 M7")),
        new Chord("m7", "m7", "7", true, tones("P1 m3 P5 m7")),
        new Chord("mMaj7", "mMaj7", "maj7", true, tones("P1 m3 P5 M7")),
        new Chord("m7b5", "m7b5", "h7", true, tones("P1 m3 d5 m7")),
        new Chord("dim7", "dim7", "o7", true, tones("P1 m3 d5 d7")),
        new Chord("9", "9", "9", false, tones("P1 M3 P5 m7 M9")),
        new Chord("add9", "add9", "add9", false, tones("P1 M3 P5 M9"))
    );
    static final List<Mode> MODES = List.of(
        new Mode("major", 0, 0), new Mode("minor", 1, -3), new Mode("ionian", 4, 0),
        new Mode("dorian", 5, -2), new Mode("phrygian", 6, -4), new Mode("lydian", 7, 1),
        new Mode("mixolydian", 8, -1), new Mode("aeolian", 9, -3), new Mode("locrian", 10, -5)
    );
    static Scale scale(String text) {
        for (Scale scale : SCALES) if (scale.name.equals(text)) return scale;
        throw bad("SCALE", text);
    }
    static int chordQuality(String text) {
        for (int i = 0; i < CHORDS.size(); i++) if (CHORDS.get(i).name.equals(text)) return i;
        throw bad("QUALITY", text);
    }
    static int mode(String text) {
        for (int i = 0; i < MODES.size(); i++) if (MODES.get(i).name.equals(text)) return i;
        throw bad("MODE", text);
    }
    static List<Pitch> build(Pitch root, List<Tone> tones) {
        List<Pitch> result = new ArrayList<>();
        for (Tone tone : tones) result.add(root.raise(tone));
        return List.copyOf(result);
    }
    static String symbol(Pitch root, int quality, Pitch bass) {
        return root + CHORDS.get(quality).suffix + (bass == null ? "" : "/" + bass);
    }
    static String roman(int degree, int quality) {
        Chord chord = CHORDS.get(quality);
        String part = ROMANS[degree];
        return (chord.lower ? part.toLowerCase(Locale.ROOT) : part) + chord.numeralSuffix;
    }
    record Key(Pitch tonic, int mode, int fifths, List<Pitch> scale) {
        int degree(Pitch pitch) { return Math.floorMod(pitch.letter - tonic.letter, 7); }
        String prefix(Pitch pitch) {
            int difference = pitch.alteration - scale.get(degree(pitch)).alteration;
            return difference < 0 ? "b".repeat(-difference) : "#".repeat(difference);
        }
        String label(Pitch pitch) { return prefix(pitch) + (degree(pitch) + 1); }
        int pitchSet() {
            int mask = 0;
            for (Pitch pitch : scale) mask |= 1 << pitch.pitchClass();
            return mask;
        }
        @Override public String toString() { return tonic + " " + MODES.get(mode).name; }
    }
    static Key key(Pitch tonic, int mode) {
        int fifths = FIFTHS[tonic.letter] + 7 * tonic.alteration + MODES.get(mode).offset;
        if (fifths < -7 || fifths > 7) throw new CommandError("THEORETICAL KEY");
        return new Key(tonic, mode, fifths, build(tonic, SCALES.get(MODES.get(mode).scale).tones));
    }
    static Key key(List<String> words, int start) {
        Pitch tonic = pitch(words.get(start));
        int mode = mode(words.get(start + 1));
        return key(tonic, mode);
    }
    record Numeral(int alteration, int degree, int quality) {}
    record ChordSymbol(Pitch root, int quality) {}
    static Numeral numeral(String text) {
        int start = 0, alteration = 0;
        if (text.charAt(0) == 'b') { start = 1; alteration = -1; }
        else if (text.charAt(0) == '#') { start = 1; alteration = 1; }
        int end = start;
        while (end < text.length() && "IViv".indexOf(text.charAt(end)) >= 0) end++;
        String part = text.substring(start, end), suffix = text.substring(end);
        for (int degree = 0; degree < 7; degree++) {
            for (int quality = 0; quality < CHORDS.size(); quality++) {
                Chord chord = CHORDS.get(quality);
                String expected = chord.lower ? ROMANS[degree].toLowerCase(Locale.ROOT) : ROMANS[degree];
                if (part.equals(expected) && suffix.equals(chord.numeralSuffix)) return new Numeral(alteration, degree, quality);
            }
        }
        throw bad("NUMERAL", text);
    }
    static ChordSymbol chordSymbol(String text) {
        PitchPrefix prefix = pitchPrefix(text);
        if (prefix != null) {
            for (int i = 0; i < CHORDS.size(); i++) {
                if (text.substring(prefix.end).equals(CHORDS.get(i).suffix)) return new ChordSymbol(prefix.pitch, i);
            }
        }
        throw bad("SYMBOL", text);
    }

    static String chordCommand(String command, List<String> args) {
        Note input = command.equals("VOICE") ? note(args.get(0)) : null;
        Pitch root = input == null ? pitch(args.get(0)) : input.pitch;
        int quality = chordQuality(args.get(1));
        Chord chord = CHORDS.get(quality);
        int inversion = args.size() == 3 ? canonical(args.get(2), 0, chord.tones.size() - 1) : 0;
        if (inversion < 0) throw bad("INVERSION", args.get(2));
        List<Pitch> tones = build(root, chord.tones), ordered = new ArrayList<>();
        for (int i = 0; i < tones.size(); i++) ordered.add(tones.get((i + inversion) % tones.size()));
        String name = symbol(root, quality, inversion == 0 ? null : ordered.getFirst());
        if (input == null) return "CHORD " + name + " " + join(ordered, " ");
        List<Note> result = new ArrayList<>();
        List<Integer> values = new ArrayList<>();
        int value = input.midi();
        for (int i = 0; i < ordered.size(); i++) {
            Pitch pitch = ordered.get(i);
            if (i != 0 || inversion != 0) {
                int difference = Math.floorMod(pitch.pitchClass() - value, 12);
                value += difference == 0 ? 12 : difference;
            }
            Note next = fromPitch(pitch, value);
            if (!next.valid()) throw new CommandError("OUT OF RANGE");
            result.add(next);
            values.add(value);
        }
        return "VOICE " + name + " " + join(result, " ") + " midi=" + join(values, ",");
    }
    static String identify(List<Note> notes) {
        notes.sort(Comparator.comparingInt(Note::midi));
        List<Note> candidates = new ArrayList<>();
        int set = 0;
        for (Note note : notes) {
            int bit = 1 << note.pitch.pitchClass();
            if ((set & bit) == 0) { set |= bit; candidates.add(note); }
        }
        Pitch bass = candidates.getFirst().pitch;
        for (Note root : candidates) {
            for (int quality = 0; quality < CHORDS.size(); quality++) {
                Chord chord = CHORDS.get(quality);
                int mask = 0;
                for (Tone tone : chord.tones) mask |= 1 << Math.floorMod(root.midi() + tone.semitones, 12);
                if (mask != set) continue;
                int inversion = 0;
                while (Math.floorMod(root.midi() + chord.tones.get(inversion).semitones, 12) != bass.pitchClass()) inversion++;
                return "IDENTIFY " + symbol(root.pitch, quality, inversion == 0 ? null : bass)
                    + " root=" + root.pitch + " quality=" + chord.name + " inversion=" + inversion;
            }
        }
        return "IDENTIFY UNKNOWN";
    }
    static String melody(List<Note> notes) {
        Note low = notes.getFirst(), high = low;
        for (Note note : notes) {
            if (note.midi() < low.midi()) low = note;
            if (note.midi() > high.midi()) high = note;
        }
        Interval range = between(low, high).interval;
        List<String> steps = new ArrayList<>();
        int leaps = 0;
        for (int i = 1; i < notes.size(); i++) {
            Motion motion = between(notes.get(i - 1), notes.get(i));
            steps.add((motion.down ? "-" : "+") + motion.interval);
            if (Math.abs(notes.get(i).midi() - notes.get(i - 1).midi()) >= 3) leaps++;
        }
        return "MELODY n=" + notes.size() + " low=" + low + " high=" + high + " range=" + range
            + " leaps=" + leaps + " steps=" + join(steps, ",");
    }
    static String cadence(List<Numeral> numerals) {
        if (numerals.size() < 2) return "none";
        Numeral x = numerals.get(numerals.size() - 2), y = numerals.getLast();
        if (x.alteration == 0 && y.alteration == 0) {
            if (x.degree == 4 && y.degree == 0) return "authentic";
            if (x.degree == 3 && y.degree == 0) return "plagal";
            if (x.degree == 4 && y.degree == 5) return "deceptive";
        }
        return y.alteration == 0 && y.degree == 4 ? "half" : "none";
    }
    static String diatonic(Key key) {
        List<String> rows = new ArrayList<>();
        rows.add("DIATONIC " + key);
        for (int size = 3; size <= 4; size++) {
            List<String> items = new ArrayList<>();
            for (int i = 0; i < 7; i++) {
                Pitch root = key.scale.get(i);
                int third = Math.floorMod(key.scale.get((i + 2) % 7).pitchClass() - root.pitchClass(), 12);
                int fifth = Math.floorMod(key.scale.get((i + 4) % 7).pitchClass() - root.pitchClass(), 12);
                int quality;
                if (size == 3) quality = third == 4 ? 0 : fifth == 7 ? 1 : 2;
                else {
                    int seventh = Math.floorMod(key.scale.get((i + 6) % 7).pitchClass() - root.pitchClass(), 12);
                    quality = third == 4 ? (seventh == 11 ? 9 : 8) : fifth == 7 ? 10 : 12;
                }
                items.add(roman(i, quality) + "=" + symbol(root, quality, null));
            }
            rows.add((size == 3 ? "TRIADS " : "SEVENTHS ") + join(items, " "));
        }
        return join(rows, "\n");
    }
    static String keyCommand(String command, List<String> args) {
        Key key = key(args, 0);
        return switch (command) {
            case "KEYSIG" -> {
                int p = key.fifths;
                if (p == 0) yield "KEYSIG " + key + " none";
                List<String> names = List.of((p > 0 ? "F# C# G# D# A# E# B#" : "Bb Eb Ab Db Gb Cb Fb").split(" "));
                yield "KEYSIG " + key + (p > 0 ? " sharps=" : " flats=") + Math.abs(p) + " " + join(names.subList(0, Math.abs(p)), " ");
            }
            case "RELATIVE" -> "RELATIVE " + key + " major=" + fifthPitch(key.fifths) + " minor=" + fifthPitch(key.fifths + 3);
            case "DEGREE" -> {
                Pitch pitch = pitch(args.get(2));
                yield "DEGREE " + key + " " + args.get(2) + " " + key.label(pitch);
            }
            case "KEYDIST" -> {
                Key other = key(args, 2);
                int distance = Math.floorMod(other.fifths - key.fifths, 12);
                if (distance > 6) distance -= 12;
                boolean sameTonic = key.tonic.pitchClass() == other.tonic.pitchClass();
                String relation;
                if (key.pitchSet() == other.pitchSet()) relation = sameTonic ? "same" : "relative";
                else if (sameTonic) relation = "parallel";
                else relation = Math.abs(distance) == 1 ? "close" : "distant";
                yield "KEYDIST " + key + " " + other + " fifths=" + (distance > 0 ? "+" : "") + distance
                    + " common=" + Integer.bitCount(key.pitchSet() & other.pitchSet()) + " relation=" + relation;
            }
            case "DIATONIC" -> diatonic(key);
            case "ANALYZE" -> {
                List<ChordSymbol> symbols = new ArrayList<>();
                for (String word : args.subList(2, args.size())) symbols.add(chordSymbol(word));
                List<String> items = new ArrayList<>();
                for (ChordSymbol chord : symbols) items.add(key.prefix(chord.root) + roman(key.degree(chord.root), chord.quality));
                yield "ANALYZE " + key + " " + join(items, " ");
            }
            case "PROGRESSION" -> {
                List<Numeral> numerals = new ArrayList<>();
                for (String word : args.subList(2, args.size())) numerals.add(numeral(word));
                List<String> rows = new ArrayList<>();
                rows.add("PROGRESSION " + key + " " + numerals.size());
                for (int i = 0; i < numerals.size(); i++) {
                    Numeral numeral = numerals.get(i);
                    Pitch degree = key.scale.get(numeral.degree);
                    Pitch root = new Pitch(degree.letter, degree.alteration + numeral.alteration);
                    List<Pitch> tones = build(root, CHORDS.get(numeral.quality).tones);
                    rows.add(args.get(i + 2) + " " + symbol(root, numeral.quality, null) + " " + join(tones, " "));
                }
                rows.add("CADENCE " + cadence(numerals));
                yield join(rows, "\n");
            }
            default -> throw new CommandError("UNKNOWN COMMAND " + command);
        };
    }

    int tuning = 44000;

    String execute(String line) {
        List<String> words = Arrays.asList(line.split(" "));
        String command = words.getFirst();
        List<String> args = words.subList(1, words.size());
        int minimum = switch (command) {
            case "MIDI", "NOTE", "FREQ", "TUNING", "PITCH", "INVERT", "ENHARMONIC", "CIRCLE", "FINDKEY" -> 1;
            case "INTERVAL", "SCALE", "CHORD", "VOICE", "IDENTIFY", "MELODY", "KEYSIG", "RELATIVE", "DIATONIC" -> 2;
            case "TRANSPOSE", "PROGRESSION", "ANALYZE", "DEGREE", "SPELL" -> 3;
            case "KEYDIST" -> 4;
            default -> throw new CommandError("UNKNOWN COMMAND " + command);
        };
        int maximum = switch (command) {
            case "CHORD", "VOICE" -> 3;
            case "IDENTIFY", "MELODY", "PROGRESSION", "ANALYZE", "FINDKEY" -> 15;
            default -> minimum;
        };
        if (args.size() < minimum || args.size() > maximum) throw new CommandError("ARGUMENT COUNT");
        return switch (command) {
            case "MIDI", "FREQ", "ENHARMONIC" -> {
                Note note = note(args.getFirst());
                int value = note.midi();
                if (command.equals("MIDI")) yield "MIDI " + args.getFirst() + " " + value;
                if (command.equals("FREQ")) {
                    int cents = (int) Math.floor(tuning * Math.pow(2, (value - 69) / 12.0) + 0.5);
                    yield "FREQ " + args.getFirst() + " " + frequencyText(cents);
                }
                List<Note> equivalents = new ArrayList<>();
                for (int octave = -1; octave <= 9; octave++) {
                    for (int letter = 0; letter < 7; letter++) {
                        int alteration = value - 12 * (octave + 1) - NATURALS[letter];
                        if (alteration >= -2 && alteration <= 2) equivalents.add(new Note(new Pitch(letter, alteration), octave));
                    }
                }
                yield "ENHARMONIC " + args.getFirst() + " " + join(equivalents, " ");
            }
            case "NOTE" -> {
                int value = number(args.getFirst());
                yield "NOTE " + value + " " + spelling(value, false) + " " + spelling(value, true);
            }
            case "TUNING", "PITCH" -> {
                int value = frequency(args.getFirst(), command.equals("TUNING"));
                if (command.equals("TUNING")) { tuning = value; yield "TUNING " + frequencyText(value); }
                double x = 69 + 12 * Math.log((double) value / tuning) / Math.log(2);
                int nearest = (int) Math.floor(x + 0.5);
                if (nearest < 0 || nearest > 127) throw new CommandError("OUT OF RANGE");
                int cents = (int) Math.floor(100 * (x - nearest) + 0.5);
                yield "PITCH " + frequencyText(value) + " " + spelling(nearest, false) + " " + (cents >= 0 ? "+" : "") + cents;
            }
            case "INTERVAL" -> {
                Note first = note(args.get(0)), second = note(args.get(1));
                Motion motion = between(first, second);
                yield "INTERVAL " + args.get(0) + " " + args.get(1) + " " + motion.interval + (motion.down ? " down" : " up")
                    + " semitones=" + motion.semitones + " simple=" + motion.interval.simple() + " class=" + motion.interval.consonance();
            }
            case "INVERT" -> {
                Interval simple = interval(args.getFirst()).simple();
                Interval inverse = new Interval(simple.quality.inverse(), 9 - simple.number);
                if (inverse.forbidden()) throw new CommandError("CANNOT INVERT");
                yield "INVERT " + args.getFirst() + " " + simple + " " + inverse;
            }
            case "TRANSPOSE" -> {
                Note note = note(args.get(0));
                Interval interval = interval(args.get(1));
                String direction = args.get(2);
                if (!direction.equals("UP") && !direction.equals("DOWN")) throw bad("DIRECTION", direction);
                int sign = direction.equals("UP") ? 1 : -1;
                Tone tone = interval.tone();
                int position = note.position() + sign * tone.letters, value = note.midi() + sign * tone.semitones;
                int letter = Math.floorMod(position, 7), octave = Math.floorDiv(position, 7);
                int alteration = value - 12 * (octave + 1) - NATURALS[letter];
                if (alteration < -2 || alteration > 2) throw new CommandError("CANNOT SPELL");
                Note result = new Note(new Pitch(letter, alteration), octave);
                if (!result.valid()) throw new CommandError("OUT OF RANGE");
                yield "TRANSPOSE " + args.get(0) + " " + args.get(1) + " " + direction + " " + result;
            }
            case "SCALE" -> {
                Pitch root = pitch(args.get(0));
                Scale scale = scale(args.get(1));
                List<Pitch> pitches = build(root, scale.tones);
                List<Integer> steps = new ArrayList<>();
                for (int i = 0; i < scale.tones.size(); i++) {
                    int next = i + 1 < scale.tones.size() ? scale.tones.get(i + 1).semitones : 12;
                    steps.add(next - scale.tones.get(i).semitones);
                }
                yield "SCALE " + args.get(0) + " " + args.get(1) + " " + join(pitches, " ") + " steps=" + join(steps, ",");
            }
            case "CHORD", "VOICE" -> chordCommand(command, args);
            case "IDENTIFY" -> identify(notes(args));
            case "MELODY" -> melody(notes(args));
            case "CIRCLE" -> {
                int mode = mode(args.getFirst());
                List<Pitch> pitches = new ArrayList<>();
                for (int p = -7; p <= 7; p++) pitches.add(fifthPitch(p - MODES.get(mode).offset));
                yield "CIRCLE " + args.getFirst() + " " + join(pitches, " ");
            }
            case "FINDKEY" -> {
                List<Pitch> pitches = new ArrayList<>();
                for (String word : args) pitches.add(pitch(word));
                List<Key> keys = new ArrayList<>();
                for (int p = -7; p <= 7; p++) {
                    for (int mode = 0; mode < 2; mode++) {
                        Key key = key(fifthPitch(p - MODES.get(mode).offset), mode);
                        if (key.scale.containsAll(pitches)) keys.add(key);
                    }
                }
                yield "FINDKEY " + keys.size() + (keys.isEmpty() ? "" : " " + join(keys, ", "));
            }
            case "SPELL" -> {
                int value = number(args.getFirst());
                Key key = key(args, 1);
                Pitch pitch = spelling(value, key.fifths < 0).pitch;
                for (Pitch candidate : key.scale) if (candidate.pitchClass() == value % 12) { pitch = candidate; break; }
                Note note = fromPitch(pitch, value);
                if (!note.valid()) throw new CommandError("OUT OF RANGE");
                yield "SPELL " + value + " " + key + " " + note + " " + key.label(pitch);
            }
            default -> keyCommand(command, args);
        };
    }

    public static void main(String[] args) throws IOException {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in));
        BufferedWriter output = new BufferedWriter(new OutputStreamWriter(System.out));
        int count = Integer.parseInt(input.readLine());
        Main calculator = new Main();
        for (int i = 0; i < count; i++) {
            String response;
            try { response = calculator.execute(input.readLine()); }
            catch (CommandError error) { response = error.getMessage(); }
            output.write(response);
            output.write('\n');
        }
        output.flush();
    }
}
