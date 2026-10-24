private class Reference(val reason: String) : RuntimeException(reason)

private class Evaluation : RuntimeException()

private data class Expr(val op: String, val text: String = "", val args: List<Expr> = emptyList())

private class Expression(text: String, val variables: Map<String, Long>, val states: Map<String, Int>) {
    val tokens = mutableListOf<String>()
    var at = 0
    init {
        var i = 0
        while (i < text.length) {
            if (text[i] == ' ') {
                i++
                continue
            }
            val start = i
            if (text[i] in '0'..'9') {
                while (i < text.length && text[i] in '0'..'9') i++
            } else if (text[i].isLetter() || text[i] == '_') {
                while (i < text.length && (text[i].isLetterOrDigit() || text[i] == '_')) i++
            } else {
                i++
                if (i < text.length && text.substring(start, i + 1) in setOf("||", "&&", "==", "!=", "<=", ">=")) i++
            }
            tokens.add(text.substring(start, i))
        }
    }

    fun parse(level: Int = 0): Expr {
        if (level == 5) {
            val t = tokens[at++]
            if (t == "!" || t == "-") return Expr("unary$t", args = listOf(parse(5)))
            if (t == "(") {
                val e = parse()
                at++
                return e
            }
            if (t[0] in '0'..'9') return Expr("number", t)
            if (t == "in") {
                at++
                val name = tokens[at++]
                if (name !in states) throw Reference("unknown state $name")
                at++
                return Expr("in", name)
            }
            if (t != "_data" && t !in variables) throw Reference("unknown variable $t")
            return Expr("variable", t)
        }
        val operators = when (level) {
            0 -> setOf("||")
            1 -> setOf("&&")
            2 -> setOf("==", "!=", "<", "<=", ">", ">=")
            3 -> setOf("+", "-")
            else -> setOf("*", "/", "%")
        }
        var left = parse(level + 1)
        while (at < tokens.size && tokens[at] in operators) {
            val op = tokens[at++]
            left = Expr(op, args = listOf(left, parse(level + 1)))
        }
        return left
    }
}

private data class Action(val kind: String, val name: String = "", val expr: Expr? = null, val text: String? = null, val delay: Int = 0)

private class State(val id: String, val kind: String, val parent: Int, val initialName: String?, val deep: Boolean, val defaultName: String?) {
    val children = mutableListOf<Int>()
    val entries = mutableListOf<List<Action>>()
    val exits = mutableListOf<List<Action>>()
    val transitions = mutableListOf<Int>()
    var depth = 0
    var initial = -1
    var default = -1
    var history: List<Int>? = null
    var entered = 0
    var taken = 0
    var dwell = 0L
    var entryTime = 0L
}

private data class Transition(val source: Int, val trigger: String, val descriptors: List<String>, val delay: Int, val guard: Expr?, val target: Int?, val mode: String, val actions: List<Action>)

private data class Definition(val line: Int, val text: String, val node: Int? = null)

private data class Event(val name: String, val value: Long = 0)

private data class Reservation(val due: Long, val creation: Int, val transition: Int? = null, val event: Event? = null)

private data class Trigger(val kind: String, val event: Event? = null, val transition: Int? = null)

private data class Selected(val transition: Int, val scope: Int?, val exits: Set<Int>)

private class Chart(val output: MutableList<String>) {
    val states = mutableListOf(State("", "root", -1, null, false, null))
    val ids = mutableMapOf<String, Int>()
    val variables = sortedMapOf<String, Long>()
    val transitions = mutableListOf<Transition>()
    val document = mutableListOf<Int>()
    val active = mutableSetOf<Int>()
    val queue = ArrayDeque<Event>()
    val reservations = mutableListOf<Reservation>()
    var time = 0L
    var data = 0L
    var trace = false
    var halted = false
    var macros = 0
    var micros = 0
    var creation = 0

    fun children(i: Int) = states[i].children.filter {
        states[it].kind != "history"
    }

    fun compound(i: Int) = i == 0 || states[i].kind == "state" && children(i).isNotEmpty()

    fun parallel(i: Int) = states[i].kind == "parallel" && children(i).isNotEmpty()

    fun atomic(i: Int) = states[i].kind != "history" && children(i).isEmpty()

    fun descendant(child: Int, ancestor: Int): Boolean {
        var p = states[child].parent
        while (p >= 0) {
            if (p == ancestor) return true
            p = states[p].parent
        }
        return false
    }

    fun expression(s: String) = Expression(s, variables, ids).parse()

    fun actions(text: String): List<Action> = text.split("; ").map {
        raw ->
        val w = raw.split(' ')
        when (w[0]) {
            "raise" -> Action("raise", w[1], if (w.size > 2) expression(w.drop(2).joinToString(" ")) else null)
            "send" -> Action("send", w[1], if (w.size > 3) expression(w.drop(3).joinToString(" ")) else null, delay = w[2].toInt())
            "cancel" -> Action("cancel", w[1])
            "log" -> {
                val rest = raw.drop(4)
                if (rest.startsWith('"')) {
                    val end = rest.indexOf('"', 1)
                    Action("log", expr = if (end + 1 < rest.length) expression(rest.drop(end + 2)) else null, text = rest.substring(1, end))
                } else Action("log", expr = expression(rest))
            } else -> {
                if (w[0] !in variables) throw Reference("unknown variable ${w[0]}")
                Action("assign", w[0], expression(w.drop(2).joinToString(" ")))
            }
        }
    }

    fun define(lines: List<Pair<Int, String>>): Boolean {
        val errors = sortedMapOf<Int, String>()
        val definitions = mutableListOf<Definition>()
        for ((line, text) in lines) {
            val w = text.split(' ')
            var node: Int? = null
            if (w[0] in setOf("state", "parallel", "final", "history")) {
                val parentName = if (w.size > 2 && w[2] != "initial") w[2] else null
                val reason = when {
                    w[1] in ids -> "duplicate state ${w[1]}"
                    parentName != null && parentName !in ids -> "unknown state $parentName"
                    parentName != null && states[ids.getValue(parentName)].kind in setOf("final", "history") -> "$parentName cannot have children"
                    else -> null
                }
                if (reason != null) errors[line] = reason else {
                    val parent = parentName?.let {
                        ids.getValue(it)
                    } ?: 0
                    val initial = w.indexOf("initial")
                    node = states.size
                    ids[w[1]] = node
                    val s = State(w[1], w[0], parent, if (initial >= 0) w[initial + 1] else null, w[0] == "history" && w[3] == "deep", if (w[0] == "history" && w.size == 5) w[4] else null)
                    s.depth = states[parent].depth + 1
                    states.add(s)
                    states[parent].children.add(node)
                }
            } else if (w[0] == "var") {
                if (w[1] in variables) errors[line] = "duplicate variable ${w[1]}" else variables[w[1]] = w[2].toLong()
            }
            definitions.add(Definition(line, text, node))
        }
        for (d in definitions) {
            if (d.line in errors) continue
            val w = d.text.split(' ')
            try {
                if (w[0] == "state" && d.node != null && states[d.node].initialName != null) {
                    val s = states[d.node]
                    val child = ids[s.initialName] ?: throw Reference("unknown state ${s.initialName}")
                    if (states[child].parent != d.node || states[child].kind == "history") throw Reference("${s.initialName} is not a child of ${s.id}")
                }
                if (w[0] == "final" || w[0] == "history") {
                    val s = states[d.node!!]
                    val p = states[s.parent]
                    if (p.kind != "state" || children(s.parent).isEmpty()) throw Reference("${s.id} needs a compound parent")
                    if (s.defaultName != null) {
                        val target = ids[s.defaultName] ?: throw Reference("unknown state ${s.defaultName}")
                        if (!descendant(target, s.parent) || states[target].kind == "history") throw Reference("${s.defaultName} is not a descendant of ${p.id}")
                    }
                }
                if (w[0] == "entry" || w[0] == "exit") {
                    val i = ids[w[1]] ?: throw Reference("unknown state ${w[1]}")
                    val s = states[i]
                    if (s.kind == "history") throw Reference("${s.id} cannot have actions")
                    val a = actions(d.text.substringAfter(" / "))
                    if (w[0] == "entry") s.entries.add(a) else s.exits.add(a)
                }
                if (w[0] == "on") {
                    val source = ids[w[1]] ?: throw Reference("unknown state ${w[1]}")
                    if (states[source].kind in setOf("final", "history")) throw Reference("${w[1]} cannot have transitions")
                    var rest = d.text.drop(4 + w[1].length)
                    var trigger: String
                    var delay = 0
                    var descriptors = emptyList<String>()
                    if (rest.startsWith("after ")) {
                        rest = rest.drop(6)
                        val word = rest.substringBefore(' ')
                        delay = word.toInt()
                        rest = rest.drop(word.length).trimStart(' ')
                        trigger = "timer"
                    } else {
                        val word = rest.substringBefore(' ')
                        rest = rest.drop(word.length).trimStart(' ')
                        trigger = if (word == "always") "always" else "event"
                        if (trigger == "event") descriptors = word.split('|')
                    }
                    var guard: Expr? = null
                    if (rest.startsWith('[')) {
                        val end = rest.indexOf(']')
                        guard = expression(rest.substring(1, end))
                        rest = rest.drop(end + 1).trimStart(' ')
                    }
                    var target: Int? = null
                    var mode = "internal"
                    if (rest.startsWith("-> ") || rest.startsWith("~> ")) {
                        mode = if (rest[0] == '-') "external" else "local"
                        rest = rest.drop(3)
                        val name = rest.substringBefore(' ')
                        target = ids[name] ?: throw Reference("unknown state $name")
                        rest = rest.drop(name.length).trimStart(' ')
                    }
                    val a = if (rest.startsWith("/ ")) actions(rest.drop(2)) else emptyList()
                    states[source].transitions.add(transitions.size)
                    transitions.add(Transition(source, trigger, descriptors, delay, guard, target, mode, a))
                }
            } catch (e: Reference) {
                errors[d.line] = e.reason
            }
        }
        if (errors.isNotEmpty()) {
            for ((line, reason) in errors) output.add("error line $line: $reason")
            return false
        }
        for (i in states.indices) {
            if (compound(i)) states[i].initial = states[i].initialName?.let {
                ids.getValue(it)
            } ?: children(i).first()
            if (states[i].kind == "history") states[i].default = states[i].defaultName?.let {
                ids.getValue(it)
            } ?: states[states[i].parent].initial
        }

        fun visit(i: Int) {
            document.add(i)
            for (c in states[i].children) visit(c)
        }
        for (i in states[0].children) visit(i)
        return true
    }

    fun warnings() {
        val reached = mutableSetOf(states[0].initial)
        while (true) {
            val before = reached.size
            for (i in reached.toList()) {
                if (states[i].parent != 0) reached.add(states[i].parent)
                if (compound(i)) reached.add(states[i].initial)
                if (parallel(i)) reached.addAll(children(i))
                for (t in states[i].transitions.map {
                    transitions[it]
                }) if (t.target != null) reached.add(if (states[t.target].kind == "history") states[t.target].default else t.target)
            }
            if (before == reached.size) break
        }
        for (i in document) if (states[i].kind != "history" && i !in reached) output.add("warning: unreachable state ${states[i].id}")
    }

    fun evaluate(e: Expr): Long {
        if (e.op == "number") return e.text.toLong()
        if (e.op == "variable") return if (e.text == "_data") data else variables.getValue(e.text)
        if (e.op == "in") return if (ids.getValue(e.text) in active) 1 else 0
        val a = evaluate(e.args[0])
        if (e.op == "unary!") return if (a == 0L) 1 else 0
        if (e.op == "unary-") return -a
        if (e.op == "&&" && a == 0L) return 0
        if (e.op == "||" && a != 0L) return 1
        val b = evaluate(e.args[1])
        if ((e.op == "/" || e.op == "%") && b == 0L) throw Evaluation()
        return when (e.op) {
            "+" -> a + b
            "-" -> a - b
            "*" -> a * b
            "/" -> a / b
            "%" -> a % b
            "==" -> if (a == b) 1 else 0
            "!=" -> if (a != b) 1 else 0
            "<" -> if (a < b) 1 else 0
            "<=" -> if (a <= b) 1 else 0
            ">" -> if (a > b) 1 else 0
            ">=" -> if (a >= b) 1 else 0
            else -> if (b != 0L) 1 else 0
        }
    }

    fun reserve(transition: Int? = null, event: Event? = null, delay: Int) {
        creation++
        reservations.add(Reservation(time + delay, creation, transition, event))
    }

    fun actions(list: List<Action>) {
        for (a in list) try {
            val v = a.expr?.let(::evaluate) ?: 0L
            when (a.kind) {
                "assign" -> variables[a.name] = v
                "raise" -> queue.add(Event(a.name, v))
                "send" -> reserve(event = Event(a.name, v), delay = a.delay)
                "cancel" -> reservations.removeAll {
                    it.event?.name == a.name
                }
                "log" -> output.add((a.text ?: "") + if (a.expr == null) "" else v.toString())
            }
        } catch (_: Evaluation) {
            queue.add(Event("error.execution"))
            break
        }
    }

    fun effective(t: Transition): List<Int> {
        val i = t.target ?: return emptyList()
        return if (states[i].kind == "history") states[i].history ?: listOf(states[i].default) else listOf(i)
    }

    fun scope(t: Transition): Int? {
        if (t.target == null) return null
        val targets = effective(t)
        if (t.mode == "local" && compound(t.source) && targets.all {
            descendant(it, t.source)
        }) return t.source
        var p = states[t.source].parent
        while (!(compound(p) && targets.all {
            descendant(it, p)
        })) p = states[p].parent
        return p
    }

    fun matches(t: Transition, trigger: Trigger, index: Int): Boolean = when (trigger.kind) {
        "always" -> t.trigger == "always"
        "timer" -> index == trigger.transition
        else -> {
            val name = trigger.event!!.name
            t.trigger == "event" && t.descriptors.any {
                it == "*" || it == name || name.startsWith("$it.")
            }
        }
    }

    fun select(trigger: Trigger): List<Selected> {
        val candidates = mutableListOf<Int>()
        val seen = mutableSetOf<Int>()
        for (leaf in document.filter {
            it in active && atomic(it)
        }) {
            var source = leaf
            var chosen: Int? = null
            while (source != 0 && chosen == null) {
                for (index in states[source].transitions) {
                    val t = transitions[index]
                    if (!matches(t, trigger, index)) continue
                    val enabled = try {
                        t.guard?.let {
                            evaluate(it) != 0L
                        } ?: true
                    } catch (_: Evaluation) {
                        queue.add(Event("error.execution"))
                        false
                    }
                    if (enabled) {
                        chosen = index
                        break
                    }
                }
                source = states[source].parent
            }
            if (chosen != null && seen.add(chosen)) candidates.add(chosen)
        }
        val occupied = mutableSetOf<Int>()
        val result = mutableListOf<Selected>()
        for (i in candidates) {
            val scope = scope(transitions[i])
            val exits = if (scope == null) emptySet() else active.filter {
                descendant(it, scope)
            }.toSet()
            if (exits.none {
                it in occupied
            }) {
                result.add(Selected(i, scope, exits))
                occupied.addAll(exits)
            }
        }
        return result
    }

    fun expand(entries: MutableSet<Int>) {
        while (true) {
            val before = entries.size
            for (i in entries.toList()) {
                if (parallel(i)) entries.addAll(children(i))
                if (compound(i) && children(i).none {
                    it in entries
                }) entries.add(states[i].initial)
            }
            if (entries.size == before) return
        }
    }

    fun complete(i: Int): Boolean = if (compound(i)) children(i).any {
        states[it].kind == "final" && it in active
    } else parallel(i) && children(i).all(::complete)

    fun enter(entries: Set<Int>) {
        for (i in document) if (i in entries) {
            val s = states[i]
            active.add(i)
            s.entered++
            s.entryTime = time
            for (index in s.transitions) if (transitions[index].trigger == "timer") reserve(transition = index, delay = transitions[index].delay)
            for (list in s.entries) actions(list)
            if (s.kind == "final") {
                val p = s.parent
                queue.add(Event("done.state.${states[p].id}"))
                val g = states[p].parent
                if (g >= 0 && parallel(g) && children(g).all(::complete)) queue.add(Event("done.state.${states[g].id}"))
            }
        }
    }

    fun list(values: List<Int>) = values.joinToString(",") {
        states[it].id
    }.ifEmpty {
        "-"
    }

    fun display(trigger: Trigger): String = when (trigger.kind) {
        "always" -> "always"
        "timer" -> {
            val t = transitions[trigger.transition!!]
            "after(${t.delay})@${states[t.source].id}"
        } else -> trigger.event!!.name + if (trigger.event.value == 0L) "" else "=${trigger.event.value}"
    }

    fun micro(selected: List<Selected>, trigger: Trigger) {
        val exits = selected.flatMap {
            it.exits
        }.toSet()
        for (i in document) if (states[i].kind == "history" && states[i].parent in exits) {
            val parent = states[i].parent
            states[i].history = document.filter {
                it in active && if (states[i].deep) atomic(it) && descendant(it, parent) else states[it].parent == parent && states[it].kind != "history"
            }
        }
        val entries = mutableSetOf<Int>()
        for (choice in selected) if (choice.scope != null) for (target in effective(transitions[choice.transition])) {
            var i = target
            while (i != choice.scope) {
                entries.add(i)
                i = states[i].parent
            }
        }
        expand(entries)
        if (trace) output.add("[t=$time] ${display(trigger)} (${list(selected.map { transitions[it.transition].source })}): exit ${list(document.asReversed().filter { it in exits })}; enter ${list(document.filter { it in entries })}")
        for (i in document.asReversed()) if (i in exits) {
            val s = states[i]
            for (a in s.exits) actions(a)
            active.remove(i)
            s.dwell += time - s.entryTime
            reservations.removeAll {
                it.transition?.let {
                    transitions[it].source == i
                } ?: false
            }
        }
        for (choice in selected) {
            val t = transitions[choice.transition]
            actions(t.actions)
            states[t.source].taken++
        }
        enter(entries)
    }

    fun macro(trigger: Trigger) {
        macros++
        var count = 0

        fun perform(selected: List<Selected>, trigger: Trigger): Boolean {
            if (selected.isEmpty()) return true
            if (count == 1000) {
                output.add("LIVELOCK t=$time")
                halted = true
                return false
            }
            count++
            micros++
            micro(selected, trigger)
            return true
        }
        if (trigger.kind == "start") {
            data = 0
            val entries = mutableSetOf(states[0].initial)
            expand(entries)
            enter(entries)
        } else {
            data = trigger.event?.value ?: 0
            if (!perform(select(trigger), trigger)) return
        }
        while (true) {
            data = 0
            val always = Trigger("always")
            val selected = select(always)
            if (selected.isNotEmpty()) {
                if (!perform(selected, always)) return
                continue
            }
            if (queue.isEmpty()) return
            val event = queue.removeFirst()
            data = event.value
            val next = Trigger("event", event)
            if (!perform(select(next), next)) return
        }
    }

    fun script(line: String) {
        if (halted) return
        val w = line.split(' ')
        when (w[0]) {
            "event" -> macro(Trigger("event", Event(w[1], w.getOrNull(2)?.toLong() ?: 0)))
            "tick" -> {
                val finish = time + w[1].toInt()
                while (!halted) {
                    val next = reservations.filter {
                        it.due <= finish
                    }.minWithOrNull(compareBy<Reservation> {
                        it.due
                    }.thenBy {
                        it.creation
                    }) ?: break
                    reservations.remove(next)
                    time = next.due
                    macro(if (next.transition == null) Trigger("event", next.event) else Trigger("timer", transition = next.transition))
                }
                if (!halted) time = finish
            }
            "set" -> if (w[1] in variables) variables[w[1]] = w[2].toLong() else output.add("error: unknown variable ${w[1]}")
            "trace" -> trace = w[1] == "on"
            "eval" -> {
                val text = line.drop(5)
                try {
                    val e = expression(text)
                    data = 0
                    try {
                        output.add("$text -> ${evaluate(e)}")
                    } catch (_: Evaluation) {
                        output.add("error: division by zero")
                    }
                } catch (e: Reference) {
                    output.add("error: ${e.reason}")
                }
            }
            "dump" -> {
                output.add("dump t=$time")
                for (i in document) if (i in active) output.add("  ".repeat(states[i].depth) + states[i].id)
                for ((name, value) in variables) output.add("  var $name = $value")
                for (i in document) states[i].history?.let {
                    output.add("  history ${states[i].id} = ${list(it)}")
                }
                for (r in reservations.sortedWith(compareBy<Reservation> {
                    it.due
                }.thenBy {
                    it.creation
                })) {
                    if (r.transition != null) {
                        val t = transitions[r.transition]
                        output.add("  timer ${r.due} after(${t.delay})@${states[t.source].id}")
                    } else output.add("  send ${r.due} ${r.event!!.name} ${r.event.value}")
                }
            }
        }
    }

    fun statistics() {
        output.add("end t=$time macrosteps=$macros microsteps=$micros")
        for (i in document) if (states[i].kind != "history") {
            val s = states[i]
            val dwell = s.dwell + if (i in active) time - s.entryTime else 0
            output.add("  ${s.id} entered=${s.entered} taken=${s.taken} time=$dwell")
        }
    }
}

fun main() {
    val lines = generateSequence(::readLine).toList()
    val output = mutableListOf<String>()
    var at = 1
    repeat(lines[0].toInt()) {
        output.add("chart ${lines[at++].drop(6)}")
        val definitions = mutableListOf<Pair<Int, String>>()
        while (lines[at] != "RUN") {
            definitions.add(at + 1 to lines[at])
            at++
        }
        at++
        val scripts = mutableListOf<String>()
        while (lines[at] != "END") scripts.add(lines[at++])
        at++
        val chart = Chart(output)
        if (chart.define(definitions)) {
            chart.warnings()
            chart.macro(Trigger("start"))
            for (line in scripts) chart.script(line)
            chart.statistics()
        }
    }
    for (line in output) println(line)
}
