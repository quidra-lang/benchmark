import java.nio.file.*;
import java.util.*;

final class Dataset {
    record Image(String id, int label, String pixels, double[] values) {}
    record Run(String name, String network, String optimizer, double eta, double lambda, double momentum,
               double beta1, double beta2, double epsilon) {}
    static final class Settings {
        int seed, batch, epochs, patience, decayStep, stride, bins;
        double gamma;
        int[] prune, noise;
        List<Run> runs = new ArrayList<>();
    }
    record Data(int width, int height, List<Image> train, List<Image> test, List<Network> networks,
                Settings settings) {}
    static final class Generator {
        long state;
        Generator(int seed) {
            state = seed;
        }
        int draw() {
            state = 48271 * state % 2147483647;
            return (int)state;
        }
        void shuffle(int[] order) {
            for (int i = order.length - 1; i > 0; i--) {
                int j = draw() % (i + 1), temp = order[i];
                order[i] = order[j];
                order[j] = temp;
            }
        }
    }
    static List<String> lines(String name) throws Exception {
        return Files.readAllLines(Path.of("input", name));
    }
    static Image image(String id, int label, String pixels) {
        double[] values = new double[pixels.length()];
        for (int i = 0; i < values.length; i++)
            values[i] = pixels.charAt(i) == '1' ? 1 : 0;
        return new Image(id, label, pixels, values);
    }
    static List<Image> images(String name) throws Exception {
        List<String> input = lines(name);
        List<Image> images = new ArrayList<>();
        for (int i = 1; i < input.size(); i++) {
            String[] w = input.get(i).split(",");
            images.add(image(w[0], Integer.parseInt(w[1]), w[2]));
        }
        return images;
    }
    static int[] integers(String[] words) {
        int[] values = new int[words.length - 1];
        for (int i = 0; i < values.length; i++)
            values[i] = Integer.parseInt(words[i + 1]);
        return values;
    }
    static Data read() throws Exception {
        List<String> definitions = lines("network.txt");
        String[] header = definitions.get(0).split(" ");
        int width = Integer.parseInt(header[1]), height = Integer.parseInt(header[2]);
        List<Network> networks = new ArrayList<>();
        String name = null;
        List<Integer> sizes = new ArrayList<>();
        List<String> activations = new ArrayList<>();
        for (int i = 1; i <= definitions.size(); i++) {
            String line = i == definitions.size() ? "" : definitions.get(i);
            if (line.isEmpty()) {
                if (name != null) {
                    int[] units = new int[sizes.size()];
                    for (int j = 0; j < units.length; j++)
                        units[j] = sizes.get(j);
                    networks.add(
                        new Network(name, width * height, units, activations.toArray(String[] ::new)));
                    name = null;
                    sizes.clear();
                    activations.clear();
                }
                continue;
            }
            String[] w = line.split(" ");
            if (w[0].equals("NETWORK"))
                name = w[1];
            else {
                sizes.add(Integer.parseInt(w[1]));
                activations.add(w[2]);
            }
        }
        Network current = null;
        int parameter = 0;
        for (String line : lines("weights.txt")) {
            if (line.isEmpty())
                continue;
            String[] w = line.split(" ");
            if (w[0].equals("NETWORK")) {
                for (Network net : networks)
                    if (net.name.equals(w[1]))
                        current = net;
                parameter = 0;
            } else if (w[0].equals("W") || w[0].equals("B"))
                for (int j = 1; j < w.length; j++)
                    current.initial[parameter++] = Double.parseDouble(w[j]);
        }
        Settings s = new Settings();
        for (String line : lines("params.txt")) {
            String[] w = line.split(" ");
            switch (w[0]) {
            case "SEED" -> s.seed = Integer.parseInt(w[1]);
            case "BATCH_SIZE" -> s.batch = Integer.parseInt(w[1]);
            case "MAX_EPOCHS" -> s.epochs = Integer.parseInt(w[1]);
            case "PATIENCE" -> s.patience = Integer.parseInt(w[1]);
            case "LR_STEP" -> {
                s.decayStep = Integer.parseInt(w[1]);
                s.gamma = Double.parseDouble(w[2]);
            }
            case "GRADIENT_CHECK_STRIDE" -> s.stride = Integer.parseInt(w[1]);
            case "CALIBRATION_BINS" -> s.bins = Integer.parseInt(w[1]);
            case "PRUNE" -> s.prune = integers(w);
            case "NOISE" -> s.noise = integers(w);
            case "RUN" -> {
                String opt = w[3];
                s.runs.add(new Run(w[1], w[2], opt, Double.parseDouble(w[4]), Double.parseDouble(w[5]),
                                   opt.equals("MOMENTUM") ? Double.parseDouble(w[6]) : 0,
                                   opt.equals("ADAM") ? Double.parseDouble(w[6]) : 0,
                                   opt.equals("ADAM") ? Double.parseDouble(w[7]) : 0,
                                   opt.equals("ADAM") ? Double.parseDouble(w[8]) : 0));
            }
            }
        }
        return new Data(width, height, images("train.csv"), images("test.csv"), networks, s);
    }
}
