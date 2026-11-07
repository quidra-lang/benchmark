import java.nio.file.*;
import java.util.*;
final class NetworkIo {
    record Network(List<String> names, List<List<String>> states, List<List<Integer>> parents,
                   Map<Integer, double[][]> expert) {}
    record Settings(double alpha, String method, List<Integer> order, int limit, long seed,
                    List<String> sources) {}
    record Input(Network network, List<int[]> samples, List<String> queries, Settings settings) {}
    static Input read() throws Exception {
        List<String> lines = new ArrayList<>();
        for (String line : Files.readAllLines(Path.of("input", "network.txt")))
            if (!line.isEmpty() && !line.startsWith("#"))
                lines.add(line);
        List<String> names = new ArrayList<>();
        List<List<String>> states = new ArrayList<>();
        List<List<Integer>> parents = new ArrayList<>();
        Map<Integer, double[][]> expert = new HashMap<>();
        for (int position = 0; position < lines.size();) {
            String[] w = lines.get(position++).split(" ");
            if (w[0].equals("VARIABLE")) {
                names.add(w[1]);
                states.add(new ArrayList<>(Arrays.asList(w).subList(2, w.length)));
                parents.add(new ArrayList<>());
            } else if (w[0].equals("PARENTS")) {
                List<Integer> list = parents.get(names.indexOf(w[1]));
                for (int i = 2; i < w.length; i++)
                    list.add(names.indexOf(w[i]));
            } else {
                int variable = names.indexOf(w[1]), rows = 1;
                for (int parent : parents.get(variable))
                    rows *= states.get(parent).size();
                double[][] cpt = new double[rows][states.get(variable).size()];
                for (int r = 0; r < rows; r++) {
                    String[] probabilities = lines.get(position++).split(" ");
                    for (int s = 0; s < cpt[r].length; s++)
                        cpt[r][s] = Double.parseDouble(probabilities[s]);
                }
                expert.put(variable, cpt);
            }
        }
        Network network = new Network(names, states, parents, expert);
        lines = Files.readAllLines(Path.of("input", "params.txt"));
        double alpha = Double.parseDouble(lines.get(0).split(" ")[1]);
        String method = lines.get(1).split(" ")[1];
        List<Integer> order = new ArrayList<>();
        String[] w = lines.get(2).split(" ");
        for (int i = 1; i < w.length; i++)
            order.add(names.indexOf(w[i]));
        int limit = Integer.parseInt(lines.get(3).split(" ")[1]);
        long seed = Long.parseLong(lines.get(4).split(" ")[1]);
        List<String> sources = new ArrayList<>(Collections.nCopies(names.size(), ""));
        for (String line : lines.subList(5, lines.size())) {
            w = line.split(" ");
            sources.set(names.indexOf(w[1]), w[2]);
        }
        Settings settings = new Settings(alpha, method, order, limit, seed, sources);
        lines = Files.readAllLines(Path.of("input", "samples.csv"));
        String[] columns = lines.getFirst().split(",");
        List<int[]> samples = new ArrayList<>();
        for (String line : lines.subList(1, lines.size())) {
            String[] values = line.split(",");
            int[] sample = new int[names.size()];
            for (int i = 0; i < columns.length; i++) {
                int v = names.indexOf(columns[i]);
                sample[v] = states.get(v).indexOf(values[i]);
            }
            samples.add(sample);
        }
        return new Input(network, samples, Files.readAllLines(Path.of("input", "queries.txt")),
                         settings);
    }
}
