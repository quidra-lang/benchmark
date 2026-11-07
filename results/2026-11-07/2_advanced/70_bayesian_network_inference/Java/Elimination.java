import java.util.*;
final class Elimination {
    record Step(int variable, int fill, List<Integer> scope, int size) {}
    record Plan(List<Step> steps, int maximum, int total) {}
    record Product(int variable, Factors.Factor factor) {}
    record Outcome(Factors.Factor factor, List<Product> products) {}
    static boolean[][] interaction(List<Factors.Factor> factors, int size) {
        boolean[][] graph = new boolean[size][size];
        for (Factors.Factor factor : factors)
            for (int a : factor.variables)
                for (int b : factor.variables)
                    if (a != b)
                        graph[a][b] = true;
        return graph;
    }
    static Plan plan(List<Factors.Factor> factors, List<Integer> eliminate, String method,
                     List<Integer> order, int[] sizes) {
        boolean[][] graph = interaction(factors, sizes.length);
        TreeSet<Integer> remaining = new TreeSet<>(eliminate);
        int[] rank = new int[sizes.length];
        for (int i = 0; i < order.size(); i++)
            rank[order.get(i)] = i;
        List<Step> steps = new ArrayList<>();
        int maximum = 0, total = 0;
        while (!remaining.isEmpty()) {
            int selected = -1, bestFill = Integer.MAX_VALUE, bestDegree = Integer.MAX_VALUE;
            for (int v : remaining) {
                List<Integer> neighbors = new ArrayList<>();
                for (int u = 0; u < sizes.length; u++)
                    if (graph[v][u])
                        neighbors.add(u);
                int fill = 0;
                for (int i = 0; i < neighbors.size(); i++)
                    for (int j = i + 1; j < neighbors.size(); j++)
                        if (!graph[neighbors.get(i)][neighbors.get(j)])
                            fill++;
                boolean better =
                    selected < 0 ||
                    (method.equals("GIVEN")
                         ? rank[v] < rank[selected]
                         : fill < bestFill || (fill == bestFill && neighbors.size() < bestDegree));
                if (better) {
                    selected = v;
                    bestFill = fill;
                    bestDegree = neighbors.size();
                }
            }
            List<Integer> scope = new ArrayList<>(), neighbors = new ArrayList<>();
            for (int u = 0; u < sizes.length; u++) {
                if (u == selected || graph[selected][u])
                    scope.add(u);
                if (graph[selected][u])
                    neighbors.add(u);
            }
            int size = Factors.entries(scope, sizes);
            steps.add(new Step(selected, bestFill, scope, size));
            maximum = Math.max(maximum, size);
            total += size;
            for (int a : neighbors)
                for (int b : neighbors)
                    if (a != b)
                        graph[a][b] = true;
            for (int u = 0; u < sizes.length; u++)
                graph[u][selected] = graph[selected][u] = false;
            remaining.remove(selected);
        }
        return new Plan(steps, maximum, total);
    }
    static Outcome execute(List<Factors.Factor> initial, Plan plan, int[] sizes, boolean maximize) {
        List<Factors.Factor> factors = new ArrayList<>(initial);
        List<Product> products = new ArrayList<>();
        for (Step step : plan.steps()) {
            List<Factors.Factor> selected = new ArrayList<>(), remaining = new ArrayList<>();
            for (Factors.Factor factor : factors)
                if (factor.variables.contains(step.variable()))
                    selected.add(factor);
                else
                    remaining.add(factor);
            Factors.Factor product = Factors.multiply(selected, sizes);
            remaining.add(product.eliminate(step.variable(), maximize));
            factors = remaining;
            if (maximize)
                products.add(new Product(step.variable(), product));
        }
        return new Outcome(Factors.multiply(factors, sizes), products);
    }
    static int[] traceback(List<Product> products, int[] sizes) {
        int[] assignment = new int[sizes.length];
        for (int i = products.size() - 1; i >= 0; i--) {
            Product product = products.get(i);
            int variable = product.variable(), best = 0;
            double maximum = -1;
            for (int state = 0; state < sizes[variable]; state++) {
                assignment[variable] = state;
                double value = product.factor().value(assignment);
                if (value > maximum) {
                    maximum = value;
                    best = state;
                }
            }
            assignment[variable] = best;
        }
        return assignment;
    }
}
