using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

class Program
{
    class Problem(string reason) : Exception(reason) { }

    static void Fail(string reason) => throw new Problem(reason);
    readonly record struct Rational : IComparable<Rational>
    {
        public readonly long Numerator, Denominator;
        public static readonly Rational Zero = new(0), One = new(1);
        public Rational(long numerator, long denominator = 1)
        {
            if (denominator < 0)
            {
                numerator = -numerator;
                denominator = -denominator;
            }
            long a = Math.Abs(numerator), b = denominator;
            while (b != 0)
            {
                long next = a % b;
                a = b;
                b = next;
            }
            Numerator = numerator / a;
            Denominator = denominator / a;
        }
        public static Rational operator +(Rational a, Rational b) => new(a.Numerator * b.Denominator + b.Numerator * a.Denominator, a.Denominator * b.Denominator);
        public static Rational operator -(Rational a) => new(-a.Numerator, a.Denominator);
        public static Rational operator -(Rational a, Rational b) => a + -b;
        public static Rational operator *(Rational a, Rational b) => new(a.Numerator * b.Numerator, a.Denominator * b.Denominator);
        public static Rational operator /(Rational a, Rational b) => new(a.Numerator * b.Denominator, a.Denominator * b.Numerator);
        public int CompareTo(Rational b) => (Numerator * b.Denominator).CompareTo(b.Numerator * Denominator);
        public override string ToString() => Denominator == 1 ? Numerator.ToString(CultureInfo.InvariantCulture) : $"{Numerator}/{Denominator}";
        public string Value()
        {
            long scaled = Math.Abs(Numerator) * 1000000 / Denominator;
            return $"{this} ({(Numerator < 0 ? "-" : "")}{scaled / 1000000}.{scaled % 1000000:000000})";
        }
    }

    static bool Digits(string text) => text.Length > 0 && text.All(c => c is >= '0' and <= '9');

    static Rational Number(string original)
    {
        string text = original;
        Rational multiplier = Rational.One;
        if (text.EndsWith("meg", StringComparison.Ordinal))
        {
            text = text[..^3];
            multiplier = new(1000000);
        }
        else if (text.EndsWith('k'))
        {
            text = text[..^1];
            multiplier = new(1000);
        }
        else if (text.EndsWith('m'))
        {
            text = text[..^1];
            multiplier = new(1, 1000);
        }
        else if (text.EndsWith('u'))
        {
            text = text[..^1];
            multiplier = new(1, 1000000);
        }
        bool negative = text.StartsWith('-');
        if (negative) text = text[1..];
        Rational? value = null;
        if (Digits(text)) value = new Rational(long.Parse(text));
        else
        {
            int dot = text.IndexOf('.'), slash = text.IndexOf('/');
            if (dot >= 0 && Digits(text[..dot]) && Digits(text[(dot + 1)..]))
            {
                long denominator = 1;
                for (int i = dot + 1; i < text.Length; i++) denominator *= 10;
                value = new Rational(long.Parse(text[..dot] + text[(dot + 1)..]), denominator);
            }
            else if (slash >= 0 && Digits(text[..slash]) && Digits(text[(slash + 1)..]))
            {
                long denominator = long.Parse(text[(slash + 1)..]);
                if (denominator != 0) value = new Rational(long.Parse(text[..slash]), denominator);
            }
        }
        if (!value.HasValue) Fail("invalid value " + original);
        Rational result = value!.Value * multiplier;
        return negative ? -result : result;
    }

    static bool ValidNode(string name) => name == "0" || name.Length is >= 1 and <= 8 && name[0] is >= 'a' and <= 'z' && name.All(c => c is >= 'a' and <= 'z' or >= '0' and <= '9');

    class Element(string name, string n1, string n2, Rational value)
    {
        public string Name = name, N1 = n1, N2 = n2;
        public string? C1, C2, Reference;
        public char Kind = name[0];
        public Rational Value = value;
        public bool Voltage => Kind is 'V' or 'E' or 'H';
        public bool Independent => Kind is 'V' or 'I';
        public IEnumerable<string> Terminals => C1 == null ? new[] { N1, N2 } : new[] { N1, N2, C1, C2! };
        public override string ToString() => $"{Name} {N1} {N2}" + (C1 != null ? $" {C1} {C2}" : Reference != null ? " " + Reference : "") + " " + Value;
    }

    class Groups
    {
        readonly Dictionary<string, string> parents = new(StringComparer.Ordinal);
        public Groups(IEnumerable<string> nodes)
        {
            foreach (string node in nodes) parents[node] = node;
        }
        public string Find(string node)
        {
            string parent = parents[node];
            if (parent != node) parents[node] = parent = Find(parent);
            return parent;
        }
        public bool Join(string a, string b)
        {
            a = Find(a);
            b = Find(b);
            if (a == b) return false;
            if (StringComparer.Ordinal.Compare(a, b) < 0) parents[b] = a;
            else parents[a] = b;
            return true;
        }
    }

    static Rational[] Zero(int count) => Enumerable.Repeat(Rational.Zero, count).ToArray();

    static Rational[][] ZeroMatrix(int count) => Enumerable.Range(0, count).Select(_ => Zero(count)).ToArray();

    static Rational[]? Solve(Rational[][] matrix, Rational[] column)
    {
        int count = column.Length;
        Rational[][] rows = Enumerable.Range(0, count).Select(i => matrix[i].Append(column[i]).ToArray()).ToArray();
        for (int k = 0; k < count; k++)
        {
            int pivot = k;
            while (pivot < count && rows[pivot][k].Numerator == 0) pivot++;
            if (pivot == count) return null;
            (rows[k], rows[pivot]) = (rows[pivot], rows[k]);
            Rational value = rows[k][k];
            for (int j = 0; j <= count; j++) rows[k][j] /= value;
            for (int i = 0; i < count; i++) if (i != k && rows[i][k].Numerator != 0)
            {
                Rational factor = rows[i][k];
                for (int j = 0; j <= count; j++) rows[i][j] -= factor * rows[k][j];
            }
        }
        return Enumerable.Range(0, count).Select(i => rows[i][count]).ToArray();
    }

    class Model
    {
        public List<string> Nodes;
        public List<Element> Sources;
        public Dictionary<string, int> Indices = new(StringComparer.Ordinal);
        public Rational[][] A;
        public Rational[] B;
        public Model(List<Element> elements, List<string> nodes, Element? changed = null, Rational replacement = default)
        {
            Nodes = nodes;
            Sources = elements.Where(e => e.Voltage).ToList();
            int count = nodes.Count + Sources.Count;
            for (int i = 0; i < nodes.Count; i++) Indices[nodes[i]] = i;
            for (int i = 0; i < Sources.Count; i++) Indices[Sources[i].Name] = nodes.Count + i;
            A = ZeroMatrix(count);
            B = Zero(count);
            foreach (Element e in elements)
            {
                Rational w = e == changed ? replacement : e.Value;
                switch (e.Kind)
                {
                    case 'R':
                        Rational g = Rational.One / w;
                        Add(e.N1, e.N1, g);
                        Add(e.N2, e.N2, g);
                        Add(e.N1, e.N2, -g);
                        Add(e.N2, e.N1, -g);
                        break;
                    case 'I':
                        Add(B, e.N1, -w);
                        Add(B, e.N2, w);
                        break;
                    case 'G':
                        Add(e.N1, e.C1!, w);
                        Add(e.N2, e.C2!, w);
                        Add(e.N1, e.C2!, -w);
                        Add(e.N2, e.C1!, -w);
                        break;
                    case 'F':
                        Add(e.N1, e.Reference!, w);
                        Add(e.N2, e.Reference!, -w);
                        break;
                    default:
                        Add(e.N1, e.Name, Rational.One);
                        Add(e.Name, e.N1, Rational.One);
                        Add(e.N2, e.Name, -Rational.One);
                        Add(e.Name, e.N2, -Rational.One);
                        if (e.Kind == 'V') Add(B, e.Name, w);
                        else if (e.Kind == 'E')
                        {
                            Add(e.Name, e.C1!, -w);
                            Add(e.Name, e.C2!, w);
                        }
                        else Add(e.Name, e.Reference!, -w);
                        break;
                }
            }
        }
        public void Add(string row, string col, Rational value)
        {
            if (Indices.TryGetValue(row, out int i) && Indices.TryGetValue(col, out int j)) A[i][j] += value;
        }
        public void Add(Rational[] column, string row, Rational value)
        {
            if (Indices.TryGetValue(row, out int i)) column[i] += value;
        }
        public Rational Voltage(Rational[] solution, string node) => node == "0" ? Rational.Zero : solution[Indices[node]];
        public Rational Current(Rational[] solution, Element e) => e.Kind switch
        {
            'R' => (Voltage(solution, e.N1) - Voltage(solution, e.N2)) / e.Value,
            'I' => e.Value,
            'G' => e.Value * (Voltage(solution, e.C1!) - Voltage(solution, e.C2!)),
            'F' => e.Value * solution[Indices[e.Reference!]],
            _ => solution[Indices[e.Name]]
        };
        public Rational[] Injection(string from, string to)
        {
            Rational[] rhs = Zero(B.Length);
            Add(rhs, from, Rational.One);
            Add(rhs, to, -Rational.One);
            return Solve(A, rhs)!;
        }
        public Rational[] Alone(Element source, bool unit)
        {
            Rational[] rhs = Zero(B.Length);
            Rational value = unit ? Rational.One : source.Value;
            if (source.Kind == 'V') Add(rhs, source.Name, value);
            else
            {
                Add(rhs, source.N1, -value);
                Add(rhs, source.N2, value);
            }
            return Solve(A, rhs)!;
        }
    }
    readonly List<Element> elements = new();

    List<string> Nodes(bool includeGround = false) => elements.SelectMany(e => e.Terminals).Where(n => includeGround || n != "0").Distinct().Order(StringComparer.Ordinal).ToList();

    Element? Find(string name) => elements.FirstOrDefault(e => e.Name == name);

    Element Get(string name) => Find(name) ?? throw new Problem("unknown element " + name);

    void Node(string name)
    {
        if (name != "0" && !Nodes().Contains(name)) Fail("unknown node " + name);
    }

    static HashSet<string> Reach(string start, List<Element> edges)
    {
        HashSet<string> reached = new(StringComparer.Ordinal) { start };
        bool changed;
        do
        {
            int before = reached.Count;
            foreach (Element e in edges)
            {
                if (reached.Contains(e.N1)) reached.Add(e.N2);
                if (reached.Contains(e.N2)) reached.Add(e.N1);
            }
            changed = before != reached.Count;
        }
        while (changed);
        return reached;
    }

    List<string> Floating()
    {
        var reached = Reach("0", elements.Where(e => e.Kind == 'R' || e.Voltage).ToList());
        return Nodes().Where(n => !reached.Contains(n)).ToList();
    }

    List<string> Loops()
    {
        Groups groups = new(Nodes(true).Append("0"));
        List<string> result = new();
        foreach (Element e in elements) if (e.Voltage && !groups.Join(e.N1, e.N2)) result.Add(e.Name);
        return result;
    }

    void Structure()
    {
        if (Nodes().Count == 0) Fail("no nodes");
        var floating = Floating();
        if (floating.Count > 0) Fail("floating node " + floating[0]);
        var loops = Loops();
        if (loops.Count > 0) Fail("voltage source loop at " + loops[0]);
    }

    void AddElement(string[] w)
    {
        string name = w[0];
        char kind = name[0];
        if (!"RVIEGFH".Contains(kind)) Fail("unknown element type " + name);
        int count = kind is 'E' or 'G' ? 6 : kind is 'F' or 'H' ? 5 : 4;
        if (w.Length != count) Fail("wrong field count for " + name);
        if (Find(name) != null) Fail("duplicate element " + name);
        for (int i = 1; i <= (count == 6 ? 4 : 2); i++) if (!ValidNode(w[i])) Fail("invalid node " + w[i]);
        if (kind is 'F' or 'H')
        {
            Element? source = Find(w[3]);
            if (source == null || source.Kind != 'V') Fail("unknown voltage source " + w[3]);
        }
        Rational value = Number(w[count - 1]);
        if (kind == 'R' && value.Numerator <= 0) Fail("nonpositive resistance " + name);
        Element e = new(name, w[1], w[2], value);
        if (count == 6)
        {
            e.C1 = w[3];
            e.C2 = w[4];
        }
        else if (count == 5) e.Reference = w[3];
        elements.Add(e);
    }
    static readonly Dictionary<string, int> Arity = new(StringComparer.Ordinal)
    {
        [".OP"] = 0,
        [".CURRENT"] = 1,
        [".VOLTAGE"] = 2,
        [".POWER"] = 0,
        [".KCL"] = 1,
        [".THEVENIN"] = 2,
        [".NORTON"] = 2,
        [".MAXPOWER"] = 2,
        [".TF"] = 2,
        [".SENS"] = 1,
        [".ZPARAM"] = 4,
        [".SUPERPOSITION"] = 1,
        [".SWEEP"] = 5,
        [".MATRIX"] = 0,
        [".REQ"] = 2,
        [".REDUCE"] = 2,
        [".CHECK"] = 0,
        [".ALTER"] = 2,
        [".DELETE"] = 1,
        [".CLEAR"] = 0,
        [".NODES"] = 0,
        [".PRINT"] = 0
    };

    string Resistance(string from, string to)
    {
        Groups groups = new(Nodes(true).Append("0"));
        foreach (Element e in elements) if (e.Kind == 'V') groups.Join(e.N1, e.N2);
        string a = groups.Find(from), b = groups.Find(to);
        if (a == b) return "Req = " + Rational.Zero.Value();
        List<Element> edges = new();
        foreach (Element e in elements.Where(e => e.Kind == 'R'))
        {
            string p = groups.Find(e.N1), q = groups.Find(e.N2);
            if (p != q) edges.Add(new(e.Name, p, q, e.Value));
        }
        var reached = Reach(a, edges);
        if (!reached.Contains(b)) return "Req = INFINITE";
        List<string> unknowns = reached.Where(n => n != b).Order(StringComparer.Ordinal).ToList();
        Dictionary<string, int> index = new(StringComparer.Ordinal);
        for (int i = 0; i < unknowns.Count; i++) index[unknowns[i]] = i;
        Rational[][] g = ZeroMatrix(unknowns.Count);
        Rational[] rhs = Zero(unknowns.Count);
        rhs[index[a]] = Rational.One;
        foreach (Element e in edges) if (reached.Contains(e.N1))
        {
            Rational value = Rational.One / e.Value;
            bool hasP = index.TryGetValue(e.N1, out int p), hasQ = index.TryGetValue(e.N2, out int q);
            if (hasP) g[p][p] += value;
            if (hasQ) g[q][q] += value;
            if (hasP && hasQ)
            {
                g[p][q] -= value;
                g[q][p] -= value;
            }
        }
        return "Req = " + Solve(g, rhs)![index[a]].Value();
    }

    List<string> Reduce(string a, string b)
    {
        if (a == b) return new() { "Req = " + Rational.Zero.Value() };
        List<Element> list = elements.Where(e => e.Kind == 'R').ToList();
        var reached = Reach(a, list);
        if (!reached.Contains(b)) return new() { "Req = INFINITE" };
        list.RemoveAll(e => !reached.Contains(e.N1));
        List<string> output = new();
        int sequence = 0;
        while (true)
        {
            int remove = list.FindIndex(e => e.N1 == e.N2);
            if (remove >= 0)
            {
                output.Add("remove " + list[remove].Name);
                list.RemoveAt(remove);
                continue;
            }
            SortedDictionary<string, int> degrees = new(StringComparer.Ordinal);
            foreach (Element e in list)
            {
                degrees[e.N1] = degrees.GetValueOrDefault(e.N1) + 1;
                degrees[e.N2] = degrees.GetValueOrDefault(e.N2) + 1;
            }
            degrees.Remove(a);
            degrees.Remove(b);
            string? leaf = degrees.FirstOrDefault(entry => entry.Value == 1).Key;
            if (leaf != null)
            {
                remove = list.FindIndex(e => e.N1 == leaf || e.N2 == leaf);
                output.Add("remove " + list[remove].Name);
                list.RemoveAt(remove);
                continue;
            }
            int x = -1, y = -1;
            bool parallel = false;
            for (int i = 0; i < list.Count && x < 0; i++) for (int j = i + 1; j < list.Count; j++)
            {
                Element p = list[i], q = list[j];
                if (p.N1 == q.N1 && p.N2 == q.N2 || p.N1 == q.N2 && p.N2 == q.N1)
                {
                    x = i;
                    y = j;
                    parallel = true;
                    break;
                }
            }
            string? middle = null;
            if (x < 0)
            {
                middle = degrees.FirstOrDefault(entry => entry.Value == 2).Key;
                if (middle == null) break;
                for (int i = 0; i < list.Count; i++) if (list[i].N1 == middle || list[i].N2 == middle)
                {
                    if (x < 0) x = i;
                    else y = i;
                }
            }
            Element first = list[x], second = list[y];
            Rational value = parallel ? first.Value * second.Value / (first.Value + second.Value) : first.Value + second.Value;
            string left = parallel ? first.N1 : first.N1 == middle ? first.N2 : first.N1, right = parallel ? first.N2 : second.N1 == middle ? second.N2 : second.N1;
            Element next = new("#" + (++sequence), left, right, value);
            list.RemoveAt(y);
            list.RemoveAt(x);
            list.Add(next);
            output.Add(next.Name + " = " + first.Name + (parallel ? " || " : " + ") + second.Name + " = " + value.Value());
        }
        output.Add(list.Count == 1 ? "Req = " + list[0].Value.Value() : $"not series-parallel: {list.Count} resistors remain");
        return output;
    }

    List<string> Command(string[] w)
    {
        string c = w[0];
        if (!Arity.TryGetValue(c, out int arity)) Fail("unknown command " + c);
        if (w.Length - 1 != arity) Fail("wrong argument count for " + c);
        List<string> output = new();
        switch (c)
        {
            case ".ALTER":
            {
                Element e = Get(w[1]);
                Rational value = Number(w[2]);
                if (e.Kind == 'R' && value.Numerator <= 0) Fail("nonpositive resistance " + e.Name);
                output.Add($"altered {e.Name}: {e.Value} -> {value}");
                e.Value = value;
                return output;
            }
            case ".DELETE":
            {
                Element e = Get(w[1]);
                foreach (Element other in elements) if (other.Reference == w[1]) Fail(w[1] + " is referenced by " + other.Name);
                elements.Remove(e);
                return new() { "deleted " + e.Name };
            }
            case ".CLEAR":
            {
                int count = elements.Count;
                elements.Clear();
                return new() { $"cleared {count} elements" };
            }
            case ".PRINT":
                return elements.Count == 0 ? new() { "empty netlist" } : elements.Select(e => e.ToString()).ToList();
            case ".NODES":
                foreach (string name in Nodes(true)) output.Add(name + ": " + string.Join(" ", elements.Where(e => e.Terminals.Contains(name)).Select(e => e.Name)));
                return output.Count == 0 ? new() { "no nodes" } : output;
            case ".REQ":
            case ".REDUCE":
                Node(w[1]);
                Node(w[2]);
                return c == ".REQ" ? new() { Resistance(w[1], w[2]) } : Reduce(w[1], w[2]);
            case ".CHECK":
            {
                if (Nodes().Count == 0) return new() { "no nodes" };
                foreach (string node in Nodes())
                {
                    int degree = elements.Sum(e => (e.N1 == node ? 1 : 0) + (e.N2 == node ? 1 : 0));
                    if (degree < 2) output.Add("dangling node " + node);
                }
                output.AddRange(Floating().Select(n => "floating node " + n));
                output.AddRange(Loops().Select(n => "voltage source loop at " + n));
                if (output.Count == 0)
                {
                    Model model = new(elements, Nodes());
                    if (Solve(model.A, model.B) == null) output.Add("singular matrix");
                }
                return output.Count == 0 ? new() { "ok" } : output;
            }
            case ".SWEEP":
            {
                Element e = Get(w[1]);
                Rational from = Number(w[2]), to = Number(w[3]), step = Number(w[4]);
                Node(w[5]);
                if (step.Numerator <= 0) Fail("invalid sweep step");
                if (from.CompareTo(to) > 0) Fail("invalid sweep range");
                Rational span = (to - from) / step;
                long count = span.Numerator / span.Denominator + 1;
                if (count > 20) Fail("too many sweep points");
                if (e.Kind == 'R' && from.Numerator <= 0) Fail("nonpositive resistance " + e.Name);
                Structure();
                for (int k = 0; k < count; k++)
                {
                    Rational value = from + step * new Rational(k);
                    Model model = new(elements, Nodes(), e, value);
                    Rational[]? solution = Solve(model.A, model.B);
                    output.Add(e.Name + " = " + value + ": " + (solution == null ? "singular matrix" : $"V({w[5]}) = {model.Voltage(solution, w[5]).Value()}"));
                }
                return output;
            }
        }
        Element? selected = null;
        switch (c)
        {
            case ".CURRENT":
                selected = Get(w[1]);
                break;
            case ".VOLTAGE":
            case ".THEVENIN":
            case ".NORTON":
            case ".MAXPOWER":
                Node(w[1]);
                Node(w[2]);
                break;
            case ".KCL":
            case ".SENS":
            case ".SUPERPOSITION":
                Node(w[1]);
                break;
            case ".ZPARAM":
                for (int i = 1; i <= 4; i++) Node(w[i]);
                break;
            case ".TF":
                Node(w[1]);
                selected = Get(w[2]);
                if (!selected.Independent) Fail("not an independent source " + selected.Name);
                break;
        }
        Structure();
        Model circuit = new(elements, Nodes());
        if (c == ".MATRIX")
        {
            output.Add("unknowns: " + string.Join(" ", circuit.Nodes.Select(n => "V(" + n + ")").Concat(circuit.Sources.Select(e => "I(" + e.Name + ")"))));
            for (int i = 0; i < circuit.B.Length; i++)
            {
                string label = i < circuit.Nodes.Count ? circuit.Nodes[i] : circuit.Sources[i - circuit.Nodes.Count].Name;
                output.Add(label + ": " + string.Join(" ", circuit.A[i].Select(q => q.ToString())) + " | " + circuit.B[i]);
            }
            return output;
        }
        Rational[] point = Solve(circuit.A, circuit.B) ?? throw new Problem("singular matrix");
        switch (c)
        {
            case ".OP":
                foreach (string node in circuit.Nodes) output.Add($"V({node}) = {circuit.Voltage(point, node).Value()}");
                foreach (Element e in circuit.Sources) output.Add($"I({e.Name}) = {circuit.Current(point, e).Value()}");
                break;
            case ".CURRENT":
                output.Add($"I({selected!.Name}) = {circuit.Current(point, selected).Value()}");
                break;
            case ".VOLTAGE":
                output.Add($"V({w[1]},{w[2]}) = {(circuit.Voltage(point, w[1]) - circuit.Voltage(point, w[2])).Value()}");
                break;
            case ".POWER":
            {
                Rational absorbed = Rational.Zero, delivered = Rational.Zero, total = Rational.Zero;
                foreach (Element e in elements)
                {
                    Rational power = (circuit.Voltage(point, e.N1) - circuit.Voltage(point, e.N2)) * circuit.Current(point, e);
                    output.Add($"P({e.Name}) = {power.Value()}");
                    if (power.Numerator > 0) absorbed += power;
                    if (power.Numerator < 0) delivered -= power;
                    total += power;
                }
                output.Add("absorbed = " + absorbed.Value());
                output.Add("delivered = " + delivered.Value());
                output.Add("total = " + total.Value());
                break;
            }
            case ".KCL":
            {
                Rational total = Rational.Zero;
                foreach (Element e in elements) if (e.N1 == w[1] || e.N2 == w[1])
                {
                    Rational value = e.N1 == e.N2 ? Rational.Zero : e.N1 == w[1] ? circuit.Current(point, e) : -circuit.Current(point, e);
                    output.Add($"I({e.Name}) leaving {w[1]} = {value.Value()}");
                    total += value;
                }
                output.Add("sum = " + total.Value());
                break;
            }
            case ".THEVENIN":
            case ".NORTON":
            case ".MAXPOWER":
            {
                Rational voltage = circuit.Voltage(point, w[1]) - circuit.Voltage(point, w[2]);
                Rational[] injection = circuit.Injection(w[1], w[2]);
                Rational resistance = circuit.Voltage(injection, w[1]) - circuit.Voltage(injection, w[2]);
                if (c == ".NORTON" && resistance.Numerator == 0) Fail("zero thevenin resistance");
                if (c == ".MAXPOWER" && resistance.Numerator <= 0) Fail("nonpositive thevenin resistance");
                if (c == ".THEVENIN")
                {
                    output.Add("Vth = " + voltage.Value());
                    output.Add("Rth = " + resistance.Value());
                }
                else if (c == ".NORTON")
                {
                    output.Add("In = " + (voltage / resistance).Value());
                    output.Add("Rn = " + resistance.Value());
                }
                else
                {
                    output.Add("RL = " + resistance.Value());
                    output.Add("Pmax = " + (voltage * voltage / (new Rational(4) * resistance)).Value());
                }
                break;
            }
            case ".TF":
            {
                Rational[] unit = circuit.Alone(selected!, true);
                output.Add("gain = " + circuit.Voltage(unit, w[1]).Value());
                if (selected!.Kind == 'V')
                {
                    Rational current = unit[circuit.Indices[selected.Name]];
                    output.Add("input resistance = " + (current.Numerator == 0 ? "INFINITE" : (-Rational.One / current).Value()));
                }
                else output.Add("input resistance = " + (circuit.Voltage(unit, selected.N2) - circuit.Voltage(unit, selected.N1)).Value());
                output.Add("output resistance = " + circuit.Voltage(circuit.Injection(w[1], "0"), w[1]).Value());
                break;
            }
            case ".SENS":
                foreach (Element e in elements)
                {
                    Rational[] rhs = Zero(circuit.B.Length);
                    switch (e.Kind)
                    {
                        case 'R':
                        {
                            Rational value = circuit.Current(point, e) / e.Value;
                            circuit.Add(rhs, e.N1, value);
                            circuit.Add(rhs, e.N2, -value);
                            break;
                        }
                        case 'I':
                            circuit.Add(rhs, e.N1, -Rational.One);
                            circuit.Add(rhs, e.N2, Rational.One);
                            break;
                        case 'G':
                        case 'F':
                        {
                            Rational value = e.Kind == 'G' ? circuit.Voltage(point, e.C1!) - circuit.Voltage(point, e.C2!) : point[circuit.Indices[e.Reference!]];
                            circuit.Add(rhs, e.N1, -value);
                            circuit.Add(rhs, e.N2, value);
                            break;
                        }
                        case 'V':
                            circuit.Add(rhs, e.Name, Rational.One);
                            break;
                        case 'E':
                            circuit.Add(rhs, e.Name, circuit.Voltage(point, e.C1!) - circuit.Voltage(point, e.C2!));
                            break;
                        case 'H':
                            circuit.Add(rhs, e.Name, point[circuit.Indices[e.Reference!]]);
                            break;
                    }
                    output.Add($"dV({w[1]})/d{e.Name} = {circuit.Voltage(Solve(circuit.A, rhs)!, w[1]).Value()}");
                }
                break;
            case ".ZPARAM":
            {
                Rational[] first = circuit.Injection(w[1], w[2]), second = circuit.Injection(w[3], w[4]);
                output.Add("z11 = " + (circuit.Voltage(first, w[1]) - circuit.Voltage(first, w[2])).Value());
                output.Add("z12 = " + (circuit.Voltage(second, w[1]) - circuit.Voltage(second, w[2])).Value());
                output.Add("z21 = " + (circuit.Voltage(first, w[3]) - circuit.Voltage(first, w[4])).Value());
                output.Add("z22 = " + (circuit.Voltage(second, w[3]) - circuit.Voltage(second, w[4])).Value());
                break;
            }
            case ".SUPERPOSITION":
            {
                Rational total = Rational.Zero;
                foreach (Element e in elements) if (e.Independent)
                {
                    Rational value = circuit.Voltage(circuit.Alone(e, false), w[1]);
                    output.Add($"{e.Name}: V({w[1]}) = {value.Value()}");
                    total += value;
                }
                output.Add($"total: V({w[1]}) = {total.Value()}");
                break;
            }
        }
        return output;
    }

    static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        Program circuit = new();
        string? line;
        int number = 0;
        while ((line = Console.ReadLine()) != null)
        {
            number++;
            if (line == ".END") break;
            if (line.StartsWith('*')) continue;
            string[] words = line.Split(' ');
            try
            {
                if (line.StartsWith('.')) foreach (string output in circuit.Command(words)) Console.WriteLine(output);
                else circuit.AddElement(words);
            }
            catch (Problem problem)
            {
                Console.WriteLine($"error: line {number}: {problem.Message}");
            }
        }
    }
}
