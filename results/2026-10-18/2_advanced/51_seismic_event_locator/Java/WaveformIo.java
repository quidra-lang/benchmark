import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.io.IOException;
import java.util.*;

final class WaveformIo {
    static final class Station {
        String code;
        int order, x, y, elevation, start;
        long[] samples;
        long mean, peak;
        double noise;
        int clipped, triggers, shortTriggers;
        List<Picker.Pick> picks = new ArrayList<>();
        double correction, magnitudeCorrection;
    }
    static final class Params {
        Map<String, double[]> values = new HashMap<>();
        double get(String key) {
            return values.get(key)[0];
        }
        int integer(String key) {
            return (int)get(key);
        }
        double[] row(String key) {
            return values.get(key);
        }
    }
    record Data(List<Station> stations, Params params) {}
    static List<String> lines(String name) throws IOException {
        return Files.readAllLines(Path.of("input", name), StandardCharsets.US_ASCII);
    }
    static Data read() throws IOException {
        List<Station> stations = new ArrayList<>();
        for (String line : lines("stations.csv").subList(1, lines("stations.csv").size())) {
            String[] w = line.split(",");
            Station s = new Station();
            s.code = w[0];
            s.x = Integer.parseInt(w[1]);
            s.y = Integer.parseInt(w[2]);
            s.elevation = Integer.parseInt(w[3]);
            s.order = stations.size();
            stations.add(s);
        }
        List<String> waveform = lines("waveforms.txt");
        int cursor = 0;
        for (Station s : stations) {
            String[] header = waveform.get(cursor++).split(" ");
            s.start = Integer.parseInt(header[2]);
            s.samples = new long[Integer.parseInt(header[3])];
            int index = 0;
            while (index < s.samples.length)
                for (String word : waveform.get(cursor++).split(" "))
                    s.samples[index++] = Long.parseLong(word);
        }
        Params params = new Params();
        for (String line : lines("params.txt")) {
            String[] w = line.split(" ");
            double[] values = new double[w.length - 1];
            for (int i = 1; i < w.length; i++)
                values[i - 1] = Double.parseDouble(w[i]);
            params.values.put(w[0], values);
        }
        return new Data(stations, params);
    }
}
