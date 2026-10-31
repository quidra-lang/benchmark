import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.io.IOException;
import java.util.*;
final class Environment {
    static final class Rng {
        long state;
        Rng(long seed) {
            state = seed;
        }
        long draw() {
            state = state * 48271 % 2147483647;
            return state;
        }
    }
    record Outcome(int cell, int weight) {}
    final int height, width, size, start;
    final char[] cells;
    final int[] states, terminals, wind;
    final long[] rewards;
    final int[][] moves;
    Environment(long stepReward) throws IOException {
        List<String> lines = Files.readAllLines(Path.of("input/world.txt"), StandardCharsets.US_ASCII);
        height = Integer.parseInt(lines.get(0).split(" ")[1]);
        width = Integer.parseInt(lines.get(1).split(" ")[1]);
        size = height * width;
        cells = new char[size];
        rewards = new long[size];
        wind = new int[width];
        moves = new int[size][4];
        List<Integer> active = new ArrayList<>(), ends = new ArrayList<>();
        int origin = -1;
        for (int r = 0; r < height; r++)
            for (int c = 0; c < width; c++) {
                int x = r * width + c;
                cells[x] = lines.get(r + 2).charAt(c);
                rewards[x] = stepReward;
                if (cells[x] == 'G' || cells[x] == 'P')
                    ends.add(x);
                else if (cells[x] != '#')
                    active.add(x);
                if (cells[x] == 'S')
                    origin = x;
            }
        start = origin;
        states = active.stream().mapToInt(Integer::intValue).toArray();
        terminals = ends.stream().mapToInt(Integer::intValue).toArray();
        String winds = lines.get(height + 2).split(" ")[1];
        for (int c = 0; c < width; c++)
            wind[c] = winds.charAt(c) - '0';
        String[] values = lines.get(height + 3).split(" ");
        for (int i = 0; i < terminals.length; i++)
            rewards[terminals[i]] = Long.parseLong(values[i + 1]);
        int[] offsets = {-width, 1, width, -1};
        for (int x : states)
            for (int action = 0; action < 4; action++) {
                int y = x + offsets[action];
                if (cells[y] == '#')
                    y = x;
                if (!terminal(y))
                    for (int i = 0; i < wind[x % width]; i++) {
                        if (cells[y - width] == '#')
                            break;
                        y -= width;
                        if (terminal(y))
                            break;
                    }
                moves[x][action] = y;
            }
    }
    boolean terminal(int x) {
        return cells[x] == 'G' || cells[x] == 'P';
    }
    static final class Model {
        final Environment world;
        final int q, floorSlip, iceSlip;
        final List<Outcome>[][] transitions;
        @SuppressWarnings("unchecked")
        Model(Environment world, int q, int floorSlip, int iceSlip) {
            this.world = world;
            this.q = q;
            this.floorSlip = floorSlip;
            this.iceSlip = iceSlip;
            transitions = (List<Outcome>[][]) new List<?>[world.size][4];
            for (int x : world.states)
                for (int a = 0; a < 4; a++) {
                    List<Outcome> row = new ArrayList<>();
                    int p = slip(x);
                    int[] directions = {a, (a + 1) % 4, (a + 3) % 4}, weights = {q - 2 * p, p, p};
                    for (int i = 0; i < 3; i++)
                        if (weights[i] > 0)
                            row.add(new Outcome(world.moves[x][directions[i]], weights[i]));
                    transitions[x][a] = row;
                }
        }
        int slip(int x) {
            return world.cells[x] == '~' ? iceSlip : floorSlip;
        }
        int step(int x, int action, Rng rng) {
            long t = rng.draw() % q;
            int p = slip(x);
            int direction = t < q - 2 * p ? action : t < q - p ? (action + 1) % 4 : (action + 3) % 4;
            return world.moves[x][direction];
        }
    }
}
