using System;
using System.Collections.Generic;
using System.Linq;
public static class Factors {
    public static int Entries(List<int> variables, int[] sizes) {
        int count = 1;
        foreach (int variable in variables)
            count *= sizes[variable];
        return count;
    }
    public static int[] Assignment(int index, List<int> variables, int[] sizes) {
        int[] states = new int[sizes.Length];
        for (int i = variables.Count - 1; i >= 0; i--) {
            int v = variables[i];
            states[v] = index % sizes[v];
            index /= sizes[v];
        }
        return states;
    }
    public sealed class Factor {
        public List<int> variables;
        public double[] values;
        public int[] sizes;
        public Factor(List<int> variables, double[] values, int[] sizes) {
            this.variables = variables.ToList();
            this.values = values;
            this.sizes = sizes;
        }
        public double
        Value(int[] assignment) => values[Learning.ParentRow(variables, assignment, sizes)];
        public Factor Reduced(int[] evidence) {
            List<int> remaining = variables.Where(v => evidence[v] < 0).ToList();
            double[] result = new double[Entries(remaining, sizes)];
            for (int i = 0; i < result.Length; i++) {
                int[] assignment = Assignment(i, remaining, sizes);
                for (int v = 0; v < sizes.Length; v++)
                    if (evidence[v] >= 0)
                        assignment[v] = evidence[v];
                result[i] = Value(assignment);
            }
            return new(remaining, result, sizes);
        }
        public Factor Multiplied(Factor other) {
            List<int> variables = this.variables.Union(other.variables).Order().ToList();
            double[] result = new double[Entries(variables, sizes)];
            for (int i = 0; i < result.Length; i++) {
                int[] assignment = Assignment(i, variables, sizes);
                result[i] = Value(assignment) * other.Value(assignment);
            }
            return new(variables, result, sizes);
        }
        public Factor Eliminate(int variable, bool maximize) {
            List<int> remaining = variables.Where(v => v != variable).ToList();
            double[] result = new double[Entries(remaining, sizes)];
            for (int i = 0; i < result.Length; i++) {
                int[] assignment = Assignment(i, remaining, sizes);
                double value = maximize ? -1 : 0;
                for (int state = 0; state < sizes[variable]; state++) {
                    assignment[variable] = state;
                    double candidate = Value(assignment);
                    value = maximize ? Math.Max(value, candidate) : value + candidate;
                }
                result[i] = value;
            }
            return new(remaining, result, sizes);
        }
    }
    public static Factor Cpt(int variable, List<int> parents, double[][] cpt, int[] sizes) {
        List<int> variables = parents.Append(variable).Distinct().Order().ToList();
        double[] values = new double[Entries(variables, sizes)];
        for (int i = 0; i < values.Length; i++) {
            int[] assignment = Assignment(i, variables, sizes);
            values[i] = cpt[Learning.ParentRow(parents, assignment, sizes)][assignment[variable]];
        }
        return new(variables, values, sizes);
    }
    public static Factor Multiply(List<Factor> factors, int[] sizes) {
        if (factors.Count == 0)
            return new(new(), new double[] { 1 }, sizes);
        Factor result = factors[0];
        for (int i = 1; i < factors.Count; i++)
            result = result.Multiplied(factors[i]);
        return result;
    }
}
