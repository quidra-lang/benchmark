import java.io.IOException;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

final class Dataset {
    static final class Row {
        int id, y;
        double[] values;
        String label;
        Row(int id, double[] values, String label) {
            this.id = id;
            this.values = values;
            this.label = label;
        }
    }
    record Subset(String name, int[] features) {}
    static final class Settings {
        String prior;
        double epsilon, gamma, theta;
        double[] smoothing, gammas, edges, reject;
        int folds, resamples, seed, width, height, plotWidth, plotHeight;
        int[] curve;
        List<Subset> subsets = new ArrayList<>();
        List<int[]> pairs = new ArrayList<>();
    }
    static final class Data {
        List<String> features, classes;
        List<Row> train, test;
        double[][] costs;
        Settings settings;
    }
    static List<String> lines(String name) throws IOException {
        return Files.readAllLines(Path.of("input", name), StandardCharsets.US_ASCII);
    }
    static List<Row> rows(List<String> lines) {
        List<Row> result = new ArrayList<>();
        for (int i = 1; i < lines.size(); i++) {
            String[] w = lines.get(i).split(",");
            double[] x = new double[w.length - 2];
            for (int j = 0; j < x.length; j++)
                x[j] = Double.parseDouble(w[j + 1]);
            result.add(new Row(Integer.parseInt(w[0]), x, w[w.length - 1]));
        }
        return result;
    }
    static double[] decimals(String[] w, int start) {
        double[] result = new double[w.length - start];
        for (int i = start; i < w.length; i++)
            result[i - start] = Double.parseDouble(w[i]);
        return result;
    }
    static int[] features(String[] w, int start, List<String> names) {
        int[] result = new int[w.length - start];
        for (int i = start; i < w.length; i++)
            result[i - start] = names.indexOf(w[i]);
        return result;
    }
    static Data read() throws IOException {
        Data d = new Data();
        List<String> training = lines("train.csv");
        String[] header = training.get(0).split(",");
        d.features = new ArrayList<>(Arrays.asList(header).subList(1, header.length - 1));
        d.train = rows(training);
        d.test = rows(lines("test.csv"));
        SortedSet<String> names = new TreeSet<>();
        for (Row row : d.train)
            names.add(row.label);
        d.classes = new ArrayList<>(names);
        for (Row row : d.train)
            row.y = d.classes.indexOf(row.label);
        for (Row row : d.test)
            row.y = d.classes.indexOf(row.label);
        d.costs = Linalg.zeros(d.classes.size());
        List<String> costs = lines("costs.csv");
        String[] columns = costs.get(0).split(",");
        for (int i = 1; i < costs.size(); i++) {
            String[] w = costs.get(i).split(",");
            int actual = d.classes.indexOf(w[0]);
            for (int j = 1; j < w.length; j++)
                d.costs[actual][d.classes.indexOf(columns[j])] = Double.parseDouble(w[j]);
        }
        Settings s = new Settings();
        d.settings = s;
        for (String line : lines("params.txt")) {
            String[] w = line.split(" ");
            switch (w[0]) {
            case "PRIOR" -> s.prior = w[1];
            case "VAR_SMOOTHING" -> s.epsilon = Double.parseDouble(w[1]);
            case "SMOOTHING_GRID" -> s.smoothing = decimals(w, 1);
            case "QDA_GAMMA" -> s.gamma = Double.parseDouble(w[1]);
            case "GAMMA_GRID" -> s.gammas = decimals(w, 1);
            case "CV_FOLDS" -> s.folds = Integer.parseInt(w[1]);
            case "CALIBRATION_EDGES" -> s.edges = decimals(w, 1);
            case "REJECT_THRESHOLDS" -> s.reject = decimals(w, 1);
            case "CURVE" -> {
                s.curve = new int[w.length - 1];
                for (int j = 1; j < w.length; j++)
                    s.curve[j - 1] = Integer.parseInt(w[j]);
            }
            case "OUTLIER_THRESHOLD" -> s.theta = Double.parseDouble(w[1]);
            case "BOOTSTRAP" -> {
                s.resamples = Integer.parseInt(w[1]);
                s.seed = Integer.parseInt(w[2]);
            }
            case "MAP_SIZE" -> {
                s.width = Integer.parseInt(w[1]);
                s.height = Integer.parseInt(w[2]);
            }
            case "PLOT_SIZE" -> {
                s.plotWidth = Integer.parseInt(w[1]);
                s.plotHeight = Integer.parseInt(w[2]);
            }
            case "SUBSET" -> s.subsets.add(new Subset(w[1], features(w, 2, d.features)));
            case "PAIR" -> s.pairs.add(features(w, 1, d.features));
            }
        }
        return d;
    }
}
