import java.util.*;

final class Resolver {
    record Period(long start, long offset, boolean dst, String abbreviation) {
        boolean sameState(Period other) { return offset == other.offset && dst == other.dst && abbreviation.equals(other.abbreviation); }
    }

    static final class Timeline {
        final List<Period> periods;
        Timeline(List<Period> periods) { this.periods = periods; }

        int indexAt(long time) {
            int low = 0, high = periods.size();
            while (low < high) { int middle = (low + high) / 2; if (periods.get(middle).start <= time) low = middle + 1; else high = middle; }
            return low - 1;
        }

        Period periodAt(long time) { return periods.get(indexAt(time)); }
        long endOf(int index) { return index + 1 < periods.size() ? periods.get(index + 1).start : DayRules.POS_INFINITY; }
        int nearbyFirst(long local) { return indexAt(local - 57600); }
        int nearbyLast(long local) { return indexAt(local + 57600); }

        List<Integer> candidates(long local) {
            List<Integer> found = new ArrayList<>();
            for (int index = nearbyFirst(local); index <= nearbyLast(local); index++) {
                Period period = periods.get(index);
                long time = local - period.offset;
                if (period.start <= time && time < endOf(index)) found.add(index);
            }
            return found;
        }

        int skippingTransition(long local) {
            for (int index = Math.max(1, nearbyFirst(local)); index <= nearbyLast(local); index++) {
                long start = periods.get(index).start;
                if (start + periods.get(index - 1).offset <= local && local < start + periods.get(index).offset) return index;
            }
            throw new IllegalStateException();
        }
    }
}
