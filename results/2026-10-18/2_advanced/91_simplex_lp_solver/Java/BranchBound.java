import java.util.*;
final class BranchBound {
    record Node(Rational[] lower, Rational[] upper, int depth, Integer parent, String branch,
                Rational parentValue) {}
    @FunctionalInterface
    interface Solver {
        Main.LpResult solve(Rational[] lower, Rational[] upper, int number);
    }
    record Result(String status, Rational objective, Rational[] solution,
                  List<Main.LpResult> solves, Main.LpResult root, List<String> lines, int nodes) {}
    static Result search(Main.Model model, int limit, Solver solve) {
        Deque<Node> stack = new ArrayDeque<>();
        stack.push(new Node(model.lower.clone(), model.upper.clone(), 0, null, "root", null));
        List<Main.LpResult> solves = new ArrayList<>();
        List<String> lines = new ArrayList<>();
        Rational[] incumbent = null;
        Rational objective = null;
        int incumbents = 0, pruned = 0, infeasible = 0;
        String status = null;
        while (!stack.isEmpty()) {
            if (solves.size() == limit) {
                status = "NODE_LIMIT";
                break;
            }
            Node node = stack.pop();
            int number = solves.size() + 1;
            Main.LpResult result = solve.solve(node.lower(), node.upper(), number);
            solves.add(result);
            String outcome;
            if (result.status.equals("INFEASIBLE")) {
                outcome = "infeasible";
                infeasible++;
            } else if (result.status.equals("UNBOUNDED")) {
                outcome = "unbounded";
                status = "UNBOUNDED";
            } else if (objective != null && (model.direction.equals("maximize")
                                                 ? result.objective.compareTo(objective) <= 0
                                                 : result.objective.compareTo(objective) >= 0)) {
                outcome = "pruned";
                pruned++;
            } else {
                int fractional = -1;
                for (int j = 0; j < model.integer.length; j++)
                    if (model.integer[j] && result.solution[j].denominator() != 1) {
                        fractional = j;
                        break;
                    }
                if (fractional < 0) {
                    incumbent = result.solution.clone();
                    objective = result.objective;
                    outcome = "incumbent";
                    incumbents++;
                } else {
                    Rational value = result.solution[fractional];
                    String name = model.variables.get(fractional);
                    long down = value.floor(), up = value.ceil();
                    Rational[] lower = node.lower().clone(), upper = node.upper().clone();
                    lower[fractional] = new Rational(up);
                    upper[fractional] = new Rational(down);
                    stack.push(new Node(lower, node.upper().clone(), node.depth() + 1, number,
                                        name + ">=" + up, result.objective));
                    stack.push(new Node(node.lower().clone(), upper, node.depth() + 1, number,
                                        name + "<=" + down, result.objective));
                    outcome = "branch " + name + " " + value;
                }
            }
            String parent = node.parent() == null ? "-" : node.parent().toString(),
                   lp = result.status.equals("OPTIMAL") ? result.objective.toString()
                                                        : result.status.toLowerCase(Locale.ROOT);
            lines.add("NODE " + number + " depth " + node.depth() + " parent " + parent +
                      " branch " + node.branch() + " lp " + lp + " pivots " + result.pivots() +
                      " action " + outcome);
            if ("UNBOUNDED".equals(status))
                break;
        }
        if (status == null)
            status = incumbent == null ? "INFEASIBLE" : "OPTIMAL";
        Rational bound = objective;
        if (status.equals("NODE_LIMIT"))
            for (Node node : stack) {
                lines.add("OPEN parent " + node.parent() + " branch " + node.branch() + " bound " +
                          node.parentValue());
                if (bound == null ||
                    (model.direction.equals("maximize") ? node.parentValue().compareTo(bound) > 0
                                                        : node.parentValue().compareTo(bound) < 0))
                    bound = node.parentValue();
            }
        lines.add("RESULT " + status + " objective " + (objective == null ? "-" : objective) +
                  " nodes " + solves.size() + " incumbents " + incumbents + " pruned " + pruned +
                  " infeasible " + infeasible + " open " + stack.size() + " bound " +
                  (bound == null ? "-" : bound));
        return new Result(status, objective, incumbent, solves, solves.getFirst(), lines,
                          solves.size());
    }
}
