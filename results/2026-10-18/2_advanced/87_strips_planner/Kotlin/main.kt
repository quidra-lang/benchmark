import java.io.File
fun arguments(domain: Domain, args: List<String>, expected: List<String>, table: Map<String, String>, noun: String): String? {
    if (args.size != expected.size) return "expected ${expected.size} arguments, got ${args.size}"
    for ((i, name) in args.withIndex()) {
        val actual = table[name] ?: return "unknown $noun $name"
        if (!Grounder.subtype(domain, actual, expected[i])) return "argument ${i + 1} ($name) is not of type ${expected[i]}"
    }
    return null
}
fun atomError(domain: Domain, atom: Atom, table: Map<String, String>, noun: String, equality: Boolean): String? {
    val types = if (equality && atom.predicate == "=") listOf("object", "object")
    else domain.predicates.firstOrNull {
        it.name == atom.predicate
    }?.types ?: return "unknown predicate ${atom.predicate}"
    return arguments(domain, atom.terms, types, table, noun)
}
fun validateDomain(domain: Domain) {
    val actions = mutableListOf<Schema>()
    for (action in domain.actions) {
        val table = action.parameters.associate {
            it.name to it.type
        }
        var error = action.parameters.firstOrNull {
            it.type !in domain.typeOrder
        }?.let {
            "unknown type ${it.type}"
        }
        if (error == null) for (literal in action.pre + action.effects) {
            val reason = atomError(domain, literal.atom, table, "variable", true)
            if (reason != null) {
                error = "${literal.atom.text}: $reason"; break
            }
        }
        if (error != null) domain.diagnostics.add("error: action ${action.name}: $error") else actions.add(action)
    }
    domain.actions = actions
    for (predicate in domain.predicates) if (domain.actions.none {
        a -> (a.pre + a.effects).any {
            it.atom.predicate == predicate.name
        }
    }) {
        domain.diagnostics.add("warning: predicate ${predicate.name} is not used by any action")
    }
}
fun validateProblem(domain: Domain, problem: Problem) {
    val table = problem.objects.associate {
        it.name to it.type
    }
    for (side in 0..1) {
        val original = if (side == 0) problem.initial else problem.goals
        val seen = mutableSetOf<Atom>()
        val kept = mutableListOf<Atom>()
        for (atom in original) {
            val error = atomError(domain, atom, table, "object", false) ?: if (atom in seen) "duplicate" else null
            if (error != null) problem.diagnostics.add("warning: ${if (side == 0) "init" else "goal"} ${atom.text}: $error")
            else {
                seen.add(atom); kept.add(atom)
            }
        }
        if (side == 0) problem.initial = kept else problem.goals = kept
    }
}
fun listed(heading: String, values: List<String>): String = heading + " " + if (values.isEmpty()) "-" else values.joinToString(" ")
fun numbers(values: State): String = if (values.isEmpty()) "-" else values.sorted().joinToString(",")
fun hText(value: Long): String = if (value >= Heuristics.INFINITY) "inf" else value.toString()
fun hValues(values: List<Long>): String = listOf("goalcount", "hmax", "hadd", "ff", "lmcount").zip(values).joinToString(" ") {
    "${it.first}=${hText(it.second)}"
}
fun cost(g: Grounding, plan: List<Int>): Long = plan.sumOf {
    g.actions[it].cost.toLong()
}
fun domainReport(domain: Domain): List<String> {
    val lines = (listOf("== domain ${domain.name} ==") + domain.diagnostics).toMutableList()
    for (type in domain.typeOrder) {
        val chain = mutableListOf(type)
        var current = type
        while (true) {
            current = domain.parents[current] ?: break; chain.add(current)
        }
        lines.add("type " + chain.joinToString(" < "))
    }
    val fluent = Grounder.fluents(domain)
    for (p in domain.predicates) lines.add("predicate ${p.name}/${p.types.size} ${if (p.name in fluent) "fluent" else "static"}")
    for (a in domain.actions) lines.add("action ${a.name}/${a.parameters.size} cost=${a.cost} pre=${a.pre.size} add=${a.effects.count { !it.negative }} del=${a.effects.count { it.negative }}")
    return lines
}
fun groundingReport(domain: Domain, problem: Problem, g: Grounding): List<String> {
    val lines = (listOf("", "== problem ${problem.name} ==") + problem.diagnostics + "objects: ${problem.objects.size}").toMutableList()
    for (type in domain.typeOrder) lines.add(listed("  $type:", problem.objects.filter {
        Grounder.subtype(domain, it.type, type)
    }.map {
        it.name
    }))
    lines.add("static facts: ${g.staticCount}")
    for ((i, a) in domain.actions.withIndex()) lines.add("schema ${a.name}: assignments=${g.stats[i][0]} candidates=${g.stats[i][1]} reachable=${g.stats[i][2]}")
    lines.add("candidates: ${g.stats.sumOf { it[1] }} reachable: ${g.actions.size}")
    lines.add("facts: ${g.facts.size} init: ${g.initial.size} goals: ${g.goals.size}")
    for (atom in g.unreachable) lines.add("unreachable goal: ${atom.text}")
    lines.add(listed("facts by predicate:", domain.predicates.filter {
        it.name in g.fluent
    }.map {
        p -> "${p.name}=${g.facts.count { it.predicate == p.name }}"
    }))
    lines.add("facts:")
    for ((i, atom) in g.facts.withIndex()) lines.add("  $i ${atom.text}")
    lines.add("actions:")
    for ((i, a) in g.actions.withIndex()) lines.add("  $i ${a.text} cost=${a.cost} pre=${numbers(a.pre)} neg=${numbers(a.neg)} add=${numbers(a.add)} del=${numbers(a.del)}")
    return lines
}
data class Validation(val status: String, val messages: List<String>, val correct: Int) {
    val verdict: String get() = if (status == "valid") "valid ${messages[0]}" else "$status: ${messages[0]}"
}
fun validateSteps(domain: Domain, problem: Problem, steps: List<Atom>): Validation {
    val world = problem.initial.toMutableSet()
    var cost = 0L
    val table = problem.objects.associate {
        it.name to it.type
    }
    for ((k, step) in steps.withIndex()) {
        val action = domain.actions.firstOrNull {
            it.name == step.predicate
        }
        ?: return Validation("invalid", listOf("step ${k + 1} ${step.text}: unknown action ${step.predicate}"), k)
        val error = arguments(domain, step.terms, action.parameters.map {
            it.type
        }, table, "object")
        if (error != null) return Validation("invalid", listOf("step ${k + 1} ${step.text}: $error"), k)
        val values = action.parameters.map {
            it.name
        }.zip(step.terms).toMap()
        for (original in action.pre) {
            val literal = original.replace(values)
            val atom = literal.atom
            val truth = if (atom.predicate == "=") atom.terms[0] == atom.terms[1] else atom in world
            if (truth == literal.negative) return Validation("invalid", listOf("step ${k + 1} ${step.text}: precondition ${literal.text} is false"), k)
        }
        for (literal in action.effects) if (literal.negative) world.remove(literal.atom.replace(values))
        for (literal in action.effects) if (!literal.negative) world.add(literal.atom.replace(values))
        cost += action.cost
    }
    val missing = problem.goals.filter {
        it !in world
    }.map {
        "unsatisfied goal ${it.text}"
    }
    return if (missing.isEmpty()) Validation("valid", listOf("length=${steps.size} cost=$cost"), steps.size) else Validation("goal not reached", missing, steps.size)
}
fun steps(g: Grounding, plan: List<Int>): List<Atom> = plan.map {
    Atom(g.actions[it].name, g.actions[it].args)
}
fun mapSteps(g: Grounding, steps: List<Atom>): List<Int> = steps.map {
    step -> g.actions.indexOfFirst {
        it.name == step.predicate && it.args == step.terms
    }
}
fun interfere(a: Action, b: Action): Boolean = a.del.any {
    it in b.pre || it in b.add
} || b.del.any {
    it in a.pre || it in a.add
} || a.add.any {
    it in b.neg
} || b.add.any {
    it in a.neg
}
fun parallel(g: Grounding, plan: List<Int>): List<List<Int>> {
    val levels = mutableListOf<Int>()
    for ((j, action) in plan.withIndex()) {
        var level = 0
        for (i in 0 until j) {
            val a = g.actions[plan[i]]
            val b = g.actions[action]
            if (a.add.any {
                it in b.pre
            } || a.del.any {
                it in b.neg
            } || interfere(a, b)) level = maxOf(level, levels[i])
        }
        levels.add(level + 1)
    }
    val layers = List(levels.maxOrNull() ?: 0) {
        mutableListOf<Int>()
    }
    for ((i, action) in plan.withIndex()) layers[levels[i] - 1].add(action)
    return layers
}
fun parallelVerdict(g: Grounding, layers: List<List<Int>>): String {
    var state = g.initial
    for ((k, layer) in layers.withIndex()) {
        val bad = layer.indices.any {
            i -> layer.drop(i + 1).any {
                interfere(g.actions[layer[i]], g.actions[it])
            }
        }
        if (bad || layer.any {
            !Search.applicable(g.actions[it], state)
        }) return "invalid at layer ${k + 1}"
        state = (state - layer.flatMap {
            g.actions[it].del
        }.toSet()) + layer.flatMap {
            g.actions[it].add
        }
    }
    return if (state.containsAll(g.goals)) "valid" else "goal not reached"
}
fun improve(g: Grounding, input: List<Int>): List<Int> {
    var plan = input
    var i = 0
    while (i < plan.size) {
        var state = g.initial
        for (action in plan.take(i)) state = Search.apply(g.actions[action], state)
        val next = plan.take(i).toMutableList()
        for (action in plan.drop(i + 1)) if (Search.applicable(g.actions[action], state)) {
            state = Search.apply(g.actions[action], state); next.add(action)
        }
        if (state.containsAll(g.goals)) plan = next else i++
    }
    return plan
}
data class Transformed(val actions: List<Action>, val initial: State, val complements: Int)
fun transformed(g: Grounding): Transformed {
    val negatives = g.actions.flatMap {
        it.neg
    }.toSet().sorted()
    val complements = negatives.withIndex().associate {
        it.value to g.facts.size + it.index
    }
    val initial = g.initial + negatives.filter {
        it !in g.initial
    }.map {
        complements.getValue(it)
    }
    val actions = g.actions.map {
        a -> a.copy(pre = a.pre + a.neg.map {
            complements.getValue(it)
        }, add = a.add + a.del.mapNotNull {
            complements[it]
        }, del = a.del + a.add.mapNotNull {
            complements[it]
        })
    }
    return Transformed(actions, initial, negatives.size)
}
data class Params(var budget: Int = 0, var weight: Int = 0, var limit: Int = 0,
val runs: MutableList<Pair<String, String>> = mutableListOf(), var repair: Pair<String, String> = Pair("", "")) {
    companion object {
        fun read(): Params {
            val p = Params()
            for (line in File("input/params.txt").readLines()) if (line.isNotEmpty() && !line.startsWith('#')) {
                val a = line.split(' ')
                when (a[0]) {
                    "budget" -> p.budget = a[1].toInt(); "weight" -> p.weight = a[1].toInt(); "graphplan" -> p.limit = a[1].toInt(); "run" -> p.runs.add(Pair(a[1], a[2])); else -> p.repair = Pair(a[1], a[2])
                }
            }
            return p
        }
    }
}
data class Candidate(val problem: String, val label: String, val steps: MutableList<Atom> = mutableListOf())
fun readCandidates(): List<Candidate> {
    val result = mutableListOf<Candidate>()
    for (line in File("input/candidates.txt").readLines()) if (line.isNotEmpty() && !line.startsWith('#')) {
        if (line.startsWith("plan ")) {
            val a = line.split(' '); result.add(Candidate(a[1], a[2]))
        }
        else if (line != "end") {
            val a = line.substring(1, line.length - 1).split(' '); result.last().steps.add(Atom(a[0], a.drop(1)))
        }
    }
    return result
}
data class PlanBlock(val lines: List<String>, val validation: List<String>, val valid: Boolean)
fun planBlock(domain: Domain, problem: Problem, g: Grounding, plan: List<Int>, tag: String, landmarks: State, seen: MutableList<Pair<List<Int>, String>>): PlanBlock {
    val first = seen.firstOrNull {
        it.first == plan
    }
    val same = first?.let {
        " (same as ${it.second})"
    } ?: ""
    if (first == null) seen.add(Pair(plan, tag))
    val lines = mutableListOf("plan: length=${plan.size} cost=${cost(g, plan)}$same")
    for ((k, action) in plan.withIndex()) lines.add("  ${k + 1} ${g.actions[action].text}")
    lines.add(listed("schemas:", domain.actions.mapIndexedNotNull {
        i, action ->
        val count = plan.count {
            g.actions[it].source == i
        }; if (count == 0) null else "${action.name}=$count"
    }))
    val layers = parallel(g, plan)
    lines.add("parallel: layers=${layers.size}")
    for ((k, layer) in layers.withIndex()) lines.add(listed("  ${k + 1}:", layer.map {
        g.actions[it].text
    }))
    val improved = improve(g, plan)
    lines.add("improved: length=${improved.size} cost=${cost(g, improved)} removed=${plan.size - improved.size}")
    if (improved.size < plan.size) {
        for ((k, action) in improved.withIndex()) lines.add("  ${k + 1} ${g.actions[action].text}")
    }
    var state = g.initial
    val reached = mutableSetOf<Int>()
    for (action in plan) {
        state = Search.apply(g.actions[action], state); reached.addAll(state.intersect(landmarks))
    }
    lines.add("landmarks reached: ${reached.size}/${landmarks.size}")
    for (fact in (landmarks - reached).sorted()) lines.add("  missed ${g.facts[fact].text}")
    val original = validateSteps(domain, problem, steps(g, plan))
    val checked = validateSteps(domain, problem, steps(g, improved))
    return PlanBlock(lines, listOf("$tag: ${original.verdict}", "  parallel: ${parallelVerdict(g, layers)}", "  improved: ${checked.verdict}"), original.status == "valid")
}
fun profile(g: Grounding, plan: List<Int>, tag: String): List<String> {
    val lines = mutableListOf("-- profile ($tag) --")
    var state = g.initial
    var remaining = cost(g, plan)
    val over = LongArray(5)
    for (k in 0..plan.size) {
        val values = Heuristics.values(g, state)
        for (i in 0 until 5) if (values[i] > remaining) over[i]++
        lines.add("  $k: h*=$remaining ${hValues(values)}")
        if (k < plan.size) {
            state = Search.apply(g.actions[plan[k]], state); remaining -= g.actions[plan[k]].cost
        }
    }
    lines.add("overestimates: ${hValues(over.toList())}")
    lines.add("-- causal links ($tag) --")
    val suppliers = IntArray(g.facts.size)
    for ((k, action) in plan.withIndex()) {
        lines.add(listed("  ${k + 1} ${g.actions[action].text}:", g.actions[action].pre.sorted().map {
            "${g.facts[it].text}<-${suppliers[it]}"
        }))
        for (fact in g.actions[action].add) suppliers[fact] = k + 1
    }
    lines.add(listed("  goal:", g.goals.sorted().map {
        "${g.facts[it].text}<-${suppliers[it]}"
    }))
    return lines
}
fun resultLine(result: SearchResult, unreachable: Boolean): String = if (unreachable) "result: FAIL (unreachable goal)"
else if (result.status == "solved") "result: solved expanded=${result.expanded} generated=${result.generated}"
else "result: FAIL (${result.status}) expanded=${result.expanded} generated=${result.generated}"
fun write(name: String, lines: List<String>) {
    File("output").mkdirs()
    File("output/$name").writeText(if (lines.isEmpty()) "" else lines.joinToString("\n") + "\n")
}
fun main() {
    val domain = PDDLParser.domain()
    validateDomain(domain)
    val problems = PDDLParser.problems()
    for (problem in problems) validateProblem(domain, problem)
    val params = Params.read()
    val grounds = problems.map {
        Grounder.ground(domain, it)
    }
    val tags = params.runs.map {
        "${it.first} ${it.second}"
    } + "graphplan"
    val groundingLines = domainReport(domain).toMutableList()
    val plans = mutableListOf<String>()
    val graphLines = mutableListOf<String>()
    val validation = mutableListOf<String>()
    val comparison = mutableListOf("problem,algorithm,heuristic,length,cost,expanded,generated")
    val problemSummary = mutableListOf<String>()
    val tagStats = Array(tags.size) {
        IntArray(4)
    }
    val bests = mutableListOf<Long?>()
    var analyzed = 0
    var validPlans = 0
    for ((index, problem) in problems.withIndex()) {
        val g = grounds[index]
        val unreachable = g.unreachable.isNotEmpty()
        groundingLines.addAll(groundingReport(domain, problem, g))
        val heading = "== problem ${problem.name} =="
        plans.add(heading); validation.add(heading); graphLines.add(heading)
        var landmarks: State = emptySet()
        if (unreachable) plans.add("initial h: unreachable goal")
        else {
            plans.add("initial h: ${hValues(Heuristics.values(g, g.initial))}")
            landmarks = Heuristics.landmarks(g, g.initial) ?: emptySet()
            plans.add("landmarks: ${landmarks.size}")
            for (fact in landmarks.sorted()) plans.add("  ${g.facts[fact].text}")
            val relaxed = Heuristics.relaxed(g, g.initial)
            plans.add("relaxed plan: length=${relaxed.plan.size} cost=${hText(relaxed.value)}")
            for (action in relaxed.plan) plans.add("  ${g.actions[action].text}")
            plans.add(listed("helpful:", relaxed.helpful.map {
                g.actions[it].text
            }))
        }
        val results = params.runs.map {
            (algorithm, heuristic) -> if (unreachable) SearchResult("unreachable goal") else Search.run(g, g.initial, algorithm, heuristic, params.budget, params.weight)
        }.toMutableList()
        if (unreachable) {
            graphLines.add("result: FAIL (unreachable goal)"); results.add(SearchResult("unreachable goal"))
        }
        else {
            val transformedGraph = transformed(g)
            val graph = GraphPlan.run(transformedGraph.actions, transformedGraph.initial, g.goals, params.limit)
            graphLines.add("complementary facts: ${transformedGraph.complements}")
            graphLines.addAll(graph.records)
            if (graph.search.status == "solved") {
                graphLines.add("result: solved levels=${graph.layers.size} length=${graph.search.plan.size} cost=${cost(g, graph.search.plan)} searched=${graph.search.expanded} memo_hits=${graph.hits} tried=${graph.search.generated}")
                for ((k, layer) in graph.layers.withIndex()) graphLines.add(listed("layer ${k + 1}:", layer.map {
                    g.actions[it].text
                }))
            } else graphLines.add("result: FAIL (${graph.search.status}) searched=${graph.search.expanded} memo_hits=${graph.hits} tried=${graph.search.generated}")
            results.add(graph.search)
        }
        graphLines.add("")
        val best = results.filter {
            it.status == "solved"
        }.minOfOrNull {
            cost(g, it.plan)
        }
        bests.add(best)
        val proof = params.runs.indices.firstOrNull {
            i ->
            val pair = params.runs[i]
            (pair == Pair("ucs", "none") || pair == Pair("astar", "hmax")) && results[i].status == "solved"
        }
        val optimal = if (proof != null) cost(g, results[proof].plan).toString()
        else if (results.any {
            it.status in listOf("unreachable goal", "dead end", "exhausted", "unreachable")
        }) "none" else "unknown"
        problemSummary.add("${problem.name}: solved=${results.count { it.status == "solved" }}/${results.size} best=${best ?: "-"} optimal=$optimal")
        val seen = mutableListOf<Pair<List<Int>, String>>()
        for ((i, result) in results.withIndex()) {
            plans.add("-- ${tags[i]} --"); plans.add(resultLine(result, unreachable))
            tagStats[i][2] += result.expanded; tagStats[i][3] += result.generated
            val pair = params.runs.getOrNull(i) ?: Pair("graphplan", "none")
            var length = "-"
            var costText = "-"
            if (result.status == "solved") {
                tagStats[i][0]++
                if (cost(g, result.plan) == best) tagStats[i][1]++
                val block = planBlock(domain, problem, g, result.plan, tags[i], landmarks, seen)
                plans.addAll(block.lines); validation.addAll(block.validation); analyzed++
                if (block.valid) validPlans++
                length = result.plan.size.toString(); costText = cost(g, result.plan).toString()
            }
            comparison.add("${problem.name},${pair.first},${pair.second},$length,$costText,${result.expanded},${result.generated}")
        }
        if (proof != null) plans.addAll(profile(g, results[proof].plan, tags[proof]))
        plans.add(""); validation.add("")
    }
    plans.add("== summary =="); plans.addAll(problemSummary)
    for ((i, tag) in tags.withIndex()) plans.add("$tag: solved=${tagStats[i][0]} best=${tagStats[i][1]} expanded=${tagStats[i][2]} generated=${tagStats[i][3]}")
    validation.add("== candidates ==")
    val candidates = readCandidates()
    var validCandidates = 0
    for ((k, candidate) in candidates.withIndex()) {
        val index = problems.indexOfFirst {
            it.name == candidate.problem
        }
        val problem = problems[index]
        val g = grounds[index]
        val checked = validateSteps(domain, problem, candidate.steps)
        if (checked.status == "valid") {
            validCandidates++
            validation.add("candidate ${k + 1} ${problem.name} ${candidate.label}: ${checked.verdict}")
            val mapped = mapSteps(g, candidate.steps)
            val improved = improve(g, mapped)
            validation.add("  improved: length=${improved.size} cost=${cost(g, improved)} removed=${mapped.size - improved.size} best known=${bests[index] ?: "-"}")
        } else {
            validation.add("candidate ${k + 1} ${problem.name} ${candidate.label}: ${checked.status}")
            validation.addAll(checked.messages.map {
                "  $it"
            })
            if (g.unreachable.isNotEmpty()) {
                validation.add("  repair: FAIL (unreachable goal)"); continue
            }
            val mapped = mapSteps(g, candidate.steps.take(checked.correct))
            var state = g.initial
            for (action in mapped) state = Search.apply(g.actions[action], state)
            val repair = Search.run(g, state, params.repair.first, params.repair.second, params.budget, params.weight)
            if (repair.status != "solved") validation.add("  repair: FAIL (${repair.status})")
            else {
                val repairedPlan = mapped + repair.plan
                val repaired = validateSteps(domain, problem, steps(g, repairedPlan))
                validation.add("  repair: kept=${checked.correct} added=${repair.plan.size} ${repaired.verdict}")
                for ((j, action) in repairedPlan.withIndex()) validation.add("    ${j + 1} ${g.actions[action].text}")
            }
        }
    }
    validation.addAll(listOf("", "== summary ==", "plans: $analyzed valid: $validPlans", "candidates: ${candidates.size} valid: $validCandidates"))
    write("grounding.txt", groundingLines); write("plans.txt", plans); write("graphplan.txt", graphLines)
    write("validation.txt", validation); write("comparison.csv", comparison)
}
