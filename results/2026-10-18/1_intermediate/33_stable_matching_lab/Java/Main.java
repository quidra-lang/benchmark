import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.nio.charset.StandardCharsets;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

public class Main {
    enum Kind { TWO_SIDED, ROOMMATE, HOUSING }
    enum Side { ANY, PROPOSER, RECEIVER }
    enum Source { GS, GSR, BOSTON, EGALITARIAN, MINREGRET }

    static final class CommandError extends RuntimeException {
        CommandError(String message) { super("ERROR " + message); }
    }

    static final class Agent {
        final String name;
        List<Integer> preference = List.of();
        int capacity = 1;
        Agent(String name) { this.name = name; }
        Agent(Agent other) {
            name = other.name;
            preference = other.preference;
            capacity = other.capacity;
        }
    }

    record Saved(Source source, int[] partners) {
        Saved { partners = partners.clone(); }
    }
    record Run(int[] partners, int count, List<String> history) {}
    record Pair(int left, int right) {}
    record Rotation(List<Pair> pairs) {}
    record Candidate(int[] partners, int origin, int via, int cost, int regret) {}
    record Lattice(List<Candidate> matchings, List<Rotation> rotations) {}

    static int[] emptyMatching(int size) {
        int[] result = new int[size];
        Arrays.fill(result, -1);
        return result;
    }

    static String listText(List<String> values) { return values.isEmpty() ? "-" : String.join(" ", values); }

    static final class Market {
        final String name;
        final Kind kind;
        final List<Agent> agents;
        final List<String> houses;
        final int proposers;
        Saved current;

        Market(String name, Kind kind, List<String> names, int proposers, List<String> houses) {
            this.name = name;
            this.kind = kind;
            this.agents = names.stream().map(Agent::new).toList();
            this.proposers = proposers;
            this.houses = List.copyOf(houses);
        }

        Market(Market other) {
            name = other.name;
            kind = other.kind;
            agents = other.agents.stream().map(Agent::new).toList();
            houses = other.houses;
            proposers = other.proposers;
            current = other.current;
        }

        void require(Kind expected) {
            if (kind != expected) throw new CommandError("WRONG TYPE " + name);
        }

        int findAgent(String name) {
            for (int a = 0; a < agents.size(); a++) if (agents.get(a).name.equals(name)) return a;
            return -1;
        }

        int agent(String name, Side side) {
            int a = findAgent(name);
            if (a < 0) throw new CommandError("UNKNOWN AGENT " + name);
            if (side == Side.PROPOSER && a >= proposers) throw new CommandError("NOT PROPOSER " + name);
            if (side == Side.RECEIVER && a < proposers) throw new CommandError("NOT RECEIVER " + name);
            return a;
        }

        int rank(int a, int partner) {
            List<Integer> preference = agents.get(a).preference;
            int index = preference.indexOf(partner);
            return index < 0 ? preference.size() + 1 : index + 1;
        }

        boolean accepts(int a, int b) { return agents.get(a).preference.contains(b); }
        String partnerName(int partner) { return partner < 0 ? "*" : agents.get(partner).name; }

        String pairs(int[] partners) {
            List<String> pairs = new ArrayList<>();
            for (int p = 0; p < proposers; p++) pairs.add(agents.get(p).name + "-" + partnerName(partners[p]));
            return String.join(" ", pairs);
        }

        String allocation(int[] allocation) {
            List<String> result = new ArrayList<>();
            for (int a = 0; a < agents.size(); a++) result.add(agents.get(a).name + "-" + (allocation[a] < 0 ? "*" : houses.get(allocation[a])));
            return String.join(" ", result);
        }

        List<Integer> effective(int a) {
            List<Integer> preference = agents.get(a).preference;
            int own = preference.indexOf(a);
            if (own >= 0) return preference.subList(0, own + 1);
            List<Integer> result = new ArrayList<>(preference);
            result.add(a);
            return result;
        }

        boolean able(int a, int[] next, int[] counts) {
            return counts[a] < agents.get(a).capacity && next[a] < agents.get(a).preference.size();
        }

        Run deferred(boolean reverse, boolean verbose) {
            int n = agents.size(), proposals = 0;
            int[] next = new int[n], counts = new int[n];
            List<List<Integer>> holding = new ArrayList<>();
            for (int a = 0; a < n; a++) holding.add(new ArrayList<>());
            ArrayDeque<Integer> queue = new ArrayDeque<>();
            int begin = reverse ? proposers : 0, end = reverse ? n : proposers;
            for (int a = begin; a < end; a++) if (able(a, next, counts)) queue.addLast(a);
            List<String> history = new ArrayList<>();
            while (!queue.isEmpty()) {
                int x = queue.removeFirst(), y = agents.get(x).preference.get(next[x]++);
                proposals++;
                String action = "REJECT";
                List<Integer> held = holding.get(y);
                if (accepts(y, x)) {
                    if (held.size() < agents.get(y).capacity) {
                        held.add(x);
                        counts[x]++;
                        action = "HOLD";
                    } else {
                        int worst = 0;
                        for (int i = 1; i < held.size(); i++) if (rank(y, held.get(i)) > rank(y, held.get(worst))) worst = i;
                        int rejected = held.get(worst);
                        if (rank(y, x) < rank(y, rejected)) {
                            held.set(worst, x);
                            counts[rejected]--;
                            counts[x]++;
                            action = "HOLD REJECT " + agents.get(rejected).name;
                            if (able(rejected, next, counts) && !queue.contains(rejected)) queue.addLast(rejected);
                        }
                    }
                }
                if (verbose) history.add("PROPOSE " + agents.get(x).name + " " + agents.get(y).name + " " + action);
                if (able(x, next, counts)) queue.addLast(x);
            }
            int[] partners = emptyMatching(proposers);
            for (int y = 0; y < n; y++) for (int x : holding.get(y)) {
                if (reverse) partners[y] = x;
                else partners[x] = y;
            }
            return new Run(partners, proposals, history);
        }

        Run boston() {
            int[] partners = emptyMatching(proposers), remaining = new int[agents.size()];
            int rounds = 0, applications = 0;
            for (int p = 0; p < proposers; p++) rounds = Math.max(rounds, agents.get(p).preference.size());
            for (int r = proposers; r < agents.size(); r++) remaining[r] = agents.get(r).capacity;
            for (int round = 0; round < rounds; round++) {
                int[] applicants = emptyMatching(proposers);
                for (int p = 0; p < proposers; p++) if (partners[p] < 0 && round < agents.get(p).preference.size()) {
                    applicants[p] = agents.get(p).preference.get(round);
                    applications++;
                }
                for (int r = proposers; r < agents.size(); r++) for (int p : agents.get(r).preference) {
                    if (remaining[r] > 0 && applicants[p] == r) { partners[p] = r; remaining[r]--; }
                }
            }
            return new Run(partners, applications, List.of());
        }

        List<Rotation> rotations(int[] partners) {
            int[] owners = emptyMatching(agents.size()), successors = emptyMatching(proposers);
            for (int p = 0; p < proposers; p++) if (partners[p] >= 0) owners[partners[p]] = p;
            for (int p = 0; p < proposers; p++) {
                if (partners[p] < 0) continue;
                List<Integer> preference = agents.get(p).preference;
                for (int i = rank(p, partners[p]); i < preference.size(); i++) {
                    int r = preference.get(i);
                    if (accepts(r, p) && (owners[r] < 0 || rank(r, p) < rank(r, owners[r]))) {
                        successors[p] = owners[r];
                        break;
                    }
                }
            }
            List<Rotation> result = new ArrayList<>();
            boolean[] covered = new boolean[proposers];
            for (int start = 0; start < proposers; start++) {
                if (covered[start]) continue;
                List<Integer> path = new ArrayList<>();
                boolean[] seen = new boolean[proposers];
                int p = start;
                while (p >= 0 && !seen[p]) { seen[p] = true; path.add(p); p = successors[p]; }
                if (p == start) {
                    List<Pair> pairs = new ArrayList<>();
                    for (int a : path) { covered[a] = true; pairs.add(new Pair(a, partners[a])); }
                    result.add(new Rotation(List.copyOf(pairs)));
                }
            }
            return result;
        }

        Candidate candidate(int[] partners, int origin, int via) {
            int cost = 0, regret = 0;
            for (int p = 0; p < proposers; p++) if (partners[p] >= 0) {
                int r = partners[p], a = rank(p, r), b = rank(r, p);
                cost += a + b;
                regret = Math.max(regret, Math.max(a, b));
            }
            return new Candidate(partners, origin, via, cost, regret);
        }

        Lattice enumerate() {
            for (int r = proposers; r < agents.size(); r++) if (agents.get(r).capacity != 1) throw new CommandError("NOT ONE TO ONE");
            List<Candidate> matchings = new ArrayList<>();
            List<Rotation> numbered = new ArrayList<>();
            matchings.add(candidate(deferred(false, false).partners, 0, 0));
            for (int index = 0; index < matchings.size(); index++) {
                int[] partners = matchings.get(index).partners;
                for (Rotation rotation : rotations(partners)) {
                    int number = numbered.indexOf(rotation);
                    if (number < 0) { number = numbered.size(); numbered.add(rotation); }
                    int[] next = partners.clone();
                    List<Pair> pairs = rotation.pairs;
                    for (int i = 0; i < pairs.size(); i++) next[pairs.get(i).left] = pairs.get((i + 1) % pairs.size()).right;
                    if (matchings.stream().anyMatch(old -> Arrays.equals(old.partners, next))) continue;
                    if (matchings.size() == 50) throw new CommandError("TOO MANY MATCHINGS");
                    matchings.add(candidate(next, index + 1, number + 1));
                }
            }
            return new Lattice(matchings, numbered);
        }

        List<String> check(String[] words) {
            if (kind == Kind.HOUSING) throw new CommandError("WRONG TYPE " + name);
            int[] partners = emptyMatching(agents.size()), counts = new int[agents.size()];
            for (int i = 2; i < words.length; i++) {
                String[] pair = words[i].split("-");
                boolean two = kind == Kind.TWO_SIDED;
                int x = agent(pair[0], two ? Side.PROPOSER : Side.ANY);
                int y = agent(pair[1], two ? Side.RECEIVER : Side.ANY);
                if (partners[x] >= 0) throw new CommandError("DUPLICATE AGENT " + pair[0]);
                if (two) {
                    if (++counts[y] > agents.get(y).capacity) throw new CommandError("OVER CAPACITY " + pair[1]);
                } else {
                    if (x == y || partners[y] >= 0) throw new CommandError("DUPLICATE AGENT " + pair[1]);
                    partners[y] = x;
                }
                partners[x] = y;
            }
            List<Pair> unacceptable = new ArrayList<>(), blocking = new ArrayList<>();
            if (kind == Kind.TWO_SIDED) {
                for (int p = 0; p < proposers; p++) {
                    if (partners[p] >= 0 && (!accepts(p, partners[p]) || !accepts(partners[p], p))) unacceptable.add(new Pair(p, partners[p]));
                    for (int r = proposers; r < agents.size(); r++) {
                        if (partners[p] == r || !accepts(p, r) || !accepts(r, p) || rank(p, r) >= rank(p, partners[p])) continue;
                        int worst = 0;
                        for (int a = 0; a < proposers; a++) if (partners[a] == r) worst = Math.max(worst, rank(r, a));
                        if (counts[r] < agents.get(r).capacity || rank(r, p) < worst) blocking.add(new Pair(p, r));
                    }
                }
            } else {
                for (int a = 0; a < agents.size(); a++) for (int b = a + 1; b < agents.size(); b++) {
                    boolean mutual = accepts(a, b) && accepts(b, a);
                    if (partners[a] == b) {
                        if (!mutual) unacceptable.add(new Pair(a, b));
                    } else if (mutual && rank(a, b) < rank(a, partners[a]) && rank(b, a) < rank(b, partners[b])) blocking.add(new Pair(a, b));
                }
            }
            if (unacceptable.isEmpty() && blocking.isEmpty()) return List.of("CHECK " + name + " STABLE");
            List<String> output = new ArrayList<>();
            output.add("CHECK " + name + " UNSTABLE unacceptable=" + unacceptable.size() + " blocking=" + blocking.size());
            for (Pair pair : unacceptable) output.add("UNACCEPTABLE " + agents.get(pair.left).name + " " + agents.get(pair.right).name);
            for (Pair pair : blocking) output.add("BLOCKING " + agents.get(pair.left).name + " " + agents.get(pair.right).name);
            return output;
        }

        void table(List<List<Integer>> lists, List<String> output) {
            for (int a = 0; a < agents.size(); a++) {
                String preference = listText(lists.get(a).stream().map(b -> agents.get(b).name).toList());
                output.add("TABLE " + agents.get(a).name + " " + preference);
            }
        }

        List<String> roommates(boolean verbose) {
            require(Kind.ROOMMATE);
            int n = agents.size();
            for (Agent agent : agents) if (agent.preference.size() < n - 1) throw new CommandError("INCOMPLETE " + agent.name);
            List<List<Integer>> lists = new ArrayList<>();
            ArrayDeque<Integer> queue = new ArrayDeque<>();
            for (int a = 0; a < n; a++) { lists.add(new ArrayList<>(agents.get(a).preference)); queue.addLast(a); }
            int[] held = emptyMatching(n);
            int proposals = 0, failure = -1;
            while (!queue.isEmpty()) {
                int x = queue.removeFirst(), y = lists.get(x).getFirst();
                if (held[y] >= 0) queue.addLast(held[y]);
                held[y] = x;
                proposals++;
                List<Integer> targets = lists.get(y);
                List<Integer> removed = new ArrayList<>(targets.subList(targets.indexOf(x) + 1, targets.size()));
                for (int w : removed) removePair(lists, y, w);
                failure = firstEmpty(lists);
                if (failure >= 0) break;
            }
            List<String> history = new ArrayList<>();
            int rotations = 0;
            if (failure < 0 && verbose) table(lists, history);
            while (failure < 0) {
                int p = 0;
                while (p < n && lists.get(p).size() < 2) p++;
                if (p == n) break;
                int[] positions = emptyMatching(n);
                List<Integer> path = new ArrayList<>();
                while (positions[p] < 0) {
                    positions[p] = path.size();
                    path.add(p);
                    int q = lists.get(p).get(1);
                    p = lists.get(q).getLast();
                }
                List<Integer> cycle = path.subList(positions[p], path.size());
                int[] front = new int[cycle.size()];
                List<String> notation = new ArrayList<>();
                for (int i = 0; i < cycle.size(); i++) {
                    int x = cycle.get(i);
                    front[i] = lists.get(x).getFirst();
                    notation.add(agents.get(x).name + "-" + agents.get(front[i]).name);
                }
                history.add("ROTATION " + (++rotations) + " " + String.join(" ", notation));
                List<Pair> removals = new ArrayList<>();
                for (int i = 0; i < cycle.size(); i++) {
                    int u = front[(i + 1) % front.length];
                    List<Integer> targets = lists.get(u);
                    for (int w : targets.subList(targets.indexOf(cycle.get(i)) + 1, targets.size())) removals.add(new Pair(u, w));
                }
                for (Pair pair : removals) removePair(lists, pair.left, pair.right);
                if (verbose) table(lists, history);
                failure = firstEmpty(lists);
            }
            List<String> output = new ArrayList<>();
            output.add("ROOMMATES " + name + " proposals=" + proposals);
            output.addAll(history);
            if (failure >= 0) output.add("NO STABLE MATCHING " + agents.get(failure).name);
            else {
                List<String> pairs = new ArrayList<>();
                for (int a = 0; a < n; a++) if (a < lists.get(a).getFirst()) pairs.add(agents.get(a).name + "-" + agents.get(lists.get(a).getFirst()).name);
                output.add("MATCHING " + String.join(" ", pairs));
            }
            return output;
        }

        List<String> ttc() {
            int n = agents.size();
            boolean[] remaining = new boolean[n];
            Arrays.fill(remaining, true);
            List<List<Integer>> effective = new ArrayList<>();
            for (int a = 0; a < n; a++) effective.add(effective(a));
            int[] allocation = emptyMatching(n);
            List<String> history = new ArrayList<>();
            while (true) {
                int start = 0;
                while (start < n && !remaining[start]) start++;
                if (start == n) break;
                int[] points = new int[n];
                for (int a = 0; a < n; a++) if (remaining[a]) {
                    for (int house : effective.get(a)) if (remaining[house]) { points[a] = house; break; }
                }
                boolean[] seen = new boolean[n];
                int p = start;
                while (!seen[p]) { seen[p] = true; p = points[p]; }
                int first = p;
                List<String> cycle = new ArrayList<>();
                do {
                    allocation[p] = points[p];
                    remaining[p] = false;
                    cycle.add(agents.get(p).name + ":" + houses.get(points[p]));
                    p = points[p];
                } while (p != first);
                history.add("CYCLE " + (history.size() + 1) + " " + String.join(" ", cycle));
            }
            List<String> output = new ArrayList<>();
            output.add("TTC " + name + " cycles=" + history.size());
            output.addAll(history);
            output.add("ALLOCATION " + allocation(allocation));
            return output;
        }

        List<String> serial(String[] words) {
            List<Integer> order = new ArrayList<>();
            for (int i = 2; i < words.length; i++) {
                int a = agent(words[i], Side.ANY);
                if (order.contains(a)) throw new CommandError("DUPLICATE AGENT " + words[i]);
                order.add(a);
            }
            if (order.size() != agents.size()) throw new CommandError("BAD ORDER");
            boolean[] taken = new boolean[agents.size()];
            int[] allocation = emptyMatching(agents.size());
            int assigned = 0;
            for (int a : order) for (int house : agents.get(a).preference) if (!taken[house]) {
                allocation[a] = house;
                taken[house] = true;
                assigned++;
                break;
            }
            List<String> worse = new ArrayList<>();
            for (int a = 0; a < agents.size(); a++) if (allocation[a] < 0 || !effective(a).contains(allocation[a])) worse.add(agents.get(a).name);
            return List.of("SERIAL " + name + " assigned=" + assigned, "ALLOCATION " + allocation(allocation), "WORSE " + listText(worse));
        }

        List<String> hr() {
            int[] a = deferred(false, false).partners, h = deferred(true, false).partners;
            List<String> unmatched = new ArrayList<>();
            boolean rural = true;
            for (int p = 0; p < proposers; p++) {
                if (a[p] < 0) unmatched.add(agents.get(p).name);
                if ((a[p] < 0) != (h[p] < 0)) rural = false;
            }
            List<String> output = new ArrayList<>(List.of("HR " + name + " residents=" + proposers + " hospitals=" + (agents.size() - proposers),
                "RESIDENT-OPTIMAL " + pairs(a), "HOSPITAL-OPTIMAL " + pairs(h), "UNMATCHED " + listText(unmatched)));
            for (int r = proposers; r < agents.size(); r++) {
                int resident = 0, hospital = 0;
                boolean same = true;
                for (int p = 0; p < proposers; p++) {
                    if (a[p] == r) resident++;
                    if (h[p] == r) hospital++;
                    if ((a[p] == r) != (h[p] == r)) same = false;
                }
                int capacity = agents.get(r).capacity;
                output.add("HOSPITAL " + agents.get(r).name + " cap=" + capacity + " resident=" + resident + " hospital=" + hospital + " same=" + (same ? "YES" : "NO"));
                if (resident != hospital || (resident < capacity && !same)) rural = false;
            }
            output.add(rural ? "RURAL HOLDS" : "RURAL FAILS");
            return output;
        }

        List<String> manipulate(int a) {
            List<Integer> truth = agents.get(a).preference;
            int b0 = boston().partners[a], g0 = deferred(false, false).partners[a];
            List<String> output = new ArrayList<>();
            output.add("MANIPULATE " + name + " " + agents.get(a).name + " boston=" + partnerName(b0) + " gs=" + partnerName(g0) + " swaps=" + Math.max(0, truth.size() - 1));
            for (int i = 0; i + 1 < truth.size(); i++) {
                Market trial = new Market(this);
                List<Integer> swapped = new ArrayList<>(truth);
                Collections.swap(swapped, i, i + 1);
                trial.agents.get(a).preference = List.copyOf(swapped);
                int b = trial.boston().partners[a], g = trial.deferred(false, false).partners[a];
                String swap = (i + 1) + " " + agents.get(truth.get(i)).name + " " + agents.get(truth.get(i + 1)).name;
                if (rank(a, b) < rank(a, b0)) output.add("IMPROVE BOSTON " + swap + " result=" + partnerName(b));
                if (rank(a, g) < rank(a, g0)) output.add("IMPROVE GS " + swap + " result=" + partnerName(g));
            }
            if (output.size() == 1) output.add("NO IMPROVEMENT");
            return output;
        }

        List<String> stats() {
            if (current == null) throw new CommandError("NO MATCHING");
            int[] sum = new int[2], first = new int[2];
            boolean[] occupied = new boolean[agents.size()];
            int pairs = 0;
            for (int p = 0; p < proposers; p++) {
                int r = current.partners[p];
                if (r < 0) continue;
                pairs++;
                occupied[r] = true;
                int[] ranks = {rank(p, r), rank(r, p)};
                for (int i = 0; i < 2; i++) { sum[i] += ranks[i]; if (ranks[i] == 1) first[i]++; }
            }
            int[] unmatched = {proposers - pairs, 0};
            for (int r = proposers; r < agents.size(); r++) if (!occupied[r]) unmatched[1]++;
            List<String> output = new ArrayList<>();
            output.add("STATS " + name + " source=" + current.source + " pairs=" + pairs);
            String[] labels = {"PROPOSERS", "RECEIVERS"};
            for (int i = 0; i < 2; i++) {
                String average = "-", truncated = "-";
                if (pairs > 0) {
                    int divisor = gcd(sum[i], pairs), cents = 100 * sum[i] / pairs;
                    average = sum[i] / divisor + "/" + pairs / divisor;
                    truncated = String.format(Locale.ROOT, "%d.%02d", cents / 100, cents % 100);
                }
                output.add(labels[i] + " sum=" + sum[i] + " average=" + average + " truncated=" + truncated + " first=" + first[i] + " unmatched=" + unmatched[i]);
            }
            return output;
        }

        List<String> show() {
            List<String> output = new ArrayList<>();
            output.add(switch (kind) {
                case TWO_SIDED -> "SHOW " + name + " MARKET proposers=" + proposers + " receivers=" + (agents.size() - proposers);
                case ROOMMATE -> "SHOW " + name + " ROOMS agents=" + agents.size();
                case HOUSING -> "SHOW " + name + " HOUSES agents=" + agents.size();
            });
            for (int a = 0; a < agents.size(); a++) {
                Agent agent = agents.get(a);
                String prefix = switch (kind) {
                    case TWO_SIDED -> a < proposers ? "PROPOSER " + agent.name : "RECEIVER " + agent.name + " cap=" + agent.capacity;
                    case ROOMMATE -> "AGENT " + agent.name;
                    case HOUSING -> "AGENT " + agent.name + " house=" + houses.get(a);
                };
                String preference = listText(agent.preference.stream().map(b -> kind == Kind.HOUSING ? houses.get(b) : agents.get(b).name).toList());
                output.add(prefix + " " + preference);
            }
            if (kind == Kind.TWO_SIDED) output.add("CURRENT " + (current == null ? "-" : current.source));
            return output;
        }
    }

    static void removePair(List<List<Integer>> lists, int a, int b) {
        lists.get(a).remove(Integer.valueOf(b));
        lists.get(b).remove(Integer.valueOf(a));
    }

    static int firstEmpty(List<List<Integer>> lists) {
        for (int a = 0; a < lists.size(); a++) if (lists.get(a).isEmpty()) return a;
        return -1;
    }

    static int gcd(int a, int b) {
        while (b != 0) { int remainder = a % b; a = b; b = remainder; }
        return a;
    }

    static final Map<String, Market> markets = new HashMap<>();

    static List<String> create(String[] words) {
        String op = words[0], name = words[1];
        if (markets.containsKey(name)) throw new CommandError("DUPLICATE MARKET " + name);
        Kind kind = switch (op) { case "ROOMS" -> Kind.ROOMMATE; case "HOUSES" -> Kind.HOUSING; default -> Kind.TWO_SIDED; };
        List<String> names = new ArrayList<>(), houses = new ArrayList<>();
        if (op.equals("RANDOM")) {
            int n = Integer.parseInt(words[2]);
            long seed = Long.parseLong(words[3]), state = seed;
            for (int a = 0; a < 2 * n; a++) names.add((a < n ? "P" : "R") + (a % n + 1));
            Market market = new Market(name, kind, names, n, houses);
            for (int a = 0; a < 2 * n; a++) {
                List<Integer> preference = new ArrayList<>();
                for (int i = 0; i < n; i++) preference.add((a < n ? n : 0) + i);
                for (int i = n; i > 1; i--) {
                    state = 48271 * state % 2147483647;
                    Collections.swap(preference, i - 1, (int)(state % i));
                }
                market.agents.get(a).preference = List.copyOf(preference);
            }
            markets.put(name, market);
            return List.of("RANDOM " + name + " n=" + n + " seed=" + seed);
        }
        Set<String> agentNames = new HashSet<>(), houseNames = new HashSet<>();
        int proposers = 0;
        for (int i = 2; i < words.length; i++) {
            if (words[i].equals("|")) { proposers = names.size(); continue; }
            String[] pair = kind == Kind.HOUSING ? words[i].split(":") : new String[]{words[i]};
            if (!agentNames.add(pair[0])) throw new CommandError("DUPLICATE AGENT " + pair[0]);
            if (kind == Kind.HOUSING) {
                if (!houseNames.add(pair[1])) throw new CommandError("DUPLICATE HOUSE " + pair[1]);
                houses.add(pair[1]);
            }
            names.add(pair[0]);
        }
        Market market = new Market(name, kind, names, proposers, houses);
        markets.put(name, market);
        return List.of(kind == Kind.TWO_SIDED ? "MARKET " + name + " proposers=" + proposers + " receivers=" + (names.size() - proposers)
            : op + " " + name + " agents=" + names.size());
    }

    static List<String> execute(String line) {
        String[] words = line.split(" ");
        String op = words[0], name = words[1];
        if (Set.of("MARKET", "ROOMS", "HOUSES", "RANDOM").contains(op)) return create(words);
        Market market = markets.get(name);
        if (market == null) throw new CommandError("UNKNOWN MARKET " + name);
        switch (op) {
            case "SHOW" -> { return market.show(); }
            case "PREF" -> {
                int a = market.agent(words[2], Side.ANY);
                List<Integer> preference = new ArrayList<>();
                for (int i = 3; i < words.length; i++) {
                    int b = market.kind == Kind.HOUSING ? market.houses.indexOf(words[i]) : market.findAgent(words[i]);
                    if (b < 0 || (market.kind == Kind.TWO_SIDED && (a < market.proposers) == (b < market.proposers))
                        || (market.kind == Kind.ROOMMATE && a == b)) throw new CommandError("BAD CHOICE " + words[i]);
                    if (preference.contains(b)) throw new CommandError("DUPLICATE CHOICE " + words[i]);
                    preference.add(b);
                }
                market.agents.get(a).preference = List.copyOf(preference);
                if (market.kind == Kind.TWO_SIDED) market.current = null;
                return List.of("PREF " + name + " " + words[2] + " length=" + preference.size());
            }
            case "CHECK" -> { return market.check(words); }
            case "ROOMMATES" -> { return market.roommates(words.length == 3); }
            case "TTC", "SERIAL" -> {
                market.require(Kind.HOUSING);
                return op.equals("TTC") ? market.ttc() : market.serial(words);
            }
        }
        market.require(Kind.TWO_SIDED);
        switch (op) {
            case "CAPACITY" -> {
                int r = market.agent(words[2], Side.RECEIVER), capacity = Integer.parseInt(words[3]);
                market.agents.get(r).capacity = capacity;
                market.current = null;
                return List.of("CAPACITY " + name + " " + words[2] + " " + capacity);
            }
            case "GS", "GSR", "BOSTON" -> {
                Run result = op.equals("BOSTON") ? market.boston() : market.deferred(op.equals("GSR"), words.length == 3);
                market.current = new Saved(Source.valueOf(op), result.partners);
                List<String> output = new ArrayList<>();
                output.add(op + " " + name + " " + (op.equals("BOSTON") ? "applications" : "proposals") + "=" + result.count);
                output.addAll(result.history);
                output.add("MATCHING " + market.pairs(result.partners));
                return output;
            }
            case "HR" -> { return market.hr(); }
            case "MANIPULATE" -> { return market.manipulate(market.agent(words[2], Side.PROPOSER)); }
            case "STATS" -> { return market.stats(); }
            case "LATTICE", "EGALITARIAN", "MINREGRET" -> {
                Lattice lattice = market.enumerate();
                if (op.equals("LATTICE")) {
                    List<String> output = new ArrayList<>();
                    output.add("LATTICE " + name + " matchings=" + lattice.matchings.size() + " rotations=" + lattice.rotations.size());
                    for (int i = 0; i < lattice.matchings.size(); i++) {
                        Candidate candidate = lattice.matchings.get(i);
                        String origin = candidate.origin == 0 ? "-" : Integer.toString(candidate.origin);
                        String via = candidate.via == 0 ? "-" : Integer.toString(candidate.via);
                        output.add("MATCHING " + (i + 1) + " from=" + origin + " via=" + via + " cost=" + candidate.cost + " regret=" + candidate.regret + " " + market.pairs(candidate.partners));
                    }
                    for (int i = 0; i < lattice.rotations.size(); i++) {
                        List<String> notation = lattice.rotations.get(i).pairs.stream().map(pair -> market.agents.get(pair.left).name + "-" + market.agents.get(pair.right).name).toList();
                        output.add("ROTATION " + (i + 1) + " " + String.join(" ", notation));
                    }
                    return output;
                }
                boolean egalitarian = op.equals("EGALITARIAN");
                int best = 0, value = 0;
                for (int i = 0; i < lattice.matchings.size(); i++) {
                    Candidate candidate = lattice.matchings.get(i);
                    int metric = egalitarian ? candidate.cost : candidate.regret;
                    if (i == 0 || metric < value) { best = i; value = metric; }
                }
                int[] selected = lattice.matchings.get(best).partners;
                market.current = new Saved(Source.valueOf(op), selected);
                return List.of(op + " " + name + " matching=" + (best + 1) + " " + (egalitarian ? "cost" : "regret") + "=" + value,
                    "MATCHING " + market.pairs(selected));
            }
            default -> throw new IllegalStateException("Unknown command in well-formed input");
        }
    }

    public static void main(String[] args) throws Exception {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8));
        BufferedWriter output = new BufferedWriter(new OutputStreamWriter(System.out, StandardCharsets.UTF_8));
        int count = Integer.parseInt(input.readLine());
        for (int i = 0; i < count; i++) {
            String line = input.readLine();
            try {
                for (String row : execute(line)) { output.write(row); output.write('\n'); }
            } catch (CommandError error) { output.write(error.getMessage()); output.write('\n'); }
        }
        output.flush();
    }
}
