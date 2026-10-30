import java.io.File
data class Bound(val lower: F?, val upper: F?)
data class Model(val name: String, val maximize: Boolean, val names: List<String>, val c: List<F>, val a: List<List<F>>, val rhs: List<F>, val comparisons: List<String>, val rowNames: List<String>, val bounds: List<Bound>, val integer: List<Boolean>)
fun content(parsed: Parsed): Model {
    parsed.error?.let {
        throw it
    }
    val names = mutableListOf<String>()
    for (terms in listOf(parsed.objective) + parsed.constraints.map {
        it.terms
    }) for (term in terms) if (term.name !in names) names.add(term.name)
    fun coefficients(terms: List<Term>): List<F> = names.map {
        name -> terms.filter {
            it.name == name
        }.map {
            it.coefficient
        }.sumF()
    }
    val bounds = MutableList(names.size) {
        Bound(F(0), null)
    }; val integer = MutableList(names.size) {
        false
    }; val seen = mutableSetOf<String>()
    for (constraint in parsed.constraints) if (!seen.add(constraint.name)) throw ModelError(constraint.line, "duplicate constraint ${constraint.name}")
    fun index(name: String, line: Int): Int {
        val j = names.indexOf(name); if (j < 0) throw ModelError(line, "unknown variable $name"); return j
    }
    fun check(j: Int, line: Int) {
        val bound = bounds[j]; if (bound.lower != null && bound.upper != null && bound.lower > bound.upper) throw ModelError(line, "inconsistent bounds ${names[j]}")
    }
    for (line in parsed.bounds) {
        val j = index(line.name, line.line); val old = bounds[j]
        bounds[j] = Bound(if (line.kind == "upper") old.lower else line.lower, if (line.kind == "lower") old.upper else line.upper); check(j, line.line)
    }
    for (line in parsed.integers) for (name in line.names) {
        val j = index(name, line.line); integer[j] = true; bounds[j] = Bound(bounds[j].lower?.let {
            F(it.ceil())
        }, bounds[j].upper?.let {
            F(it.floor())
        }); check(j, line.line)
    }
    for (line in parsed.binaries) for (name in line.names) {
        val j = index(name, line.line); integer[j] = true; bounds[j] = Bound(F(0), F(1))
    }
    return Model(parsed.name, parsed.maximize, names, coefficients(parsed.objective), parsed.constraints.map {
        coefficients(it.terms)
    }, parsed.constraints.map {
        it.rhs
    }, parsed.constraints.map {
        it.comparison
    }, parsed.constraints.map {
        it.name
    }, bounds, integer)
}
data class Substitution(val kind: String, val offset: F, val columns: List<Pair<Int, F>>)
data class Standard(val columns: List<String>, val rows: List<String>, val signs: List<F>, val initial: List<Int>, val slacks: List<Int?>, val artificial: Set<Int>, val phase1: List<F>, val phase2: List<F>, val constant: F, val sign: F, val substitutions: List<Substitution>, val upperRows: List<Int?>)
fun standard(model: Model, bounds: List<Bound>): Pair<Standard, Tableau> {
    val columns = mutableListOf<String>(); val substitutions = mutableListOf<Substitution>(); val costs = mutableListOf<F>()
    for (j in model.names.indices) {
        val bound = bounds[j]; val parts = mutableListOf<Pair<Int, F>>(); val kind: String; val offset: F
        if (bound.lower != null) {
            parts.add(Pair(columns.size, F(1))); columns.add(model.names[j]); costs.add(model.c[j]); kind = "shift"; offset = bound.lower
        }
        else if (bound.upper != null) {
            parts.add(Pair(columns.size, F(-1))); columns.add(model.names[j] + "'"); costs.add(-model.c[j]); kind = "reflect"; offset = bound.upper
        }
        else {
            parts.add(Pair(columns.size, F(1))); columns.add(model.names[j] + "+"); costs.add(model.c[j]); parts.add(Pair(columns.size, F(-1))); columns.add(model.names[j] + "-"); costs.add(-model.c[j]); kind = "split"; offset = F(0)
        }
        substitutions.add(Substitution(kind, offset, parts))
    }
    val variableColumns = columns.size; val rows = model.rowNames.toMutableList(); val comparisons = model.comparisons.toMutableList(); val coefficients = mutableListOf<MutableList<F>>(); val beta = mutableListOf<F>()
    for (i in model.a.indices) {
        val row = MutableList(variableColumns) {
            F(0)
        }; var rhs = model.rhs[i]
        for (j in model.names.indices) {
            rhs -= model.a[i][j] * substitutions[j].offset; for ((k, direction) in substitutions[j].columns) row[k] = direction * model.a[i][j]
        }
        coefficients.add(row); beta.add(rhs)
    }
    val upperRows = MutableList<Int?>(model.names.size) {
        null
    }
    for (j in model.names.indices) if (substitutions[j].kind == "shift") {
        val upper = bounds[j].upper
        if (upper != null) {
            upperRows[j] = rows.size; rows.add(model.names[j] + ".ub"); comparisons.add("<="); val row = MutableList(variableColumns) {
                F(0)
            }; row[substitutions[j].columns[0].first] = F(1); coefficients.add(row); beta.add(upper - substitutions[j].offset)
        }
    }
    val signs = MutableList(rows.size) {
        F(1)
    }
    for (i in rows.indices) if (beta[i] < F(0)) {
        signs[i] = F(-1); beta[i] = -beta[i]; coefficients[i] = coefficients[i].map {
            -it
        }.toMutableList(); comparisons[i] = when (comparisons[i]) {
            "<=" -> ">="; ">=" -> "<="; else -> "="
        }
    }
    val initial = MutableList(rows.size) {
        -1
    }; val slacks = MutableList<Int?>(rows.size) {
        null
    }
    for (i in rows.indices) if (comparisons[i] != "=") {
        val k = columns.size; columns.add("s:" + rows[i]); costs.add(F(0)); for (row in coefficients) row.add(F(0)); coefficients[i][k] = F(if (comparisons[i] == "<=") 1 else -1); slacks[i] = k; if (comparisons[i] == "<=") initial[i] = k
    }
    val artificial = mutableSetOf<Int>()
    for (i in rows.indices) if (comparisons[i] != "<=") {
        val k = columns.size; columns.add("a:" + rows[i]); costs.add(F(0)); for (row in coefficients) row.add(F(0)); coefficients[i][k] = F(1); initial[i] = k; artificial.add(k)
    }
    val sign = F(if (model.maximize) -1 else 1); val constant = model.names.indices.map {
        model.c[it] * substitutions[it].offset
    }.sumF()
    val s = Standard(columns, rows, signs, initial.toList(), slacks, artificial, columns.indices.map {
        F(if (it in artificial) 1 else 0)
    }, costs.map {
        sign * it
    }, constant, sign, substitutions, upperRows)
    return Pair(s, Tableau(coefficients, beta, initial))
}
data class LPResult(val standard: Standard, val tableau: Tableau, val status: String, val value: F, val solution: List<F>, val phase1: Int, val phase2: Int, val drives: Int, val infeasibility: F, val multipliers: List<F>, val ray: List<F>, val rate: F) {
    val pivots: Int get() = phase1 + phase2 + drives
}
fun recover(s: Standard, columns: List<F>, offset: Boolean): List<F> = s.substitutions.map {
    v -> v.columns.map {
        (k, direction) -> direction * columns[k]
    }.sumF() + if (offset) v.offset else F(0)
}
fun solveLP(model: Model, bounds: List<Bound>, node: Int, level: Int, log: MutableList<String>): LPResult {
    val (s, t) = standard(model, bounds)
    log.add("SOLVE node $node rows ${s.rows.size} columns ${s.columns.size} artificials ${s.artificial.size}")
    if (level >= 1) {
        for ((j, value) in s.substitutions.withIndex()) {
            var line = "MAP ${model.names[j]} ${value.kind}"
            if (value.kind != "split") {
                line += " ${value.offset}"; if (value.kind == "shift" && bounds[j].upper != null) line += " upper ${bounds[j].upper}"
            }; log.add(line)
        }
        for (i in s.signs.indices) if (s.signs[i] < F(0)) log.add("FLIP ${s.rows[i]}")
    }
    var phase1 = 0; var phase2 = 0; var drives = 0; var redundant = 0; var status = "OPTIMAL"; var infeasibility = F(0); var unbounded: Int? = null
    if (s.artificial.isNotEmpty()) {
        if (level >= 1) log.add("PHASE 1")
        if (level >= 2) log.addAll(t.display("phase 1 start", s.columns, s.rows, s.phase1, F(0), F(1)))
        phase1 = Simplex.phase(t, s.phase1, s.columns.indices.toList(), s.columns, s.rows, F(0), F(1), level, log).first
        infeasibility = t.value(s.phase1)
        if (level >= 1) log.add("PHASE 1 END objective $infeasibility iterations $phase1")
        if (infeasibility > F(0)) {
            status = "INFEASIBLE"; if (level >= 2) log.addAll(t.display("final", s.columns, s.rows, s.phase1, F(0), F(1)))
        }
        else {
            for (i in s.rows.indices) if (t.basis[i] in s.artificial) {
                val k = s.columns.indices.firstOrNull {
                    it !in s.artificial && t.t[i][it] != F(0)
                }
                if (k != null) {
                    if (level >= 1) log.add("DRIVE row ${s.rows[i]} enter ${s.columns[k]} leave ${s.columns[t.basis[i]]}"); t.pivot(i, k); drives++
                }
                else {
                    redundant++; if (level >= 1) log.add("REDUNDANT row ${s.rows[i]}")
                }
            }
        }
    }
    if (status != "INFEASIBLE") {
        if (level >= 1) log.add("PHASE 2")
        if (level >= 2) log.addAll(t.display("phase 2 start", s.columns, s.rows, s.phase2, s.constant, s.sign))
        val phase = Simplex.phase(t, s.phase2, s.columns.indices.filter {
            it !in s.artificial
        }, s.columns, s.rows, s.constant, s.sign, level, log); phase2 = phase.first; unbounded = phase.second
        if (unbounded != null) {
            status = "UNBOUNDED"; if (level >= 1) log.add("UNBOUNDED enter ${s.columns[unbounded]}")
        }
        if (level >= 1) log.add("PHASE 2 END objective ${s.constant + s.sign * t.value(s.phase2)} iterations $phase2")
        if (level >= 2) log.addAll(t.display("final", s.columns, s.rows, s.phase2, s.constant, s.sign))
    }
    val value = s.constant + s.sign * t.value(s.phase2); val columns = MutableList(s.columns.size) {
        F(0)
    }
    for (i in s.rows.indices) columns[t.basis[i]] = t.beta[i]
    val solution = recover(s, columns, true); val reduced = t.reduced(s.phase1)
    val multipliers = if (status == "INFEASIBLE") s.initial.mapIndexed {
        i, k -> s.signs[i] * (s.phase1[k] - reduced[k])
    } else emptyList()
    var ray: List<F> = emptyList(); var rate = F(0)
    if (unbounded != null) {
        val direction = MutableList(s.columns.size) {
            F(0)
        }; direction[unbounded] = F(1); for (i in s.rows.indices) direction[t.basis[i]] = -t.t[i][unbounded]; ray = recover(s, direction, false); rate = model.c.indices.map {
            model.c[it] * ray[it]
        }.sumF()
    }
    log.add("RESULT $status objective ${if (status == "OPTIMAL") value.toString() else "-"} phase1 $phase1 phase2 $phase2 drives $drives redundant $redundant")
    return LPResult(s, t, status, value, solution, phase1, phase2, drives, infeasibility, multipliers, ray, rate)
}
fun interval(value: F, lower: F?, upper: F?): Pair<String, String> = Pair(lower?.let {
    (value + it).toString()
} ?: "-inf", upper?.let {
    (value + it).toString()
} ?: "inf")
fun sensitivity(model: Model, result: LPResult): List<String> {
    val s = result.standard; val t = result.tableau; val reducedColumns = t.reduced(s.phase2); val basic = t.basis.toSet(); val nonbasic = s.columns.indices.filter {
        it !in basic && it !in s.artificial
    }
    val prices = model.a.indices.map {
        -s.sign * s.signs[it] * reducedColumns[s.initial[it]]
    }
    val reduced = model.names.indices.map {
        j -> model.c[j] - model.a.indices.map {
            prices[it] * model.a[it][j]
        }.sumF()
    }
    val objective = model.a.indices.map {
        prices[it] * model.rhs[it]
    }.sumF() + model.names.indices.map {
        reduced[it] * result.solution[it]
    }.sumF()
    val lines = mutableListOf("MODEL ${model.name} ${if (model.integer.any { it }) "relaxation" else "lp"} objective ${result.value}", "BASIS " + t.basis.joinToString(" ") {
        s.columns[it]
    }, "DEGENERACY primal ${s.rows.indices.count { t.basis[it] !in s.artificial && t.beta[it] == F(0) }} dual ${nonbasic.count { reducedColumns[it] == F(0) }}", "DUAL objective $objective")
    for (i in model.a.indices) {
        val rho = s.rows.indices.map {
            s.signs[i] * t.t[it][s.initial[i]]
        }; var lower: F? = null; var upper: F? = null
        val fixed = s.rows.indices.any {
            rho[it] != F(0) && t.basis[it] in s.artificial
        }
        val ends: Pair<String, String>
        if (fixed) ends = Pair(model.rhs[i].toString(), model.rhs[i].toString())
        else {
            for (j in s.rows.indices) {
                if (rho[j] > F(0)) {
                    val value = -t.beta[j] / rho[j]; lower = maxOf(lower ?: value, value)
                } else if (rho[j] < F(0)) {
                    val value = -t.beta[j] / rho[j]; upper = minOf(upper ?: value, value)
                }
            }; ends = interval(model.rhs[i], lower, upper)
        }
        lines.add("CONSTRAINT ${model.rowNames[i]} price ${prices[i]} rhs ${model.rhs[i]} range ${ends.first} ${ends.second}")
    }
    for (j in model.names.indices) {
        val variable = s.substitutions[j]
        val status = if (variable.kind == "split") {
            if (variable.columns.all {
                it.first !in basic
            }) "zero" else "basic"
        } else if (variable.columns[0].first !in basic) {
            if (variable.kind == "shift") "lower" else "upper"
        } else if (variable.kind == "shift" && s.upperRows[j]?.let {
            s.slacks[it]!! !in basic
        } == true) "upper" else "basic"
        val h = MutableList(s.columns.size) {
            F(0)
        }; for ((k, direction) in variable.columns) h[k] = s.sign * direction
        val eta = t.reduced(h); var lower: F? = null; var upper: F? = null
        for (k in nonbasic) {
            if (eta[k] > F(0)) {
                val value = -reducedColumns[k] / eta[k]; lower = maxOf(lower ?: value, value)
            } else if (eta[k] < F(0)) {
                val value = -reducedColumns[k] / eta[k]; upper = minOf(upper ?: value, value)
            }
        }
        val ends = interval(model.c[j], lower, upper)
        lines.add("VARIABLE ${model.names[j]} $status value ${result.solution[j]} reduced ${reduced[j]} cost ${model.c[j]} range ${ends.first} ${ends.second}")
    }
    return lines
}
fun statistics(model: Model): String {
    val matrix = model.a.flatten().filter {
        it != F(0)
    }.map {
        it.absolute
    }; val objective = model.c.filter {
        it != F(0)
    }.map {
        it.absolute
    }; val rhs = model.rhs.filter {
        it != F(0)
    }.map {
        it.absolute
    }; val bounds = model.bounds.flatMap {
        listOfNotNull(it.lower, it.upper)
    }.filter {
        it != F(0)
    }.map {
        it.absolute
    }
    fun range(values: List<F>): String = if (values.isEmpty()) "- -" else "${values.minOrNull()} ${values.maxOrNull()}"
    return "STATS nonzeros ${matrix.size} matrix ${range(matrix)} objective ${range(objective)} rhs ${range(rhs)} bounds ${range(bounds)}"
}
fun write(name: String, lines: List<String>) {
    File("output").mkdirs(); File("output/$name").writeText(if (lines.isEmpty()) "" else lines.joinToString("\n") + "\n")
}
fun main() {
    val blocks = LPParser.read(); val params = LPParser.params(); val iterations = mutableListOf<String>(); val solutions = mutableListOf<String>(); val sensitivityLines = mutableListOf<String>(); val tree = mutableListOf<String>(); val csv = mutableListOf("model,status,objective,approx,relaxation,nodes,pivots")
    val statuses = IntArray(5); val totals = IntArray(4); var analyzed = 0; var integerModels = 0; var integerNodes = 0; var limits = 0
    for (block in blocks) {
        val model: Model
        try {
            model = content(block)
        } catch (error: ModelError) {
            statuses[4]++; iterations.add("MODEL ${block.name} error"); solutions.addAll(listOf("MODEL ${block.name}", "STATUS ERROR line ${error.line} ${error.reason}")); sensitivityLines.add("MODEL ${block.name} skipped ERROR"); csv.add("${block.name},ERROR,-,-,-,0,0"); continue
        }
        val integer = model.integer.any {
            it
        }; val level = params.levels[model.name] ?: params.level; val limit = params.limits[model.name] ?: params.limit
        iterations.add("MODEL ${model.name} level $level")
        val outcome = if (integer) BranchBound.solve(model, limit, level, iterations) else {
            val root = solveLP(model, model.bounds, 1, level, iterations); Outcome(root.status, root, if (root.status == "OPTIMAL") root.solution else null, if (root.status == "OPTIMAL") root.value else null, 1, root.phase1, root.phase2, root.drives, emptyList())
        }
        val root = outcome.root; val status = outcome.status; statuses[listOf("OPTIMAL", "INFEASIBLE", "UNBOUNDED", "NODE_LIMIT").indexOf(status)]++
        totals[0] += outcome.nodes; totals[1] += outcome.phase1; totals[2] += outcome.phase2; totals[3] += outcome.drives
        if (integer) {
            integerModels++; integerNodes += outcome.nodes; if (status == "NODE_LIMIT") limits++; tree.addAll(outcome.lines)
        }
        solutions.addAll(listOf("MODEL ${model.name} ${if (model.maximize) "maximize" else "minimize"} variables ${model.names.size} constraints ${model.a.size} integers ${model.integer.count { it }}", statistics(model), "STATUS $status"))
        outcome.objective?.let {
            solutions.add("OBJECTIVE $it approx ${it.approximate}")
        }
        if (integer && root.status == "OPTIMAL") solutions.add("RELAXATION ${root.value} approx ${root.value.approximate}")
        if (root.status == "INFEASIBLE") {
            solutions.add("INFEASIBILITY ${root.infeasibility}"); for ((i, multiplier) in root.multipliers.withIndex()) solutions.add("FARKAS ${root.standard.rows[i]} $multiplier")
        }
        if (outcome.solution != null || status == "UNBOUNDED") {
            for ((j, value) in (outcome.solution ?: root.solution).withIndex()) solutions.add("VALUE ${model.names[j]} $value")
        }
        if (status == "UNBOUNDED") {
            for ((j, value) in root.ray.withIndex()) solutions.add("RAY ${model.names[j]} $value"); solutions.add("RATE ${root.rate}")
        }
        val values = outcome.solution
        if (values != null) {
            for (i in model.a.indices) {
                val value = model.names.indices.map {
                    model.a[i][it] * values[it]
                }.sumF(); val margin = if (model.comparisons[i] == "<=") model.rhs[i] - value else value - model.rhs[i]; solutions.add("ROW ${model.rowNames[i]} $value $margin")
            }
        }
        if (integer) solutions.add("NODES ${outcome.nodes}"); solutions.add("PIVOTS ${outcome.pivots}")
        if (root.status == "OPTIMAL") {
            analyzed++; sensitivityLines.addAll(sensitivity(model, root))
        } else sensitivityLines.add("MODEL ${model.name} skipped ${root.status}")
        csv.add("${model.name},$status,${outcome.objective?.toString() ?: "-"},${outcome.objective?.approximate ?: "-"},${if (root.status == "OPTIMAL") root.value.toString() else "-"},${outcome.nodes},${outcome.pivots}")
    }
    iterations.add("TOTAL solves ${totals[0]} phase1 ${totals[1]} phase2 ${totals[2]} drives ${totals[3]} pivots ${totals[1] + totals[2] + totals[3]}")
    solutions.add("SUMMARY models ${blocks.size} optimal ${statuses[0]} infeasible ${statuses[1]} unbounded ${statuses[2]} node_limit ${statuses[3]} error ${statuses[4]}")
    sensitivityLines.add("SUMMARY analyzed $analyzed skipped ${blocks.size - analyzed}"); tree.add("SUMMARY models $integerModels nodes $integerNodes node_limit $limits")
    write("iterations.txt", iterations); write("solutions.txt", solutions); write("sensitivity.txt", sensitivityLines); write("bnb_tree.txt", tree); write("summary.csv", csv)
}
