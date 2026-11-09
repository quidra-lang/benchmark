import java.util.*;

final class Associator {
    static final class Candidate {
        int number;
        Picker.Pick first;
        List<Picker.Pick> picks = new ArrayList<>(), dropped = new ArrayList<>();
        List<Locator.Run> passes = new ArrayList<>();
        Main.Event event;
        boolean rejected;
    }
    static List<Candidate> associate(List<Picker.Pick> picks, int window, int minimum) {
        List<Candidate> candidates = new ArrayList<>();
        for (int i = 0; i < picks.size(); i++) {
            Picker.Pick first = picks.get(i);
            if (first.assigned)
                continue;
            Set<Integer> seen = new HashSet<>();
            List<Picker.Pick> selected = new ArrayList<>();
            for (int j = i; j < picks.size(); j++) {
                Picker.Pick pick = picks.get(j);
                if (pick.sample > first.sample + window)
                    break;
                if (!pick.assigned && seen.add(pick.station.order))
                    selected.add(pick);
            }
            if (selected.size() < minimum)
                continue;
            Candidate candidate = new Candidate();
            candidate.number = candidates.size() + 1;
            candidate.first = first;
            candidate.picks = selected;
            for (Picker.Pick pick : selected)
                pick.assigned = true;
            candidates.add(candidate);
        }
        return candidates;
    }
}
