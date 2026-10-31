using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
public sealed class Cache {
    public sealed class Line {
        public int block;
        public string state;
        public Line(int block, string state) {
            this.block = block;
            this.state = state;
        }
    }
    public record Location(int row, int way);
    public int numberSets, ways, clock;
    public string replacement;
    public Line[][] entries;
    public int[][] touched, bits;
    public int[] fills, evictions;
    public Cache(int sets, int ways, string replacement) {
        numberSets = sets;
        this.ways = ways;
        this.replacement = replacement;
        entries = Enumerable.Range(0, sets)
                      .Select(
                          _ => new Line[ways])
                      .ToArray();
        touched = Enumerable.Range(0, sets)
                      .Select(
                          _ => new int[ways])
                      .ToArray();
        bits = Enumerable.Range(0, sets)
                   .Select(
                       _ => new int[ways])
                   .ToArray();
        fills = new int[sets];
        evictions = new int[sets];
    }
    public Location Locate(int block) {
        int row = block % numberSets;
        for (int way = 0; way < ways; way++)
            if (entries[row][way] != null && entries[row][way].block == block)
                return new(row, way);
        return null;
    }
    public string State(int block) {
        Location p = Locate(block);
        return p == null ? "I" : entries[p.row][p.way].state;
    }
    public void Change(int block, string state) {
        Location p = Locate(block);
        if (p != null)
            entries[p.row][p.way].state = state;
    }
    public void TouchWay(int row, int way, bool fill) {
        if (replacement == "LRU" || replacement == "FIFO" && fill)
            touched[row][way] = ++clock;
        else if (replacement == "PLRU") {
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
    public void Touch(int block) {
        Location p = Locate(block);
        if (p != null)
            TouchWay(p.row, p.way, false);
    }
    public int Victim(int row) {
        if (replacement == "PLRU") {
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
    public Line Fill(int block, string state) {
        int row = block % numberSets, way = -1;
        for (int i = 0; i < ways; i++)
            if (entries[row][i] == null) {
                way = i;
                break;
            }
        if (way < 0)
            way = Victim(row);
        Line old = entries[row][way];
        if (old != null)
            evictions[row]++;
        entries[row][way] = new(block, state);
        fills[row]++;
        TouchWay(row, way, true);
        return old;
    }
    public Line Remove(int block) {
        Location p = Locate(block);
        if (p == null)
            return null;
        Line old = entries[p.row][p.way];
        entries[p.row][p.way] = null;
        return old;
    }
    public string Order(int row) {
        if (replacement == "PLRU") {
            if (ways == 1)
                return "-";
            StringBuilder text = new();
            for (int i = 1; i < ways; i++)
                text.Append(bits[row][i]);
            return text.ToString();
        }
        List<int> active = Enumerable.Range(0, ways)
                               .Where(way => entries[row][way] != null)
                               .OrderByDescending(way => touched[row][way])
                               .ThenBy(way => way)
                               .ToList();
        return active.Count == 0 ? "-" : string.Join(" ", active);
    }
    public List<Line>
    Lines() => entries.SelectMany(row => row).Where(line => line != null).ToList();
}
