using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Associator {
    public sealed class Candidate {
        public int number;
        public Picker.Pick first;
        public List<Picker.Pick> picks = new(), dropped = new();
        public List<Locator.Run> passes = new();
        public Program.Event earthquake;
        public bool rejected;
    }
    public static List<Candidate> Associate(List<Picker.Pick> picks, int window, int minimum) {
        List<Candidate> candidates = new();
        for (int i = 0; i < picks.Count; i++) {
            Picker.Pick first = picks[i];
            if (first.assigned)
                continue;
            HashSet<int> seen = new();
            List<Picker.Pick> selected = new();
            for (int j = i; j < picks.Count; j++) {
                Picker.Pick pick = picks[j];
                if (pick.sample > first.sample + window)
                    break;
                if (!pick.assigned && seen.Add(pick.station.order))
                    selected.Add(pick);
            }
            if (selected.Count < minimum)
                continue;
            Candidate candidate = new Candidate();
            candidate.number = candidates.Count + 1;
            candidate.first = first;
            candidate.picks = selected;
            foreach (Picker.Pick pick in selected)
                pick.assigned = true;
            candidates.Add(candidate);
        }
        return candidates;
    }
}
