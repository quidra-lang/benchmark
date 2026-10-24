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
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.function.Predicate;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class Main {
    private static final List<String> TYPES = List.of("BUG", "TASK", "STORY");
    private static final List<String> PRIORITIES = List.of("LOW", "MEDIUM", "HIGH", "CRITICAL");
    private static final Map<String, List<String>> WORKFLOWS = Map.of(
            "BUG", List.of("OPEN", "TRIAGED", "IN_PROGRESS", "REVIEW", "RESOLVED", "CLOSED", "REOPENED"),
            "TASK", List.of("OPEN", "IN_PROGRESS", "DONE"),
            "STORY", List.of("BACKLOG", "READY", "IN_PROGRESS", "REVIEW", "DONE"));
    private static final Map<String, Set<String>> TRANSITIONS = Map.of(
            "BUG", Set.of("OPEN>TRIAGED", "TRIAGED>IN_PROGRESS", "IN_PROGRESS>REVIEW", "REVIEW>IN_PROGRESS",
                    "REVIEW>RESOLVED", "RESOLVED>CLOSED", "RESOLVED>REOPENED", "CLOSED>REOPENED", "REOPENED>IN_PROGRESS"),
            "TASK", Set.of("OPEN>IN_PROGRESS", "IN_PROGRESS>OPEN", "IN_PROGRESS>DONE"),
            "STORY", Set.of("BACKLOG>READY", "READY>BACKLOG", "READY>IN_PROGRESS", "IN_PROGRESS>REVIEW",
                    "REVIEW>IN_PROGRESS", "REVIEW>DONE"));
    private static final Set<String> EQUALITY = Set.of("=", "!=");
    private static final Set<String> ORDERED = Set.of("=", "!=", "<", "<=", ">", ">=");
    private static final Map<String, Set<String>> FIELD_OPERATORS = Map.ofEntries(
            Map.entry("id", ORDERED), Map.entry("type", EQUALITY), Map.entry("status", EQUALITY),
            Map.entry("priority", ORDERED), Map.entry("assignee", EQUALITY), Map.entry("reviewer", EQUALITY),
            Map.entry("estimate", ORDERED), Map.entry("sprint", EQUALITY), Map.entry("comments", ORDERED),
            Map.entry("blocked", EQUALITY), Map.entry("done", EQUALITY), Map.entry("title", Set.of("~")));

    private static final class CommandError extends RuntimeException {
        CommandError(String message) { super(message); }
    }

    private static String display(Object value) { return value == null ? "-" : value.toString(); }
    private static String yesNo(boolean value) { return value ? "yes" : "no"; }
    private static String numberList(Collection<Integer> numbers) {
        return numbers.isEmpty() ? "-" : String.join(",", numbers.stream().sorted().map(String::valueOf).toList());
    }

    private static final class Issue {
        final int number;
        final String type;
        final String title;
        String priority;
        String state;
        String assignee;
        String reviewer;
        Integer estimate;
        String sprint;
        int comments;
        final Set<Integer> blocks = new HashSet<>();
        final Set<Integer> blockers = new HashSet<>();
        Integer duplicate;
        final Set<Integer> duplicates = new HashSet<>();
        final List<String> history = new ArrayList<>();

        Issue(int number, String type, String priority, String title) {
            this.number = number;
            this.type = type;
            this.priority = priority;
            this.title = title;
            state = WORKFLOWS.get(type).get(0);
        }

        boolean done() { return Set.of("RESOLVED", "CLOSED", "DONE").contains(state); }
        int points() { return estimate == null ? 0 : estimate; }
        int level() { return PRIORITIES.indexOf(priority); }
    }

    private static final class Sprint {
        final String name;
        String phase = "PLANNED";
        int start;
        int end;
        int velocity;
        final Map<Integer, Integer> records = new HashMap<>();
        Sprint(String name) { this.name = name; }
    }

    private static final class QueryParser {
        final List<String> tokens;
        final List<Predicate<Issue>> conditions;
        int position;

        QueryParser(List<String> tokens, List<Predicate<Issue>> conditions) {
            this.tokens = tokens;
            this.conditions = conditions;
        }

        boolean accept(String token) {
            if (position >= tokens.size() || !tokens.get(position).equals(token)) return false;
            position++;
            return true;
        }

        Predicate<Issue> expression() {
            Predicate<Issue> node = term();
            while (accept("OR")) node = node.or(term());
            return node;
        }

        Predicate<Issue> term() {
            Predicate<Issue> node = factor();
            while (accept("AND")) node = node.and(factor());
            return node;
        }

        Predicate<Issue> factor() {
            if (accept("NOT")) return factor().negate();
            if (accept("(")) {
                Predicate<Issue> node = expression();
                accept(")");
                return node;
            }
            return conditions.get(position++);
        }
    }

    private static final class Tracker {
        int day = 1;
        final Set<String> users = new HashSet<>();
        final Map<Integer, Issue> issues = new HashMap<>();
        final Map<String, Sprint> sprints = new LinkedHashMap<>();

        Issue issue(String text) {
            Issue issue = issues.get(Integer.parseInt(text));
            if (issue == null) throw new CommandError("unknown issue");
            return issue;
        }

        Sprint sprint(String name) {
            Sprint sprint = sprints.get(name);
            if (sprint == null) throw new CommandError("unknown sprint");
            return sprint;
        }

        String user(String spec) {
            if (spec.equals("-")) return null;
            if (!users.contains(spec)) throw new CommandError("unknown user");
            return spec;
        }

        void notDone(Issue issue) { if (issue.done()) throw new CommandError("issue done"); }
        List<Issue> orderedIssues() { return issues.values().stream().sorted(Comparator.comparingInt(i -> i.number)).toList(); }
        List<Integer> unfinished(Issue issue) {
            return issue.blockers.stream().filter(number -> !issues.get(number).done()).sorted().toList();
        }
        boolean blocked(Issue issue) { return !issue.done() && !unfinished(issue).isEmpty(); }
        long wip(String user) {
            return issues.values().stream().filter(i -> Objects.equals(i.assignee, user) && i.state.equals("IN_PROGRESS")).count();
        }
        Sprint activeSprint() {
            return sprints.values().stream().filter(s -> s.phase.equals("ACTIVE")).findFirst().orElse(null);
        }
        List<Issue> members(Sprint sprint) {
            return orderedIssues().stream().filter(i -> sprint.name.equals(i.sprint)).toList();
        }
        int remaining(Sprint sprint) { return members(sprint).stream().filter(i -> !i.done()).mapToInt(Issue::points).sum(); }
        String summary(Sprint sprint) {
            List<Issue> members = members(sprint);
            return "issues " + members.size() + " points " + members.stream().mapToInt(Issue::points).sum();
        }
        void record(Issue issue, String content) { issue.history.add("day " + day + " " + content); }
        Map<Integer, Boolean> blockedBefore(Collection<Integer> numbers) {
            Map<Integer, Boolean> result = new HashMap<>();
            for (int number : numbers) result.put(number, blocked(issues.get(number)));
            return result;
        }
        void notify(Map<Integer, Boolean> before, List<String> output) {
            for (int number : before.keySet().stream().sorted().toList()) {
                boolean after = blocked(issues.get(number));
                if (after != before.get(number)) output.add((after ? "BLOCKED " : "UNBLOCKED ") + number);
            }
        }
        void changeState(Issue issue, String target, List<String> output) {
            Map<Integer, Boolean> before = blockedBefore(issue.blocks);
            output.add("MOVE " + issue.number + " " + issue.state + " " + target);
            record(issue, "MOVE " + issue.state + " " + target);
            issue.state = target;
            notify(before, output);
        }
        boolean reaches(int start, int goal) {
            ArrayDeque<Integer> pending = new ArrayDeque<>();
            Set<Integer> visited = new HashSet<>();
            pending.add(start);
            while (!pending.isEmpty()) {
                int number = pending.removeFirst();
                if (number == goal) return true;
                if (visited.add(number)) pending.addAll(issues.get(number).blocks);
            }
            return false;
        }

        boolean compare(Integer actual, Integer expected, String operator) {
            if (operator.equals("=")) return Objects.equals(actual, expected);
            if (operator.equals("!=")) return !Objects.equals(actual, expected);
            if (actual == null) return false;
            return switch (operator) {
                case "<" -> actual < expected;
                case "<=" -> actual <= expected;
                case ">" -> actual > expected;
                default -> actual >= expected;
            };
        }

        Predicate<Issue> condition(String token) {
            int length = 0;
            while (length < token.length() && token.charAt(length) >= 'a' && token.charAt(length) <= 'z') length++;
            String field = token.substring(0, length);
            String rest = token.substring(length);
            String operator = null;
            for (String candidate : List.of(">=", "<=", "!=", "=", "<", ">", "~")) {
                if (rest.startsWith(candidate)) { operator = candidate; break; }
            }
            String text = operator == null ? "" : rest.substring(operator.length());
            if (field.isEmpty() || operator == null || text.isEmpty()) throw new CommandError("syntax near " + token);
            Set<String> operators = FIELD_OPERATORS.get(field);
            if (operators == null) throw new CommandError("unknown field " + field);
            if (!operators.contains(operator)) throw new CommandError("bad operator " + token);
            boolean none = text.equals("-") && Set.of("assignee", "reviewer", "estimate", "sprint").contains(field)
                    && EQUALITY.contains(operator);
            Integer numeric = null;
            String string = none ? null : text;
            boolean valid;
            switch (field) {
                case "id", "estimate", "comments" -> {
                    valid = none || text.matches("[0-9]{1,6}");
                    if (valid && !none) numeric = Integer.valueOf(text);
                }
                case "priority" -> {
                    valid = PRIORITIES.contains(text);
                    if (valid) numeric = PRIORITIES.indexOf(text);
                }
                case "type" -> valid = TYPES.contains(text);
                case "status" -> valid = WORKFLOWS.values().stream().anyMatch(states -> states.contains(text));
                case "assignee", "reviewer" -> valid = none || users.contains(text);
                case "sprint" -> valid = none || sprints.containsKey(text);
                case "blocked", "done" -> valid = text.equals("yes") || text.equals("no");
                case "title" -> { string = text.toLowerCase(Locale.ROOT); valid = true; }
                default -> valid = false;
            }
            if (!valid) throw new CommandError("bad value " + token);
            Integer expectedNumber = numeric;
            String expectedString = string;
            String comparison = operator;
            return issue -> {
                if (Set.of("id", "estimate", "comments", "priority").contains(field)) {
                    Integer actual = switch (field) {
                        case "id" -> issue.number;
                        case "estimate" -> issue.estimate;
                        case "comments" -> issue.comments;
                        default -> issue.level();
                    };
                    return compare(actual, expectedNumber, comparison);
                }
                String actual = switch (field) {
                    case "type" -> issue.type;
                    case "status" -> issue.state;
                    case "assignee" -> issue.assignee;
                    case "reviewer" -> issue.reviewer;
                    case "sprint" -> issue.sprint;
                    case "blocked" -> yesNo(blocked(issue));
                    case "done" -> yesNo(issue.done());
                    default -> issue.title.toLowerCase(Locale.ROOT);
                };
                return switch (comparison) {
                    case "~" -> actual.contains(expectedString);
                    case "=" -> Objects.equals(actual, expectedString);
                    default -> !Objects.equals(actual, expectedString);
                };
            };
        }

        void query(String text, List<String> output) {
            List<String> tokens = new ArrayList<>();
            Matcher matcher = Pattern.compile("[()]|[^ ()]+").matcher(text);
            while (matcher.find()) tokens.add(matcher.group());
            List<Predicate<Issue>> conditions = new ArrayList<>();
            boolean operand = true;
            int depth = 0;
            for (String token : tokens) {
                Predicate<Issue> predicate = null;
                if (operand) {
                    switch (token) {
                        case "NOT" -> { }
                        case "(" -> depth++;
                        case "AND", "OR", ")" -> throw new CommandError("syntax near " + token);
                        default -> { predicate = condition(token); operand = false; }
                    }
                } else {
                    switch (token) {
                        case "AND", "OR" -> operand = true;
                        case ")" -> {
                            if (depth == 0) throw new CommandError("syntax near " + token);
                            depth--;
                        }
                        default -> throw new CommandError("syntax near " + token);
                    }
                }
                conditions.add(predicate);
            }
            if (operand || depth != 0) throw new CommandError("syntax at end");
            Predicate<Issue> predicate = new QueryParser(tokens, conditions).expression();
            List<Issue> matches = issues.values().stream().filter(predicate)
                    .sorted(Comparator.comparingInt(Issue::level).reversed().thenComparingInt(i -> i.number)).toList();
            output.add("QUERY " + matches.size());
            for (Issue issue : matches) output.add(issue.number + " " + issue.type + " " + issue.priority + " " + issue.state
                    + " " + display(issue.assignee) + " " + display(issue.estimate) + " " + issue.title);
        }

        void sprintCommand(String[] words, List<String> output) {
            String action = words[1];
            String name = words[2];
            if (action.equals("NEW")) {
                if (sprints.containsKey(name)) throw new CommandError("sprint exists");
                sprints.put(name, new Sprint(name));
                output.add("SPRINT NEW " + name);
                return;
            }
            Sprint sprint = sprint(name);
            switch (action) {
                case "ADD", "REMOVE" -> {
                    Issue issue = issue(words[3]);
                    if (sprint.phase.equals("ENDED")) throw new CommandError("sprint ended");
                    if (action.equals("ADD")) {
                        notDone(issue);
                        if (issue.sprint != null && !sprints.get(issue.sprint).phase.equals("ENDED")) throw new CommandError("in sprint " + issue.sprint);
                        if (issue.state.equals("BACKLOG")) throw new CommandError("not ready");
                        issue.sprint = name;
                    } else {
                        if (!name.equals(issue.sprint)) throw new CommandError("not in sprint");
                        notDone(issue);
                        issue.sprint = null;
                    }
                    record(issue, "SPRINT " + action + " " + name);
                    output.add("SPRINT " + action + " " + name + " " + issue.number + " " + summary(sprint));
                }
                case "START" -> {
                    if (!sprint.phase.equals("PLANNED")) throw new CommandError("sprint not planned");
                    Sprint active = activeSprint();
                    if (active != null) throw new CommandError("sprint active " + active.name);
                    if (members(sprint).isEmpty()) throw new CommandError("sprint empty");
                    sprint.phase = "ACTIVE";
                    sprint.start = day;
                    sprint.records.put(day, remaining(sprint));
                    output.add("SPRINT START " + name + " day " + day + " " + summary(sprint) + " remaining " + remaining(sprint));
                }
                case "END" -> {
                    if (!sprint.phase.equals("ACTIVE")) throw new CommandError("sprint not active");
                    sprint.records.put(day, remaining(sprint));
                    List<Issue> members = members(sprint);
                    List<Issue> finished = members.stream().filter(Issue::done).toList();
                    List<Issue> returned = members.stream().filter(i -> !i.done()).toList();
                    sprint.velocity = finished.stream().mapToInt(Issue::points).sum();
                    sprint.phase = "ENDED";
                    sprint.end = day;
                    output.add("SPRINT END " + name + " day " + day + " velocity " + sprint.velocity
                            + " done " + finished.size() + " returned " + returned.size());
                    for (Issue issue : returned) {
                        issue.sprint = null;
                        record(issue, "SPRINT RETURN " + name);
                        output.add("RETURNED " + issue.number);
                    }
                }
            }
        }

        void process(String line, List<String> output) {
            String[] words = line.split(" ");
            String command = words[0];
            switch (command) {
                case "DAY" -> {
                    int next = Integer.parseInt(words[1]);
                    if (next < day) throw new CommandError("day backwards");
                    day = next;
                    output.add("DAY " + day);
                }
                case "USER" -> {
                    if (!users.add(words[1])) throw new CommandError("user exists");
                    output.add("USER " + words[1]);
                }
                case "CREATE" -> {
                    int number = Integer.parseInt(words[1]);
                    if (issues.containsKey(number)) throw new CommandError("issue exists");
                    if (!TYPES.contains(words[2])) throw new CommandError("bad type");
                    if (!PRIORITIES.contains(words[3])) throw new CommandError("bad priority");
                    Issue issue = new Issue(number, words[2], words[3], String.join(" ", Arrays.copyOfRange(words, 4, words.length)));
                    issues.put(number, issue);
                    record(issue, "CREATE " + issue.type + " " + issue.priority);
                    output.add("CREATE " + number + " " + issue.type + " " + issue.priority + " " + issue.state);
                }
                case "PRIORITY" -> {
                    Issue issue = issue(words[1]);
                    String priority = words[2];
                    if (!PRIORITIES.contains(priority)) throw new CommandError("bad priority");
                    notDone(issue);
                    if (priority.equals(issue.priority)) throw new CommandError("no change");
                    String old = issue.priority;
                    issue.priority = priority;
                    record(issue, "PRIORITY " + old + " " + priority);
                    output.add("PRIORITY " + issue.number + " " + old + " " + priority);
                }
                case "ASSIGN", "REVIEWER" -> {
                    Issue issue = issue(words[1]);
                    String spec = words[2];
                    String user = user(spec);
                    notDone(issue);
                    String old = command.equals("ASSIGN") ? issue.assignee : issue.reviewer;
                    if (Objects.equals(old, user)) throw new CommandError("no change");
                    if (command.equals("ASSIGN")) {
                        if (user == null && Set.of("IN_PROGRESS", "REVIEW").contains(issue.state)) throw new CommandError("assignee required");
                        if (issue.state.equals("IN_PROGRESS") && wip(user) >= 3) throw new CommandError("wip limit " + spec);
                        if (issue.state.equals("REVIEW") && Objects.equals(user, issue.reviewer)) throw new CommandError("reviewer is assignee");
                        issue.assignee = user;
                    } else {
                        if (user == null && issue.state.equals("REVIEW")) throw new CommandError("reviewer required");
                        if (issue.state.equals("REVIEW") && Objects.equals(user, issue.assignee)) throw new CommandError("reviewer is assignee");
                        issue.reviewer = user;
                    }
                    record(issue, command + " " + spec);
                    output.add(command + " " + issue.number + " " + spec);
                }
                case "ESTIMATE" -> {
                    Issue issue = issue(words[1]);
                    int points = Integer.parseInt(words[2]);
                    if (!Set.of(0, 1, 2, 3, 5, 8, 13, 21).contains(points)) throw new CommandError("bad estimate");
                    notDone(issue);
                    if (Objects.equals(issue.estimate, points)) throw new CommandError("no change");
                    String old = display(issue.estimate);
                    issue.estimate = points;
                    record(issue, "ESTIMATE " + old + " " + points);
                    output.add("ESTIMATE " + issue.number + " " + old + " " + points);
                }
                case "COMMENT" -> {
                    Issue issue = issue(words[1]);
                    user(words[2]);
                    issue.comments++;
                    record(issue, "COMMENT " + words[2] + " " + String.join(" ", Arrays.copyOfRange(words, 3, words.length)));
                    output.add("COMMENT " + issue.number + " " + issue.comments);
                }
                case "MOVE" -> {
                    Issue issue = issue(words[1]);
                    String target = words[2];
                    if (issue.duplicate != null) throw new CommandError("duplicate of " + issue.duplicate);
                    if (!WORKFLOWS.get(issue.type).contains(target)) throw new CommandError("bad state");
                    if (!TRANSITIONS.get(issue.type).contains(issue.state + ">" + target)) throw new CommandError("cannot move " + issue.state + " to " + target);
                    if (target.equals("IN_PROGRESS")) {
                        Sprint active = activeSprint();
                        if (issue.type.equals("STORY") && (active == null || !active.name.equals(issue.sprint))) throw new CommandError("not in active sprint");
                        if (issue.assignee == null) throw new CommandError("no assignee");
                        if (wip(issue.assignee) >= 3) throw new CommandError("wip limit " + issue.assignee);
                    }
                    if (target.equals("REVIEW")) {
                        if (issue.reviewer == null) throw new CommandError("no reviewer");
                        if (issue.reviewer.equals(issue.assignee)) throw new CommandError("reviewer is assignee");
                    }
                    if (Set.of("DONE", "RESOLVED").contains(target) && !unfinished(issue).isEmpty()) {
                        throw new CommandError("blocked by " + unfinished(issue).get(0));
                    }
                    if (target.equals("READY") && issue.estimate == null) throw new CommandError("no estimate");
                    changeState(issue, target, output);
                }
                case "LINK", "UNLINK" -> {
                    String relation = words[2];
                    if (!(command.equals("LINK") ? Set.of("BLOCKS", "DUPLICATES") : Set.of("BLOCKS")).contains(relation)) throw new CommandError("bad link");
                    Issue source = issue(words[1]);
                    Issue target = issue(words[3]);
                    if (command.equals("UNLINK")) {
                        if (!source.blocks.contains(target.number)) throw new CommandError("no link");
                        Map<Integer, Boolean> before = blockedBefore(List.of(target.number));
                        source.blocks.remove(target.number);
                        target.blockers.remove(source.number);
                        record(source, "UNLINK BLOCKS " + target.number);
                        record(target, "UNLINK BLOCKED_BY " + source.number);
                        output.add("UNLINK " + source.number + " BLOCKS " + target.number);
                        notify(before, output);
                    } else {
                        if (source == target) throw new CommandError("self link");
                        if (relation.equals("BLOCKS")) {
                            if (source.blocks.contains(target.number)) throw new CommandError("link exists");
                            if (reaches(target.number, source.number)) throw new CommandError("cycle");
                            notDone(target);
                            Map<Integer, Boolean> before = blockedBefore(List.of(target.number));
                            source.blocks.add(target.number);
                            target.blockers.add(source.number);
                            record(source, "LINK BLOCKS " + target.number);
                            record(target, "LINK BLOCKED_BY " + source.number);
                            output.add("LINK " + source.number + " BLOCKS " + target.number);
                            notify(before, output);
                        } else {
                            if (!source.type.equals(target.type)) throw new CommandError("type mismatch");
                            notDone(source);
                            if (target.duplicate != null) throw new CommandError("target is duplicate");
                            source.duplicate = target.number;
                            target.duplicates.add(source.number);
                            record(source, "LINK DUPLICATES " + target.number);
                            record(target, "LINK DUPLICATED_BY " + source.number);
                            output.add("LINK " + source.number + " DUPLICATES " + target.number);
                            changeState(source, source.type.equals("BUG") ? "CLOSED" : "DONE", output);
                            if (source.sprint != null && !sprints.get(source.sprint).phase.equals("ENDED")) {
                                record(source, "SPRINT REMOVE " + source.sprint);
                                source.sprint = null;
                            }
                        }
                    }
                }
                case "SPRINT" -> sprintCommand(words, output);
                case "QUERY" -> query(String.join(" ", Arrays.copyOfRange(words, 1, words.length)), output);
                case "SHOW" -> {
                    Issue issue = issue(words[1]);
                    output.add("ISSUE " + issue.number + " " + issue.type + " " + issue.priority + " " + issue.state + " blocked " + yesNo(blocked(issue)));
                    output.add("TITLE " + issue.title);
                    output.add("PEOPLE assignee " + display(issue.assignee) + " reviewer " + display(issue.reviewer));
                    output.add("PLAN estimate " + display(issue.estimate) + " sprint " + display(issue.sprint) + " comments " + issue.comments);
                    output.add("LINKS blocks " + numberList(issue.blocks) + " blocked_by " + numberList(issue.blockers)
                            + " duplicate_of " + display(issue.duplicate) + " duplicated_by " + numberList(issue.duplicates));
                }
                case "HISTORY" -> {
                    Issue issue = issue(words[1]);
                    output.add("HISTORY " + issue.number + " " + issue.history.size());
                    output.addAll(issue.history);
                }
                case "BOARD" -> {
                    output.add("BOARD");
                    for (String type : TYPES) {
                        StringBuilder row = new StringBuilder(type);
                        for (String state : WORKFLOWS.get(type)) row.append(' ').append(state).append(' ')
                                .append(issues.values().stream().filter(i -> i.type.equals(type) && i.state.equals(state)).count());
                        output.add(row.toString());
                    }
                    long done = issues.values().stream().filter(Issue::done).count();
                    output.add("TOTAL " + issues.size() + " open " + (issues.size() - done) + " done " + done);
                }
                case "WORKLOAD" -> {
                    output.add("WORKLOAD " + users.size());
                    for (String user : users.stream().sorted().toList()) {
                        List<Issue> assigned = issues.values().stream().filter(i -> user.equals(i.assignee) && !i.done()).toList();
                        output.add(user + " assigned " + assigned.size() + " in_progress " + assigned.stream().filter(i -> i.state.equals("IN_PROGRESS")).count()
                                + " review " + assigned.stream().filter(i -> i.state.equals("REVIEW")).count()
                                + " reviewing " + issues.values().stream().filter(i -> user.equals(i.reviewer) && i.state.equals("REVIEW")).count()
                                + " points " + assigned.stream().mapToInt(Issue::points).sum());
                    }
                }
                case "SPRINTS" -> {
                    output.add("SPRINTS " + sprints.size());
                    for (Sprint sprint : sprints.values()) output.add(switch (sprint.phase) {
                        case "PLANNED" -> sprint.name + " PLANNED " + summary(sprint);
                        case "ACTIVE" -> sprint.name + " ACTIVE start " + sprint.start + " " + summary(sprint) + " remaining " + remaining(sprint);
                        default -> sprint.name + " ENDED start " + sprint.start + " end " + sprint.end + " velocity " + sprint.velocity;
                    });
                }
                case "BURNDOWN" -> {
                    Sprint sprint = sprint(words[1]);
                    if (sprint.phase.equals("PLANNED")) throw new CommandError("sprint not started");
                    int last = sprint.phase.equals("ACTIVE") ? day : sprint.end;
                    output.add("BURNDOWN " + sprint.name + " " + sprint.phase + " days " + (last - sprint.start + 1));
                    int value = 0;
                    for (int recordDay = sprint.start; recordDay <= last; recordDay++) {
                        value = sprint.records.getOrDefault(recordDay, value);
                        output.add("day " + recordDay + " " + value);
                    }
                }
            }
        }

        List<String> execute(String line) {
            List<String> output = new ArrayList<>();
            try { process(line, output); }
            catch (CommandError error) { output.add("ERROR " + error.getMessage()); }
            Sprint active = activeSprint();
            if (active != null) active.records.put(day, remaining(active));
            return output;
        }
    }

    public static void main(String[] args) throws Exception {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in));
        BufferedWriter output = new BufferedWriter(new OutputStreamWriter(System.out));
        Tracker tracker = new Tracker();
        int count = Integer.parseInt(input.readLine());
        for (int index = 0; index < count; index++) {
            for (String line : tracker.execute(input.readLine())) {
                output.write(line);
                output.newLine();
            }
        }
        output.flush();
    }
}
