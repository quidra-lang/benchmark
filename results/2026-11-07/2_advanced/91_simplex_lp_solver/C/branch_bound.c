#include "solver.h"
static bool better(const Model *model, Rational a, Rational b) {
    return model->maximize ? rat_compare(a, b) > 0 : rat_compare(a, b) < 0;
}
void result_push(ModelResult *result, LPResult *lp) {
    if (result->solve_count == result->solve_capacity) {
        result->solve_capacity = result->solve_capacity ? result->solve_capacity * 2 : 16;
        result->solves =
            resize(result->solves, (size_t)result->solve_capacity * sizeof *result->solves);
    }
    result->solves[result->solve_count++] = lp;
}
typedef struct {
    Bound lower[15], upper[15];
    int depth, parent;
    char branch[64];
    Rational parent_value;
} SearchNode;
typedef struct {
    SearchNode *data;
    int count, capacity;
} NodeStack;
static void push(NodeStack *stack, SearchNode node) {
    if (stack->count == stack->capacity) {
        stack->capacity = stack->capacity ? stack->capacity * 2 : 16;
        stack->data = resize(stack->data, (size_t)stack->capacity * sizeof *stack->data);
    }
    stack->data[stack->count++] = node;
}
ModelResult branch_bound(const Model *model, int limit, int level) {
    NodeStack stack = {0};
    SearchNode root = {0};
    memcpy(root.lower, model->lower, (size_t)model->variable_count * sizeof *root.lower);
    memcpy(root.upper, model->upper, (size_t)model->variable_count * sizeof *root.upper);
    strcpy(root.branch, "root");
    push(&stack, root);
    ModelResult out = {0};
    int incumbents = 0, pruned = 0, infeasible = 0;
    bool ended = false;
    while (stack.count) {
        if (out.solve_count == limit) {
            out.status = NODE_LIMIT;
            ended = true;
            break;
        }
        SearchNode node = stack.data[--stack.count];
        int number = out.solve_count + 1;
        LPResult *lp = solve_lp(model, node.lower, node.upper, number, level);
        result_push(&out, lp);
        char *outcome = NULL;
        if (lp->status == INFEASIBLE) {
            outcome = copy_text("infeasible");
            ++infeasible;
        } else if (lp->status == UNBOUNDED) {
            outcome = copy_text("unbounded");
            out.status = UNBOUNDED;
            ended = true;
        } else if (out.has_solution && !better(model, lp->objective, out.objective)) {
            outcome = copy_text("pruned");
            ++pruned;
        } else {
            int variable = -1;
            for (int j = 0; j < model->variable_count; ++j)
                if (model->integer[j] && !rat_whole(lp->solution[j])) {
                    variable = j;
                    break;
                }
            if (variable < 0) {
                out.has_solution = true;
                out.objective = lp->objective;
                memcpy(out.solution, lp->solution,
                       (size_t)model->variable_count * sizeof *out.solution);
                outcome = copy_text("incumbent");
                ++incumbents;
            } else {
                Rational value = lp->solution[variable], down = integer(rat_floor(value)),
                         up = integer(rat_ceil(value));
                SearchNode upper = node, lower = node;
                upper.lower[variable] = (Bound){true, up};
                upper.depth = node.depth + 1;
                upper.parent = number;
                upper.parent_value = lp->objective;
                snprintf(upper.branch, sizeof upper.branch, "%s>=%s", model->variables[variable],
                         rat_text(up).value);
                lower.upper[variable] = (Bound){true, down};
                lower.depth = node.depth + 1;
                lower.parent = number;
                lower.parent_value = lp->objective;
                snprintf(lower.branch, sizeof lower.branch, "%s<=%s", model->variables[variable],
                         rat_text(down).value);
                push(&stack, upper);
                push(&stack, lower);
                outcome =
                    format_text("branch %s %s", model->variables[variable], rat_text(value).value);
            }
        }
        char *parent = node.parent ? format_text("%d", node.parent) : copy_text("-");
        FractionText lp_number = rat_text(lp->objective);
        const char *lp_value = lp->status == OPTIMAL      ? lp_number.value
                               : lp->status == INFEASIBLE ? "infeasible"
                                                          : "unbounded";
        lines_push(&out.tree,
                   format_text("NODE %d depth %d parent %s branch %s lp %s pivots %d action %s",
                               number, node.depth, parent, node.branch, lp_value, lp_pivots(lp),
                               outcome));
        free(parent);
        free(outcome);
        if (ended && out.status == UNBOUNDED)
            break;
    }
    if (!ended)
        out.status = out.has_solution ? OPTIMAL : INFEASIBLE;
    Bound bound = {out.has_solution, out.objective};
    if (out.status == NODE_LIMIT)
        for (int i = stack.count - 1; i >= 0; --i) {
            const SearchNode *node = &stack.data[i];
            lines_push(&out.tree, format_text("OPEN parent %d branch %s bound %s", node->parent,
                                              node->branch, rat_text(node->parent_value).value));
            if (!bound.finite || better(model, node->parent_value, bound.value))
                bound = (Bound){true, node->parent_value};
        }
    lines_push(
        &out.tree,
        format_text(
            "RESULT %s objective %s nodes %d incumbents %d pruned %d infeasible %d open %d bound %s",
            status_name(out.status), out.has_solution ? rat_text(out.objective).value : "-",
            out.solve_count, incumbents, pruned, infeasible, stack.count,
            bound.finite ? rat_text(bound.value).value : "-"));
    free(stack.data);
    return out;
}
