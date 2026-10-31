import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

public final class Main {
    private static final class CommandError extends RuntimeException {
        CommandError(String message) { super(message); }
    }

    private static long gcd(long a, long b) {
        a = Math.abs(a);
        b = Math.abs(b);
        while (b != 0) {
            long remainder = a % b;
            a = b;
            b = remainder;
        }
        return a;
    }

    private record Fraction(long numerator, long denominator) implements Comparable<Fraction> {
        Fraction {
            if (denominator < 0) {
                numerator = -numerator;
                denominator = -denominator;
            }
            long divisor = gcd(numerator, denominator);
            numerator /= divisor;
            denominator /= divisor;
        }

        Fraction add(Fraction other) {
            return new Fraction(numerator * other.denominator + other.numerator * denominator,
                                denominator * other.denominator);
        }

        Fraction subtract(Fraction other) {
            return new Fraction(numerator * other.denominator - other.numerator * denominator,
                                denominator * other.denominator);
        }

        Fraction multiply(Fraction other) {
            return new Fraction(numerator * other.numerator, denominator * other.denominator);
        }

        Fraction divide(Fraction other) {
            return new Fraction(numerator * other.denominator, denominator * other.numerator);
        }

        Fraction abs() { return new Fraction(Math.abs(numerator), denominator); }

        @Override
        public int compareTo(Fraction other) {
            return Long.compare(numerator * other.denominator, other.numerator * denominator);
        }

        @Override
        public String toString() { return numerator + "/" + denominator; }

        String value() {
            long decimal = numerator % denominator * 1_000_000 / denominator;
            return this + "(" + numerator / denominator + "." +
                String.format(Locale.ROOT, "%06d", decimal) + ")";
        }
    }

    private static final Fraction ZERO = new Fraction(0, 1);
    private static final Fraction ONE = new Fraction(1, 1);
    private static final Fraction TWO = new Fraction(2, 1);

    private static int number(String text) { return Integer.parseInt(text); }
    private static String yes(boolean value) { return value ? "yes" : "no"; }

    private static Fraction probability(String text) {
        String[] parts = text.split("/");
        long numerator = Long.parseLong(parts[0]);
        long denominator = parts.length == 1 ? 1 : Long.parseLong(parts[1]);
        if (denominator == 0 || numerator > denominator) throw new CommandError("BAD PROBABILITY");
        return new Fraction(numerator, denominator);
    }

    private static Fraction[] vector(int size) {
        Fraction[] result = new Fraction[size];
        Arrays.fill(result, ZERO);
        return result;
    }

    private static Fraction[][] matrix(int rows, int columns) {
        Fraction[][] result = new Fraction[rows][];
        for (int i = 0; i < rows; i++) result[i] = vector(columns);
        return result;
    }

    private static Fraction[][] identity(int size) {
        Fraction[][] result = matrix(size, size);
        for (int i = 0; i < size; i++) result[i][i] = ONE;
        return result;
    }

    private static Fraction sum(Fraction[] values) {
        Fraction total = ZERO;
        for (Fraction value : values) total = total.add(value);
        return total;
    }

    private static Fraction[][] product(Fraction[][] left, Fraction[][] right) {
        Fraction[][] result = matrix(left.length, right[0].length);
        for (int i = 0; i < left.length; i++) {
            for (int j = 0; j < right[0].length; j++) {
                for (int k = 0; k < right.length; k++) {
                    result[i][j] = result[i][j].add(left[i][k].multiply(right[k][j]));
                }
            }
        }
        return result;
    }

    private static Fraction[][] eliminate(Fraction[][] equations) {
        int size = equations.length;
        for (int column = 0; column < size; column++) {
            int pivotRow = column;
            while (equations[pivotRow][column].equals(ZERO)) pivotRow++;
            Fraction[] swapped = equations[column];
            equations[column] = equations[pivotRow];
            equations[pivotRow] = swapped;
            Fraction pivot = equations[column][column];
            for (int j = 0; j < equations[column].length; j++) {
                equations[column][j] = equations[column][j].divide(pivot);
            }
            for (int row = 0; row < size; row++) {
                if (row == column || equations[row][column].equals(ZERO)) continue;
                Fraction factor = equations[row][column];
                for (int j = 0; j < equations[row].length; j++) {
                    equations[row][j] = equations[row][j].subtract(factor.multiply(equations[column][j]));
                }
            }
        }
        return equations;
    }

    private static String fractions(Fraction[] values) {
        return String.join(" ", Arrays.stream(values).map(Fraction::toString).toList());
    }

    private static final class Chain {
        final List<String> states;
        final Fraction[][] transition;

        Chain(List<String> states) {
            this.states = List.copyOf(states);
            transition = matrix(states.size(), states.size());
        }

        int size() { return states.size(); }

        int state(String name) {
            int index = states.indexOf(name);
            if (index < 0) throw new CommandError("UNKNOWN STATE " + name);
            return index;
        }

        Fraction rowSum(int row, List<Integer> selected) {
            Fraction result = ZERO;
            for (int column : selected) result = result.add(transition[row][column]);
            return result;
        }

        List<Integer> targets(String[] words, int start) {
            boolean[] selected = new boolean[size()];
            for (int i = start; i < words.length; i++) {
                int index = state(words[i]);
                if (selected[index]) throw new CommandError("DUPLICATE STATE " + words[i]);
                selected[index] = true;
            }
            List<Integer> result = new ArrayList<>();
            for (int i = 0; i < size(); i++) if (selected[i]) result.add(i);
            return result;
        }

        List<Integer> absorbing() {
            List<Integer> result = new ArrayList<>();
            for (int i = 0; i < size(); i++) if (transition[i][i].equals(ONE)) result.add(i);
            return result;
        }

        String names(List<Integer> indices, String separator) {
            return String.join(separator, indices.stream().map(states::get).toList());
        }

        void display(List<String> lines, Fraction[][] values, String label) {
            lines.add("STATES " + String.join(" ", states));
            for (int i = 0; i < size(); i++) lines.add(label + " " + states.get(i) + " " + fractions(values[i]));
        }
    }

    private record CommunicatingClass(List<Integer> states, boolean closed, int period) {}

    private static final class Graph {
        final boolean[][] reachable;
        final List<CommunicatingClass> classes = new ArrayList<>();
        final int[] classOf;
        final int[] levels;

        Graph(Chain chain) {
            int size = chain.size();
            reachable = new boolean[size][size];
            for (int i = 0; i < size; i++) {
                for (int j = 0; j < size; j++) {
                    reachable[i][j] = i == j || !chain.transition[i][j].equals(ZERO);
                }
            }
            for (int k = 0; k < size; k++) {
                for (int i = 0; i < size; i++) {
                    for (int j = 0; j < size; j++) reachable[i][j] |= reachable[i][k] && reachable[k][j];
                }
            }
            classOf = new int[size];
            Arrays.fill(classOf, -1);
            levels = new int[size];
            for (int root = 0; root < size; root++) {
                if (classOf[root] >= 0) continue;
                List<Integer> states = new ArrayList<>();
                for (int i = 0; i < size; i++) {
                    if (reachable[root][i] && reachable[i][root]) {
                        states.add(i);
                        classOf[i] = classes.size();
                    }
                }
                boolean closed = true;
                boolean[] visited = new boolean[size];
                ArrayDeque<Integer> queue = new ArrayDeque<>();
                queue.add(root);
                visited[root] = true;
                while (!queue.isEmpty()) {
                    int current = queue.remove();
                    for (int next = 0; next < size; next++) {
                        if (chain.transition[current][next].equals(ZERO)) continue;
                        if (!states.contains(next)) {
                            closed = false;
                        } else if (!visited[next]) {
                            visited[next] = true;
                            levels[next] = levels[current] + 1;
                            queue.add(next);
                        }
                    }
                }
                long period = 0;
                for (int i : states) {
                    for (int j : states) {
                        if (!chain.transition[i][j].equals(ZERO)) period = gcd(period, levels[i] + 1L - levels[j]);
                    }
                }
                classes.add(new CommunicatingClass(states, closed, (int) period));
            }
        }

        boolean reaches(int source, List<Integer> targets) {
            for (int target : targets) if (reachable[source][target]) return true;
            return false;
        }

        void requireIrreducible() {
            if (classes.size() != 1) throw new CommandError("NOT IRREDUCIBLE");
        }
    }

    private static Fraction[] stationary(Chain chain, List<Integer> states) {
        int count = states.size();
        Fraction[][] equations = matrix(count, count + 1);
        for (int i = 0; i < count - 1; i++) {
            for (int j = 0; j < count; j++) {
                equations[i][j] = chain.transition[states.get(j)][states.get(i)].subtract(i == j ? ONE : ZERO);
            }
        }
        Arrays.fill(equations[count - 1], ONE);
        eliminate(equations);
        Fraction[] distribution = vector(chain.size());
        for (int i = 0; i < count; i++) distribution[states.get(i)] = equations[i][count];
        return distribution;
    }

    private record Hitting(Fraction[] probabilities, Fraction[] times) {}

    private static Hitting hitting(Chain chain, Graph graph, List<Integer> targets, boolean withTimes) {
        int size = chain.size();
        Fraction[] probabilities = vector(size);
        Fraction[] times = new Fraction[size];
        for (int target : targets) {
            probabilities[target] = ONE;
            times[target] = ZERO;
        }
        List<Integer> unknown = new ArrayList<>();
        for (int i = 0; i < size; i++) {
            if (!targets.contains(i) && graph.reaches(i, targets)) unknown.add(i);
        }
        int count = unknown.size();
        if (count > 0) {
            Fraction[][] equations = matrix(count, count + 1);
            for (int i = 0; i < count; i++) {
                for (int j = 0; j < count; j++) {
                    equations[i][j] = (i == j ? ONE : ZERO).subtract(chain.transition[unknown.get(i)][unknown.get(j)]);
                }
                equations[i][count] = chain.rowSum(unknown.get(i), targets);
            }
            eliminate(equations);
            for (int i = 0; i < count; i++) probabilities[unknown.get(i)] = equations[i][count];
        }
        if (withTimes) {
            List<Integer> certain = unknown.stream().filter(i -> probabilities[i].equals(ONE)).toList();
            count = certain.size();
            if (count > 0) {
                Fraction[][] equations = matrix(count, count + 1);
                for (int i = 0; i < count; i++) {
                    for (int j = 0; j < count; j++) {
                        equations[i][j] = (i == j ? ONE : ZERO).subtract(chain.transition[certain.get(i)][certain.get(j)]);
                    }
                    equations[i][count] = ONE;
                }
                eliminate(equations);
                for (int i = 0; i < count; i++) times[certain.get(i)] = equations[i][count];
            }
        }
        return new Hitting(probabilities, times);
    }

    private record Absorption(List<Integer> transientStates, List<Integer> absorbingStates,
                              Fraction[][] fundamental, Fraction[] means, Fraction[] variances,
                              Fraction[][] probabilities) {}

    private static Absorption absorption(Chain chain) {
        List<Integer> absorbing = chain.absorbing();
        List<Integer> transientStates = new ArrayList<>();
        for (int i = 0; i < chain.size(); i++) if (!absorbing.contains(i)) transientStates.add(i);
        int count = transientStates.size();
        Fraction[][] equations = matrix(count, 2 * count);
        for (int i = 0; i < count; i++) {
            for (int j = 0; j < count; j++) {
                equations[i][j] = (i == j ? ONE : ZERO).subtract(chain.transition[transientStates.get(i)][transientStates.get(j)]);
            }
            equations[i][count + i] = ONE;
        }
        eliminate(equations);
        Fraction[][] fundamental = matrix(count, count);
        Fraction[] means = vector(count);
        for (int i = 0; i < count; i++) {
            fundamental[i] = Arrays.copyOfRange(equations[i], count, 2 * count);
            means[i] = sum(fundamental[i]);
        }
        Fraction[] variances = vector(count);
        Fraction[][] probabilities = matrix(count, absorbing.size());
        for (int i = 0; i < count; i++) {
            Fraction second = ZERO;
            for (int j = 0; j < count; j++) {
                Fraction coefficient = TWO.multiply(fundamental[i][j]).subtract(i == j ? ONE : ZERO);
                second = second.add(coefficient.multiply(means[j]));
            }
            variances[i] = second.subtract(means[i].multiply(means[i]));
            for (int j = 0; j < absorbing.size(); j++) {
                for (int k = 0; k < count; k++) {
                    probabilities[i][j] = probabilities[i][j].add(
                        fundamental[i][k].multiply(chain.transition[transientStates.get(k)][absorbing.get(j)]));
                }
            }
        }
        return new Absorption(transientStates, absorbing, fundamental, means, variances, probabilities);
    }

    private static Chain build(String[] words, List<String> lines) {
        int order = number(words[2]);
        int tokens = words.length - 3;
        if (order != 1 && order != 2) throw new CommandError("BAD ORDER");
        if (tokens <= order) throw new CommandError("TOO FEW TOKENS");
        List<String> states = new ArrayList<>();
        List<Integer> observations = new ArrayList<>();
        for (int i = 0; i < tokens - order + 1; i++) {
            String name = order == 1 ? words[3 + i] : words[3 + i] + "." + words[4 + i];
            int index = states.indexOf(name);
            if (index < 0) {
                if (states.size() == 10) throw new CommandError("TOO MANY STATES");
                index = states.size();
                states.add(name);
            }
            observations.add(index);
        }
        Chain chain = new Chain(states);
        int size = chain.size();
        int[][] counts = new int[size][size];
        int[] totals = new int[size];
        for (int i = 0; i < observations.size() - 1; i++) {
            int from = observations.get(i);
            counts[from][observations.get(i + 1)]++;
            totals[from]++;
        }
        lines.add("BUILD " + words[1] + " order=" + order + " states=" + size + " transitions=" + (observations.size() - 1));
        for (int i = 0; i < size; i++) {
            StringBuilder line = new StringBuilder("FROM " + states.get(i) + " total=" + totals[i]);
            if (totals[i] == 0) {
                chain.transition[i][i] = ONE;
                line.append(" absorbing");
            } else {
                for (int j = 0; j < size; j++) {
                    chain.transition[i][j] = new Fraction(counts[i][j], totals[i]);
                    if (counts[i][j] > 0) line.append(' ').append(states.get(j)).append(':').append(counts[i][j]);
                }
            }
            lines.add(line.toString());
        }
        return chain;
    }

    private static Chain gambler(String[] words, List<String> lines) {
        int goal = number(words[2]);
        int start = number(words[3]);
        if (goal == 0 || goal > 9) throw new CommandError("BAD SIZE");
        if (start > goal) throw new CommandError("BAD START");
        Fraction chance = probability(words[4]);
        if (chance.equals(ZERO) || chance.equals(ONE)) throw new CommandError("BAD PROBABILITY");
        List<String> states = new ArrayList<>();
        for (int i = 0; i <= goal; i++) states.add("s" + i);
        Chain chain = new Chain(states);
        chain.transition[0][0] = ONE;
        chain.transition[goal][goal] = ONE;
        for (int i = 1; i < goal; i++) {
            chain.transition[i][i + 1] = chance;
            chain.transition[i][i - 1] = ONE.subtract(chance);
        }
        Absorption result = absorption(chain);
        Fraction[] ruin = vector(goal + 1);
        Fraction[] duration = vector(goal + 1);
        ruin[0] = ONE;
        for (int i = 0; i < result.transientStates().size(); i++) {
            int state = result.transientStates().get(i);
            ruin[state] = result.probabilities()[i][0];
            duration[state] = result.means()[i];
        }
        lines.add("GAMBLER " + words[1] + " g=" + goal + " p=" + chance + " start=s" + start +
                  " ruin=" + ruin[start].value() + " duration=" + duration[start].value());
        for (int i = 0; i <= goal; i++) {
            lines.add("CAPITAL s" + i + " ruin=" + ruin[i].value() + " win=" + ONE.subtract(ruin[i]).value() +
                      " duration=" + duration[i].value());
        }
        return chain;
    }

    private static List<String> execute(Map<String, Chain> chains, String[] words) {
        String command = words[0];
        String name = words[1];
        List<String> lines = new ArrayList<>();
        switch (command) {
            case "CHAIN" -> {
                List<String> states = Arrays.asList(words).subList(2, words.length);
                if (states.size() > 10) throw new CommandError("TOO MANY STATES");
                Set<String> seen = new HashSet<>();
                for (String state : states) if (!seen.add(state)) throw new CommandError("DUPLICATE STATE " + state);
                chains.put(name, new Chain(states));
                lines.add("CHAIN " + name + " states=" + states.size());
                return lines;
            }
            case "BUILD" -> {
                chains.put(name, build(words, lines));
                return lines;
            }
            case "GAMBLER" -> {
                chains.put(name, gambler(words, lines));
                return lines;
            }
        }
        Chain chain = chains.get(name);
        if (chain == null) throw new CommandError("UNKNOWN CHAIN " + name);
        int size = chain.size();
        Fraction[][] transition = chain.transition;
        switch (command) {
            case "P" -> {
                int from = chain.state(words[2]);
                int to = chain.state(words[3]);
                Fraction value = probability(words[4]);
                transition[from][to] = value;
                lines.add("P " + name + " " + words[2] + " " + words[3] + " " + value + " rowsum=" + sum(transition[from]));
                return lines;
            }
            case "ROW" -> {
                int from = chain.state(words[2]);
                if (words.length - 3 != size) throw new CommandError("BAD LENGTH");
                Fraction[] row = vector(size);
                for (int i = 0; i < size; i++) row[i] = probability(words[3 + i]);
                transition[from] = row;
                lines.add("ROW " + name + " " + words[2] + " rowsum=" + sum(row));
                return lines;
            }
            case "SHOW" -> {
                lines.add("MATRIX " + name + " states=" + size);
                chain.display(lines, transition, "ROW");
                return lines;
            }
            case "CHECK" -> {
                List<String> badRows = new ArrayList<>();
                for (int i = 0; i < size; i++) {
                    Fraction total = sum(transition[i]);
                    if (!total.equals(ONE)) badRows.add("BADROW " + chain.states.get(i) + " sum=" + total);
                }
                lines.add("CHECK " + name + (badRows.isEmpty() ? " ok" : " bad=" + badRows.size()));
                lines.addAll(badRows);
                return lines;
            }
        }
        for (int i = 0; i < size; i++) {
            if (!sum(transition[i]).equals(ONE)) throw new CommandError("NOT STOCHASTIC " + chain.states.get(i));
        }
        Graph graph = new Graph(chain);
        switch (command) {
            case "CLASSES" -> {
                lines.add("CLASSES " + name + " count=" + graph.classes.size());
                for (int i = 0; i < graph.classes.size(); i++) {
                    CommunicatingClass group = graph.classes.get(i);
                    lines.add("CLASS " + (i + 1) + " " + (group.closed() ? "RECURRENT" : "TRANSIENT") +
                              " period=" + group.period() + " size=" + group.states().size() + " " + chain.names(group.states(), " "));
                    if (group.period() >= 2) {
                        for (int remainder = 0; remainder < group.period(); remainder++) {
                            List<Integer> cyclic = new ArrayList<>();
                            for (int state : group.states()) if (graph.levels[state] % group.period() == remainder) cyclic.add(state);
                            lines.add("CYCLIC " + remainder + " " + chain.names(cyclic, " "));
                        }
                    }
                }
            }
            case "CLASSIFY" -> {
                List<Integer> absorbing = chain.absorbing();
                boolean isAbsorbing = !absorbing.isEmpty();
                for (int i = 0; i < size; i++) isAbsorbing &= graph.reaches(i, absorbing);
                boolean[][] edges = new boolean[size][size];
                for (int i = 0; i < size; i++) {
                    for (int j = 0; j < size; j++) edges[i][j] = !transition[i][j].equals(ZERO);
                }
                boolean[][] power = edges;
                int exponent = 0;
                int limit = (size - 1) * (size - 1) + 1;
                for (int step = 1; step <= limit; step++) {
                    boolean positive = true;
                    for (boolean[] row : power) for (boolean value : row) positive &= value;
                    if (positive) {
                        exponent = step;
                        break;
                    }
                    if (step == limit) break;
                    boolean[][] next = new boolean[size][size];
                    for (int i = 0; i < size; i++) {
                        for (int j = 0; j < size; j++) {
                            for (int k = 0; k < size; k++) next[i][j] |= power[i][k] && edges[k][j];
                        }
                    }
                    power = next;
                }
                lines.add("CLASSIFY " + name + " absorbing_states=" + absorbing.size() + " absorbing=" + yes(isAbsorbing) +
                          " ergodic=" + yes(graph.classes.size() == 1) + " regular=" + yes(exponent != 0) +
                          " exponent=" + (exponent == 0 ? "-" : exponent));
            }
            case "STEP" -> {
                Fraction[] distribution = vector(size);
                if (Character.isDigit(words[2].charAt(0))) {
                    String[] values = words[2].split(",");
                    if (values.length != size) throw new CommandError("BAD LENGTH");
                    for (int i = 0; i < size; i++) distribution[i] = probability(values[i]);
                    if (!sum(distribution).equals(ONE)) throw new CommandError("BAD DISTRIBUTION");
                } else {
                    distribution[chain.state(words[2])] = ONE;
                }
                int steps = number(words[3]);
                for (int step = 0; step < steps; step++) {
                    Fraction[] next = vector(size);
                    for (int j = 0; j < size; j++) {
                        for (int i = 0; i < size; i++) next[j] = next[j].add(distribution[i].multiply(transition[i][j]));
                    }
                    distribution = next;
                }
                lines.add("STEP " + name + " k=" + steps);
                for (int i = 0; i < size; i++) lines.add("PROB " + chain.states.get(i) + " " + distribution[i].value());
            }
            case "POWER" -> {
                int steps = number(words[2]);
                Fraction[][] power = identity(size);
                for (int step = 0; step < steps; step++) power = product(power, transition);
                lines.add("POWER " + name + " k=" + steps);
                chain.display(lines, power, "ROW");
            }
            case "STATIONARY" -> {
                long count = graph.classes.stream().filter(CommunicatingClass::closed).count();
                lines.add("STATIONARY " + name + " count=" + count);
                int distribution = 0;
                for (int i = 0; i < graph.classes.size(); i++) {
                    CommunicatingClass group = graph.classes.get(i);
                    if (!group.closed()) continue;
                    Fraction[] pi = stationary(chain, group.states());
                    lines.add("DIST " + (++distribution) + " class=" + (i + 1) + " size=" + group.states().size());
                    for (int state : group.states()) lines.add("PI " + chain.states.get(state) + " " + pi[state].value());
                }
            }
            case "RECURRENCE" -> {
                int state = chain.state(words[2]);
                CommunicatingClass group = graph.classes.get(graph.classOf[state]);
                if (!group.closed()) throw new CommandError("TRANSIENT STATE " + words[2]);
                Fraction rho = stationary(chain, group.states())[state];
                lines.add("RECURRENCE " + name + " " + words[2] + " pi=" + rho.value() +
                          " mean=" + ONE.divide(rho).value() + " period=" + group.period());
            }
            case "ABSORB" -> {
                List<Integer> absorbing = chain.absorbing();
                if (absorbing.isEmpty()) throw new CommandError("NO ABSORBING STATE");
                for (int i = 0; i < size; i++) {
                    if (!graph.reaches(i, absorbing)) throw new CommandError("NOT ABSORBING " + chain.states.get(i));
                }
                Absorption result = absorption(chain);
                int count = result.transientStates().size();
                lines.add("ABSORB " + name + " transient=" + count + " absorbing=" + absorbing.size());
                if (count == 0) break;
                lines.add("TRANSIENT " + chain.names(result.transientStates(), " "));
                lines.add("ABSORBING " + chain.names(absorbing, " "));
                for (int i = 0; i < count; i++) {
                    lines.add("N " + chain.states.get(result.transientStates().get(i)) + " " + fractions(result.fundamental()[i]));
                }
                for (int i = 0; i < count; i++) {
                    lines.add("STEPS " + chain.states.get(result.transientStates().get(i)) + " mean=" + result.means()[i].value() +
                              " var=" + result.variances()[i].value());
                }
                for (int i = 0; i < count; i++) {
                    lines.add("B " + chain.states.get(result.transientStates().get(i)) + " " + fractions(result.probabilities()[i]));
                }
            }
            case "HITTING" -> {
                List<Integer> targets = chain.targets(words, 2);
                Hitting result = hitting(chain, graph, targets, true);
                lines.add("HITTING " + name + " targets=" + chain.names(targets, ","));
                for (int i = 0; i < size; i++) {
                    lines.add("HIT " + chain.states.get(i) + " prob=" + result.probabilities()[i].value() +
                              " time=" + (result.times()[i] == null ? "inf" : result.times()[i].value()));
                }
            }
            case "PASSAGE" -> {
                graph.requireIrreducible();
                Fraction[] pi = stationary(chain, graph.classes.getFirst().states());
                Fraction[][] passage = matrix(size, size);
                for (int j = 0; j < size; j++) {
                    Fraction[] times = hitting(chain, graph, List.of(j), true).times();
                    for (int i = 0; i < size; i++) passage[i][j] = i == j ? ONE.divide(pi[j]) : times[i];
                }
                Fraction kemeny = ZERO;
                for (int j = 1; j < size; j++) kemeny = kemeny.add(pi[j].multiply(passage[0][j]));
                lines.add("PASSAGE " + name + " kemeny=" + kemeny.value());
                chain.display(lines, passage, "M");
            }
            case "FIRSTPASSAGE" -> {
                int from = chain.state(words[2]);
                int target = chain.state(words[3]);
                int steps = number(words[4]);
                if (steps == 0) throw new CommandError("BAD STEPS");
                Fraction[] current = vector(size);
                for (int i = 0; i < size; i++) current[i] = transition[i][target];
                Fraction cumulative = ZERO;
                List<String> records = new ArrayList<>();
                for (int step = 1; step <= steps; step++) {
                    cumulative = cumulative.add(current[from]);
                    records.add("FP " + step + " " + current[from].value() + " cum=" + cumulative.value());
                    if (step == steps) break;
                    Fraction[] next = vector(size);
                    for (int i = 0; i < size; i++) {
                        for (int j = 0; j < size; j++) {
                            if (j != target) next[i] = next[i].add(transition[i][j].multiply(current[j]));
                        }
                    }
                    current = next;
                }
                lines.add("FIRSTPASSAGE " + name + " " + words[2] + " " + words[3] + " k=" + steps + " total=" + cumulative.value());
                lines.addAll(records);
            }
            case "PATHPROB" -> {
                int[] path = new int[words.length - 2];
                for (int i = 0; i < path.length; i++) path[i] = chain.state(words[2 + i]);
                Fraction chance = ONE;
                int zeroAt = 0;
                for (int i = 1; i < path.length; i++) {
                    chance = chance.multiply(transition[path[i - 1]][path[i]]);
                    if (zeroAt == 0 && chance.equals(ZERO)) zeroAt = i;
                }
                lines.add("PATHPROB " + name + " steps=" + (path.length - 1) + " prob=" + chance.value() +
                          (zeroAt == 0 ? "" : " zero_at=" + zeroAt));
            }
            case "MOSTLIKELY" -> {
                int start = chain.state(words[2]);
                int steps = number(words[3]);
                if (steps == 0) throw new CommandError("BAD STEPS");
                Fraction[][] best = matrix(steps + 1, size);
                Arrays.fill(best[steps], ONE);
                int[][] choice = new int[steps][size];
                for (int step = steps - 1; step >= 0; step--) {
                    for (int i = 0; i < size; i++) {
                        for (int j = 0; j < size; j++) {
                            Fraction candidate = transition[i][j].multiply(best[step + 1][j]);
                            if (candidate.compareTo(best[step][i]) > 0) {
                                best[step][i] = candidate;
                                choice[step][i] = j;
                            }
                        }
                    }
                }
                List<Integer> path = new ArrayList<>();
                int current = start;
                path.add(current);
                for (int step = 0; step < steps; step++) {
                    current = choice[step][current];
                    path.add(current);
                }
                lines.add("MOSTLIKELY " + name + " " + words[2] + " k=" + steps + " prob=" + best[0][start].value());
                lines.add("PATH " + chain.names(path, " "));
            }
            case "REVERSIBLE" -> {
                graph.requireIrreducible();
                Fraction[] pi = stationary(chain, graph.classes.getFirst().states());
                List<String> violations = new ArrayList<>();
                for (int i = 0; i < size; i++) {
                    for (int j = i + 1; j < size; j++) {
                        Fraction forward = pi[i].multiply(transition[i][j]);
                        Fraction backward = pi[j].multiply(transition[j][i]);
                        if (!forward.equals(backward)) {
                            violations.add("VIOLATION " + chain.states.get(i) + " " + chain.states.get(j) +
                                           " " + forward.value() + " " + backward.value());
                        }
                    }
                }
                lines.add("REVERSIBLE " + name + (violations.isEmpty() ? " yes" : " no violations=" + violations.size()));
                lines.addAll(violations);
            }
            case "REVERSE" -> {
                graph.requireIrreducible();
                Fraction[] pi = stationary(chain, graph.classes.getFirst().states());
                Chain reversed = new Chain(chain.states);
                boolean reversible = true;
                for (int i = 0; i < size; i++) {
                    for (int j = 0; j < size; j++) {
                        reversed.transition[i][j] = pi[j].multiply(transition[j][i]).divide(pi[i]);
                        reversible &= reversed.transition[i][j].equals(transition[i][j]);
                    }
                }
                chains.put(words[2], reversed);
                lines.add("REVERSE " + name + " " + words[2] + " reversible=" + yes(reversible));
                reversed.display(lines, reversed.transition, "ROW");
            }
            case "MIXING" -> {
                int steps = number(words[2]);
                if (steps == 0) throw new CommandError("BAD STEPS");
                Fraction epsilon = probability(words[3]);
                graph.requireIrreducible();
                Fraction[] pi = stationary(chain, graph.classes.getFirst().states());
                Fraction[][] power = identity(size);
                int mixingTime = 0;
                List<String> records = new ArrayList<>();
                for (int step = 1; step <= steps; step++) {
                    power = product(power, transition);
                    Fraction maximum = ZERO;
                    int worst = 0;
                    for (int i = 0; i < size; i++) {
                        Fraction distance = ZERO;
                        for (int j = 0; j < size; j++) distance = distance.add(power[i][j].subtract(pi[j]).abs());
                        distance = distance.divide(TWO);
                        if (distance.compareTo(maximum) > 0) {
                            maximum = distance;
                            worst = i;
                        }
                    }
                    if (mixingTime == 0 && maximum.compareTo(epsilon) <= 0) mixingTime = step;
                    records.add("TV " + step + " " + maximum.value() + " from=" + chain.states.get(worst));
                }
                lines.add("MIXING " + name + " k=" + steps + " eps=" + epsilon + " time=" + (mixingTime == 0 ? "none" : mixingTime));
                lines.addAll(records);
            }
            case "LUMP" -> {
                List<List<Integer>> blocks = new ArrayList<>();
                boolean[] seen = new boolean[size];
                for (String group : words[3].split("\\|")) {
                    List<Integer> block = new ArrayList<>();
                    for (String stateName : group.split(",")) {
                        int state = chain.state(stateName);
                        if (seen[state]) throw new CommandError("BAD PARTITION");
                        seen[state] = true;
                        block.add(state);
                    }
                    block.sort(Comparator.naturalOrder());
                    blocks.add(block);
                }
                for (boolean included : seen) if (!included) throw new CommandError("BAD PARTITION");
                blocks.sort(Comparator.comparingInt(block -> block.getFirst()));
                Chain lumped = new Chain(blocks.stream().map(block -> chain.states.get(block.getFirst())).toList());
                for (int k = 0; k < blocks.size(); k++) {
                    int representative = blocks.get(k).getFirst();
                    for (int l = 0; l < blocks.size(); l++) {
                        List<Integer> target = blocks.get(l);
                        Fraction expected = chain.rowSum(representative, target);
                        lumped.transition[k][l] = expected;
                        for (int state : blocks.get(k)) {
                            Fraction actual = state == representative ? expected : chain.rowSum(state, target);
                            if (!actual.equals(expected)) {
                                lines.add("LUMP " + name + " not lumpable block=" + chain.states.get(representative) +
                                          " target=" + chain.states.get(target.getFirst()) + " " + chain.states.get(representative) +
                                          "=" + expected.value() + " " + chain.states.get(state) + "=" + actual.value());
                                return lines;
                            }
                        }
                    }
                }
                chains.put(words[2], lumped);
                lines.add("LUMP " + name + " " + words[2] + " blocks=" + blocks.size());
                lumped.display(lines, lumped.transition, "ROW");
            }
            case "REWARD" -> {
                if (words.length - 3 != size) throw new CommandError("BAD LENGTH");
                Fraction discount = probability(words[2]);
                if (discount.equals(ONE)) throw new CommandError("BAD DISCOUNT");
                Fraction[] rewards = vector(size);
                for (int i = 0; i < size; i++) rewards[i] = new Fraction(number(words[3 + i]), 1);
                Fraction[][] equations = matrix(size, size + 1);
                for (int i = 0; i < size; i++) {
                    for (int j = 0; j < size; j++) equations[i][j] = (i == j ? ONE : ZERO).subtract(discount.multiply(transition[i][j]));
                    equations[i][size] = rewards[i];
                }
                eliminate(equations);
                Fraction[] gains = vector(size);
                for (CommunicatingClass group : graph.classes) {
                    if (!group.closed()) continue;
                    Fraction[] rho = stationary(chain, group.states());
                    Fraction gain = ZERO;
                    for (int state : group.states()) gain = gain.add(rho[state].multiply(rewards[state]));
                    Fraction[] chances = hitting(chain, graph, group.states(), false).probabilities();
                    for (int i = 0; i < size; i++) gains[i] = gains[i].add(chances[i].multiply(gain));
                }
                lines.add("REWARD " + name + " gamma=" + discount);
                for (int i = 0; i < size; i++) {
                    lines.add("VALUE " + chain.states.get(i) + " discounted=" + equations[i][size].value() + " gain=" + gains[i].value());
                }
            }
            case "RESTRICT" -> {
                List<Integer> selected = chain.targets(words, 3);
                for (int state : selected) {
                    for (int j = 0; j < size; j++) {
                        if (!selected.contains(j) && !transition[state][j].equals(ZERO)) {
                            throw new CommandError("NOT CLOSED " + chain.states.get(state));
                        }
                    }
                }
                Chain restricted = new Chain(selected.stream().map(chain.states::get).toList());
                for (int i = 0; i < selected.size(); i++) {
                    for (int j = 0; j < selected.size(); j++) restricted.transition[i][j] = transition[selected.get(i)][selected.get(j)];
                }
                chains.put(words[2], restricted);
                lines.add("RESTRICT " + name + " " + words[2] + " states=" + selected.size());
                restricted.display(lines, restricted.transition, "ROW");
            }
            case "SIMULATE" -> {
                int current = chain.state(words[2]);
                int steps = number(words[3]);
                long seed = Long.parseLong(words[4]);
                if (steps == 0) throw new CommandError("BAD STEPS");
                if (seed == 0 || seed >= 2_147_483_647L) throw new CommandError("BAD SEED");
                long random = seed;
                List<Integer> path = new ArrayList<>();
                int[] visits = new int[size];
                path.add(current);
                visits[current]++;
                for (int step = 0; step < steps; step++) {
                    Fraction[] row = transition[current];
                    long denominator = 1;
                    for (Fraction value : row) denominator = denominator / gcd(denominator, value.denominator()) * value.denominator();
                    random = 48_271 * random % 2_147_483_647L;
                    long pick = random % denominator;
                    Fraction cumulative = ZERO;
                    for (int j = 0; j < size; j++) {
                        cumulative = cumulative.add(row[j]);
                        long boundary = cumulative.numerator() * (denominator / cumulative.denominator());
                        if (boundary > pick) {
                            current = j;
                            break;
                        }
                    }
                    path.add(current);
                    visits[current]++;
                }
                lines.add("SIMULATE " + name + " " + words[2] + " steps=" + steps + " seed=" + seed + " end=" + chain.states.get(current));
                lines.add("PATH " + chain.names(path, " "));
                for (int i = 0; i < size; i++) lines.add("VISIT " + chain.states.get(i) + " " + visits[i]);
            }
            default -> throw new IllegalStateException(command);
        }
        return lines;
    }

    public static void main(String[] args) throws Exception {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in));
        int count = number(input.readLine());
        Map<String, Chain> chains = new HashMap<>();
        StringBuilder output = new StringBuilder();
        for (int i = 0; i < count; i++) {
            String[] words = input.readLine().split(" ");
            try {
                for (String line : execute(chains, words)) output.append(line).append('\n');
            } catch (CommandError error) {
                output.append("ERROR ").append(error.getMessage()).append('\n');
            }
        }
        System.out.print(output);
    }
}
