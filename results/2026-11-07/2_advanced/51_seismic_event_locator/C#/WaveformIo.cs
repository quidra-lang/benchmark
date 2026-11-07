using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class WaveformIo {
    public sealed class Station {
        public string code;
        public int order, x, y, elevation, start;
        public long[] samples;
        public long mean, peak;
        public double noise;
        public int clipped, triggers, shortTriggers;
        public List<Picker.Pick> picks = new();
        public double correction, magnitudeCorrection;
    }
    public sealed class Params {
        public Dictionary<string, double[]> values = new();
        public double Get(string key) {
            return values[key][0];
        }
        public int Integer(string key) {
            return (int)Get(key);
        }
        public double[] Row(string key) {
            return values[key];
        }
    }
    public record Data(List<Station> stations, Params settings) {
    }
    public static List<string> Lines(string name) {
        return File.ReadAllLines(Path.Combine("input", name), Encoding.ASCII).ToList();
    }
    public static Data Read() {
        List<Station> stations = new();
        foreach (string line in Lines("stations.csv").GetRange(1, Lines("stations.csv").Count - (1))) {
            string[] w = line.Split(',');
            Station s = new Station();
            s.code = w[0];
            s.x = int.Parse(w[1]);
            s.y = int.Parse(w[2]);
            s.elevation = int.Parse(w[3]);
            s.order = stations.Count;
            stations.Add(s);
        }
        List<string> waveform = Lines("waveforms.txt");
        int cursor = 0;
        foreach (Station s in stations) {
            string[] header = waveform[cursor++].Split(' ');
            s.start = int.Parse(header[2]);
            s.samples = new long[int.Parse(header[3])];
            int index = 0;
            while (index < s.samples.Length)
                foreach (string word in waveform[cursor++].Split(' '))
                    s.samples[index++] = long.Parse(word);
        }
        Params settings = new Params();
        foreach (string line in Lines("params.txt")) {
            string[] w = line.Split(' ');
            double[] values = new double[w.Length - 1];
            for (int i = 1; i < w.Length; i++)
                values[i - 1] = double.Parse(w[i]);
            settings.values[w[0]] = values;
        }
        return new Data(stations, settings);
    }
}
