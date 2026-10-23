import java.io.*;
import java.util.*;

public class Main {
    static class ExpansionError extends RuntimeException {
        ExpansionError(String message) {
            super(message);
        }
    }

    static class AbortBuild extends RuntimeException { }

    static void error(String message) {
        throw new ExpansionError(message);
    }

    static String leftTrim(String text) {
        int i = 0;
        while (i < text.length() && text.charAt(i) == ' ') i++;
        return text.substring(i);
    }

    static String rightTrim(String text) {
        int i = text.length();
        while (i > 0 && text.charAt(i - 1) == ' ') i--;
        return text.substring(0, i);
    }

    static String trim(String text) {
        return rightTrim(leftTrim(text));
    }

    static List<String> words(String text) {
        String value = trim(text);
        return value.isEmpty() ? new ArrayList<>() : new ArrayList<>(Arrays.asList(value.split(" +")));
    }

    static List<String> unique(Collection<String> values) {
        return new ArrayList<>(new LinkedHashSet<>(values));
    }

    static boolean numeric(String text) {
        return !text.isEmpty() && text.chars().allMatch(c -> c >= '0' && c <= '9');
    }

    static String stem(String pattern, String word) {
        int p = pattern.indexOf('%');
        if (p < 0) return pattern.equals(word) ? "" : null;
        String prefix = pattern.substring(0, p), suffix = pattern.substring(p + 1);
        return word.length() >= prefix.length() + suffix.length() && word.startsWith(prefix) && word.endsWith(suffix) ? word.substring(prefix.length(), word.length() - suffix.length()) : null;
    }

    static String substitute(String pattern, String value) {
        int p = pattern.indexOf('%');
        return p < 0 ? pattern : pattern.substring(0, p) + value + pattern.substring(p + 1);
    }

    static String replacement(String word, String pattern, String value) {
        String s = stem(pattern, word);
        return s == null ? word : pattern.contains("%") ? substitute(value, s) : value;
    }

    static boolean wildcard(String pattern, String name) {
        boolean[][] match = new boolean[pattern.length() + 1][name.length() + 1];
        match[0][0] = true;
        for (int i = 0; i < pattern.length(); i++) for (int j = 0; j <= name.length(); j++) if (match[i][j]) {
            char c = pattern.charAt(i);
            if (c == '*') {
                match[i + 1][j] = true;
                if (j < name.length() && name.charAt(j) != '/') match[i][j + 1] = true;
            } else if (j < name.length() && (c == '?' ? name.charAt(j) != '/' : c == name.charAt(j))) match[i + 1][j + 1] = true;
        }
        return match[pattern.length()][name.length()];
    }

    record Variable(boolean simple, String value) { }

    record RecipeLine(int number, String text) { }

    static class Recipe {
        List<RecipeLine> lines = new ArrayList<>();
    }

    static class Rule {
        String name, stem = "";
        boolean pattern;
        List<String> prerequisites = new ArrayList<>();
        Recipe recipe;
        Rule(String name, boolean pattern) {
            this.name = name;
            this.pattern = pattern;
        }
    }

    static class Group {
        List<Rule> rules = new ArrayList<>();
        Recipe recipe;
    }

    static class Condition {
        boolean outer, value, alternative;
        int line;
        Condition(boolean outer, boolean value, int line) {
            this.outer = outer;
            this.value = value;
            this.line = line;
        }
    }

    static class Scope {
        String name, value;
        List<String> arguments;
        Scope(String name, String value) {
            this.name = name;
            this.value = value;
        }
        Scope(List<String> arguments) {
            this.arguments = arguments;
        }
    }
    TreeMap<String, Integer> files = new TreeMap<>();
    int clock;
    TreeMap<String, Variable> variables = new TreeMap<>();
    TreeMap<String, Rule> rules = new TreeMap<>();
    List<Rule> patterns = new ArrayList<>();
    Set<String> phony = new TreeSet<>();
    boolean loaded;
    String goal, location = "make";
    List<Scope> scopes = new ArrayList<>();
    Set<String> expanding = new HashSet<>();
    Map<String, String> automatic;
    List<String> output = new ArrayList<>();
    static final Map<String, int[]> FUNCTIONS = new HashMap<>();

    static {
        for (String name : List.of("strip", "sort", "words", "firstword", "lastword", "dir", "notdir", "suffix", "basename", "wildcard", "value", "info", "warning", "error")) FUNCTIONS.put(name, new int[]{1, 1});
        for (String name : List.of("findstring", "filter", "filter-out", "word", "addsuffix", "addprefix")) FUNCTIONS.put(name, new int[]{2, 2});
        for (String name : List.of("subst", "patsubst", "wordlist", "foreach")) FUNCTIONS.put(name, new int[]{3, 3});
        FUNCTIONS.put("if", new int[]{2, 3});
        FUNCTIONS.put("call", new int[]{1, Integer.MAX_VALUE});
    }

    void newTime(String name) {
        files.put(name, ++clock);
    }

    void discard() {
        loaded = false;
        variables.clear();
        rules.clear();
        patterns.clear();
        phony.clear();
        goal = null;
    }

    void expansionMessage(ExpansionError e) {
        output.add(location + ": *** " + e.getMessage() + ".  Stop.");
    }

    void cleanExpansion() {
        scopes.clear();
        expanding.clear();
        automatic = null;
        location = "make";
    }

    List<String> wildcardExpansion(String pattern) {
        if (!pattern.contains("*") && !pattern.contains("?")) return files.containsKey(pattern) ? new ArrayList<>(List.of(pattern)) : new ArrayList<>();
        return files.keySet().stream().filter(name -> wildcard(pattern, name)).toList();
    }

    int bracketEnd(String text, int opening) {
        char open = text.charAt(opening), close = open == '(' ? ')' : '}';
        int depth = 0;
        for (int i = opening; i < text.length(); i++) {
            if (text.charAt(i) == open) depth++;
            else if (text.charAt(i) == close) {
                depth--;
                if (depth == 0) return i;
            }
        }
        error("unterminated variable reference");
        return -1;
    }

    String expand(String text) {
        StringBuilder result = new StringBuilder();
        for (int i = 0; i < text.length();) {
            char c = text.charAt(i++);
            if (c != '$') {
                result.append(c);
                continue;
            }
            if (i == text.length()) break;
            c = text.charAt(i++);
            if (c == '$') result.append('$');
            else if (c == '(' || c == '{') {
                int end = bracketEnd(text, i - 1);
                result.append(reference(text.substring(i, end), c));
                i = end + 1;
            } else result.append(value(Character.toString(c)));
        }
        return result.toString();
    }

    String value(String name) {
        for (int i = scopes.size() - 1; i >= 0; i--) {
            Scope scope = scopes.get(i);
            if (scope.arguments == null) {
                if (scope.name.equals(name)) return scope.value;
            } else if (numeric(name)) {
                int index = Integer.parseInt(name);
                return index < scope.arguments.size() ? scope.arguments.get(index) : "";
            }
        }
        if (automatic != null && automatic.containsKey(name)) return automatic.get(name);
        Variable variable = variables.get(name);
        if (variable == null) return "";
        if (variable.simple) return variable.value;
        if (!expanding.add(name)) error("Recursive variable '" + name + "' references itself (eventually)");
        try {
            return expand(variable.value);
        } finally {
            expanding.remove(name);
        }
    }

    String reference(String content, char opening) {
        int first = content.indexOf(' ');
        if (first >= 0 && FUNCTIONS.containsKey(content.substring(0, first))) return function(content.substring(0, first), leftTrim(content.substring(first + 1)), opening);
        String name = expand(content);
        int colon = name.indexOf(':'), equal = colon < 0 ? -1 : name.indexOf('=', colon + 1);
        if (equal >= 0) {
            String pattern = name.substring(colon + 1, equal), replacementText = name.substring(equal + 1);
            if (!pattern.contains("%")) {
                pattern = "%" + pattern;
                replacementText = "%" + replacementText;
            }
            List<String> result = new ArrayList<>();
            for (String word : words(value(name.substring(0, colon)))) result.add(replacement(word, pattern, replacementText));
            return String.join(" ", result);
        }
        return value(name);
    }

    List<String> arguments(String text, int maximum, char opening) {
        char closing = opening == '(' ? ')' : '}';
        List<String> result = new ArrayList<>();
        int depth = 0, start = 0;
        for (int i = 0; i < text.length(); i++) {
            char c = text.charAt(i);
            if (c == opening) depth++;
            else if (c == closing) depth--;
            else if (c == ',' && depth == 0 && result.size() < maximum - 1) {
                result.add(text.substring(start, i));
                start = i + 1;
            }
        }
        result.add(text.substring(start));
        return result;
    }

    String function(String name, String text, char opening) {
        int[] limits = FUNCTIONS.get(name);
        List<String> raw = arguments(text, limits[1], opening);
        if (raw.size() < limits[0]) error("insufficient number of arguments (" + raw.size() + ") to function '" + name + "'");
        if (name.equals("foreach")) {
            String variable = trim(expand(raw.get(0)));
            List<String> list = words(expand(raw.get(1))), result = new ArrayList<>();
            for (String word : list) {
                scopes.add(new Scope(variable, word));
                try {
                    result.add(expand(raw.get(2)));
                } finally {
                    scopes.removeLast();
                }
            }
            return String.join(" ", result);
        }
        if (name.equals("if")) {
            boolean condition = !trim(expand(raw.get(0))).isEmpty();
            return condition ? expand(raw.get(1)) : raw.size() == 3 ? expand(raw.get(2)) : "";
        }
        List<String> a = new ArrayList<>();
        for (String arg : raw) {
            String v = expand(arg);
            a.add(name.equals("subst") || name.equals("call") ? v : trim(v));
        }
        if (name.equals("call")) {
            String variable = trim(a.getFirst());
            Variable v = variables.get(variable);
            if (v == null) return "";
            if (v.simple) return v.value;
            a.set(0, variable);
            scopes.add(new Scope(a));
            try {
                return expand(v.value);
            } finally {
                scopes.removeLast();
            }
        }
        if (name.equals("value")) {
            Variable v = variables.get(a.getFirst());
            return v == null ? "" : v.value;
        }
        if (name.equals("info")) {
            output.add(a.getFirst());
            return "";
        }
        if (name.equals("warning")) {
            output.add(location + ": " + a.getFirst());
            return "";
        }
        if (name.equals("error")) {
            error(a.getFirst());
            return "";
        }
        if (name.equals("subst")) return a.get(0).isEmpty() ? a.get(2) : a.get(2).replace(a.get(0), a.get(1));
        if (name.equals("findstring")) return a.get(1).contains(a.get(0)) ? a.get(0) : "";
        if (name.equals("word")) {
            String n = a.get(0);
            if (!numeric(n)) error("non-numeric first argument to 'word' function: '" + n + "'");
            int index = Integer.parseInt(n);
            if (index == 0) error("first argument to 'word' function must be greater than 0");
            List<String> list = words(a.get(1));
            return index <= list.size() ? list.get(index - 1) : "";
        }
        if (name.equals("wordlist")) {
            if (!numeric(a.get(0))) error("non-numeric first argument to 'wordlist' function: '" + a.get(0) + "'");
            if (!numeric(a.get(1))) error("non-numeric second argument to 'wordlist' function: '" + a.get(1) + "'");
            int start = Integer.parseInt(a.get(0)), end = Integer.parseInt(a.get(1));
            if (start == 0) error("invalid first argument to 'wordlist' function: '" + a.get(0) + "'");
            List<String> list = words(a.get(2));
            return start > end || start > list.size() ? "" : String.join(" ", list.subList(start - 1, Math.min(end, list.size())));
        }
        List<String> list = words(a.getLast()), result = new ArrayList<>();
        switch (name) {
            case "patsubst" -> {
                for (String word : list) result.add(replacement(word, a.get(0), a.get(1)));
            }
            case "filter", "filter-out" -> {
                List<String> filters = words(a.get(0));
                for (String word : list) {
                    boolean found = filters.stream().anyMatch(p -> stem(p, word) != null);
                    if (found == name.equals("filter")) result.add(word);
                }
            }
            case "strip" -> result.addAll(list);
            case "sort" -> result.addAll(new TreeSet<>(list));
            case "words" -> {
                return Integer.toString(list.size());
            }
            case "firstword" -> {
                return list.isEmpty() ? "" : list.getFirst();
            }
            case "lastword" -> {
                return list.isEmpty() ? "" : list.getLast();
            }
            case "dir", "notdir", "suffix", "basename" -> {
                for (String word : list) {
                    int slash = word.lastIndexOf('/'), dot = word.lastIndexOf('.');
                    boolean extension = dot > slash;
                    switch (name) {
                        case "dir" -> result.add(slash < 0 ? "./" : word.substring(0, slash + 1));
                        case "notdir" -> result.add(word.substring(slash + 1));
                        case "suffix" -> {
                            if (extension) result.add(word.substring(dot));
                        }
                        default -> result.add(extension ? word.substring(0, dot) : word);
                    }
                }
            }
            case "addsuffix" -> {
                for (String word : list) result.add(word + a.getFirst());
            }
            case "addprefix" -> {
                for (String word : list) result.add(a.getFirst() + word);
            }
            case "wildcard" -> {
                for (String word : list) result.addAll(wildcardExpansion(word));
            }
            default -> throw new IllegalStateException();
        }
        return String.join(" ", result);
    }

    int[] outside(String text) {
        int[] positions = {-1, -1, -1};
        for (int i = 0; i < text.length();) {
            char c = text.charAt(i);
            if (c == '$') {
                if (i + 1 < text.length() && (text.charAt(i + 1) == '(' || text.charAt(i + 1) == '{')) i = bracketEnd(text, i + 1) + 1;
                else i += Math.min(2, text.length() - i);
            } else {
                int k = c == '=' ? 0 : c == ':' ? 1 : c == ';' ? 2 : -1;
                if (k >= 0 && positions[k] < 0) positions[k] = i;
                i++;
            }
        }
        return positions;
    }

    Rule register(String target, List<String> prerequisites) {
        Rule rule = rules.computeIfAbsent(target, t -> new Rule(t, false));
        for (String p : unique(prerequisites)) if (!rule.prerequisites.contains(p)) rule.prerequisites.add(p);
        if (goal == null && !target.startsWith(".")) goal = target;
        return rule;
    }

    void addRecipe(Group group, int number, String text) {
        if (group.rules.isEmpty()) return;
        if (group.recipe == null) {
            group.recipe = new Recipe();
            for (Rule rule : group.rules) {
                if (!rule.pattern && rule.recipe != null) {
                    output.add("Makefile:" + number + ": warning: overriding recipe for target '" + rule.name + "'");
                    output.add("Makefile:" + rule.recipe.lines.getFirst().number + ": warning: ignoring old recipe for target '" + rule.name + "'");
                }
                rule.recipe = group.recipe;
            }
        }
        group.recipe.lines.add(new RecipeLine(number, text));
    }

    boolean active(List<Condition> conditions) {
        return conditions.isEmpty() || conditions.getLast().outer && conditions.getLast().value;
    }

    void conditional(String name, String rest, int line, List<Condition> conditions) {
        if (name.equals("else")) {
            if (conditions.isEmpty()) error("extraneous 'else'");
            Condition top = conditions.getLast();
            if (top.alternative) error("only one 'else' per conditional");
            top.value = !top.value;
            top.alternative = true;
            return;
        }
        if (name.equals("endif")) {
            if (conditions.isEmpty()) error("extraneous 'endif'");
            conditions.removeLast();
            return;
        }
        boolean outer = active(conditions), condition = false;
        if (outer) {
            if (name.equals("ifdef") || name.equals("ifndef")) {
                Variable v = variables.get(trim(expand(rest)));
                condition = v != null && !v.value.isEmpty();
                if (name.equals("ifndef")) condition = !condition;
            } else {
                if (rest.length() < 2 || !rest.startsWith("(") || !rest.endsWith(")")) error("invalid syntax in conditional");
                String inside = rest.substring(1, rest.length() - 1);
                int depth = 0, comma = -1;
                for (int i = 0; i < inside.length(); i++) {
                    char ch = inside.charAt(i);
                    if (ch == '(') depth++;
                    else if (ch == ')') depth--;
                    else if (ch == ',' && depth == 0) {
                        comma = i;
                        break;
                    }
                }
                if (comma < 0) error("invalid syntax in conditional");
                String a = trim(expand(inside.substring(0, comma))), b = trim(expand(inside.substring(comma + 1)));
                condition = a.equals(b);
                if (name.equals("ifneq")) condition = !condition;
            }
        }
        conditions.add(new Condition(outer, condition, line));
    }

    void load(List<String> body) {
        discard();
        Group current = null;
        List<Condition> conditions = new ArrayList<>();
        try {
            for (int i = 0; i < body.size(); i++) {
                int number = i + 1;
                location = "Makefile:" + number;
                String line = body.get(i);
                if (line.startsWith(">")) {
                    if (!active(conditions)) continue;
                    if (current == null) error("recipe commences before first target");
                    addRecipe(current, number, leftTrim(line.substring(1)));
                    continue;
                }
                while (line.endsWith("\\") && i + 1 < body.size()) line = rightTrim(line.substring(0, line.length() - 1)) + " " + leftTrim(body.get(++i));
                int comment = line.indexOf('#');
                String t = trim(comment < 0 ? line : line.substring(0, comment));
                int space = t.indexOf(' ');
                String first = space < 0 ? t : t.substring(0, space), rest = space < 0 ? "" : trim(t.substring(space + 1));
                if (List.of("ifeq", "ifneq", "ifdef", "ifndef", "else", "endif").contains(first)) {
                    conditional(first, rest, number, conditions);
                    continue;
                }
                if (t.isEmpty() || !active(conditions)) continue;
                int[] positions = outside(t);
                int equal = positions[0], colon = positions[1];
                if (equal >= 0 && (colon < 0 || colon >= equal - 1)) {
                    char op = equal > 0 && ":+?".indexOf(t.charAt(equal - 1)) >= 0 ? t.charAt(equal - 1) : '=';
                    String name = trim(t.substring(0, equal - (op == '=' ? 0 : 1))), rhs = trim(t.substring(equal + 1));
                    if (name.isEmpty()) error("empty variable name");
                    Variable old = variables.get(name);
                    if (op == ':') variables.put(name, new Variable(true, expand(rhs)));
                    else if (op == '+' && old != null) {
                        String add = old.simple ? expand(rhs) : rhs;
                        variables.put(name, new Variable(old.simple, old.value.isEmpty() ? add : old.value + " " + add));
                    } else if (op != '?' || old == null) variables.put(name, new Variable(false, rhs));
                    current = null;
                } else if (colon >= 0) {
                    List<String> targets = unique(words(expand(t.substring(0, colon))));
                    String r = t.substring(colon + 1), inline = null;
                    int semicolon = outside(r)[2];
                    if (semicolon >= 0) {
                        inline = leftTrim(r.substring(semicolon + 1));
                        r = r.substring(0, semicolon);
                    }
                    int staticColon = outside(r)[1];
                    String targetPattern = null;
                    if (staticColon >= 0) {
                        targetPattern = trim(expand(r.substring(0, staticColon)));
                        r = r.substring(staticColon + 1);
                    }
                    List<String> prerequisites = words(expand(r));
                    current = new Group();
                    if (targets.size() == 1 && targets.getFirst().equals(".PHONY")) phony.addAll(prerequisites);
                    else if (targetPattern != null) {
                        if (!targetPattern.contains("%")) error("target pattern contains no '%'");
                        for (String target : targets) {
                            String s = stem(targetPattern, target);
                            if (s == null || s.isEmpty()) output.add(location + ": target '" + target + "' doesn't match the target pattern");
                            else {
                                List<String> p = new ArrayList<>();
                                for (String q : prerequisites) p.add(substitute(q, s));
                                Rule rule = register(target, p);
                                rule.stem = s;
                                current.rules.add(rule);
                            }
                        }
                    } else if (targets.stream().anyMatch(p -> p.contains("%"))) {
                        if (targets.stream().anyMatch(p -> !p.contains("%"))) error("mixed implicit and normal rules");
                        for (String target : targets) {
                            Rule rule = new Rule(target, true);
                            rule.prerequisites.addAll(prerequisites);
                            patterns.add(rule);
                            current.rules.add(rule);
                        }
                    } else for (String target : targets) current.rules.add(register(target, prerequisites));
                    if (inline != null) addRecipe(current, number, inline);
                } else if (!trim(expand(t)).isEmpty()) error("missing separator");
            }
            if (!conditions.isEmpty()) {
                location = "Makefile:" + conditions.getLast().line;
                error("missing 'endif'");
            }
            loaded = true;
            output.add("Makefile loaded: lines=" + body.size() + " variables=" + variables.size() + " targets=" + rules.size() + " patterns=" + patterns.stream().filter(p -> p.recipe != null).count() + " goal=" + (goal == null ? "(none)" : goal));
        } catch (ExpansionError e) {
            expansionMessage(e);
            discard();
        } finally {
            cleanExpansion();
        }
    }

    static class Choice {
        List<String> prerequisites = new ArrayList<>();
        Recipe recipe;
        String stem = "";
        boolean source, missing;
    }

    Choice determine(String target) {
        Rule explicit = rules.get(target);
        Choice choice = new Choice();
        if (explicit != null && explicit.recipe != null) {
            choice.prerequisites.addAll(explicit.prerequisites);
            choice.recipe = explicit.recipe;
            choice.stem = explicit.stem;
            return choice;
        }
        if (!phony.contains(target)) {
            Rule best = null;
            String bestStem = null;
            for (Rule pattern : patterns) if (pattern.recipe != null) {
                String s = stem(pattern.name, target);
                if (s == null || s.isEmpty() || bestStem != null && s.length() >= bestStem.length()) continue;
                boolean usable = true;
                for (String p : pattern.prerequisites) {
                    String name = substitute(p, s);
                    if (!files.containsKey(name) && !rules.containsKey(name)) {
                        usable = false;
                        break;
                    }
                }
                if (usable) {
                    best = pattern;
                    bestStem = s;
                }
            }
            if (best != null) {
                for (String p : best.prerequisites) choice.prerequisites.add(substitute(p, bestStem));
                if (explicit != null) choice.prerequisites.addAll(explicit.prerequisites);
                choice.prerequisites = unique(choice.prerequisites);
                choice.recipe = best.recipe;
                choice.stem = bestStem;
                return choice;
            }
        }
        if (explicit != null || phony.contains(target)) {
            if (explicit != null) {
                choice.prerequisites.addAll(explicit.prerequisites);
                choice.stem = explicit.stem;
            }
            return choice;
        }
        if (files.containsKey(target)) choice.source = true;
        else choice.missing = true;
        return choice;
    }

    Integer targetTime(String target) {
        return phony.contains(target) ? null : files.get(target);
    }

    int execute(String command) {
        List<String> w = words(command);
        String c = w.getFirst();
        switch (c) {
            case "echo" -> {
                output.add(String.join(" ", w.subList(1, w.size())));
                return 0;
            }
            case "touch" -> {
                for (String name : w.subList(1, w.size())) newTime(name);
                return 0;
            }
            case "rm" -> {
                boolean force = w.size() > 1 && w.get(1).equals("-f");
                int status = 0;
                for (String pattern : w.subList(force ? 2 : 1, w.size())) {
                    List<String> names = wildcardExpansion(pattern);
                    if (names.isEmpty()) names = List.of(pattern);
                    for (String name : names) if (files.remove(name) == null && !force) {
                        output.add("rm: cannot remove '" + name + "': No such file or directory");
                        status = 1;
                    }
                }
                return status;
            }
            case "false" -> {
                return 1;
            }
            case "exit" -> {
                return w.size() > 1 ? Integer.parseInt(w.get(1)) : 0;
            }
            default -> {
                return 0;
            }
        }
    }
    class Build {
        Set<Character> options;
        Map<String, Integer> results = new HashMap<>();
        Map<String, Choice> choices = new HashMap<>();
        Set<String> building = new HashSet<>();
        int runs;
        Build(Set<Character> options) {
            this.options = options;
        }
        boolean has(char c) {
            return options.contains(c);
        }
        int target(String name, String parent) {
            if (results.containsKey(name)) return results.get(name);
            Choice choice = determine(name);
            choices.put(name, choice);
            if (choice.missing) {
                results.put(name, 1);
                output.add("make: *** No rule to make target '" + name + "'" + (parent == null ? "." : ", needed by '" + parent + "'.") + (has('k') ? "" : "  Stop."));
                if (!has('k')) throw new AbortBuild();
                return 1;
            }
            if (choice.source) {
                results.put(name, 0);
                return 0;
            }
            building.add(name);
            boolean failed = false;
            List<String> kept = new ArrayList<>();
            for (String p : choice.prerequisites) {
                if (building.contains(p)) output.add("make: Circular " + name + " <- " + p + " dependency dropped.");
                else {
                    kept.add(p);
                    if (target(p, name) != 0) failed = true;
                }
            }
            choice.prerequisites = kept;
            building.remove(name);
            int result = failed ? 2 : update(name, choice);
            results.put(name, result);
            return result;
        }
        int update(String target, Choice choice) {
            Integer old = targetTime(target);
            List<String> fresh = new ArrayList<>();
            for (String p : choice.prerequisites) {
                Integer time = targetTime(p);
                if (has('B') || old == null || time == null || time > old) fresh.add(p);
            }
            if (choice.recipe == null || !has('B') && old != null && fresh.isEmpty()) return 0;
            runs++;
            List<RecipeLine> expanded = new ArrayList<>();
            automatic = new HashMap<>();
            automatic.put("@", target);
            automatic.put("<", keptFirst(choice.prerequisites));
            automatic.put("^", String.join(" ", choice.prerequisites));
            automatic.put("?", String.join(" ", fresh));
            automatic.put("*", choice.stem);
            try {
                for (RecipeLine line : choice.recipe.lines) {
                    location = "Makefile:" + line.number;
                    expanded.add(new RecipeLine(line.number, expand(line.text)));
                }
            } finally {
                automatic = null;
            }
            for (RecipeLine line : expanded) {
                int i = 0;
                boolean silent = false, ignore = false;
                while (i < line.text.length() && " @-".indexOf(line.text.charAt(i)) >= 0) {
                    silent |= line.text.charAt(i) == '@';
                    ignore |= line.text.charAt(i) == '-';
                    i++;
                }
                String command = rightTrim(line.text.substring(i));
                if (command.isEmpty()) continue;
                if (has('n') || !silent && !has('s')) output.add(command);
                if (has('n')) continue;
                int status = execute(command);
                if (status != 0) {
                    if (ignore || has('i')) output.add("make: [Makefile:" + line.number + ": " + target + "] Error " + status + " (ignored)");
                    else {
                        output.add("make: *** [Makefile:" + line.number + ": " + target + "] Error " + status);
                        if (!has('k')) throw new AbortBuild();
                        return 1;
                    }
                }
            }
            if (!phony.contains(target)) newTime(target);
            return 0;
        }
    }

    static String keptFirst(List<String> list) {
        return list.isEmpty() ? "" : list.getFirst();
    }

    void make(String args) {
        List<String> goals = new ArrayList<>();
        Set<Character> options = new HashSet<>();
        for (String word : words(args)) {
            if (word.startsWith("-")) {
                for (int i = 1; i < word.length(); i++) {
                    char option = word.charAt(i);
                    if ("nBkis".indexOf(option) < 0) {
                        output.add("make: invalid option -- '" + option + "'");
                        return;
                    }
                    options.add(option);
                }
            } else goals.add(word);
        }
        if (goals.isEmpty()) {
            if (!loaded) {
                output.add("make: *** No targets specified and no makefile found.  Stop.");
                return;
            }
            if (goal == null) {
                output.add("make: *** No targets.  Stop.");
                return;
            }
            goals.add(goal);
        }
        TreeMap<String, Integer> saved = options.contains('n') ? new TreeMap<>(files) : null;
        int oldClock = clock;
        Build build = new Build(options);
        try {
            for (String name : goals) {
                int previous = build.runs, result = build.target(name, null);
                if (result == 0 && previous == build.runs) output.add(phony.contains(name) || build.choices.get(name).recipe == null ? "make: Nothing to be done for '" + name + "'." : "make: '" + name + "' is up to date.");
                else if (result == 2) output.add("make: Target '" + name + "' not remade because of errors.");
            }
        } catch (AbortBuild e) { } catch (ExpansionError e) {
            expansionMessage(e);
        } finally {
            if (saved != null) {
                files = saved;
                clock = oldClock;
            }
            cleanExpansion();
        }
    }

    void command(String line, List<String> body) {
        output = new ArrayList<>(List.of("$ " + line));
        int space = line.indexOf(' ');
        String c = space < 0 ? line : line.substring(0, space), rest = space < 0 ? "" : line.substring(space + 1);
        try {
            switch (c) {
                case "MAKEFILE" -> load(body);
                case "MAKE" -> make(rest);
                case "TOUCH" -> {
                    for (String name : words(rest)) newTime(name);
                }
                case "RM" -> {
                    for (String name : words(rest)) if (files.remove(name) == null) output.add("rm: cannot remove '" + name + "': No such file or directory");
                }
                case "FILES" -> {
                    output.add("clock " + clock);
                    for (var e : files.entrySet()) output.add(e.getKey() + " " + e.getValue());
                }
                case "VARS" -> {
                    if (loaded) for (var e : variables.entrySet()) {
                        String value = trim(value(e.getKey()));
                        output.add(e.getKey() + (e.getValue().simple ? " :=" : " =") + (value.isEmpty() ? "" : " " + value));
                    }
                }
                case "RULES" -> {
                    if (loaded) {
                        List<Rule> all = new ArrayList<>(rules.values());
                        for (Rule p : patterns) if (p.recipe != null) all.add(p);
                        for (Rule rule : all) {
                            output.add(rule.name + ":" + (rule.prerequisites.isEmpty() ? "" : " " + String.join(" ", rule.prerequisites)));
                            if (rule.recipe != null) for (RecipeLine recipe : rule.recipe.lines) output.add(">" + recipe.text);
                        }
                        if (!phony.isEmpty()) output.add(".PHONY: " + String.join(" ", phony));
                    }
                }
                case "EXPAND" -> output.add("[" + expand(rest) + "]");
                default -> throw new IllegalStateException();
            }
        } catch (ExpansionError e) {
            expansionMessage(e);
        } finally {
            cleanExpansion();
        }
        for (String row : output) System.out.println(row);
    }

    public static void main(String[] args) throws IOException {
        BufferedReader reader = new BufferedReader(new InputStreamReader(System.in));
        Main runner = new Main();
        reader.readLine();
        String line;
        while (!(line = reader.readLine()).equals("END FILES")) {
            int space = line.indexOf(' '), value = Integer.parseInt(line.substring(space + 1));
            runner.files.put(line.substring(0, space), value);
            runner.clock = Math.max(runner.clock, value);
        }
        while (!(line = reader.readLine()).equals("QUIT")) {
            List<String> body = new ArrayList<>();
            if (line.equals("MAKEFILE")) {
                String row;
                while (!(row = reader.readLine()).equals("END MAKEFILE")) body.add(row);
            }
            runner.command(line, body);
        }
    }
}
