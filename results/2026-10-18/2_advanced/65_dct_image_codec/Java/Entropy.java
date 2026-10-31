import java.util.*;
final class Entropy {
    static final int[] CLASSES = {0, 1, 0, 1}, IDS = {0, 0, 1, 1};
    static final String[] NAMES = {"dc_luma", "ac_luma", "dc_chroma", "ac_chroma"};
    static int category(int value) {
        int n = 0;
        for (int a = Math.abs(value); a != 0; a >>= 1)
            n++;
        return n;
    }
    static int extra(int value) { return value >= 0 ? value : value + (1 << category(value)) - 1; }
    static int amplitude(int bits, int n) {
        return n == 0 ? 0 : bits >= (1 << (n - 1)) ? bits : bits - (1 << n) + 1;
    }
    static final class Table {
        final int[] counts, symbols, lengths = new int[256], codes = new int[256];
        final Map<Integer, Integer> decode = new HashMap<>();
        Table(int[] counts, int[] symbols) {
            this.counts = counts;
            this.symbols = symbols;
            int code = 0, offset = 0;
            for (int length = 1; length <= 16; length++) {
                for (int i = 0; i < counts[length - 1]; i++) {
                    int symbol = symbols[offset++];
                    lengths[symbol] = length;
                    codes[symbol] = code;
                    decode.put((length << 16) | code, symbol);
                    code++;
                }
                code *= 2;
            }
        }
    }
    static Table optimized(int[] input) {
        int[] frequencies = Arrays.copyOf(input, 257), sizes = new int[257], others = new int[257];
        frequencies[256] = 1;
        Arrays.fill(others, -1);
        while (true) {
            List<Integer> available = new ArrayList<>();
            for (int v = 0; v <= 256; v++)
                if (frequencies[v] > 0)
                    available.add(v);
            if (available.size() < 2)
                break;
            available.sort((a, b)
                               -> frequencies[a] != frequencies[b]
                                      ? Integer.compare(frequencies[a], frequencies[b])
                                      : Integer.compare(b, a));
            int first = available.get(0), second = available.get(1);
            frequencies[first] += frequencies[second];
            frequencies[second] = 0;
            sizes[first]++;
            while (others[first] != -1) {
                first = others[first];
                sizes[first]++;
            }
            others[first] = second;
            sizes[second]++;
            while (others[second] != -1) {
                second = others[second];
                sizes[second]++;
            }
        }
        int[] counts = new int[257];
        int maximum = 0;
        for (int length : sizes)
            if (length > 0) {
                counts[length]++;
                maximum = Math.max(maximum, length);
            }
        for (int length = maximum; length >= 17; length--)
            while (counts[length] > 0) {
                int j = length - 2;
                while (counts[j] == 0)
                    j--;
                counts[length] -= 2;
                counts[length - 1]++;
                counts[j + 1] += 2;
                counts[j]--;
            }
        int longest = 16;
        while (counts[longest] == 0)
            longest--;
        counts[longest]--;
        List<Integer> symbols = new ArrayList<>();
        for (int v = 0; v < 256; v++)
            if (sizes[v] > 0)
                symbols.add(v);
        symbols.sort((a, b)
                         -> sizes[a] != sizes[b] ? Integer.compare(sizes[a], sizes[b])
                                                 : Integer.compare(a, b));
        int[] values = new int[symbols.size()];
        for (int i = 0; i < values.length; i++)
            values[i] = symbols.get(i);
        return new Table(Arrays.copyOfRange(counts, 1, 17), values);
    }
}
