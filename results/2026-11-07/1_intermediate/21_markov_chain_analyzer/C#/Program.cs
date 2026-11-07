using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;

class Program
{
    sealed class CommandError(string message) : Exception(message) { }

    static long Gcd(long a, long b)
    {
        a = Math.Abs(a);
        b = Math.Abs(b);
        while (b != 0) (a, b) = (b, a % b);
        return a;
    }

    readonly record struct Fraction : IComparable<Fraction>
    {
        public long Numerator { get; }
        public long Denominator { get; }
        public static readonly Fraction Zero = new(0);
        public static readonly Fraction One = new(1);
        public static readonly Fraction Two = new(2);

        public Fraction(long numerator, long denominator = 1)
        {
            if (denominator < 0) (numerator, denominator) = (-numerator, -denominator);
            long divisor = Gcd(numerator, denominator);
            Numerator = numerator / divisor;
            Denominator = denominator / divisor;
        }

        public static Fraction operator +(Fraction a, Fraction b) =>
            new(a.Numerator * b.Denominator + b.Numerator * a.Denominator, a.Denominator * b.Denominator);
        public static Fraction operator -(Fraction a, Fraction b) =>
            new(a.Numerator * b.Denominator - b.Numerator * a.Denominator, a.Denominator * b.Denominator);
        public static Fraction operator *(Fraction a, Fraction b) =>
            new(a.Numerator * b.Numerator, a.Denominator * b.Denominator);
        public static Fraction operator /(Fraction a, Fraction b) =>
            new(a.Numerator * b.Denominator, a.Denominator * b.Numerator);
        public int CompareTo(Fraction other) =>
            (Numerator * other.Denominator).CompareTo(other.Numerator * Denominator);
        public static bool operator <(Fraction a, Fraction b) => a.CompareTo(b) < 0;
        public static bool operator >(Fraction a, Fraction b) => a.CompareTo(b) > 0;
        public static bool operator <=(Fraction a, Fraction b) => a.CompareTo(b) <= 0;
        public static bool operator >=(Fraction a, Fraction b) => a.CompareTo(b) >= 0;
        public bool IsZero => Numerator == 0;
        public Fraction Absolute => new(Math.Abs(Numerator), Denominator);
        public override string ToString() => $"{Numerator}/{Denominator}";
        public string Value => $"{this}({Numerator / Denominator}.{Numerator % Denominator * 1000000 / Denominator:D6})";
    }

    static Fraction Probability(string text)
    {
        var parts = text.Split('/');
        long numerator = long.Parse(parts[0]);
        long denominator = parts.Length == 1 ? 1 : long.Parse(parts[1]);
        if (denominator == 0 || numerator > denominator) throw new CommandError("BAD PROBABILITY");
        return new Fraction(numerator, denominator);
    }

    static Fraction[] Vector(int size) => Enumerable.Repeat(Fraction.Zero, size).ToArray();
    static Fraction[][] Matrix(int rows, int columns) =>
        Enumerable.Range(0, rows).Select(_ => Vector(columns)).ToArray();
    static Fraction Delta(int i, int j) => i == j ? Fraction.One : Fraction.Zero;
    static Fraction Sum(IEnumerable<Fraction> values)
    {
        var total = Fraction.Zero;
        foreach (var value in values) total += value;
        return total;
    }

    static Fraction[][] Identity(int size)
    {
        var result = Matrix(size, size);
        for (int i = 0; i < size; i++) result[i][i] = Fraction.One;
        return result;
    }

    static Fraction[] Advance(Fraction[] distribution, Fraction[][] transitions)
    {
        var result = Vector(distribution.Length);
        for (int j = 0; j < result.Length; j++)
            for (int i = 0; i < distribution.Length; i++)
                result[j] += distribution[i] * transitions[i][j];
        return result;
    }

    static Fraction[][] Multiply(Fraction[][] left, Fraction[][] right) =>
        left.Select(row => Advance(row, right)).ToArray();

    static Fraction[][] Solve(Fraction[][] rows)
    {
        int size = rows.Length;
        if (size == 0) return [];
        int width = rows[0].Length;
        for (int column = 0; column < size; column++)
        {
            int pivotRow = column;
            while (rows[pivotRow][column].IsZero) pivotRow++;
            (rows[column], rows[pivotRow]) = (rows[pivotRow], rows[column]);
            var pivot = rows[column][column];
            for (int j = 0; j < width; j++) rows[column][j] /= pivot;
            for (int i = 0; i < size; i++)
            {
                if (i == column) continue;
                var factor = rows[i][column];
                if (factor.IsZero) continue;
                for (int j = 0; j < width; j++) rows[i][j] -= factor * rows[column][j];
            }
        }
        return rows.Select(row => row[size..]).ToArray();
    }

    sealed record Component(int[] States, bool Closed, int Period, int[] Levels);
    sealed record Graph(bool[][] Reach, Component[] Classes);
    sealed record HitResult(Fraction[] Probability, Fraction?[] Time);
    sealed record Absorption(int[] Transient, int[] Absorbing, Fraction[][] Fundamental,
        Fraction[][] Probability, Fraction[] Mean, Fraction[] Variance);

    sealed class Chain(string[] names, Fraction[][] transitions)
    {
        public string[] Names { get; } = names;
        public Fraction[][] P { get; } = transitions;
        public int Size => Names.Length;
        public IEnumerable<int> Indices => Enumerable.Range(0, Size);
        public string Labels(IEnumerable<int> states, string separator = " ") =>
            string.Join(separator, states.Select(i => Names[i]));

        public int State(string name)
        {
            int index = Array.IndexOf(Names, name);
            if (index < 0) throw new CommandError($"UNKNOWN STATE {name}");
            return index;
        }

        public int[] StateSet(IEnumerable<string> names)
        {
            var states = new HashSet<int>();
            foreach (string name in names)
                if (!states.Add(State(name))) throw new CommandError($"DUPLICATE STATE {name}");
            return states.Order().ToArray();
        }

        public void CheckStochastic()
        {
            foreach (int i in Indices)
                if (Sum(P[i]) != Fraction.One) throw new CommandError($"NOT STOCHASTIC {Names[i]}");
        }

        public Graph AnalyzeGraph()
        {
            var reach = Indices.Select(i => Indices.Select(j => i == j || !P[i][j].IsZero).ToArray()).ToArray();
            for (int k = 0; k < Size; k++)
                for (int i = 0; i < Size; i++)
                    for (int j = 0; j < Size; j++)
                        reach[i][j] |= reach[i][k] && reach[k][j];
            var assigned = new bool[Size];
            var classes = new List<Component>();
            for (int first = 0; first < Size; first++)
            {
                if (assigned[first]) continue;
                int[] states = Indices.Where(j => reach[first][j] && reach[j][first]).ToArray();
                var members = states.ToHashSet();
                foreach (int i in states) assigned[i] = true;
                bool closed = states.All(i => Indices.All(j => members.Contains(j) || P[i][j].IsZero));
                var levels = Enumerable.Repeat(-1, Size).ToArray();
                levels[first] = 0;
                var queue = new Queue<int>();
                queue.Enqueue(first);
                while (queue.TryDequeue(out int current))
                    foreach (int j in states)
                        if (levels[j] < 0 && !P[current][j].IsZero)
                        {
                            levels[j] = levels[current] + 1;
                            queue.Enqueue(j);
                        }
                int period = 0;
                foreach (int i in states)
                    foreach (int j in states)
                        if (!P[i][j].IsZero) period = (int)Gcd(period, levels[i] + 1 - levels[j]);
                classes.Add(new Component(states, closed, period, levels));
            }
            return new Graph(reach, classes.ToArray());
        }

        public Fraction[] Stationary(int[] states)
        {
            int count = states.Length;
            var equations = Matrix(count, count + 1);
            for (int row = 0; row < count - 1; row++)
                for (int col = 0; col < count; col++)
                    equations[row][col] = P[states[col]][states[row]] - Delta(col, row);
            Array.Fill(equations[count - 1], Fraction.One);
            var solution = Solve(equations);
            var distribution = Vector(Size);
            for (int i = 0; i < count; i++) distribution[states[i]] = solution[i][0];
            return distribution;
        }

        public Fraction[] UniqueStationary()
        {
            var classes = AnalyzeGraph().Classes;
            if (classes.Length != 1) throw new CommandError("NOT IRREDUCIBLE");
            return Stationary(classes[0].States);
        }

        public HitResult Hitting(int[] targets, bool withTimes = true)
        {
            var reach = AnalyzeGraph().Reach;
            var targetSet = targets.ToHashSet();
            int[] unknown = Indices.Where(i => !targetSet.Contains(i) && targets.Any(j => reach[i][j])).ToArray();
            var probability = Vector(Size);
            var time = new Fraction?[Size];
            foreach (int target in targets)
            {
                probability[target] = Fraction.One;
                time[target] = Fraction.Zero;
            }
            if (unknown.Length > 0)
            {
                var equations = Matrix(unknown.Length, unknown.Length + 1);
                for (int i = 0; i < unknown.Length; i++)
                {
                    for (int j = 0; j < unknown.Length; j++)
                        equations[i][j] = Delta(i, j) - P[unknown[i]][unknown[j]];
                    equations[i][unknown.Length] = Sum(targets.Select(j => P[unknown[i]][j]));
                }
                var solution = Solve(equations);
                for (int i = 0; i < unknown.Length; i++) probability[unknown[i]] = solution[i][0];
            }
            int[] certain = unknown.Where(i => probability[i] == Fraction.One).ToArray();
            if (withTimes && certain.Length > 0)
            {
                var equations = Matrix(certain.Length, certain.Length + 1);
                for (int i = 0; i < certain.Length; i++)
                {
                    for (int j = 0; j < certain.Length; j++)
                        equations[i][j] = Delta(i, j) - P[certain[i]][certain[j]];
                    equations[i][certain.Length] = Fraction.One;
                }
                var solution = Solve(equations);
                for (int i = 0; i < certain.Length; i++) time[certain[i]] = solution[i][0];
            }
            return new HitResult(probability, time);
        }

        public Absorption Absorb()
        {
            int[] absorbing = Indices.Where(i => P[i][i] == Fraction.One).ToArray();
            if (absorbing.Length == 0) throw new CommandError("NO ABSORBING STATE");
            int[] transient = Indices.Where(i => P[i][i] != Fraction.One).ToArray();
            var reach = AnalyzeGraph().Reach;
            foreach (int i in transient)
                if (!absorbing.Any(j => reach[i][j])) throw new CommandError($"NOT ABSORBING {Names[i]}");
            int size = transient.Length;
            var equations = Matrix(size, 2 * size);
            for (int i = 0; i < size; i++)
                for (int j = 0; j < size; j++)
                {
                    equations[i][j] = Delta(i, j) - P[transient[i]][transient[j]];
                    equations[i][size + j] = Delta(i, j);
                }
            var fundamental = Solve(equations);
            var mean = fundamental.Select(Sum).ToArray();
            var variance = Vector(size);
            var probability = Matrix(size, absorbing.Length);
            for (int i = 0; i < size; i++)
            {
                for (int j = 0; j < size; j++)
                    variance[i] += (Fraction.Two * fundamental[i][j] - Delta(i, j)) * mean[j];
                variance[i] -= mean[i] * mean[i];
                for (int j = 0; j < absorbing.Length; j++)
                    for (int k = 0; k < size; k++)
                        probability[i][j] += fundamental[i][k] * P[transient[k]][absorbing[j]];
            }
            return new Absorption(transient, absorbing, fundamental, probability, mean, variance);
        }
    }

    sealed class Analyzer
    {
        readonly Dictionary<string, Chain> chains = new(StringComparer.Ordinal);
        readonly StringBuilder output = new();
        void Emit(string line) => output.Append(line).Append('\n');
        static string Yes(bool value) => value ? "yes" : "no";
        public override string ToString() => output.ToString();

        void Display(Chain chain, Fraction[][]? values = null, string label = "ROW")
        {
            values ??= chain.P;
            Emit($"STATES {string.Join(" ", chain.Names)}");
            for (int i = 0; i < chain.Size; i++)
                Emit($"{label} {chain.Names[i]} {string.Join(" ", values[i])}");
        }

        void Create(string[] words)
        {
            string name = words[1];
            string[] names = words[2..];
            if (names.Length > 10) throw new CommandError("TOO MANY STATES");
            var seen = new HashSet<string>(StringComparer.Ordinal);
            foreach (string state in names)
                if (!seen.Add(state)) throw new CommandError($"DUPLICATE STATE {state}");
            chains[name] = new Chain(names, Matrix(names.Length, names.Length));
            Emit($"CHAIN {name} states={names.Length}");
        }

        void Build(string[] words)
        {
            string name = words[1];
            int order = int.Parse(words[2]);
            if (order is not (1 or 2)) throw new CommandError("BAD ORDER");
            string[] tokens = words[3..];
            if (tokens.Length <= order) throw new CommandError("TOO FEW TOKENS");
            string[] observations = order == 1 ? tokens :
                Enumerable.Range(0, tokens.Length - 1).Select(i => $"{tokens[i]}.{tokens[i + 1]}").ToArray();
            var names = new List<string>();
            var seen = new HashSet<string>(StringComparer.Ordinal);
            foreach (string state in observations) if (seen.Add(state)) names.Add(state);
            if (names.Count > 10) throw new CommandError("TOO MANY STATES");
            var chain = new Chain(names.ToArray(), Matrix(names.Count, names.Count));
            var counts = new int[chain.Size, chain.Size];
            var totals = new int[chain.Size];
            for (int i = 0; i < observations.Length - 1; i++)
            {
                int from = chain.State(observations[i]), to = chain.State(observations[i + 1]);
                counts[from, to]++;
                totals[from]++;
            }
            foreach (int i in chain.Indices)
                if (totals[i] == 0) chain.P[i][i] = Fraction.One;
                else foreach (int j in chain.Indices) chain.P[i][j] = new Fraction(counts[i, j], totals[i]);
            chains[name] = chain;
            Emit($"BUILD {name} order={order} states={chain.Size} transitions={observations.Length - 1}");
            foreach (int i in chain.Indices)
            {
                string suffix = totals[i] == 0 ? "absorbing" : string.Join(" ", chain.Indices
                    .Where(j => counts[i, j] > 0).Select(j => $"{chain.Names[j]}:{counts[i, j]}"));
                Emit($"FROM {chain.Names[i]} total={totals[i]} {suffix}");
            }
        }

        void Gambler(string[] words)
        {
            string name = words[1];
            int goal = int.Parse(words[2]), start = int.Parse(words[3]);
            if (goal is 0 or > 9) throw new CommandError("BAD SIZE");
            if (start > goal) throw new CommandError("BAD START");
            var up = Probability(words[4]);
            if (up.IsZero || up == Fraction.One) throw new CommandError("BAD PROBABILITY");
            var names = Enumerable.Range(0, goal + 1).Select(i => $"s{i}").ToArray();
            var chain = new Chain(names, Matrix(goal + 1, goal + 1));
            chain.P[0][0] = chain.P[goal][goal] = Fraction.One;
            for (int i = 1; i < goal; i++)
            {
                chain.P[i][i - 1] = Fraction.One - up;
                chain.P[i][i + 1] = up;
            }
            var result = chain.Absorb();
            var ruin = Vector(chain.Size);
            var duration = Vector(chain.Size);
            ruin[0] = Fraction.One;
            for (int i = 0; i < result.Transient.Length; i++)
            {
                ruin[result.Transient[i]] = result.Probability[i][0];
                duration[result.Transient[i]] = result.Mean[i];
            }
            chains[name] = chain;
            Emit($"GAMBLER {name} g={goal} p={up} start=s{start} ruin={ruin[start].Value} duration={duration[start].Value}");
            foreach (int i in chain.Indices)
                Emit($"CAPITAL s{i} ruin={ruin[i].Value} win={(Fraction.One - ruin[i]).Value} duration={duration[i].Value}");
        }

        void Classes(string name, Chain chain)
        {
            var classes = chain.AnalyzeGraph().Classes;
            Emit($"CLASSES {name} count={classes.Length}");
            for (int i = 0; i < classes.Length; i++)
            {
                var component = classes[i];
                Emit($"CLASS {i + 1} {(component.Closed ? "RECURRENT" : "TRANSIENT")} " +
                    $"period={component.Period} size={component.States.Length} {chain.Labels(component.States)}");
                if (component.Period >= 2)
                    for (int r = 0; r < component.Period; r++)
                        Emit($"CYCLIC {r} {chain.Labels(component.States.Where(j => component.Levels[j] % component.Period == r))}");
            }
        }

        void Classify(string name, Chain chain)
        {
            var graph = chain.AnalyzeGraph();
            int[] absorbing = chain.Indices.Where(i => chain.P[i][i] == Fraction.One).ToArray();
            bool allAbsorbed = absorbing.Length > 0 && chain.Indices.All(i => absorbing.Any(j => graph.Reach[i][j]));
            var edges = chain.P.Select(row => row.Select(p => !p.IsZero).ToArray()).ToArray();
            var power = edges;
            int? exponent = null;
            int bound = (chain.Size - 1) * (chain.Size - 1) + 1;
            for (int t = 1; t <= bound; t++)
            {
                if (power.All(row => row.All(value => value)))
                {
                    exponent = t;
                    break;
                }
                power = chain.Indices.Select(i => chain.Indices.Select(j =>
                    chain.Indices.Any(k => power[i][k] && edges[k][j])).ToArray()).ToArray();
            }
            Emit($"CLASSIFY {name} absorbing_states={absorbing.Length} absorbing={Yes(allAbsorbed)} " +
                $"ergodic={Yes(graph.Classes.Length == 1)} regular={Yes(exponent.HasValue)} exponent={exponent?.ToString() ?? "-"}");
        }

        void Step(string[] words, Chain chain)
        {
            Fraction[] distribution;
            string initial = words[2];
            if (char.IsAsciiDigit(initial[0]))
            {
                string[] values = initial.Split(',');
                if (values.Length != chain.Size) throw new CommandError("BAD LENGTH");
                distribution = values.Select(Probability).ToArray();
                if (Sum(distribution) != Fraction.One) throw new CommandError("BAD DISTRIBUTION");
            }
            else
            {
                distribution = Vector(chain.Size);
                distribution[chain.State(initial)] = Fraction.One;
            }
            int steps = int.Parse(words[3]);
            for (int t = 0; t < steps; t++) distribution = Advance(distribution, chain.P);
            Emit($"STEP {words[1]} k={steps}");
            foreach (int i in chain.Indices) Emit($"PROB {chain.Names[i]} {distribution[i].Value}");
        }

        void Stationary(string name, Chain chain)
        {
            var classes = chain.AnalyzeGraph().Classes;
            Emit($"STATIONARY {name} count={classes.Count(component => component.Closed)}");
            int number = 0;
            for (int i = 0; i < classes.Length; i++)
            {
                var component = classes[i];
                if (!component.Closed) continue;
                var distribution = chain.Stationary(component.States);
                Emit($"DIST {++number} class={i + 1} size={component.States.Length}");
                foreach (int state in component.States) Emit($"PI {chain.Names[state]} {distribution[state].Value}");
            }
        }

        void Recurrence(string[] words, Chain chain)
        {
            int state = chain.State(words[2]);
            var component = chain.AnalyzeGraph().Classes.Single(c => c.States.Contains(state));
            if (!component.Closed) throw new CommandError($"TRANSIENT STATE {words[2]}");
            var rho = chain.Stationary(component.States)[state];
            Emit($"RECURRENCE {words[1]} {words[2]} pi={rho.Value} mean={(Fraction.One / rho).Value} period={component.Period}");
        }

        void Absorb(string name, Chain chain)
        {
            var result = chain.Absorb();
            Emit($"ABSORB {name} transient={result.Transient.Length} absorbing={result.Absorbing.Length}");
            if (result.Transient.Length == 0) return;
            Emit($"TRANSIENT {chain.Labels(result.Transient)}");
            Emit($"ABSORBING {chain.Labels(result.Absorbing)}");
            for (int i = 0; i < result.Transient.Length; i++)
                Emit($"N {chain.Names[result.Transient[i]]} {string.Join(" ", result.Fundamental[i])}");
            for (int i = 0; i < result.Transient.Length; i++)
                Emit($"STEPS {chain.Names[result.Transient[i]]} mean={result.Mean[i].Value} var={result.Variance[i].Value}");
            for (int i = 0; i < result.Transient.Length; i++)
                Emit($"B {chain.Names[result.Transient[i]]} {string.Join(" ", result.Probability[i])}");
        }

        void Hitting(string[] words, Chain chain)
        {
            int[] targets = chain.StateSet(words[2..]);
            var result = chain.Hitting(targets);
            Emit($"HITTING {words[1]} targets={chain.Labels(targets, ",")}");
            foreach (int i in chain.Indices)
                Emit($"HIT {chain.Names[i]} prob={result.Probability[i].Value} time={result.Time[i]?.Value ?? "inf"}");
        }

        void Passage(string name, Chain chain)
        {
            var pi = chain.UniqueStationary();
            var passage = Matrix(chain.Size, chain.Size);
            foreach (int j in chain.Indices)
            {
                var times = chain.Hitting([j]).Time;
                foreach (int i in chain.Indices) passage[i][j] = i == j ? Fraction.One / pi[j] : times[i]!.Value;
            }
            var kemeny = Fraction.Zero;
            for (int j = 1; j < chain.Size; j++) kemeny += pi[j] * passage[0][j];
            Emit($"PASSAGE {name} kemeny={kemeny.Value}");
            Display(chain, passage, "M");
        }

        void FirstPassage(string[] words, Chain chain)
        {
            int from = chain.State(words[2]), target = chain.State(words[3]);
            int steps = int.Parse(words[4]);
            if (steps == 0) throw new CommandError("BAD STEPS");
            var previous = chain.Indices.Select(i => chain.P[i][target]).ToArray();
            var entries = new List<(Fraction Probability, Fraction Cumulative)>();
            var total = Fraction.Zero;
            for (int t = 1; t <= steps; t++)
            {
                total += previous[from];
                entries.Add((previous[from], total));
                if (t < steps)
                    previous = chain.Indices.Select(i => Sum(chain.Indices.Where(j => j != target)
                        .Select(j => chain.P[i][j] * previous[j]))).ToArray();
            }
            Emit($"FIRSTPASSAGE {words[1]} {words[2]} {words[3]} k={steps} total={total.Value}");
            for (int i = 0; i < entries.Count; i++)
                Emit($"FP {i + 1} {entries[i].Probability.Value} cum={entries[i].Cumulative.Value}");
        }

        void PathProbability(string[] words, Chain chain)
        {
            int[] states = words[2..].Select(chain.State).ToArray();
            var product = Fraction.One;
            int? zeroAt = null;
            for (int i = 1; i < states.Length; i++)
            {
                product *= chain.P[states[i - 1]][states[i]];
                if (product.IsZero) zeroAt ??= i;
            }
            Emit($"PATHPROB {words[1]} steps={states.Length - 1} prob={product.Value}" +
                (zeroAt.HasValue ? $" zero_at={zeroAt}" : ""));
        }

        void MostLikely(string[] words, Chain chain)
        {
            int start = chain.State(words[2]), steps = int.Parse(words[3]);
            if (steps == 0) throw new CommandError("BAD STEPS");
            var best = Matrix(steps + 1, chain.Size);
            Array.Fill(best[steps], Fraction.One);
            for (int t = steps - 1; t >= 0; t--)
                foreach (int i in chain.Indices)
                    foreach (int j in chain.Indices)
                    {
                        var candidate = chain.P[i][j] * best[t + 1][j];
                        if (candidate > best[t][i]) best[t][i] = candidate;
                    }
            var path = new List<int> { start };
            int state = start;
            for (int t = 0; t < steps; t++)
                foreach (int j in chain.Indices)
                    if (chain.P[state][j] * best[t + 1][j] == best[t][state])
                    {
                        state = j;
                        path.Add(j);
                        break;
                    }
            Emit($"MOSTLIKELY {words[1]} {words[2]} k={steps} prob={best[0][start].Value}");
            Emit($"PATH {chain.Labels(path)}");
        }

        void Reversible(string name, Chain chain)
        {
            var pi = chain.UniqueStationary();
            var violations = new List<(int From, int To, Fraction Forward, Fraction Backward)>();
            foreach (int i in chain.Indices)
                for (int j = i + 1; j < chain.Size; j++)
                {
                    var forward = pi[i] * chain.P[i][j];
                    var backward = pi[j] * chain.P[j][i];
                    if (forward != backward) violations.Add((i, j, forward, backward));
                }
            Emit($"REVERSIBLE {name} {(violations.Count == 0 ? "yes" : $"no violations={violations.Count}")}");
            foreach (var pair in violations)
                Emit($"VIOLATION {chain.Names[pair.From]} {chain.Names[pair.To]} {pair.Forward.Value} {pair.Backward.Value}");
        }

        void Reverse(string[] words, Chain chain)
        {
            var pi = chain.UniqueStationary();
            var reversed = new Chain([.. chain.Names], Matrix(chain.Size, chain.Size));
            bool same = true;
            foreach (int i in chain.Indices)
                foreach (int j in chain.Indices)
                {
                    reversed.P[i][j] = pi[j] * chain.P[j][i] / pi[i];
                    if (reversed.P[i][j] != chain.P[i][j]) same = false;
                }
            chains[words[2]] = reversed;
            Emit($"REVERSE {words[1]} {words[2]} reversible={Yes(same)}");
            Display(reversed);
        }

        void Mixing(string[] words, Chain chain)
        {
            int steps = int.Parse(words[2]);
            if (steps == 0) throw new CommandError("BAD STEPS");
            var epsilon = Probability(words[3]);
            var pi = chain.UniqueStationary();
            var power = Identity(chain.Size);
            var entries = new List<(Fraction Distance, int From)>();
            int? mixing = null;
            for (int t = 1; t <= steps; t++)
            {
                power = Multiply(power, chain.P);
                var distance = Fraction.Zero;
                int from = 0;
                foreach (int i in chain.Indices)
                {
                    var current = Sum(chain.Indices.Select(j => (power[i][j] - pi[j]).Absolute)) / Fraction.Two;
                    if (current > distance) (distance, from) = (current, i);
                }
                if (distance <= epsilon) mixing ??= t;
                entries.Add((distance, from));
            }
            Emit($"MIXING {words[1]} k={steps} eps={epsilon} time={mixing?.ToString() ?? "none"}");
            for (int t = 0; t < entries.Count; t++)
                Emit($"TV {t + 1} {entries[t].Distance.Value} from={chain.Names[entries[t].From]}");
        }

        void Lump(string[] words, Chain chain)
        {
            var blocks = new List<int[]>();
            var seen = new HashSet<int>();
            foreach (string text in words[3].Split('|'))
            {
                var block = new List<int>();
                foreach (string name in text.Split(','))
                {
                    int state = chain.State(name);
                    if (!seen.Add(state)) throw new CommandError("BAD PARTITION");
                    block.Add(state);
                }
                block.Sort();
                blocks.Add(block.ToArray());
            }
            if (seen.Count != chain.Size) throw new CommandError("BAD PARTITION");
            blocks.Sort((a, b) => a[0].CompareTo(b[0]));
            var lumped = new Chain(blocks.Select(block => chain.Names[block[0]]).ToArray(), Matrix(blocks.Count, blocks.Count));
            for (int i = 0; i < blocks.Count; i++)
                for (int j = 0; j < blocks.Count; j++)
                {
                    int representative = blocks[i][0];
                    var baseline = Sum(blocks[j].Select(state => chain.P[representative][state]));
                    foreach (int state in blocks[i])
                    {
                        var value = Sum(blocks[j].Select(target => chain.P[state][target]));
                        if (value != baseline)
                        {
                            Emit($"LUMP {words[1]} not lumpable block={chain.Names[representative]} target={chain.Names[blocks[j][0]]} " +
                                $"{chain.Names[representative]}={baseline.Value} {chain.Names[state]}={value.Value}");
                            return;
                        }
                    }
                    lumped.P[i][j] = baseline;
                }
            chains[words[2]] = lumped;
            Emit($"LUMP {words[1]} {words[2]} blocks={blocks.Count}");
            Display(lumped);
        }

        void Reward(string[] words, Chain chain)
        {
            if (words.Length - 3 != chain.Size) throw new CommandError("BAD LENGTH");
            var discount = Probability(words[2]);
            if (discount == Fraction.One) throw new CommandError("BAD DISCOUNT");
            var rewards = words[3..].Select(text => new Fraction(long.Parse(text))).ToArray();
            var equations = Matrix(chain.Size, chain.Size + 1);
            foreach (int i in chain.Indices)
            {
                foreach (int j in chain.Indices) equations[i][j] = Delta(i, j) - discount * chain.P[i][j];
                equations[i][chain.Size] = rewards[i];
            }
            var discounted = Solve(equations);
            var gain = Vector(chain.Size);
            foreach (var component in chain.AnalyzeGraph().Classes)
            {
                if (!component.Closed) continue;
                var rho = chain.Stationary(component.States);
                var average = Sum(component.States.Select(i => rho[i] * rewards[i]));
                var hitting = chain.Hitting(component.States, withTimes: false).Probability;
                foreach (int i in chain.Indices) gain[i] += hitting[i] * average;
            }
            Emit($"REWARD {words[1]} gamma={discount}");
            foreach (int i in chain.Indices)
                Emit($"VALUE {chain.Names[i]} discounted={discounted[i][0].Value} gain={gain[i].Value}");
        }

        void Restrict(string[] words, Chain chain)
        {
            int[] states = chain.StateSet(words[3..]);
            var inside = states.ToHashSet();
            foreach (int i in states)
                if (chain.Indices.Any(j => !inside.Contains(j) && !chain.P[i][j].IsZero))
                    throw new CommandError($"NOT CLOSED {chain.Names[i]}");
            var restricted = new Chain(states.Select(i => chain.Names[i]).ToArray(),
                states.Select(i => states.Select(j => chain.P[i][j]).ToArray()).ToArray());
            chains[words[2]] = restricted;
            Emit($"RESTRICT {words[1]} {words[2]} states={states.Length}");
            Display(restricted);
        }

        void Simulate(string[] words, Chain chain)
        {
            int state = chain.State(words[2]), steps = int.Parse(words[3]);
            if (steps == 0) throw new CommandError("BAD STEPS");
            long seed = long.Parse(words[4]);
            if (seed == 0 || seed >= 2147483647) throw new CommandError("BAD SEED");
            long random = seed;
            var visits = new int[chain.Size];
            visits[state] = 1;
            var path = new List<int> { state };
            for (int t = 0; t < steps; t++)
            {
                long denominator = 1;
                foreach (var value in chain.P[state])
                    denominator = denominator / Gcd(denominator, value.Denominator) * value.Denominator;
                random = 48271 * random % 2147483647;
                long sample = random % denominator;
                var cumulative = Fraction.Zero;
                foreach (int j in chain.Indices)
                {
                    cumulative += chain.P[state][j];
                    if (cumulative.Numerator * (denominator / cumulative.Denominator) > sample)
                    {
                        state = j;
                        break;
                    }
                }
                path.Add(state);
                visits[state]++;
            }
            Emit($"SIMULATE {words[1]} {words[2]} steps={steps} seed={seed} end={chain.Names[state]}");
            Emit($"PATH {chain.Labels(path)}");
            foreach (int i in chain.Indices) Emit($"VISIT {chain.Names[i]} {visits[i]}");
        }

        public void Execute(string line)
        {
            var words = line.Split(' ');
            try
            {
                string command = words[0], name = words[1];
                if (command == "CHAIN") { Create(words); return; }
                if (command == "BUILD") { Build(words); return; }
                if (command == "GAMBLER") { Gambler(words); return; }
                if (!chains.TryGetValue(name, out var chain)) throw new CommandError($"UNKNOWN CHAIN {name}");
                if (command is not ("P" or "ROW" or "SHOW" or "CHECK")) chain.CheckStochastic();
                switch (command)
                {
                    case "P":
                    {
                        int from = chain.State(words[2]), to = chain.State(words[3]);
                        var value = Probability(words[4]);
                        chain.P[from][to] = value;
                        Emit($"P {name} {words[2]} {words[3]} {value} rowsum={Sum(chain.P[from])}");
                        break;
                    }
                    case "ROW":
                    {
                        int state = chain.State(words[2]);
                        if (words.Length - 3 != chain.Size) throw new CommandError("BAD LENGTH");
                        var row = words[3..].Select(Probability).ToArray();
                        chain.P[state] = row;
                        Emit($"ROW {name} {words[2]} rowsum={Sum(row)}");
                        break;
                    }
                    case "SHOW":
                        Emit($"MATRIX {name} states={chain.Size}");
                        Display(chain);
                        break;
                    case "CHECK":
                    {
                        var sums = chain.P.Select(Sum).ToArray();
                        int[] bad = chain.Indices.Where(i => sums[i] != Fraction.One).ToArray();
                        Emit($"CHECK {name} {(bad.Length == 0 ? "ok" : $"bad={bad.Length}")}");
                        foreach (int i in bad) Emit($"BADROW {chain.Names[i]} sum={sums[i]}");
                        break;
                    }
                    case "CLASSES": Classes(name, chain); break;
                    case "CLASSIFY": Classify(name, chain); break;
                    case "STEP": Step(words, chain); break;
                    case "POWER":
                    {
                        int steps = int.Parse(words[2]);
                        var power = Identity(chain.Size);
                        for (int t = 0; t < steps; t++) power = Multiply(power, chain.P);
                        Emit($"POWER {name} k={steps}");
                        Display(chain, power);
                        break;
                    }
                    case "STATIONARY": Stationary(name, chain); break;
                    case "RECURRENCE": Recurrence(words, chain); break;
                    case "ABSORB": Absorb(name, chain); break;
                    case "HITTING": Hitting(words, chain); break;
                    case "PASSAGE": Passage(name, chain); break;
                    case "FIRSTPASSAGE": FirstPassage(words, chain); break;
                    case "PATHPROB": PathProbability(words, chain); break;
                    case "MOSTLIKELY": MostLikely(words, chain); break;
                    case "REVERSIBLE": Reversible(name, chain); break;
                    case "REVERSE": Reverse(words, chain); break;
                    case "MIXING": Mixing(words, chain); break;
                    case "LUMP": Lump(words, chain); break;
                    case "REWARD": Reward(words, chain); break;
                    case "RESTRICT": Restrict(words, chain); break;
                    case "SIMULATE": Simulate(words, chain); break;
                }
            }
            catch (CommandError error)
            {
                Emit($"ERROR {error.Message}");
            }
        }
    }

    static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        int count = int.Parse(Console.ReadLine()!);
        var analyzer = new Analyzer();
        for (int i = 0; i < count; i++) analyzer.Execute(Console.ReadLine()!);
        Console.Write(analyzer);
    }
}
