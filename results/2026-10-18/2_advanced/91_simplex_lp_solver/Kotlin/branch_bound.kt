data class SearchNode(val bounds: List<Bound>, val depth: Int, val parent: Int?, val branch: String, val parentValue: F?)
data class Outcome(val status: String, val root: LPResult, val solution: List<F>?, val objective: F?, val nodes: Int, val phase1: Int, val phase2: Int, val drives: Int, val lines: List<String>) {
    val pivots: Int get() = phase1 + phase2 + drives
}
object BranchBound {
    fun solve(model: Model, limit: Int, level: Int, log: MutableList<String>): Outcome {
        val stack = mutableListOf(SearchNode(model.bounds, 0, null, "root", null)); val lines = mutableListOf("MODEL ${model.name} ${if (model.maximize) "maximize" else "minimize"} integers ${model.integer.count { it }} node_limit $limit")
        var root: LPResult? = null; var solution: List<F>? = null; var objective: F? = null; var nodes = 0; var phase1 = 0; var phase2 = 0; var drives = 0; var incumbents = 0; var pruned = 0; var infeasible = 0; var status: String? = null
        while (stack.isNotEmpty()) {
            if (nodes == limit) {
                status = "NODE_LIMIT"; break
            }
            val node = stack.removeAt(stack.lastIndex); nodes++
            val result = solveLP(model, node.bounds, nodes, level, log)
            if (root == null) root = result
            phase1 += result.phase1; phase2 += result.phase2; drives += result.drives
            val action: String
            if (result.status == "INFEASIBLE") {
                infeasible++; action = "infeasible"
            }
            else if (result.status == "UNBOUNDED") {
                status = "UNBOUNDED"; action = "unbounded"
            }
            else if (objective != null && (if (model.maximize) result.value <= objective else result.value >= objective)) {
                pruned++; action = "pruned"
            }
            else {
                val j = model.names.indices.firstOrNull {
                    model.integer[it] && result.solution[it].d != 1L
                }
                if (j == null) {
                    solution = result.solution.toList(); objective = result.value; incumbents++; action = "incumbent"
                }
                else {
                    val v = result.solution[j]; val down = F(v.floor()); val up = F(v.ceil())
                    val high = node.bounds.toMutableList(); high[j] = high[j].copy(lower = up)
                    val low = node.bounds.toMutableList(); low[j] = low[j].copy(upper = down)
                    stack.add(SearchNode(high, node.depth + 1, nodes, "${model.names[j]}>=$up", result.value)); stack.add(SearchNode(low, node.depth + 1, nodes, "${model.names[j]}<=$down", result.value)); action = "branch ${model.names[j]} $v"
                }
            }
            lines.add("NODE $nodes depth ${node.depth} parent ${node.parent?.toString() ?: "-"} branch ${node.branch} lp ${if (result.status == "OPTIMAL") result.value.toString() else result.status.lowercase()} pivots ${result.pivots} action $action")
            if (status == "UNBOUNDED") break
        }
        if (status == null) status = if (solution != null) "OPTIMAL" else "INFEASIBLE"
        var bound = objective
        if (status == "NODE_LIMIT") {
            for (node in stack.asReversed()) lines.add("OPEN parent ${node.parent} branch ${node.branch} bound ${node.parentValue}")
            val values = stack.mapNotNull {
                it.parentValue
            } + listOfNotNull(objective); bound = if (model.maximize) values.maxOrNull() else values.minOrNull()
        }
        lines.add("RESULT $status objective ${objective?.toString() ?: "-"} nodes $nodes incumbents $incumbents pruned $pruned infeasible $infeasible open ${stack.size} bound ${bound?.toString() ?: "-"}")
        return Outcome(status, root!!, solution, objective, nodes, phase1, phase2, drives, lines)
    }
}
