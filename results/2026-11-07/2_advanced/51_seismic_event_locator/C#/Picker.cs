using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Picker {
    public sealed class Pick {
        public WaveformIo.Station station;
        public int sample, duration, earthquake;
        public double ratio, residual, firstResidual;
        public long amplitude;
        public bool clipped, assigned;
        public string state = "unassociated";
        public double Time() {
            return sample / 100.0;
        }
    }
    public static void Finish(WaveformIo.Station station, WaveformIo.Params settings, long[] d, long[] energy,
                              int begin, int end, double maximum) {
        station.triggers++;
        int duration = end - begin;
        if (duration < settings.Integer("min_duration")) {
            station.shortTriggers++;
            return;
        }
        int k = begin;
        while (k - 1 >= begin - settings.Integer("sta_window") + 1 &&
               energy[k - 1] >= settings.Get("noise_level"))
            k--;
        Pick pick = new Pick();
        pick.station = station;
        pick.sample = station.start + k;
        pick.duration = duration;
        pick.ratio = maximum;
        for (int j = k; j < Math.Min(k + settings.Integer("amplitude_window"), d.Length); j++) {
            pick.amplitude = Math.Max(pick.amplitude, Math.Abs(d[j]));
            if (Math.Abs(station.samples[j]) >= settings.Get("clip_level"))
                pick.clipped = true;
        }
        station.picks.Add(pick);
    }
    public static List<Pick> Detect(WaveformIo.Station station, WaveformIo.Params settings) {
        long sum = 0;
        foreach (long value in station.samples)
            sum += value;
        int n = station.samples.Length;
        station.mean = Magnitude.FloorDivision(sum, n);
        long[] d = new long[n], energy = new long[n], prefix = new long[n + 1];
        List<Double> absolute = new();
        for (int i = 0; i < n; i++) {
            d[i] = station.samples[i] - station.mean;
            energy[i] = d[i] * d[i];
            prefix[i + 1] = prefix[i] + energy[i];
            absolute.Add((double)Math.Abs(d[i]));
            station.peak = Math.Max(station.peak, Math.Abs(d[i]));
            if (Math.Abs(station.samples[i]) >= settings.Get("clip_level"))
                station.clipped++;
        }
        station.noise = Magnitude.Median(absolute);
        int sw = settings.Integer("sta_window"), lw = settings.Integer("lta_window");
        double[] on = settings.Row("trigger_on"), off = settings.Row("trigger_off");
        bool active = false;
        int begin = 0;
        double maximum = 0;
        for (int i = sw + lw - 1; i < n; i++) {
            long sta = prefix[i + 1] - prefix[i - sw + 1], lta = prefix[i - sw + 1] - prefix[i - sw - lw + 1];
            double ratio = (double)(sta * lw) / (lta * sw);
            if (!active) {
                if (sta * lw * (long)on[1] >= (long)on[0] * lta * sw) {
                    active = true;
                    begin = i;
                    maximum = ratio;
                }
            } else if (sta * lw * (long)off[1] < (long)off[0] * lta * sw) {
                Finish(station, settings, d, energy, begin, i, maximum);
                active = false;
            } else
                maximum = Math.Max(maximum, ratio);
        }
        if (active)
            Finish(station, settings, d, energy, begin, n, maximum);
        return station.picks;
    }
}
