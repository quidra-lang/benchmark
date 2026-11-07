import java.util.*;
final class Postprocess {
    record Result(String name, double[] displacement, double[] forces, double[] reactions,
                  double[] external) {}
    static double[] forces(List<Assembly.Geometry> geometry, List<Assembly.Properties> properties,
                           double[] displacement, double[] temperature, int removed) {
        double[] forces = new double[geometry.size()];
        for (int m = 0; m < geometry.size(); m++)
            if (m != removed) {
                Assembly.Geometry g = geometry.get(m);
                int[] a = g.dofs();
                double extension = (displacement[a[2]] - displacement[a[0]]) * g.cosine() +
                                   (displacement[a[3]] - displacement[a[1]]) * g.sine();
                forces[m] = properties.get(m).stiffness() * extension - temperature[m];
            }
        return forces;
    }
    static double[] reactions(double[][] matrix, double[] displacement, double[] force,
                              int[] restrained) {
        double[] result = new double[force.length];
        for (int row : restrained) {
            double value = 0;
            for (int d = 0; d < force.length; d++)
                value += matrix[row][d] * displacement[d];
            result[row] = value - force[row];
        }
        return result;
    }
    static double[][] vectors(Result result) {
        return new double[][] {result.displacement(), result.forces(), result.reactions(),
                               result.external()};
    }
    static Result superpose(ModelIo.Combination combination, Map<String, Result> results) {
        ModelIo.Term first = combination.terms().getFirst();
        double[][] source = vectors(results.get(first.name())), values = new double[4][];
        for (int v = 0; v < 4; v++) {
            values[v] = new double[source[v].length];
            for (int i = 0; i < values[v].length; i++)
                values[v][i] = first.factor() * source[v][i];
        }
        for (int t = 1; t < combination.terms().size(); t++) {
            ModelIo.Term term = combination.terms().get(t);
            source = vectors(results.get(term.name()));
            for (int v = 0; v < 4; v++)
                for (int i = 0; i < values[v].length; i++)
                    values[v][i] += term.factor() * source[v][i];
        }
        return new Result(combination.name(), values[0], values[1], values[2], values[3]);
    }
    static double equilibrium(Result result, List<Assembly.Geometry> geometry) {
        double[] residual = new double[result.external().length];
        for (int d = 0; d < residual.length; d++)
            residual[d] = result.external()[d] + result.reactions()[d];
        for (int m = 0; m < geometry.size(); m++) {
            Assembly.Geometry g = geometry.get(m);
            double[] direction = {g.cosine(), g.sine(), -g.cosine(), -g.sine()};
            for (int i = 0; i < 4; i++)
                residual[g.dofs()[i]] += result.forces()[m] * direction[i];
        }
        double maximum = 0;
        for (double value : residual)
            maximum = Math.max(maximum, Math.abs(value));
        return maximum;
    }
}
