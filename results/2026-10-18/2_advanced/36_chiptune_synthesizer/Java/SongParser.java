import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.io.IOException;
import java.util.*;
final class SongParser {
    static final String[] PITCHES = {"C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#", "B-"};
    static int hex(String text) {
        return Integer.parseInt(text, 16);
    }
    static int note(String text) {
        for (int i = 0; i < PITCHES.length; i++)
            if (text.startsWith(PITCHES[i]))
                return 12 * (text.charAt(2) - '0') + i;
        throw new IllegalArgumentException(text);
    }
    static String noteName(int number) {
        return PITCHES[number % 12] + number / 12;
    }
    record Effect(String text, String name, int argument, int x, int y) {}
    static Effect effect(String text) {
        if (text.equals("..."))
            return new Effect(text, "", 0, 0, 0);
        int argument = hex(text.substring(1));
        return new Effect(text, text.startsWith("E") ? text.substring(0, 2) : text.substring(0, 1), argument,
                          argument / 16, argument % 16);
    }
    record Cell(int note, int instrument, int volume, Effect effect) {
        boolean empty() {
            return note == -2 && instrument == 0 && volume < 0 && effect.name.isEmpty();
        }
    }
    static Cell cell(String text) {
        String note = text.substring(0, 3), instrument = text.substring(4, 6), volume = text.substring(7, 8);
        return new Cell(note.equals("...")   ? -2
                        : note.equals("OFF") ? -1
                                             : note(note),
                        instrument.equals("..") ? 0 : hex(instrument), volume.equals(".") ? -1 : hex(volume),
                        effect(text.substring(9)));
    }
    static final class Instrument {
        int number;
        String name, wave;
        int mode, attack, decay, sustain, release, vibratoDelay = -1, vibratoSpeed, vibratoDepth, sweep;
        int[] arpeggio = new int[0], table = new int[0];
    }
    static final class Song {
        String title;
        int rate, speed, tempo, gain;
        int[] order;
        final SortedMap<Integer, Instrument> instruments = new TreeMap<>();
        final SortedMap<Integer, Cell[][]> patterns = new TreeMap<>();
    }
    static final class Settings {
        final Map<String, String[]> entries = new HashMap<>();
        final Set<Integer> traces = new HashSet<>();
        int integer(String key) {
            return Integer.parseInt(entries.get(key)[0]);
        }
        int[] numbers(String key) {
            String[] values = entries.get(key);
            int[] result = new int[values.length];
            for (int i = 0; i < values.length; i++)
                result[i] = Integer.parseInt(values[i]);
            return result;
        }
    }
    static Song song() throws IOException {
        List<String> lines = new ArrayList<>();
        for (String line : Files.readAllLines(Path.of("input/song.txt"), StandardCharsets.US_ASCII))
            if (!line.isEmpty() && !line.startsWith("#"))
                lines.add(line);
        Song song = new Song();
        song.title = lines.get(0).substring(6);
        song.rate = Integer.parseInt(lines.get(1).split(" ")[1]);
        song.speed = Integer.parseInt(lines.get(2).split(" ")[1]);
        song.tempo = Integer.parseInt(lines.get(3).split(" ")[1]);
        song.gain = Integer.parseInt(lines.get(4).split(" ")[1]);
        int i = 5;
        while (i < lines.size()) {
            String[] parts = lines.get(i++).split(" ");
            if (parts[0].equals("ORDER")) {
                song.order = new int[parts.length - 1];
                for (int j = 1; j < parts.length; j++)
                    song.order[j - 1] = hex(parts[j]);
            } else if (parts[0].equals("INSTRUMENT")) {
                Instrument instrument = new Instrument();
                instrument.number = hex(parts[1]);
                instrument.name = parts[2];
                while (!lines.get(i).equals("END")) {
                    String[] attributes = lines.get(i++).split(" ");
                    String kind = attributes[0];
                    if (kind.equals("WAVE")) {
                        instrument.wave = attributes[1];
                        if (instrument.wave.equals("PULSE"))
                            instrument.mode = List.of("12", "25", "50", "75").indexOf(attributes[2]);
                        if (instrument.wave.equals("NOISE"))
                            instrument.mode = attributes[2].equals("SHORT") ? 1 : 0;
                        if (instrument.wave.equals("TABLE")) {
                            instrument.table = new int[32];
                            for (int j = 0; j < 32; j++)
                                instrument.table[j] = hex(attributes[2].substring(j, j + 1));
                        }
                    } else if (kind.equals("ENVELOPE")) {
                        instrument.attack = Integer.parseInt(attributes[1]);
                        instrument.decay = Integer.parseInt(attributes[2]);
                        instrument.sustain = Integer.parseInt(attributes[3]);
                        instrument.release = Integer.parseInt(attributes[4]);
                    } else if (kind.equals("VIBRATO")) {
                        instrument.vibratoDelay = Integer.parseInt(attributes[1]);
                        instrument.vibratoSpeed = Integer.parseInt(attributes[2]);
                        instrument.vibratoDepth = Integer.parseInt(attributes[3]);
                    } else if (kind.equals("ARPEGGIO")) {
                        instrument.arpeggio = new int[attributes.length - 1];
                        for (int j = 1; j < attributes.length; j++)
                            instrument.arpeggio[j - 1] = Integer.parseInt(attributes[j]);
                    } else
                        instrument.sweep = Integer.parseInt(attributes[1]);
                }
                i++;
                song.instruments.put(instrument.number, instrument);
            } else {
                int number = hex(parts[1]);
                Cell[][] pattern = new Cell[64][4];
                for (Cell[] row : pattern)
                    Arrays.fill(row, cell("... .. . ..."));
                while (!lines.get(i).equals("END")) {
                    String line = lines.get(i++);
                    int row = hex(line.substring(0, 2));
                    String[] cells = line.substring(3).split(" \\| ");
                    for (int channel = 0; channel < 4; channel++)
                        pattern[row][channel] = cell(cells[channel]);
                }
                i++;
                song.patterns.put(number, pattern);
            }
        }
        return song;
    }
    static Settings settings() throws IOException {
        Settings settings = new Settings();
        for (String line : Files.readAllLines(Path.of("input/params.txt"), StandardCharsets.US_ASCII)) {
            String[] parts = line.split(" ");
            if (parts[0].equals("trace"))
                settings.traces.add(hex(parts[1]) * 64 + hex(parts[2]));
            else
                settings.entries.put(parts[0], Arrays.copyOfRange(parts, 1, parts.length));
        }
        return settings;
    }
}
