import java.io.File
class Writer(val store: Store, val quoted: Boolean) {
    val names = mutableMapOf<Int, String>()
    var generated = 0
    fun atom(name: String): String {
        val plain = name.isNotEmpty() && lower(name[0]) && name.all {
            alpha(it) || digit(it) || it == '_'
        } || name.isNotEmpty() && name != "." && name.all(::symbol) || name in listOf("[]", "!", ";")
        if (!quoted || plain) return name
        return buildString {
            append(39.toChar())
            for (c in name) {
                when (c.code) {
                    92, 39 -> {
                        append(92.toChar())
                        append(c)
                    }
                    10 -> {
                        append(92.toChar())
                        append('n')
                    }
                    9 -> {
                        append(92.toChar())
                        append('t')
                    }
                    else -> append(c)
                }
            }
            append(39.toChar())
        }
    }
    fun term(source: Term, limit: Int = 1200, operand: Boolean = false): String = when (val value = store.dereference(source)) {
        is Term.Integer -> value.value.toString()
        is Term.Variable -> names.getOrPut(value.id) {
            generated++
            "_G$generated"
        }
        is Term.Atom -> {
            val text = atom(value.name)
            if (operand && isOperator(value.name)) "($text)" else text
        }
        is Term.Compound -> {
            val name = value.name
            val args = value.args
            if (name == "." && args.size == 2) {
                val (elements, tail) = store.parts(value)
                "[" + elements.joinToString(",") {
                    term(it, 999)
                } + (if (tail == Term.Atom("[]")) "" else "|" + term(tail, 999)) + "]"
            }
            else {
                val infix = if (args.size == 2) operatorInfo(name) else null
                val prefix = if (args.size == 1) prefixPriority(name) else null
                if (infix != null) {
                    val a = term(args[0], infix.left, true)
                    val b = term(args[1], infix.right, true)
                    val text = if (name == ",") "$a,$b" else if (alpha(name[0])) "$a $name $b" else a + (if (a.lastOrNull()?.let(::symbol) == true) " " else "") + name + (if (b.firstOrNull()?.let(::symbol) == true) " " else "") + b
                    if (infix.priority > limit) "($text)" else text
                }
                else if (prefix != null) {
                    val argument = term(args[0], prefix, true)
                    val space = argument.firstOrNull()?.let {
                        symbol(it) || digit(it) || it == '('
                    } == true
                    val text = name + (if (space) " " else "") + argument
                    if (prefix > limit) "($text)" else text
                }
                else atom(name) + "(" + args.joinToString(",") {
                    term(it, 999)
                } + ")"
            }
        }
    }
}
fun writeTerm(term: Term, store: Store, quoted: Boolean = true): String = Writer(store, quoted).term(term)
fun indicatorText(key: Indicator): String = writeTerm(indicatorTerm(key), Store())
fun goalConversion(term: Term, store: Store): Term? = when (val value = store.dereference(term)) {
    is Term.Variable -> Term.Compound("call", listOf(value))
    is Term.Integer -> null
    is Term.Compound -> if (value.name in listOf(",", ";", "->") && value.args.size == 2) {
        val left = goalConversion(value.args[0], store)
        val right = if (left == null) null else goalConversion(value.args[1], store)
        if (left == null || right == null) null else Term.Compound(value.name, listOf(left, right))
    } else value
    else -> value
}
class Consult {
    val database = Database()
    val store = Store()
    val reports = mutableListOf<String>()
    val counts = List(2) {
        IntArray(3)
    }
    fun warning(file: Int, line: Int, message: String) {
        counts[file][2]++
        reports.add("${if (file == 0) "prelude.pl" else "program.pl"}:$line: warning: $message")
    }
    fun read(file: Int, text: String) {
        val name = if (file == 0) "prelude.pl" else "program.pl"
        val tokens = lex(text, 1)
        val source = text.split(10.toChar())
        var start = 0
        var last: Int? = null
        val discontiguous = mutableSetOf<Int>()
        while (tokens[start].kind != "eof") {
            val line = tokens[start].line
            val parsed = try {
                Reader(tokens, start, store).clause()
            } catch (error: ReadError) {
                counts[file][1]++
                reports.add("$name:${error.line}:${error.column}: syntax error: ${error.reason}")
                if (!error.eof) {
                    reports.add("    " + source[error.line - 1])
                    reports.add(" ".repeat(error.column + 3) + "^")
                }
                start = error.index
                while (tokens[start].kind != "eof" && tokens[start].kind != "end") start++
                if (tokens[start].kind == "end") start++
                continue
            }
            start = parsed.next
            val clause = parsed.term as? Term.Compound
            val rule = clause != null && clause.name == ":-" && clause.args.size == 2
            val head = if (rule) clause!!.args[0] else parsed.term
            val body = if (rule) clause!!.args[1] else null
            var error: Term? = if (head is Term.Variable) Term.Atom("instantiation_error") else if (head is Term.Integer) typeError("callable", head) else null
            val key = head.indicator
            if (error == null && key != null && (control(key) || builtin(key))) error = Term.Compound("permission_error", listOf(Term.Atom("modify"), Term.Atom("static_procedure"), indicatorTerm(key)))
            val converted = body?.let {
                goalConversion(it, store)
            }
            if (error == null && body != null && converted == null) error = typeError("callable", body)
            if (error != null) {
                counts[file][1]++
                reports.add("$name:$line: error: ${writeTerm(error, store)}")
                continue
            }
            val indicator = key!!
            val index = database.find(indicator) ?: database.predicates.size.also {
                database.predicates.add(Predicate(indicator))
            }
            val predicate = database.predicates[index]
            if (file == 1 && predicate.clauses.any {
                it.file == "prelude.pl"
            }) {
                warning(file, line, "redefining prelude procedure " + indicatorText(indicator))
                predicate.clauses.clear()
            }
            if (predicate.clauses.any {
                it.file == name
            } && last != index && discontiguous.add(index)) warning(file, line, "clauses of ${indicatorText(indicator)} are not together")
            predicate.clauses.add(Clause(head, converted, name, line))
            last = index
            counts[file][0]++
            val singletons = parsed.variables.filter {
                !it.name.startsWith("_") && it.count == 1
            }.map {
                it.name
            }
            if (singletons.isNotEmpty()) warning(file, line, "singleton variables: " + singletons.joinToString(", "))
            val repeated = parsed.variables.filter {
                it.name.startsWith("_") && it.name.length > 1 && it.count >= 2
            }.map {
                it.name
            }
            if (repeated.isNotEmpty()) warning(file, line, "variables starting with _ occur more than once: " + repeated.joinToString(", "))
        }
    }
    fun undefined() {
        fun visit(term: Term, result: MutableList<Indicator>) {
            val key = term.indicator ?: return
            val args = term.arguments
            if (key.name in listOf(",", ";", "->") && key.arity == 2) {
                visit(args[0], result)
                visit(args[1], result)
            }
            else if (key.name in listOf(backslash + "+", "call") && key.arity == 1) visit(args[0], result)
            else if (key == Indicator("findall", 3)) visit(args[1], result)
            else if (key == Indicator("catch", 3)) {
                visit(args[0], result)
                visit(args[2], result)
            }
            else if (!control(key) && !builtin(key)) result.add(key)
        }
        val warnings = mutableListOf<Triple<Int, Int, String>>()
        val reported = mutableSetOf<Indicator>()
        for (predicate in database.predicates) for (clause in predicate.clauses) {
            val body = clause.body ?: continue
            val indicators = mutableListOf<Indicator>()
            visit(body, indicators)
            for (key in indicators) {
                if (database.find(key) == null && reported.add(key)) warnings.add(Triple(if (clause.file == "prelude.pl") 0 else 1, clause.line, "undefined procedure ${indicatorText(key)} called from ${indicatorText(predicate.indicator)}"))
            }
        }
        for ((file, line, message) in warnings) warning(file, line, message)
        for ((i, name) in listOf("prelude.pl", "program.pl").withIndex()) reports.add("$name: clauses=${counts[i][0]} errors=${counts[i][1]} warnings=${counts[i][2]}")
        reports.add("database: predicates=${database.predicates.size} clauses=${database.predicates.sumOf { it.clauses.size }}")
    }
    fun listing(): List<String> {
        val output = mutableListOf<String>()
        for ((p, predicate) in database.predicates.withIndex()) {
            if (p > 0) output.add("")
            for (clause in predicate.clauses) {
                val variables = store.variables(listOfNotNull(clause.head, clause.body))
                val counts = variables.groupingBy {
                    it
                }.eachCount()
                val writer = Writer(store, true)
                var number = 0
                for (id in variables) {
                    if (id !in writer.names) {
                        if (counts[id] == 1) writer.names[id] = "_" else {
                            writer.names[id] = (65 + number % 26).toChar().toString() + if (number >= 26) (number / 26).toString() else ""
                            number++
                        }
                    }
                }
                val head = writer.term(clause.head)
                if (clause.body == null) output.add("$head.") else {
                    output.add("$head :-")
                    val goals = mutableListOf<Term>()
                    var rest: Term = clause.body
                    while (rest is Term.Compound && rest.name == "," && rest.args.size == 2) {
                        goals.add(rest.args[0])
                        rest = rest.args[1]
                    }
                    goals.add(rest)
                    for ((i, goal) in goals.withIndex()) output.add("    " + writer.term(goal, 999) + if (i + 1 == goals.size) "." else ",")
                }
            }
        }
        return output
    }
}
data class Profile(var calls: Int = 0, var tries: Int = 0)
sealed interface Goal {
    data class Value(val term: Term) : Goal
    data class Ite(val height: Int) : Goal
    data class Naf(val height: Int) : Goal
    data class Exit(val point: Choice) : Goal
    data class Collect(val point: Choice) : Goal
}
data class Entry(val goal: Goal, val barrier: Int, val context: Choice?)
fun entry(term: Term, barrier: Int, context: Choice?): Entry = Entry(Goal.Value(term), barrier, context)
class Goals(val entry: Entry, val next: Goals?)
sealed interface ChoiceKind {
    data object Alternative : ChoiceKind
    data class Clauses(val predicate: Int, val candidates: List<Int>, var next: Int, val goal: Term, val barrier: Int, val context: Choice?) : ChoiceKind
    data class Between(val high: Long, val variable: Term, var next: Long) : ChoiceKind
    data class Length(val tail: Term, val length: Term, val prefix: Int, var next: Int) : ChoiceKind
    data class Catcher(val catcher: Term, val recovery: Term, val parent: Choice?) : ChoiceKind
    data class Findall(val template: Term, val result: Term, val values: MutableList<Term> = mutableListOf()) : ChoiceKind
}
class Choice(val mark: Int, val resume: Goals?, val kind: ChoiceKind)
class Engine(val database: Database, val profile: MutableMap<Indicator, Profile>, val store: Store, query: Term) {
    val trail = Trail()
    var goals: Goals? = Goals(entry(Term.Compound("call", listOf(query)), 0, null), null)
    val choices = mutableListOf<Choice>()
    var solutions = 0
    var inferences = 0
    var choicepoints = 0
    var backtracks = 0
    var limitReached = false
    val output = StringBuilder()
    val answers = mutableListOf<String>()
    fun push(kind: ChoiceKind, resume: Goals?): Choice {
        choicepoints++
        val result = Choice(trail.mark, resume, kind)
        choices.add(result)
        return result
    }
    fun prepend(entries: List<Entry>) {
        for (entry in entries.asReversed()) goals = Goals(entry, goals)
    }
    fun cut(height: Int) {
        while (choices.size > height) choices.removeAt(choices.lastIndex)
    }
    fun inference(key: Indicator): Boolean {
        if (inferences == 20000) {
            limitReached = true
            return false
        }
        inferences++
        profile.getOrPut(key) {
            Profile()
        }.calls++
        return true
    }
    fun unify(a: Term, b: Term): Boolean = trail.unify(a, b, store)
    fun tryClause(predicate: Int, clause: Int, goal: Term, barrier: Int, context: Choice?, resume: Goals?): Boolean {
        profile.getOrPut(database.predicates[predicate].indicator) {
            Profile()
        }.tries++
        val (head, body) = database.copy(predicate, clause, store)
        if (!unify(head, goal)) return false
        goals = resume
        if (body != null) goals = Goals(entry(body, barrier, context), goals)
        return true
    }
    fun execute(current: Entry): Boolean {
        val barrier = current.barrier
        val context = current.context
        val term = when (val goal = current.goal) {
            is Goal.Ite -> {
                cut(goal.height)
                return true
            }
            is Goal.Naf -> {
                cut(goal.height)
                return false
            }
            is Goal.Exit -> {
                if (choices.lastOrNull() === goal.point) choices.removeAt(choices.lastIndex)
                return true
            }
            is Goal.Collect -> {
                val point = goal.point.kind as ChoiceKind.Findall
                point.values.add(store.copy(point.template))
                return false
            }
            is Goal.Value -> store.dereference(goal.term)
        }
        val key = term.indicator!!
        val args = term.arguments
        if (control(key)) {
            when (key.name) {
                "," -> prepend(listOf(entry(args[0], barrier, context), entry(args[1], barrier, context)))
                "!" -> cut(barrier)
                ";" -> {
                    val height = choices.size
                    push(ChoiceKind.Alternative, Goals(entry(args[1], barrier, context), goals))
                    val left = store.dereference(args[0])
                    if (left is Term.Compound && left.name == "->" && left.args.size == 2) prepend(listOf(entry(left.args[0], height + 1, context), Entry(Goal.Ite(height), barrier, context), entry(left.args[1], barrier, context))) else prepend(listOf(entry(left, barrier, context)))
                }
                "->" -> {
                    val height = choices.size
                    prepend(listOf(entry(args[0], height, context), Entry(Goal.Ite(height), barrier, context), entry(args[1], barrier, context)))
                }
                backslash + "+" -> {
                    val height = choices.size
                    push(ChoiceKind.Alternative, goals)
                    prepend(listOf(entry(Term.Compound("call", listOf(args[0])), barrier, context), Entry(Goal.Naf(height), barrier, context)))
                }
                "call" -> {
                    val first = store.dereference(args[0])
                    if (first is Term.Variable) throw PrologError(errorBall(Term.Atom("instantiation_error"), key))
                    if (first is Term.Integer) throw PrologError(errorBall(typeError("callable", first), key))
                    val applied = if (args.size == 1) first else if (first is Term.Atom) Term.Compound(first.name, args.drop(1)) else {
                        first as Term.Compound
                        Term.Compound(first.name, first.args + args.drop(1))
                    }
                    val converted = goalConversion(applied, store) ?: throw PrologError(errorBall(typeError("callable", applied), key))
                    prepend(listOf(entry(converted, choices.size, context)))
                }
                "catch" -> {
                    val point = push(ChoiceKind.Catcher(args[1], args[2], context), goals)
                    prepend(listOf(entry(Term.Compound("call", listOf(args[0])), barrier, point), Entry(Goal.Exit(point), barrier, context)))
                }
            }
            return true
        }
        if (!inference(key)) return false
        when (key) {
            Indicator("findall", 3) -> {
                val point = push(ChoiceKind.Findall(args[0], args[2]), goals)
                goals = null
                prepend(listOf(entry(Term.Compound("call", listOf(args[1])), barrier, context), Entry(Goal.Collect(point), barrier, context)))
                return true
            }
            Indicator("throw", 1) -> {
                val ball = store.dereference(args[0])
                throw PrologError(if (ball is Term.Variable) errorBall(Term.Atom("instantiation_error"), key) else ball)
            }
            Indicator("between", 3) -> {
                try {
                    val low = integer(args[0], store)
                    val high = integer(args[1], store)
                    val variable = store.dereference(args[2])
                    if (variable is Term.Integer) return variable.value in low..high
                    if (variable !is Term.Variable) throw PrologError(typeError("integer", variable))
                    if (low > high) return false
                    if (low < high) push(ChoiceKind.Between(high, variable, low + 1), goals)
                    return unify(variable, Term.Integer(low))
                } catch (error: PrologError) {
                    throw PrologError(errorBall(error.term, key))
                }
            }
            Indicator("length", 2) -> {
                val length = store.dereference(args[1])
                if (length !is Term.Variable) {
                    if (length !is Term.Integer) throw PrologError(errorBall(typeError("integer", length), key))
                    if (length.value < 0) throw PrologError(errorBall(domainError("not_less_than_zero", length), key))
                }
                val (elements, tail) = store.parts(args[0])
                val prefix = elements.size
                if (tail == Term.Atom("[]")) return unify(args[1], Term.Integer(prefix.toLong()))
                if (tail !is Term.Variable) throw PrologError(errorBall(typeError("list", args[0]), key))
                if (length is Term.Integer) {
                    if (length.value < prefix) return false
                    return unify(tail, list(List((length.value - prefix).toInt()) {
                        store.fresh()
                    }))
                }
                push(ChoiceKind.Length(tail, length, prefix, prefix + 1), goals)
                return unify(tail, Term.Atom("[]")) && unify(length, Term.Integer(prefix.toLong()))
            }
            else -> {
                if (builtin(key)) {
                    try {
                        return deterministic(key, args, store, trail, output)
                    } catch (error: PrologError) {
                        throw PrologError(errorBall(error.term, key))
                    }
                }
                val predicate = database.find(key) ?: throw PrologError(errorBall(Term.Compound("existence_error", listOf(Term.Atom("procedure"), indicatorTerm(key))), key))
                val candidates = database.candidates(predicate, term, store)
                if (candidates.isEmpty()) return false
                val height = choices.size
                val resume = goals
                if (candidates.size > 1) push(ChoiceKind.Clauses(predicate, candidates, 1, term, height, context), resume)
                return tryClause(predicate, candidates[0], term, height, context, resume)
            }
        }
    }
    fun backtrack(): Boolean {
        retry@ while (true) {
            backtracks++
            while (choices.isNotEmpty()) {
                val point = choices.last()
                trail.undo(point.mark, store)
                when (val kind = point.kind) {
                    ChoiceKind.Alternative -> {
                        choices.removeAt(choices.lastIndex)
                        goals = point.resume
                        return true
                    }
                    is ChoiceKind.Clauses -> {
                        val next = kind.next
                        if (next + 1 == kind.candidates.size) choices.removeAt(choices.lastIndex) else kind.next++
                        if (tryClause(kind.predicate, kind.candidates[next], kind.goal, kind.barrier, kind.context, point.resume)) return true
                        continue@retry
                    }
                    is ChoiceKind.Between -> {
                        if (!inference(Indicator("between", 3))) return false
                        val next = kind.next
                        if (next == kind.high) choices.removeAt(choices.lastIndex) else kind.next++
                        if (unify(kind.variable, Term.Integer(next))) {
                            goals = point.resume
                            return true
                        }
                        continue@retry
                    }
                    is ChoiceKind.Length -> {
                        if (!inference(Indicator("length", 2))) return false
                        val next = kind.next++
                        val elements = List(next - kind.prefix) {
                            store.fresh()
                        }
                        if (unify(kind.tail, list(elements)) && unify(kind.length, Term.Integer(next.toLong()))) {
                            goals = point.resume
                            return true
                        }
                        continue@retry
                    }
                    is ChoiceKind.Catcher -> choices.removeAt(choices.lastIndex)
                    is ChoiceKind.Findall -> {
                        choices.removeAt(choices.lastIndex)
                        if (unify(list(kind.values), kind.result)) {
                            goals = point.resume
                            return true
                        }
                        continue@retry
                    }
                }
            }
            return false
        }
    }
    fun exception(original: Term, initial: Choice?): Boolean {
        val ball = store.copy(original)
        var context = initial
        while (context != null) {
            val point = context
            val index = choices.indexOfFirst {
                it === point
            }
            check(index >= 0)
            val kind = point.kind as ChoiceKind.Catcher
            while (choices.size > index) choices.removeAt(choices.lastIndex)
            trail.undo(point.mark, store)
            val mark = trail.mark
            val copied = store.copy(ball)
            if (unify(copied, kind.catcher)) {
                goals = point.resume
                prepend(listOf(entry(Term.Compound("call", listOf(kind.recovery)), choices.size, kind.parent)))
                return true
            }
            trail.undo(mark, store)
            context = kind.parent
        }
        answers.add("uncaught exception: " + writeTerm(ball, store))
        return false
    }
    fun answer(source: List<Variable>): String {
        val variables = source.filter {
            !it.name.startsWith("_")
        }
        val values = variables.map {
            store.dereference(it.term)
        }
        val writer = Writer(store, true)
        for ((variable, value) in variables.zip(values)) {
            val id = value.variableID
            if (id != null && id !in writer.names) writer.names[id] = variable.name
        }
        val items = mutableListOf<String>()
        for ((i, variable) in variables.withIndex()) {
            val id = values[i].variableID
            if (id == null) items.add(variable.name + " = " + writer.term(values[i], 699, true)) else {
                val previous = (i - 1 downTo 0).firstOrNull {
                    values[it].variableID == id
                }
                if (previous != null) items.add(variables[previous].name + " = " + variable.name)
            }
        }
        return if (items.isEmpty()) "true" else items.joinToString(", ")
    }
    fun run(variables: List<Variable>, limit: Int?) {
        while (true) {
            val current = goals
            if (current == null) {
                solutions++
                val text = answer(variables)
                if (limit == solutions || choices.isEmpty()) {
                    answers.add("$text.")
                    return
                }
                answers.add("$text ;")
                if (!backtrack()) {
                    answers.add(if (limitReached) "inference limit exceeded" else "false.")
                    return
                }
                continue
            }
            goals = current.next
            try {
                if (!execute(current.entry)) {
                    if (limitReached || !backtrack()) {
                        answers.add(if (limitReached) "inference limit exceeded" else "false.")
                        return
                    }
                }
            } catch (error: PrologError) {
                if (!exception(error.term, current.entry.context)) return
            }
        }
    }
}
fun linesText(lines: List<String>): String = if (lines.isEmpty()) "" else lines.joinToString("\n") + "\n"
fun write(name: String, text: String) {
    File("output").mkdirs()
    File("output/$name").writeText(text)
}
fun main() {
    val consult = Consult()
    consult.read(0, File("input/prelude.pl").readText())
    consult.read(1, File("input/program.pl").readText())
    consult.undefined()
    val answers = mutableListOf<String>()
    val output = StringBuilder()
    val statistics = mutableListOf<String>()
    val totals = IntArray(4)
    val profile = mutableMapOf<Indicator, Profile>()
    for ((i, line) in File("input/queries.txt").readLines().withIndex()) {
        answers.add(line)
        output.append("== query ${i + 1} ==\n")
        val at = line.indexOf("?- ")
        val prefix = line.substring(0, at).trim()
        val limit = prefix.toIntOrNull()
        val start = at + 3
        val tokens = lex(line.substring(start), start + 1)
        val store = consult.store.clone()
        try {
            val parsed = Reader(tokens, 0, store).clause(true)
            val engine = Engine(consult.database, profile, store, parsed.term)
            engine.run(parsed.variables, limit)
            answers.addAll(engine.answers)
            output.append(engine.output)
            if (engine.output.isNotEmpty() && engine.output.last().code != 10) output.append(10.toChar())
            statistics.add("query ${i + 1}: solutions=${engine.solutions} inferences=${engine.inferences} choicepoints=${engine.choicepoints} backtracks=${engine.backtracks}")
            totals[0] += engine.solutions
            totals[1] += engine.inferences
            totals[2] += engine.choicepoints
            totals[3] += engine.backtracks
        }
        catch (error: ReadError) {
            answers.add("syntax error at column ${error.column}: ${error.reason}")
            statistics.add("query ${i + 1}: syntax error")
        }
    }
    statistics.add("total: solutions=${totals[0]} inferences=${totals[1]} choicepoints=${totals[2]} backtracks=${totals[3]}")
    statistics.add("== profile ==")
    val entries = profile.entries.filter {
        it.value.calls > 0
    }.sortedWith(compareByDescending<Map.Entry<Indicator, Profile>> {
        it.value.calls
    }.thenBy {
        indicatorText(it.key)
    })
    for ((key, counts) in entries) statistics.add("${indicatorText(key)} calls=${counts.calls}" + if (consult.database.find(key) != null) " tries=${counts.tries}" else "")
    write("consult.txt", linesText(consult.reports))
    write("listing.txt", linesText(consult.listing()))
    write("answers.txt", linesText(answers))
    write("write_output.txt", output.toString())
    write("stats.txt", linesText(statistics))
}
