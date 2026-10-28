using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Formula {
    public record Factor(string name, string column, int power, bool categorical) {
    }
    public static Factor ParseFactor(string name) {
        if (name.StartsWith("C("))
            return new Factor(name, name.Substring(2, name.Length - 1 - (2)), 1, true);
        if (name.StartsWith("I(")) {
            int caret = name.IndexOf('^');
            return new Factor(name, name.Substring(2, caret - (2)),
                              int.Parse(name.Substring(caret + 1, caret + 2 - (caret + 1))), false);
        }
        return new Factor(name, name, 1, false);
    }
    public sealed class Term {
        public string name;
        public List<Factor> factors;
        public HashSet<string> names = new();
        public Term(List<string> words) {
            factors = new();
            foreach (string word in words) {
                factors.Add(ParseFactor(word));
                names.Add(word);
            }
            name = string.Join(":", words);
        }
    }
    public static bool Contained(Term a, Term b) {
        return a.names.Count < b.names.Count && b.names.IsSupersetOf(a.names);
    }
    public sealed class Model {
        public string response, weight, original;
        public List<Term> terms = new();
        public HashSet<string> variables = new();
        public HashSet<string> factorColumns = new();
    }
    public static void Add(Model model, List<string> factors) {
        Term term = new Term(factors);
        foreach (Term old in model.terms)
            if (old.names.SetEquals(term.names))
                return;
        model.terms.Add(term);
    }
    public static Model Parse(string line) {
        Model model = new Model();
        int weighted = line.IndexOf(" weights=");
        model.original = weighted < 0 ? line : line.Substring(0, weighted - (0));
        model.weight = weighted < 0 ? null : line.Substring(weighted + 9);
        int split = model.original.IndexOf(" ~ ");
        model.response = model.original.Substring(0, split - (0));
        foreach (string expression in model.original.Substring(split + 3).Split(" + ",
                                                                                StringSplitOptions.None)) {
            if (!expression.Contains("*"))
                Add(model, expression.Split(':').ToList());
            else {
                List<string> factors = expression.Split('*').ToList();
                for (int size = 1; size <= factors.Count; size++)
                    for (int mask = 1; mask < (1 << factors.Count); mask++)
                        if (System.Numerics.BitOperations.PopCount((uint)mask) == size) {
                            List<string> selected = new();
                            for (int i = 0; i < factors.Count; i++)
                                if ((mask & (1 << i)) != 0)
                                    selected.Add(factors[i]);
                            Add(model, selected);
                        }
            }
        }
        foreach (Term term in model.terms)
            foreach (Factor factor in term.factors)
                model.factorColumns.Add(factor.column);
        model.variables.UnionWith(model.factorColumns);
        model.variables.Add(model.response);
        if (model.weight != null)
            model.variables.Add(model.weight);
        return model;
    }
    public record Component(Factor factor, string name, string level) {
        public double Value(Dataframe.Row row) {
            if (factor.categorical)
                return row.values[factor.column].Equals(level) ? 1 : 0;
            double v = row.Numeric(factor.column);
            return factor.power == 1 ? v : factor.power == 2 ? v * v : v * v * v;
        }
    }
    public sealed class Column {
        public string name;
        public int term;
        public List<Component> components;
        public Column(string name, int term, List<Component> components) {
            this.name = name;
            this.term = term;
            this.components = components;
        }
        public double Value(Dataframe.Row row) {
            double product = 1;
            foreach (Component component in components)
                product *= component.Value(row);
            return product;
        }
    }
    public sealed class Design {
        public Model model;
        public List<Dataframe.Row> rows = new();
        public Dictionary<string, List<string>> levels = new();
        public List<Column> columns = new();
        public double[] y, w;
        public Design(Model model, Dataframe.Frame frame) {
            this.model = model;
            foreach (Dataframe.Row row in frame.rows) {
                bool valid = true;
                foreach (string column in model.variables)
                    if (row.values[column] == null)
                        valid = false;
                if (valid)
                    rows.Add(row);
            }
            foreach (Term term in model.terms)
                foreach (Factor factor in term.factors)
                    if (factor.categorical && !levels.ContainsKey(factor.column)) {
                        SortedSet<string> values = new(StringComparer.Ordinal);
                        foreach (Dataframe.Row row in rows)
                            values.Add(row.values[factor.column]);
                        levels[factor.column] = new(values);
                    }
            columns.Add(new Column("(Intercept)", -1, new()));
            for (int t = 0; t < model.terms.Count; t++) {
                Term term = model.terms[t];
                List<List<Component>> choices = new();
                int count = 1;
                foreach (Factor factor in term.factors) {
                    List<Component> components = new();
                    if (factor.categorical) {
                        List<string> values = levels[factor.column];
                        for (int i = 1; i < values.Count; i++)
                            components.Add(new Component(factor, factor.name + values[i], values[i]));
                    } else
                        components.Add(new Component(factor, factor.name, null));
                    choices.Add(components);
                    count *= components.Count;
                }
                for (int ordinal = 0; ordinal < count; ordinal++) {
                    int rest = ordinal;
                    List<Component> components = new();
                    List<string> names = new();
                    foreach (List<Component> list in choices) {
                        Component component = list[rest % list.Count];
                        rest /= list.Count;
                        components.Add(component);
                        names.Add(component.name);
                    }
                    columns.Add(new Column(string.Join(":", names), t, components));
                }
            }
            y = new double[rows.Count];
            w = new double[rows.Count];
            for (int i = 0; i < rows.Count; i++) {
                y[i] = rows[i].Numeric(model.response);
                w[i] = model.weight == null ? 1 : rows[i].Numeric(model.weight);
            }
        }
        public int[] Indices(int mask) {
            List<int> result = new();
            for (int j = 0; j < columns.Count; j++)
                if (columns[j].term < 0 || (mask & (1 << columns[j].term)) != 0)
                    result.Add(j);
            int[] indices = new int[result.Count];
            for (int i = 0; i < indices.Length; i++)
                indices[i] = result[i];
            return indices;
        }
        public double[][] Matrix(int[] indices) {
            double[][] result = Enumerable.Range(0, rows.Count)
                                    .Select(
                                        _ => new double[indices.Length])
                                    .ToArray();
            for (int i = 0; i < rows.Count; i++)
                for (int j = 0; j < indices.Length; j++)
                    result[i][j] = columns[indices[j]].Value(rows[i]);
            return result;
        }
        public bool Predictable(Dataframe.Row row) {
            foreach (string name in model.factorColumns) {
                string value = row.values[name];
                if (value == null || (levels.ContainsKey(name) && !levels[name].Contains(value)))
                    return false;
            }
            return true;
        }
        public double[] Vector(Dataframe.Row row) {
            double[] result = new double[columns.Count];
            for (int j = 0; j < result.Length; j++)
                result[j] = columns[j].Value(row);
            return result;
        }
    }
    public static string Display(Model model, int mask) {
        List<string> terms = new();
        for (int t = 0; t < model.terms.Count; t++)
            if ((mask & (1 << t)) != 0)
                terms.Add(model.terms[t].name);
        return model.response + " ~ " + (terms.Count == 0 ? "1" : string.Join(" + ", terms));
    }
    public static bool Removable(Model model, int mask, int term) {
        if ((mask & (1 << term)) == 0)
            return false;
        for (int t = 0; t < model.terms.Count; t++)
            if ((mask & (1 << t)) != 0 && Contained(model.terms[term], model.terms[t]))
                return false;
        return true;
    }
    public static bool Hierarchical(Model model, int mask) {
        for (int t = 0; t < model.terms.Count; t++)
            if ((mask & (1 << t)) != 0)
                for (int a = 0; a < model.terms.Count; a++)
                    if (Contained(model.terms[a], model.terms[t]) && (mask & (1 << a)) == 0)
                        return false;
        return true;
    }
}
