import java.nio.file.*;
import java.util.*;

final class Dataset {
    record Example(String id, Kernels.Point point, int label) {}
    static final class Settings {
        double[] coefficients, plotX, plotY;
        int[] learning;
        double tolerance, eps, multiC, lambda;
        int maximum, folds, newton, pegasos, seed, width, height;
        String multiKernel;
        List<Kernels.Kernel> kernels = new ArrayList<>();
    }
    record Data(List<Example> train, List<Example> test, List<Example> multiTrain, List<Example> multiTest,
                Settings settings) {}
    static List<String> lines(String name) throws Exception {
        return Files.readAllLines(Path.of("input", name));
    }
    static double[] reals(String[] w, int first) {
        double[] a = new double[w.length - first];
        for (int i = 0; i < a.length; i++)
            a[i] = Double.parseDouble(w[i + first]);
        return a;
    }
    static Example example(String[] w) {
        return new Example(w[0], new Kernels.Point(Double.parseDouble(w[1]), Double.parseDouble(w[2])),
                           Integer.parseInt(w[3]));
    }
    static List<Example> binary(String name) throws Exception {
        List<String> lines = lines(name);
        List<Example> result = new ArrayList<>();
        for (int i = 1; i < lines.size(); i++)
            result.add(example(lines.get(i).split(",")));
        return result;
    }
    static Data read() throws Exception {
        List<Example> train = binary("train.csv"), test = binary("test.csv"), multiTrain = new ArrayList<>(),
                      multiTest = new ArrayList<>();
        List<String> multi = lines("multiclass.csv");
        for (int i = 1; i < multi.size(); i++) {
            String[] w = multi.get(i).split(",");
            (w[4].equals("train") ? multiTrain : multiTest).add(example(w));
        }
        Settings s = new Settings();
        for (String line : lines("params.txt")) {
            String[] w = line.split(" ");
            switch (w[0]) {
            case "C_GRID" -> s.coefficients = reals(w, 1);
            case "KERNEL" -> {
                String kind = w[2];
                int degree = kind.equals("poly") ? Integer.parseInt(w[3]) : 0;
                double gamma = kind.equals("poly")  ? Double.parseDouble(w[4])
                               : kind.equals("rbf") ? Double.parseDouble(w[3])
                                                    : 0,
                       offset = kind.equals("poly") ? Double.parseDouble(w[5]) : 0;
                s.kernels.add(new Kernels.Kernel(w[1], kind, degree, gamma, offset));
            }
            case "TOLERANCE" -> s.tolerance = Double.parseDouble(w[1]);
            case "EPS" -> s.eps = Double.parseDouble(w[1]);
            case "MAX_PASSES" -> s.maximum = Integer.parseInt(w[1]);
            case "FOLDS" -> s.folds = Integer.parseInt(w[1]);
            case "LEARNING_CURVE" -> {
                s.learning = new int[w.length - 1];
                for (int i = 0; i < s.learning.length; i++)
                    s.learning[i] = Integer.parseInt(w[i + 1]);
            }
            case "NEWTON_ITERATIONS" -> s.newton = Integer.parseInt(w[1]);
            case "MULTICLASS" -> {
                s.multiKernel = w[1];
                s.multiC = Double.parseDouble(w[2]);
            }
            case "PEGASOS" -> {
                s.lambda = Double.parseDouble(w[1]);
                s.pegasos = Integer.parseInt(w[2]);
                s.seed = Integer.parseInt(w[3]);
            }
            case "PLOT_X" -> s.plotX = reals(w, 1);
            case "PLOT_Y" -> s.plotY = reals(w, 1);
            case "PLOT_SIZE" -> {
                s.width = Integer.parseInt(w[1]);
                s.height = Integer.parseInt(w[2]);
            }
            }
        }
        return new Data(train, test, multiTrain, multiTest, s);
    }
    static List<Kernels.Point> points(List<Example> examples) {
        List<Kernels.Point> points = new ArrayList<>();
        for (Example example : examples)
            points.add(example.point());
        return points;
    }
    static int[] labels(List<Example> examples) {
        int[] labels = new int[examples.size()];
        for (int i = 0; i < labels.length; i++)
            labels[i] = examples.get(i).label();
        return labels;
    }
}
