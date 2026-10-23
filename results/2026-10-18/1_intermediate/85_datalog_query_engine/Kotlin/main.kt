private val reserved = setOf("not", "mod", "count", "sum", "min", "max", "retract", "dump", "why", "forget", "listing", "strata", "stats", "check", "predicates", "undo", "halt")

private class Problem(val reason: String) : RuntimeException(reason)

private fun fail(reason: String): Nothing = throw Problem(reason)

private data class Value(val integer: Long? = null, val symbol: String = "") : Comparable<Value> {
    override fun compareTo(other: Value): Int = when {
        integer != null && other.integer != null -> integer.compareTo(other.integer)
        integer != null -> -1
        other.integer != null -> 1
        else -> symbol.compareTo(other.symbol)
    }
    fun text(): String = integer?.toString() ?: if (symbol.matches(Regex("[a-z][A-Za-z0-9_]*")) && symbol !in reserved) symbol else "\"$symbol\""
}
private typealias Tuple = List<Value>
private typealias Environment = Map<String, Value>
private typealias Database = Map<String, Set<Tuple>>
private typealias Derivations = Map<String, Map<Tuple, Pair<Int, Int>>>
private val tupleOrder = Comparator<Tuple> {
    a, b ->
    var result = 0
    for (i in a.indices) {
        result = a[i].compareTo(b[i])
        if (result != 0) break
    }
    result
}
private data class Term(val kind: String, val value: Value = Value(), val name: String = "") {
    fun text(env: Environment? = null): String = when (kind) {
        "constant" -> value.text()
        "variable" -> env?.get(name)?.text() ?: name
        else -> "_"
    }
    fun value(env: Environment): Value? = when (kind) {
        "constant" -> value
        "variable" -> env[name]
        else -> null
    }
    fun variables() = if (kind == "variable") listOf(name) else emptyList()
}
private data class Expression(val kind: String, val term: Term? = null, val left: Expression? = null, val right: Expression? = null) {
    fun text(env: Environment? = null): String = when (kind) {
        "term" -> term!!.text(env)
        "parentheses" -> "(${left!!.text(env)})"
        else -> "${left!!.text(env)} $kind ${right!!.text(env)}"
    }
    fun variables(): List<String> = if (kind == "term") term!!.variables() else left!!.variables() + (right?.variables() ?: emptyList())

    fun anonymous(): Boolean = if (kind == "term") term!!.kind == "anonymous" else left!!.anonymous() || right?.anonymous() == true

    fun value(env: Environment): Value? {
        if (kind == "term") return term!!.value(env)
        if (kind == "parentheses") return left!!.value(env)
        val a = left!!.value(env)?.integer ?: return null
        val b = right!!.value(env)?.integer ?: return null
        val n = when (kind) {
            "+" -> a + b
            "-" -> a - b
            "*" -> a * b
            else -> {
                if (b == 0L) return null
                val q = a / b - if (a % b != 0L && (a < 0) != (b < 0)) 1 else 0
                if (kind == "/") q else a - b * q
            }
        }
        return Value(n)
    }
}
private data class Atom(val name: String, val terms: List<Term>) {
    fun text(env: Environment? = null) = name + if (terms.isEmpty()) "" else terms.joinToString(", ", "(", ")") {
        it.text(env)
    }
    fun variables() = terms.flatMap {
        it.variables()
    }
    fun tuple(env: Environment) = terms.map {
        it.value(env)!!
    }
    fun matching(tuple: Tuple, env: Environment): Environment? {
        val result = env.toMutableMap()
        for ((term, value) in terms.zip(tuple)) {
            if (term.kind == "constant" && term.value != value) return null
            if (term.kind == "variable") {
                if (term.name in result && result[term.name] != value) return null
                result[term.name] = value
            }
        }
        return result
    }
}
private fun tupleText(name: String, tuple: Tuple) = Atom(name, tuple.map {
    Term("constant", it)
}).text()

private data class Literal(val atom: Atom? = null, val negative: Boolean = false, val op: String = "", val left: Expression? = null, val right: Expression? = null) {
    val positive get() = atom != null && !negative

    fun variables() = atom?.variables() ?: (left!!.variables() + right!!.variables())

    fun text(env: Environment? = null) = if (atom != null) (if (negative) "not " else "") + atom.text(env) else "${left!!.text(env)} $op ${right!!.text(env)}"

    fun holds(env: Environment, data: Database): Boolean {
        if (atom != null) return !negative || data.getValue(atom.name).none {
            atom.matching(it, env) != null
        }
        val a = left!!.value(env) ?: return false
        val b = right!!.value(env) ?: return false
        if (op == "=") return a == b
        if (op == "!=") return a != b
        val x = a.integer ?: return false
        val y = b.integer ?: return false
        return when (op) {
            "<" -> x < y
            "<=" -> x <= y
            ">" -> x > y
            else -> x >= y
        }
    }
}
private data class Rule(val number: Int = 0, val head: Atom? = null, val body: List<Literal>) {
    fun text() = (head?.let {
        it.text() + " "
    } ?: "") + ":- " + body.joinToString(", ") {
        it.text()
    } + "."

    fun variables() = (head?.variables() ?: emptyList()) + body.flatMap {
        it.variables()
    }
    fun atoms() = listOfNotNull(head) + body.mapNotNull {
        it.atom
    }
}
private data class Token(val kind: String, val text: String)

private fun wordCharacter(c: Char) = c in 'a'..'z' || c in 'A'..'Z' || c in '0'..'9' || c == '_'

private fun lex(line: String): List<Token> {
    val result = mutableListOf<Token>()
    var at = 0
    while (at < line.length) {
        if (line[at] == ' ') {
            at++
            continue
        }
        if (line[at] == '%') break
        val start = at
        val kind: String
        if (line[at] == '"') {
            at++
            while (at < line.length && line[at] != '"') at++
            if (at == line.length) fail("unterminated string")
            at++
            kind = "string"
        } else if (at + 1 < line.length && line.substring(at, at + 2) in setOf(":-", "?-", "!=", "<=", ">=")) {
            at += 2
            kind = line.substring(start, at)
        } else if (line[at] in "(),.:=<>+-*/") {
            kind = line[at++].toString()
        } else if (wordCharacter(line[at])) {
            at++
            while (at < line.length && wordCharacter(line[at])) at++
            val word = line.substring(start, at)
            kind = when {
                word[0] in 'a'..'z' -> if (word in reserved) word else "name"
                word[0] in 'A'..'Z' -> "variable"
                word == "_" -> "anonymous"
                word.all {
                    it in '0'..'9'
                } -> {
                    if (word.toLong() > 1000000000L) fail("integer out of range '$word'")
                    "integer"
                } else -> fail("bad token '$word'")
            }
        } else fail("bad character '${line[at]}'")
        result.add(Token(kind, line.substring(start, at)))
    }
    return result
}
private data class Statement(val kind: String, val rule: Rule? = null, val atom: Atom? = null, val aggregate: String = "", val argument: String = "")

private class Parser(val tokens: List<Token>) {
    var at = 0
    val kind get() = tokens.getOrNull(at)?.kind ?: "end"

    fun error(): Nothing = fail(tokens.getOrNull(at)?.let {
        "syntax error at '${it.text}'"
    } ?: "syntax error at end of line")

    fun take(expected: String): Token {
        if (kind != expected) error()
        return tokens[at++]
    }
    fun term(): Term = when (kind) {
        "name" -> Term("constant", Value(symbol = take("name").text))
        "string" -> Term("constant", Value(symbol = take("string").text.drop(1).dropLast(1)))
        "integer" -> Term("constant", Value(take("integer").text.toLong()))
        "-" -> {
            take("-")
            Term("constant", Value(-take("integer").text.toLong()))
        }
        "variable" -> Term("variable", name = take("variable").text)
        "anonymous" -> {
            take("anonymous")
            Term("anonymous")
        } else -> error()
    }
    fun atom(): Atom {
        val name = take("name").text
        val terms = mutableListOf<Term>()
        if (kind == "(") {
            take("(")
            terms.add(term())
            while (kind == ",") {
                take(",")
                terms.add(term())
            }
            take(")")
        }
        return Atom(name, terms)
    }
    fun factor(): Expression = if (kind == "(") {
        take("(")
        val e = expression()
        take(")")
        Expression("parentheses", left = e)
    } else Expression("term", term())

    fun product(): Expression {
        var e = factor()
        while (kind in setOf("*", "/", "mod")) {
            val op = tokens[at++].text
            e = Expression(op, left = e, right = factor())
        }
        return e
    }
    fun expression(): Expression {
        var e = product()
        while (kind in setOf("+", "-")) {
            val op = tokens[at++].text
            e = Expression(op, left = e, right = product())
        }
        return e
    }
    fun literal(): Literal {
        if (kind == "not") {
            take("not")
            return Literal(atom(), true)
        }
        val following = tokens.getOrNull(at + 1)?.kind ?: "end"
        if (kind == "name" && following !in setOf("=", "!=", "<", "<=", ">", ">=", "+", "-", "*", "/", "mod")) return Literal(atom())
        val left = expression()
        if (kind !in setOf("=", "!=", "<", "<=", ">", ">=")) error()
        val op = tokens[at++].text
        return Literal(op = op, left = left, right = expression())
    }
    fun body(): List<Literal> {
        val result = mutableListOf(literal())
        while (kind == ",") {
            take(",")
            result.add(literal())
        }
        return result
    }
    fun statement(): Statement {
        val result = when (kind) {
            "name" -> {
                val head = atom()
                val body = if (kind == ":-") {
                    take(":-")
                    body()
                } else emptyList()
                Statement("clause", Rule(head = head, body = body))
            }
            ":-" -> {
                take(":-")
                Statement("clause", Rule(body = body()))
            }
            "?-" -> {
                take("?-")
                var aggregate = ""
                var variable = ""
                if (kind in setOf("count", "sum", "min", "max")) {
                    aggregate = tokens[at++].text
                    if (aggregate != "count") {
                        variable = take("variable").text
                        take(":")
                    }
                }
                Statement("query", Rule(body = body()), aggregate = aggregate, argument = variable)
            }
            "retract", "why" -> {
                val command = tokens[at++].text
                Statement(command, atom = atom())
            }
            "dump", "forget", "listing", "strata", "stats", "check", "predicates", "undo", "halt" -> {
                val command = tokens[at++].text
                val argument = when {
                    command == "dump" -> take("name").text
                    command == "forget" -> take("integer").text
                    command == "listing" && kind == "name" -> take("name").text
                    else -> ""
                }
                Statement(command, argument = argument)
            } else -> error()
        }
        take(".")
        if (kind != "end") error()
        return result
    }
}
private data class State(val predicates: Map<String, Int> = emptyMap(), val facts: Database = emptyMap(), val rules: List<Rule> = emptyList())

private fun safety(rule: Rule, aggregate: String = "") {
    if (rule.head?.terms?.any {
        it.kind == "anonymous"
    } == true) fail("anonymous variable in head")
    if (rule.body.any {
        it.atom == null && (it.left!!.anonymous() || it.right!!.anonymous())
    })
    fail("anonymous variable in comparison")
    val bound = rule.body.filter {
        it.positive
    }.flatMap {
        it.variables()
    }.toSet()
    val required = (rule.head?.variables() ?: if (aggregate.isEmpty()) emptyList() else listOf(aggregate)) + rule.body.filter {
        !it.positive
    }.flatMap {
        it.variables()
    }
    for (name in required) if (name !in bound) fail("unsafe variable $name")
}
private fun strata(state: State): Map<String, Int>? {
    val result = state.predicates.keys.associateWith {
        0
    }.toMutableMap()
    if (result.isEmpty()) return result
    repeat(result.size) {
        var changed = false
        for (r in state.rules) if (r.head != null) for (l in r.body) if (l.atom != null) {
            val value = result.getValue(l.atom.name) + if (l.negative) 1 else 0
            if (value > result.getValue(r.head.name)) {
                result[r.head.name] = value
                changed = true
            }
        }
        if (!changed) return result
    }
    return null
}
private fun solutions(body: List<Literal>, data: Database, derivations: Derivations, before: Int? = null): Set<Environment> {
    val output = mutableSetOf<Environment>()

    fun visit(remaining: List<Int>, env: Environment) {
        for (l in body) if (!l.positive && l.variables().all {
            it in env
        } && !l.holds(env, data)) return
        if (remaining.isEmpty()) {
            output.add(env)
            return
        }
        var best = -1
        var candidates = emptySet<Environment>()
        for (i in remaining) {
            val a = body[i].atom!!
            val possible = data.getValue(a.name).asSequence().filter {
                before == null || derivations.getValue(a.name).getValue(it).first < before
            }.mapNotNull {
                a.matching(it, env)
            }.toSet()
            if (best < 0 || possible.size < candidates.size) {
                best = i
                candidates = possible
            }
        }
        val rest = remaining.filter {
            it != best
        }
        for (next in candidates) visit(rest, next)
    }
    visit(body.indices.filter {
        body[it].positive
    },
    emptyMap())
    return output
}
private class Model(val state: State) {
    val levels = strata(state)!!
    val data = state.facts.mapValues {
        it.value.toMutableSet()
    }.toMutableMap()
    val derivations = state.facts.mapValues {
        (_, ts) -> ts.associateWith {
            0 to 0
        }.toMutableMap()
    }.toMutableMap()
    val rounds = IntArray((levels.values.maxOrNull() ?: 0) + 1)
    val additions = IntArray(rounds.size)
    init {
        var serial = 0
        for (k in rounds.indices) while (true) {
            val added = mutableMapOf<Pair<String, Tuple>, Int>()
            for (r in state.rules) {
                val h = r.head ?: continue
                if (levels[h.name] != k) continue
                for (env in solutions(r.body, data, derivations)) {
                    val tuple = h.tuple(env)
                    if (tuple !in data.getValue(h.name)) {
                        val key = h.name to tuple
                        added[key] = minOf(added[key] ?: r.number, r.number)
                    }
                }
            }
            if (added.isEmpty()) break
            serial++
            rounds[k]++
            additions[k] += added.size
            for ((key, rule) in added) {
                data.getValue(key.first).add(key.second)
                derivations.getValue(key.first)[key.second] = serial to rule
            }
        }
    }
    fun answers(body: List<Literal>): Pair<List<String>, List<Tuple>> {
        val names = body.flatMap {
            it.variables()
        }.distinct()
        val answers = solutions(body, data, derivations).map {
            env -> names.map {
                env.getValue(it)
            }
        }.distinct().sortedWith(tupleOrder)
        return names to answers
    }
    fun proof(name: String, tuple: Tuple, depth: Int, output: MutableList<String>) {
        val round = derivations.getValue(name).getValue(tuple).first
        val prefix = "  ".repeat(depth) + tupleText(name, tuple)
        if (round == 0) {
            output.add("$prefix [fact]")
            return
        }
        for (r in state.rules.filter {
            it.head?.name == name
        }) {
            val order = r.variables().distinct()
            val candidates = solutions(r.body, data, derivations, round).filter {
                r.head!!.tuple(it) == tuple
            }.sortedWith {
                a, b -> tupleOrder.compare(order.map {
                    a.getValue(it)
                },
                order.map {
                    b.getValue(it)
                })
            }
            val env = candidates.firstOrNull() ?: continue
            output.add("$prefix [rule ${r.number}]")
            for (l in r.body) {
                if (l.positive) {
                    val a = l.atom!!
                    val child = data.getValue(a.name).filter {
                        derivations.getValue(a.name).getValue(it).first < round && a.matching(it, env) != null
                    }.minWith(tupleOrder)
                    proof(a.name, child, depth + 1, output)
                } else output.add("  ".repeat(depth + 1) + l.text(env))
            }
            return
        }
    }
}
private fun answerText(names: List<String>, tuple: Tuple) = names.zip(tuple).joinToString(", ") {
    (n, v) -> "$n = ${v.text()}"
}
private class Engine {
    var state = State()
    var nextRule = 1
    val history = mutableListOf<Pair<State, Int>>()

    fun predicateCheck(atoms: List<Atom>, register: Boolean): Map<String, Int> {
        val predicates = state.predicates.toMutableMap()
        for (a in atoms) {
            val arity = predicates[a.name]
            if (arity != null && arity != a.terms.size) fail("arity mismatch for ${a.name}: expected $arity, got ${a.terms.size}")
            if (arity == null) {
                if (!register) fail("unknown predicate ${a.name}")
                predicates[a.name] = a.terms.size
            }
        }
        return predicates
    }
    fun save(line: Int) {
        history.add(state to line)
    }
    fun clause(rule: Rule, line: Int): List<String> {
        val predicates = predicateCheck(rule.atoms(), true)
        safety(rule)
        if (rule.body.isEmpty()) {
            val h = rule.head!!
            val tuple = h.tuple(emptyMap())
            if (tuple !in (state.facts[h.name] ?: emptySet())) {
                save(line)
                state = state.copy(predicates = predicates, facts = state.facts + (h.name to ((state.facts[h.name] ?: emptySet()) + setOf(tuple))))
            }
            return emptyList()
        }
        state.rules.firstOrNull {
            it.text() == rule.text()
        }?.let {
            fail("duplicate of rule ${it.number}")
        }
        val numbered = rule.copy(number = nextRule)
        val proposed = State(predicates, predicates.keys.associateWith {
            state.facts[it] ?: emptySet()
        },
        state.rules + numbered)
        if (strata(proposed) == null) fail("negative cycle through ${rule.head!!.name}")
        save(line)
        state = proposed
        nextRule++
        val all = rule.variables()
        return all.distinct().filter {
            n -> all.count {
                it == n
            } == 1
        }.map {
            "WARNING line $line: singleton variable $it"
        }
    }
    fun execute(statement: Statement, line: Int): List<String> {
        val kind = statement.kind
        if (kind == "clause") return clause(statement.rule!!, line)
        if (kind == "query") {
            val rule = statement.rule!!
            predicateCheck(rule.atoms(), false)
            safety(rule, statement.argument)
            val (names, answers) = Model(state).answers(rule.body)
            if (statement.aggregate == "count") return listOf(answers.size.toString())
            if (statement.aggregate in setOf("sum", "min", "max")) {
                val i = names.indexOf(statement.argument)
                if (statement.aggregate == "sum") {
                    var total = 0L
                    for (row in answers) total += row[i].integer ?: fail("non-integer value in sum")
                    return listOf(total.toString())
                }
                val values = answers.map {
                    it[i]
                }.sorted()
                return listOf(if (values.isEmpty()) "no answers" else (if (statement.aggregate == "min") values.first() else values.last()).text())
            }
            if (names.isEmpty()) return listOf(if (answers.isEmpty()) "false." else "true.")
            return answers.map {
                answerText(names, it)
            } + "${answers.size} ${if (answers.size == 1) "answer" else "answers"}"
        }
        if (kind == "retract" || kind == "why") {
            val a = statement.atom!!
            predicateCheck(listOf(a), false)
            if (kind == "retract") {
                val removed = state.facts.getValue(a.name).filter {
                    a.matching(it, emptyMap()) != null
                }.toSet()
                if (removed.isEmpty()) fail("no matching facts")
                save(line)
                state = state.copy(facts = state.facts + (a.name to (state.facts.getValue(a.name) - removed)))
                return listOf("${removed.size} ${if (removed.size == 1) "fact" else "facts"} retracted")
            }
            if (a.terms.any {
                it.kind != "constant"
            })
            fail("why needs a ground atom")
            val model = Model(state)
            val tuple = a.tuple(emptyMap())
            if (tuple !in model.data.getValue(a.name)) return listOf("false.")
            val output = mutableListOf<String>()
            model.proof(a.name, tuple, 0, output)
            return output
        }
        return command(kind, statement.argument, line)
    }
    fun command(command: String, argument: String, line: Int): List<String> {
        if (command == "undo") {
            if (history.isEmpty()) fail("nothing to undo")
            val (previous, number) = history.removeAt(history.lastIndex)
            state = previous
            return listOf("undid line $number")
        }
        if (command == "forget") {
            val n = argument.toInt()
            if (state.rules.none {
                it.number == n
            })
            fail("no rule $n")
            save(line)
            state = state.copy(rules = state.rules.filter {
                it.number != n
            })
            return emptyList()
        }
        if (command in setOf("dump", "listing") && argument.isNotEmpty() && argument !in state.predicates) fail("unknown predicate $argument")
        if (command == "listing") return state.rules.filter {
            argument.isEmpty() || it.head?.name == argument
        }.map {
            "${it.number}: ${it.text()}"
        }.ifEmpty {
            listOf("no rules")
        }
        val model = Model(state)
        val output = mutableListOf<String>()
        when (command) {
            "dump" -> {
                val tuples = model.data.getValue(argument).sortedWith(tupleOrder)
                output.addAll(tuples.map {
                    tupleText(argument, it) + "."
                })
                output.add("${tuples.size} ${if (tuples.size == 1) "tuple" else "tuples"}")
            }
            "strata" -> {
                if (state.predicates.isEmpty()) return listOf("no predicates")
                val edges = state.predicates.keys.associateWith {
                    p -> state.rules.filter {
                        it.head?.name == p
                    }.flatMap {
                        it.body.mapNotNull {
                            l -> l.atom?.name
                        }
                    }
                }
                fun recursive(p: String): Boolean {
                    val visited = mutableSetOf<String>()

                    fun visit(n: String): Boolean = visited.add(n) && edges.getValue(n).any {
                        it == p || visit(it)
                    }
                    return visit(p)
                }
                for (k in model.rounds.indices) output.add("stratum $k: " + model.levels.keys.filter {
                    model.levels[it] == k
                }.sorted().joinToString(", ") {
                    it + if (recursive(it)) "*" else ""
                })
            }
            "stats" -> {
                val constraints = state.rules.count {
                    it.head == null
                }
                output.add("facts ${state.facts.values.sumOf { it.size }}, rules ${state.rules.size - constraints}, constraints $constraints, tuples ${model.data.values.sumOf { it.size }}")
                if (state.predicates.isNotEmpty()) for (k in model.rounds.indices) output.add("stratum $k: rounds ${model.rounds[k]}, new ${model.additions[k]}")
                for (r in state.rules.filter {
                    it.head != null
                })
                output.add("rule ${r.number}: new ${model.derivations.values.sumOf { d -> d.values.count { it.second == r.number } }}")
            }
            "predicates" -> {
                if (state.predicates.isEmpty()) return listOf("no predicates")
                for (p in state.predicates.keys.sorted()) output.add("$p/${state.predicates.getValue(p)}: facts ${state.facts.getValue(p).size}, rules ${state.rules.count { it.head?.name == p }}, tuples ${model.data.getValue(p).size}")
            }
            "check" -> {
                for (r in state.rules.filter {
                    it.head == null
                }) {
                    val (names, answers) = model.answers(r.body)
                    output.add(if (answers.isEmpty()) "constraint ${r.number}: ok" else "constraint ${r.number}: ${answers.size} ${if (answers.size == 1) "violation" else "violations"}")
                    if (names.isNotEmpty()) output.addAll(answers.map {
                        "  " + answerText(names, it)
                    })
                }
                if (output.isEmpty()) output.add("no constraints")
            }
        }
        return output
    }
}
fun main() {
    val engine = Engine()
    var lineNumber = 0
    while (true) {
        val line = readLine() ?: break
        lineNumber++
        try {
            val tokens = lex(line)
            if (tokens.isEmpty()) continue
            val statement = Parser(tokens).statement()
            if (statement.kind == "halt") break
            engine.execute(statement, lineNumber).forEach(::println)
        } catch (e: Problem) {
            println("ERROR line $lineNumber: ${e.reason}")
        }
    }
}
