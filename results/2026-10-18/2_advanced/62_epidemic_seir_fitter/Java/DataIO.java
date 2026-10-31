import java.nio.file.*;
import java.util.*;

final class DataIO {
    record Group(String name, int population, double fatality) {}
    record Intervention(int day, double multiplier) {}
    record Scenario(String name, double multiplier) {}
    record ContactChange(String name, String group, double factor) {}
    static final class Settings {
        Map<String, List<String>> values = new HashMap<>();
        List<Scenario> scenarios = new ArrayList<>();
        List<ContactChange> changes = new ArrayList<>();
        int integer(String name, int index) {
            return Integer.parseInt(values.get(name).get(index));
        }
        double real(String name, int index) {
            return Double.parseDouble(values.get(name).get(index));
        }
        int[] integers(String name) {
            List<String> row = values.get(name);
            int[] result = new int[row.size()];
            for (int i = 0; i < result.length; i++)
                result[i] = Integer.parseInt(row.get(i));
            return result;
        }
    }
    record Data(int[] cases, int[] deaths, List<Group> groups, double[][] contacts,
                List<Intervention> interventions, Settings settings) {}
    static List<String> lines(String name) throws Exception {
        return Files.readAllLines(Path.of("input", name));
    }
    static Data read() throws Exception {
        List<String> input = lines("cases.csv");
        int[] cases = new int[input.size() - 1], deaths = new int[cases.length];
        for (int i = 0; i < cases.length; i++) {
            String[] w = input.get(i + 1).split(",");
            cases[i] = Integer.parseInt(w[1]);
            deaths[i] = Integer.parseInt(w[2]);
        }
        List<Group> groups = new ArrayList<>();
        List<double[]> contacts = new ArrayList<>();
        for (String line : lines("population.txt")) {
            String[] w = line.split(" ");
            if (w[0].equals("group"))
                groups.add(new Group(w[1], Integer.parseInt(w[2]), Double.parseDouble(w[3])));
            else {
                double[] row = new double[w.length - 1];
                for (int j = 0; j < row.length; j++)
                    row[j] = Double.parseDouble(w[j + 1]);
                contacts.add(row);
            }
        }
        List<Intervention> interventions = new ArrayList<>();
        for (String line : lines("interventions.txt")) {
            String[] w = line.split(" ");
            interventions.add(new Intervention(Integer.parseInt(w[0]), Double.parseDouble(w[1])));
        }
        Settings s = new Settings();
        for (String line : lines("params.txt")) {
            String[] w = line.split(" ");
            if (w[0].equals("scenario"))
                s.scenarios.add(new Scenario(w[1], Double.parseDouble(w[2])));
            else if (w[0].equals("contact_change"))
                s.changes.add(new ContactChange(w[1], w[2], Double.parseDouble(w[3])));
            else
                s.values.put(w[0], new ArrayList<>(Arrays.asList(w).subList(1, w.length)));
        }
        return new Data(cases, deaths, groups, contacts.toArray(double[][] ::new), interventions, s);
    }
    static void write(String name, List<String> lines) throws Exception {
        Files.createDirectories(Path.of("output"));
        Files.writeString(Path.of("output", name), String.join("\n", lines) + "\n");
    }
}
