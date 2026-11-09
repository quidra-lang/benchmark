import java.io.*;
import java.util.*;

public class Main {
    static final int LIMIT = 7;

    enum Kind {
        PLURALITY, RUNOFF, IRV, COOMBS, BUCKLIN, BORDA, BALDWIN, NANSON, BLACK,
        VETO, CONDORCET, COPELAND, MINIMAX, SCHULZE, RANKEDPAIRS, KEMENY, APPROVAL, STV
    }
    enum MinimaxKind { WINNING, MARGIN, OPPOSITION }

    record Method(Kind kind, int parameter, MinimaxKind minimax) {
        Method(Kind kind) { this(kind, 0, MinimaxKind.WINNING); }
        static Method parse(String[] words, int start) {
            Kind kind = Kind.valueOf(words[start]);
            return switch (kind) {
                case MINIMAX -> new Method(kind, 0, MinimaxKind.valueOf(words[start + 1]));
                case APPROVAL, STV -> new Method(kind, Integer.parseInt(words[start + 1]), MinimaxKind.WINNING);
                default -> new Method(kind);
            };
        }
        boolean rankable() { return kind != Kind.CONDORCET && kind != Kind.STV; }
        @Override public String toString() {
            return switch (kind) {
                case MINIMAX -> kind + " " + minimax;
                case APPROVAL, STV -> kind + " " + parameter;
                default -> kind.toString();
            };
        }
    }

    static final List<Method> SUMMARY = List.of(
        new Method(Kind.PLURALITY), new Method(Kind.RUNOFF), new Method(Kind.IRV),
        new Method(Kind.COOMBS), new Method(Kind.BUCKLIN), new Method(Kind.BORDA),
        new Method(Kind.BALDWIN), new Method(Kind.NANSON), new Method(Kind.BLACK),
        new Method(Kind.VETO), new Method(Kind.COPELAND), new Method(Kind.MINIMAX),
        new Method(Kind.SCHULZE), new Method(Kind.RANKEDPAIRS), new Method(Kind.KEMENY)
    );

    record Ballot(int votes, List<Integer> ranking) {
        Ballot { ranking = List.copyOf(ranking); }
    }
    record Outcome(List<Integer> order, List<String> lines) {}
    record Removal(int candidate, boolean tie) {}
    record Standing(List<Integer> order, boolean tie) {}
    record Pair(int from, int to) {}

    static final class Tallies {
        final int[] first = new int[LIMIT], last = new int[LIMIT], borda = new int[LIMIT];
        final int[][] approval = new int[LIMIT][LIMIT];
        int nonblank;
    }

    static final class CommandError extends RuntimeException {
        CommandError(String reason) { super(reason); }
    }

    static int bit(int candidate) { return 1 << candidate; }
    static List<Integer> members(int field) {
        List<Integer> result = new ArrayList<>();
        for (int a = 0; a < LIMIT; a++) if ((field & bit(a)) != 0) result.add(a);
        return result;
    }
    static int mask(List<Integer> candidates) {
        int field = 0;
        for (int a : candidates) field |= bit(a);
        return field;
    }
    static List<Integer> effective(List<Integer> ranking, int field) {
        return ranking.stream().filter(a -> (field & bit(a)) != 0).toList();
    }
    static int sum(int field, int[] scores) {
        int total = 0;
        for (int a : members(field)) total += scores[a];
        return total;
    }
    static boolean majority(int field, int[] scores) {
        int total = sum(field, scores);
        for (int a : members(field)) if (2 * scores[a] > total) return true;
        return false;
    }
    static String tieMark(boolean tie) { return tie ? " (tie)" : ""; }
    static String money(int value) { return String.format(Locale.ROOT, "%d.%02d", value / 100, value % 100); }
    static void closure(int field, boolean[][] relation) {
        List<Integer> list = members(field);
        for (int via : list) for (int a : list) for (int b : list) {
            relation[a][b] |= relation[a][via] && relation[via][b];
        }
    }

    static final class Election {
        final int number;
        final List<String> names;
        int active;
        List<Integer> tiebreak;
        final int[] priority = new int[LIMIT];
        final List<Ballot> groups = new ArrayList<>();
        final List<Integer> entryEnds = new ArrayList<>();
        int total;
        final Tallies[] cache = new Tallies[1 << LIMIT];
        int[][] pairs;

        Election(int number, List<String> names) {
            this.number = number;
            this.names = List.copyOf(names);
            active = bit(names.size()) - 1;
            tiebreak = members(active);
            tiebreak.sort(Comparator.comparing(names::get));
            setTiebreak(tiebreak);
        }
        void setTiebreak(List<Integer> order) {
            for (int i = 0; i < order.size(); i++) priority[order.get(i)] = i;
            tiebreak = order;
        }
        int candidate(String name) {
            int a = names.indexOf(name);
            if (a < 0) throw new CommandError("unknown candidate " + name);
            return a;
        }
        List<Integer> checkedNames(List<String> words) {
            List<Integer> result = new ArrayList<>();
            for (String name : words) {
                int a = candidate(name);
                if (result.contains(a)) throw new CommandError("duplicate candidate " + name);
                result.add(a);
            }
            return result;
        }
        String namesText(List<Integer> list, String separator) {
            return String.join(separator, list.stream().map(names::get).toList());
        }
        String values(int field, int[] scores, boolean cents) {
            StringJoiner result = new StringJoiner(", ");
            for (int a : members(field)) result.add(names.get(a) + " " + (cents ? money(scores[a]) : scores[a]));
            return result.toString();
        }
        List<Integer> ordered(int field, int[] scores, boolean descending) {
            List<Integer> result = members(field);
            result.sort((a, b) -> {
                int comparison = descending ? Integer.compare(scores[b], scores[a]) : Integer.compare(scores[a], scores[b]);
                return comparison != 0 ? comparison : Integer.compare(priority[a], priority[b]);
            });
            return result;
        }
        Outcome finish(List<Integer> order, boolean tie, List<String> lines) {
            lines.add("winner: " + names.get(order.getFirst()) + tieMark(tie));
            return new Outcome(order, lines);
        }
        void invalidate() { Arrays.fill(cache, null); pairs = null; }
        void finishEntry() { entryEnds.add(groups.size()); invalidate(); }

        Tallies tallies(int field) {
            if (cache[field] != null) return cache[field];
            Tallies scores = new Tallies();
            List<Integer> candidates = members(field);
            int size = candidates.size();
            for (Ballot group : groups) {
                List<Integer> ranking = effective(group.ranking, field);
                int ranked = mask(ranking);
                if (!ranking.isEmpty()) {
                    scores.first[ranking.getFirst()] += group.votes;
                    scores.nonblank += group.votes;
                }
                if (ranking.size() == size) scores.last[ranking.getLast()] += group.votes;
                else for (int a : candidates) if ((ranked & bit(a)) == 0) scores.last[a] += group.votes;
                for (int j = 0; j < ranking.size(); j++) {
                    int a = ranking.get(j);
                    scores.borda[a] += group.votes * (size - j - 1);
                    for (int depth = j; depth < size; depth++) scores.approval[depth][a] += group.votes;
                }
            }
            cache[field] = scores;
            return scores;
        }
        int[][] pairwise() {
            if (pairs != null) return pairs;
            int[][] matrix = new int[LIMIT][LIMIT];
            for (Ballot group : groups) {
                int[] positions = new int[LIMIT];
                Arrays.fill(positions, LIMIT);
                for (int i = 0; i < group.ranking.size(); i++) positions[group.ranking.get(i)] = i;
                for (int a = 0; a < names.size(); a++) for (int b = 0; b < names.size(); b++) {
                    if (positions[a] < positions[b]) matrix[a][b] += group.votes;
                }
            }
            return pairs = matrix;
        }
        int condorcet(int field, boolean loser) {
            int[][] matrix = pairwise();
            List<Integer> list = members(field);
            for (int a : list) {
                boolean found = true;
                for (int b : list) if (a != b && (loser ? matrix[a][b] >= matrix[b][a] : matrix[a][b] <= matrix[b][a])) {
                    found = false;
                    break;
                }
                if (found) return a;
            }
            return -1;
        }
        Removal lookBack(int field, List<int[]> history) {
            List<Integer> choices = members(field);
            int[] current = history.getLast();
            int minimum = choices.stream().mapToInt(a -> current[a]).min().orElseThrow();
            choices.removeIf(a -> current[a] != minimum);
            boolean tie = choices.size() > 1;
            for (int i = history.size() - 2; i >= 0; i--) {
                int[] previous = history.get(i);
                int low = choices.stream().mapToInt(a -> previous[a]).min().orElseThrow();
                choices.removeIf(a -> previous[a] != low);
            }
            int a = Collections.max(choices, Comparator.comparingInt(x -> priority[x]));
            return new Removal(a, tie);
        }

        Outcome elimination(int field, boolean coombs, boolean exhausted) {
            int remaining = field;
            List<Integer> removed = new ArrayList<>();
            List<int[]> history = new ArrayList<>();
            List<String> lines = new ArrayList<>();
            while (true) {
                Tallies scores = tallies(remaining);
                int round = lines.size() + 1, activeVotes = sum(remaining, scores.first);
                String line = "round " + round + ": " + (exhausted
                    ? "active " + activeVotes + ", exhausted " + (total - activeVotes)
                    : values(remaining, scores.first, false));
                if (Integer.bitCount(remaining) == 1 || majority(remaining, scores.first)) {
                    lines.add(line);
                    List<Integer> order = ordered(remaining, scores.first, true);
                    order.addAll(removed.reversed());
                    return exhausted ? new Outcome(order, lines) : finish(order, false, lines);
                }
                Removal choice;
                if (coombs) {
                    List<Integer> candidates = members(remaining);
                    int maximum = candidates.stream().mapToInt(a -> scores.last[a]).max().orElseThrow();
                    candidates.removeIf(a -> scores.last[a] != maximum);
                    List<Integer> least = ordered(mask(candidates), scores.first, true);
                    choice = new Removal(least.getLast(), candidates.size() > 1);
                    line += "; last " + values(remaining, scores.last, false);
                } else {
                    history.add(scores.first);
                    choice = lookBack(remaining, history);
                }
                if (!exhausted) line += "; eliminated " + names.get(choice.candidate) + tieMark(choice.tie);
                lines.add(line);
                removed.add(choice.candidate);
                remaining &= ~bit(choice.candidate);
            }
        }
        Outcome runoff(int field) {
            int[] first = tallies(field).first;
            List<Integer> order = ordered(field, first, true);
            List<String> lines = new ArrayList<>();
            lines.add("round 1: " + values(field, first, false));
            boolean tie = false;
            if (!majority(field, first)) {
                int a = order.get(0), b = order.get(1), finalists = bit(a) | bit(b);
                boolean advanceTie = order.size() >= 3 && first[b] == first[order.get(2)];
                int[] second = tallies(finalists).first;
                tie = second[a] == second[b];
                if (second[b] > second[a]) Collections.swap(order, 0, 1);
                lines.add("finalists: " + namesText(members(finalists), ", ") + tieMark(advanceTie));
                lines.add("round 2: " + values(finalists, second, false));
            }
            return finish(order, tie, lines);
        }
        Outcome bucklin(int field) {
            Tallies scores = tallies(field);
            int majority = scores.nonblank / 2 + 1, lastDepth = 0;
            List<String> lines = new ArrayList<>();
            lines.add("majority: " + majority);
            List<Integer> order = members(field);
            for (int depth = 0; depth < order.size(); depth++) {
                lastDepth = depth;
                lines.add("round " + (depth + 1) + ": " + values(field, scores.approval[depth], false));
                boolean reached = false;
                for (int a : order) if (scores.approval[depth][a] >= majority) reached = true;
                if (reached) break;
            }
            int finalDepth = lastDepth;
            order.sort((a, b) -> {
                for (int depth = finalDepth; depth >= 0; depth--) {
                    int comparison = Integer.compare(scores.approval[depth][b], scores.approval[depth][a]);
                    if (comparison != 0) return comparison;
                }
                return Integer.compare(priority[a], priority[b]);
            });
            boolean tie = scores.approval[finalDepth][order.get(0)] == scores.approval[finalDepth][order.get(1)];
            return finish(order, tie, lines);
        }
        Outcome bordaElimination(int field, boolean nanson) {
            int remaining = field;
            List<Integer> tail = new ArrayList<>();
            List<int[]> history = new ArrayList<>();
            List<String> lines = new ArrayList<>();
            while (Integer.bitCount(remaining) >= 2) {
                int[] scores = tallies(remaining).borda;
                String line = "round " + (lines.size() + 1) + ": " + values(remaining, scores, false);
                List<Integer> removed;
                if (nanson) {
                    int total = sum(remaining, scores), size = Integer.bitCount(remaining);
                    removed = members(remaining);
                    removed.removeIf(a -> scores[a] * size >= total);
                    if (removed.isEmpty()) { lines.add(line); break; }
                    line += "; eliminated " + namesText(removed, ", ");
                    removed = ordered(mask(removed), scores, true);
                } else {
                    history.add(scores);
                    Removal choice = lookBack(remaining, history);
                    line += "; eliminated " + names.get(choice.candidate) + tieMark(choice.tie);
                    removed = new ArrayList<>(List.of(choice.candidate));
                }
                lines.add(line);
                remaining &= ~mask(removed);
                removed.addAll(tail);
                tail = removed;
            }
            List<Integer> order = ordered(remaining, new int[LIMIT], true);
            boolean tie = nanson && order.size() > 1;
            order.addAll(tail);
            return finish(order, tie, lines);
        }

        List<String> pairLines(int field, int[][] matrix) {
            List<Integer> list = members(field);
            List<String> lines = new ArrayList<>();
            for (int i = 0; i < list.size(); i++) for (int j = i + 1; j < list.size(); j++) {
                int a = list.get(i), b = list.get(j);
                String result = matrix[a][b] == matrix[b][a] ? "tie" : names.get(matrix[a][b] > matrix[b][a] ? a : b);
                lines.add(names.get(a) + " vs " + names.get(b) + ": " + matrix[a][b] + "-" + matrix[b][a] + " (" + result + ")");
            }
            return lines;
        }
        Outcome condorcetReport(int field) {
            int winner = condorcet(field, false), loser = condorcet(field, true);
            int[][] matrix = pairwise();
            boolean[][] weak = new boolean[LIMIT][LIMIT], strong = new boolean[LIMIT][LIMIT];
            List<Integer> list = members(field);
            for (int a : list) for (int b : list) {
                weak[a][b] = matrix[a][b] >= matrix[b][a];
                strong[a][b] = matrix[a][b] > matrix[b][a];
            }
            closure(field, weak);
            closure(field, strong);
            List<Integer> smith = list.stream().filter(a -> list.stream().allMatch(b -> weak[a][b])).toList();
            List<Integer> schwartz = list.stream().filter(a -> list.stream().allMatch(b -> !strong[b][a] || strong[a][b])).toList();
            return new Outcome(List.of(), List.of(
                "winner: " + (winner < 0 ? "NONE" : names.get(winner)),
                "loser: " + (loser < 0 ? "NONE" : names.get(loser)),
                "smith: " + namesText(smith, ", "), "schwartz: " + namesText(schwartz, ", ")
            ));
        }
        Standing topological(int field, boolean[][] relation) {
            int remaining = field;
            List<Integer> order = new ArrayList<>();
            boolean tie = false;
            while (remaining != 0) {
                List<Integer> list = members(remaining);
                List<Integer> choices = list.stream().filter(a -> list.stream().allMatch(b -> a.equals(b) || !relation[b][a])).toList();
                if (order.isEmpty()) tie = choices.size() > 1;
                int a = Collections.min(choices, Comparator.comparingInt(x -> priority[x]));
                order.add(a);
                remaining &= ~bit(a);
            }
            return new Standing(order, tie);
        }
        Outcome schulze(int field) {
            int[][] matrix = pairwise(), paths = new int[LIMIT][LIMIT];
            List<Integer> list = members(field);
            for (int a : list) for (int b : list) if (matrix[a][b] > matrix[b][a]) paths[a][b] = matrix[a][b];
            for (int via : list) for (int a : list) for (int b : list) {
                if (a != via && b != via && a != b) paths[a][b] = Math.max(paths[a][b], Math.min(paths[a][via], paths[via][b]));
            }
            boolean[][] relation = new boolean[LIMIT][LIMIT];
            for (int a : list) for (int b : list) relation[a][b] = paths[a][b] > paths[b][a];
            Standing result = topological(field, relation);
            List<String> lines = pairLines(field, paths);
            lines.add("ranking: " + namesText(result.order, " > "));
            return finish(result.order, result.tie, lines);
        }
        Outcome rankedPairs(int field) {
            int[][] matrix = pairwise();
            List<Integer> list = members(field);
            List<Pair> pairs = new ArrayList<>();
            for (int a : list) for (int b : list) if (matrix[a][b] > matrix[b][a]) pairs.add(new Pair(a, b));
            pairs.sort(Comparator.comparingInt((Pair p) -> -matrix[p.from][p.to])
                .thenComparingInt(p -> matrix[p.to][p.from]).thenComparingInt(p -> priority[p.from]).thenComparingInt(p -> priority[p.to]));
            boolean[][] locked = new boolean[LIMIT][LIMIT], reached = new boolean[LIMIT][LIMIT];
            List<String> lines = new ArrayList<>();
            for (Pair pair : pairs) {
                int a = pair.from, b = pair.to;
                boolean skip = reached[b][a];
                lines.add((skip ? "skip " : "lock ") + names.get(a) + ">" + names.get(b) + " " + matrix[a][b] + "-" + matrix[b][a]);
                if (!skip) {
                    locked[a][b] = reached[a][b] = true;
                    closure(field, reached);
                }
            }
            Standing result = topological(field, locked);
            return finish(result.order, result.tie, lines);
        }
        Outcome kemeny(int field) {
            int[][] matrix = pairwise();
            int[] best = new int[1 << LIMIT], ways = new int[1 << LIMIT], heads = new int[1 << LIMIT];
            ways[0] = 1;
            for (int subset = 1; subset <= field; subset++) {
                if ((subset & ~field) != 0) continue;
                best[subset] = -1;
                List<Integer> list = members(subset);
                for (int a : list) {
                    int rest = subset & ~bit(a), score = best[rest];
                    for (int b : list) if (a != b) score += matrix[a][b];
                    if (score > best[subset]) { best[subset] = score; ways[subset] = heads[subset] = 0; }
                    if (score == best[subset]) { ways[subset] += ways[rest]; heads[subset] |= bit(a); }
                }
            }
            List<Integer> order = new ArrayList<>();
            int remaining = field;
            while (remaining != 0) {
                for (int a : tiebreak) if ((heads[remaining] & bit(a)) != 0) {
                    order.add(a);
                    remaining &= ~bit(a);
                    break;
                }
            }
            List<String> lines = new ArrayList<>(List.of("score: " + best[field], "optimal: " + ways[field], "ranking: " + namesText(order, " > ")));
            return finish(order, Integer.bitCount(heads[field]) > 1, lines);
        }
        Outcome stv(int field, int seats) {
            int[] value = new int[groups.size()], owner = new int[groups.size()];
            for (int i = 0; i < groups.size(); i++) if (!effective(groups.get(i).ranking, field).isEmpty()) value[i] = 100;
            int quota = tallies(field).nonblank * 100 / (seats + 1) + 1, continuing = field;
            List<String> lines = new ArrayList<>(List.of("quota: " + money(quota)));
            List<Integer> elected = new ArrayList<>();
            List<int[]> history = new ArrayList<>();
            while (true) {
                int[] scores = new int[LIMIT];
                int exhausted = 0;
                Arrays.fill(owner, -1);
                for (int i = 0; i < groups.size(); i++) {
                    if (value[i] == 0) continue;
                    Ballot group = groups.get(i);
                    for (int a : group.ranking) if ((continuing & bit(a)) != 0) { owner[i] = a; break; }
                    int amount = group.votes * value[i];
                    if (owner[i] < 0) exhausted += amount;
                    else scores[owner[i]] += amount;
                }
                history.add(scores);
                String line = "round " + history.size() + ": " + values(continuing, scores, true) + "; exhausted " + money(exhausted);
                List<Integer> order = ordered(continuing, scores, true);
                if (order.size() == seats - elected.size()) {
                    lines.add(line + "; elected " + namesText(order, ", "));
                    elected.addAll(order);
                    break;
                }
                int a = order.getFirst();
                if (scores[a] >= quota) {
                    int surplus = scores[a] - quota;
                    elected.add(a);
                    continuing &= ~bit(a);
                    for (int i = 0; i < groups.size(); i++) if (owner[i] == a) value[i] = value[i] * surplus / scores[a];
                    lines.add(line + "; elected " + names.get(a) + " (surplus " + money(surplus) + ")");
                    if (elected.size() == seats) break;
                } else {
                    Removal choice = lookBack(continuing, history);
                    continuing &= ~bit(choice.candidate);
                    lines.add(line + "; excluded " + names.get(choice.candidate) + tieMark(choice.tie));
                }
            }
            lines.add("elected: " + namesText(elected, ", "));
            return new Outcome(List.of(), lines);
        }

        Outcome tally(int field, Method method) {
            switch (method.kind) {
                case RUNOFF -> { return runoff(field); }
                case IRV, COOMBS -> { return elimination(field, method.kind == Kind.COOMBS, false); }
                case BUCKLIN -> { return bucklin(field); }
                case BALDWIN, NANSON -> { return bordaElimination(field, method.kind == Kind.NANSON); }
                case CONDORCET -> { return condorcetReport(field); }
                case SCHULZE -> { return schulze(field); }
                case RANKEDPAIRS -> { return rankedPairs(field); }
                case KEMENY -> { return kemeny(field); }
                case STV -> { return stv(field, method.parameter); }
                default -> {}
            }
            Tallies base = tallies(field);
            List<String> lines = new ArrayList<>();
            int[] scores;
            String label = "scores";
            boolean descending = true;
            int condorcetWinner = -1;
            switch (method.kind) {
                case PLURALITY -> { scores = base.first; label = "votes"; }
                case BORDA, BLACK -> {
                    scores = base.borda;
                    if (method.kind == Kind.BLACK) {
                        condorcetWinner = condorcet(field, false);
                        lines.add("condorcet: " + (condorcetWinner < 0 ? "NONE" : names.get(condorcetWinner)));
                    }
                }
                case VETO -> { scores = base.last; label = "vetoes"; descending = false; }
                case APPROVAL -> {
                    scores = base.approval[Math.min(method.parameter, Integer.bitCount(field)) - 1];
                    label = "approvals";
                }
                case COPELAND -> {
                    scores = new int[LIMIT];
                    int[][] matrix = pairwise();
                    List<Integer> list = members(field);
                    StringJoiner descriptions = new StringJoiner(", ");
                    for (int a : list) {
                        int wins = 0, draws = 0, losses = 0;
                        for (int b : list) if (a != b) {
                            if (matrix[a][b] > matrix[b][a]) wins++;
                            else if (matrix[a][b] == matrix[b][a]) draws++;
                            else losses++;
                        }
                        scores[a] = 2 * wins + draws;
                        descriptions.add(names.get(a) + " " + scores[a] / 2 + "." + scores[a] % 2 * 5
                            + " (" + wins + "-" + draws + "-" + losses + ")");
                    }
                    lines.add("scores: " + descriptions);
                    label = null;
                }
                case MINIMAX -> {
                    scores = new int[LIMIT];
                    descending = false;
                    int[][] matrix = pairwise();
                    List<Integer> list = members(field);
                    for (int a : list) for (int b : list) if (a != b) {
                        int opposition = matrix[b][a], support = matrix[a][b], value = 0;
                        if (method.minimax == MinimaxKind.OPPOSITION) value = opposition;
                        else if (opposition > support) value = method.minimax == MinimaxKind.MARGIN ? opposition - support : opposition;
                        scores[a] = Math.max(scores[a], value);
                    }
                }
                default -> throw new AssertionError();
            }
            List<Integer> order = ordered(field, scores, descending);
            boolean tie = scores[order.get(0)] == scores[order.get(1)];
            if (condorcetWinner >= 0) {
                order.remove(Integer.valueOf(condorcetWinner));
                order.addFirst(condorcetWinner);
                tie = false;
            }
            if (label != null) lines.add(label + ": " + values(field, scores, false));
            return finish(order, tie, lines);
        }
        List<String> ballotsReport() {
            Map<String, Integer> counts = new HashMap<>();
            for (Ballot group : groups) {
                List<Integer> ranking = effective(group.ranking, active);
                String notation = ranking.isEmpty() ? "-" : namesText(ranking, ">");
                counts.merge(notation, group.votes, Integer::sum);
            }
            List<String> ranked = new ArrayList<>(counts.keySet());
            ranked.sort(Comparator.<String>comparingInt(counts::get).reversed().thenComparing(Comparator.naturalOrder()));
            List<String> lines = new ArrayList<>();
            lines.add("total " + total + ", blank " + counts.getOrDefault("-", 0) + ", distinct " + counts.size());
            for (String notation : ranked) lines.add(counts.get(notation) + " " + notation);
            return lines;
        }
    }

    static final class Lab {
        Election election;
        int number;

        List<String> execute(String line) {
            String[] words = line.split(" ");
            String command = words[0];
            if (command.equals("CANDIDATES")) {
                List<String> names = Arrays.asList(words).subList(1, words.length);
                if (names.size() < 2) throw new CommandError("too few candidates");
                Set<String> seen = new HashSet<>();
                for (String name : names) if (!seen.add(name)) throw new CommandError("duplicate candidate " + name);
                election = new Election(++number, names);
                return List.of("election " + number + ": " + names.size() + " candidates");
            }
            Election e = election;
            if (e == null) throw new CommandError("no election");
            switch (command) {
                case "BALLOT" -> {
                    List<Integer> ranking = words[2].equals("-") ? List.of() : e.checkedNames(Arrays.asList(words[2].split(">")));
                    int votes = Integer.parseInt(words[1]);
                    e.groups.add(new Ballot(votes, ranking));
                    e.total += votes;
                    e.finishEntry();
                    return List.of();
                }
                case "RANDOM" -> {
                    int count = Integer.parseInt(words[1]);
                    long state = Long.parseLong(words[2]);
                    for (int group = 0; group < count; group++) {
                        List<Integer> ranking = members(e.active);
                        for (int i = ranking.size() - 1; i > 0; i--) {
                            state = 48271 * state % 2147483647;
                            Collections.swap(ranking, i, (int) (state % (i + 1)));
                        }
                        state = 48271 * state % 2147483647;
                        int length = (int) (state % ranking.size()) + 1;
                        e.groups.add(new Ballot(1, ranking.subList(0, length)));
                    }
                    e.total += count;
                    e.finishEntry();
                    return List.of();
                }
                case "UNDO" -> {
                    if (e.entryEnds.isEmpty()) throw new CommandError("nothing to undo");
                    e.entryEnds.removeLast();
                    int end = e.entryEnds.isEmpty() ? 0 : e.entryEnds.getLast();
                    for (int i = end; i < e.groups.size(); i++) e.total -= e.groups.get(i).votes;
                    e.groups.subList(end, e.groups.size()).clear();
                    e.invalidate();
                    return List.of();
                }
                case "WITHDRAW", "RESTORE" -> {
                    int a = e.candidate(words[1]);
                    boolean active = (e.active & bit(a)) != 0;
                    if (command.equals("WITHDRAW")) {
                        if (!active) throw new CommandError("already withdrawn " + words[1]);
                        if (Integer.bitCount(e.active) <= 2) throw new CommandError("too few candidates");
                        e.active &= ~bit(a);
                    } else {
                        if (active) throw new CommandError("not withdrawn " + words[1]);
                        e.active |= bit(a);
                    }
                    return List.of();
                }
                case "TIEBREAK" -> {
                    List<Integer> order = e.checkedNames(Arrays.asList(words).subList(1, words.length));
                    if (order.size() != e.names.size()) throw new CommandError("incomplete tiebreak");
                    e.setTiebreak(order);
                    return List.of();
                }
                case "STATUS" -> {
                    List<Integer> withdrawn = members((bit(e.names.size()) - 1) & ~e.active);
                    return List.of("[" + line + "]", "election " + e.number,
                        "active: " + e.namesText(members(e.active), ", "),
                        "withdrawn: " + (withdrawn.isEmpty() ? "none" : e.namesText(withdrawn, ", ")),
                        "tiebreak: " + e.namesText(e.tiebreak, ", "),
                        "ballots: " + e.total + " in " + e.entryEnds.size() + " entries");
                }
            }
            if (e.entryEnds.isEmpty()) throw new CommandError("no ballots");
            Method requested = null;
            if (command.equals("RANKING") || command.equals("SPOILERS")) {
                requested = Method.parse(words, 1);
                if (!requested.rankable()) throw new CommandError("not rankable");
                if (command.equals("SPOILERS") && Integer.bitCount(e.active) < 3) throw new CommandError("too few candidates");
            }
            int[] compared = new int[2];
            if (command.equals("COMPARE")) {
                for (int i = 0; i < 2; i++) {
                    compared[i] = e.candidate(words[i + 1]);
                    if ((e.active & bit(compared[i])) == 0) throw new CommandError("withdrawn candidate " + words[i + 1]);
                }
                if (compared[0] == compared[1]) throw new CommandError("same candidate");
            }
            if (command.equals("STV") && Integer.parseInt(words[1]) >= Integer.bitCount(e.active)) throw new CommandError("too many seats");
            List<String> lines = new ArrayList<>();
            lines.add("[" + line + "]");
            switch (command) {
                case "RANKING", "SPOILERS" -> {
                    Outcome result = e.tally(e.active, requested);
                    if (command.equals("RANKING")) lines.add(e.namesText(result.order, " > "));
                    else {
                        int winner = result.order.getFirst();
                        lines.add("winner: " + e.names.get(winner));
                        for (int a : members(e.active)) if (a != winner) {
                            int other = e.tally(e.active & ~bit(a), requested).order.getFirst();
                            lines.add("without " + e.names.get(a) + ": " + e.names.get(other) + (other != winner ? " (changed)" : ""));
                        }
                    }
                }
                case "BALLOTS" -> lines.addAll(e.ballotsReport());
                case "PROFILE" -> {
                    Tallies scores = e.tallies(e.active);
                    int size = Integer.bitCount(e.active);
                    for (int a : members(e.active)) {
                        StringJoiner counts = new StringJoiner(" ");
                        for (int j = 0; j < size; j++) counts.add(Integer.toString(scores.approval[j][a] - (j == 0 ? 0 : scores.approval[j - 1][a])));
                        lines.add(e.names.get(a) + ": " + counts + " unranked " + (e.total - scores.approval[size - 1][a]));
                    }
                }
                case "PAIRWISE" -> lines.addAll(e.pairLines(e.active, e.pairwise()));
                case "EXHAUSTED" -> lines.addAll(e.elimination(e.active, false, true).lines);
                case "SUMMARY", "COMPARE" -> {
                    int[] wins = new int[LIMIT];
                    List<List<String>> ahead = List.of(new ArrayList<>(), new ArrayList<>());
                    for (Method method : SUMMARY) {
                        Outcome result = e.tally(e.active, method);
                        if (command.equals("SUMMARY")) {
                            int winner = result.order.getFirst();
                            wins[winner]++;
                            lines.add(method + ": " + e.names.get(winner));
                        } else {
                            int side = result.order.indexOf(compared[0]) < result.order.indexOf(compared[1]) ? 0 : 1;
                            ahead.get(side).add(method.toString());
                        }
                    }
                    if (command.equals("SUMMARY")) lines.add("wins: " + e.values(e.active, wins, false));
                    else {
                        int[][] matrix = e.pairwise();
                        int a = compared[0], b = compared[1];
                        lines.add(e.names.get(a) + " " + matrix[a][b] + ", " + e.names.get(b) + " " + matrix[b][a]
                            + ", neither " + (e.total - matrix[a][b] - matrix[b][a]));
                        for (int i = 0; i < 2; i++) lines.add(e.names.get(compared[i]) + " ahead: "
                            + (ahead.get(i).isEmpty() ? "none" : String.join(", ", ahead.get(i))));
                    }
                }
                default -> lines.addAll(e.tally(e.active, Method.parse(words, 0)).lines);
            }
            return lines;
        }
    }

    public static void main(String[] args) throws IOException {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in));
        BufferedWriter output = new BufferedWriter(new OutputStreamWriter(System.out));
        int count = Integer.parseInt(input.readLine());
        Lab lab = new Lab();
        for (int i = 0; i < count; i++) {
            String line = input.readLine();
            try {
                for (String row : lab.execute(line)) { output.write(row); output.write('\n'); }
            } catch (CommandError error) {
                output.write("ERROR " + error.getMessage());
                output.write('\n');
            }
        }
        output.flush();
    }
}
