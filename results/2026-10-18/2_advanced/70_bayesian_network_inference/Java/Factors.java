import java.util.*;
final class Factors {
    static int entries(List<Integer> variables, int[] sizes) {
        int count = 1;
        for (int variable : variables)
            count *= sizes[variable];
        return count;
    }
    static int[] assignment(int index, List<Integer> variables, int[] sizes) {
        int[] states = new int[sizes.length];
        for (int i = variables.size() - 1; i >= 0; i--) {
            int v = variables.get(i);
            states[v] = index % sizes[v];
            index /= sizes[v];
        }
        return states;
    }
    static final class Factor {
        List<Integer> variables;
        double[] values;
        int[] sizes;
        Factor(List<Integer> variables, double[] values, int[] sizes) {
            this.variables = List.copyOf(variables);
            this.values = values;
            this.sizes = sizes;
        }
        double value(int[] assignment) {
            return values[Learning.parentRow(variables, assignment, sizes)];
        }
        Factor reduced(int[] evidence) {
            List<Integer> remaining = new ArrayList<>();
            for (int v : variables)
                if (evidence[v] < 0)
                    remaining.add(v);
            double[] result = new double[entries(remaining, sizes)];
            for (int i = 0; i < result.length; i++) {
                int[] assignment = assignment(i, remaining, sizes);
                for (int v = 0; v < sizes.length; v++)
                    if (evidence[v] >= 0)
                        assignment[v] = evidence[v];
                result[i] = value(assignment);
            }
            return new Factor(remaining, result, sizes);
        }
        Factor multiplied(Factor other) {
            TreeSet<Integer> union = new TreeSet<>(variables);
            union.addAll(other.variables);
            List<Integer> variables = new ArrayList<>(union);
            double[] result = new double[entries(variables, sizes)];
            for (int i = 0; i < result.length; i++) {
                int[] assignment = assignment(i, variables, sizes);
                result[i] = value(assignment) * other.value(assignment);
            }
            return new Factor(variables, result, sizes);
        }
        Factor eliminate(int variable, boolean maximize) {
            List<Integer> remaining = new ArrayList<>(variables);
            remaining.remove(Integer.valueOf(variable));
            double[] result = new double[entries(remaining, sizes)];
            for (int i = 0; i < result.length; i++) {
                int[] assignment = assignment(i, remaining, sizes);
                double value = maximize ? -1 : 0;
                for (int state = 0; state < sizes[variable]; state++) {
                    assignment[variable] = state;
                    double candidate = value(assignment);
                    value = maximize ? Math.max(value, candidate) : value + candidate;
                }
                result[i] = value;
            }
            return new Factor(remaining, result, sizes);
        }
    }
    static Factor cpt(int variable, List<Integer> parents, double[][] cpt, int[] sizes) {
        TreeSet<Integer> set = new TreeSet<>(parents);
        set.add(variable);
        List<Integer> variables = new ArrayList<>(set);
        double[] values = new double[entries(variables, sizes)];
        for (int i = 0; i < values.length; i++) {
            int[] assignment = assignment(i, variables, sizes);
            values[i] = cpt[Learning.parentRow(parents, assignment, sizes)][assignment[variable]];
        }
        return new Factor(variables, values, sizes);
    }
    static Factor multiply(List<Factor> factors, int[] sizes) {
        if (factors.isEmpty())
            return new Factor(List.of(), new double[] {1}, sizes);
        Factor result = factors.getFirst();
        for (int i = 1; i < factors.size(); i++)
            result = result.multiplied(factors.get(i));
        return result;
    }
}
