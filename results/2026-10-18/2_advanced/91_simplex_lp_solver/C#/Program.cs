using System;
using System.IO;
using System.Globalization;
using System.Collections.Generic;
using System.Linq;
sealed record Bound(F? Lower, F? Upper);
sealed record Model(string Name, bool Maximize, List<string> Names, List<F> C, List<List<F>> A, List<F> Rhs, List<string> Comparisons, List<string> RowNames, List<Bound> Bounds, List<bool> Integer);
sealed record Substitution(string Kind, F Offset, List<(int Column, F Direction)> Columns);
sealed record Standard(List<string> Columns, List<string> Rows, List<F> Signs, List<int> Initial, List<int?> Slacks, HashSet<int> Artificial, List<F> Phase1, List<F> Phase2, F Constant, F Sign, List<Substitution> Substitutions, List<int?> UpperRows);
sealed record LPResult(Standard Standard, Tableau Tableau, string Status, F Value, List<F> Solution, int Phase1, int Phase2, int Drives, F Infeasibility, List<F> Multipliers, List<F> Ray, F Rate) {
    public int Pivots => Phase1 + Phase2 + Drives;
}
static class Program {
    static Model Content(Parsed parsed) {
        if (parsed.Error != null) throw parsed.Error;
        List<string> names = new();
        foreach (List<Term> terms in new[] {
            parsed.Objective
        }.Concat(parsed.Constraints.Select(c => c.Terms))) foreach (Term term in terms) if (!names.Contains(term.Name)) names.Add(term.Name);
        List<F> Coefficients(List<Term> terms) => names.Select(name => terms.Where(term => term.Name == name).Select(term => term.Coefficient).SumF()).ToList();
        List<Bound> bounds = names.Select(_ => new Bound(0, null)).ToList();
        List<bool> integer = names.Select(_ => false).ToList();
        HashSet<string> seen = new();
        foreach (Constraint constraint in parsed.Constraints) if (!seen.Add(constraint.Name)) throw new ModelError(constraint.Line, "duplicate constraint " + constraint.Name);
        int Index(string name, int line) {
            int j = names.IndexOf(name);
            if (j < 0) throw new ModelError(line, "unknown variable " + name);
            return j;
        }
        void Check(int j, int line) {
            Bound bound = bounds[j];
            if (bound.Lower.HasValue && bound.Upper.HasValue && bound.Lower.Value > bound.Upper.Value) throw new ModelError(line, "inconsistent bounds " + names[j]);
        }
        foreach (BoundLine line in parsed.Bounds) {
            int j = Index(line.Name, line.Line);
            Bound old = bounds[j];
            bounds[j] = new(line.Kind == "upper" ? old.Lower : line.Lower, line.Kind == "lower" ? old.Upper : line.Upper);
            Check(j, line.Line);
        }
        foreach (Declaration line in parsed.Integers) foreach (string name in line.Names) {
            int j = Index(name, line.Line);
            integer[j] = true;
            F? lower = bounds[j].Lower, upper = bounds[j].Upper;
            bounds[j] = new(lower.HasValue ? new F(lower.Value.Ceil()) : null, upper.HasValue ? new F(upper.Value.Floor()) : null);
            Check(j, line.Line);
        }
        foreach (Declaration line in parsed.Binaries) foreach (string name in line.Names) {
            int j = Index(name, line.Line);
            integer[j] = true;
            bounds[j] = new(0, 1);
        }
        return new(parsed.Name, parsed.Maximize, names, Coefficients(parsed.Objective), parsed.Constraints.Select(c => Coefficients(c.Terms)).ToList(), parsed.Constraints.Select(c => c.Rhs).ToList(), parsed.Constraints.Select(c => c.Comparison).ToList(), parsed.Constraints.Select(c => c.Name).ToList(), bounds, integer);
    }
    static (Standard Standard, Tableau Tableau) Standardize(Model model, List<Bound> bounds) {
        List<string> columns = new();
        List<Substitution> substitutions = new();
        List<F> costs = new();
        for (int j = 0; j < model.Names.Count; j++) {
            Bound bound = bounds[j];
            List<(int, F)> parts = new();
            string kind;
            F offset;
            if (bound.Lower.HasValue) {
                parts.Add((columns.Count, 1));
                columns.Add(model.Names[j]);
                costs.Add(model.C[j]);
                kind = "shift";
                offset = bound.Lower.Value;
            }
            else if (bound.Upper.HasValue) {
                parts.Add((columns.Count, -1));
                columns.Add(model.Names[j] + "'");
                costs.Add(-model.C[j]);
                kind = "reflect";
                offset = bound.Upper.Value;
            }
            else {
                parts.Add((columns.Count, 1));
                columns.Add(model.Names[j] + "+");
                costs.Add(model.C[j]);
                parts.Add((columns.Count, -1));
                columns.Add(model.Names[j] + "-");
                costs.Add(-model.C[j]);
                kind = "split";
                offset = 0;
            }
            substitutions.Add(new(kind, offset, parts));
        }
        int variableColumns = columns.Count;
        List<string> rows = new(model.RowNames), comparisons = new(model.Comparisons);
        List<List<F>> coefficients = new();
        List<F> beta = new();
        for (int i = 0; i < model.A.Count; i++) {
            List<F> row = Enumerable.Repeat((F)0, variableColumns).ToList();
            F rhs = model.Rhs[i];
            for (int j = 0; j < model.Names.Count; j++) {
                rhs -= model.A[i][j] * substitutions[j].Offset;
                foreach (var (k, direction) in substitutions[j].Columns) row[k] = direction * model.A[i][j];
            } coefficients.Add(row);
            beta.Add(rhs);
        }
        List<int?> upperRows = Enumerable.Repeat<int?>(null, model.Names.Count).ToList();
        for (int j = 0; j < model.Names.Count; j++) if (substitutions[j].Kind == "shift" && bounds[j].Upper.HasValue) {
            upperRows[j] = rows.Count;
            rows.Add(model.Names[j] + ".ub");
            comparisons.Add("<=");
            List<F> row = Enumerable.Repeat((F)0, variableColumns).ToList();
            row[substitutions[j].Columns[0].Column] = 1;
            coefficients.Add(row);
            beta.Add(bounds[j].Upper!.Value - substitutions[j].Offset);
        }
        List<F> signs = Enumerable.Repeat((F)1, rows.Count).ToList();
        for (int i = 0; i < rows.Count; i++) if (beta[i] < 0) {
            signs[i] = -1;
            beta[i] = -beta[i];
            coefficients[i] = coefficients[i].Select(value => -value).ToList();
            comparisons[i] = comparisons[i] switch {
                "<=" => ">=", ">=" => "<=", _ => "="
            };
        }
        List<int> initial = Enumerable.Repeat(-1, rows.Count).ToList();
        List<int?> slacks = Enumerable.Repeat<int?>(null, rows.Count).ToList();
        for (int i = 0; i < rows.Count; i++) if (comparisons[i] != "=") {
            int k = columns.Count;
            columns.Add("s:" + rows[i]);
            costs.Add(0);
            foreach (List<F> row in coefficients) row.Add(0);
            coefficients[i][k] = comparisons[i] == "<=" ? 1 : -1;
            slacks[i] = k;
            if (comparisons[i] == "<=") initial[i] = k;
        }
        HashSet<int> artificial = new();
        for (int i = 0; i < rows.Count; i++) if (comparisons[i] != "<=") {
            int k = columns.Count;
            columns.Add("a:" + rows[i]);
            costs.Add(0);
            foreach (List<F> row in coefficients) row.Add(0);
            coefficients[i][k] = 1;
            initial[i] = k;
            artificial.Add(k);
        }
        F sign = model.Maximize ? -1 : 1, constant = Enumerable.Range(0, model.Names.Count).Select(j => model.C[j] * substitutions[j].Offset).SumF();
        Standard standard = new(columns, rows, signs, new(initial), slacks, artificial, Enumerable.Range(0, columns.Count).Select(k => (F)(artificial.Contains(k) ? 1 : 0)).ToList(), costs.Select(value => sign * value).ToList(), constant, sign, substitutions, upperRows);
        return (standard, new(coefficients, beta, initial));
    }
    static List<F> Recover(Standard s, List<F> columns, bool offset) => s.Substitutions.Select(v => v.Columns.Select(part => part.Direction * columns[part.Column]).SumF() + (offset ? v.Offset : (F)0)).ToList();
    public static LPResult SolveLP(Model model, List<Bound> bounds, int node, int level, List<string> log) {
        var (s, t) = Standardize(model, bounds);
        log.Add($"SOLVE node {node} rows {s.Rows.Count} columns {s.Columns.Count} artificials {s.Artificial.Count}");
        if (level >= 1) {
            for (int j = 0; j < s.Substitutions.Count; j++) {
                Substitution value = s.Substitutions[j];
                string line = $"MAP {model.Names[j]} {value.Kind}";
                if (value.Kind != "split") {
                    line += " " + value.Offset;
                    if (value.Kind == "shift" && bounds[j].Upper.HasValue) line += " upper " + bounds[j].Upper;
                } log.Add(line);
            }
            for (int i = 0; i < s.Signs.Count; i++) if (s.Signs[i] < 0) log.Add("FLIP " + s.Rows[i]);
        }
        int phase1 = 0, phase2 = 0, drives = 0, redundant = 0;
        string status = "OPTIMAL";
        F infeasibility = 0;
        int? unbounded = null;
        if (s.Artificial.Count > 0) {
            if (level >= 1) log.Add("PHASE 1");
            if (level >= 2) log.AddRange(t.Display("phase 1 start", s.Columns, s.Rows, s.Phase1, 0, 1));
            phase1 = Simplex.Phase(t, s.Phase1, Enumerable.Range(0, s.Columns.Count).ToList(), s.Columns, s.Rows, 0, 1, level, log).Count;
            infeasibility = t.Value(s.Phase1);
            if (level >= 1) log.Add($"PHASE 1 END objective {infeasibility} iterations {phase1}");
            if (infeasibility > 0) {
                status = "INFEASIBLE";
                if (level >= 2) log.AddRange(t.Display("final", s.Columns, s.Rows, s.Phase1, 0, 1));
            }
            else for (int i = 0; i < s.Rows.Count; i++) if (s.Artificial.Contains(t.Basis[i])) {
                int? k = Enumerable.Range(0, s.Columns.Count).Where(column => !s.Artificial.Contains(column) && t.T[i][column] != 0).Select(column => (int?)column).FirstOrDefault();
                if (k.HasValue) {
                    if (level >= 1) log.Add($"DRIVE row {s.Rows[i]} enter {s.Columns[k.Value]} leave {s.Columns[t.Basis[i]]}");
                    t.Pivot(i, k.Value);
                    drives++;
                }
                else {
                    redundant++;
                    if (level >= 1) log.Add("REDUNDANT row " + s.Rows[i]);
                }
            }
        }
        if (status != "INFEASIBLE") {
            if (level >= 1) log.Add("PHASE 2");
            if (level >= 2) log.AddRange(t.Display("phase 2 start", s.Columns, s.Rows, s.Phase2, s.Constant, s.Sign));
            (phase2, unbounded) = Simplex.Phase(t, s.Phase2, Enumerable.Range(0, s.Columns.Count).Where(k => !s.Artificial.Contains(k)).ToList(), s.Columns, s.Rows, s.Constant, s.Sign, level, log);
            if (unbounded.HasValue) {
                status = "UNBOUNDED";
                if (level >= 1) log.Add("UNBOUNDED enter " + s.Columns[unbounded.Value]);
            }
            if (level >= 1) log.Add($"PHASE 2 END objective {s.Constant + s.Sign * t.Value(s.Phase2)} iterations {phase2}");
            if (level >= 2) log.AddRange(t.Display("final", s.Columns, s.Rows, s.Phase2, s.Constant, s.Sign));
        }
        F value = s.Constant + s.Sign * t.Value(s.Phase2);
        List<F> columns = Enumerable.Repeat((F)0, s.Columns.Count).ToList();
        for (int i = 0; i < s.Rows.Count; i++) columns[t.Basis[i]] = t.Beta[i];
        List<F> solution = Recover(s, columns, true), reduced = t.Reduced(s.Phase1);
        List<F> multipliers = status == "INFEASIBLE" ? s.Initial.Select((k, i) => s.Signs[i] * (s.Phase1[k] - reduced[k])).ToList() : new();
        List<F> ray = new();
        F rate = 0;
        if (unbounded.HasValue) {
            int q = unbounded.Value;
            List<F> direction = Enumerable.Repeat((F)0, s.Columns.Count).ToList();
            direction[q] = 1;
            for (int i = 0; i < s.Rows.Count; i++) direction[t.Basis[i]] = -t.T[i][q];
            ray = Recover(s, direction, false);
            rate = Enumerable.Range(0, model.C.Count).Select(j => model.C[j] * ray[j]).SumF();
        }
        log.Add($"RESULT {status} objective {(status == "OPTIMAL" ? value.ToString() : "-")} phase1 {phase1} phase2 {phase2} drives {drives} redundant {redundant}");
        return new(s, t, status, value, solution, phase1, phase2, drives, infeasibility, multipliers, ray, rate);
    }
    static (string Lower, string Upper) Interval(F origin, F? lower, F? upper) => (lower.HasValue ? (origin + lower.Value).ToString() : "-inf", upper.HasValue ? (origin + upper.Value).ToString() : "inf");
    static List<string> Sensitivity(Model model, LPResult result) {
        Standard s = result.Standard;
        Tableau t = result.Tableau;
        List<F> reducedColumns = t.Reduced(s.Phase2);
        HashSet<int> basic = new(t.Basis);
        List<int> nonbasic = Enumerable.Range(0, s.Columns.Count).Where(k => !basic.Contains(k) && !s.Artificial.Contains(k)).ToList();
        List<F> prices = Enumerable.Range(0, model.A.Count).Select(i => -s.Sign * s.Signs[i] * reducedColumns[s.Initial[i]]).ToList();
        List<F> reduced = Enumerable.Range(0, model.Names.Count).Select(j => model.C[j] - Enumerable.Range(0, model.A.Count).Select(i => prices[i] * model.A[i][j]).SumF()).ToList();
        F objective = Enumerable.Range(0, model.A.Count).Select(i => prices[i] * model.Rhs[i]).SumF() + Enumerable.Range(0, model.Names.Count).Select(j => reduced[j] * result.Solution[j]).SumF();
        List<string> lines = new() {
            $"MODEL {model.Name} {(model.Integer.Any(v => v) ? "relaxation" : "lp")} objective {result.Value}", "BASIS " + string.Join(" ", t.Basis.Select(k => s.Columns[k])), $"DEGENERACY primal {Enumerable.Range(0, s.Rows.Count).Count(i => !s.Artificial.Contains(t.Basis[i]) && t.Beta[i] == 0)} dual {nonbasic.Count(k => reducedColumns[k] == 0)}", $"DUAL objective {objective}"
        };
        for (int i = 0; i < model.A.Count; i++) {
            List<F> rho = Enumerable.Range(0, s.Rows.Count).Select(row => s.Signs[i] * t.T[row][s.Initial[i]]).ToList();
            F? lower = null, upper = null;
            bool fixedRange = Enumerable.Range(0, s.Rows.Count).Any(row => rho[row] != 0 && s.Artificial.Contains(t.Basis[row]));
            (string Lower, string Upper) ends;
            if (fixedRange) ends = (model.Rhs[i].ToString(), model.Rhs[i].ToString());
            else {
                for (int row = 0; row < s.Rows.Count; row++) {
                    if (rho[row] > 0) {
                        F value = -t.Beta[row] / rho[row];
                        if (!lower.HasValue || value > lower.Value) lower = value;
                    } else if (rho[row] < 0) {
                        F value = -t.Beta[row] / rho[row];
                        if (!upper.HasValue || value < upper.Value) upper = value;
                    }
                } ends = Interval(model.Rhs[i], lower, upper);
            }
            lines.Add($"CONSTRAINT {model.RowNames[i]} price {prices[i]} rhs {model.Rhs[i]} range {ends.Lower} {ends.Upper}");
        }
        for (int j = 0; j < model.Names.Count; j++) {
            Substitution variable = s.Substitutions[j];
            string status;
            if (variable.Kind == "split") status = variable.Columns.All(part => !basic.Contains(part.Column)) ? "zero" : "basic";
            else if (!basic.Contains(variable.Columns[0].Column)) status = variable.Kind == "shift" ? "lower" : "upper";
            else if (variable.Kind == "shift" && s.UpperRows[j].HasValue && !basic.Contains(s.Slacks[s.UpperRows[j]!.Value]!.Value)) status = "upper";
            else status = "basic";
            List<F> h = Enumerable.Repeat((F)0, s.Columns.Count).ToList();
            foreach (var (k, direction) in variable.Columns) h[k] = s.Sign * direction;
            List<F> eta = t.Reduced(h);
            F? lower = null, upper = null;
            foreach (int k in nonbasic) {
                if (eta[k] > 0) {
                    F value = -reducedColumns[k] / eta[k];
                    if (!lower.HasValue || value > lower.Value) lower = value;
                } else if (eta[k] < 0) {
                    F value = -reducedColumns[k] / eta[k];
                    if (!upper.HasValue || value < upper.Value) upper = value;
                }
            }
            var ends = Interval(model.C[j], lower, upper);
            lines.Add($"VARIABLE {model.Names[j]} {status} value {result.Solution[j]} reduced {reduced[j]} cost {model.C[j]} range {ends.Lower} {ends.Upper}");
        }
        return lines;
    }
    static string Statistics(Model model) {
        List<F> matrix = model.A.SelectMany(row => row).Where(v => v != 0).Select(v => v.Absolute).ToList(), objective = model.C.Where(v => v != 0).Select(v => v.Absolute).ToList(), rhs = model.Rhs.Where(v => v != 0).Select(v => v.Absolute).ToList(), bounds = model.Bounds.SelectMany(b => new[] {
            b.Lower, b.Upper
        }).Where(v => v.HasValue && v.Value != 0).Select(v => v!.Value.Absolute).ToList();
        string Range(List<F> values) => values.Count == 0 ? "- -" : $"{values.Min()} {values.Max()}";
        return $"STATS nonzeros {matrix.Count} matrix {Range(matrix)} objective {Range(objective)} rhs {Range(rhs)} bounds {Range(bounds)}";
    }
    static void Write(string name, List<string> lines) {
        Directory.CreateDirectory("output");
        File.WriteAllText("output/" + name, lines.Count == 0 ? "" : string.Join("\n", lines) + "\n");
    }
    static void Main() {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        CultureInfo.CurrentUICulture = CultureInfo.InvariantCulture;
        List<Parsed> blocks = LPParser.Read();
        Params parameters = LPParser.Settings();
        List<string> iterations = new(), solutions = new(), sensitivity = new(), tree = new(), csv = new() {
            "model,status,objective,approx,relaxation,nodes,pivots"
        };
        int[] statuses = new int[5], totals = new int[4];
        int analyzed = 0, integerModels = 0, integerNodes = 0, limits = 0;
        foreach (Parsed block in blocks) {
            Model model;
            try {
                model = Content(block);
            } catch (ModelError error) {
                statuses[4]++;
                iterations.Add("MODEL " + block.Name + " error");
                solutions.AddRange(new[] {
                    "MODEL " + block.Name, $"STATUS ERROR line {error.Line} {error.Reason}"
                });
                sensitivity.Add("MODEL " + block.Name + " skipped ERROR");
                csv.Add(block.Name + ",ERROR,-,-,-,0,0");
                continue;
            }
            bool integer = model.Integer.Any(v => v);
            int level = parameters.Levels.GetValueOrDefault(model.Name, parameters.Level), limit = parameters.Limits.GetValueOrDefault(model.Name, parameters.Limit);
            iterations.Add($"MODEL {model.Name} level {level}");
            Outcome outcome;
            if (integer) outcome = BranchBound.Solve(model, limit, level, iterations);
            else {
                LPResult relaxation = SolveLP(model, model.Bounds, 1, level, iterations);
                outcome = new(relaxation.Status, relaxation, relaxation.Status == "OPTIMAL" ? relaxation.Solution : null, relaxation.Status == "OPTIMAL" ? relaxation.Value : null, 1, relaxation.Phase1, relaxation.Phase2, relaxation.Drives, new());
            }
            LPResult root = outcome.Root;
            string status = outcome.Status;
            statuses[Array.IndexOf(new[] {
                "OPTIMAL", "INFEASIBLE", "UNBOUNDED", "NODE_LIMIT"
            }, status)]++;
            totals[0] += outcome.Nodes;
            totals[1] += outcome.Phase1;
            totals[2] += outcome.Phase2;
            totals[3] += outcome.Drives;
            if (integer) {
                integerModels++;
                integerNodes += outcome.Nodes;
                if (status == "NODE_LIMIT") limits++;
                tree.AddRange(outcome.Lines);
            }
            solutions.AddRange(new[] {
                $"MODEL {model.Name} {(model.Maximize ? "maximize" : "minimize")} variables {model.Names.Count} constraints {model.A.Count} integers {model.Integer.Count(v => v)}", Statistics(model), "STATUS " + status
            });
            if (outcome.Objective.HasValue) solutions.Add($"OBJECTIVE {outcome.Objective} approx {outcome.Objective.Value.Approximate}");
            if (integer && root.Status == "OPTIMAL") solutions.Add($"RELAXATION {root.Value} approx {root.Value.Approximate}");
            if (root.Status == "INFEASIBLE") {
                solutions.Add("INFEASIBILITY " + root.Infeasibility);
                for (int i = 0; i < root.Multipliers.Count; i++) solutions.Add($"FARKAS {root.Standard.Rows[i]} {root.Multipliers[i]}");
            }
            if (outcome.Solution != null || status == "UNBOUNDED") {
                List<F> values = outcome.Solution ?? root.Solution;
                for (int j = 0; j < values.Count; j++) solutions.Add($"VALUE {model.Names[j]} {values[j]}");
            }
            if (status == "UNBOUNDED") {
                for (int j = 0; j < root.Ray.Count; j++) solutions.Add($"RAY {model.Names[j]} {root.Ray[j]}");
                solutions.Add("RATE " + root.Rate);
            }
            if (outcome.Solution != null) for (int i = 0; i < model.A.Count; i++) {
                F value = Enumerable.Range(0, model.Names.Count).Select(j => model.A[i][j] * outcome.Solution[j]).SumF(), margin = model.Comparisons[i] == "<=" ? model.Rhs[i] - value : value - model.Rhs[i];
                solutions.Add($"ROW {model.RowNames[i]} {value} {margin}");
            }
            if (integer) solutions.Add("NODES " + outcome.Nodes);
            solutions.Add("PIVOTS " + outcome.Pivots);
            if (root.Status == "OPTIMAL") {
                analyzed++;
                sensitivity.AddRange(Sensitivity(model, root));
            } else sensitivity.Add($"MODEL {model.Name} skipped {root.Status}");
            csv.Add($"{model.Name},{status},{outcome.Objective?.ToString() ?? "-"},{outcome.Objective?.Approximate ?? "-"},{(root.Status == "OPTIMAL" ? root.Value.ToString() : "-")},{outcome.Nodes},{outcome.Pivots}");
        }
        iterations.Add($"TOTAL solves {totals[0]} phase1 {totals[1]} phase2 {totals[2]} drives {totals[3]} pivots {totals[1] + totals[2] + totals[3]}");
        solutions.Add($"SUMMARY models {blocks.Count} optimal {statuses[0]} infeasible {statuses[1]} unbounded {statuses[2]} node_limit {statuses[3]} error {statuses[4]}");
        sensitivity.Add($"SUMMARY analyzed {analyzed} skipped {blocks.Count - analyzed}");
        tree.Add($"SUMMARY models {integerModels} nodes {integerNodes} node_limit {limits}");
        Write("iterations.txt", iterations);
        Write("solutions.txt", solutions);
        Write("sensitivity.txt", sensitivity);
        Write("bnb_tree.txt", tree);
        Write("summary.csv", csv);
    }
}
