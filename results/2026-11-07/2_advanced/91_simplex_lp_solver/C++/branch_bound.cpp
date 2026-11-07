#include "solver.hpp"
static bool better(const Model &model, Rational a, Rational b) {
    return model.direction == "maximize" ? a.compare(b) > 0 : a.compare(b) < 0;
}
ModelResult branchBound(const Model &model, int limit, const Solve &solve) {
    struct SearchNode {
        Bounds lower, upper;
        int depth = 0, parent = 0;
        std::string branch;
        Rational parentValue;
    };
    std::vector<SearchNode> stack{{model.lower, model.upper, 0, 0, "root", {}}};
    ModelResult out;
    int incumbents = 0, pruned = 0, infeasible = 0;
    while (!stack.empty()) {
        if (static_cast<int>(out.solves.size()) == limit) {
            out.status = "NODE_LIMIT";
            break;
        }
        SearchNode node = std::move(stack.back());
        stack.pop_back();
        int number = static_cast<int>(out.solves.size() + 1);
        LPResult lp = solve(node.lower, node.upper, number);
        std::string outcome;
        if (lp.status == "INFEASIBLE") {
            outcome = "infeasible";
            ++infeasible;
        } else if (lp.status == "UNBOUNDED") {
            outcome = "unbounded";
            out.status = "UNBOUNDED";
        } else if (out.hasSolution && !better(model, lp.objective, out.objective)) {
            outcome = "pruned";
            ++pruned;
        } else {
            int variable = -1;
            for (int j = 0; j < static_cast<int>(model.variables.size()); ++j)
                if (model.integer[j] && !lp.solution[j].whole()) {
                    variable = j;
                    break;
                }
            if (variable < 0) {
                out.hasSolution = true;
                out.objective = lp.objective;
                out.solution = lp.solution;
                outcome = "incumbent";
                ++incumbents;
            } else {
                Rational value = lp.solution[variable], down(value.floor()), up(value.ceil());
                SearchNode upper = node, lower = node;
                upper.lower[variable] = up;
                upper.depth = node.depth + 1;
                upper.parent = number;
                upper.branch = text(model.variables[variable], ">=", up);
                upper.parentValue = lp.objective;
                lower.upper[variable] = down;
                lower.depth = node.depth + 1;
                lower.parent = number;
                lower.branch = text(model.variables[variable], "<=", down);
                lower.parentValue = lp.objective;
                stack.push_back(std::move(upper));
                stack.push_back(std::move(lower));
                outcome = text("branch ", model.variables[variable], " ", value);
            }
        }
        std::string parent = node.parent ? std::to_string(node.parent) : "-",
                    lpValue = lp.status == "OPTIMAL"      ? lp.objective.str()
                              : lp.status == "INFEASIBLE" ? "infeasible"
                                                          : "unbounded";
        out.tree.push_back(text("NODE ", number, " depth ", node.depth, " parent ", parent,
                                " branch ", node.branch, " lp ", lpValue, " pivots ", lp.pivots(),
                                " action ", outcome));
        out.solves.push_back(std::move(lp));
        if (out.status == "UNBOUNDED")
            break;
    }
    if (out.status.empty())
        out.status = out.hasSolution ? "OPTIMAL" : "INFEASIBLE";
    Bound bound;
    if (out.hasSolution)
        bound = out.objective;
    if (out.status == "NODE_LIMIT")
        for (auto node = stack.rbegin(); node != stack.rend(); ++node) {
            out.tree.push_back(text("OPEN parent ", node->parent, " branch ", node->branch,
                                    " bound ", node->parentValue));
            if (!bound || better(model, node->parentValue, *bound))
                bound = node->parentValue;
        }
    out.tree.push_back(text(
        "RESULT ", out.status, " objective ", out.hasSolution ? out.objective.str() : "-",
        " nodes ", out.solves.size(), " incumbents ", incumbents, " pruned ", pruned,
        " infeasible ", infeasible, " open ", stack.size(), " bound ", bound ? bound->str() : "-"));
    return out;
}
