using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;

int count = int.Parse(Console.ReadLine()!);
var registrar = new Registrar();
for (int i = 0; i < count; ++i)
    registrar.Execute(Console.ReadLine()!);
Console.Write(registrar.Output());

static class Rules
{
    public static readonly string[] Days = { "MO", "TU", "WE", "TH", "FR", "SA", "SU" };
    public static readonly Dictionary<string, int> GradePoints = new(StringComparer.Ordinal)
    {
        ["A"] = 4, ["B"] = 3, ["C"] = 2, ["D"] = 1, ["F"] = 0
    };

    public static string Time(int minutes) => $"{minutes / 60:00}:{minutes % 60:00}";

    public static string Rate(int count, int capacity) =>
        capacity == 0 ? "n/a" : $"{count * 100 / capacity}%";

    public static bool Overlaps(Slot a, Slot b) =>
        a.Day == b.Day && a.Start < b.End && b.Start < a.End;

    public static List<Slot> ParseSlots(string text)
    {
        if (text == "-") return new List<Slot>();

        var slots = new List<Slot>();
        foreach (string raw in text.Split(','))
        {
            string day = raw[..2];
            int startHour = int.Parse(raw.Substring(2, 2));
            int startMinute = int.Parse(raw.Substring(4, 2));
            int endHour = int.Parse(raw.Substring(7, 2));
            int endMinute = int.Parse(raw.Substring(9, 2));
            int start = 60 * startHour + startMinute;
            int end = 60 * endHour + endMinute;
            if (!Days.Contains(day) || startHour > 23 || startMinute > 59 ||
                endHour > 23 || endMinute > 59 || start >= end)
                throw new CommandError($"invalid slot {raw}");
            slots.Add(new Slot(day, start, end, raw));
        }

        for (int i = 0; i < slots.Count; ++i)
            for (int j = i + 1; j < slots.Count; ++j)
                if (Overlaps(slots[i], slots[j]))
                    throw new CommandError(
                        $"overlapping slots {slots[i].Raw} {slots[j].Raw}");

        return slots;
    }

    public static string Canonical(Expr? expr)
    {
        if (expr is null) return "-";
        if (expr.Kind == "word") return expr.Word;
        return string.Join(expr.Kind == "and" ? "&" : "|", expr.Children.Select(child =>
        {
            string text = Canonical(child);
            return expr.Kind == "and" && child.Kind == "or" ? $"({text})" : text;
        }));
    }

    public static bool Contains(Expr? expr, string code) =>
        expr is not null && (expr.Kind == "word"
            ? expr.Word == code : expr.Children.Any(child => Contains(child, code)));

    public static bool Satisfied(Expr? expr, Student student)
    {
        if (expr is null) return true;
        if (expr.Kind == "word")
        {
            string word = expr.Word;
            return word.Length == 2 && word[0] == 'Y'
                ? student.Year >= word[1] - '0'
                : student.Passed(word) is not null;
        }
        return expr.Kind == "and"
            ? expr.Children.All(child => Satisfied(child, student))
            : expr.Children.Any(child => Satisfied(child, student));
    }
}

sealed class CommandError : Exception
{
    public CommandError(string message) : base(message) {}
}

sealed record Slot(string Day, int Start, int End, string Raw);
sealed record Grade(string Code, string GradeName, int Credits);
sealed record History(int Number, string Event);

sealed class Expr
{
    public string Kind { get; }
    public string Word { get; }
    public List<Expr> Children { get; }

    public Expr(string kind, string word = "", List<Expr>? children = null)
    {
        Kind = kind;
        Word = word;
        Children = children ?? new List<Expr>();
    }

    public static Expr Combine(string kind, IEnumerable<Expr> nodes)
    {
        var children = new List<Expr>();
        foreach (Expr node in nodes)
        {
            if (node.Kind == kind) children.AddRange(node.Children);
            else children.Add(node);
        }
        return children.Count == 1 ? children[0] : new Expr(kind, children: children);
    }
}

sealed class PrerequisiteParser
{
    private readonly string course;
    private readonly List<string> tokens;
    private int position;

    private PrerequisiteParser(string course, string text)
    {
        this.course = course;
        tokens = Regex.Matches(text, @"[A-Z0-9]+|[&|()]")
            .Cast<Match>().Select(m => m.Value).ToList();
        if (string.Concat(tokens) != text) Invalid();
        foreach (string token in tokens)
        {
            if (token is "&" or "|" or "(" or ")") continue;
            if (!Regex.IsMatch(token, @"^(?:[A-Z]{2,4}[0-9]{3}|Y[1-9])$"))
                Invalid();
        }
    }

    private void Invalid() => throw new CommandError("invalid prereq " + course);
    private string? Peek() => position < tokens.Count ? tokens[position] : null;

    private Expr Factor()
    {
        string? token = Peek();
        ++position;
        if (token == "(")
        {
            Expr child = Expression();
            if (Peek() != ")") Invalid();
            ++position;
            return child;
        }
        if (token is null or "&" or "|" or ")") Invalid();
        return new Expr("word", token!);
    }

    private Expr Term()
    {
        var nodes = new List<Expr> { Factor() };
        while (Peek() == "&")
        {
            ++position;
            nodes.Add(Factor());
        }
        return Expr.Combine("and", nodes);
    }

    private Expr Expression()
    {
        var nodes = new List<Expr> { Term() };
        while (Peek() == "|")
        {
            ++position;
            nodes.Add(Term());
        }
        return Expr.Combine("or", nodes);
    }

    private Expr Parse()
    {
        Expr result = Expression();
        if (position != tokens.Count) Invalid();
        if (Rules.Contains(result, course))
            throw new CommandError("self prereq " + course);
        return result;
    }

    public static Expr? From(string course, string text) =>
        text == "-" ? null : new PrerequisiteParser(course, text).Parse();
}

sealed class Course
{
    public string Code { get; }
    public int Credits { get; }
    public int Capacity { get; set; }
    public List<Slot> Slots { get; }
    public Expr? Prerequisite { get; set; }
    public bool Open { get; set; } = true;
    public HashSet<string> Enrolled { get; } = new(StringComparer.Ordinal);
    public List<string> Waiting { get; } = new();

    public Course(string code, int credits, int capacity, List<Slot> slots, Expr? prerequisite)
    {
        Code = code;
        Credits = credits;
        Capacity = capacity;
        Slots = slots;
        Prerequisite = prerequisite;
    }

    public string Status => Open ? "open" : "closed";
    public string Department => Code[..^3];
    public int Weekly => Slots.Sum(slot => slot.End - slot.Start);
}

sealed class Student
{
    public string Id { get; }
    public int Year { get; }
    public int Limit { get; set; }
    public List<Grade> Grades { get; }
    public HashSet<string> Taking { get; } = new(StringComparer.Ordinal);
    public List<History> History { get; } = new();

    public Student(string id, int year, int limit, List<Grade> grades)
    {
        Id = id;
        Year = year;
        Limit = limit;
        Grades = grades;
    }

    public string? Passed(string code) =>
        Grades.FirstOrDefault(g => g.Code == code &&
            (g.GradeName is "A" or "B" or "C"))?.GradeName;

    public int Earned => Grades.Where(g => g.GradeName != "F").Sum(g => g.Credits);

    public string Gpa
    {
        get
        {
            if (Grades.Count == 0) return "n/a";
            int points = Grades.Sum(g => Rules.GradePoints[g.GradeName] * g.Credits);
            int credits = Grades.Sum(g => g.Credits);
            int rounded = (200 * points + credits) / (2 * credits);
            return $"{rounded / 100}.{rounded % 100:00}";
        }
    }
}

sealed class Decision
{
    public string Word { get; }
    public string[] Extra { get; }

    public Decision(string word, params string[] extra)
    {
        Word = word;
        Extra = extra;
    }
}

sealed class Registrar
{
    private readonly Dictionary<string, Course> courses = new(StringComparer.Ordinal);
    private readonly Dictionary<string, Student> students = new(StringComparer.Ordinal);
    private readonly List<string> output = new();
    private int commandNumber;

    private void Emit(int indent, params object[] parts) =>
        output.Add(new string(' ', indent) + string.Join(" ", parts));

    private Student GetStudent(string id) =>
        students.TryGetValue(id, out Student? student)
            ? student : throw new CommandError("unknown student " + id);

    private Course GetCourse(string code) =>
        courses.TryGetValue(code, out Course? course)
            ? course : throw new CommandError("unknown course " + code);

    private List<Course> SortedCourses() =>
        courses.Values.OrderBy(c => c.Code, StringComparer.Ordinal).ToList();

    private List<Course> Taking(Student student, string? excluded = null) =>
        student.Taking.Where(code => code != excluded)
            .OrderBy(code => code, StringComparer.Ordinal)
            .Select(code => courses[code]).ToList();

    private int Credits(Student student, string? excluded = null) =>
        Taking(student, excluded).Sum(c => c.Credits);

    private List<Course> Waitlists(Student student) =>
        SortedCourses().Where(c => c.Waiting.Contains(student.Id)).ToList();

    private Course? Conflict(Student student, Course target, string? excluded = null) =>
        Taking(student, excluded).FirstOrDefault(c =>
            c.Slots.Any(a => target.Slots.Any(b => Rules.Overlaps(a, b))));

    private Decision Eligible(Student student, Course course, string? excluded = null)
    {
        if (!course.Open) return new Decision("course closed");
        if (course.Enrolled.Contains(student.Id)) return new Decision("already enrolled");
        if (course.Waiting.Contains(student.Id)) return new Decision("already waitlisted");

        string? grade = student.Passed(course.Code);
        if (grade is not null) return new Decision("already completed", grade);
        if (!Rules.Satisfied(course.Prerequisite, student)) return new Decision("prereq not met");

        Course? conflict = Conflict(student, course, excluded);
        if (conflict is not null) return new Decision("time conflict", conflict.Code);
        int credits = Credits(student, excluded) + course.Credits;
        if (credits > student.Limit)
            return new Decision("credit limit", credits.ToString(), student.Limit.ToString());
        return new Decision("OK");
    }

    private int WaitPosition(Student student, Course course) =>
        1 + course.Waiting.Count(id => students[id].Year >= student.Year);

    private Decision Judgment(Student student, Course course)
    {
        Decision decision = Eligible(student, course);
        if (decision.Word != "OK") return decision;
        if (course.Enrolled.Count < course.Capacity) return new Decision("enroll");
        if (Waitlists(student).Count >= 3) return new Decision("waitlist limit");
        return new Decision("waitlist", WaitPosition(student, course).ToString());
    }

    private void Reject(Student student, Course course, Decision decision) =>
        throw new CommandError(string.Join(" ",
            new[] { decision.Word, student.Id, course.Code }.Concat(decision.Extra)));

    private void Record(Student student, string eventText) =>
        student.History.Add(new History(commandNumber, eventText));

    private void Enroll(Student student, Course course)
    {
        course.Enrolled.Add(student.Id);
        student.Taking.Add(course.Code);
    }

    private void Withdraw(Student student, Course course)
    {
        course.Enrolled.Remove(student.Id);
        student.Taking.Remove(course.Code);
    }

    private void EnrollmentLine(string label, Student student, Course course, int indent = 0) =>
        Emit(indent, label, student.Id, course.Code, "enrolled",
            $"{course.Enrolled.Count}/{course.Capacity}", "credits",
            $"{Credits(student)}/{student.Limit}");

    private void Promote()
    {
        foreach (Course course in SortedCourses())
        {
            if (!course.Open) continue;
            while (course.Enrolled.Count < course.Capacity)
            {
                int index = course.Waiting.FindIndex(id =>
                {
                    Student s = students[id];
                    return Conflict(s, course) is null && Credits(s) + course.Credits <= s.Limit;
                });
                if (index < 0) break;
                string id = course.Waiting[index];
                course.Waiting.RemoveAt(index);
                Student student = students[id];
                Enroll(student, course);
                Record(student, "promote " + course.Code);
                EnrollmentLine("PROMOTE", student, course, 2);
            }
        }
    }

    private void Schedule(Student student)
    {
        List<Course> taking = Taking(student);
        Emit(0, "SCHEDULE", student.Id, "courses", taking.Count, "credits",
            Credits(student), "weekly", Rules.Time(taking.Sum(c => c.Weekly)));
        foreach (string day in Rules.Days)
        {
            var meetings = taking.SelectMany(c => c.Slots
                    .Where(slot => slot.Day == day)
                    .Select(slot => (Course: c, Slot: slot)))
                .OrderBy(row => row.Slot.Start).ToList();
            if (meetings.Count == 0) continue;
            var parts = new List<object> { day };
            foreach (var meeting in meetings)
            {
                parts.Add($"{Rules.Time(meeting.Slot.Start)}-{Rules.Time(meeting.Slot.End)}");
                parts.Add(meeting.Course.Code);
            }
            Emit(2, parts.ToArray());
        }

        string[] tba = taking.Where(c => c.Slots.Count == 0)
            .Select(c => c.Code).ToArray();
        if (tba.Length != 0)
            Emit(2, new object[] { "TBA" }.Concat(tba.Cast<object>()).ToArray());
    }

    private void Command(string command, string[] a)
    {
        switch (command)
        {
            case "COURSE":
            {
                if (courses.ContainsKey(a[0]))
                    throw new CommandError("duplicate course " + a[0]);
                List<Slot> slots = Rules.ParseSlots(a[3]);
                Expr? tree = PrerequisiteParser.From(a[0], a[4]);
                var course = new Course(a[0], int.Parse(a[1]), int.Parse(a[2]), slots, tree);
                courses.Add(course.Code, course);
                Emit(0, "COURSE", course.Code, "credits", course.Credits,
                    "capacity", course.Capacity, "meetings", slots.Count,
                    "weekly", Rules.Time(course.Weekly), "prereq", Rules.Canonical(tree));
                break;
            }

            case "STUDENT":
            {
                if (students.ContainsKey(a[0]))
                    throw new CommandError("duplicate student " + a[0]);
                var grades = new List<Grade>();
                var seen = new HashSet<string>(StringComparer.Ordinal);
                foreach (string record in a[3] == "-" ? Array.Empty<string>() : a[3].Split(','))
                {
                    string[] values = record.Split(':');
                    string code = values[0], grade = values[1];
                    if (!Rules.GradePoints.ContainsKey(grade))
                        throw new CommandError($"invalid grade {a[0]} {code} {grade}");
                    if (!seen.Add(code))
                        throw new CommandError($"duplicate record {a[0]} {code}");
                    grades.Add(new Grade(code, grade, int.Parse(values[2])));
                }
                var student = new Student(a[0], int.Parse(a[1]), int.Parse(a[2]), grades);
                students.Add(student.Id, student);
                Emit(0, "STUDENT", student.Id, "year", student.Year,
                    "limit", student.Limit, "records", grades.Count,
                    "earned", student.Earned, "gpa", student.Gpa);
                break;
            }

            case "ENROLL":
            case "CHECK":
            {
                Student student = GetStudent(a[0]);
                Course course = GetCourse(a[1]);
                Decision decision = Judgment(student, course);
                if (command == "CHECK")
                {
                    Emit(0, new object[] { "CHECK", student.Id, course.Code, decision.Word }
                        .Concat(decision.Extra.Cast<object>()).ToArray());
                }
                else if (decision.Word == "enroll")
                {
                    Enroll(student, course);
                    Record(student, "enroll " + course.Code);
                    EnrollmentLine("ENROLL", student, course);
                }
                else if (decision.Word == "waitlist")
                {
                    int position = int.Parse(decision.Extra[0]);
                    course.Waiting.Insert(position - 1, student.Id);
                    Record(student, $"waitlist {course.Code} {position}");
                    Emit(0, "ENROLL", student.Id, course.Code, "waitlist", position);
                }
                else Reject(student, course, decision);
                break;
            }

            case "OPTIONS":
            {
                Student student = GetStudent(a[0]);
                Emit(0, "OPTIONS", student.Id, "courses", courses.Count);
                foreach (Course course in SortedCourses())
                {
                    Decision decision = Judgment(student, course);
                    Emit(2, new object[] { course.Code, decision.Word }
                        .Concat(decision.Extra.Cast<object>()).ToArray());
                }
                break;
            }

            case "DROP":
            {
                Student student = GetStudent(a[0]);
                Course course = GetCourse(a[1]);
                if (course.Enrolled.Contains(student.Id))
                {
                    Withdraw(student, course);
                    Record(student, "drop " + course.Code);
                    EnrollmentLine("DROP", student, course);
                }
                else if (course.Waiting.Remove(student.Id))
                {
                    Record(student, "drop " + course.Code + " waitlist");
                    Emit(0, "DROP", student.Id, course.Code, "waitlist", "removed");
                }
                else throw new CommandError($"not registered {student.Id} {course.Code}");
                Promote();
                break;
            }

            case "SWAP":
            {
                Student student = GetStudent(a[0]);
                Course old = GetCourse(a[1]);
                Course target = GetCourse(a[2]);
                if (!old.Enrolled.Contains(student.Id))
                    throw new CommandError($"not enrolled {student.Id} {old.Code}");
                if (old == target) throw new CommandError("same course " + old.Code);
                Decision decision = Eligible(student, target, old.Code);
                if (decision.Word != "OK") Reject(student, target, decision);
                if (target.Enrolled.Count >= target.Capacity)
                    throw new CommandError("course full " + target.Code);
                Withdraw(student, old);
                Enroll(student, target);
                Record(student, $"swap {old.Code} {target.Code}");
                Emit(0, "SWAP", student.Id, old.Code, "->", target.Code,
                    "credits", $"{Credits(student)}/{student.Limit}");
                Promote();
                break;
            }

            case "CLOSE":
            case "OPEN":
            {
                Course course = GetCourse(a[0]);
                bool opening = command == "OPEN";
                if (course.Open == opening)
                    throw new CommandError($"already {(opening ? "open" : "closed")} {course.Code}");
                course.Open = opening;
                Emit(0, command, course.Code, "enrolled",
                    $"{course.Enrolled.Count}/{course.Capacity}",
                    "waitlist", course.Waiting.Count);
                if (opening) Promote();
                break;
            }

            case "CAPACITY":
            {
                Course course = GetCourse(a[0]);
                int capacity = int.Parse(a[1]);
                if (capacity < course.Enrolled.Count)
                    throw new CommandError(
                        $"capacity below enrollment {course.Code} {course.Enrolled.Count}");
                int old = course.Capacity;
                course.Capacity = capacity;
                Emit(0, "CAPACITY", course.Code, old, "->", capacity);
                Promote();
                break;
            }

            case "LIMIT":
            {
                Student student = GetStudent(a[0]);
                int limit = int.Parse(a[1]), credits = Credits(student);
                if (limit < credits)
                    throw new CommandError($"limit below enrolled {student.Id} {credits}");
                int old = student.Limit;
                student.Limit = limit;
                Emit(0, "LIMIT", student.Id, old, "->", limit);
                Promote();
                break;
            }

            case "PREREQ":
            {
                Course course = GetCourse(a[0]);
                Expr? tree = PrerequisiteParser.From(course.Code, a[1]);
                course.Prerequisite = tree;
                Emit(0, "PREREQ", course.Code, Rules.Canonical(tree));
                foreach (string id in course.Waiting.ToArray())
                {
                    Student student = students[id];
                    if (!Rules.Satisfied(tree, student))
                    {
                        course.Waiting.Remove(id);
                        Record(student, "unlist " + course.Code);
                        Emit(2, "UNLIST", student.Id, course.Code);
                    }
                }
                break;
            }

            case "CANCEL":
            {
                Course course = GetCourse(a[0]);
                Emit(0, "CANCEL", course.Code,
                    "enrolled", course.Enrolled.Count, "waitlist", course.Waiting.Count);
                foreach (string id in course.Enrolled)
                {
                    students[id].Taking.Remove(course.Code);
                    Record(students[id], "cancel " + course.Code);
                }
                foreach (string id in course.Waiting)
                    Record(students[id], "cancel " + course.Code + " waitlist");
                courses.Remove(course.Code);
                Promote();
                break;
            }

            case "ROSTER":
            {
                Course course = GetCourse(a[0]);
                Emit(0, "ROSTER", course.Code, course.Status,
                    "enrolled", $"{course.Enrolled.Count}/{course.Capacity}",
                    "waitlist", course.Waiting.Count);
                foreach (string id in course.Enrolled.OrderBy(id => id, StringComparer.Ordinal))
                    Emit(2, "enrolled", id, "year", students[id].Year);
                for (int i = 0; i < course.Waiting.Count; ++i)
                    Emit(2, "waitlist", i + 1, course.Waiting[i],
                        "year", students[course.Waiting[i]].Year);
                break;
            }

            case "SCHEDULE":
                Schedule(GetStudent(a[0]));
                break;

            case "FREE":
            {
                Student student = GetStudent(a[0]);
                string day = a[1];
                if (!Rules.Days.Contains(day)) throw new CommandError("invalid day " + day);
                List<Slot> meetings = Taking(student).SelectMany(c => c.Slots)
                    .Where(slot => slot.Day == day && slot.Start < 1320 && slot.End > 480)
                    .OrderBy(slot => slot.Start).ToList();
                var ranges = new List<(int Start, int End)>();
                int cursor = 480;
                foreach (Slot slot in meetings)
                {
                    int start = Math.Max(slot.Start, 480);
                    if (start > cursor) ranges.Add((cursor, start));
                    cursor = Math.Max(cursor, Math.Min(slot.End, 1320));
                }
                if (cursor < 1320) ranges.Add((cursor, 1320));
                int total = ranges.Sum(range => range.End - range.Start);
                var parts = new List<object> { "FREE", student.Id, day, "total", Rules.Time(total) };
                foreach (var interval in ranges)
                    parts.Add($"{Rules.Time(interval.Start)}-{Rules.Time(interval.End)}");
                Emit(0, parts.ToArray());
                break;
            }

            case "INFO":
            {
                Course course = GetCourse(a[0]);
                Emit(0, "INFO", course.Code, course.Status,
                    "credits", course.Credits, "capacity", course.Capacity,
                    "prereq", Rules.Canonical(course.Prerequisite));
                Slot[] slots = course.Slots.OrderBy(slot => Array.IndexOf(Rules.Days, slot.Day))
                    .ThenBy(slot => slot.Start).ToArray();
                if (slots.Length == 0) Emit(2, "meet", "TBA");
                foreach (Slot slot in slots)
                    Emit(2, "meet", slot.Day, $"{Rules.Time(slot.Start)}-{Rules.Time(slot.End)}");

                string[] required = SortedCourses()
                    .Where(c => Rules.Contains(c.Prerequisite, course.Code))
                    .Select(c => c.Code).ToArray();
                Emit(2, new object[] { "required", "by" }
                    .Concat((required.Length > 0 ? required : new[] { "none" }).Cast<object>())
                    .ToArray());
                break;
            }

            case "AUDIT":
            {
                Student student = GetStudent(a[0]);
                Emit(0, "AUDIT", student.Id, "year", student.Year, "limit", student.Limit);
                foreach (Grade record in student.Grades.OrderBy(g => g.Code, StringComparer.Ordinal))
                    Emit(2, "record", record.Code, record.GradeName, record.Credits);
                Emit(2, "earned", student.Earned, "gpa", student.Gpa);
                foreach (Course course in Taking(student))
                    Emit(2, "enrolled", course.Code, course.Credits);
                int credits = Credits(student);
                Emit(2, "credits", credits, "remaining", student.Limit - credits);
                foreach (Course course in Waitlists(student))
                    Emit(2, "waitlist", course.Code, course.Waiting.IndexOf(student.Id) + 1);
                break;
            }

            case "HISTORY":
            {
                Student student = GetStudent(a[0]);
                Emit(0, "HISTORY", student.Id, "events", student.History.Count);
                foreach (History row in student.History)
                    Emit(2, row.Number, row.Event);
                break;
            }

            case "STUDENTS":
            {
                Emit(0, "STUDENTS", students.Count);
                foreach (Student student in students.Values
                    .OrderBy(s => s.Id, StringComparer.Ordinal))
                    Emit(2, student.Id, "year", student.Year,
                        "credits", $"{Credits(student)}/{student.Limit}",
                        "courses", student.Taking.Count, "waitlists", Waitlists(student).Count);
                break;
            }

            case "REPORT":
            {
                List<Course> all = SortedCourses();
                int enrolled = all.Sum(c => c.Enrolled.Count);
                int capacity = all.Sum(c => c.Capacity);
                int waiting = all.Sum(c => c.Waiting.Count);
                Emit(0, "REPORT", "courses", all.Count,
                    "enrolled", $"{enrolled}/{capacity}", "rate", Rules.Rate(enrolled, capacity),
                    "waitlisted", waiting);
                foreach (Course course in all)
                    Emit(2, course.Code, course.Status,
                        $"{course.Enrolled.Count}/{course.Capacity}",
                        Rules.Rate(course.Enrolled.Count, course.Capacity),
                        "waitlist", course.Waiting.Count);
                foreach (var department in all.GroupBy(c => c.Department)
                    .OrderBy(group => group.Key, StringComparer.Ordinal))
                {
                    int count = department.Sum(c => c.Enrolled.Count);
                    int seats = department.Sum(c => c.Capacity);
                    int queue = department.Sum(c => c.Waiting.Count);
                    Emit(2, "dept", department.Key, "courses", department.Count(),
                        "enrolled", $"{count}/{seats}", "rate", Rules.Rate(count, seats),
                        "waitlisted", queue);
                }
                break;
            }
        }
    }

    public void Execute(string line)
    {
        ++commandNumber;
        string[] fields = line.Split(' ');
        try
        {
            Command(fields[0], fields.Skip(1).ToArray());
        }
        catch (CommandError error)
        {
            Emit(0, "ERROR", error.Message);
        }
    }

    public string Output() => output.Count == 0 ? "" : string.Join("\n", output) + "\n";
}
