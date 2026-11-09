import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.TreeMap;

public class Main {
    enum Command {
        GEN("NV", 2, 25), PCHECK("NV", 2, 25), HAMMING("NI", 2, 2), SIMPLEX("NI", 2, 2),
        REPETITION("NI", 2, 2), PARITY("NI", 2, 2), RM("NII", 3, 3), CYCLIC("NIV", 3, 3),
        DUAL("NA", 2, 2), EXTEND("NA", 2, 2), PUNCTURE("NAI", 3, 3), SHORTEN("NAI", 3, 3),
        AUGMENT("NA", 2, 2), EXPURGATE("NA", 2, 2), PERMUTE("NAI", 3, 26),
        DIRECTSUM("NAB", 3, 3), UUV("NAB", 3, 3), PRODUCT("NAB", 3, 3),
        LIST("", 0, 0), DELETE("A", 1, 1), SHOW("A", 1, 1), INFO("A", 1, 1),
        SYSTEMATIC("A", 1, 1), WEIGHTS("A", 1, 1), COVERING("A", 1, 1), BURST("A", 1, 1),
        TRELLIS("A", 1, 1), STDARRAY("A", 1, 1), EQUAL("AB", 2, 2), ENCODE("AV", 2, 2),
        SYNDROME("AV", 2, 2), DECODE("AV", 2, 2), BOUNDED("AIV", 3, 3), COSET("AV", 2, 2),
        ERASURE("AX", 2, 2), INTERLEAVE("AIIV", 4, 11), CRC("VV", 2, 2), CRCCHECK("VV", 2, 2),
        FACTOR("I", 1, 1), MACWILLIAMS("II", 2, 26), BOUNDS("II", 2, 2);

        final String types;
        final int minimum, maximum;
        Command(String types, int minimum, int maximum) {
            this.types = types; this.minimum = minimum; this.maximum = maximum;
        }
        boolean defining() { return ordinal() <= PRODUCT.ordinal(); }
    }

    static final class CommandError extends RuntimeException {
        CommandError(String message) { super(message); }
    }

    record Division(int quotient, int remainder) {}
    record Echelon(List<Integer> rows, List<Integer> columns) {}
    record Decoded(int word, int message, int error) {}

    static void require(boolean condition, String message) {
        if (!condition) throw new CommandError(message);
    }

    static boolean letter(char c) { return c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z'; }
    static boolean digit(char c) { return c >= '0' && c <= '9'; }

    static boolean validWord(String text, char kind) {
        if (text.isEmpty()) return false;
        if (kind == 'N' || kind == 'A' || kind == 'B') {
            if (text.length() > 8 || !letter(text.charAt(0))) return false;
            for (char c : text.toCharArray()) if (!letter(c) && !digit(c)) return false;
        } else if (kind == 'I') {
            if (text.length() > 4 || text.length() > 1 && text.charAt(0) == '0') return false;
            for (char c : text.toCharArray()) if (!digit(c)) return false;
        } else {
            if (text.length() > 30) return false;
            for (char c : text.toCharArray()) if (c != '0' && c != '1' && !(kind == 'X' && c == '?')) return false;
        }
        return true;
    }

    static int number(String text) { return Integer.parseInt(text); }
    static int parseBits(String text) { return Integer.parseInt(text, 2); }
    static int mask(int n) { return (1 << n) - 1; }
    static int bit(int n, int column) { return 1 << (n - column - 1); }
    static int weight(int value) { return Integer.bitCount(value); }
    static int length(int value) { return Integer.SIZE - Integer.numberOfLeadingZeros(value); }
    static String bits(int value, int n) {
        String text = Integer.toBinaryString(value);
        return "0".repeat(n - text.length()) + text;
    }
    static String yes(boolean value) { return value ? "yes" : "no"; }
    static String format(String pattern, Object... args) { return String.format(Locale.ROOT, pattern, args); }
    static String line(String pattern, Object... args) { return format(pattern, args) + "\n"; }
    static void line(StringBuilder out, String pattern, Object... args) { out.append(line(pattern, args)); }

    static Division divide(int value, int divisor) {
        int quotient = 0;
        while (value != 0 && length(value) >= length(divisor)) {
            int shift = length(value) - length(divisor);
            quotient ^= 1 << shift;
            value ^= divisor << shift;
        }
        return new Division(quotient, value);
    }

    static List<Integer> basis(List<Integer> rows, int n) {
        int[] pivots = new int[32];
        List<Integer> result = new ArrayList<>();
        for (int original : rows) {
            int row = original;
            for (int column = n - 1; column >= 0; --column) {
                if ((row & (1 << column)) == 0) continue;
                if (pivots[column] != 0) row ^= pivots[column];
                else { pivots[column] = row; result.add(original); break; }
            }
        }
        return result;
    }

    static Echelon rref(List<Integer> source, int n) {
        List<Integer> rows = new ArrayList<>(source), columns = new ArrayList<>();
        for (int column = 0; column < n; ++column) {
            int rank = columns.size(), found = rank;
            while (found < rows.size() && (rows.get(found) & bit(n, column)) == 0) ++found;
            if (found == rows.size()) continue;
            int temporary = rows.get(rank);
            rows.set(rank, rows.get(found)); rows.set(found, temporary);
            for (int i = 0; i < rows.size(); ++i)
                if (i != rank && (rows.get(i) & bit(n, column)) != 0) rows.set(i, rows.get(i) ^ rows.get(rank));
            columns.add(column);
        }
        return new Echelon(List.copyOf(rows.subList(0, columns.size())), List.copyOf(columns));
    }

    static List<Integer> nullSpace(List<Integer> source, int n) {
        Echelon reduced = rref(source, n);
        List<Integer> result = new ArrayList<>();
        for (int column = 0; column < n; ++column) {
            if (reduced.columns.contains(column)) continue;
            int row = bit(n, column);
            for (int i = 0; i < reduced.rows.size(); ++i)
                if ((reduced.rows.get(i) & bit(n, column)) != 0) row |= bit(n, reduced.columns.get(i));
            result.add(row);
        }
        return result;
    }

    static List<Integer> span(List<Integer> rows) {
        List<Integer> words = new ArrayList<>(List.of(0));
        for (int row : rows) {
            int count = words.size();
            for (int i = 0; i < count; ++i) words.add(words.get(i) ^ row);
        }
        return words;
    }

    static List<Integer> reedMuller(int r, int m) {
        if (r == 0) return List.of(mask(1 << m));
        int half = 1 << (m - 1);
        List<Integer> result = new ArrayList<>();
        for (int row : reedMuller(Math.min(r, m - 1), m - 1)) result.add((row << half) | row);
        result.addAll(reedMuller(r - 1, m - 1));
        return result;
    }

    static void checkDimension(int n, int k) {
        require(k >= 1 && k <= 12 && n - k >= 1 && n - k <= 12, format("bad dimension %d %d", n, k));
    }

    record Code(int n, List<Integer> g, List<Integer> h, Integer polynomial) {
        Code {
            checkDimension(n, g.size());
            g = List.copyOf(g);
            h = List.copyOf(h == null ? nullSpace(g, n) : h);
        }
        int k() { return g.size(); }
        String encoder() { return polynomial == null ? "matrix" : "polynomial"; }
        int encode(int message) {
            if (polynomial != null) {
                int shifted = message << h.size();
                return shifted | divide(shifted, polynomial).remainder;
            }
            int word = 0;
            for (int i = 0; i < k(); ++i) if ((message & bit(k(), i)) != 0) word ^= g.get(i);
            return word;
        }
        int syndrome(int word) {
            int result = 0;
            for (int row : h) result = (result << 1) | (weight(row & word) & 1);
            return result;
        }
        int message(int word) {
            for (int message = 0; message < (1 << k()); ++message) if (encode(message) == word) return message;
            throw new IllegalStateException("Word outside code");
        }
        int[] leaders() {
            int[] result = new int[1 << h.size()];
            Arrays.fill(result, -1); result[0] = 0;
            int found = 1;
            for (int w = 1; w <= n; ++w) {
                for (int word = mask(w); word < (1 << n);) {
                    int syndrome = syndrome(word);
                    if (result[syndrome] == -1) {
                        result[syndrome] = word;
                        if (++found == result.length) return result;
                    }
                    int lowest = word & -word, next = word + lowest;
                    word = next | (((next ^ word) >> 2) / lowest);
                }
            }
            return result;
        }
        Decoded decode(int received, int[] leaders) {
            int error = leaders[syndrome(received)], word = received ^ error;
            return new Decoded(word, message(word), error);
        }
        String decodedText(Decoded decoded) {
            return format("codeword %s message %s error %s weight %d", bits(decoded.word, n),
                bits(decoded.message, k()), bits(decoded.error, n), weight(decoded.error));
        }
        int burstCorrection() {
            boolean[] seen = new boolean[1 << h.size()]; seen[0] = true;
            for (int size = 1; size <= n; ++size) {
                int variants = size == 1 ? 1 : 1 << (size - 2);
                for (int offset = 0; offset <= n - size; ++offset) for (int middle = 0; middle < variants; ++middle) {
                    int word = size == 1 ? 1 : (1 << (size - 1)) | (middle << 1) | 1;
                    int syndrome = syndrome(word << offset);
                    if (seen[syndrome]) return size - 1;
                    seen[syndrome] = true;
                }
            }
            throw new IllegalStateException("No colliding burst");
        }
    }

    static Code construct(Command command, String[] args, Code a, Code b) {
        int n;
        List<Integer> g = new ArrayList<>(), h = null;
        Integer polynomial = null;
        switch (command) {
            case GEN, PCHECK -> {
                n = args[1].length();
                for (int i = 1; i < args.length; ++i) {
                    require(args[i].length() == n, "bad length");
                    g.add(parseBits(args[i]));
                }
                g = basis(g, n);
                if (command == Command.PCHECK) { h = g; g = nullSpace(h, n); }
            }
            case HAMMING, SIMPLEX -> {
                int r = number(args[1]); require(r >= 2 && r <= 4, "bad parameter");
                n = (1 << r) - 1;
                for (int i = 0; i < r; ++i) {
                    int row = 0;
                    for (int j = 1; j <= n; ++j) row = (row << 1) | ((j >> (r - i - 1)) & 1);
                    g.add(row);
                }
                if (command == Command.HAMMING) { h = g; g = nullSpace(h, n); }
            }
            case REPETITION, PARITY -> {
                n = number(args[1]); require(n >= 2 && n <= 24, "bad parameter");
                if (command == Command.REPETITION) g.add(mask(n));
                else for (int i = 0; i < n - 1; ++i) g.add(bit(n, i) | 1);
            }
            case RM -> {
                int r = number(args[1]), m = number(args[2]);
                require(m >= 1 && m <= 4 && r <= m, "bad parameter");
                n = 1 << m; g = reedMuller(r, m);
            }
            case CYCLIC -> {
                n = number(args[1]); int d = args[2].length() - 1;
                require(n >= 2 && n <= 24 && args[2].charAt(0) == '1' && d >= 1 && d < n, "bad parameter");
                int divisor = parseBits(args[2]);
                require(divide((1 << n) | 1, divisor).remainder == 0, "not a divisor");
                int k = n - d;
                for (int i = 0; i < k; ++i) g.add(divisor << (k - i - 1));
                h = new ArrayList<>();
                for (int i = 0; i < d; ++i) h.add(0);
                for (int j = 0; j < n; ++j) {
                    int remainder = divide(bit(n, j), divisor).remainder;
                    for (int i = 0; i < d; ++i) h.set(i, (h.get(i) << 1) | ((remainder >> (d - i - 1)) & 1));
                }
                polynomial = divisor;
            }
            case DUAL -> { n = a.n; g = a.h; h = a.g; }
            case EXTEND -> {
                n = a.n + 1;
                for (int row : a.g) g.add((row << 1) | (weight(row) & 1));
            }
            case PUNCTURE, SHORTEN, EXPURGATE -> {
                boolean expurgating = command == Command.EXPURGATE;
                int position = expurgating ? 0 : number(args[2]);
                if (!expurgating) require(position >= 1 && position <= a.n, "bad position");
                n = a.n - (expurgating ? 0 : 1);
                int removed = -1;
                if (command != Command.PUNCTURE) for (int i = 0; i < a.k(); ++i) {
                    boolean selected = expurgating ? (weight(a.g.get(i)) & 1) != 0 : (a.g.get(i) & bit(a.n, position - 1)) != 0;
                    if (selected) { removed = i; break; }
                }
                for (int i = 0; i < a.k(); ++i) {
                    if (i == removed) continue;
                    int row = a.g.get(i);
                    if (removed >= 0 && (expurgating ? (weight(row) & 1) != 0 : (row & bit(a.n, position - 1)) != 0)) row ^= a.g.get(removed);
                    if (!expurgating) { int low = a.n - position; row = ((row >> (low + 1)) << low) | (row & mask(low)); }
                    g.add(row);
                }
                if (command == Command.PUNCTURE) g = basis(g, n);
            }
            case AUGMENT -> {
                n = a.n; g.addAll(a.g); g.add(mask(n)); g = basis(g, n);
            }
            case PERMUTE -> {
                n = a.n; require(args.length - 2 == n, "bad permutation");
                boolean[] used = new boolean[n + 1];
                for (int i = 2; i < args.length; ++i) {
                    int position = number(args[i]);
                    require(position >= 1 && position <= n && !used[position], "bad permutation");
                    used[position] = true;
                }
                for (int original : a.g) {
                    int row = 0;
                    for (int i = 2; i < args.length; ++i) row = (row << 1) | ((original & bit(n, number(args[i]) - 1)) != 0 ? 1 : 0);
                    g.add(row);
                }
            }
            case DIRECTSUM, UUV, PRODUCT -> {
                if (command == Command.UUV) require(a.n == b.n, "bad length");
                n = command == Command.PRODUCT ? a.n * b.n : a.n + b.n;
                checkDimension(n, command == Command.PRODUCT ? a.k() * b.k() : a.k() + b.k());
                if (command == Command.PRODUCT) {
                    for (int x : a.g) for (int y : b.g) {
                        int row = 0;
                        for (int i = 0; i < a.n; ++i) row = (row << b.n) | ((x & bit(a.n, i)) != 0 ? y : 0);
                        g.add(row);
                    }
                } else {
                    for (int row : a.g) g.add((row << b.n) | (command == Command.UUV ? row : 0));
                    g.addAll(b.g);
                }
            }
            default -> throw new IllegalStateException("Not a defining command");
        }
        return new Code(n, g, h, polynomial);
    }

    static int[] distribution(Iterable<Integer> words, int offset, int n) {
        int[] counts = new int[n + 1];
        for (int word : words) ++counts[weight(word ^ offset)];
        return counts;
    }

    static String weightList(int[] counts) {
        List<String> items = new ArrayList<>();
        for (int i = 0; i < counts.length; ++i) if (counts[i] != 0) items.add(i + ":" + counts[i]);
        return String.join(" ", items);
    }

    static long gcd(long a, long b) {
        a = Math.abs(a);
        while (b != 0) { long remainder = a % b; a = b; b = remainder; }
        return a;
    }

    static final long[][] COMBINATIONS = new long[25][25];
    static {
        for (int n = 0; n <= 24; ++n) {
            COMBINATIONS[n][0] = COMBINATIONS[n][n] = 1;
            for (int k = 1; k < n; ++k) COMBINATIONS[n][k] = COMBINATIONS[n - 1][k - 1] + COMBINATIONS[n - 1][k];
        }
    }
    static long choose(int n, int k) { return k < 0 || k > n ? 0 : COMBINATIONS[n][k]; }
    static long volume(int n, int radius) {
        long sum = 0;
        for (int i = 0; i <= radius; ++i) sum += choose(n, i);
        return sum;
    }
    static long krawtchouk(int n, int j, int x) {
        long sum = 0;
        for (int y = 0; y <= j; ++y) {
            long term = choose(x, y) * choose(n - x, j - y);
            sum += y % 2 == 0 ? term : -term;
        }
        return sum;
    }

    static void matrixText(StringBuilder out, String label, List<Integer> rows, int n) {
        for (int row : rows) line(out, "%s %s", label, bits(row, n));
    }

    static String systematic(String name, Code code) {
        List<Integer> rows = new ArrayList<>(code.g);
        int[] permutation = new int[code.n];
        for (int i = 0; i < code.n; ++i) permutation[i] = i + 1;
        for (int r = 0; r < code.k(); ++r) {
            int column = r, found;
            while (true) {
                found = r;
                while (found < rows.size() && (rows.get(found) & bit(code.n, column)) == 0) ++found;
                if (found < rows.size()) break;
                ++column;
            }
            if (column != r) {
                int left = bit(code.n, r), right = bit(code.n, column);
                for (int i = 0; i < rows.size(); ++i)
                    if (((rows.get(i) & left) != 0) != ((rows.get(i) & right) != 0)) rows.set(i, rows.get(i) ^ left ^ right);
                int temporary = permutation[r]; permutation[r] = permutation[column]; permutation[column] = temporary;
            }
            int temporary = rows.get(r); rows.set(r, rows.get(found)); rows.set(found, temporary);
            for (int i = 0; i < rows.size(); ++i)
                if (i != r && (rows.get(i) & bit(code.n, r)) != 0) rows.set(i, rows.get(i) ^ rows.get(r));
        }
        StringBuilder out = new StringBuilder("systematic " + name + " perm");
        for (int column : permutation) out.append(' ').append(column);
        out.append('\n'); matrixText(out, "G", rows, code.n);
        for (int j = 0; j < code.h.size(); ++j) {
            int row = 0;
            for (int value : rows) row = (row << 1) | ((value & bit(code.n, code.k() + j)) != 0 ? 1 : 0);
            line(out, "H %s", bits((row << code.h.size()) | bit(code.h.size(), j), code.n));
        }
        return out.toString();
    }

    static String independent(Command command, String[] args) {
        if (command == Command.CRC || command == Command.CRCCHECK) {
            int d = args[0].length() - 1;
            require(args[0].charAt(0) == '1' && d >= 1 && d <= 16, "bad parameter");
            if (command == Command.CRC) require(args[1].length() + d <= 30, "bad length");
            int value = parseBits(args[1]);
            if (command == Command.CRC) value <<= d;
            int remainder = divide(value, parseBits(args[0])).remainder;
            String suffix = bits(remainder, d);
            return command == Command.CRC ? line("crc remainder %s frame %s%s", suffix, args[1], suffix)
                : line("crccheck %s remainder %s", remainder == 0 ? "ok" : "error", suffix);
        }
        int n = number(args[0]);
        if (command == Command.BOUNDS) {
            int d = number(args[1]); require(d >= 1 && d <= n && n <= 24, "bad parameter");
            long volume = volume(n, (d - 1) / 2), sum = 0;
            int hamming = 0, griesmer = 0;
            for (int k = 0; k <= n; ++k) if ((1L << k) * volume <= (1L << n)) hamming = k;
            for (int k = 1; k <= n; ++k) {
                long denominator = 1L << (k - 1);
                sum += (d + denominator - 1) / denominator;
                if (sum <= n) griesmer = k;
            }
            return line("bounds n %d d %d singleton %d hamming %d griesmer %d", n, d, n - d + 1, hamming, griesmer);
        }
        require(n >= 1 && n <= 24, "bad parameter");
        StringBuilder out = new StringBuilder();
        if (command == Command.FACTOR) {
            int remaining = (1 << n) | 1, divisors = 1;
            out.append("factor ").append(n);
            for (int factor = 3; 2 * (length(factor) - 1) <= length(remaining) - 1; factor += 2) {
                int exponent = 0;
                while (true) {
                    Division result = divide(remaining, factor);
                    if (result.remainder != 0) break;
                    remaining = result.quotient; ++exponent;
                }
                if (exponent != 0) { out.append(' ').append(bits(factor, length(factor))).append('^').append(exponent); divisors *= exponent + 1; }
            }
            if (remaining != 1) { out.append(' ').append(bits(remaining, length(remaining))).append("^1"); divisors *= 2; }
            line(out, " divisors %d", divisors);
            return out.toString();
        }
        require(args.length == n + 2, "bad length"); require(number(args[1]) == 1, "bad parameter");
        long size = 0;
        for (int i = 1; i < args.length; ++i) size += number(args[i]);
        boolean feasible = (size & (size - 1)) == 0;
        line(out, "macwilliams n %d size %d", n, size); out.append("dual");
        for (int j = 0; j <= n; ++j) {
            long numerator = 0;
            for (int x = 0; x <= n; ++x) numerator += number(args[x + 1]) * krawtchouk(n, j, x);
            if (numerator < 0 || numerator % size != 0) feasible = false;
            long divisor = gcd(numerator, size), denominator = size / divisor;
            out.append(' ').append(numerator / divisor);
            if (denominator != 1) out.append('/').append(denominator);
        }
        out.append('\n'); line(out, "feasible %s", yes(feasible));
        return out.toString();
    }

    static final class Laboratory {
        final TreeMap<String, Code> codes = new TreeMap<>();

        String process(String input) {
            String[] words = input.split(" "), args = Arrays.copyOfRange(words, 1, words.length);
            Command command;
            try { command = Command.valueOf(words[0]); }
            catch (IllegalArgumentException error) { throw new CommandError("unknown command " + words[0]); }
            require(args.length >= command.minimum && args.length <= command.maximum, "bad arguments");
            for (int i = 0; i < args.length; ++i)
                require(validWord(args[i], command.types.charAt(Math.min(i, command.types.length() - 1))), "bad arguments");
            Code a = null, b = null;
            for (int i = 0; i < command.types.length(); ++i) {
                char kind = command.types.charAt(i);
                if (kind != 'A' && kind != 'B') continue;
                Code code = codes.get(args[i]); require(code != null, "no code " + args[i]);
                if (kind == 'A') a = code; else b = code;
            }
            if (command.defining()) {
                Code code = construct(command, args, a, b);
                String status = codes.containsKey(args[0]) ? "redefined" : "defined";
                codes.put(args[0], code);
                return line("%s %s n %d k %d", status, args[0], code.n, code.k());
            }
            switch (command) {
                case CRC, CRCCHECK, FACTOR, MACWILLIAMS, BOUNDS -> { return independent(command, args); }
                default -> { }
            }
            StringBuilder out = new StringBuilder();
            if (command == Command.LIST) {
                line(out, "codes %d", codes.size());
                for (var entry : codes.entrySet()) {
                    Code code = entry.getValue();
                    line(out, "%s n %d k %d encoder %s", entry.getKey(), code.n, code.k(), code.encoder());
                }
                return out.toString();
            }
            String name = args[0];
            if (command == Command.DELETE) { codes.remove(name); return line("deleted %s", name); }
            int n = a.n, k = a.k();
            switch (command) {
                case SHOW -> {
                    line(out, "code %s n %d k %d encoder %s", name, n, k, a.encoder());
                    if (a.polynomial != null) line(out, "poly g %s h %s", bits(a.polynomial, n - k + 1), bits(divide((1 << n) | 1, a.polynomial).quotient, k + 1));
                    matrixText(out, "G", a.g, n); matrixText(out, "H", a.h, n);
                }
                case INFO -> {
                    List<Integer> codewords = span(a.g);
                    int distance = n, generator = Integer.MAX_VALUE;
                    for (int word : codewords.subList(1, codewords.size())) { distance = Math.min(distance, weight(word)); generator = Math.min(generator, word); }
                    int t = (distance - 1) / 2; long divisor = gcd(k, n);
                    boolean cyclic = true;
                    for (int row : a.g) if (a.syndrome(((row << 1) & mask(n)) | (row >> (n - 1))) != 0) cyclic = false;
                    line(out, "info %s n %d k %d rate %d/%d d %d t %d perfect %s mds %s cyclic %s", name, n, k,
                        k / divisor, n / divisor, distance, t, yes(volume(n, t) == (1L << (n - k))), yes(distance == n - k + 1),
                        cyclic ? bits(generator, length(generator)) : "no");
                }
                case SYSTEMATIC -> { return systematic(name, a); }
                case WEIGHTS -> {
                    int[] primary = distribution(span(a.g), 0, n), dual = distribution(span(a.h), 0, n);
                    boolean orthogonal = true;
                    for (int x : a.g) for (int y : a.g) if ((weight(x & y) & 1) != 0) orthogonal = false;
                    line(out, "weights %s %s", name, weightList(primary)); line(out, "dual %s %s", name, weightList(dual));
                    line(out, "duality %s self-orthogonal %s self-dual %s formally-self-dual %s", name,
                        yes(orthogonal), yes(orthogonal && n == 2 * k), yes(Arrays.equals(primary, dual)));
                }
                case COVERING -> {
                    int[] counts = new int[n + 1];
                    for (int leader : a.leaders()) ++counts[weight(leader)];
                    int radius = n; while (counts[radius] == 0) --radius;
                    out.append(format("covering %s radius %d leaders", name, radius));
                    for (int i = 0; i <= radius; ++i) out.append(' ').append(i).append(':').append(counts[i]);
                    out.append('\n');
                }
                case BURST -> {
                    int detect = n;
                    for (int word : span(a.g)) if (word != 0) detect = Math.min(detect, length(word) - Integer.numberOfTrailingZeros(word) - 1);
                    line(out, "burst %s detect %d correct %d", name, detect, a.burstCorrection());
                }
                case TRELLIS -> {
                    out.append("trellis ").append(name).append(" profile"); int maximum = 0;
                    for (int cut = 0; cut <= n; ++cut) {
                        List<Integer> prefix = new ArrayList<>(), suffix = new ArrayList<>();
                        for (int row : a.g) { prefix.add(row >> (n - cut)); suffix.add(row & mask(n - cut)); }
                        int states = basis(prefix, cut).size() + basis(suffix, n - cut).size() - k;
                        maximum = Math.max(maximum, states); out.append(' ').append(states);
                    }
                    line(out, " max %d", maximum);
                }
                case STDARRAY -> {
                    require(n - k <= 6 && k <= 4, "too large");
                    int[] leaders = a.leaders();
                    List<Integer> syndromes = new ArrayList<>(), codewords = span(a.g);
                    for (int i = 0; i < leaders.length; ++i) syndromes.add(i);
                    syndromes.sort(Comparator.comparingInt((Integer s) -> weight(leaders[s])).thenComparingInt(s -> leaders[s]));
                    codewords.sort(Comparator.naturalOrder());
                    line(out, "stdarray %s rows %d columns %d", name, leaders.length, codewords.size());
                    for (int s : syndromes) {
                        out.append(bits(s, n - k)).append(':');
                        for (int word : codewords) out.append(' ').append(bits(leaders[s] ^ word, n));
                        out.append('\n');
                    }
                }
                case EQUAL -> {
                    if (n != b.n) line(out, "equal %s %s no lengths %d %d", name, args[1], n, b.n);
                    else {
                        List<Integer> rows = new ArrayList<>(a.g); rows.addAll(b.g);
                        int common = k + b.k() - basis(rows, n).size();
                        line(out, "equal %s %s %s intersection %d", name, args[1], yes(k == common && b.k() == common), common);
                    }
                }
                case ENCODE -> {
                    require(args[1].length() == k, "bad length");
                    line(out, "encode %s message %s codeword %s", name, args[1], bits(a.encode(parseBits(args[1])), n));
                }
                case SYNDROME, DECODE, BOUNDED, COSET -> {
                    String text = args[command == Command.BOUNDED ? 2 : 1]; require(text.length() == n, "bad length");
                    int word = parseBits(text), syndrome = a.syndrome(word);
                    if (command == Command.SYNDROME) line(out, "syndrome %s %s codeword %s", name, bits(syndrome, n - k), yes(syndrome == 0));
                    else {
                        Decoded decoded = a.decode(word, a.leaders());
                        if (command == Command.COSET) line(out, "coset %s syndrome %s leader %s weights %s", name,
                            bits(syndrome, n - k), bits(decoded.error, n), weightList(distribution(span(a.g), word, n)));
                        else if (command == Command.BOUNDED && weight(decoded.error) > number(args[1])) line(out, "bounded %s fail weight %d", name, weight(decoded.error));
                        else line(out, "%s %s %s", command == Command.BOUNDED ? "bounded" : "decode", name, a.decodedText(decoded));
                    }
                }
                case ERASURE -> {
                    require(args[1].length() == n, "bad length");
                    int known = 0, value = 0, erased = 0, candidates = 0, candidate = 0;
                    for (int i = 0; i < n; ++i) {
                        char c = args[1].charAt(i);
                        if (c == '?') ++erased; else { known |= bit(n, i); if (c == '1') value |= bit(n, i); }
                    }
                    for (int word : span(a.g)) if ((word & known) == value) { candidate = word; ++candidates; }
                    out.append(format("erasure %s erased %d candidates %d", name, erased, candidates));
                    if (candidates == 1) out.append(format(" codeword %s message %s", bits(candidate, n), bits(a.message(candidate), k)));
                    out.append('\n');
                }
                case INTERLEAVE -> {
                    int depth = args.length - 3, start = number(args[1]), size = number(args[2]);
                    for (int i = 3; i < args.length; ++i) require(args[i].length() == k, "bad length");
                    require(start >= 1 && size >= 1 && start + size - 1 <= depth * n, "bad burst");
                    int[] sentRows = new int[depth], receivedRows = new int[depth];
                    for (int i = 0; i < depth; ++i) sentRows[i] = a.encode(parseBits(args[i + 3]));
                    StringBuilder sent = new StringBuilder(), received = new StringBuilder();
                    for (int column = 0; column < n; ++column) for (int i = 0; i < depth; ++i) {
                        int position = column * depth + i + 1;
                        boolean value = (sentRows[i] & bit(n, column)) != 0;
                        sent.append(value ? '1' : '0');
                        if (position >= start && position < start + size) value = !value;
                        received.append(value ? '1' : '0'); receivedRows[i] = (receivedRows[i] << 1) | (value ? 1 : 0);
                    }
                    line(out, "interleave %s depth %d burst %d %d", name, depth, start, size);
                    line(out, "sent %s", sent); line(out, "recv %s", received);
                    int[] leaders = a.leaders(); int correct = 0;
                    for (int i = 0; i < depth; ++i) {
                        Decoded decoded = a.decode(receivedRows[i], leaders);
                        boolean ok = decoded.message == parseBits(args[i + 3]); if (ok) ++correct;
                        line(out, "row %d errors %d corrected %d message %s %s", i + 1, weight(receivedRows[i] ^ sentRows[i]),
                            weight(decoded.error), bits(decoded.message, k), ok ? "ok" : "wrong");
                    }
                    line(out, "result ok %d wrong %d", correct, depth - correct);
                }
                default -> throw new IllegalStateException("Unhandled command");
            }
            return out.toString();
        }
    }

    public static void main(String[] args) throws Exception {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in));
        BufferedWriter output = new BufferedWriter(new OutputStreamWriter(System.out));
        int count = Integer.parseInt(input.readLine());
        Laboratory laboratory = new Laboratory();
        for (int i = 0; i < count; ++i) {
            try { output.write(laboratory.process(input.readLine())); }
            catch (CommandError error) { output.write("error: " + error.getMessage() + "\n"); }
        }
        output.flush();
    }
}
