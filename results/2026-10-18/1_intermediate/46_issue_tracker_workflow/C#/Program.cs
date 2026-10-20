#nullable enable
using System;
using System.Collections.Generic;
using System.Linq;

static class Rules
{
    public static readonly string[] Types = { "BUG", "TASK", "STORY" };
    public static readonly string[] Priorities = { "LOW", "MEDIUM", "HIGH", "CRITICAL" };
    public static readonly Dictionary<string, string[]> Workflows = new()
    {
        ["BUG"] = new[] { "OPEN", "TRIAGED", "IN_PROGRESS", "REVIEW", "RESOLVED", "CLOSED", "REOPENED" },
        ["TASK"] = new[] { "OPEN", "IN_PROGRESS", "DONE" },
        ["STORY"] = new[] { "BACKLOG", "READY", "IN_PROGRESS", "REVIEW", "DONE" }
    };
    public static readonly Dictionary<string, HashSet<string>> Transitions = new()
    {
        ["BUG"] = new() { "OPEN>TRIAGED", "TRIAGED>IN_PROGRESS", "IN_PROGRESS>REVIEW", "REVIEW>IN_PROGRESS", "REVIEW>RESOLVED", "RESOLVED>CLOSED", "RESOLVED>REOPENED", "CLOSED>REOPENED", "REOPENED>IN_PROGRESS" },
        ["TASK"] = new() { "OPEN>IN_PROGRESS", "IN_PROGRESS>OPEN", "IN_PROGRESS>DONE" },
        ["STORY"] = new() { "BACKLOG>READY", "READY>BACKLOG", "READY>IN_PROGRESS", "IN_PROGRESS>REVIEW", "REVIEW>IN_PROGRESS", "REVIEW>DONE" }
    };
    public static readonly HashSet<string> AllStates = Workflows.Values.SelectMany(x => x).ToHashSet();
    public static readonly HashSet<int> Estimates = new() { 0, 1, 2, 3, 5, 8, 13, 21 };
    public static readonly string[] Equality = { "=", "!=" };
    public static readonly string[] Ordered = { "=", "!=", "<", "<=", ">", ">=" };
    public static readonly Dictionary<string, string[]> FieldOperators = new()
    {
        ["id"] = Ordered, ["type"] = Equality, ["status"] = Equality, ["priority"] = Ordered,
        ["assignee"] = Equality, ["reviewer"] = Equality, ["estimate"] = Ordered, ["sprint"] = Equality,
        ["comments"] = Ordered, ["blocked"] = Equality, ["done"] = Equality, ["title"] = new[] { "~" }
    };
    public static bool IsDone(string state) => state is "RESOLVED" or "CLOSED" or "DONE";
    public static string Display(object? value) => value?.ToString() ?? "-";
    public static string YesNo(bool value) => value ? "yes" : "no";
    public static string NumberList(SortedSet<int> values) => values.Count == 0 ? "-" : string.Join(",", values);
}

sealed class CommandError : Exception
{
    public CommandError(string message) : base(message) { }
}

sealed class Issue
{
    public int Number { get; }
    public string Kind { get; }
    public string Title { get; }
    public string Priority { get; set; }
    public string State { get; set; }
    public string? Assignee { get; set; }
    public string? Reviewer { get; set; }
    public int? Estimate { get; set; }
    public string? Sprint { get; set; }
    public int Comments { get; set; }
    public SortedSet<int> Blocks { get; } = new();
    public SortedSet<int> Blockers { get; } = new();
    public int? Duplicate { get; set; }
    public SortedSet<int> Duplicates { get; } = new();
    public List<string> History { get; } = new();
    public bool Done => Rules.IsDone(State);
    public int Points => Estimate ?? 0;
    public int Level => Array.IndexOf(Rules.Priorities, Priority);

    public Issue(int number, string kind, string priority, string title)
    {
        Number = number;
        Kind = kind;
        Priority = priority;
        Title = title;
        State = Rules.Workflows[kind][0];
    }
}

sealed class Sprint
{
    public string Name { get; }
    public string Phase { get; set; } = "PLANNED";
    public int? Start { get; set; }
    public int? End { get; set; }
    public int Velocity { get; set; }
    public Dictionary<int, int> Records { get; } = new();
    public Sprint(string name) { Name = name; }
}

sealed record Condition(string Field, string Operation, object? Value)
{
    public bool Matches(Tracker tracker, Issue issue)
    {
        object? actual = tracker.FieldValue(issue, Field);
        if (Operation == "~") return ((string)actual!).Contains((string)Value!, StringComparison.Ordinal);
        if (Operation == "=") return Equals(actual, Value);
        if (Operation == "!=") return !Equals(actual, Value);
        if (actual is not int a || Value is not int b) return false;
        return Operation switch { "<" => a < b, "<=" => a <= b, ">" => a > b, _ => a >= b };
    }
}

abstract record QueryNode
{
    public abstract bool Matches(Tracker tracker, Issue issue);
}
sealed record ConditionNode(Condition Condition) : QueryNode
{
    public override bool Matches(Tracker tracker, Issue issue) => Condition.Matches(tracker, issue);
}
sealed record NotNode(QueryNode Operand) : QueryNode
{
    public override bool Matches(Tracker tracker, Issue issue) => !Operand.Matches(tracker, issue);
}
sealed record BinaryNode(string Operation, QueryNode Left, QueryNode Right) : QueryNode
{
    public override bool Matches(Tracker tracker, Issue issue) => Operation == "AND"
        ? Left.Matches(tracker, issue) && Right.Matches(tracker, issue)
        : Left.Matches(tracker, issue) || Right.Matches(tracker, issue);
}

sealed class QueryParser
{
    readonly List<string> tokens;
    readonly List<Condition?> conditions;
    int position;
    public QueryParser(List<string> tokens, List<Condition?> conditions)
    {
        this.tokens = tokens;
        this.conditions = conditions;
    }
    bool Accept(string token)
    {
        if (position >= tokens.Count || tokens[position] != token) return false;
        position++;
        return true;
    }
    public QueryNode Expression()
    {
        QueryNode node = Term();
        while (Accept("OR")) node = new BinaryNode("OR", node, Term());
        return node;
    }
    QueryNode Term()
    {
        QueryNode node = Factor();
        while (Accept("AND")) node = new BinaryNode("AND", node, Factor());
        return node;
    }
    QueryNode Factor()
    {
        if (Accept("NOT")) return new NotNode(Factor());
        if (Accept("("))
        {
            QueryNode node = Expression();
            Accept(")");
            return node;
        }
        return new ConditionNode(conditions[position++]!);
    }
}

sealed class Tracker
{
    int day = 1;
    readonly SortedSet<string> users = new(StringComparer.Ordinal);
    readonly SortedDictionary<int, Issue> issues = new();
    readonly Dictionary<string, Sprint> sprints = new(StringComparer.Ordinal);
    readonly List<Sprint> sprintOrder = new();
    Sprint? ActiveSprint => sprintOrder.FirstOrDefault(s => s.Phase == "ACTIVE");

    Issue RequireIssue(string text) => issues.TryGetValue(int.Parse(text), out Issue? issue)
        ? issue : throw new CommandError("unknown issue");
    string? RequireUser(string text)
    {
        if (text == "-") return null;
        if (!users.Contains(text)) throw new CommandError("unknown user");
        return text;
    }
    Sprint RequireSprint(string name) => sprints.TryGetValue(name, out Sprint? sprint)
        ? sprint : throw new CommandError("unknown sprint");
    static void RequireNotDone(Issue issue)
    {
        if (issue.Done) throw new CommandError("issue done");
    }
    void Record(Issue issue, string content) => issue.History.Add($"day {day} {content}");
    List<int> UnfinishedBlockers(Issue issue) => issue.Blockers.Where(n => !issues[n].Done).ToList();
    bool Blocked(Issue issue) => !issue.Done && issue.Blockers.Any(n => !issues[n].Done);
    int Wip(string? user) => issues.Values.Count(i => i.Assignee == user && i.State == "IN_PROGRESS");
    List<Issue> Members(Sprint sprint) => issues.Values.Where(i => i.Sprint == sprint.Name).ToList();
    int Remaining(Sprint sprint) => Members(sprint).Where(i => !i.Done).Sum(i => i.Points);
    string Summary(Sprint sprint)
    {
        List<Issue> members = Members(sprint);
        return $"issues {members.Count} points {members.Sum(i => i.Points)}";
    }
    List<string> Notify(Dictionary<int, bool> before)
    {
        var lines = new List<string>();
        foreach (int number in before.Keys.OrderBy(n => n))
        {
            bool after = Blocked(issues[number]);
            if (before[number] != after) lines.Add($"{(after ? "BLOCKED" : "UNBLOCKED")} {number}");
        }
        return lines;
    }
    List<string> ChangeState(Issue issue, string target)
    {
        var before = issue.Blocks.ToDictionary(n => n, n => Blocked(issues[n]));
        var lines = new List<string> { $"MOVE {issue.Number} {issue.State} {target}" };
        Record(issue, $"MOVE {issue.State} {target}");
        issue.State = target;
        lines.AddRange(Notify(before));
        return lines;
    }
    bool Reaches(int start, int goal)
    {
        var pending = new Stack<int>();
        var seen = new HashSet<int>();
        pending.Push(start);
        while (pending.Count > 0)
        {
            int number = pending.Pop();
            if (number == goal) return true;
            if (seen.Add(number)) foreach (int child in issues[number].Blocks) pending.Push(child);
        }
        return false;
    }

    public object? FieldValue(Issue issue, string field) => field switch
    {
        "id" => issue.Number, "type" => issue.Kind, "status" => issue.State, "priority" => issue.Level,
        "assignee" => issue.Assignee, "reviewer" => issue.Reviewer, "estimate" => issue.Estimate,
        "sprint" => issue.Sprint, "comments" => issue.Comments, "blocked" => Rules.YesNo(Blocked(issue)),
        "done" => Rules.YesNo(issue.Done), _ => issue.Title.ToLowerInvariant()
    };

    Condition ParseCondition(string token)
    {
        int length = 0;
        while (length < token.Length && token[length] >= 'a' && token[length] <= 'z') length++;
        string field = token[..length];
        string rest = token[length..];
        string? operation = new[] { ">=", "<=", "!=", "=", "<", ">", "~" }.FirstOrDefault(op => rest.StartsWith(op, StringComparison.Ordinal));
        if (field.Length == 0 || operation == null || rest.Length == operation.Length) throw new CommandError($"syntax near {token}");
        string text = rest[operation.Length..];
        if (!Rules.FieldOperators.TryGetValue(field, out string[]? allowed)) throw new CommandError($"unknown field {field}");
        if (!allowed.Contains(operation)) throw new CommandError($"bad operator {token}");
        object? value;
        if (text == "-" && new[] { "assignee", "reviewer", "estimate", "sprint" }.Contains(field) && Rules.Equality.Contains(operation)) value = null;
        else if (new[] { "id", "estimate", "comments" }.Contains(field) && text.Length is >= 1 and <= 6 && text.All(c => c >= '0' && c <= '9')) value = int.Parse(text);
        else if (field == "priority" && Rules.Priorities.Contains(text)) value = Array.IndexOf(Rules.Priorities, text);
        else if (field == "type" && Rules.Types.Contains(text)) value = text;
        else if (field == "status" && Rules.AllStates.Contains(text)) value = text;
        else if ((field is "assignee" or "reviewer") && users.Contains(text)) value = text;
        else if (field == "sprint" && sprints.ContainsKey(text)) value = text;
        else if ((field is "blocked" or "done") && (text is "yes" or "no")) value = text;
        else if (field == "title") value = text.ToLowerInvariant();
        else throw new CommandError($"bad value {token}");
        return new Condition(field, operation, value);
    }

    List<string> Query(string text)
    {
        var tokens = new List<string>();
        int position = 0;
        while (position < text.Length)
        {
            if (text[position] == ' ') { position++; continue; }
            if (text[position] is '(' or ')') { tokens.Add(text[position++].ToString()); continue; }
            int start = position;
            while (position < text.Length && text[position] != ' ' && text[position] != '(' && text[position] != ')') position++;
            tokens.Add(text[start..position]);
        }
        bool expectingOperand = true;
        int depth = 0;
        var conditions = new List<Condition?>();
        foreach (string token in tokens)
        {
            Condition? condition = null;
            if (expectingOperand)
            {
                if (token == "(") depth++;
                else if (token is "AND" or "OR" or ")") throw new CommandError($"syntax near {token}");
                else if (token != "NOT") { condition = ParseCondition(token); expectingOperand = false; }
            }
            else if (token is "AND" or "OR") expectingOperand = true;
            else if (token == ")" && depth > 0) depth--;
            else throw new CommandError($"syntax near {token}");
            conditions.Add(condition);
        }
        if (expectingOperand || depth != 0) throw new CommandError("syntax at end");
        QueryNode tree = new QueryParser(tokens, conditions).Expression();
        List<Issue> matches = issues.Values.Where(i => tree.Matches(this, i)).OrderByDescending(i => i.Level).ThenBy(i => i.Number).ToList();
        var lines = new List<string> { $"QUERY {matches.Count}" };
        lines.AddRange(matches.Select(i => $"{i.Number} {i.Kind} {i.Priority} {i.State} {Rules.Display(i.Assignee)} {Rules.Display(i.Estimate)} {i.Title}"));
        return lines;
    }

    List<string> SprintCommand(string[] words)
    {
        string action = words[1], name = words[2];
        if (action == "NEW")
        {
            if (sprints.ContainsKey(name)) throw new CommandError("sprint exists");
            var created = new Sprint(name);
            sprints.Add(name, created);
            sprintOrder.Add(created);
            return new() { $"SPRINT NEW {name}" };
        }
        Sprint sprint = RequireSprint(name);
        if (action is "ADD" or "REMOVE")
        {
            Issue issue = RequireIssue(words[3]);
            if (sprint.Phase == "ENDED") throw new CommandError("sprint ended");
            if (action == "ADD")
            {
                RequireNotDone(issue);
                if (issue.Sprint != null && sprints[issue.Sprint].Phase != "ENDED") throw new CommandError($"in sprint {issue.Sprint}");
                if (issue.State == "BACKLOG") throw new CommandError("not ready");
                issue.Sprint = name;
            }
            else
            {
                if (issue.Sprint != name) throw new CommandError("not in sprint");
                RequireNotDone(issue);
                issue.Sprint = null;
            }
            Record(issue, $"SPRINT {action} {name}");
            return new() { $"SPRINT {action} {name} {issue.Number} {Summary(sprint)}" };
        }
        if (action == "START")
        {
            if (sprint.Phase != "PLANNED") throw new CommandError("sprint not planned");
            if (ActiveSprint is Sprint active) throw new CommandError($"sprint active {active.Name}");
            if (Members(sprint).Count == 0) throw new CommandError("sprint empty");
            sprint.Phase = "ACTIVE";
            sprint.Start = day;
            int remaining = Remaining(sprint);
            sprint.Records[day] = remaining;
            return new() { $"SPRINT START {name} day {day} {Summary(sprint)} remaining {remaining}" };
        }
        if (sprint.Phase != "ACTIVE") throw new CommandError("sprint not active");
        sprint.Records[day] = Remaining(sprint);
        List<Issue> members = Members(sprint);
        List<Issue> finished = members.Where(i => i.Done).ToList();
        List<Issue> returned = members.Where(i => !i.Done).ToList();
        sprint.Velocity = finished.Sum(i => i.Points);
        sprint.Phase = "ENDED";
        sprint.End = day;
        var lines = new List<string> { $"SPRINT END {name} day {day} velocity {sprint.Velocity} done {finished.Count} returned {returned.Count}" };
        foreach (Issue issue in returned)
        {
            issue.Sprint = null;
            Record(issue, $"SPRINT RETURN {name}");
            lines.Add($"RETURNED {issue.Number}");
        }
        return lines;
    }

    List<string> Command(string line)
    {
        string[] words = line.Split(' ');
        string command = words[0];
        switch (command)
        {
            case "DAY":
                int targetDay = int.Parse(words[1]);
                if (targetDay < day) throw new CommandError("day backwards");
                day = targetDay;
                return new() { $"DAY {day}" };
            case "USER":
                if (!users.Add(words[1])) throw new CommandError("user exists");
                return new() { $"USER {words[1]}" };
            case "CREATE":
            {
                int number = int.Parse(words[1]);
                string kind = words[2], priority = words[3];
                if (issues.ContainsKey(number)) throw new CommandError("issue exists");
                if (!Rules.Types.Contains(kind)) throw new CommandError("bad type");
                if (!Rules.Priorities.Contains(priority)) throw new CommandError("bad priority");
                var issue = new Issue(number, kind, priority, string.Join(" ", words.Skip(4)));
                issues.Add(number, issue);
                Record(issue, $"CREATE {kind} {priority}");
                return new() { $"CREATE {number} {kind} {priority} {issue.State}" };
            }
            case "PRIORITY":
            {
                Issue issue = RequireIssue(words[1]);
                string priority = words[2];
                if (!Rules.Priorities.Contains(priority)) throw new CommandError("bad priority");
                RequireNotDone(issue);
                if (priority == issue.Priority) throw new CommandError("no change");
                string old = issue.Priority;
                issue.Priority = priority;
                Record(issue, $"PRIORITY {old} {priority}");
                return new() { $"PRIORITY {issue.Number} {old} {priority}" };
            }
            case "ASSIGN":
            case "REVIEWER":
            {
                Issue issue = RequireIssue(words[1]);
                string? user = RequireUser(words[2]);
                RequireNotDone(issue);
                if (command == "ASSIGN")
                {
                    if (user == issue.Assignee) throw new CommandError("no change");
                    if (user == null && (issue.State is "IN_PROGRESS" or "REVIEW")) throw new CommandError("assignee required");
                    if (issue.State == "IN_PROGRESS" && Wip(user) >= 3) throw new CommandError($"wip limit {words[2]}");
                    if (issue.State == "REVIEW" && user == issue.Reviewer) throw new CommandError("reviewer is assignee");
                    issue.Assignee = user;
                }
                else
                {
                    if (user == issue.Reviewer) throw new CommandError("no change");
                    if (issue.State == "REVIEW" && user == null) throw new CommandError("reviewer required");
                    if (issue.State == "REVIEW" && user == issue.Assignee) throw new CommandError("reviewer is assignee");
                    issue.Reviewer = user;
                }
                Record(issue, $"{command} {words[2]}");
                return new() { $"{command} {issue.Number} {words[2]}" };
            }
            case "ESTIMATE":
            {
                Issue issue = RequireIssue(words[1]);
                int points = int.Parse(words[2]);
                if (!Rules.Estimates.Contains(points)) throw new CommandError("bad estimate");
                RequireNotDone(issue);
                if (issue.Estimate == points) throw new CommandError("no change");
                string old = Rules.Display(issue.Estimate);
                issue.Estimate = points;
                Record(issue, $"ESTIMATE {old} {points}");
                return new() { $"ESTIMATE {issue.Number} {old} {points}" };
            }
            case "COMMENT":
            {
                Issue issue = RequireIssue(words[1]);
                RequireUser(words[2]);
                issue.Comments++;
                Record(issue, $"COMMENT {words[2]} {string.Join(" ", words.Skip(3))}");
                return new() { $"COMMENT {issue.Number} {issue.Comments}" };
            }
            case "MOVE":
            {
                Issue issue = RequireIssue(words[1]);
                string target = words[2];
                if (issue.Duplicate != null) throw new CommandError($"duplicate of {issue.Duplicate}");
                if (!Rules.Workflows[issue.Kind].Contains(target)) throw new CommandError("bad state");
                if (!Rules.Transitions[issue.Kind].Contains($"{issue.State}>{target}")) throw new CommandError($"cannot move {issue.State} to {target}");
                if (target == "IN_PROGRESS")
                {
                    if (issue.Kind == "STORY" && (ActiveSprint == null || issue.Sprint != ActiveSprint.Name)) throw new CommandError("not in active sprint");
                    if (issue.Assignee == null) throw new CommandError("no assignee");
                    if (Wip(issue.Assignee) >= 3) throw new CommandError($"wip limit {issue.Assignee}");
                }
                if (target == "REVIEW")
                {
                    if (issue.Reviewer == null) throw new CommandError("no reviewer");
                    if (issue.Reviewer == issue.Assignee) throw new CommandError("reviewer is assignee");
                }
                if (target is "DONE" or "RESOLVED")
                {
                    List<int> blockers = UnfinishedBlockers(issue);
                    if (blockers.Count > 0) throw new CommandError($"blocked by {blockers[0]}");
                }
                if (target == "READY" && issue.Estimate == null) throw new CommandError("no estimate");
                return ChangeState(issue, target);
            }
            case "LINK":
            case "UNLINK":
            {
                string relation = words[2];
                bool unlink = command == "UNLINK";
                if (relation != "BLOCKS" && (unlink || relation != "DUPLICATES")) throw new CommandError("bad link");
                Issue a = RequireIssue(words[1]), b = RequireIssue(words[3]);
                if (unlink)
                {
                    if (!a.Blocks.Contains(b.Number)) throw new CommandError("no link");
                }
                else
                {
                    if (a.Number == b.Number) throw new CommandError("self link");
                    if (relation == "BLOCKS")
                    {
                        if (a.Blocks.Contains(b.Number)) throw new CommandError("link exists");
                        if (Reaches(b.Number, a.Number)) throw new CommandError("cycle");
                        RequireNotDone(b);
                    }
                    else
                    {
                        if (a.Kind != b.Kind) throw new CommandError("type mismatch");
                        RequireNotDone(a);
                        if (b.Duplicate != null) throw new CommandError("target is duplicate");
                        a.Duplicate = b.Number;
                        b.Duplicates.Add(a.Number);
                        Record(a, $"LINK DUPLICATES {b.Number}");
                        Record(b, $"LINK DUPLICATED_BY {a.Number}");
                        var lines = new List<string> { $"LINK {a.Number} DUPLICATES {b.Number}" };
                        lines.AddRange(ChangeState(a, a.Kind == "BUG" ? "CLOSED" : "DONE"));
                        if (a.Sprint != null && sprints[a.Sprint].Phase != "ENDED")
                        {
                            string old = a.Sprint;
                            a.Sprint = null;
                            Record(a, $"SPRINT REMOVE {old}");
                        }
                        return lines;
                    }
                }
                var before = new Dictionary<int, bool> { [b.Number] = Blocked(b) };
                if (unlink) { a.Blocks.Remove(b.Number); b.Blockers.Remove(a.Number); }
                else { a.Blocks.Add(b.Number); b.Blockers.Add(a.Number); }
                Record(a, $"{command} BLOCKS {b.Number}");
                Record(b, $"{command} BLOCKED_BY {a.Number}");
                var result = new List<string> { $"{command} {a.Number} BLOCKS {b.Number}" };
                result.AddRange(Notify(before));
                return result;
            }
            case "SPRINT": return SprintCommand(words);
            case "QUERY": return Query(string.Join(" ", words.Skip(1)));
            case "SHOW":
            {
                Issue issue = RequireIssue(words[1]);
                return new()
                {
                    $"ISSUE {issue.Number} {issue.Kind} {issue.Priority} {issue.State} blocked {Rules.YesNo(Blocked(issue))}",
                    $"TITLE {issue.Title}",
                    $"PEOPLE assignee {Rules.Display(issue.Assignee)} reviewer {Rules.Display(issue.Reviewer)}",
                    $"PLAN estimate {Rules.Display(issue.Estimate)} sprint {Rules.Display(issue.Sprint)} comments {issue.Comments}",
                    $"LINKS blocks {Rules.NumberList(issue.Blocks)} blocked_by {Rules.NumberList(issue.Blockers)} duplicate_of {Rules.Display(issue.Duplicate)} duplicated_by {Rules.NumberList(issue.Duplicates)}"
                };
            }
            case "HISTORY":
            {
                Issue issue = RequireIssue(words[1]);
                var lines = new List<string> { $"HISTORY {issue.Number} {issue.History.Count}" };
                lines.AddRange(issue.History);
                return lines;
            }
            case "BOARD":
            {
                var lines = new List<string> { "BOARD" };
                foreach (string kind in Rules.Types)
                    lines.Add(kind + string.Concat(Rules.Workflows[kind].Select(state => $" {state} {issues.Values.Count(i => i.Kind == kind && i.State == state)}")));
                int done = issues.Values.Count(i => i.Done);
                lines.Add($"TOTAL {issues.Count} open {issues.Count - done} done {done}");
                return lines;
            }
            case "WORKLOAD":
            {
                var lines = new List<string> { $"WORKLOAD {users.Count}" };
                foreach (string user in users)
                {
                    List<Issue> assigned = issues.Values.Where(i => !i.Done && i.Assignee == user).ToList();
                    int progress = assigned.Count(i => i.State == "IN_PROGRESS");
                    int review = assigned.Count(i => i.State == "REVIEW");
                    int reviewing = issues.Values.Count(i => i.Reviewer == user && i.State == "REVIEW");
                    lines.Add($"{user} assigned {assigned.Count} in_progress {progress} review {review} reviewing {reviewing} points {assigned.Sum(i => i.Points)}");
                }
                return lines;
            }
            case "SPRINTS":
            {
                var lines = new List<string> { $"SPRINTS {sprintOrder.Count}" };
                foreach (Sprint sprint in sprintOrder)
                    lines.Add(sprint.Phase switch
                    {
                        "PLANNED" => $"{sprint.Name} PLANNED {Summary(sprint)}",
                        "ACTIVE" => $"{sprint.Name} ACTIVE start {sprint.Start} {Summary(sprint)} remaining {Remaining(sprint)}",
                        _ => $"{sprint.Name} ENDED start {sprint.Start} end {sprint.End} velocity {sprint.Velocity}"
                    });
                return lines;
            }
            case "BURNDOWN":
            {
                Sprint sprint = RequireSprint(words[1]);
                if (sprint.Phase == "PLANNED") throw new CommandError("sprint not started");
                int start = sprint.Start!.Value, last = sprint.Phase == "ACTIVE" ? day : sprint.End!.Value;
                var lines = new List<string> { $"BURNDOWN {sprint.Name} {sprint.Phase} days {last - start + 1}" };
                int points = 0;
                for (int date = start; date <= last; date++)
                {
                    if (sprint.Records.TryGetValue(date, out int recorded)) points = recorded;
                    lines.Add($"day {date} {points}");
                }
                return lines;
            }
            default: throw new InvalidOperationException("Unknown command");
        }
    }

    public List<string> Execute(string line)
    {
        List<string> lines;
        try { lines = Command(line); }
        catch (CommandError error) { lines = new() { $"ERROR {error.Message}" }; }
        if (ActiveSprint is Sprint sprint) sprint.Records[day] = Remaining(sprint);
        return lines;
    }
}

static class Program
{
    static void Main()
    {
        int count = int.Parse(Console.ReadLine()!);
        var tracker = new Tracker();
        using var output = new System.IO.StreamWriter(Console.OpenStandardOutput()) { NewLine = "\n" };
        for (int i = 0; i < count; i++)
            foreach (string line in tracker.Execute(Console.ReadLine()!)) output.WriteLine(line);
    }
}
