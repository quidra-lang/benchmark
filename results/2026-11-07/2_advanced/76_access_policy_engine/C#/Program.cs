using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
public static class Program {
    public static Rbac rbac;
    public static PolicyParser.Element root;
    public static List<PolicyParser.Element> elements, rules;
    public static SortedDictionary<string, Dictionary<string, object>> subjects =
        new(StringComparer.Ordinal);
    public static SortedDictionary<string, Resource> resources = new(StringComparer.Ordinal);
    public static List<Analysis.Domain> domains = new();
    public static Dictionary<string, object> reference;
    public static List<Request> requests = new();
    public static Dictionary<string, StringBuilder> coverage = new();
    public static Dictionary<Rbac.Grant, int> grantCounts = new();
    public static Dictionary<string, int> decisions = new(), decisiveCounts = new();
    public static SortedDictionary<string, int> obligationCounts = new(StringComparer.Ordinal),
                                                adviceCounts = new(StringComparer.Ordinal);
    public static int refused;
    public record Failure(string reason) {}
    public record Target(string result, string reason) {}
    public record Item(string identifier, string text) {}
    public record Resource(string type, Dictionary<string, object> attributes) {}
    public record Request(string identifier, string user, string roles, string action,
                          string resource, Dictionary<string, object> environment, bool explain) {}
    public record Activation(string role, string reason) {}
    public record Prepared(List<Activation> activations, List<string> roles, string grant,
                           Dictionary<string, object> values) {}
    public record ConflictPair(PolicyParser.Element policy, PolicyParser.Element earlier,
                               PolicyParser.Element later) {}
    public sealed class Evaluation {
        public PolicyParser.Element element, decisive;
        public Target target;
        public string decision = Combining.NA, reason;
        public object condition;
        public List<Combining.State> children = new();
        public List<Item> obligations = new(), advice = new();
        public Evaluation(PolicyParser.Element element, Target target) {
            this.element = element;
            this.target = target;
        }
    }
    public static bool Definite(string decision) {
        return decision.Equals("PERMIT") || decision.Equals("DENY");
    }
    public static object InputValue(string text) {
        if (text == "true" || text == "false")
            return text == "true";
        if (text.StartsWith('['))
            return text == "[]" ? new List<string>() : text[1.. ^ 1].Split(',').ToList();
        if (Regex.IsMatch(text, "\\A-?[0-9]+\\z"))
            return int.Parse(text, CultureInfo.InvariantCulture);
        return text;
    }
    public static Dictionary<string, object> Attributes(List<string> fields) {
        Dictionary<string, object> result = new();
        foreach (string field in fields) {
            int equal = field.IndexOf('=');
            result[field[..equal]] = InputValue(field[(equal + 1)..]);
        }
        return result;
    }
    public static string ValueNotation(object value) {
        if (value is bool flag)
            return flag ? "true" : "false";
        if (value is int)
            return value.ToString();
        if (value is string text)
            return "\"" + text + "\"";
        return "[" + string.Join(",", ((List<string>)value).Select(item => ValueNotation(item))) +
               "]";
    }
    public static Failure FirstError(List<object> values) {
        foreach (object value in values)
            if (value is Failure failure)
                return failure;
        return null;
    }
    public static object BooleanResult(List<object> values, bool veto, string name) {
        Failure first = null;
        bool found = false;
        foreach (object value in values)
            if (value is bool flag) {
                if (flag == veto)
                    found = true;
            } else if (first == null)
                first = value as Failure ?? new Failure("type " + name);
        if (found)
            return veto;
        return first != null ? first : !veto;
    }
    public static object Operation(string name, List<object> values) {
        Failure error = FirstError(values);
        if (error != null)
            return error;
        if (new HashSet<string> { "+", "-", "*", "<", "<=", ">", ">=" }.Contains(name)) {
            if (values.All(value => value is int)) {
                int a = (int)values[0];
                if (values.Count == 1)
                    return -a;
                int b = (int)values[1];
                return name switch { "+" => a + b, "-" => a - b, "*" => a * b,
                                     "<" => a<b, "<=" => a <= b, ">" => a> b,
                                     _ => a >= b };
            }
        } else if (name == "==" || name == "!=") {
            object a = values[0], b = values[1];
            if (a.GetType() == b.GetType() && (a is int || a is string || a is bool))
                return (name == "==") == a.Equals(b);
        } else if (name == "in") {
            if (values[0] is string text && values[1] is List<string> bag)
                return bag.Contains(text);
        } else if (name == "not") {
            if (values[0] is bool flag)
                return !flag;
        } else if (name == "starts_with" || name == "^=") {
            if (values[0] is string text && values[1] is string prefix)
                return text.StartsWith(prefix, StringComparison.Ordinal);
        } else if (name == "size") {
            if (values[0] is List<string> bag)
                return bag.Count;
        }
        return new Failure("type " + name);
    }
    public static object Expression(Expressions.Expr tree, Dictionary<string, object> values,
                                    string current) {
        if (tree is Expressions.Literal literal)
            return literal.value;
        if (tree is Expressions.Reference reference)
            return values.TryGetValue(reference.name, out object value)
                       ? value
                       : new Failure("missing " + reference.name);
        if (tree is Expressions.Current)
            return current;
        Expressions.Operation op = (Expressions.Operation)tree;
        string name = op.name;
        List<Expressions.Expr> arguments = op.arguments;
        if (name == "present")
            return values.ContainsKey(((Expressions.Reference)arguments[0]).name);
        if (name == "any_of" || name == "all_of") {
            object source = Expression(arguments[0], values, current);
            if (source is Failure)
                return source;
            if (source is not List<string> items)
                return new Failure("type " + name);
            List<object> predicates = new();
            foreach (string item in items)
                predicates.Add(Expression(arguments[1], values, item));
            return BooleanResult(predicates, name == "any_of", name);
        }
        List<object> operands = new();
        foreach (Expressions.Expr argument in arguments)
            operands.Add(Expression(argument, values, current));
        return name == "and" || name == "or" ? BooleanResult(operands, name == "or", name)
                                             : Operation(name, operands);
    }
    public static Target TargetGroup(List<Target> results, bool conjunction) {
        if (conjunction) {
            bool all = true;
            foreach (Target result in results) {
                if (result.result.Equals("NO_MATCH"))
                    return new Target("NO_MATCH", null);
                if (!result.result.Equals("MATCH"))
                    all = false;
            }
            if (all)
                return new Target("MATCH", null);
        } else
            foreach (Target result in results)
                if (result.result.Equals("MATCH"))
                    return new Target("MATCH", null);
        foreach (Target result in results)
            if (result.result.Equals("INDETERMINATE"))
                return result;
        return new Target("NO_MATCH", null);
    }
    public static Target MatchClause(PolicyParser.Clause clause,
                                     Dictionary<string, object> values) {
        string reference = clause.reference;
        if (!values.ContainsKey(reference))
            return clause.mandatory ? new("INDETERMINATE", "missing " + reference)
                                    : new("NO_MATCH", null);
        object source = values[reference];
        IEnumerable<object> items =
            source is List<string> bag ? bag.Cast<object>() : new[] { source };
        object comparison = Expression(clause.literal, values, null);
        List<object> results = new();
        foreach (object item in items)
            results.Add(Operation(clause.op, new() { item, comparison }));
        if (results.Any(result => result is true))
            return new("MATCH", null);
        Failure error = FirstError(results);
        return error == null ? new("NO_MATCH", null) : new("INDETERMINATE", error.reason);
    }
    public static string DecisionNotation(string decision, string reason) {
        return decision.StartsWith("INDETERMINATE") ? decision + " (" + reason + ")" : decision;
    }
    public static string FinalNotation(Evaluation result) {
        return DecisionNotation(result.decision, result.reason) +
               (Definite(result.decision) ? " by " + result.decisive.identifier : "");
    }
    public sealed class Evaluator {
        public Dictionary<string, object> values;
        public Dictionary<string, char> coverage;
        public Evaluator(Dictionary<string, object> values, Dictionary<string, char> coverage) {
            this.values = values;
            this.coverage = coverage;
        }
        public Target Target(PolicyParser.Element element) {
            List<Target> lines = new();
            foreach (List<List<PolicyParser.Clause>> line in element.targets) {
                List<Target> alternatives = new();
                foreach (List<PolicyParser.Clause> alternative in line) {
                    List<Target> clauses = new();
                    foreach (PolicyParser.Clause clause in alternative)
                        clauses.Add(MatchClause(clause, values));
                    alternatives.Add(TargetGroup(clauses, true));
                }
                lines.Add(TargetGroup(alternatives, false));
            }
            return TargetGroup(lines, true);
        }
        public void Attachments(Evaluation result, List<Evaluation> supporters) {
            foreach (Evaluation supporter in supporters) {
                result.obligations.AddRange(supporter.obligations);
                result.advice.AddRange(supporter.advice);
            }
            string effect = result.decision;
            for (int kind = 0; kind < 2; kind++)
                foreach (PolicyParser.Attachment definition in kind == 0
                             ? result.element.obligations
                             : result.element.advice)
                    if (definition.effect.Equals(effect)) {
                        List<object> evaluated = new();
                        foreach (PolicyParser.Argument argument in definition.arguments)
                            evaluated.Add(Expression(argument.expression, values, null));
                        Failure error = FirstError(evaluated);
                        if (error != null) {
                            if (kind == 0) {
                                result.decision =
                                    effect.Equals("DENY") ? Combining.ID : Combining.IP;
                                result.reason =
                                    "obligation " + definition.identifier + ": " + error.reason;
                                result.decisive = null;
                                result.obligations.Clear();
                                result.advice.Clear();
                                return;
                            }
                            continue;
                        }
                        StringBuilder item = new StringBuilder(definition.identifier);
                        for (int i = 0; i < evaluated.Count; i++)
                            item.Append(" ")
                                .Append(definition.arguments[i].name)
                                .Append("=")
                                .Append(ValueNotation(evaluated[i]));
                        (kind == 0 ? result.obligations : result.advice)
                            .Add(new Item(definition.identifier, item.ToString()));
                    }
        }
        public Evaluation Rule(PolicyParser.Element element, bool obligations) {
            Evaluation result = new Evaluation(element, Target(element));
            string target = result.target.result, reason = result.target.reason,
                   indeterminate = element.behavior.Equals("DENY") ? Combining.ID : Combining.IP;
            if (target.Equals("INDETERMINATE")) {
                result.decision = indeterminate;
                result.reason = reason;
            } else if (target.Equals("MATCH")) {
                object condition =
                    element.condition == null ? true : Expression(element.condition, values, null);
                if (!(condition is bool) && !(condition is Failure))
                    condition = new Failure("type condition");
                result.condition = condition;
                if (condition is Failure error) {
                    result.decision = indeterminate;
                    result.reason = error.reason;
                } else if ((bool)condition) {
                    result.decision = element.behavior;
                    result.decisive = element;
                    if (obligations)
                        Attachments(result, new());
                }
            }
            if (coverage != null)
                coverage[element.identifier] = result.decision.Equals("PERMIT")       ? 'P'
                                               : result.decision.Equals("DENY")       ? 'D'
                                               : result.decision.Equals(Combining.NA) ? '-'
                                                                                      : 'I';
            return result;
        }
        public Evaluation Evaluate(PolicyParser.Element element) {
            if (element.kind.Equals("rule"))
                return Rule(element, true);
            Evaluation result = new Evaluation(element, Target(element));
            string target = result.target.result;
            if (target.Equals("NO_MATCH"))
                return result;
            Combining.Result combined =
                Combining.Combine(element.behavior, element.children, Evaluate, Target);
            result.decision = combined.decision;
            result.reason = combined.reason;
            result.children = combined.states;
            if (target.Equals("INDETERMINATE")) {
                if (Definite(result.decision))
                    result.decision = result.decision.Equals("DENY") ? Combining.ID : Combining.IP;
                if (result.decision.StartsWith("INDETERMINATE"))
                    result.reason = result.target.reason;
            }
            if (Definite(result.decision)) {
                List<Evaluation> supporters = new();
                foreach (Combining.State state in result.children)
                    if (state != null && state.evaluated != null &&
                        state.evaluated.decision.Equals(result.decision))
                        supporters.Add(state.evaluated);
                result.decisive = supporters.Count == 0 ? element : supporters[0].decisive;
                Attachments(result, supporters);
            }
            return result;
        }
    }
    public static List<string> TreeLines(Evaluation result, int depth) {
        PolicyParser.Element element = result.element;
        string target = result.target.result, prefix = new string(' ', 2 + 2 * depth),
               line = prefix + element.kind + " " + element.identifier + " " + element.behavior +
                      " target " + target;
        if (element.kind.Equals("rule") && target.Equals("MATCH"))
            line += " condition " + (result.condition is Failure      ? "INDETERMINATE"
                                     : Equals(result.condition, true) ? "TRUE"
                                                                      : "FALSE");
        List<string> lines = new();
        lines.Add(line + " -> " + DecisionNotation(result.decision, result.reason));
        if (!element.kind.Equals("rule") && !target.Equals("NO_MATCH"))
            for (int i = 0; i < element.children.Count; i++) {
                PolicyParser.Element child = element.children[i];
                Combining.State state = result.children[i];
                if (state != null && state.evaluated != null)
                    lines.AddRange(TreeLines(state.evaluated, depth + 1));
                else if (state == null)
                    lines.Add(prefix + "  " + child.kind + " " + child.identifier + " skipped");
                else {
                    Target checkedTarget = state.checkedTarget;
                    lines.Add(prefix + "  " + child.kind + " " + child.identifier + " " +
                              child.behavior + " target " + checkedTarget.result +
                              (checkedTarget.result.Equals("INDETERMINATE")
                                   ? " (" + checkedTarget.reason + ")"
                                   : ""));
                }
            }
        return lines;
    }
    public static void Add<K>(IDictionary<K, int> counts, K key, int amount) {
        counts.AddCount(key, amount);
    }
    public static string CheckRequest(Request request) {
        if (!subjects.ContainsKey(request.user))
            return "unknown user " + request.user;
        if (!resources.ContainsKey(request.resource))
            return "unknown resource " + request.resource;
        return request.environment.TryGetValue("day", out object day) && day is int value &&
                       value >= 1 && value <= 365
                   ? null
                   : "bad day";
    }
    public static Prepared Prepare(Request request) {
        int day = (int)request.environment["day"];
        SortedSet<string> authorized = rbac.Authorized(request.user, day);
        List<string> candidates = request.roles.Equals("-")   ? new()
                                  : request.roles.Equals("*") ? new(authorized)
                                                              : request.roles.Split(",").ToList();
        List<string> active = new();
        HashSet<string> seen = new();
        List<Activation> activations = new();
        foreach (string candidate in candidates) {
            string reason = null;
            if (!rbac.roles.Contains(candidate))
                reason = "unknown";
            else if (seen.Contains(candidate))
                reason = "duplicate";
            else if (!authorized.Contains(candidate))
                reason = "unauthorized";
            else {
                HashSet<string> proposed = new(active);
                proposed.Add(candidate);
                SortedSet<string> closure = rbac.Closure(proposed);
                foreach (Rbac.Constraint constraint in rbac.dsd) {
                    HashSet<string> intersection = new(constraint.roles);
                    intersection.IntersectWith(closure);
                    if (intersection.Count >= constraint.cardinality) {
                        reason = "dsd " + constraint.name;
                        break;
                    }
                }
            }
            seen.Add(candidate);
            if (reason == null)
                active.Add(candidate);
            activations.Add(new Activation(candidate, reason));
        }
        List<string> roles = new(rbac.Closure(active));
        Resource resource = resources[request.resource];
        string grant = null;
        foreach (string role in roles)
            if (rbac.permissions[role].Contains(
                    new Rbac.Permission(request.action, resource.type))) {
                grant = role;
                break;
            }
        Dictionary<string, object> values = new();
        foreach (var entry in subjects[request.user])
            values["subject." + entry.Key] = entry.Value;
        values["subject.id"] = request.user;
        values["subject.role"] = new List<string>(roles);
        values["subject.rbac"] = grant != null;
        foreach (var entry in resource.attributes)
            values["resource." + entry.Key] = entry.Value;
        values["resource.id"] = request.resource;
        values["resource.type"] = resource.type;
        values["action.id"] = request.action;
        foreach (var entry in request.environment)
            values["environment." + entry.Key] = entry.Value;
        return new Prepared(activations, roles, grant, values);
    }
    public static List<string> Trace(Request request, Prepared prepared, Evaluation result) {
        List<string> lines = new();
        lines.Add("request " + request.identifier);
        lines.Add("  user " + request.user + " resource " + request.resource + " type " +
                  resources[request.resource].type + " action " + request.action + " day " +
                  request.environment["day"]);
        foreach (Activation activation in prepared.activations)
            lines.Add("  activate " + activation.role +
                      (activation.reason == null ? " ok" : " refused " + activation.reason));
        lines.Add("  roles " +
                  (prepared.roles.Count == 0 ? "-" : string.Join(",", prepared.roles)));
        lines.Add("  rbac " + (prepared.grant == null ? "no" : "yes " + prepared.grant));
        lines.AddRange(TreeLines(result, 0));
        lines.Add("  decision " + FinalNotation(result));
        return lines;
    }
    public static List<string> JoinBlocks(List<List<string>> blocks) {
        List<string> lines = new();
        foreach (List<string> block in blocks) {
            if (lines.Count != 0)
                lines.Add("");
            lines.AddRange(block);
        }
        return lines;
    }
    public static List<List<string>> ProcessRequests() {
        List<string> lines = new();
        List<List<string>> explanations = new();
        foreach (Request request in requests) {
            Dictionary<string, char> symbols = new();
            foreach (PolicyParser.Element rule in rules)
                symbols[rule.identifier] = '.';
            string error = CheckRequest(request);
            if (error != null) {
                lines.Add(request.identifier + " ERROR " + error);
                Add(decisions, "ERROR", 1);
                if (request.explain)
                    explanations.Add(
                        new List<string> { "request " + request.identifier, "  error " + error });
            } else {
                Prepared prepared = Prepare(request);
                Evaluation result = new Evaluator(prepared.values, symbols).Evaluate(root);
                lines.Add(request.identifier + " " + FinalNotation(result));
                foreach (Activation activation in prepared.activations)
                    if (activation.reason != null) {
                        lines.Add("  refused " + activation.role + " " + activation.reason);
                        refused++;
                    }
                foreach (Item item in result.obligations) {
                    lines.Add("  obligation " + item.text);
                    Add(obligationCounts, item.identifier, 1);
                }
                foreach (Item item in result.advice) {
                    lines.Add("  advice " + item.text);
                    Add(adviceCounts, item.identifier, 1);
                }
                if (prepared.grant != null)
                    Add(grantCounts,
                        new Rbac.Grant(prepared.grant, request.action,
                                       resources[request.resource].type),
                        1);
                Add(decisions,
                    result.decision.StartsWith("INDETERMINATE") ? "INDETERMINATE" : result.decision,
                    1);
                if (Definite(result.decision))
                    Add(decisiveCounts, result.decisive.identifier, 1);
                if (request.explain)
                    explanations.Add(Trace(request, prepared, result));
            }
            foreach (PolicyParser.Element rule in rules)
                coverage[rule.identifier].Append(symbols[rule.identifier]);
        }
        return new List<List<string>> { lines, JoinBlocks(explanations) };
    }
    public static List<string> PermissionReport() {
        List<List<string>> blocks = new();
        SortedSet<string> users = new(StringComparer.Ordinal);
        foreach (Rbac.Assignment assignment in rbac.assignments)
            users.Add(assignment.user);
        IComparer<Rbac.Permission> order = Comparer<Rbac.Permission>.Default;
        foreach (string user in users) {
            SortedDictionary<string, HashSet<int>> assigned = new(StringComparer.Ordinal),
                                                   authorized = new(StringComparer.Ordinal);
            foreach (Rbac.Assignment assignment in rbac.assignments)
                if (assignment.user.Equals(user)) {
                    HashSet<int> days = assigned.GetOrAdd(assignment.role, key => new());
                    for (int day = assignment.first; day <= assignment.last; day++)
                        days.Add(day);
                }
            foreach (var entry in assigned)
                foreach (string role in rbac.Closure(new List<string> { entry.Key }))
                    authorized.GetOrAdd(role, key => new()).UnionWith(entry.Value);
            List<string> lines = new();
            lines.Add("user " + user);
            foreach (var entry in assigned)
                lines.Add("  assigned " + entry.Key + " " + Analysis.DayNotation(entry.Value));
            foreach (var entry in authorized)
                lines.Add("  authorized " + entry.Key + " " + Analysis.DayNotation(entry.Value));
            SortedDictionary<Rbac.Permission, List<string>> via = new(order);
            foreach (string role in authorized.Keys)
                foreach (Rbac.Permission permission in rbac.permissions[role])
                    via.GetOrAdd(permission, key => new()).Add(role);
            foreach (var entry in via) {
                Rbac.Permission permission = entry.Key;
                List<string> roles = entry.Value;
                HashSet<int> days = new();
                foreach (string role in roles)
                    days.UnionWith(authorized[role]);
                string effective = "-";
                if (subjects.ContainsKey(user)) {
                    int permitted = 0, total = 0;
                    foreach (var resource in resources)
                        if (resource.Value.type.Equals(permission.type)) {
                            total++;
                            Request request = new Request("", user, "*", permission.action,
                                                          resource.Key, reference, false);
                            Prepared prepared = Prepare(request);
                            if (new Evaluator(prepared.values, null)
                                    .Evaluate(root)
                                    .decision.Equals("PERMIT"))
                                permitted++;
                        }
                    effective = permitted + "/" + total;
                }
                lines.Add("  permission " + permission.action + " " + permission.type + " " +
                          Analysis.DayNotation(days) + " via " + string.Join(",", roles) +
                          " effective " + effective);
            }
            blocks.Add(lines);
        }
        return JoinBlocks(blocks);
    }
    public static List<string> DomainAnalysis() {
        Dictionary<string, int> counts = new();
        Dictionary<string, string> examples = new();
        Dictionary<ConflictPair, int> conflictCounts = new();
        HashSet<string> shadowed = new();
        Dictionary<string, HashSet<string>> blockers = new();
        List<ConflictPair> pairs = new();
        foreach (PolicyParser.Element rule in rules)
            if (rule.parent.behavior.Equals("first-applicable"))
                shadowed.Add(rule.identifier);
        foreach (PolicyParser.Element policy in elements)
            if (policy.kind.Equals("policy"))
                for (int i = 0; i < policy.children.Count; i++)
                    for (int j = i + 1; j < policy.children.Count; j++) {
                        PolicyParser.Element earlier = policy.children[i],
                                             later = policy.children[j];
                        if (!earlier.behavior.Equals(later.behavior))
                            pairs.Add(new ConflictPair(policy, earlier, later));
                    }
        int pointCount = 0;
        foreach (Dictionary<string, object> values in Analysis.Points(domains)) {
            pointCount++;
            Evaluator evaluator = new Evaluator(values, null);
            Dictionary<string, string> targets = new(), standalone = new();
            foreach (PolicyParser.Element element in elements)
                if (!element.kind.Equals("rule"))
                    targets[element.identifier] = evaluator.Target(element).result;
            foreach (PolicyParser.Element rule in rules)
                standalone[rule.identifier] = evaluator.Rule(rule, false).decision;
            HashSet<string> applying = new();
            foreach (PolicyParser.Element rule in rules) {
                string identifier = rule.identifier;
                if (!Definite(standalone[identifier]))
                    continue;
                bool ancestors = true;
                for (PolicyParser.Element parent = rule.parent; parent != null;
                     parent = parent.parent)
                    if (!targets[parent.identifier].Equals("MATCH"))
                        ancestors = false;
                if (!ancestors)
                    continue;
                applying.Add(identifier);
                Add(counts, identifier, 1);
                if (!examples.ContainsKey(identifier)) {
                    List<string> assignments = new();
                    foreach (Analysis.Domain domain in domains)
                        if (domain.values.Count >= 2)
                            assignments.Add(domain.name + "=" + ValueNotation(values[domain.name]));
                    examples[identifier] = string.Join(" ", assignments);
                }
                if (shadowed.Contains(identifier)) {
                    string earlier = Analysis.Blocker(rule, standalone);
                    if (earlier == null)
                        shadowed.Remove(identifier);
                    else
                        blockers.GetOrAdd(identifier, key => new()).Add(earlier);
                }
            }
            foreach (ConflictPair pair in pairs)
                if (applying.Contains(pair.earlier.identifier) &&
                    applying.Contains(pair.later.identifier))
                    Add(conflictCounts, pair, 1);
        }
        List<string> lines = new();
        lines.Add("applicability " + pointCount);
        List<string> dead = new();
        foreach (PolicyParser.Element rule in rules) {
            int count = counts.GetValueOrDefault(rule.identifier, 0);
            lines.Add("  " + rule.identifier + " " + count + " " +
                      examples.GetValueOrDefault(rule.identifier, "-"));
            if (count == 0)
                dead.Add(rule.identifier);
        }
        lines.Add("dead " + dead.Count);
        foreach (string identifier in dead)
            lines.Add("  " + identifier);
        shadowed.ExceptWith(dead);
        lines.Add("shadowed " + shadowed.Count);
        foreach (PolicyParser.Element rule in rules)
            if (shadowed.Contains(rule.identifier)) {
                List<string> names = new();
                foreach (PolicyParser.Element earlier in rules)
                    if (blockers.GetValueOrDefault(rule.identifier, new HashSet<string> {})
                            .Contains(earlier.identifier))
                        names.Add(earlier.identifier);
                lines.Add("  " + rule.identifier + " by " + string.Join(",", names));
            }
        int conflictCount = 0;
        foreach (ConflictPair pair in pairs)
            if (conflictCounts.GetValueOrDefault(pair, 0) > 0)
                conflictCount++;
        lines.Add("conflicts " + conflictCount);
        foreach (ConflictPair pair in pairs) {
            int count = conflictCounts.GetValueOrDefault(pair, 0);
            if (count > 0)
                lines.Add("  " + pair.policy.identifier + " " + pair.earlier.identifier + " " +
                          pair.later.identifier + " " + count + " " +
                          Analysis.ConflictWinner(pair.policy, pair.earlier, pair.later));
        }
        return lines;
    }
    public static List<string> AnalysisReport() {
        List<string> lines = new();
        lines.Add("rbac " + rbac.diagnostics.Count);
        foreach (Rbac.Diagnostic diagnostic in rbac.diagnostics)
            lines.Add("  line " + diagnostic.line + " " + diagnostic.keyword + " " +
                      diagnostic.message);
        lines.Add("grants " + rbac.grants.Count);
        foreach (Rbac.Grant grant in rbac.grants)
            lines.Add("  " + grant.role + " " + grant.action + " " + grant.type + " " +
                      grantCounts.GetValueOrDefault(grant, 0));
        lines.AddRange(DomainAnalysis());
        lines.Add("coverage " + requests.Count);
        List<string> uncovered = new();
        foreach (PolicyParser.Element rule in rules) {
            string symbols = coverage[rule.identifier].ToString();
            int count = 0;
            foreach (char c in symbols.ToCharArray())
                if (c == 'P' || c == 'D')
                    count++;
            lines.Add("  " + rule.identifier + " " + symbols + " " + count);
            if (count == 0)
                uncovered.Add(rule.identifier);
        }
        lines.Add("uncovered " + uncovered.Count);
        foreach (string identifier in uncovered)
            lines.Add("  " + identifier);
        lines.Add("summary");
        foreach (string name in new List<string> { "PERMIT", "DENY", Combining.NA, "INDETERMINATE",
                                                   "ERROR" })
            lines.Add("  decision " + name + " " + decisions.GetValueOrDefault(name, 0));
        lines.Add("  refused " + refused);
        foreach (PolicyParser.Element element in elements) {
            int count = decisiveCounts.GetValueOrDefault(element.identifier, 0);
            if (count > 0)
                lines.Add("  decisive " + element.identifier + " " + count);
        }
        foreach (var entry in obligationCounts)
            lines.Add("  obligation " + entry.Key + " " + entry.Value);
        foreach (var entry in adviceCounts)
            lines.Add("  advice " + entry.Key + " " + entry.Value);
        return lines;
    }
    public static void ReadInputs() {
        rbac = new Rbac();
        PolicyParser.Policies policies = PolicyParser.Read();
        root = policies.root;
        elements = policies.elements;
        rules = new();
        foreach (PolicyParser.Element element in elements)
            if (element.kind.Equals("rule")) {
                rules.Add(element);
                coverage[element.identifier] = new StringBuilder();
            }
        foreach (string line in File.ReadAllLines(Path.Combine("input", "attributes.txt"))
                     .ToList()) {
            List<string> fields = line.Split(" ").ToList();
            switch (fields[0]) {
            case "SUBJECT":
                subjects[fields[1]] = Attributes(fields.GetRange(2, fields.Count - 2));
                break;
            case "RESOURCE":
                resources[fields[1]] =
                    new Resource(fields[2], Attributes(fields.GetRange(3, fields.Count - 3)));
                break;
            case "DOMAIN": {
                List<object> values = new();
                foreach (string value in fields.GetRange(2, fields.Count - 2))
                    values.Add(InputValue(value));
                domains.Add(new Analysis.Domain(fields[1], values));
                break;
            }
            default:
                reference = Attributes(fields.GetRange(1, fields.Count - 1));
                break;
            }
        }
        foreach (string line in File.ReadAllLines(Path.Combine("input", "requests.txt")).ToList()) {
            List<string> fields = new(line.Split(" ").ToList());
            bool explain = fields[^1].Equals("EXPLAIN");
            if (explain)
                fields.RemoveAt(fields.Count - 1);
            requests.Add(new Request(fields[0], fields[1], fields[2], fields[3], fields[4],
                                     Attributes(fields.GetRange(5, fields.Count - 5)), explain));
        }
    }
    public static void Write(string name, List<string> lines) {
        File.WriteAllText(Path.Combine("output", name),
                          string.Join("\n", lines) + (lines.Count == 0 ? "" : "\n"));
    }
    public static void Main(string[] args) {
        CultureInfo.CurrentCulture=CultureInfo.InvariantCulture;
        ReadInputs();
        List<List<string>> reports = ProcessRequests();
        Directory.CreateDirectory(Path.Combine("output"));
        Write("decisions.txt", reports[0]);
        Write("traces.txt", reports[1]);
        Write("permissions.txt", PermissionReport());
        Write("analysis.txt", AnalysisReport());
    }
}
public static class CollectionHelpers {
    public static void AddCount<K>(this IDictionary<K, int> map, K key, int amount) {
        map.TryGetValue(key, out int old);
        map[key] = old + amount;
    }
    public static V GetOrAdd<K, V>(this IDictionary<K, V> map, K key, Func<K, V> factory) {
        if (!map.TryGetValue(key, out V value)) {
            value = factory(key);
            map[key] = value;
        }
        return value;
    }
}
