import java.nio.file.*;
import java.util.*;
public class Main {
    static Rbac rbac;
    static PolicyParser.Element root;
    static List<PolicyParser.Element> elements, rules;
    static TreeMap<String, Map<String, Object>> subjects = new TreeMap<>();
    static TreeMap<String, Resource> resources = new TreeMap<>();
    static List<Analysis.Domain> domains = new ArrayList<>();
    static Map<String, Object> reference;
    static List<Request> requests = new ArrayList<>();
    static Map<String, StringBuilder> coverage = new HashMap<>();
    static Map<Rbac.Grant, Integer> grantCounts = new HashMap<>();
    static Map<String, Integer> decisions = new HashMap<>(), decisiveCounts = new HashMap<>();
    static TreeMap<String, Integer> obligationCounts = new TreeMap<>(), adviceCounts =
                                                                            new TreeMap<>();
    static int refused;
    record Failure(String reason) {}
    record Target(String result, String reason) {}
    record Item(String identifier, String text) {}
    record Resource(String type, Map<String, Object> attributes) {}
    record Request(String identifier, String user, String roles, String action, String resource,
                   Map<String, Object> environment, boolean explain) {}
    record Activation(String role, String reason) {}
    record Prepared(List<Activation> activations, List<String> roles, String grant,
                    Map<String, Object> values) {}
    record ConflictPair(PolicyParser.Element policy, PolicyParser.Element earlier,
                        PolicyParser.Element later) {}
    static final class Evaluation {
        PolicyParser.Element element, decisive;
        Target target;
        String decision = Combining.NA, reason;
        Object condition;
        List<Combining.State> children = new ArrayList<>();
        List<Item> obligations = new ArrayList<>(), advice = new ArrayList<>();
        Evaluation(PolicyParser.Element element, Target target) {
            this.element = element;
            this.target = target;
        }
    }
    static boolean definite(String decision) {
        return decision.equals("PERMIT") || decision.equals("DENY");
    }
    static Object inputValue(String text) {
        if (text.equals("true") || text.equals("false"))
            return text.equals("true");
        if (text.startsWith("["))
            return text.equals("[]")
                ? List.of()
                : List.copyOf(Arrays.asList(text.substring(1, text.length() - 1).split(",")));
        if (text.matches("-?[0-9]+"))
            return Integer.parseInt(text);
        return text;
    }
    static Map<String, Object> attributes(List<String> fields) {
        Map<String, Object> result = new LinkedHashMap<>();
        for (String field : fields) {
            int equals = field.indexOf('=');
            result.put(field.substring(0, equals), inputValue(field.substring(equals + 1)));
        }
        return result;
    }
    static String valueNotation(Object value) {
        if (value instanceof Boolean flag)
            return flag ? "true" : "false";
        if (value instanceof Integer)
            return value.toString();
        if (value instanceof String text)
            return "\"" + text + "\"";
        List<String> values = new ArrayList<>();
        for (Object item : (List<?>)value)
            values.add(valueNotation(item));
        return "[" + String.join(",", values) + "]";
    }
    static Failure firstError(List<Object> values) {
        for (Object value : values)
            if (value instanceof Failure failure)
                return failure;
        return null;
    }
    static Object booleanResult(List<Object> values, boolean veto, String name) {
        Failure first = null;
        boolean found = false;
        for (Object value : values) {
            if (value instanceof Boolean flag) {
                if (flag == veto)
                    found = true;
            } else if (first == null)
                first = value instanceof Failure failure ? failure : new Failure("type " + name);
        }
        if (found)
            return veto;
        return first != null ? first : !veto;
    }
    static Object operation(String name, List<Object> values) {
        Failure error = firstError(values);
        if (error != null)
            return error;
        if (Set.of("+", "-", "*", "<", "<=", ">", ">=").contains(name)) {
            boolean integers = true;
            for (Object value : values)
                if (!(value instanceof Integer))
                    integers = false;
            if (integers) {
                int a = (Integer)values.get(0);
                if (values.size() == 1)
                    return -a;
                int b = (Integer)values.get(1);
                return switch (name) {
                    case "+" -> a + b;
                    case "-" -> a - b;
                    case "*" -> a *b;
                    case "<" -> a < b;
                    case "<=" -> a <= b;
                    case ">" -> a > b;
                    default -> a >= b;
                };
            }
        } else if (name.equals("==") || name.equals("!=")) {
            Object a = values.get(0), b = values.get(1);
            if (a.getClass() == b.getClass() &&
                (a instanceof Integer || a instanceof String || a instanceof Boolean))
                return name.equals("==") == a.equals(b);
        } else if (name.equals("in")) {
            if (values.get(0) instanceof String text && values.get(1) instanceof List<?> bag)
                return bag.contains(text);
        } else if (name.equals("not")) {
            if (values.getFirst() instanceof Boolean flag)
                return !flag;
        } else if (name.equals("starts_with") || name.equals("^=")) {
            if (values.get(0) instanceof String text && values.get(1) instanceof String prefix)
                return text.startsWith(prefix);
        } else if (name.equals("size")) {
            if (values.getFirst() instanceof List<?> bag)
                return bag.size();
        }
        return new Failure("type " + name);
    }
    static Object expression(Expressions.Expr tree, Map<String, Object> values, String current) {
        if (tree instanceof Expressions.Literal literal)
            return literal.value();
        if (tree instanceof Expressions.Reference reference)
            return values.containsKey(reference.name())
                ? values.get(reference.name())
                : new Failure("missing " + reference.name());
        if (tree instanceof Expressions.Current)
            return current;
        Expressions.Operation operation = (Expressions.Operation)tree;
        String name = operation.name();
        List<Expressions.Expr> arguments = operation.arguments();
        if (name.equals("present"))
            return values.containsKey(((Expressions.Reference)arguments.getFirst()).name());
        if (name.equals("any_of") || name.equals("all_of")) {
            Object bag = expression(arguments.get(0), values, current);
            if (bag instanceof Failure)
                return bag;
            if (!(bag instanceof List<?> items))
                return new Failure("type " + name);
            List<Object> predicates = new ArrayList<>();
            for (Object item : items)
                predicates.add(expression(arguments.get(1), values, (String)item));
            return booleanResult(predicates, name.equals("any_of"), name);
        }
        List<Object> operands = new ArrayList<>();
        for (Expressions.Expr argument : arguments)
            operands.add(expression(argument, values, current));
        return name.equals("and") || name.equals("or")
            ? booleanResult(operands, name.equals("or"), name)
            : operation(name, operands);
    }
    static Target targetGroup(List<Target> results, boolean conjunction) {
        if (conjunction) {
            boolean all = true;
            for (Target result : results) {
                if (result.result().equals("NO_MATCH"))
                    return new Target("NO_MATCH", null);
                if (!result.result().equals("MATCH"))
                    all = false;
            }
            if (all)
                return new Target("MATCH", null);
        } else
            for (Target result : results)
                if (result.result().equals("MATCH"))
                    return new Target("MATCH", null);
        for (Target result : results)
            if (result.result().equals("INDETERMINATE"))
                return result;
        return new Target("NO_MATCH", null);
    }
    static Target matchClause(PolicyParser.Clause clause, Map<String, Object> values) {
        String reference = clause.reference();
        if (!values.containsKey(reference))
            return clause.mandatory() ? new Target("INDETERMINATE", "missing " + reference)
                                      : new Target("NO_MATCH", null);
        Object source = values.get(reference);
        List<?> items = source instanceof List<?> bag ? bag : List.of(source);
        Object comparison = expression(clause.literal(), values, null);
        List<Object> results = new ArrayList<>();
        for (Object item : items)
            results.add(operation(clause.operator(), List.of(item, comparison)));
        for (Object result : results)
            if (Boolean.TRUE.equals(result))
                return new Target("MATCH", null);
        Failure error = firstError(results);
        return error == null ? new Target("NO_MATCH", null)
                             : new Target("INDETERMINATE", error.reason());
    }
    static String decisionNotation(String decision, String reason) {
        return decision.startsWith("INDETERMINATE") ? decision + " (" + reason + ")" : decision;
    }
    static String finalNotation(Evaluation result) {
        return decisionNotation(result.decision, result.reason) +
            (definite(result.decision) ? " by " + result.decisive.identifier : "");
    }
    static final class Evaluator {
        Map<String, Object> values;
        Map<String, Character> coverage;
        Evaluator(Map<String, Object> values, Map<String, Character> coverage) {
            this.values = values;
            this.coverage = coverage;
        }
        Target target(PolicyParser.Element element) {
            List<Target> lines = new ArrayList<>();
            for (List<List<PolicyParser.Clause>> line : element.targets) {
                List<Target> alternatives = new ArrayList<>();
                for (List<PolicyParser.Clause> alternative : line) {
                    List<Target> clauses = new ArrayList<>();
                    for (PolicyParser.Clause clause : alternative)
                        clauses.add(matchClause(clause, values));
                    alternatives.add(targetGroup(clauses, true));
                }
                lines.add(targetGroup(alternatives, false));
            }
            return targetGroup(lines, true);
        }
        void attachments(Evaluation result, List<Evaluation> supporters) {
            for (Evaluation supporter : supporters) {
                result.obligations.addAll(supporter.obligations);
                result.advice.addAll(supporter.advice);
            }
            String effect = result.decision;
            for (int kind = 0; kind < 2; kind++)
                for (PolicyParser.Attachment definition :
                     kind == 0 ? result.element.obligations : result.element.advice)
                    if (definition.effect().equals(effect)) {
                        List<Object> evaluated = new ArrayList<>();
                        for (PolicyParser.Argument argument : definition.arguments())
                            evaluated.add(expression(argument.expression(), values, null));
                        Failure error = firstError(evaluated);
                        if (error != null) {
                            if (kind == 0) {
                                result.decision =
                                    effect.equals("DENY") ? Combining.ID : Combining.IP;
                                result.reason =
                                    "obligation " + definition.identifier() + ": " + error.reason();
                                result.decisive = null;
                                result.obligations.clear();
                                result.advice.clear();
                                return;
                            }
                            continue;
                        }
                        StringBuilder item = new StringBuilder(definition.identifier());
                        for (int i = 0; i < evaluated.size(); i++)
                            item.append(" ")
                                .append(definition.arguments().get(i).name())
                                .append("=")
                                .append(valueNotation(evaluated.get(i)));
                        (kind == 0 ? result.obligations : result.advice)
                            .add(new Item(definition.identifier(), item.toString()));
                    }
        }
        Evaluation rule(PolicyParser.Element element, boolean obligations) {
            Evaluation result = new Evaluation(element, target(element));
            String target = result.target.result(), reason = result.target.reason(),
                   indeterminate = element.behavior.equals("DENY") ? Combining.ID : Combining.IP;
            if (target.equals("INDETERMINATE")) {
                result.decision = indeterminate;
                result.reason = reason;
            } else if (target.equals("MATCH")) {
                Object condition =
                    element.condition == null ? true : expression(element.condition, values, null);
                if (!(condition instanceof Boolean) && !(condition instanceof Failure))
                    condition = new Failure("type condition");
                result.condition = condition;
                if (condition instanceof Failure error) {
                    result.decision = indeterminate;
                    result.reason = error.reason();
                } else if ((Boolean)condition) {
                    result.decision = element.behavior;
                    result.decisive = element;
                    if (obligations)
                        attachments(result, List.of());
                }
            }
            if (coverage != null)
                coverage.put(element.identifier, result.decision.equals("PERMIT")       ? 'P'
                                                 : result.decision.equals("DENY")       ? 'D'
                                                 : result.decision.equals(Combining.NA) ? '-'
                                                                                        : 'I');
            return result;
        }
        Evaluation evaluate(PolicyParser.Element element) {
            if (element.kind.equals("rule"))
                return rule(element, true);
            Evaluation result = new Evaluation(element, target(element));
            String target = result.target.result();
            if (target.equals("NO_MATCH"))
                return result;
            Combining.Result combined =
                Combining.combine(element.behavior, element.children, this::evaluate, this::target);
            result.decision = combined.decision();
            result.reason = combined.reason();
            result.children = combined.states();
            if (target.equals("INDETERMINATE")) {
                if (definite(result.decision))
                    result.decision = result.decision.equals("DENY") ? Combining.ID : Combining.IP;
                if (result.decision.startsWith("INDETERMINATE"))
                    result.reason = result.target.reason();
            }
            if (definite(result.decision)) {
                List<Evaluation> supporters = new ArrayList<>();
                for (Combining.State state : result.children)
                    if (state != null && state.evaluated() != null &&
                        state.evaluated().decision.equals(result.decision))
                        supporters.add(state.evaluated());
                result.decisive = supporters.isEmpty() ? element : supporters.getFirst().decisive;
                attachments(result, supporters);
            }
            return result;
        }
    }
    static List<String> treeLines(Evaluation result, int depth) {
        PolicyParser.Element element = result.element;
        String target = result.target.result(), prefix = " ".repeat(2 + 2 * depth),
               line = prefix + element.kind + " " + element.identifier + " " + element.behavior +
                      " target " + target;
        if (element.kind.equals("rule") && target.equals("MATCH"))
            line += " condition " + (result.condition instanceof Failure     ? "INDETERMINATE"
                                     : Boolean.TRUE.equals(result.condition) ? "TRUE"
                                                                             : "FALSE");
        List<String> lines = new ArrayList<>();
        lines.add(line + " -> " + decisionNotation(result.decision, result.reason));
        if (!element.kind.equals("rule") && !target.equals("NO_MATCH"))
            for (int i = 0; i < element.children.size(); i++) {
                PolicyParser.Element child = element.children.get(i);
                Combining.State state = result.children.get(i);
                if (state != null && state.evaluated() != null)
                    lines.addAll(treeLines(state.evaluated(), depth + 1));
                else if (state == null)
                    lines.add(prefix + "  " + child.kind + " " + child.identifier + " skipped");
                else {
                    Target checked = state.checked();
                    lines.add(prefix + "  " + child.kind + " " + child.identifier + " " +
                              child.behavior + " target " + checked.result() +
                              (checked.result().equals("INDETERMINATE")
                                   ? " (" + checked.reason() + ")"
                                   : ""));
                }
            }
        return lines;
    }
    static <K> void add(Map<K, Integer> counts, K key, int amount) {
        counts.merge(key, amount, Integer::sum);
    }
    static String checkRequest(Request request) {
        if (!subjects.containsKey(request.user()))
            return "unknown user " + request.user();
        if (!resources.containsKey(request.resource()))
            return "unknown resource " + request.resource();
        Object day = request.environment().get("day");
        return day instanceof Integer value && value >= 1 && value <= 365 ? null : "bad day";
    }
    static Prepared prepare(Request request) {
        int day = (Integer)request.environment().get("day");
        Set<String> authorized = rbac.authorized(request.user(), day);
        List<String> candidates = request.roles().equals("-") ? List.of()
                                  : request.roles().equals("*")
                                      ? new ArrayList<>(authorized)
                                      : Arrays.asList(request.roles().split(","));
        List<String> active = new ArrayList<>();
        Set<String> seen = new HashSet<>();
        List<Activation> activations = new ArrayList<>();
        for (String candidate : candidates) {
            String reason = null;
            if (!rbac.roles.contains(candidate))
                reason = "unknown";
            else if (seen.contains(candidate))
                reason = "duplicate";
            else if (!authorized.contains(candidate))
                reason = "unauthorized";
            else {
                Set<String> proposed = new HashSet<>(active);
                proposed.add(candidate);
                Set<String> closure = rbac.closure(proposed);
                for (Rbac.Constraint constraint : rbac.dsd) {
                    Set<String> intersection = new HashSet<>(constraint.roles());
                    intersection.retainAll(closure);
                    if (intersection.size() >= constraint.cardinality()) {
                        reason = "dsd " + constraint.name();
                        break;
                    }
                }
            }
            seen.add(candidate);
            if (reason == null)
                active.add(candidate);
            activations.add(new Activation(candidate, reason));
        }
        List<String> roles = new ArrayList<>(rbac.closure(active));
        Resource resource = resources.get(request.resource());
        String grant = null;
        for (String role : roles)
            if (rbac.permissions.get(role).contains(
                    new Rbac.Permission(request.action(), resource.type()))) {
                grant = role;
                break;
            }
        Map<String, Object> values = new HashMap<>();
        for (var entry : subjects.get(request.user()).entrySet())
            values.put("subject." + entry.getKey(), entry.getValue());
        values.put("subject.id", request.user());
        values.put("subject.role", List.copyOf(roles));
        values.put("subject.rbac", grant != null);
        for (var entry : resource.attributes().entrySet())
            values.put("resource." + entry.getKey(), entry.getValue());
        values.put("resource.id", request.resource());
        values.put("resource.type", resource.type());
        values.put("action.id", request.action());
        for (var entry : request.environment().entrySet())
            values.put("environment." + entry.getKey(), entry.getValue());
        return new Prepared(activations, roles, grant, values);
    }
    static List<String> trace(Request request, Prepared prepared, Evaluation result) {
        List<String> lines = new ArrayList<>();
        lines.add("request " + request.identifier());
        lines.add("  user " + request.user() + " resource " + request.resource() + " type " +
                  resources.get(request.resource()).type() + " action " + request.action() +
                  " day " + request.environment().get("day"));
        for (Activation activation : prepared.activations())
            lines.add("  activate " + activation.role() +
                      (activation.reason() == null ? " ok" : " refused " + activation.reason()));
        lines.add("  roles " +
                  (prepared.roles().isEmpty() ? "-" : String.join(",", prepared.roles())));
        lines.add("  rbac " + (prepared.grant() == null ? "no" : "yes " + prepared.grant()));
        lines.addAll(treeLines(result, 0));
        lines.add("  decision " + finalNotation(result));
        return lines;
    }
    static List<String> joinBlocks(List<List<String>> blocks) {
        List<String> lines = new ArrayList<>();
        for (List<String> block : blocks) {
            if (!lines.isEmpty())
                lines.add("");
            lines.addAll(block);
        }
        return lines;
    }
    static List<List<String>> processRequests() {
        List<String> lines = new ArrayList<>();
        List<List<String>> explanations = new ArrayList<>();
        for (Request request : requests) {
            Map<String, Character> symbols = new HashMap<>();
            for (PolicyParser.Element rule : rules)
                symbols.put(rule.identifier, '.');
            String error = checkRequest(request);
            if (error != null) {
                lines.add(request.identifier() + " ERROR " + error);
                add(decisions, "ERROR", 1);
                if (request.explain())
                    explanations.add(
                        List.of("request " + request.identifier(), "  error " + error));
            } else {
                Prepared prepared = prepare(request);
                Evaluation result = new Evaluator(prepared.values(), symbols).evaluate(root);
                lines.add(request.identifier() + " " + finalNotation(result));
                for (Activation activation : prepared.activations())
                    if (activation.reason() != null) {
                        lines.add("  refused " + activation.role() + " " + activation.reason());
                        refused++;
                    }
                for (Item item : result.obligations) {
                    lines.add("  obligation " + item.text());
                    add(obligationCounts, item.identifier(), 1);
                }
                for (Item item : result.advice) {
                    lines.add("  advice " + item.text());
                    add(adviceCounts, item.identifier(), 1);
                }
                if (prepared.grant() != null)
                    add(grantCounts,
                        new Rbac.Grant(prepared.grant(), request.action(),
                                       resources.get(request.resource()).type()),
                        1);
                add(decisions,
                    result.decision.startsWith("INDETERMINATE") ? "INDETERMINATE" : result.decision,
                    1);
                if (definite(result.decision))
                    add(decisiveCounts, result.decisive.identifier, 1);
                if (request.explain())
                    explanations.add(trace(request, prepared, result));
            }
            for (PolicyParser.Element rule : rules)
                coverage.get(rule.identifier).append(symbols.get(rule.identifier));
        }
        return List.of(lines, joinBlocks(explanations));
    }

    static List<String> permissionReport() {
        List<List<String>> blocks = new ArrayList<>();
        Set<String> users = new TreeSet<>();
        for (Rbac.Assignment assignment : rbac.assignments)
            users.add(assignment.user());
        Comparator<Rbac.Permission> order =
            Comparator.comparing(Rbac.Permission::action).thenComparing(Rbac.Permission::type);
        for (String user : users) {
            TreeMap<String, Set<Integer>> assigned = new TreeMap<>(), authorized = new TreeMap<>();
            for (Rbac.Assignment assignment : rbac.assignments)
                if (assignment.user().equals(user)) {
                    Set<Integer> days =
                        assigned.computeIfAbsent(assignment.role(), key -> new TreeSet<>());
                    for (int day = assignment.first(); day <= assignment.last(); day++)
                        days.add(day);
                }
            for (var entry : assigned.entrySet())
                for (String role : rbac.closure(List.of(entry.getKey())))
                    authorized.computeIfAbsent(role, key -> new TreeSet<>())
                        .addAll(entry.getValue());
            List<String> lines = new ArrayList<>();
            lines.add("user " + user);
            for (var entry : assigned.entrySet())
                lines.add("  assigned " + entry.getKey() + " " +
                          Analysis.dayNotation(entry.getValue()));
            for (var entry : authorized.entrySet())
                lines.add("  authorized " + entry.getKey() + " " +
                          Analysis.dayNotation(entry.getValue()));
            TreeMap<Rbac.Permission, List<String>> via = new TreeMap<>(order);
            for (String role : authorized.keySet())
                for (Rbac.Permission permission : rbac.permissions.get(role))
                    via.computeIfAbsent(permission, key -> new ArrayList<>()).add(role);
            for (var entry : via.entrySet()) {
                Rbac.Permission permission = entry.getKey();
                List<String> roles = entry.getValue();
                Set<Integer> days = new TreeSet<>();
                for (String role : roles)
                    days.addAll(authorized.get(role));
                String effective = "-";
                if (subjects.containsKey(user)) {
                    int permitted = 0, total = 0;
                    for (var resource : resources.entrySet())
                        if (resource.getValue().type().equals(permission.type())) {
                            total++;
                            Request request = new Request("", user, "*", permission.action(),
                                                          resource.getKey(), reference, false);
                            Prepared prepared = prepare(request);
                            if (new Evaluator(prepared.values(), null)
                                    .evaluate(root)
                                    .decision.equals("PERMIT"))
                                permitted++;
                        }
                    effective = permitted + "/" + total;
                }
                lines.add("  permission " + permission.action() + " " + permission.type() + " " +
                          Analysis.dayNotation(days) + " via " + String.join(",", roles) +
                          " effective " + effective);
            }
            blocks.add(lines);
        }
        return joinBlocks(blocks);
    }
    static List<String> domainAnalysis() {
        Map<String, Integer> counts = new HashMap<>();
        Map<String, String> examples = new HashMap<>();
        Map<ConflictPair, Integer> conflictCounts = new HashMap<>();
        Set<String> shadowed = new HashSet<>();
        Map<String, Set<String>> blockers = new HashMap<>();
        List<ConflictPair> pairs = new ArrayList<>();
        for (PolicyParser.Element rule : rules)
            if (rule.parent.behavior.equals("first-applicable"))
                shadowed.add(rule.identifier);
        for (PolicyParser.Element policy : elements)
            if (policy.kind.equals("policy"))
                for (int i = 0; i < policy.children.size(); i++)
                    for (int j = i + 1; j < policy.children.size(); j++) {
                        PolicyParser.Element earlier = policy.children.get(i),
                                             later = policy.children.get(j);
                        if (!earlier.behavior.equals(later.behavior))
                            pairs.add(new ConflictPair(policy, earlier, later));
                    }
        int pointCount = 0;
        for (Map<String, Object> values : Analysis.points(domains)) {
            pointCount++;
            Evaluator evaluator = new Evaluator(values, null);
            Map<String, String> targets = new HashMap<>(), standalone = new HashMap<>();
            for (PolicyParser.Element element : elements)
                if (!element.kind.equals("rule"))
                    targets.put(element.identifier, evaluator.target(element).result());
            for (PolicyParser.Element rule : rules)
                standalone.put(rule.identifier, evaluator.rule(rule, false).decision);
            Set<String> applying = new HashSet<>();
            for (PolicyParser.Element rule : rules) {
                String identifier = rule.identifier;
                if (!definite(standalone.get(identifier)))
                    continue;
                boolean ancestors = true;
                for (PolicyParser.Element parent = rule.parent; parent != null;
                     parent = parent.parent)
                    if (!targets.get(parent.identifier).equals("MATCH"))
                        ancestors = false;
                if (!ancestors)
                    continue;
                applying.add(identifier);
                add(counts, identifier, 1);
                if (!examples.containsKey(identifier)) {
                    List<String> assignments = new ArrayList<>();
                    for (Analysis.Domain domain : domains)
                        if (domain.values().size() >= 2)
                            assignments.add(domain.name() + "=" +
                                            valueNotation(values.get(domain.name())));
                    examples.put(identifier, String.join(" ", assignments));
                }
                if (shadowed.contains(identifier)) {
                    String earlier = Analysis.blocker(rule, standalone);
                    if (earlier == null)
                        shadowed.remove(identifier);
                    else
                        blockers.computeIfAbsent(identifier, key -> new HashSet<>()).add(earlier);
                }
            }
            for (ConflictPair pair : pairs)
                if (applying.contains(pair.earlier().identifier) &&
                    applying.contains(pair.later().identifier))
                    add(conflictCounts, pair, 1);
        }
        List<String> lines = new ArrayList<>();
        lines.add("applicability " + pointCount);
        List<String> dead = new ArrayList<>();
        for (PolicyParser.Element rule : rules) {
            int count = counts.getOrDefault(rule.identifier, 0);
            lines.add("  " + rule.identifier + " " + count + " " +
                      examples.getOrDefault(rule.identifier, "-"));
            if (count == 0)
                dead.add(rule.identifier);
        }
        lines.add("dead " + dead.size());
        for (String identifier : dead)
            lines.add("  " + identifier);
        shadowed.removeAll(dead);
        lines.add("shadowed " + shadowed.size());
        for (PolicyParser.Element rule : rules)
            if (shadowed.contains(rule.identifier)) {
                List<String> names = new ArrayList<>();
                for (PolicyParser.Element earlier : rules)
                    if (blockers.getOrDefault(rule.identifier, Set.of())
                            .contains(earlier.identifier))
                        names.add(earlier.identifier);
                lines.add("  " + rule.identifier + " by " + String.join(",", names));
            }
        int conflictCount = 0;
        for (ConflictPair pair : pairs)
            if (conflictCounts.getOrDefault(pair, 0) > 0)
                conflictCount++;
        lines.add("conflicts " + conflictCount);
        for (ConflictPair pair : pairs) {
            int count = conflictCounts.getOrDefault(pair, 0);
            if (count > 0)
                lines.add("  " + pair.policy().identifier + " " + pair.earlier().identifier + " " +
                          pair.later().identifier + " " + count + " " +
                          Analysis.conflictWinner(pair.policy(), pair.earlier(), pair.later()));
        }
        return lines;
    }
    static List<String> analysisReport() {
        List<String> lines = new ArrayList<>();
        lines.add("rbac " + rbac.diagnostics.size());
        for (Rbac.Diagnostic diagnostic : rbac.diagnostics)
            lines.add("  line " + diagnostic.line() + " " + diagnostic.keyword() + " " +
                      diagnostic.message());
        lines.add("grants " + rbac.grants.size());
        for (Rbac.Grant grant : rbac.grants)
            lines.add("  " + grant.role() + " " + grant.action() + " " + grant.type() + " " +
                      grantCounts.getOrDefault(grant, 0));
        lines.addAll(domainAnalysis());
        lines.add("coverage " + requests.size());
        List<String> uncovered = new ArrayList<>();
        for (PolicyParser.Element rule : rules) {
            String symbols = coverage.get(rule.identifier).toString();
            int count = 0;
            for (char c : symbols.toCharArray())
                if (c == 'P' || c == 'D')
                    count++;
            lines.add("  " + rule.identifier + " " + symbols + " " + count);
            if (count == 0)
                uncovered.add(rule.identifier);
        }
        lines.add("uncovered " + uncovered.size());
        for (String identifier : uncovered)
            lines.add("  " + identifier);
        lines.add("summary");
        for (String name : List.of("PERMIT", "DENY", Combining.NA, "INDETERMINATE", "ERROR"))
            lines.add("  decision " + name + " " + decisions.getOrDefault(name, 0));
        lines.add("  refused " + refused);
        for (PolicyParser.Element element : elements) {
            int count = decisiveCounts.getOrDefault(element.identifier, 0);
            if (count > 0)
                lines.add("  decisive " + element.identifier + " " + count);
        }
        for (var entry : obligationCounts.entrySet())
            lines.add("  obligation " + entry.getKey() + " " + entry.getValue());
        for (var entry : adviceCounts.entrySet())
            lines.add("  advice " + entry.getKey() + " " + entry.getValue());
        return lines;
    }
    static void readInputs() throws Exception {
        rbac = new Rbac();
        PolicyParser.Policies policies = PolicyParser.read();
        root = policies.root();
        elements = policies.elements();
        rules = new ArrayList<>();
        for (PolicyParser.Element element : elements)
            if (element.kind.equals("rule")) {
                rules.add(element);
                coverage.put(element.identifier, new StringBuilder());
            }
        for (String line : Files.readAllLines(Path.of("input", "attributes.txt"))) {
            List<String> fields = Arrays.asList(line.split(" "));
            switch (fields.getFirst()) {
            case "SUBJECT":
                subjects.put(fields.get(1), attributes(fields.subList(2, fields.size())));
                break;
            case "RESOURCE":
                resources.put(
                    fields.get(1),
                    new Resource(fields.get(2), attributes(fields.subList(3, fields.size()))));
                break;
            case "DOMAIN": {
                List<Object> values = new ArrayList<>();
                for (String value : fields.subList(2, fields.size()))
                    values.add(inputValue(value));
                domains.add(new Analysis.Domain(fields.get(1), values));
                break;
            }
            default:
                reference = attributes(fields.subList(1, fields.size()));
            }
        }
        for (String line : Files.readAllLines(Path.of("input", "requests.txt"))) {
            List<String> fields = new ArrayList<>(Arrays.asList(line.split(" ")));
            boolean explain = fields.getLast().equals("EXPLAIN");
            if (explain)
                fields.removeLast();
            requests.add(new Request(fields.get(0), fields.get(1), fields.get(2), fields.get(3),
                                     fields.get(4), attributes(fields.subList(5, fields.size())),
                                     explain));
        }
    }
    static void write(String name, List<String> lines) throws Exception {
        Files.writeString(Path.of("output", name),
                          String.join("\n", lines) + (lines.isEmpty() ? "" : "\n"));
    }
    public static void main(String[] args) throws Exception {
        readInputs();
        List<List<String>> reports = processRequests();
        Files.createDirectories(Path.of("output"));
        write("decisions.txt", reports.get(0));
        write("traces.txt", reports.get(1));
        write("permissions.txt", permissionReport());
        write("analysis.txt", analysisReport());
    }
}
