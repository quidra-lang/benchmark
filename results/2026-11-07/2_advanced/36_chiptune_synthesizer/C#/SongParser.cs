using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class SongParser {
    public static readonly string[] PITCHES = { "C-", "C#", "D-", "D#", "E-", "F-",
                                                "F#", "G-", "G#", "A-", "A#", "B-" };
    public static int Hex(string text) {
        return Convert.ToInt32(text, 16);
    }
    public static int Note(string text) {
        for (int i = 0; i < PITCHES.Length; i++)
            if (text.StartsWith(PITCHES[i]))
                return 12 * (text[2] - '0') + i;
        throw new ArgumentException(text);
    }
    public static string NoteName(int number) {
        return PITCHES[number % 12] + number / 12;
    }
    public sealed record Effect(string text, string name, int argument, int x, int y);
    public static Effect ParseEffect(string text) {
        if (text.Equals("..."))
            return new Effect(text, "", 0, 0, 0);
        int argument = Hex(text.Substring(1));
        return new Effect(text, text.StartsWith("E") ? text.Substring(0, 2) : text.Substring(0, 1), argument,
                          argument / 16, argument % 16);
    }
    public record Cell(int note, int instrument, int volume, Effect effect) {
        public bool Empty() {
            return note == -2 && instrument == 0 && volume < 0 && effect.name.Length == 0;
        }
    }
    public static Cell ParseCell(string text) {
        string note = text.Substring(0, 3), instrument = text.Substring(4, 2), volume = text.Substring(7, 1);
        return new Cell(note.Equals("...")   ? -2
                        : note.Equals("OFF") ? -1
                                             : Note(note),
                        instrument.Equals("..") ? 0 : Hex(instrument), volume.Equals(".") ? -1 : Hex(volume),
                        ParseEffect(text.Substring(9)));
    }
    public sealed class Instrument {
        public int number;
        public string name, wave;
        public int mode, attack, decay, sustain, release, vibratoDelay = -1, vibratoSpeed, vibratoDepth,
                                                          sweep;
        public int[] arpeggio = new int[0], table = new int[0];
    }
    public sealed class Song {
        public string title;
        public int rate, speed, tempo, gain;
        public int[] order;
        public readonly SortedDictionary<int, Instrument> instruments = new();
        public readonly SortedDictionary<int, Cell[][]> patterns = new();
    }
    public sealed class Settings {
        public readonly Dictionary<string, string[]> entries = new();
        public readonly HashSet<int> traces = new();
        public int Integer(string key) {
            return int.Parse(entries[key][0]);
        }
        public int[] Numbers(string key) {
            string[] values = entries[key];
            int[] result = new int[values.Length];
            for (int i = 0; i < values.Length; i++)
                result[i] = int.Parse(values[i]);
            return result;
        }
    }
    public static Song ReadSong() {
        List<string> lines = new();
        foreach (string line in File.ReadAllLines(Path.Combine("input/song.txt"), Encoding.ASCII))
            if (line.Length != 0 && !line.StartsWith("#"))
                lines.Add(line);
        Song song = new Song();
        song.title = lines[0].Substring(6);
        song.rate = int.Parse(lines[1].Split(" ")[1]);
        song.speed = int.Parse(lines[2].Split(" ")[1]);
        song.tempo = int.Parse(lines[3].Split(" ")[1]);
        song.gain = int.Parse(lines[4].Split(" ")[1]);
        int i = 5;
        while (i < lines.Count) {
            string[] parts = lines[i++].Split(" ");
            if (parts[0].Equals("ORDER")) {
                song.order = new int[parts.Length - 1];
                for (int j = 1; j < parts.Length; j++)
                    song.order[j - 1] = Hex(parts[j]);
            } else if (parts[0].Equals("INSTRUMENT")) {
                Instrument instrument = new Instrument();
                instrument.number = Hex(parts[1]);
                instrument.name = parts[2];
                while (!lines[i].Equals("END")) {
                    string[] attributes = lines[i++].Split(" ");
                    string kind = attributes[0];
                    if (kind.Equals("WAVE")) {
                        instrument.wave = attributes[1];
                        if (instrument.wave.Equals("PULSE"))
                            instrument.mode =
                                Array.IndexOf(new string[] { "12", "25", "50", "75" }, attributes[2]);
                        if (instrument.wave.Equals("NOISE"))
                            instrument.mode = attributes[2].Equals("SHORT") ? 1 : 0;
                        if (instrument.wave.Equals("TABLE")) {
                            instrument.table = new int[32];
                            for (int j = 0; j < 32; j++)
                                instrument.table[j] = Hex(attributes[2].Substring(j, 1));
                        }
                    } else if (kind.Equals("ENVELOPE")) {
                        instrument.attack = int.Parse(attributes[1]);
                        instrument.decay = int.Parse(attributes[2]);
                        instrument.sustain = int.Parse(attributes[3]);
                        instrument.release = int.Parse(attributes[4]);
                    } else if (kind.Equals("VIBRATO")) {
                        instrument.vibratoDelay = int.Parse(attributes[1]);
                        instrument.vibratoSpeed = int.Parse(attributes[2]);
                        instrument.vibratoDepth = int.Parse(attributes[3]);
                    } else if (kind.Equals("ARPEGGIO")) {
                        instrument.arpeggio = new int[attributes.Length - 1];
                        for (int j = 1; j < attributes.Length; j++)
                            instrument.arpeggio[j - 1] = int.Parse(attributes[j]);
                    } else
                        instrument.sweep = int.Parse(attributes[1]);
                }
                i++;
                song.instruments[instrument.number] = instrument;
            } else {
                int number = Hex(parts[1]);
                Cell[][] pattern = Enumerable.Range(0, 64)
                                       .Select(
                                           _ => new Cell[4])
                                       .ToArray();
                foreach (Cell[] row in pattern)
                    Array.Fill(row, ParseCell("... .. . ..."));
                while (!lines[i].Equals("END")) {
                    string line = lines[i++];
                    int row = Hex(line.Substring(0, 2));
                    string[] cells = line.Substring(3).Split(" | ", StringSplitOptions.None);
                    for (int channel = 0; channel < 4; channel++)
                        pattern[row][channel] = ParseCell(cells[channel]);
                }
                i++;
                song.patterns[number] = pattern;
            }
        }
        return song;
    }
    public static Settings ReadSettings() {
        Settings settings = new Settings();
        foreach (string line in File.ReadAllLines(Path.Combine("input/params.txt"), Encoding.ASCII)) {
            string[] parts = line.Split(" ");
            if (parts[0].Equals("trace"))
                settings.traces.Add(Hex(parts[1]) * 64 + Hex(parts[2]));
            else
                settings.entries[parts[0]] = parts[1..parts.Length];
        }
        return settings;
    }
}
