using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
public static class Conformance {
    public sealed class Net {
        public List<string> places, transitions;
        public Dictionary<string, int> placeIndex = new(), transitionIndex = new();
        public List<SortedSet<int>> inputs = new(), outputs = new();
        public int initial, finish;
        public Net(List<string> places, List<string> transitions, int initial, int finish) {
            this.places = new(places);
            this.transitions = new(transitions);
            this.transitions.Sort(StringComparer.Ordinal);
            this.initial = initial;
            this.finish = finish;
            for (int p = 0; p < places.Count; p++)
                placeIndex[places[p]] = p;
            for (int t = 0; t < this.transitions.Count; t++) {
                transitionIndex[this.transitions[t]] = t;
                inputs.Add(new());
                outputs.Add(new());
            }
        }
        public void Arc(string from, string to) {
            if (placeIndex.TryGetValue(from, out int place))
                inputs[transitionIndex[to]].Add(place);
            else
                outputs[transitionIndex[from]].Add(placeIndex[to]);
        }
        public int Arcs() => inputs.Sum(x => x.Count) + outputs.Sum(x => x.Count);
        public int[] InitialMarking() {
            int[] result = new int[places.Count];
            result[initial] = 1;
            return result;
        }
        public int[] FinalMarking() {
            int[] result = new int[places.Count];
            result[finish] = 1;
            return result;
        }
    }
    public sealed class Totals {
        public long missing, remaining, consumed, produced, skipped;
        public long[] placeMissing, placeRemaining, deviating, waitingCount, waitingSum, waitingMax;
        public long[][] routes;
        public Totals(int places, int transitions) {
            placeMissing = new long[places];
            placeRemaining = new long[places];
            deviating = new long[places];
            waitingCount = new long[places];
            waitingSum = new long[places];
            waitingMax = new long[places];
            routes = Enumerable.Range(0, places)
                         .Select(
                             _ => new long[transitions])
                         .ToArray();
        }
        public Report.Fraction Fitness() => new((consumed - missing) * produced +
                                                    (produced - remaining) * consumed,
                                                2 * consumed * produced);
    }
    public static bool Enabled(Net net, int[] marking, int transition) {
        foreach (int place in net.inputs[transition])
            if (marking[place] < 1)
                return false;
        return true;
    }
    public static int[] Fire(Net net, int[] marking, int transition) {
        int[] result = marking.ToArray();
        foreach (int place in net.inputs[transition])
            result[place]--;
        foreach (int place in net.outputs[transition])
            result[place]++;
        return result;
    }
    public static Net Read() {
        List<string> places = new(), transitions = new();
        List<string[]> arcs = new();
        string initial = "", finish = "";
        foreach (string line in File.ReadAllLines(Path.Combine("input", "model.txt"))) {
            string[] w = line.Split(' ');
            switch (w[0]) {
            case "PLACE":
                places.Add(w[1]);
                break;
            case "TRANSITION":
                transitions.Add(w[1]);
                break;
            case "ARC":
                arcs.Add(new string[] { w[1], w[2] });
                break;
            case "INITIAL":
                initial = w[1];
                break;
            case "FINAL":
                finish = w[1];
                break;
            }
        }
        Net net = new(places, transitions, places.IndexOf(initial), places.IndexOf(finish));
        foreach (string[] arc in arcs)
            net.Arc(arc[0], arc[1]);
        return net;
    }
}
