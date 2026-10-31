import java.util.*;

final class Picker {
    static final class Pick {
        WaveformIo.Station station;
        int sample, duration, event;
        double ratio, residual, firstResidual;
        long amplitude;
        boolean clipped, assigned;
        String state = "unassociated";
        double time() {
            return sample / 100.0;
        }
    }
    static void finish(WaveformIo.Station station, WaveformIo.Params params, long[] d, long[] energy,
                       int begin, int end, double maximum) {
        station.triggers++;
        int duration = end - begin;
        if (duration < params.integer("min_duration")) {
            station.shortTriggers++;
            return;
        }
        int k = begin;
        while (k - 1 >= begin - params.integer("sta_window") + 1 &&
               energy[k - 1] >= params.get("noise_level"))
            k--;
        Pick pick = new Pick();
        pick.station = station;
        pick.sample = station.start + k;
        pick.duration = duration;
        pick.ratio = maximum;
        for (int j = k; j < Math.min(k + params.integer("amplitude_window"), d.length); j++) {
            pick.amplitude = Math.max(pick.amplitude, Math.abs(d[j]));
            if (Math.abs(station.samples[j]) >= params.get("clip_level"))
                pick.clipped = true;
        }
        station.picks.add(pick);
    }
    static List<Pick> detect(WaveformIo.Station station, WaveformIo.Params params) {
        long sum = 0;
        for (long value : station.samples)
            sum += value;
        int n = station.samples.length;
        station.mean = Math.floorDiv(sum, n);
        long[] d = new long[n], energy = new long[n], prefix = new long[n + 1];
        List<Double> absolute = new ArrayList<>();
        for (int i = 0; i < n; i++) {
            d[i] = station.samples[i] - station.mean;
            energy[i] = d[i] * d[i];
            prefix[i + 1] = prefix[i] + energy[i];
            absolute.add((double)Math.abs(d[i]));
            station.peak = Math.max(station.peak, Math.abs(d[i]));
            if (Math.abs(station.samples[i]) >= params.get("clip_level"))
                station.clipped++;
        }
        station.noise = Magnitude.median(absolute);
        int sw = params.integer("sta_window"), lw = params.integer("lta_window");
        double[] on = params.row("trigger_on"), off = params.row("trigger_off");
        boolean active = false;
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
                finish(station, params, d, energy, begin, i, maximum);
                active = false;
            } else
                maximum = Math.max(maximum, ratio);
        }
        if (active)
            finish(station, params, d, energy, begin, n, maximum);
        return station.picks;
    }
}
