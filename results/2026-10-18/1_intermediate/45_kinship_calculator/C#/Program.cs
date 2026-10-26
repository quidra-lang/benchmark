using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

enum Sex { M, F, X }
enum MarriageStatus { Current, Divorced, Widowed }
sealed class CommandError(string message) : Exception
(message);

readonly record struct Fraction(long Numerator, int Power) {
    public static Fraction Make(long numerator, int power) {
        if (numerator == 0)
            return new(0, 0);
        while (power > 0 && numerator % 2 == 0) {
            numerator /= 2;
            power--;
        }
        return new(numerator, power);
    }
    public static Fraction operator +(Fraction a, Fraction b) {
        int power = Math.Max(a.Power, b.Power);
        return Make((a.Numerator << (power - a.Power)) + (b.Numerator << (power - b.Power)), power);
    }
    public Fraction Half() => Make(Numerator, Power + 1);
    public override string ToString() => $"{Numerator}/{1L << Power}";
}

sealed class Person(string id, Sex sex, int birth, string name) {
    public string Id { get; } = id;
    public Sex Sex { get; } = sex;
    public int Birth { get; } = birth;
    public string Name { get; } = name;
    public int? Death { get; set; }
    public HashSet<string> Parents { get; } = new(StringComparer.Ordinal);
    public string Life => $"{Birth}-{Death?.ToString(CultureInfo.InvariantCulture) ?? ""}";

    public Person Copy() {
        Person copy = new(Id, Sex, Birth, Name) { Death = Death };
        copy.Parents.UnionWith(Parents);
        return copy;
    }
}

sealed record Marriage(string First, string Second, int Start, int? End = null,
                       MarriageStatus Status = MarriageStatus.Current, string? Died = null) {
    public bool Contains(string id) => First == id || Second == id;
    public string Other(string id) => First == id ? Second : First;
    public string StatusText => Status.ToString().ToLowerInvariant();
}

sealed class Family {
    public SortedDictionary<string, Person> People { get; } = new(StringComparer.Ordinal);
    public List<Marriage> Marriages { get; } = [];

    public Family Copy() {
        Family copy = new();
        foreach ((string id, Person person) in People)
            copy.People[id] = person.Copy();
        copy.Marriages.AddRange(Marriages);
        return copy;
    }
}

readonly record struct Apex(string Id, int A, int B, int Share = 0) {
    public bool Collateral => A > 0 && B > 0;
}

static class Terms {
    public static string Gender(Sex sex, string male, string female,
                                string neutral) => sex == Sex.M   ? male
                                                   : sex == Sex.F ? female
                                                                  : neutral;

    static string Grand(int generation) =>
        generation == 1 ? "" : string.Concat(Enumerable.Repeat("great-", generation - 2)) + "grand";

    static string Ordinal(int value) {
        string[] first = [
            "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth",
            "tenth"
        ];
        if (value <= 10)
            return first[value - 1];
        string suffix = value % 100 is 11 or 12 or 13 ? "th"
                                                      : ((value % 10) switch {
                                                            1 => "st",
                                                            2 => "nd",
                                                            3 => "rd",
                                                            _ => "th"
                                                        });
        return value + suffix;
    }

    public static string Build(int a, int b, Sex sex) {
        if (a == 0 && b == 0)
            return "self";
        if (a == 0)
            return Grand(b) + Gender(sex, "father", "mother", "parent");
        if (b == 0)
            return Grand(a) + Gender(sex, "son", "daughter", "child");
        if (a == 1 && b == 1)
            return Gender(sex, "brother", "sister", "sibling");
        if (a == 1)
            return Grand(b - 1) + Gender(sex, "uncle", "aunt", "pibling");
        if (b == 1)
            return Grand(a - 1) + Gender(sex, "nephew", "niece", "nibling");
        int removal = Math.Abs(a - b);
        string suffix = removal switch {
            0 => "",
            1 => " once removed",
            2 => " twice removed",
            _ => $" {removal} times removed"
        };
        return Ordinal(Math.Min(a, b) - 1) + " cousin" + suffix;
    }
}

sealed class Analysis {
    readonly Family family;
    readonly Dictionary<string, List<string>> children = new(StringComparer.Ordinal);
    readonly Dictionary<string, Dictionary<string, int>> ancestors = new(StringComparer.Ordinal);
    readonly Dictionary<string, Dictionary<string, int>> descendants = new(StringComparer.Ordinal);
    readonly Dictionary<(string, string), Fraction> coefficients = [];
    readonly Dictionary<(string, string), Marriage> last = [];

    public Analysis(Family family) {
        this.family = family;
        foreach (string id in family.People.Keys)
            children[id] = [];
        foreach (Person person in family.People.Values)
            foreach (string parent in person.Parents)
                children[parent].Add(person.Id);
        foreach (Marriage marriage in family.Marriages)
            last[Pair(marriage.First, marriage.Second)] = marriage;
    }

    static (string, string) Pair(string a, string b) => string.CompareOrdinal(a, b) <= 0 ? (a, b)
                                                                                         : (b, a);
    public Person Person(string id) => family.People[id];
    public IEnumerable<string> Ids => family.People.Keys;
    public IEnumerable<string> Parents(string id) => Person(id).Parents;
    public IEnumerable<string> Children(string id) => children[id];
    public IEnumerable<string> ByAge(IEnumerable<string> ids) =>
        ids.OrderBy(id => Person(id).Birth).ThenBy(id => id, StringComparer.Ordinal);
    public string PersonList(IEnumerable<string> ids) {
        string result = string.Join(" ", ByAge(ids));
        return result.Length == 0 ? "-" : result;
    }
    public Marriage? Current(string id) =>
        family.Marriages.FirstOrDefault(m => m.Status == MarriageStatus.Current && m.Contains(id));
    public string? Spouse(string id) => Current(id)?.Other(id);
    public Marriage? Last(string a, string b) => last.GetValueOrDefault(Pair(a, b));
    public bool Partner(string a, string b) => Last(a, b) is Marriage m
                                               && m.Status != MarriageStatus.Divorced;
    public IEnumerable<string> Partners(string id) => Ids.Where(other => Partner(id, other));
    public int SharedParents(string a, string b) => Parents(a).Count(Person(b).Parents.Contains);
    public bool Siblings(string a, string b) => a != b && SharedParents(a, b) > 0;
    public bool StepSiblings(string a,
                             string b) => SharedParents(a, b) == 0 &&
                                          Parents(a).Any(p => Parents(b).Any(q => Partner(p, q)));

    Dictionary<string, int> Distances(string start, bool upward) {
        Dictionary<string, Dictionary<string, int>> cache = upward ? ancestors : descendants;
        if (cache.TryGetValue(start, out Dictionary<string, int>? saved))
            return saved;
        Dictionary<string, int> distances = new(StringComparer.Ordinal) { [start] = 0 };
        Queue<string> pending = new();
        pending.Enqueue(start);
        while (pending.TryDequeue(out string? current))
        {
            foreach (string next in upward ? Parents(current) : Children(current))
                if (distances.TryAdd(next, distances[current] + 1))
                    pending.Enqueue(next);
        }
        cache[start] = distances;
        return distances;
    }
    public Dictionary<string, int> Up(string id) => Distances(id, true);
    public Dictionary<string, int> Down(string id) => Distances(id, false);
    public bool Ancestor(string a, string b) => a != b && Up(b).ContainsKey(a);

    public Apex? ApexOf(string a, string b) {
        Dictionary<string, int> da = Up(a), db = Up(b);
        if (db.TryGetValue(a, out int fromB))
            return new(a, 0, fromB);
        if (da.TryGetValue(b, out int fromA))
            return new(b, fromA, 0);
        string? apex = da.Keys.Where(db.ContainsKey)
                           .OrderBy(id => da[id] + db[id])
                           .ThenBy(id => da[id])
                           .ThenBy(id => id, StringComparer.Ordinal)
                           .FirstOrDefault();
        if (apex is null)
            return null;
        int share =
            da.Keys.Count(id => db.ContainsKey(id) && da[id] == da[apex] && db[id] == db[apex]);
        return new(apex, da[apex], db[apex], share);
    }

    public string Blood(string a, Apex apex, Sex? sex = null) {
        string prefix = apex.Collateral ? apex.Share == 1   ? "half-"
                                          : apex.Share >= 4 ? "double "
                                                            : ""
                                        : "";
        return prefix + Terms.Build(apex.A, apex.B, sex ?? Person(a).Sex);
    }

    public List<string> Relations(string a, string b, Sex? overrideSex = null) {
        if (a == b)
            return ["self"];
        Sex sex = overrideSex ?? Person(a).Sex;
        List<string> result = [];
        string Word(string male, string female, string neutral) =>
            Terms.Gender(sex, male, female, neutral);
        if (ApexOf(a, b) is Apex apex)
            result.Add(Blood(a, apex, sex));
        Marriage? marriage = Last(a, b);
        if (marriage?.Status == MarriageStatus.Current)
            result.Add(Word("husband", "wife", "spouse"));
        if (marriage?.Status == MarriageStatus.Widowed)
            result.Add(marriage.Died == a ? Word("late husband", "late wife", "late spouse")
                                          : Word("widower", "widow", "surviving spouse"));
        if (marriage?.Status == MarriageStatus.Divorced)
            result.Add(Word("ex-husband", "ex-wife", "ex-spouse"));
        if (marriage is null && Children(a).Any(child => Person(child).Parents.Contains(b)))
            result.Add("co-parent");
        if (!Person(b).Parents.Contains(a) && Parents(b).Any(p => Partner(a, p)))
            result.Add(Word("stepfather", "stepmother", "stepparent"));
        if (!Person(a).Parents.Contains(b) && Parents(a).Any(p => Partner(b, p)))
            result.Add(Word("stepson", "stepdaughter", "stepchild"));
        if (StepSiblings(a, b))
            result.Add(Word("stepbrother", "stepsister", "stepsibling"));
        if (!Ancestor(a, b) && Up(b).Any(item => item.Value == 2 && Partner(a, item.Key)))
            result.Add(Word("stepgrandfather", "stepgrandmother", "stepgrandparent"));
        if (!Ancestor(b, a) && Up(a).Any(item => item.Value == 2 && Partner(b, item.Key)))
            result.Add(Word("stepgrandson", "stepgranddaughter", "stepgrandchild"));
        if (Partners(b).Any(p => Person(p).Parents.Contains(a)))
            result.Add(Word("father-in-law", "mother-in-law", "parent-in-law"));
        if (Partners(a).Any(p => Person(p).Parents.Contains(b)))
            result.Add(Word("son-in-law", "daughter-in-law", "child-in-law"));
        if (Partners(b).Any(p => Siblings(a, p)) || Partners(a).Any(p => Siblings(p, b)))
            result.Add(Word("brother-in-law", "sister-in-law", "sibling-in-law"));
        return result;
    }
    public string Relation(string a, string b) {
        List<string> terms = Relations(a, b);
        return terms.Count == 0 ? "no relation" : string.Join(", ", terms);
    }

    public Fraction Phi(string a, string b) {
        (string, string) key = Pair(a, b);
        if (coefficients.TryGetValue(key, out Fraction value))
            return value;
        if (a == b)
            value = (new Fraction(1, 0) + Inbreeding(a)).Half();
        else {
            if (Person(a).Birth < Person(b).Birth)
                (a, b) = (b, a);
            Fraction sum = default;
            foreach (string parent in Parents(a))
                sum += Phi(parent, b);
            value = sum.Half();
        }
        coefficients[key] = value;
        return value;
    }
    public Fraction Inbreeding(string id) {
        string[] parents = Parents(id).ToArray();
        return parents.Length == 2 ? Phi(parents[0], parents[1]) : default;
    }
}

sealed class Calculator {
    Family family = new();
    readonly Stack<(string Line, Family State)> history = new();

    void Check(string id) {
        if (!family.People.ContainsKey(id))
            throw new CommandError("UNKNOWN PERSON " + id);
    }
    void Remember(string line) => history.Push((line, family.Copy()));
    static void Reject(bool condition, string reason) {
        if (condition)
            throw new CommandError(reason);
    }

    List<string> Modify(string line, string[] args, Analysis graph) {
        string command = args[0], id = args[1];
        if (command == "PERSON") {
            Reject(family.People.ContainsKey(id), "DUPLICATE PERSON " + id);
            Remember(line);
            Person person = new(id, Enum.Parse<Sex>(args[2]), int.Parse(args[3]), args[4]);
            family.People[id] = person;
            return [$"ADDED {id} {person.Name} {person.Sex} {person.Birth}"];
        }
        Check(id);
        Person first = family.People[id];
        if (command == "REMOVE") {
            Remember(line);
            family.People.Remove(id);
            foreach (Person person in family.People.Values)
                person.Parents.Remove(id);
            family.Marriages.RemoveAll(m => m.Contains(id));
            return ["REMOVED " + id];
        }
        if (command == "DEATH") {
            int year = int.Parse(args[2]);
            Reject(first.Death is not null, "ALREADY DECEASED " + id);
            Reject(
                year < first.Birth ||
                    family.Marriages.Any(m => m.Contains(id) && (m.Start > year || m.End > year)),
                "BAD YEAR " + id);
            string? child =
                graph.Children(id).FirstOrDefault(c => graph.Person(c).Birth > year + 1);
            if (child is not null)
                throw new CommandError($"AFTER DEATH {child} {id}");
            Marriage? current = graph.Current(id);
            Remember(line);
            first.Death = year;
            if (current is not null) {
                int index = family.Marriages.IndexOf(current);
                family.Marriages[index] =
                    current with { End = year, Status = MarriageStatus.Widowed, Died = id };
            }
            return [$"DIED {id} {year}" + (current is null ? "" : " spouse=" + current.Other(id))];
        }
        string other = args[2];
        Check(other);
        Person second = family.People[other];
        if (command == "PARENT") {
            Reject(id == other, "SAME PERSON " + id);
            Reject(first.Parents.Contains(other), $"ALREADY PARENT {id} {other}");
            Reject(first.Parents.Count == 2, "TOO MANY PARENTS " + id);
            Reject(graph.Ancestor(id, other), $"CYCLE {id} {other}");
            Reject(second.Birth + 12 > first.Birth, $"AGE GAP {id} {other}");
            Reject(second.Death + 1 < first.Birth, $"AFTER DEATH {id} {other}");
            Remember(line);
            first.Parents.Add(other);
            return
                [$"LINKED {id} {other} " + Terms.Gender(second.Sex, "father", "mother", "parent")];
        }
        if (command == "UNPARENT") {
            Reject(!first.Parents.Contains(other), $"NOT PARENT {id} {other}");
            Remember(line);
            first.Parents.Remove(other);
            return [$"UNLINKED {id} {other}"];
        }
        int marriageYear = int.Parse(args[3]);
        if (command == "SPOUSE") {
            Reject(id == other, "SAME PERSON " + id);
            foreach (Person person in new[] { first, second })
                Reject(person.Death is not null, "DECEASED " + person.Id);
            foreach (Person person in new[] { first, second })
                Reject(graph.Spouse(person.Id) is not null, "ALREADY MARRIED " + person.Id);
            Reject(graph.Ancestor(id, other) || graph.Ancestor(other, id) ||
                       graph.Siblings(id, other),
                   $"CLOSE KIN {id} {other}");
            foreach (Person person in new[] { first, second })
                Reject(marriageYear < person.Birth + 16, "TOO YOUNG " + person.Id);
            foreach (Person person in new[] { first, second })
                Reject(family.Marriages.Any(m => m.Contains(person.Id) && m.End >= marriageYear),
                       "BAD YEAR " + person.Id);
            Remember(line);
            family.Marriages.Add(new(id, other, marriageYear));
            return [$"MARRIED {id} {other} {marriageYear}"];
        }
        Marriage? marriage = graph.Current(id);
        Reject(marriage is null || marriage.Other(id) != other, $"NOT MARRIED {id} {other}");
        Reject(marriageYear <= marriage!.Start, "BAD YEAR " + id);
        Remember(line);
        family.Marriages[family.Marriages.IndexOf(marriage)] =
            marriage with { End = marriageYear, Status = MarriageStatus.Divorced };
        return [$"DIVORCED {id} {other} {marriageYear}"];
    }

    List<string> Info(string id, Analysis graph) {
        Person person = graph.Person(id);
        List<string> lines = [
            $"INFO {id} {person.Name} {person.Sex} {person.Life}",
            "  parents: " + graph.PersonList(person.Parents)
        ];
        foreach (Marriage marriage in family.Marriages.Where(m => m.Contains(id)))
            lines.Add(
                $"  marriage: {marriage.Other(id)} {marriage.Start}-{marriage.End?.ToString() ?? ""} {marriage.StatusText}");
        lines.Add("  children: " + graph.PersonList(graph.Children(id)));
        lines.Add("  siblings: " +
                  graph.PersonList(graph.Ids.Where(other => graph.Siblings(id, other))));
        lines.Add("  inbreeding: " + graph.Inbreeding(id));
        return lines;
    }

    static List<string> Path(string a, string b, Analysis graph) {
        if (graph.ApexOf(a, b) is not Apex apex)
            return [$"PATH {a} {b} none"];
        Dictionary<string, int> distances = graph.Down(apex.Id);
        List<string> Upward(string start) {
            List<string> path = [start];
            while (path[^1] != apex.Id) {
                string current = path[^1];
                path.Add(
                    graph.Parents(current)
                        .Where(p => distances.GetValueOrDefault(p, -1) == distances[current] - 1)
                        .OrderBy(p => p, StringComparer.Ordinal)
                        .First());
            }
            return path;
        }
        List<string> result = Upward(a), tail = Upward(b);
        result.AddRange(tail.Take(tail.Count - 1).Reverse());
        return [$"PATH {a} {b} {apex.A + apex.B}: " + string.Join(" ", result)];
    }

    static List<string> Common(string a, string b, Analysis graph) {
        Dictionary<string, int> da = graph.Up(a), db = graph.Up(b);
        HashSet<string> common = da.Keys.Where(db.ContainsKey).ToHashSet(StringComparer.Ordinal);
        string[] nearest = common.Where(c => !graph.Children(c).Any(common.Contains))
                               .OrderBy(c => da[c] + db[c])
                               .ThenBy(c => c, StringComparer.Ordinal)
                               .ToArray();
        List<string> lines = [$"COMMON {a} {b} {nearest.Length}"];
        lines.AddRange(nearest.Select(c => $"  {c} {da[c]} {db[c]}"));
        return lines;
    }

    static List<string> Generations(string id, Analysis graph) {
        var groups = graph.Down(id)
                         .Where(pair => pair.Value > 0)
                         .GroupBy(pair => pair.Value)
                         .OrderBy(group => group.Key)
                         .ToArray();
        List<string> lines = [$"GENERATIONS {id} {groups.Length}"];
        foreach (var group in groups) {
            Person[] persons = group.Select(pair => graph.Person(pair.Key)).ToArray();
            lines.Add(
                $"  {group.Key} {persons.Length} {persons.Count(p => p.Death is null)} {persons.Min(p => p.Birth)}-{persons.Max(p => p.Birth)}");
        }
        return lines;
    }

    static List<string> Tree(string id, Analysis graph) {
        List<string> lines = [$"TREE {id} {graph.Down(id).Count - 1}"];
        HashSet<string> seen = new(StringComparer.Ordinal);
        void Visit(string current, int depth) {
            string prefix = new(' ', 2 * (depth + 1));
            if (!seen.Add(current)) {
                lines.Add(prefix + current + " (see above)");
                return;
            }
            Person person = graph.Person(current);
            string? spouse = graph.Spouse(current);
            lines.Add($"{prefix}{current} {person.Name} {person.Life}" +
                      (spouse is null ? "" : " = " + spouse));
            foreach (string child in graph.ByAge(graph.Children(current)))
                Visit(child, depth + 1);
        }
        Visit(id, 0);
        return lines;
    }

    static List<string> Pedigree(string id, int depth, Analysis graph) {
        List<string> lines = [];
        HashSet<string> distinct = new(StringComparer.Ordinal);
        void Enter(string current, int number, int generation) {
            Person person = graph.Person(current);
            distinct.Add(current);
            lines.Add(new string(' ', 2 * (generation + 1)) +
                      $"{number} {current} {person.Name} {person.Life}");
            if (generation >= depth)
                return;
            string[] parents = graph.Parents(current)
                                   .OrderBy(p => graph.Person(p).Sex)
                                   .ThenBy(p => p, StringComparer.Ordinal)
                                   .ToArray();
            for (int i = 0; i < parents.Length; i++)
                Enter(parents[i], 2 * number + i, generation + 1);
        }
        Enter(id, 1, 0);
        lines.Insert(0, $"PEDIGREE {id} {depth} entries={lines.Count} distinct={distinct.Count}");
        return lines;
    }

    List<string> Timeline(string id, Analysis graph) {
        Person person = graph.Person(id);
        List<(int Year, int Rank, string Other, string Text)> events =
            [(person.Birth, 0, "", "born")];
        foreach (Marriage marriage in family.Marriages.Where(m => m.Contains(id))) {
            string other = marriage.Other(id);
            events.Add((marriage.Start, 1, other, "married " + other));
            if (marriage.Status == MarriageStatus.Divorced)
                events.Add((marriage.End!.Value, 3, other, "divorced " + other));
            if (marriage.Status == MarriageStatus.Widowed && marriage.Died == other)
                events.Add((marriage.End!.Value, 4, other, "widowed " + other));
        }
        foreach (string child in graph.Children(id))
            events.Add((graph.Person(child).Birth, 2, child, "child " + child));
        void Lost(IEnumerable<string> ids, string kind) {
            foreach (string other in ids)
                if (graph.Person(other).Death is int death && death >= person.Birth &&
                    (person.Death is null || death <= person.Death))
                    events.Add((death, 5, other, "lost " + kind + " " + other));
        }
        Lost(person.Parents, "parent");
        Lost(graph.Children(id), "child");
        if (person.Death is int year)
            events.Add((year, 6, "", "died"));
        List<string> lines = [$"TIMELINE {id} {events.Count}"];
        lines.AddRange(events.OrderBy(e => e.Year)
                           .ThenBy(e => e.Rank)
                           .ThenBy(e => e.Other, StringComparer.Ordinal)
                           .Select(e => $"  {e.Year} {e.Text}"));
        return lines;
    }

    List<string> Census(int year, Analysis graph) {
        string[] residents = graph
                                 .ByAge(graph.Ids.Where(id => graph.Person(id).Birth <= year &&
                                                              (graph.Person(id).Death is null ||
                                                               graph.Person(id).Death > year)))
                                 .ToArray();
        List<string> lines = [$"CENSUS {year} {residents.Length}"];
        foreach (string id in residents) {
            Marriage? marriage =
                family.Marriages.LastOrDefault(m => m.Contains(id) && m.Start <= year);
            string status = marriage is null ? "single"
                            : marriage.End is null || marriage.End > year
                                ? "married " + marriage.Other(id)
                                : marriage.StatusText;
            lines.Add($"  {id} {year - graph.Person(id).Birth} {status}");
        }
        return lines;
    }

    List<string> Stats(Analysis graph) {
        Dictionary<string, int> levels = new(StringComparer.Ordinal);
        foreach (string id in graph.ByAge(graph.Ids))
            levels[id] = 1 + graph.Parents(id).Select(p => levels[p]).DefaultIfEmpty(0).Max();
        return [
            $"STATS persons={family.People.Count} living={family.People.Values.Count(p => p.Death is null)} " +
            $"links={family.People.Values.Sum(p => p.Parents.Count)} couples={family.Marriages.Count(m => m.Status == MarriageStatus.Current)} " +
            $"founders={family.People.Values.Count(p => p.Parents.Count == 0)} generations={levels.Values.DefaultIfEmpty(0).Max()}"
        ];
    }

    List<string> Audit(Analysis graph) {
        List<string> lines = [];
        foreach (Marriage marriage in family.Marriages)
            if (graph.ApexOf(marriage.First, marriage.Second) is Apex apex)
                lines.Add(
                    $"  marriage {marriage.First} {marriage.Second} {graph.Blood(marriage.First, apex)}");
        foreach (string id in graph.Ids) {
            Fraction value = graph.Inbreeding(id);
            if (value.Numerator != 0)
                lines.Add($"  inbred {id} {value}");
        }
        lines.Insert(0, "AUDIT " + lines.Count);
        return lines;
    }

    static List<string> Find(string id, string route, Analysis graph) {
        HashSet<string> current = new(StringComparer.Ordinal) { id };
        foreach (string step in route.Split('.')) {
            string kind = step switch {
                "father" or "mother" => "parent",
                "son" or "daughter" => "child",
                "brother" or "sister" => "sibling",
                "husband" or "wife" => "spouse",
                _ => step,
            };
            Sex? sex = step switch {
                "father" or "son" or "brother" or "husband" => Sex.M,
                "mother" or "daughter" or "sister" or "wife" => Sex.F,
                _ => null,
            };
            HashSet<string> next = new(StringComparer.Ordinal);
            foreach (string person in current) {
                IEnumerable<string> candidates = kind switch {
                    "parent" => graph.Parents(person),
                    "child" => graph.Children(person),
                    "sibling" => graph.Ids.Where(other => graph.Siblings(person, other)),
                    _ => graph.Spouse(person) is string spouse ? [spouse] : [],
                };
                foreach (string other in candidates)
                    if (sex is null || graph.Person(other).Sex == sex)
                        next.Add(other);
            }
            current = next;
        }
        current.Remove(id);
        List<string> lines = [$"FIND {id} {route} {current.Count}"];
        lines.AddRange(current.OrderBy(other => other, StringComparer.Ordinal)
                           .Select(other => $"  {other}: {graph.Relation(other, id)}"));
        return lines;
    }

    public List<string> Execute(string line) {
        string[] args = line.Split(' ');
        string command = args[0];
        if (command == "UNDO") {
            if (!history.TryPop(out var previous))
                throw new CommandError("NOTHING TO UNDO");
            family = previous.State;
            return ["UNDONE " + previous.Line];
        }
        Analysis graph = new(family);
        if (command is "PERSON" or "DEATH" or "REMOVE" or "PARENT" or "UNPARENT" or "SPOUSE" or
                       "DIVORCE")
            return Modify(line, args, graph);
        if (command == "TERM") {
            int a = int.Parse(args[1]), b = int.Parse(args[2]);
            Sex sex = Enum.Parse<Sex>(args[3]);
            return [$"TERM {a} {b} {sex} {Terms.Build(a, b, sex)}"];
        }
        if (command == "STATS")
            return Stats(graph);
        if (command == "AUDIT")
            return Audit(graph);
        if (command == "CENSUS")
            return Census(int.Parse(args[1]), graph);
        string id = args[1];
        Check(id);
        if (command is "RELATION" or "PATH" or "COMMON" or "KINSHIP") {
            string other = args[2];
            Check(other);
            return command switch {
                "RELATION" => [$"RELATION {id} {other}: {graph.Relation(id, other)}"],
                "PATH" => Path(id, other, graph),
                "COMMON" => Common(id, other, graph),
                _ => [$"KINSHIP {id} {other} {graph.Phi(id, other)}"],
            };
        }
        if (command == "INFO")
            return Info(id, graph);
        if (command == "TREE")
            return Tree(id, graph);
        if (command == "PEDIGREE")
            return Pedigree(id, int.Parse(args[2]), graph);
        if (command == "TIMELINE")
            return Timeline(id, graph);
        if (command == "GENERATIONS")
            return Generations(id, graph);
        if (command == "FIND")
            return Find(id, args[2], graph);
        if (command == "RELATIVES" || command == "WHO") {
            string query = command == "WHO" ? string.Join(" ", args.Skip(2)) : "";
            List<string> lines = [];
            foreach (string other in graph.Ids.Where(other => other != id)) {
                List<string> actual = graph.Relations(other, id);
                if (command == "RELATIVES") {
                    if (actual.Count > 0)
                        lines.Add($"  {other}: " + string.Join(", ", actual));
                } else {
                    List<string> neutral = graph.Relations(other, id, Sex.X);
                    int match =
                        Enumerable.Range(0, actual.Count)
                            .FirstOrDefault(i => actual[i] == query || neutral[i] == query, -1);
                    if (match >= 0)
                        lines.Add($"  {other}: {actual[match]}");
                }
            }
            lines.Insert(0, command == "WHO" ? $"WHO {id} {query} {lines.Count}"
                                             : $"RELATIVES {id} {lines.Count}");
            return lines;
        }
        if (command is "ANCESTORS" or "DESCENDANTS") {
            bool upward = command == "ANCESTORS";
            Dictionary<string, int> distances = upward ? graph.Up(id) : graph.Down(id);
            List<string> lines = [$"{command} {id} {distances.Count - 1}"];
            foreach ((string other, int distance) in distances.Where(pair => pair.Value > 0)
                         .OrderBy(pair => pair.Value)
                         .ThenBy(pair => pair.Key, StringComparer.Ordinal))
                lines.Add($"  {distance} {other} " + Terms.Build(upward ? 0 : distance,
                                                                 upward ? distance : 0,
                                                                 graph.Person(other).Sex));
            return lines;
        }
        if (command == "COUSINS") {
            int degree = int.Parse(args[2]);
            List<(string Id, Apex Apex)> matches = [];
            foreach (string other in graph.Ids.Where(other => other != id))
                if (graph.ApexOf(other, id) is Apex apex && apex.A >= 2 && apex.B >= 2 &&
                    Math.Min(apex.A, apex.B) - 1 == degree)
                    matches.Add((other, apex));
            List<string> lines = [$"COUSINS {id} {degree} {matches.Count}"];
            lines.AddRange(matches.OrderBy(item => Math.Abs(item.Apex.A - item.Apex.B))
                               .ThenBy(item => item.Id, StringComparer.Ordinal)
                               .Select(item => $"  {item.Id} {graph.Blood(item.Id, item.Apex)}"));
            return lines;
        }
        List<(string Id, string Kind)> siblings = [];
        int before = 0;
        Person subject = graph.Person(id);
        foreach (string other in graph.ByAge(graph.Ids.Where(other => other != id))) {
            int common = graph.SharedParents(id, other);
            string kind = common == 2                     ? "full"
                          : common == 1                   ? "half"
                          : graph.StepSiblings(id, other) ? "step"
                                                          : "";
            if (kind.Length == 0)
                continue;
            siblings.Add((other, kind));
            Person person = graph.Person(other);
            if (common > 0 &&
                (person.Birth < subject.Birth ||
                 (person.Birth == subject.Birth && string.CompareOrdinal(other, id) < 0)))
                before++;
        }
        List<string> result = [$"SIBLINGS {id} {siblings.Count} order={before + 1}"];
        result.AddRange(
            siblings.Select(item => $"  {item.Id} {item.Kind} {graph.Person(item.Id).Birth}"));
        return result;
    }
}

static class Program {
    public static void Main() {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        Calculator calculator = new();
        int count = int.Parse(Console.ReadLine()!);
        for (int i = 0; i < count; i++) {
            try {
                foreach (string line in calculator.Execute(Console.ReadLine()!))
                    Console.WriteLine(line);
            } catch (CommandError error) {
                Console.WriteLine("ERROR " + error.Message);
            }
        }
    }
}
