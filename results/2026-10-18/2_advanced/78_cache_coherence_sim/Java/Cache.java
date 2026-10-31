import java.util.*;
final class Cache {
    static final class Line {
        int block;
        String state;
        Line(int block, String state) {
            this.block = block;
            this.state = state;
        }
    }
    record Location(int row, int way) {}
    int numberSets, ways, clock;
    String replacement;
    Line[][] entries;
    int[][] touched, bits;
    int[] fills, evictions;
    Cache(int sets, int ways, String replacement) {
        numberSets = sets;
        this.ways = ways;
        this.replacement = replacement;
        entries = new Line[sets][ways];
        touched = new int[sets][ways];
        bits = new int[sets][ways];
        fills = new int[sets];
        evictions = new int[sets];
    }
    Location locate(int block) {
        int row = block % numberSets;
        for (int way = 0; way < ways; way++)
            if (entries[row][way] != null && entries[row][way].block == block)
                return new Location(row, way);
        return null;
    }
    String state(int block) {
        Location p = locate(block);
        return p == null ? "I" : entries[p.row()][p.way()].state;
    }
    void change(int block, String state) {
        Location p = locate(block);
        if (p != null)
            entries[p.row()][p.way()].state = state;
    }
    void touchWay(int row, int way, boolean fill) {
        if (replacement.equals("LRU") || replacement.equals("FIFO") && fill)
            touched[row][way] = ++clock;
        else if (replacement.equals("PLRU")) {
            int low = 0, high = ways, node = 1;
            while (high - low > 1) {
                int mid = (low + high) / 2;
                if (way < mid) {
                    bits[row][node] = 1;
                    high = mid;
                    node *= 2;
                } else {
                    bits[row][node] = 0;
                    low = mid;
                    node = 2 * node + 1;
                }
            }
        }
    }
    void touch(int block) {
        Location p = locate(block);
        if (p != null)
            touchWay(p.row(), p.way(), false);
    }
    int victim(int row) {
        if (replacement.equals("PLRU")) {
            int low = 0, high = ways, node = 1;
            while (high - low > 1) {
                int mid = (low + high) / 2;
                if (bits[row][node] == 0) {
                    high = mid;
                    node *= 2;
                } else {
                    low = mid;
                    node = 2 * node + 1;
                }
            }
            return low;
        }
        int best = 0;
        for (int way = 1; way < ways; way++)
            if (touched[row][way] < touched[row][best])
                best = way;
        return best;
    }
    Line fill(int block, String state) {
        int row = block % numberSets, way = -1;
        for (int i = 0; i < ways; i++)
            if (entries[row][i] == null) {
                way = i;
                break;
            }
        if (way < 0)
            way = victim(row);
        Line old = entries[row][way];
        if (old != null)
            evictions[row]++;
        entries[row][way] = new Line(block, state);
        fills[row]++;
        touchWay(row, way, true);
        return old;
    }
    Line remove(int block) {
        Location p = locate(block);
        if (p == null)
            return null;
        Line old = entries[p.row()][p.way()];
        entries[p.row()][p.way()] = null;
        return old;
    }
    String order(int row) {
        if (replacement.equals("PLRU")) {
            if (ways == 1)
                return "-";
            StringBuilder text = new StringBuilder();
            for (int i = 1; i < ways; i++)
                text.append(bits[row][i]);
            return text.toString();
        }
        List<Integer> active = new ArrayList<>();
        for (int way = 0; way < ways; way++)
            if (entries[row][way] != null)
                active.add(way);
        active.sort(Comparator.<Integer>comparingInt(way -> touched[row][way])
                        .reversed()
                        .thenComparingInt(way -> way));
        List<String> text = new ArrayList<>();
        for (int way : active)
            text.add(Integer.toString(way));
        return text.isEmpty() ? "-" : String.join(" ", text);
    }
    List<Line> lines() {
        List<Line> result = new ArrayList<>();
        for (Line[] row : entries)
            for (Line line : row)
                if (line != null)
                    result.add(line);
        return result;
    }
}
