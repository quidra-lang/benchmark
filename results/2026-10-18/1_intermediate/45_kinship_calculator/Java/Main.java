import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collection;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;

public class Main {
    private static final Set<String> TWO_IDS = Set.of("PARENT", "UNPARENT", "SPOUSE",
            "DIVORCE", "RELATION", "PATH", "COMMON", "KINSHIP");
    private static final Set<String> ONE_ID = Set.of("DEATH", "REMOVE", "INFO", "RELATIVES",
            "WHO", "ANCESTORS", "DESCENDANTS", "COUSINS", "SIBLINGS", "GENERATIONS",
            "TREE", "PEDIGREE", "TIMELINE", "FIND");
    private static final Set<String> MODIFYING = Set.of("PERSON", "DEATH", "REMOVE",
            "PARENT", "UNPARENT", "SPOUSE", "DIVORCE");

    private static final class CommandError extends RuntimeException {
        CommandError(String message) {
            super(message);
        }
    }

    private static final class Person {
        final String id;
        final String sex;
        final int birth;
        final String name;
        Integer death;
        final Set<String> parents = new HashSet<>();

        Person(String id, String sex, int birth, String name) {
            this.id = id;
            this.sex = sex;
            this.birth = birth;
            this.name = name;
        }

        Person duplicate() {
            Person result = new Person(id, sex, birth, name);
            result.death = death;
            result.parents.addAll(parents);
            return result;
        }

        String lifeYears() {
            return birth + "-" + (death == null ? "" : death);
        }
    }

    private static final class Marriage {
        final String first;
        final String second;
        final int start;
        Integer end;
        String status = "current";
        String died;

        Marriage(String first, String second, int start) {
            this.first = first;
            this.second = second;
            this.start = start;
        }

        boolean contains(String id) {
            return first.equals(id) || second.equals(id);
        }

        String other(String id) {
            return first.equals(id) ? second : first;
        }

        Marriage duplicate() {
            Marriage result = new Marriage(first, second, start);
            result.end = end;
            result.status = status;
            result.died = died;
            return result;
        }
    }

    private record Fraction(long numerator, long denominator) {
        static final Fraction ZERO = new Fraction(0, 1);
        static final Fraction ONE = new Fraction(1, 1);
        static final Fraction HALF = new Fraction(1, 2);

        Fraction {
            long a = numerator;
            long b = denominator;
            while (b != 0) {
                long remainder = a % b;
                a = b;
                b = remainder;
            }
            numerator /= a;
            denominator /= a;
        }

        Fraction add(Fraction other) {
            long common = Math.max(denominator, other.denominator);
            return new Fraction(numerator * (common / denominator)
                    + other.numerator * (common / other.denominator), common);
        }

        Fraction half() {
            return new Fraction(numerator, denominator * 2);
        }

        @Override
        public String toString() {
            return numerator + "/" + denominator;
        }
    }

    private record Apex(String id, int da, int db, int shares, boolean collateral) {}
    private record Pair(String first, String second) {}
    private record Snapshot(Map<String, Person> people, List<Marriage> marriages) {}
    private record UndoEntry(String line, Snapshot state) {}
    private record Event(int year, int rank, String counterpart, String text) {}
    private record Cousin(String id, int removal) {}

    private static String sexWord(String sex, String male, String female, String neutral) {
        return switch (sex) {
            case "M" -> male;
            case "F" -> female;
            default -> neutral;
        };
    }

    private static String generationPrefix(int generation) {
        return switch (generation) {
            case 1 -> "";
            case 2 -> "grand";
            default -> "great-".repeat(generation - 2) + "grand";
        };
    }

    private static String ordinal(int number) {
        String[] words = {"first", "second", "third", "fourth", "fifth", "sixth",
                "seventh", "eighth", "ninth", "tenth"};
        if (number <= 10) return words[number - 1];
        String suffix = number % 100 >= 11 && number % 100 <= 13 ? "th"
                : switch (number % 10) {
                    case 1 -> "st";
                    case 2 -> "nd";
                    case 3 -> "rd";
                    default -> "th";
                };
        return number + suffix;
    }

    private static String term(int da, int db, String sex) {
        if (da == 0 && db == 0) return "self";
        if (da == 0) return generationPrefix(db) + sexWord(sex, "father", "mother", "parent");
        if (db == 0) return generationPrefix(da) + sexWord(sex, "son", "daughter", "child");
        if (da == 1 && db == 1) return sexWord(sex, "brother", "sister", "sibling");
        if (da == 1) return generationPrefix(db - 1) + sexWord(sex, "uncle", "aunt", "pibling");
        if (db == 1) return generationPrefix(da - 1) + sexWord(sex, "nephew", "niece", "nibling");
        int distance = Math.abs(da - db);
        String removal = switch (distance) {
            case 0 -> "";
            case 1 -> " once removed";
            case 2 -> " twice removed";
            default -> " " + distance + " times removed";
        };
        return ordinal(Math.min(da, db) - 1) + " cousin" + removal;
    }

    private static final class Family {
        private Map<String, Person> people = new HashMap<>();
        private List<Marriage> marriages = new ArrayList<>();
        private final List<UndoEntry> history = new ArrayList<>();
        private final Map<String, Map<String, Integer>> ancestorCache = new HashMap<>();
        private final Map<Pair, Fraction> kinshipCache = new HashMap<>();

        private Person person(String id) {
            return people.get(id);
        }

        private Snapshot snapshot() {
            Map<String, Person> savedPeople = new HashMap<>();
            for (Person person : people.values()) savedPeople.put(person.id, person.duplicate());
            List<Marriage> savedMarriages = new ArrayList<>();
            for (Marriage marriage : marriages) savedMarriages.add(marriage.duplicate());
            return new Snapshot(savedPeople, savedMarriages);
        }

        private List<String> children(String id) {
            List<String> result = new ArrayList<>();
            for (Person person : people.values()) {
                if (person.parents.contains(id)) result.add(person.id);
            }
            return result;
        }

        private Comparator<String> ageComparator() {
            return Comparator.<String>comparingInt(id -> person(id).birth).thenComparing(id -> id);
        }

        private List<String> ageOrder(Collection<String> ids) {
            List<String> result = new ArrayList<>(ids);
            result.sort(ageComparator());
            return result;
        }

        private List<String> idOrder() {
            List<String> result = new ArrayList<>(people.keySet());
            result.sort(Comparator.naturalOrder());
            return result;
        }

        private String personList(Collection<String> ids) {
            return ids.isEmpty() ? "-" : String.join(" ", ageOrder(ids));
        }

        private Marriage lastMarriage(String a, String b) {
            for (int index = marriages.size() - 1; index >= 0; index--) {
                Marriage marriage = marriages.get(index);
                if (marriage.contains(a) && marriage.contains(b)) return marriage;
            }
            return null;
        }

        private Marriage currentMarriage(String id) {
            for (Marriage marriage : marriages) {
                if (marriage.status.equals("current") && marriage.contains(id)) return marriage;
            }
            return null;
        }

        private String spouse(String id) {
            Marriage marriage = currentMarriage(id);
            return marriage == null ? null : marriage.other(id);
        }

        private Set<String> partners(String id) {
            Map<String, Marriage> latest = new HashMap<>();
            for (Marriage marriage : marriages) {
                if (marriage.contains(id)) latest.put(marriage.other(id), marriage);
            }
            Set<String> result = new HashSet<>();
            latest.forEach((other, marriage) -> {
                if (!marriage.status.equals("divorced")) result.add(other);
            });
            return result;
        }

        private boolean siblings(String a, String b) {
            return !a.equals(b) && person(a).parents.stream().anyMatch(person(b).parents::contains);
        }

        private Map<String, Integer> ancestors(String id) {
            Map<String, Integer> cached = ancestorCache.get(id);
            if (cached != null) return cached;
            Map<String, Integer> distance = new HashMap<>();
            ArrayDeque<String> queue = new ArrayDeque<>();
            distance.put(id, 0);
            queue.add(id);
            while (!queue.isEmpty()) {
                String current = queue.removeFirst();
                for (String parent : person(current).parents) {
                    if (!distance.containsKey(parent)) {
                        distance.put(parent, distance.get(current) + 1);
                        queue.addLast(parent);
                    }
                }
            }
            ancestorCache.put(id, distance);
            return distance;
        }

        private Map<String, Integer> descendants(String id) {
            Map<String, Integer> distance = new HashMap<>();
            ArrayDeque<String> queue = new ArrayDeque<>();
            distance.put(id, 0);
            queue.add(id);
            while (!queue.isEmpty()) {
                String current = queue.removeFirst();
                for (String child : children(current)) {
                    if (!distance.containsKey(child)) {
                        distance.put(child, distance.get(current) + 1);
                        queue.addLast(child);
                    }
                }
            }
            distance.remove(id);
            return distance;
        }

        private Apex apex(String a, String b) {
            Map<String, Integer> fromA = ancestors(a);
            Map<String, Integer> fromB = ancestors(b);
            if (fromB.containsKey(a)) return new Apex(a, 0, fromB.get(a), 0, false);
            if (fromA.containsKey(b)) return new Apex(b, fromA.get(b), 0, 0, false);
            Set<String> common = new HashSet<>(fromA.keySet());
            common.retainAll(fromB.keySet());
            String chosen = common.stream().min(Comparator.<String>comparingInt(
                    id -> fromA.get(id) + fromB.get(id)).thenComparingInt(fromA::get)
                    .thenComparing(id -> id)).orElse(null);
            if (chosen == null) return null;
            int da = fromA.get(chosen);
            int db = fromB.get(chosen);
            int shares = 0;
            for (String id : common) {
                if (fromA.get(id) == da && fromB.get(id) == db) shares++;
            }
            return new Apex(chosen, da, db, shares, true);
        }

        private String bloodTerm(String a, String b, String sex) {
            Apex top = apex(a, b);
            String prefix = !top.collateral() ? "" : top.shares() == 1 ? "half-"
                    : top.shares() >= 4 ? "double " : "";
            return prefix + term(top.da(), top.db(), sex);
        }

        private String bloodTerm(String a, String b) {
            return bloodTerm(a, b, person(a).sex);
        }

        private List<String> relationships(String a, String b, String sex) {
            if (a.equals(b)) return List.of("self");
            List<String> result = new ArrayList<>();
            Set<String> parentsA = person(a).parents;
            Set<String> parentsB = person(b).parents;
            Set<String> partnersA = partners(a);
            Set<String> partnersB = partners(b);
            Marriage marriage = lastMarriage(a, b);
            if (apex(a, b) != null) result.add(bloodTerm(a, b, sex));
            if (marriage != null) {
                switch (marriage.status) {
                    case "current" -> result.add(sexWord(sex, "husband", "wife", "spouse"));
                    case "widowed" -> result.add(marriage.died.equals(a)
                            ? sexWord(sex, "late husband", "late wife", "late spouse")
                            : sexWord(sex, "widower", "widow", "surviving spouse"));
                    case "divorced" -> result.add(sexWord(sex, "ex-husband", "ex-wife", "ex-spouse"));
                }
            }
            if (marriage == null && children(a).stream().anyMatch(id -> person(id).parents.contains(b))) {
                result.add("co-parent");
            }
            if (!parentsB.contains(a) && parentsB.stream().anyMatch(partnersA::contains)) {
                result.add(sexWord(sex, "stepfather", "stepmother", "stepparent"));
            }
            if (!parentsA.contains(b) && parentsA.stream().anyMatch(partnersB::contains)) {
                result.add(sexWord(sex, "stepson", "stepdaughter", "stepchild"));
            }
            if (parentsA.stream().noneMatch(parentsB::contains)
                    && parentsA.stream().anyMatch(p -> parentsB.stream().anyMatch(partners(p)::contains))) {
                result.add(sexWord(sex, "stepbrother", "stepsister", "stepsibling"));
            }
            if (!ancestors(b).containsKey(a) && ancestors(b).entrySet().stream()
                    .anyMatch(entry -> entry.getValue() == 2 && partnersA.contains(entry.getKey()))) {
                result.add(sexWord(sex, "stepgrandfather", "stepgrandmother", "stepgrandparent"));
            }
            if (!ancestors(a).containsKey(b) && ancestors(a).entrySet().stream()
                    .anyMatch(entry -> entry.getValue() == 2 && partnersB.contains(entry.getKey()))) {
                result.add(sexWord(sex, "stepgrandson", "stepgranddaughter", "stepgrandchild"));
            }
            if (partnersB.stream().anyMatch(id -> person(id).parents.contains(a))) {
                result.add(sexWord(sex, "father-in-law", "mother-in-law", "parent-in-law"));
            }
            if (partnersA.stream().anyMatch(id -> person(id).parents.contains(b))) {
                result.add(sexWord(sex, "son-in-law", "daughter-in-law", "child-in-law"));
            }
            if (partnersB.stream().anyMatch(id -> siblings(a, id))
                    || partnersA.stream().anyMatch(id -> siblings(id, b))) {
                result.add(sexWord(sex, "brother-in-law", "sister-in-law", "sibling-in-law"));
            }
            return result;
        }

        private List<String> relationships(String a, String b) {
            return relationships(a, b, person(a).sex);
        }

        private String relationshipString(String a, String b) {
            List<String> terms = relationships(a, b);
            return terms.isEmpty() ? "no relation" : String.join(", ", terms);
        }

        private Fraction kinship(String a, String b) {
            Pair key = a.compareTo(b) <= 0 ? new Pair(a, b) : new Pair(b, a);
            Fraction cached = kinshipCache.get(key);
            if (cached != null) return cached;
            Fraction result;
            if (a.equals(b)) {
                List<String> parents = new ArrayList<>(person(a).parents);
                result = parents.size() == 2
                        ? Fraction.ONE.add(kinship(parents.get(0), parents.get(1))).half() : Fraction.HALF;
            } else {
                String x = person(a).birth >= person(b).birth ? a : b;
                String y = x.equals(a) ? b : a;
                Fraction total = Fraction.ZERO;
                for (String parent : person(x).parents) total = total.add(kinship(parent, y));
                result = total.half();
            }
            kinshipCache.put(key, result);
            return result;
        }

        private Fraction inbreeding(String id) {
            List<String> parents = new ArrayList<>(person(id).parents);
            return parents.size() == 2 ? kinship(parents.get(0), parents.get(1)) : Fraction.ZERO;
        }

        private List<String> upwardPath(String id, String top) {
            List<String> result = new ArrayList<>();
            String current = id;
            result.add(current);
            while (!current.equals(top)) {
                int remaining = ancestors(current).get(top);
                current = person(current).parents.stream().sorted()
                        .filter(parent -> Integer.valueOf(remaining - 1).equals(ancestors(parent).get(top)))
                        .findFirst().orElseThrow();
                result.add(current);
            }
            return result;
        }

        private int longestChain(String id, Map<String, Integer> lengths) {
            Integer cached = lengths.get(id);
            if (cached != null) return cached;
            int result = 1;
            for (String parent : person(id).parents) result = Math.max(result, 1 + longestChain(parent, lengths));
            lengths.put(id, result);
            return result;
        }

        private void tree(String id, int depth, Set<String> visited, List<String> output) {
            String indent = "  ".repeat(depth + 1);
            if (!visited.add(id)) {
                output.add(indent + id + " (see above)");
                return;
            }
            Person person = person(id);
            String spouse = spouse(id);
            output.add(indent + id + " " + person.name + " " + person.lifeYears()
                    + (spouse == null ? "" : " = " + spouse));
            for (String child : ageOrder(children(id))) tree(child, depth + 1, visited, output);
        }

        private void pedigree(String id, int number, int generation, int depth,
                              List<String> rows, Set<String> distinct) {
            Person person = person(id);
            distinct.add(id);
            rows.add("  ".repeat(generation + 1) + number + " " + id + " " + person.name + " " + person.lifeYears());
            if (generation >= depth) return;
            List<String> parents = new ArrayList<>(person.parents);
            parents.sort(Comparator.<String>comparingInt(parent -> switch (person(parent).sex) {
                case "M" -> 0;
                case "F" -> 1;
                default -> 2;
            }).thenComparing(parent -> parent));
            for (int index = 0; index < parents.size(); index++) {
                pedigree(parents.get(index), 2 * number + index, generation + 1, depth, rows, distinct);
            }
        }

        private void loss(String other, String kind, Person person, List<Event> events) {
            Integer year = person(other).death;
            if (year != null && year >= person.birth && (person.death == null || year <= person.death)) {
                events.add(new Event(year, 5, other, "lost " + kind + " " + other));
            }
        }

        List<String> execute(String line) {
            ancestorCache.clear();
            kinshipCache.clear();
            String[] words = line.split(" ");
            String command = words[0];
            int checkedIds = TWO_IDS.contains(command) ? 2 : ONE_ID.contains(command) ? 1 : 0;
            for (int index = 1; index <= checkedIds; index++) {
                if (!people.containsKey(words[index])) throw new CommandError("UNKNOWN PERSON " + words[index]);
            }
            Snapshot before = MODIFYING.contains(command) ? snapshot() : null;
            List<String> output = new ArrayList<>();
            switch (command) {
                case "PERSON" -> {
                    String id = words[1];
                    if (people.containsKey(id)) throw new CommandError("DUPLICATE PERSON " + id);
                    people.put(id, new Person(id, words[2], Integer.parseInt(words[3]), words[4]));
                    output.add("ADDED " + id + " " + words[4] + " " + words[2] + " " + words[3]);
                }
                case "DEATH" -> {
                    String id = words[1];
                    int year = Integer.parseInt(words[2]);
                    Person person = person(id);
                    if (person.death != null) throw new CommandError("ALREADY DECEASED " + id);
                    if (year < person.birth || marriages.stream().anyMatch(marriage -> marriage.contains(id)
                            && (year < marriage.start || marriage.end != null && year < marriage.end))) {
                        throw new CommandError("BAD YEAR " + id);
                    }
                    String child = children(id).stream().sorted().filter(c -> person(c).birth > year + 1)
                            .findFirst().orElse(null);
                    if (child != null) throw new CommandError("AFTER DEATH " + child + " " + id);
                    Marriage marriage = currentMarriage(id);
                    person.death = year;
                    if (marriage != null) {
                        marriage.end = year;
                        marriage.status = "widowed";
                        marriage.died = id;
                    }
                    output.add("DIED " + id + " " + year + (marriage == null ? "" : " spouse=" + marriage.other(id)));
                }
                case "REMOVE" -> {
                    String id = words[1];
                    for (Person person : people.values()) person.parents.remove(id);
                    marriages.removeIf(marriage -> marriage.contains(id));
                    people.remove(id);
                    output.add("REMOVED " + id);
                }
                case "PARENT" -> {
                    String child = words[1];
                    String parent = words[2];
                    Person c = person(child);
                    Person p = person(parent);
                    if (child.equals(parent)) throw new CommandError("SAME PERSON " + child);
                    if (c.parents.contains(parent)) throw new CommandError("ALREADY PARENT " + child + " " + parent);
                    if (c.parents.size() == 2) throw new CommandError("TOO MANY PARENTS " + child);
                    if (ancestors(parent).containsKey(child)) throw new CommandError("CYCLE " + child + " " + parent);
                    if (p.birth + 12 > c.birth) throw new CommandError("AGE GAP " + child + " " + parent);
                    if (p.death != null && p.death + 1 < c.birth) throw new CommandError("AFTER DEATH " + child + " " + parent);
                    c.parents.add(parent);
                    output.add("LINKED " + child + " " + parent + " " + sexWord(p.sex, "father", "mother", "parent"));
                }
                case "UNPARENT" -> {
                    String child = words[1];
                    String parent = words[2];
                    if (!person(child).parents.contains(parent)) throw new CommandError("NOT PARENT " + child + " " + parent);
                    person(child).parents.remove(parent);
                    output.add("UNLINKED " + child + " " + parent);
                }
                case "SPOUSE" -> {
                    String a = words[1];
                    String b = words[2];
                    int year = Integer.parseInt(words[3]);
                    List<String> ids = List.of(a, b);
                    if (a.equals(b)) throw new CommandError("SAME PERSON " + a);
                    for (String id : ids) if (person(id).death != null) throw new CommandError("DECEASED " + id);
                    for (String id : ids) if (spouse(id) != null) throw new CommandError("ALREADY MARRIED " + id);
                    if (ancestors(b).containsKey(a) || ancestors(a).containsKey(b) || siblings(a, b)) {
                        throw new CommandError("CLOSE KIN " + a + " " + b);
                    }
                    for (String id : ids) if (year < person(id).birth + 16) throw new CommandError("TOO YOUNG " + id);
                    for (String id : ids) {
                        if (marriages.stream().anyMatch(marriage -> marriage.contains(id)
                                && marriage.end != null && marriage.end >= year)) throw new CommandError("BAD YEAR " + id);
                    }
                    marriages.add(new Marriage(a, b, year));
                    output.add("MARRIED " + a + " " + b + " " + year);
                }
                case "DIVORCE" -> {
                    String a = words[1];
                    String b = words[2];
                    int year = Integer.parseInt(words[3]);
                    if (!b.equals(spouse(a))) throw new CommandError("NOT MARRIED " + a + " " + b);
                    Marriage marriage = currentMarriage(a);
                    if (year <= marriage.start) throw new CommandError("BAD YEAR " + a);
                    marriage.end = year;
                    marriage.status = "divorced";
                    output.add("DIVORCED " + a + " " + b + " " + year);
                }
                case "UNDO" -> {
                    if (history.isEmpty()) throw new CommandError("NOTHING TO UNDO");
                    UndoEntry entry = history.remove(history.size() - 1);
                    people = entry.state().people();
                    marriages = entry.state().marriages();
                    output.add("UNDONE " + entry.line());
                }
                case "INFO" -> {
                    String id = words[1];
                    Person person = person(id);
                    output.add("INFO " + id + " " + person.name + " " + person.sex + " " + person.lifeYears());
                    output.add("  parents: " + personList(person.parents));
                    for (Marriage marriage : marriages) {
                        if (marriage.contains(id)) output.add("  marriage: " + marriage.other(id) + " "
                                + marriage.start + "-" + (marriage.end == null ? "" : marriage.end) + " " + marriage.status);
                    }
                    output.add("  children: " + personList(children(id)));
                    output.add("  siblings: " + personList(people.keySet().stream().filter(other -> siblings(id, other)).toList()));
                    output.add("  inbreeding: " + inbreeding(id));
                }
                case "RELATION" -> output.add("RELATION " + words[1] + " " + words[2] + ": "
                        + relationshipString(words[1], words[2]));
                case "RELATIVES" -> {
                    String id = words[1];
                    List<String> rows = new ArrayList<>();
                    for (String other : idOrder()) {
                        if (other.equals(id)) continue;
                        List<String> terms = relationships(other, id);
                        if (!terms.isEmpty()) rows.add("  " + other + ": " + String.join(", ", terms));
                    }
                    output.add("RELATIVES " + id + " " + rows.size());
                    output.addAll(rows);
                }
                case "WHO" -> {
                    String id = words[1];
                    String query = String.join(" ", Arrays.copyOfRange(words, 2, words.length));
                    List<String> rows = new ArrayList<>();
                    for (String other : idOrder()) {
                        if (other.equals(id)) continue;
                        List<String> actual = relationships(other, id);
                        List<String> neutral = relationships(other, id, "X");
                        for (int index = 0; index < actual.size(); index++) {
                            if (actual.get(index).equals(query) || neutral.get(index).equals(query)) {
                                rows.add("  " + other + ": " + actual.get(index));
                                break;
                            }
                        }
                    }
                    output.add("WHO " + id + " " + query + " " + rows.size());
                    output.addAll(rows);
                }
                case "PATH" -> {
                    String a = words[1];
                    String b = words[2];
                    Apex top = apex(a, b);
                    if (top == null) output.add("PATH " + a + " " + b + " none");
                    else {
                        List<String> path = upwardPath(a, top.id());
                        List<String> tail = upwardPath(b, top.id());
                        for (int index = tail.size() - 2; index >= 0; index--) path.add(tail.get(index));
                        output.add("PATH " + a + " " + b + " " + (top.da() + top.db()) + ": " + String.join(" ", path));
                    }
                }
                case "COMMON" -> {
                    String a = words[1];
                    String b = words[2];
                    Map<String, Integer> fromA = ancestors(a);
                    Map<String, Integer> fromB = ancestors(b);
                    Set<String> common = new HashSet<>(fromA.keySet());
                    common.retainAll(fromB.keySet());
                    List<String> nearest = common.stream().filter(id -> children(id).stream().noneMatch(common::contains))
                            .sorted(Comparator.<String>comparingInt(id -> fromA.get(id) + fromB.get(id))
                                    .thenComparing(id -> id)).toList();
                    output.add("COMMON " + a + " " + b + " " + nearest.size());
                    for (String id : nearest) output.add("  " + id + " " + fromA.get(id) + " " + fromB.get(id));
                }
                case "ANCESTORS", "DESCENDANTS" -> {
                    String id = words[1];
                    boolean upward = command.equals("ANCESTORS");
                    Map<String, Integer> distances = new HashMap<>(upward ? ancestors(id) : descendants(id));
                    distances.remove(id);
                    List<String> ids = new ArrayList<>(distances.keySet());
                    ids.sort(Comparator.<String>comparingInt(distances::get).thenComparing(other -> other));
                    output.add(command + " " + id + " " + ids.size());
                    for (String other : ids) {
                        int generation = distances.get(other);
                        String label = upward ? term(0, generation, person(other).sex)
                                : term(generation, 0, person(other).sex);
                        output.add("  " + generation + " " + other + " " + label);
                    }
                }
                case "COUSINS" -> {
                    String id = words[1];
                    int degree = Integer.parseInt(words[2]);
                    List<Cousin> matches = new ArrayList<>();
                    for (String other : people.keySet()) {
                        if (other.equals(id)) continue;
                        Apex top = apex(other, id);
                        if (top != null && top.da() >= 2 && top.db() >= 2
                                && Math.min(top.da(), top.db()) - 1 == degree) {
                            matches.add(new Cousin(other, Math.abs(top.da() - top.db())));
                        }
                    }
                    matches.sort(Comparator.comparingInt(Cousin::removal).thenComparing(Cousin::id));
                    output.add("COUSINS " + id + " " + degree + " " + matches.size());
                    for (Cousin match : matches) output.add("  " + match.id() + " " + bloodTerm(match.id(), id));
                }
                case "SIBLINGS" -> {
                    String id = words[1];
                    Map<String, String> classes = new HashMap<>();
                    for (String other : people.keySet()) {
                        if (other.equals(id)) continue;
                        Set<String> shared = new HashSet<>(person(id).parents);
                        shared.retainAll(person(other).parents);
                        String kind;
                        if (shared.size() == 2) kind = "full";
                        else if (shared.size() == 1) kind = "half";
                        else if (person(id).parents.stream().anyMatch(p -> person(other).parents.stream()
                                .anyMatch(partners(p)::contains))) kind = "step";
                        else continue;
                        classes.put(other, kind);
                    }
                    long earlier = classes.entrySet().stream().filter(entry -> !entry.getValue().equals("step")
                            && ageComparator().compare(entry.getKey(), id) < 0).count();
                    output.add("SIBLINGS " + id + " " + classes.size() + " order=" + (earlier + 1));
                    for (String other : ageOrder(classes.keySet())) {
                        output.add("  " + other + " " + classes.get(other) + " " + person(other).birth);
                    }
                }
                case "GENERATIONS" -> {
                    String id = words[1];
                    Map<Integer, List<String>> groups = new TreeMap<>();
                    descendants(id).forEach((other, generation) ->
                            groups.computeIfAbsent(generation, ignored -> new ArrayList<>()).add(other));
                    output.add("GENERATIONS " + id + " " + groups.size());
                    groups.forEach((generation, ids) -> {
                        int minimum = ids.stream().mapToInt(other -> person(other).birth).min().orElseThrow();
                        int maximum = ids.stream().mapToInt(other -> person(other).birth).max().orElseThrow();
                        long living = ids.stream().filter(other -> person(other).death == null).count();
                        output.add("  " + generation + " " + ids.size() + " " + living + " " + minimum + "-" + maximum);
                    });
                }
                case "TREE" -> {
                    String id = words[1];
                    output.add("TREE " + id + " " + descendants(id).size());
                    tree(id, 0, new HashSet<>(), output);
                }
                case "PEDIGREE" -> {
                    String id = words[1];
                    int depth = Integer.parseInt(words[2]);
                    List<String> rows = new ArrayList<>();
                    Set<String> distinct = new HashSet<>();
                    pedigree(id, 1, 0, depth, rows, distinct);
                    output.add("PEDIGREE " + id + " " + depth + " entries=" + rows.size() + " distinct=" + distinct.size());
                    output.addAll(rows);
                }
                case "TIMELINE" -> {
                    String id = words[1];
                    Person person = person(id);
                    List<Event> events = new ArrayList<>();
                    events.add(new Event(person.birth, 0, "", "born"));
                    for (Marriage marriage : marriages) {
                        if (!marriage.contains(id)) continue;
                        String other = marriage.other(id);
                        events.add(new Event(marriage.start, 1, other, "married " + other));
                        if (marriage.status.equals("divorced")) {
                            events.add(new Event(marriage.end, 3, other, "divorced " + other));
                        } else if (marriage.status.equals("widowed") && marriage.died.equals(other)) {
                            events.add(new Event(marriage.end, 4, other, "widowed " + other));
                        }
                    }
                    for (String child : children(id)) events.add(new Event(person(child).birth, 2, child, "child " + child));
                    for (String parent : person.parents) loss(parent, "parent", person, events);
                    for (String child : children(id)) loss(child, "child", person, events);
                    if (person.death != null) events.add(new Event(person.death, 6, "", "died"));
                    events.sort(Comparator.comparingInt(Event::year).thenComparingInt(Event::rank).thenComparing(Event::counterpart));
                    output.add("TIMELINE " + id + " " + events.size());
                    for (Event event : events) output.add("  " + event.year() + " " + event.text());
                }
                case "CENSUS" -> {
                    int year = Integer.parseInt(words[1]);
                    List<String> residents = ageOrder(people.keySet().stream().filter(id -> person(id).birth <= year
                            && (person(id).death == null || person(id).death > year)).toList());
                    output.add("CENSUS " + year + " " + residents.size());
                    for (String id : residents) {
                        Marriage latest = null;
                        for (Marriage marriage : marriages) {
                            if (marriage.contains(id) && marriage.start <= year) latest = marriage;
                        }
                        String status = latest == null ? "single"
                                : latest.end == null || latest.end > year ? "married " + latest.other(id) : latest.status;
                        output.add("  " + id + " " + (year - person(id).birth) + " " + status);
                    }
                }
                case "KINSHIP" -> output.add("KINSHIP " + words[1] + " " + words[2] + " " + kinship(words[1], words[2]));
                case "FIND" -> {
                    String id = words[1];
                    String route = words[2];
                    Set<String> found = new HashSet<>(Set.of(id));
                    for (String step : route.split("\\.")) {
                        String requiredSex = switch (step) {
                            case "father", "son", "brother", "husband" -> "M";
                            case "mother", "daughter", "sister", "wife" -> "F";
                            default -> null;
                        };
                        Set<String> next = new HashSet<>();
                        for (String current : found) {
                            Collection<String> candidates = switch (step) {
                                case "parent", "father", "mother" -> person(current).parents;
                                case "child", "son", "daughter" -> children(current);
                                case "sibling", "brother", "sister" -> people.keySet().stream()
                                        .filter(other -> siblings(current, other)).toList();
                                default -> spouse(current) == null ? List.of() : List.of(spouse(current));
                            };
                            for (String candidate : candidates) {
                                if (requiredSex == null || person(candidate).sex.equals(requiredSex)) next.add(candidate);
                            }
                        }
                        found = next;
                    }
                    found.remove(id);
                    List<String> ordered = new ArrayList<>(found);
                    ordered.sort(Comparator.naturalOrder());
                    output.add("FIND " + id + " " + route + " " + ordered.size());
                    for (String other : ordered) output.add("  " + other + ": " + relationshipString(other, id));
                }
                case "TERM" -> output.add("TERM " + words[1] + " " + words[2] + " " + words[3] + " "
                        + term(Integer.parseInt(words[1]), Integer.parseInt(words[2]), words[3]));
                case "STATS" -> {
                    long living = people.values().stream().filter(person -> person.death == null).count();
                    int links = people.values().stream().mapToInt(person -> person.parents.size()).sum();
                    long couples = marriages.stream().filter(marriage -> marriage.status.equals("current")).count();
                    long founders = people.values().stream().filter(person -> person.parents.isEmpty()).count();
                    Map<String, Integer> lengths = new HashMap<>();
                    int generations = people.keySet().stream().mapToInt(id -> longestChain(id, lengths)).max().orElse(0);
                    output.add("STATS persons=" + people.size() + " living=" + living + " links=" + links
                            + " couples=" + couples + " founders=" + founders + " generations=" + generations);
                }
                case "AUDIT" -> {
                    List<String> rows = new ArrayList<>();
                    for (Marriage marriage : marriages) {
                        if (apex(marriage.first, marriage.second) != null) {
                            rows.add("  marriage " + marriage.first + " " + marriage.second + " "
                                    + bloodTerm(marriage.first, marriage.second));
                        }
                    }
                    for (String id : idOrder()) {
                        Fraction coefficient = inbreeding(id);
                        if (coefficient.numerator() != 0) rows.add("  inbred " + id + " " + coefficient);
                    }
                    output.add("AUDIT " + rows.size());
                    output.addAll(rows);
                }
            }
            if (before != null) history.add(new UndoEntry(line, before));
            return output;
        }
    }

    public static void main(String[] args) throws Exception {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in));
        BufferedWriter output = new BufferedWriter(new OutputStreamWriter(System.out));
        Family family = new Family();
        int count = Integer.parseInt(input.readLine());
        for (int index = 0; index < count; index++) {
            List<String> result;
            try {
                result = family.execute(input.readLine());
            } catch (CommandError error) {
                result = List.of("ERROR " + error.getMessage());
            }
            for (String line : result) {
                output.write(line);
                output.newLine();
            }
        }
        output.flush();
    }
}
