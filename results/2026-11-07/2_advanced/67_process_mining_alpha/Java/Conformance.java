import java.nio.file.*;
import java.util.*;
final class Conformance {
    static final class Net {
        List<String> places, transitions;
        Map<String, Integer> placeIndex = new HashMap<>(), transitionIndex = new HashMap<>();
        List<TreeSet<Integer>> inputs = new ArrayList<>(), outputs = new ArrayList<>();
        int initial, finish;
        Net(List<String> places, List<String> transitions, int initial, int finish) {
            this.places = new ArrayList<>(places);
            this.transitions = new ArrayList<>(transitions);
            this.transitions.sort(String::compareTo);
            this.initial = initial;
            this.finish = finish;
            for (int p = 0; p < places.size(); p++)
                placeIndex.put(places.get(p), p);
            for (int t = 0; t < this.transitions.size(); t++) {
                transitionIndex.put(this.transitions.get(t), t);
                inputs.add(new TreeSet<>());
                outputs.add(new TreeSet<>());
            }
        }
        void arc(String from, String to) {
            if (placeIndex.containsKey(from))
                inputs.get(transitionIndex.get(to)).add(placeIndex.get(from));
            else
                outputs.get(transitionIndex.get(from)).add(placeIndex.get(to));
        }
        int arcs() {
            int count = 0;
            for (int t = 0; t < transitions.size(); t++)
                count += inputs.get(t).size() + outputs.get(t).size();
            return count;
        }
        int[] initialMarking() {
            int[] result = new int[places.size()];
            result[initial] = 1;
            return result;
        }
        int[] finalMarking() {
            int[] result = new int[places.size()];
            result[finish] = 1;
            return result;
        }
    }
    static final class Totals {
        long missing, remaining, consumed, produced, skipped;
        long[] placeMissing, placeRemaining, deviating, waitingCount, waitingSum, waitingMax;
        long[][] routes;
        Totals(int places, int transitions) {
            placeMissing = new long[places];
            placeRemaining = new long[places];
            deviating = new long[places];
            waitingCount = new long[places];
            waitingSum = new long[places];
            waitingMax = new long[places];
            routes = new long[places][transitions];
        }
        Report.Fraction fitness() {
            return new Report.Fraction((consumed - missing) * produced +
                                           (produced - remaining) * consumed,
                                       2 * consumed * produced);
        }
    }
    static boolean enabled(Net net, int[] marking, int transition) {
        for (int place : net.inputs.get(transition))
            if (marking[place] < 1)
                return false;
        return true;
    }
    static int[] fire(Net net, int[] marking, int transition) {
        int[] result = marking.clone();
        for (int place : net.inputs.get(transition))
            result[place]--;
        for (int place : net.outputs.get(transition))
            result[place]++;
        return result;
    }
    static Net read() throws Exception {
        List<String> places = new ArrayList<>(), transitions = new ArrayList<>();
        List<String[]> arcs = new ArrayList<>();
        String initial = "", finish = "";
        for (String line : Files.readAllLines(Path.of("input", "model.txt"))) {
            String[] w = line.split(" ");
            switch (w[0]) {
            case "PLACE" -> places.add(w[1]);
            case "TRANSITION" -> transitions.add(w[1]);
            case "ARC" -> arcs.add(new String[] {w[1], w[2]});
            case "INITIAL" -> initial = w[1];
            case "FINAL" -> finish = w[1];
            }
        }
        Net net = new Net(places, transitions, places.indexOf(initial), places.indexOf(finish));
        for (String[] arc : arcs)
            net.arc(arc[0], arc[1]);
        return net;
    }
}
