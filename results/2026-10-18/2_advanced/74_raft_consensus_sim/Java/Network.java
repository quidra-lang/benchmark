import java.nio.file.*;
import java.util.*;
final class Network {
    static final String[] TYPES = {"RV", "RVR", "AE", "AER", "TN"},
                          FIELDS = {"sent", "delivered", "inflight", "partition",
                                    "rule", "loss",      "down"};
    interface Payload {}
    record VoteRequest(int lastIndex, int lastTerm) implements Payload {}
    record VoteResponse(boolean granted) implements Payload {}
    record AppendRequest(int previous, int previousTerm, List<RaftNode.Entry> entries, int commit)
        implements Payload {}
    record AppendResponse(boolean success, int match) implements Payload {}
    record Immediate() implements Payload {}
    record Message(String kind, int source, int destination, int term, Payload data) {}
    record Drop(String kind, int start, int end) {}
    record Scheduled(int arrival, int source, int serial, Message message) {}
    static final class Link {
        int delay, loss, passed;
        List<Drop> drops = new ArrayList<>();
        int[] stats = new int[7];
        Link(int delay) { this.delay = delay; }
    }
    final int count;
    Link[][] links;
    int[] groups, total = new int[7];
    int[][] byType = new int[5][7];
    int serial;
    PriorityQueue<Scheduled> queue = new PriorityQueue<>(Comparator.comparingInt(Scheduled::arrival)
                                                             .thenComparingInt(Scheduled::source)
                                                             .thenComparingInt(Scheduled::serial));
    Network(int count) throws Exception {
        this.count = count;
        links = new Link[count + 1][count + 1];
        groups = new int[count + 1];
        List<String> lines = Files.readAllLines(Path.of("input", "network.txt"));
        int defaultDelay = Integer.parseInt(lines.getFirst().split(" ")[1]);
        for (int a = 1; a <= count; a++)
            for (int b = 1; b <= count; b++)
                if (a != b)
                    links[a][b] = new Link(defaultDelay);
        for (String line : lines.subList(1, lines.size())) {
            String[] w = line.split(" ");
            for (int a = 1; a <= count; a++)
                for (int b = 1; b <= count; b++)
                    if (a != b && (w[1].equals("*") || Integer.parseInt(w[1]) == a) &&
                        (w[2].equals("*") || Integer.parseInt(w[2]) == b)) {
                        Link link = links[a][b];
                        switch (w[0]) {
                        case "DELAY":
                            link.delay = Integer.parseInt(w[3]);
                            break;
                        case "LOSS":
                            link.loss = Integer.parseInt(w[3]);
                            break;
                        default:
                            link.drops.add(
                                new Drop(w[3], Integer.parseInt(w[4]), Integer.parseInt(w[5])));
                        }
                    }
        }
    }
    void partition(List<List<Integer>> partitions) {
        for (int i = 0; i < partitions.size(); i++)
            for (int node : partitions.get(i))
                groups[node] = i;
    }
    void heal() { Arrays.fill(groups, 0); }
    boolean separated(int a, int b) { return groups[a] != groups[b]; }
    int typeIndex(String kind) {
        for (int i = 0; i < TYPES.length; i++)
            if (TYPES[i].equals(kind))
                return i;
        throw new IllegalArgumentException();
    }
    void count(Message message, int field, int amount) {
        total[field] += amount;
        byType[typeIndex(message.kind())][field] += amount;
        links[message.source()][message.destination()].stats[field] += amount;
    }
    void send(int time, int source, int destination, int term, String kind, Payload data) {
        Message message = new Message(kind, source, destination, term, data);
        serial++;
        count(message, 0, 1);
        Link link = links[source][destination];
        if (separated(source, destination)) {
            count(message, 3, 1);
            return;
        }
        for (Drop drop : link.drops)
            if ((drop.kind().equals(kind) || drop.kind().equals("ALL")) && drop.start() <= time &&
                time <= drop.end()) {
                count(message, 4, 1);
                return;
            }
        link.passed++;
        if (link.loss > 0 && link.passed % link.loss == 0) {
            count(message, 5, 1);
            return;
        }
        count(message, 2, 1);
        queue.add(new Scheduled(time + link.delay, source, serial, message));
    }
    List<Message> arrivals(int time) {
        List<Message> result = new ArrayList<>();
        while (!queue.isEmpty() && queue.peek().arrival() == time) {
            Message message = queue.remove().message();
            count(message, 2, -1);
            result.add(message);
        }
        return result;
    }
    boolean deliver(Message message, boolean up) {
        if (!up) {
            count(message, 6, 1);
            return false;
        }
        if (separated(message.source(), message.destination())) {
            count(message, 3, 1);
            return false;
        }
        count(message, 1, 1);
        return true;
    }
}
