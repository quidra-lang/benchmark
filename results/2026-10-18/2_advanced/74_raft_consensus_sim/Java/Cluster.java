import java.nio.file.*;
import java.util.*;
final class Cluster {
    record Settings(int nodes, int electionMin, int electionMax, int heartbeat, int batch,
                    int quorum, int seed, int end, int retry, int attempts, int sample) {}
    record Control(int time, String kind, List<Integer> arguments, List<List<Integer>> groups) {}
    static final class Request {
        int number, time, initialDestination, scheduled, destination, attempts, redirects, index,
            term, latency;
        String command, status, result;
        boolean accepted, abandoned;
        Request(int number, int time, int destination, String command) {
            this.number = number;
            this.time = time;
            this.initialDestination = destination;
            this.destination = destination;
            this.scheduled = time;
            this.command = command;
        }
    }
    record Input(Settings settings, List<Control> controls, List<Request> requests) {}
    static Input read() throws Exception {
        Map<String, int[]> values = new HashMap<>();
        for (String line : Files.readAllLines(Path.of("input", "cluster.txt"))) {
            String[] fields = line.split(" ");
            int[] numbers = new int[fields.length - 1];
            for (int i = 1; i < fields.length; i++)
                numbers[i - 1] = Integer.parseInt(fields[i]);
            values.put(fields[0], numbers);
        }
        Settings settings = new Settings(
            values.get("NODES")[0], values.get("ELECTION")[0], values.get("ELECTION")[1],
            values.get("HEARTBEAT")[0], values.get("BATCH")[0], values.get("QUORUM")[0],
            values.get("SEED")[0], values.get("END")[0], values.get("RETRY")[0],
            values.get("ATTEMPTS")[0], values.get("SAMPLE")[0]);
        List<Control> controls = new ArrayList<>();
        List<Request> requests = new ArrayList<>();
        for (String line : Files.readAllLines(Path.of("input", "script.txt"))) {
            String[] w = line.split(" ");
            int time = Integer.parseInt(w[0]);
            String kind = w[1];
            if (kind.equals("REQUEST"))
                requests.add(new Request(requests.size() + 1, time, Integer.parseInt(w[2]),
                                         String.join(" ", Arrays.copyOfRange(w, 3, w.length))));
            else {
                List<Integer> arguments = new ArrayList<>();
                List<List<Integer>> groups = new ArrayList<>();
                for (int i = 2; i < w.length; i++)
                    if (kind.equals("PARTITION")) {
                        List<Integer> group = new ArrayList<>();
                        for (String number : w[i].split(","))
                            group.add(Integer.parseInt(number));
                        groups.add(group);
                    } else
                        arguments.add(Integer.parseInt(w[i]));
                controls.add(new Control(time, kind, arguments, groups));
            }
        }
        return new Input(settings, controls, requests);
    }
}
