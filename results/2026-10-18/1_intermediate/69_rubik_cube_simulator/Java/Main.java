import java.io.*;
import java.util.*;

public class Main {
    static final String FACES = "URFDLB", COLORS = "WRGYOB", LETTERS = "URFDLBMESurfdlbxyz";
    static final String[] CORNERS = {"URF", "UFL", "ULB", "UBR", "DFR", "DLF", "DBL", "DRB"};
    static final String[] EDGES = {"UR", "UF", "UL", "UB", "DR", "DF", "DL", "DB", "FR", "FL", "BL", "BR"};
    static final int[][] CORNER_STICKERS = {
        {8,9,20},{6,18,38},{0,36,47},{2,45,11},{29,26,15},{27,44,24},{33,53,42},{35,17,51}
    };
    static final int[][] EDGE_STICKERS = {
        {5,10},{7,19},{3,37},{1,46},{32,16},{28,25},{30,43},{34,52},{23,12},{21,41},{50,39},{48,14}
    };
    static final Set<String> NO_ARGS = Set.of("RESET", "SHOW", "STATE", "ISSOLVED", "HISTORY", "SOLUTION", "ANALYZE", "STAGE", "MACROS");
    static final Set<String> WORD = Set.of("CHECK", "LOAD", "UNDO", "REDO", "SEARCH", "WHERE", "SAVE", "RESTORE", "SCRAMBLE");
    static final Set<String> SEQUENCE = Set.of("APPLY", "INVERT", "SIMPLIFY", "METRICS", "ORDER", "CYCLES", "UNROTATE", "UNTIL");
    static final Set<String> HEAD = Set.of("DEFINE", "MIRROR", "ROTATE");
    record Move(char letter, int amount) {
        Move inverse() {
            return new Move(letter, 4 - amount);
        }
        public String toString() {
            return "" + letter + (amount == 1 ? "" : amount == 2 ? "2" : "'");
        }
    }
    record Save(char[] state, List<Move> history) {}
    record Pieces(int[] piece, int[] orientation) {}
    record Normalized(char[] state, List<Move> rotation) {}
    static class Problem extends RuntimeException {
        Problem(String reason) {
            super(reason);
        }
    }

    static final Map<Move, int[]> permutations = new HashMap<>();
    static final List<List<Move>> rotations = new ArrayList<>();
    static final Map<String, List<Move>> macros = new TreeMap<>();
    static final Map<String, Save> saves = new HashMap<>();
    static char[] state = solvedState();
    static final List<Move> history = new ArrayList<>(), redo = new ArrayList<>();
    static char[] solvedState() {
        char[] out = new char[54];
        for (int i = 0; i < 54; i++) out[i] = COLORS.charAt(i / 9);
        return out;
    }

    static int[] identity() {
        int[] p = new int[54];
        for (int i = 0; i < 54; i++) p[i] = i;
        return p;
    }

    static int[] compose(int[] first, int[] second) {
        int[] p = new int[54];
        for (int i = 0; i < 54; i++) p[i] = second[first[i]];
        return p;
    }

    static int[] inverse(int[] p) {
        int[] out = new int[54];
        for (int i = 0; i < 54; i++) out[p[i]] = i;
        return out;
    }

    static int axis(char letter) {
        return "RLMrlx".indexOf(letter) >= 0 ? 0 : "UDEudy".indexOf(letter) >= 0 ? 1 : 2;
    }

    static int[] rotate(int[] v, int axis) {
        return axis == 0 ? new int[]{v[0], -v[2], v[1]} : axis == 1 ? new int[]{v[2], v[1], -v[0]} : new int[]{-v[1], v[0], v[2]};
    }

    static void initialize() {
        int[][] positions = new int[54][], normals = new int[54][];
        int[][] faceNormals = {
            {0,1,0},{1,0,0},{0,0,1},{0,-1,0},{-1,0,0},{0,0,-1}
        };
        for (int face = 0; face < 6; face++) for (int row = 0; row < 3; row++) for (int col = 0; col < 3; col++) {
            int i = face * 9 + row * 3 + col;
            positions[i] = switch (face) {
                case 0 -> new int[]{col-1,1,row-1};
                case 1 -> new int[]{1,1-row,1-col};
                case 2 -> new int[]{col-1,1-row,1};
                case 3 -> new int[]{col-1,-1,1-row};
                case 4 -> new int[]{-1,1-row,col-1};
                default -> new int[]{1-col,1-row,-1};
            };
            normals[i] = faceNormals[face];
        }
        for (char letter : LETTERS.toCharArray()) {
            int ax = axis(letter), direction = "URFSurfxyz".indexOf(letter) >= 0 ? -1 : 1;
            boolean all = "xyz".indexOf(letter) >= 0, wide = "urfdlb".indexOf(letter) >= 0;
            int layer = "MES".indexOf(letter) >= 0 ? 0 : "URFurf".indexOf(letter) >= 0 ? 1 : -1;
            int[] p = identity();
            for (int i = 0; i < 54; i++) {
                if (!(all || (wide ? positions[i][ax] * layer >= 0 : positions[i][ax] == layer))) continue;
                int[] pos = positions[i].clone(), normal = normals[i].clone();
                for (int n = 0; n < (direction == 1 ? 1 : 3); n++) {
                    pos = rotate(pos, ax);
                    normal = rotate(normal, ax);
                }
                for (int j = 0; j < 54; j++) if (Arrays.equals(pos, positions[j]) && Arrays.equals(normal, normals[j])) {
                    p[i] = j;
                    break;
                }
            }
            int[] effect = identity();
            for (int amount = 1; amount <= 3; amount++) {
                effect = compose(effect, p);
                permutations.put(new Move(letter, amount), effect);
            }
        }
        List<List<Move>> bases = List.of(List.of(), List.of(new Move('x',1)), List.of(new Move('x',2)), List.of(new Move('x',3)), List.of(new Move('z',1)), List.of(new Move('z',3)));
        for (List<Move> base : bases) for (int y = 0; y < 4; y++) {
            List<Move> rotation = new ArrayList<>(base);
            if (y != 0) rotation.add(new Move('y',y));
            rotations.add(rotation);
        }
    }

    static char[] apply(char[] input, int[] p) {
        char[] out = new char[54];
        for (int i = 0; i < 54; i++) out[p[i]] = input[i];
        return out;
    }

    static char[] apply(char[] input, List<Move> moves) {
        char[] out = input;
        for (Move move : moves) out = apply(out, permutations.get(move));
        return out;
    }

    static int[] effect(List<Move> moves) {
        int[] out = identity();
        for (Move move : moves) out = compose(out, permutations.get(move));
        return out;
    }

    static List<Move> invert(List<Move> moves) {
        List<Move> out = new ArrayList<>();
        for (int i = moves.size() - 1; i >= 0; i--) out.add(moves.get(i).inverse());
        return out;
    }

    static String moveText(List<Move> moves) {
        return String.join(" ", moves.stream().map(Move::toString).toList());
    }

    static String sequenceText(List<Move> moves) {
        return moves.size() + (moves.isEmpty() ? "" : " " + moveText(moves));
    }

    static class SequenceParser {
        String line;
        int at;
        SequenceParser(String line, int start) {
            this.line = line;
            at = start;
        }
        char peek() {
            return at >= line.length() ? '\0' : line.charAt(at);
        }
        void spaces() {
            while (peek() == ' ') at++;
        }
        void syntax() {
            throw new Problem("error: syntax at " + (Math.min(at, line.length()) + 1));
        }
        List<Move> power(List<Move> moves) {
            int count = 1;
            if (peek() >= '1' && peek() <= '9') {
                count = peek() - '0';
                at++;
                if (peek() >= '0' && peek() <= '9') {
                    count = 10 * count + peek() - '0';
                    at++;
                }
            }
            boolean reverse = peek() == '\'';
            if (reverse) at++;
            List<Move> out = new ArrayList<>();
            for (int i = 0; i < count; i++) out.addAll(moves);
            return reverse ? invert(out) : out;
        }
        List<Move> sequence() {
            List<Move> out = new ArrayList<>();
            while (true) {
                spaces();
                char c = peek();
                if (LETTERS.indexOf(c) >= 0 && c != '\0') {
                    at++;
                    int amount = peek() == '2' ? 2 : peek() == '\'' ? 3 : 1;
                    if (amount != 1) at++;
                    out.add(new Move(c, amount));
                } else if (c == '(') {
                    at++;
                    List<Move> group = sequence();
                    spaces();
                    if (peek() != ')') syntax();
                    at++;
                    out.addAll(power(group));
                } else if (c == '[') {
                    at++;
                    List<Move> first = sequence();
                    spaces();
                    char separator = peek();
                    if (separator != ',' && separator != ':') syntax();
                    at++;
                    List<Move> second = sequence();
                    spaces();
                    if (peek() != ']') syntax();
                    at++;
                    List<Move> group = new ArrayList<>(first);
                    group.addAll(second);
                    group.addAll(invert(first));
                    if (separator == ',') group.addAll(invert(second));
                    out.addAll(power(group));
                } else if (c == '{') {
                    at++;
                    int start = at;
                    while (peek() >= 'a' && peek() <= 'z') at++;
                    String name = line.substring(start, at);
                    if (name.isEmpty() || peek() != '}') syntax();
                    if (!macros.containsKey(name)) throw new Problem("error: undefined " + name);
                    at++;
                    out.addAll(power(macros.get(name)));
                } else return out;
            }
        }
        List<Move> whole() {
            List<Move> out = sequence();
            spaces();
            if (at < line.length()) syntax();
            if (out.size() > 500) throw new Problem("error: too long");
            return out;
        }
    }

    static boolean solved(char[] input) {
        for (int i = 0; i < 54; i++) if (input[i] != input[(i / 9) * 9 + 4]) return false;
        return true;
    }

    static Normalized normalize(char[] input) {
        for (List<Move> rotation : rotations) {
            char[] candidate = apply(input, rotation);
            boolean good = true;
            for (int face = 0; face < 6; face++) if (candidate[face * 9 + 4] != COLORS.charAt(face)) good = false;
            if (good) return new Normalized(candidate, rotation);
        }
        return null;
    }

    static Pieces identify(char[] input, int[][] stickers, String[] names) {
        int[] piece = new int[names.length], orientation = new int[names.length];
        Arrays.fill(piece, -1);
        for (int q = 0; q < names.length; q++) for (int p = 0; p < names.length; p++) for (int t = 0; t < stickers[q].length; t++) {
            boolean good = true;
            for (int i = 0; i < stickers[q].length; i++) if (input[stickers[q][(t + i) % stickers[q].length]] != COLORS.charAt(FACES.indexOf(names[p].charAt(i)))) good = false;
            if (good) {
                piece[q] = p;
                orientation[q] = t;
            }
        }
        return new Pieces(piece, orientation);
    }

    static int parity(int[] permutation) {
        int count = 0;
        for (int i = 0; i < permutation.length; i++) for (int j = i + 1; j < permutation.length; j++) if (permutation[i] > permutation[j]) count++;
        return count % 2;
    }

    static String check(String text) {
        if (text.length() != 54) return "length " + text.length();
        for (int i = 0; i < 54; i++) if (COLORS.indexOf(text.charAt(i)) < 0) return "char " + (i + 1);
        for (char color : COLORS.toCharArray()) {
            long count = text.chars().filter(c -> c == color).count();
            if (count != 9) return "count " + color + " " + count;
        }
        char[] input = text.toCharArray();
        Normalized normalized = normalize(input);
        if (normalized == null) return "centers";
        Pieces corners = identify(input, CORNER_STICKERS, CORNERS), edges = identify(input, EDGE_STICKERS, EDGES);
        for (int i = 0; i < 8; i++) if (corners.piece()[i] < 0) return "corner " + CORNERS[i];
        for (int i = 0; i < 12; i++) if (edges.piece()[i] < 0) return "edge " + EDGES[i];
        for (int i = 0; i < 8; i++) {
            boolean found = false;
            for (int p : corners.piece()) if (p == i) found = true;
            if (!found) return "missing " + CORNERS[i];
        }
        for (int i = 0; i < 12; i++) {
            boolean found = false;
            for (int p : edges.piece()) if (p == i) found = true;
            if (!found) return "missing " + EDGES[i];
        }
        corners = identify(normalized.state(), CORNER_STICKERS, CORNERS);
        edges = identify(normalized.state(), EDGE_STICKERS, EDGES);
        if (Arrays.stream(corners.orientation()).sum() % 3 != 0) return "twist";
        if (Arrays.stream(edges.orientation()).sum() % 2 != 0) return "flip";
        return parity(corners.piece()) != parity(edges.piece()) ? "parity" : null;
    }

    static String cycles(Pieces pieces, String[] names, int base) {
        int[] destination = new int[names.length], orientation = new int[names.length];
        for (int q = 0; q < names.length; q++) {
            destination[pieces.piece()[q]] = q;
            orientation[pieces.piece()[q]] = pieces.orientation()[q];
        }
        boolean[] seen = new boolean[names.length];
        List<String> out = new ArrayList<>();
        for (int start = 0; start < names.length; start++) if (!seen[start]) {
            List<String> cycle = new ArrayList<>();
            int p = start, sum = 0;
            do {
                seen[p] = true;
                cycle.add(names[p]);
                sum += orientation[p];
                p = destination[p];
            }
            while (p != start);
            String mark = base == 3 ? sum % 3 == 1 ? "+" : sum % 3 == 2 ? "-" : "" : base == 2 && sum % 2 == 1 ? "+" : "";
            if (cycle.size() >= 2 || !mark.isEmpty()) out.add("(" + String.join(" ", cycle) + ")" + mark);
        }
        return out.isEmpty() ? "none" : String.join(" ", out);
    }

    static void cycles(char[] input, boolean centers) {
        System.out.println("corners " + cycles(identify(input, CORNER_STICKERS, CORNERS), CORNERS, 3));
        System.out.println("edges " + cycles(identify(input, EDGE_STICKERS, EDGES), EDGES, 2));
        if (centers) {
            int[] piece = new int[6];
            for (int i = 0; i < 6; i++) piece[i] = COLORS.indexOf(input[i * 9 + 4]);
            String[] names = FACES.chars().mapToObj(c -> "" + (char)c).toArray(String[]::new);
            System.out.println("centers " + cycles(new Pieces(piece, new int[6]), names, 1));
        }
    }

    static List<Move> simplify(List<Move> input) {
        List<Move> moves = new ArrayList<>(input);
        while (true) {
            List<Move> out = new ArrayList<>();
            for (int i = 0; i < moves.size();) {
                int ax = axis(moves.get(i).letter());
                LinkedHashMap<Character, Integer> amounts = new LinkedHashMap<>();
                while (i < moves.size() && axis(moves.get(i).letter()) == ax) {
                    Move move = moves.get(i++);
                    amounts.merge(move.letter(), move.amount(), Integer::sum);
                }
                for (var entry : amounts.entrySet()) if (entry.getValue() % 4 != 0) out.add(new Move(entry.getKey(), entry.getValue() % 4));
            }
            if (out.equals(moves)) return out;
            moves = out;
        }
    }

    static Move conjugate(int[] rotation, Move move) {
        int[] target = compose(compose(rotation, permutations.get(move)), inverse(rotation));
        for (char letter : LETTERS.toCharArray()) for (int amount = 1; amount <= 3; amount++) {
            Move candidate = new Move(letter, amount);
            if (Arrays.equals(target, permutations.get(candidate))) return candidate;
        }
        throw new IllegalStateException();
    }

    static List<Move> unrotate(List<Move> moves) {
        Map<Character, List<Move>> replacements = Map.of('M', List.of(new Move('R',1), new Move('L',3), new Move('x',3)), 'E', List.of(new Move('U',1), new Move('D',3), new Move('y',3)), 'S', List.of(new Move('F',3), new Move('B',1), new Move('z',1)), 'r', List.of(new Move('L',1), new Move('x',1)), 'l', List.of(new Move('R',1), new Move('x',3)), 'u', List.of(new Move('D',1), new Move('y',1)), 'd', List.of(new Move('U',1), new Move('y',3)), 'f', List.of(new Move('B',1), new Move('z',1)), 'b', List.of(new Move('F',1), new Move('z',3)));
        int[] rotation = identity();
        List<Move> out = new ArrayList<>();
        for (Move original : moves) for (Move move : replacements.containsKey(original.letter()) ? replacements.get(original.letter()).stream().map(m -> new Move(m.letter(), m.amount() * original.amount() % 4)).toList() : List.of(original)) {
            if ("xyz".indexOf(move.letter()) >= 0) rotation = compose(rotation, permutations.get(move));
            else out.add(conjugate(rotation, move));
        }
        for (List<Move> candidate : rotations) if (Arrays.equals(effect(candidate), rotation)) {
            out.addAll(candidate);
            break;
        }
        return out;
    }

    static long gcd(long a, long b) {
        while (b != 0) {
            long remainder = a % b;
            a = b;
            b = remainder;
        }
        return a;
    }

    static long order(int[] permutation) {
        boolean[] seen = new boolean[54];
        long order = 1;
        for (int i = 0; i < 54; i++) if (!seen[i]) {
            int count = 0, p = i;
            do {
                seen[p] = true;
                count++;
                p = permutation[p];
            }
            while (p != i);
            order = order / gcd(order, count) * count;
        }
        return order;
    }

    static boolean search(char[] input, int left, int previous, List<Move> path) {
        if (solved(input)) return true;
        if (left == 0) return false;
        for (int face = 0; face < 6; face++) {
            if (face == previous || previous == 3 && face == 0 || previous == 4 && face == 1 || previous == 5 && face == 2) continue;
            for (int amount = 1; amount <= 3; amount++) {
                Move move = new Move(FACES.charAt(face), amount);
                path.add(move);
                if (search(apply(input, permutations.get(move)), left - 1, face, path)) return true;
                path.removeLast();
            }
        }
        return false;
    }

    static void applyCurrent(List<Move> moves) {
        state = apply(state, moves);
        history.addAll(moves);
        redo.clear();
    }

    static void require(boolean condition, String reason) {
        if (!condition) throw new Problem(reason);
    }

    static long number(String word) {
        require(word.matches("0|[1-9][0-9]{0,9}"), "error: bad arguments");
        return Long.parseLong(word);
    }

    static void command(String line) {
        int space = line.indexOf(' ');
        String command = space < 0 ? line : line.substring(0, space), argument = space < 0 ? null : line.substring(space + 1);
        require(NO_ARGS.contains(command) || WORD.contains(command) || SEQUENCE.contains(command) || HEAD.contains(command), "error: unknown command " + command);
        String[] words = argument == null ? new String[0] : argument.split(" ", -1);
        String head = null;
        List<Move> moves = List.of();
        long n = 0, seed = 0;
        if (NO_ARGS.contains(command)) require(argument == null, "error: bad arguments");
        if (WORD.contains(command)) {
            require(words.length == (command.equals("SCRAMBLE") ? 2 : 1), "error: bad arguments");
            if (Set.of("UNDO", "REDO", "SEARCH", "SCRAMBLE").contains(command)) n = number(words[0]);
            if (command.equals("SCRAMBLE")) seed = number(words[1]);
            if (command.equals("SAVE") || command.equals("RESTORE")) require(words[0].matches("[a-z]{1,8}"), "error: bad arguments");
        }
        if (HEAD.contains(command)) {
            require(argument != null, "error: bad arguments");
            head = words[0];
            require(command.equals("DEFINE") ? head.matches("[a-z]{1,8}") : command.equals("MIRROR") ? Set.of("LR", "UD", "FB").contains(head) : head.matches("[xyz](?:'|2)?"), "error: bad arguments");
            moves = new SequenceParser(line, command.length() + head.length() + 2).whole();
        } else if (SEQUENCE.contains(command)) moves = new SequenceParser(line, command.length() + 1).whole();
        if (command.equals("UNDO") || command.equals("REDO")) require(n >= 1, "error: bad value");
        if (command.equals("SEARCH")) require(n <= 4, "error: bad value");
        if (command.equals("SCRAMBLE")) require(n >= 1 && n <= 50 && seed >= 1 && seed <= 2147483646L, "error: bad value");
        if (command.equals("WHERE")) require(Arrays.asList(CORNERS).contains(words[0]) || Arrays.asList(EDGES).contains(words[0]), "error: unknown piece " + words[0]);
        switch (command) {
            case "RESET":
                state = solvedState();
                history.clear();
                redo.clear();
                System.out.println("reset");
                break;
            case "SHOW":
                for (int row = 0; row < 3; row++) System.out.println("      " + state[row * 3] + " " + state[row * 3 + 1] + " " + state[row * 3 + 2]);
                for (int row = 0; row < 3; row++) {
                    List<String> colors = new ArrayList<>();
                    for (int face : new int[]{4,2,1,5}) for (int col = 0; col < 3; col++) colors.add("" + state[face * 9 + row * 3 + col]);
                    System.out.println(String.join(" ", colors));
                }
                for (int row = 0; row < 3; row++) System.out.println("      " + state[27 + row * 3] + " " + state[28 + row * 3] + " " + state[29 + row * 3]);
                break;
            case "STATE":
                System.out.println("state " + new String(state));
                break;
            case "ISSOLVED":
                int count = 0;
                for (int i = 0; i < 54; i++) if (state[i] != state[(i / 9) * 9 + 4]) count++;
                System.out.println(count == 0 ? "solved" : "unsolved " + count);
                break;
            case "HISTORY":
                System.out.println("history " + sequenceText(history));
                break;
            case "SOLUTION":
                System.out.println("solution " + sequenceText(simplify(invert(history))));
                break;
            case "ANALYZE":
                {
                    Normalized normalized = normalize(state);
                    System.out.println("rotation " + (normalized.rotation().isEmpty() ? "none" : moveText(normalized.rotation())));
                    cycles(normalized.state(), false);
                    break;
                }
            case "STAGE":
                {
                    char[] normalized = normalize(state).state();
                    Pieces corners = identify(normalized, CORNER_STICKERS, CORNERS), edges = identify(normalized, EDGE_STICKERS, EDGES);
                    int cross = 0, slots = 0, top = 0;
                    for (int i = 4; i < 8; i++) if (edges.piece()[i] == i && edges.orientation()[i] == 0) cross++;
                    for (int i = 0; i < 4; i++) if (corners.piece()[i + 4] == i + 4 && corners.orientation()[i + 4] == 0 && edges.piece()[i + 8] == i + 8 && edges.orientation()[i + 8] == 0) slots++;
                    for (int i = 0; i < 9; i++) if (normalized[i] == 'W') top++;
                    String stage = solved(normalized) ? "solved" : cross == 4 && slots == 4 && top == 9 ? "oll" : cross == 4 && slots == 4 ? "f2l" : cross == 4 ? "cross" : "none";
                    System.out.println("stage " + stage + " cross " + cross + " slots " + slots + " top " + top);
                    break;
                }
            case "MACROS":
                System.out.println("macros " + macros.size());
                macros.forEach((name, sequence) -> System.out.println("macro " + name + " " + sequenceText(sequence)));
                break;
            case "CHECK", "LOAD":
                {
                    String reason = check(words[0]);
                    if (command.equals("CHECK")) System.out.println(reason == null ? "valid" : "invalid " + reason);
                    else {
                        require(reason == null, "error: invalid " + reason);
                        state = words[0].toCharArray();
                        history.clear();
                        redo.clear();
                        System.out.println("loaded");
                    }
                    break;
                }
            case "UNDO", "REDO":
                {
                    boolean undo = command.equals("UNDO");
                    List<Move> source = undo ? history : redo, target = undo ? redo : history;
                    require(!source.isEmpty(), undo ? "error: nothing to undo" : "error: nothing to redo");
                    int countMoves = (int)Math.min(n, source.size());
                    for (int i = 0; i < countMoves; i++) {
                        Move move = source.removeLast();
                        state = apply(state, permutations.get(undo ? move.inverse() : move));
                        target.add(move);
                    }
                    System.out.println((undo ? "undone " : "redone ") + countMoves);
                    break;
                }
            case "SEARCH":
                {
                    List<Move> solution = new ArrayList<>();
                    boolean found = false;
                    for (int depth = 0; depth <= n; depth++) {
                        solution.clear();
                        if (search(state, depth, -1, solution)) {
                            found = true;
                            break;
                        }
                    }
                    System.out.println(found ? "found " + sequenceText(solution) : "not found");
                    break;
                }
            case "WHERE":
                {
                    char[] normalized = normalize(state).state();
                    boolean corner = Arrays.asList(CORNERS).contains(words[0]);
                    String[] names = corner ? CORNERS : EDGES;
                    Pieces pieces = identify(normalized, corner ? CORNER_STICKERS : EDGE_STICKERS, names);
                    int piece = Arrays.asList(names).indexOf(words[0]);
                    for (int q = 0; q < names.length; q++) if (pieces.piece()[q] == piece) System.out.println(words[0] + " at " + names[q] + (corner ? " twist " : " flip ") + pieces.orientation()[q]);
                    break;
                }
            case "SAVE":
                saves.put(words[0], new Save(state.clone(), new ArrayList<>(history)));
                System.out.println("saved " + words[0]);
                break;
            case "RESTORE":
                {
                    Save save = saves.get(words[0]);
                    require(save != null, "error: no save " + words[0]);
                    state = save.state().clone();
                    history.clear();
                    history.addAll(save.history());
                    redo.clear();
                    System.out.println("restored " + words[0]);
                    break;
                }
            case "SCRAMBLE":
                {
                    List<Move> scramble = new ArrayList<>();
                    long random = seed;
                    for (int i = 0; i < n; i++) {
                        List<Character> usable = new ArrayList<>();
                        for (char face : FACES.toCharArray()) {
                            if (i >= 1 && scramble.get(i - 1).letter() == face) continue;
                            if (i >= 2 && axis(scramble.get(i - 1).letter()) == axis(scramble.get(i - 2).letter()) && axis(face) == axis(scramble.get(i - 1).letter())) continue;
                            usable.add(face);
                        }
                        random = 48271 * random % 2147483647;
                        char face = usable.get((int)(random % usable.size()));
                        random = 48271 * random % 2147483647;
                        int amount = new int[]{1,3,2}[(int)(random % 3)];
                        scramble.add(new Move(face, amount));
                    }
                    applyCurrent(scramble);
                    System.out.println("scramble " + moveText(scramble));
                    break;
                }
            case "APPLY":
                applyCurrent(moves);
                System.out.println("applied " + moves.size());
                break;
            case "INVERT":
                System.out.println("inverse " + sequenceText(invert(moves)));
                break;
            case "SIMPLIFY":
                System.out.println("simplified " + sequenceText(simplify(moves)));
                break;
            case "METRICS":
                {
                    int htm = 0, qtm = 0, stm = 0;
                    for (Move move : moves) if ("xyz".indexOf(move.letter()) < 0) {
                        int weight = "MES".indexOf(move.letter()) >= 0 ? 2 : 1;
                        htm += weight;
                        qtm += weight * (move.amount() == 2 ? 2 : 1);
                        stm++;
                    }
                    System.out.println("metrics htm " + htm + " qtm " + qtm + " stm " + stm + " etm " + moves.size());
                    break;
                }
            case "ORDER":
                System.out.println("order " + order(effect(moves)));
                break;
            case "CYCLES":
                cycles(apply(solvedState(), moves), true);
                break;
            case "UNROTATE":
                System.out.println("unrotated " + sequenceText(unrotate(moves)));
                break;
            case "UNTIL":
                {
                    int[] permutation = effect(moves);
                    long order = order(permutation), found = 0;
                    char[] candidate = state;
                    for (long k = 1; k <= order; k++) {
                        candidate = apply(candidate, permutation);
                        if (solved(candidate)) {
                            found = k;
                            break;
                        }
                    }
                    System.out.println(found == 0 ? "until never" : "until " + found);
                    break;
                }
            case "DEFINE":
                macros.put(head, new ArrayList<>(moves));
                System.out.println("defined " + head + " " + moves.size());
                break;
            case "MIRROR":
                {
                    int mirrorAxis = head.equals("LR") ? 0 : head.equals("UD") ? 1 : 2;
                    String opposites = "DLBURFdlburf", originals = "URFDLBurfdlb";
                    List<Move> out = new ArrayList<>();
                    for (Move move : moves) {
                        char letter = move.letter();
                        int amount = move.amount();
                        if (axis(letter) == mirrorAxis) {
                            int i = originals.indexOf(letter);
                            if (i >= 0) {
                                letter = opposites.charAt(i);
                                amount = 4 - amount;
                            }
                        } else amount = 4 - amount;
                        out.add(new Move(letter, amount));
                    }
                    System.out.println("mirror " + sequenceText(out));
                    break;
                }
            case "ROTATE":
                {
                    Move rotation = new Move(head.charAt(0), head.length() == 1 ? 1 : head.charAt(1) == '2' ? 2 : 3);
                    List<Move> out = new ArrayList<>();
                    for (Move move : moves) out.add(conjugate(permutations.get(rotation), move));
                    System.out.println("rotated " + sequenceText(out));
                }
        }
    }

    public static void main(String[] args) throws IOException {
        initialize();
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in));
        int count = Integer.parseInt(input.readLine());
        for (int i = 0; i < count; i++) try {
            command(input.readLine());
        } catch (Problem ex) {
            System.out.println(ex.getMessage());
        }
    }
}
