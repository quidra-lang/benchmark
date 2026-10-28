import java.nio.file.*;
import java.util.*;

final class Processes {
    record Action(String kind, String argument, String value) {}
    record Scheduled(int first, int period, Action action) {}
    record Rule(String tag, Action action) {}
    record Planned(int time, int process, Action action) {}
    static final class State {
        int index, initial, balance, lamport, incoming, outgoing, refused, minimum, maxHeld;
        int[] vector, broadcast, next, counts = new int[5];
        List<Scheduled> scheduled = new ArrayList<>();
        List<Rule> rules = new ArrayList<>();
        List<Main.Event> events = new ArrayList<>();
        List<Main.Packet> hold = new ArrayList<>(), delivered = new ArrayList<>();
        List<Map<Integer, Main.Packet>> reorder = new ArrayList<>();
        State(int index, int initial, int size) {
            this.index = index;
            this.initial = initial;
            balance = initial;
            minimum = initial;
            vector = new int[size];
            broadcast = new int[size];
            next = new int[size];
            Arrays.fill(next, 1);
            for (int i = 0; i < size; i++)
                reorder.add(new HashMap<>());
        }
        int held() {
            int total = hold.size();
            for (Map<Integer, Main.Packet> buffer : reorder)
                total += buffer.size();
            return total;
        }
        int balanceAt(int count) {
            return count == 0 ? initial : events.get(count - 1).balance;
        }
    }
    static Action action(String[] w, int start) {
        return new Action(w[start], w[start + 1], start + 2 < w.length ? w[start + 2] : "");
    }
    static List<State> read(List<String> names) throws Exception {
        List<State> result = new ArrayList<>();
        State current = null;
        for (String line : Files.readAllLines(Path.of("input/programs.txt"))) {
            String[] w = line.split(" ");
            switch (w[0]) {
            case "PROCESS" -> {
                current = new State(names.indexOf(w[1]), Integer.parseInt(w[3]), names.size());
                result.add(current);
            }
            case "AT" -> {
                boolean every = w[2].equals("EVERY");
                current.scheduled.add(new Scheduled(
                    Integer.parseInt(w[1]), every ? Integer.parseInt(w[3]) : 0, action(w, every ? 4 : 2)));
            }
            case "ON" -> current.rules.add(new Rule(w[1], action(w, 2)));
            }
        }
        return result;
    }
    static List<Planned> expand(List<State> states, int end) {
        List<Planned> result = new ArrayList<>();
        for (State p : states)
            for (Scheduled s : p.scheduled) {
                for (int time = s.first(); time <= end; time += s.period()) {
                    result.add(new Planned(time, p.index, s.action()));
                    if (s.period() == 0)
                        break;
                }
            }
        return result;
    }
}
