using System;
using System.Collections.Generic;
public static class Postprocess {
    public record Result(string name, double[] displacement, double[] forces, double[] reactions,
                         double[] external);
    public static double[] Forces(List<Assembly.Geometry> geometry,
                                  List<Assembly.Properties> properties, double[] displacement,
                                  double[] temperature, int removed) {
        double[] forces = new double[geometry.Count];
        for (int m = 0; m < geometry.Count; m++)
            if (m != removed) {
                Assembly.Geometry g = geometry[m];
                int[] a = g.dofs;
                double extension = (displacement[a[2]] - displacement[a[0]]) * g.cosine +
                                   (displacement[a[3]] - displacement[a[1]]) * g.sine;
                forces[m] = properties[m].stiffness * extension - temperature[m];
            }
        return forces;
    }
    public static double[] Reactions(double[][] matrix, double[] displacement, double[] force,
                                     int[] restrained) {
        double[] result = new double[force.Length];
        foreach (int row in restrained) {
            double value = 0;
            for (int d = 0; d < force.Length; d++)
                value += matrix[row][d] * displacement[d];
            result[row] = value - force[row];
        }
        return result;
    }
    public static double[][] Vectors(Result result) => new[] { result.displacement, result.forces,
                                                               result.reactions, result.external };
    public static Result Superpose(ModelIo.Combination combination,
                                   Dictionary<string, Result> results) {
        ModelIo.Term first = combination.terms[0];
        double[][] source = Vectors(results[first.name]), values = new double [4][];
        for (int v = 0; v < 4; v++) {
            values[v] = new double[source[v].Length];
            for (int i = 0; i < values[v].Length; i++)
                values[v][i] = first.factor * source[v][i];
        }
        for (int t = 1; t < combination.terms.Count; t++) {
            ModelIo.Term term = combination.terms[t];
            source = Vectors(results[term.name]);
            for (int v = 0; v < 4; v++)
                for (int i = 0; i < values[v].Length; i++)
                    values[v][i] += term.factor * source[v][i];
        }
        return new(combination.name, values[0], values[1], values[2], values[3]);
    }
    public static double Equilibrium(Result result, List<Assembly.Geometry> geometry) {
        double[] residual = new double[result.external.Length];
        for (int d = 0; d < residual.Length; d++)
            residual[d] = result.external[d] + result.reactions[d];
        for (int m = 0; m < geometry.Count; m++) {
            Assembly.Geometry g = geometry[m];
            double[] direction = { g.cosine, g.sine, -g.cosine, -g.sine };
            for (int i = 0; i < 4; i++)
                residual[g.dofs[i]] += result.forces[m] * direction[i];
        }
        double maximum = 0;
        foreach (double value in residual)
            maximum = Math.Max(maximum, Math.Abs(value));
        return maximum;
    }
}
