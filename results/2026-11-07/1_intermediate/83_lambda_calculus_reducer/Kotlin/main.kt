private class Problem(val reason: String) : RuntimeException(reason)

private fun fail(reason: String): Nothing = throw Problem(reason)

private data class Term(val kind: String, val name: String = "", val left: Term? = null, val right: Term? = null, val number: Int = 0)

private fun variable(name: String) = Term("var", name)

private fun lambda(name: String, body: Term) = Term("lam", name, body)

private fun application(left: Term, right: Term) = Term("app", left = left, right = right)

private fun free(t: Term): Set<String> = when (t.kind) {
    "var" -> setOf(t.name)
    "lam" -> free(t.left!!) - t.name
    "app" -> free(t.left!!) + free(t.right!!)
    else -> emptySet()
}

private fun references(t: Term): List<String> = when (t.kind) {
    "macro" -> listOf(t.name)
    "lam" -> references(t.left!!)
    "app" -> references(t.left!!) + references(t.right!!)
    else -> emptyList()
}

private fun printed(t: Term, end: Boolean = true, db: Boolean = false): String = when (t.kind) {
    "var", "macro" -> t.name
    "index" -> t.number.toString()
    "num" -> "#${t.number}"
    "lam" -> {
        var body = t
        val names = mutableListOf<String>()
        while (body.kind == "lam") {
            names.add(body.name)
            body = body.left!!
        }
        val s = if (db) "\\".repeat(names.size) + printed(body, true, true) else "\\" + names.joinToString(" ") + ". " + printed(body)
        if (end) s else "($s)"
    } else -> {
        val a = t.left!!
        val b = t.right!!
        val left = if (a.kind == "lam") "(${printed(a, true, db)})" else printed(a, false, db)
        val right = if (b.kind == "app") "(${printed(b, true, db)})" else printed(b, end, db)
        "$left $right"
    }
}

private fun sequenceName(n: Int) = ('a'.code + n % 26).toChar().toString() + if (n < 26) "" else (n / 26).toString()

private fun canonical(t: Term): Term {
    val f = free(t)
    var next = 0

    fun visit(s: Term, env: List<Pair<String, String>>): Term = when (s.kind) {
        "var" -> variable(env.lastOrNull {
            it.first == s.name
        }?.second ?: s.name)
        "lam" -> {
            while (sequenceName(next) in f) next++
            val name = sequenceName(next++)
            lambda(name, visit(s.left!!, env + (s.name to name)))
        }
        "app" -> application(visit(s.left!!, env), visit(s.right!!, env))
        else -> s
    }
    return visit(t, emptyList())
}

private fun debruijn(t: Term, env: List<String> = emptyList()): Term = when (t.kind) {
    "var" -> {
        val i = env.indexOfLast {
            it == t.name
        }
        if (i < 0) t else Term("index", number = env.lastIndex - i)
    }
    "lam" -> lambda("", debruijn(t.left!!, env + t.name))
    "app" -> application(debruijn(t.left!!, env), debruijn(t.right!!, env))
    else -> t
}

private fun substitute(t: Term, x: String, n: Term): Term = when (t.kind) {
    "var" -> if (t.name == x) n else t
    "app" -> application(substitute(t.left!!, x, n), substitute(t.right!!, x, n))
    "lam" -> {
        val body = t.left!!
        if (t.name == x || x !in free(body)) t
        else if (t.name !in free(n)) lambda(t.name, substitute(body, x, n))
        else {
            val forbidden = free(n) + free(body)
            val base = t.name.trimEnd {
                it in '0'..'9'
            }
            var i = 1
            while (base + i in forbidden) i++
            val z = base + i
            lambda(z, substitute(substitute(body, t.name, variable(z)), x, n))
        }
    } else -> t
}

private fun eta(t: Term): Term? {
    if (t.kind != "lam") return null
    val b = t.left!!
    return if (b.kind == "app" && b.right!!.kind == "var" && b.right.name == t.name && t.name !in free(b.left!!)) b.left else null
}

private fun step(t: Term, strategy: String, useEta: Boolean): Pair<Term, String>? {
    if (t.kind == "app") {
        val a = t.left!!
        val b = t.right!!
        if (strategy in setOf("NORMAL", "CBN") && a.kind == "lam") return substitute(a.left!!, a.name, b) to "beta"
        step(a, strategy, useEta)?.let {
            return application(it.first, b) to it.second
        }
        if (strategy != "CBN") step(b, strategy, useEta)?.let {
            return application(a, it.first) to it.second
        }
        if (strategy in setOf("APPLICATIVE", "CBV") && a.kind == "lam" && (strategy != "CBV" || b.kind in setOf("var", "lam"))) return substitute(a.left!!, a.name, b) to "beta"
    } else if (t.kind == "lam" && strategy in setOf("NORMAL", "APPLICATIVE")) {
        if (strategy == "NORMAL" && useEta) eta(t)?.let {
            return it to "eta"
        }
        step(t.left!!, strategy, useEta)?.let {
            return lambda(t.name, it.first) to it.second
        }
        if (strategy == "APPLICATIVE" && useEta) eta(t)?.let {
            return it to "eta"
        }
    }
    return null
}

private class Ty(val id: Int = -1, val left: Ty? = null, val right: Ty? = null)

private fun infer(t: Term): String {
    var next = 0
    val bindings = mutableMapOf<Int, Ty>()
    val globals = mutableMapOf<String, Ty>()

    fun fresh() = Ty(next++)

    fun resolve(t: Ty): Ty = if (t.id >= 0 && t.id in bindings) resolve(bindings.getValue(t.id)) else t

    fun occurs(id: Int, t: Ty): Boolean {
        val a = resolve(t)
        return if (a.id >= 0) a.id == id else occurs(id, a.left!!) || occurs(id, a.right!!)
    }

    fun unify(a0: Ty, b0: Ty) {
        val a = resolve(a0)
        val b = resolve(b0)
        if (a === b || a.id >= 0 && a.id == b.id) return
        if (a.id >= 0) {
            if (occurs(a.id, b)) throw IllegalStateException()
            bindings[a.id] = b
        } else if (b.id >= 0) {
            if (occurs(b.id, a)) throw IllegalStateException()
            bindings[b.id] = a
        } else {
            unify(a.left!!, b.left!!)
            unify(a.right!!, b.right!!)
        }
    }

    fun visit(t: Term, env: List<Pair<String, Ty>>): Ty = when (t.kind) {
        "var" -> env.lastOrNull {
            it.first == t.name
        }?.second ?: globals.getOrPut(t.name) {
            fresh()
        }
        "lam" -> {
            val a = fresh()
            Ty(left = a, right = visit(t.left!!, env + (t.name to a)))
        } else -> {
            val a = visit(t.left!!, env)
            val b = visit(t.right!!, env)
            val result = fresh()
            unify(a, Ty(left = b, right = result))
            result
        }
    }
    return try {
        val result = visit(t, emptyList())
        val names = mutableMapOf<Int, String>()

        fun show(t: Ty): String {
            val a = resolve(t)
            if (a.id >= 0) return names.getOrPut(a.id) {
                sequenceName(names.size)
            }
            val l = resolve(a.left!!)
            return (if (l.id < 0) "(${show(l)})" else show(l)) + " -> " + show(a.right!!)
        }
        show(result)
    } catch (_: IllegalStateException) {
        "not typable"
    }
}

private fun abstract(x: String, e: Term): Term {
    if (x !in free(e)) return application(Term("macro", "K"), e)
    if (e.kind == "var" && e.name == x) return Term("macro", "I")
    if (e.right!!.kind == "var" && e.right.name == x && x !in free(e.left!!)) return e.left
    return application(application(Term("macro", "S"), abstract(x, e.left!!)), abstract(x, e.right))
}

private fun ski(t: Term): Term = when (t.kind) {
    "var" -> t
    "lam" -> abstract(t.name, ski(t.left!!))
    else -> application(ski(t.left!!), ski(t.right!!))
}

private fun skiStep(t: Term): Pair<Term, String>? {
    var h = t
    val args = mutableListOf<Term>()
    while (h.kind == "app") {
        args.add(0, h.right!!)
        h = h.left!!
    }

    fun build(head: Term, rest: List<Term>) = rest.fold(head, ::application)
    if (h.kind == "macro") {
        when (h.name) {
            "I" -> if (args.size >= 1) return build(args[0], args.drop(1)) to "I"
            "K" -> if (args.size >= 2) return build(args[0], args.drop(2)) to "K"
            "S" -> if (args.size >= 3) return build(application(application(args[0], args[2]), application(args[1], args[2])), args.drop(3)) to "S"
        }
    }
    for (i in args.indices) skiStep(args[i])?.let {
        args[i] = it.first
        return build(h, args) to it.second
    }
    return null
}

private fun church(t: Term): String {
    if (t.kind == "lam" && t.left!!.kind == "lam") {
        val f = t.name
        val x = t.left.name
        var b = t.left.left!!
        var count = 0
        while (b.kind == "app" && b.left!!.kind == "var" && b.left.name == f) {
            count++
            b = b.right!!
        }
        if (b.kind == "var" && b.name == x) return count.toString()
        if (t.left.left!!.kind == "var" && t.left.left.name == f) return "true"
    }
    if (t.kind == "lam") {
        val b = t.left!!
        if (b.kind == "app" && b.left!!.kind == "app" && b.left.left!!.kind == "var" && b.left.left.name == t.name) {
            val p = b.left.right!!
            val q = b.right!!
            if (t.name !in free(p) && t.name !in free(q)) return "(${church(p)}, ${church(q)})"
        }
    }
    return printed(canonical(t))
}

private data class Token(val kind: String, val text: String, val column: Int)

private class Parser(line: String, argument: String, offset: Int) {
    val tokens = mutableListOf<Token>()
    var at = 0
    init {
        var i = 0
        while (i < argument.length) {
            val c = argument[i]
            if (c == ' ') {
                i++
                continue
            }
            val start = i
            val kind = when {
                c in "\\.()=;" -> {
                    i++
                    c.toString()
                }
                c in 'a'..'z' -> {
                    i++
                    while (i < argument.length && (argument[i] in 'a'..'z' || argument[i] in '0'..'9')) i++
                    "var"
                }
                c in 'A'..'Z' -> {
                    i++
                    while (i < argument.length && (argument[i] in 'A'..'Z' || argument[i] in '0'..'9' || argument[i] == '_')) i++
                    "macro"
                }
                c == '#' && i + 1 < argument.length && argument[i + 1] in '0'..'9' -> {
                    i += 2
                    while (i < argument.length && argument[i] in '0'..'9') i++
                    "num"
                } else -> fail("column ${offset + i}: unexpected character '$c'")
            }
            tokens.add(Token(kind, argument.substring(start, i), offset + start))
        }
        tokens.add(Token("end", "", line.length + 1))
    }

    fun expect(kind: String): Token {
        val t = tokens[at]
        if (t.kind != kind) fail("column ${t.column}: expected " + when (kind) {
            "var" -> "variable"
            "macro" -> "macro name"
            else -> "'$kind'"
        })
        at++
        return t
    }

    fun term(): Term {
        val elements = mutableListOf<Term>()
        while (tokens[at].kind in setOf("var", "macro", "num", "(")) {
            val t = tokens[at++]
            elements.add(when (t.kind) {
                "(" -> {
                    val e = term()
                    expect(")")
                    e
                }
                "num" -> Term("num", number = t.text.drop(1).toInt())
                else -> Term(t.kind, t.text)
            })
        }
        if (tokens[at].kind == "\\") {
            at++
            val names = mutableListOf(expect("var").text)
            while (tokens[at].kind == "var") names.add(tokens[at++].text)
            expect(".")
            var body = term()
            for (n in names.asReversed()) body = lambda(n, body)
            elements.add(body)
        }
        if (elements.isEmpty()) fail("column ${tokens[at].column}: expected term")
        return elements.drop(1).fold(elements[0], ::application)
    }

    fun end() {
        val t = tokens[at]
        if (t.kind != "end") fail("column ${t.column}: unexpected '${t.text}'")
    }
}

private data class Closure(val code: Term, val env: List<Closure>)

private class Workbench {
    val macros = sortedMapOf<String, Term>()
    val reserved = setOf("S", "K", "I", "NORMAL", "APPLICATIVE", "CBN", "CBV")
    var display = false
    var etaMode = false
    var limit = 10000
    init {
        val x = variable("x")
        val y = variable("y")
        val z = variable("z")
        macros["I"] = lambda("x", x)
        macros["K"] = lambda("x", lambda("y", x))
        macros["S"] = lambda("x", lambda("y", lambda("z", application(application(x, z), application(y, z)))))
    }

    fun expand(t: Term): Term = when (t.kind) {
        "macro" -> expand(macros[t.name] ?: fail("unbound macro ${t.name}"))
        "num" -> {
            var b = variable("x")
            repeat(t.number) {
                b = application(variable("f"), b)
            }
            lambda("f", lambda("x", b))
        }
        "lam" -> lambda(t.name, expand(t.left!!))
        "app" -> application(expand(t.left!!), expand(t.right!!))
        else -> t
    }

    fun depends(name: String, target: String): Boolean {
        val visited = mutableSetOf<String>()

        fun visit(n: String): Boolean {
            if (!visited.add(n)) return false
            return macros[n]?.let {
                references(it).any {
                    r -> r == target || visit(r)
                }
            } ?: false
        }
        return visit(name)
    }

    fun reduce(t: Term, strategy: String, useEta: Boolean, output: MutableList<String>?, combinators: Boolean = false): Pair<Term, Int>? {
        var current = t
        var count = 0
        while (true) {
            val next = if (combinators) skiStep(current) else step(current, strategy, useEta)
            if (next == null) return current to count
            if (count == limit) return null
            current = next.first
            count++
            if (display && output != null) output.add("step $count (${next.second}): ${printed(current)}")
        }
    }

    fun kam(t: Term): List<String> {
        var code = debruijn(t)
        var env = emptyList<Closure>()
        val stack = mutableListOf<Closure>()
        var count = 0
        val output = mutableListOf<String>()
        while (true) {
            val kind = when {
                code.kind == "app" -> "push"
                code.kind == "lam" && stack.isNotEmpty() -> "grab"
                code.kind == "index" -> "access"
                else -> break
            }
            if (count == limit) {
                output.add("no result within $limit transitions")
                return output
            }
            when (kind) {
                "push" -> {
                    stack.add(Closure(code.right!!, env))
                    code = code.left!!
                }
                "grab" -> {
                    env = listOf(stack.removeAt(stack.lastIndex)) + env
                    code = code.left!!
                }
                "access" -> {
                    val c = env[code.number]
                    code = c.code
                    env = c.env
                }
            }
            count++
            if (display) output.add("step $count ($kind): ${printed(code, db = true)} [env ${env.size}, stack ${stack.size}]")
        }

        fun reify(initialTerm: Term, initialEnvironment: List<Closure>, initialDepth: Int): Term {
            var term = initialTerm
            var environment = initialEnvironment
            var depth = initialDepth
            while (term.kind == "index" && term.number >= depth) {
                val closure = environment[term.number - depth]
                term = closure.code
                environment = closure.env
                depth = 0
            }
            return when (term.kind) {
                "lam" -> lambda("", reify(term.left!!, environment, depth + 1))
                "app" -> application(reify(term.left!!, environment, depth), reify(term.right!!, environment, depth))
                else -> term
            }
        }
        var result = reify(code, env, 0)
        for (c in stack.asReversed()) result = application(result, reify(c.code, c.env, 0))
        val f = free(result)
        var nextName = 0

        fun named(t: Term, bound: List<String>): Term = when (t.kind) {
            "index" -> variable(bound[bound.lastIndex - t.number])
            "lam" -> {
                while (sequenceName(nextName) in f) nextName++
                val n = sequenceName(nextName++)
                lambda(n, named(t.left!!, bound + n))
            }
            "app" -> application(named(t.left!!, bound), named(t.right!!, bound))
            else -> t
        }
        output.add("result: ${printed(named(result, emptyList()))} (transitions: $count)")
        return output
    }

    fun command(line: String): List<String> {
        val command = line.substringBefore(' ')
        val arg = if (' ' in line) line.substringAfter(' ') else ""
        val known = setOf("let", "unlet", "macros", "steps", "eta", "limit", "expand", "subst", "reduce", "equal", "alpha", "debruijn", "fv", "size", "depth", "type", "church", "ski", "skireduce", "kam")
        if (command !in known) fail("unknown command $command")
        val words = arg.split(' ').filter {
            it.isNotEmpty()
        }
        if (command in setOf("steps", "eta")) {
            if (words.size != 1 || words[0] !in setOf("on", "off")) fail("bad argument")
            if (command == "steps") display = words[0] == "on" else etaMode = words[0] == "on"
            return emptyList()
        }
        if (command == "limit") {
            if (words.size != 1 || words[0].length !in 1..5 || words[0].any {
                it !in '0'..'9'
            } || words[0].toInt() !in 1..10000) fail("bad argument")
            limit = words[0].toInt()
            return emptyList()
        }
        if (command == "macros") {
            if (words.isNotEmpty()) fail("bad argument")
            return macros.filterKeys {
                it !in reserved
            }.map {
                (n, t) -> "$n = ${printed(t)}"
            }.ifEmpty {
                listOf("(none)")
            }
        }
        if (command == "unlet") {
            if (words.size != 1 || !words[0].matches(Regex("[A-Z][A-Z0-9_]*"))) fail("bad argument")
            val name = words[0]
            if (name in reserved) fail("reserved name $name")
            if (name !in macros) fail("unbound macro $name")
            macros.keys.firstOrNull {
                it !in reserved && name in references(macros.getValue(it))
            }?.let {
                fail("$name is used by $it")
            }
            macros.remove(name)
            return listOf("removed $name")
        }
        val p = Parser(line, arg, if (' ' in line) command.length + 2 else line.length + 1)
        var name = ""
        var strategy = "NORMAL"
        val terms = mutableListOf<Term>()
        when (command) {
            "let" -> {
                name = p.expect("macro").text
                p.expect("=")
                terms.add(p.term())
            }
            "subst" -> {
                name = p.expect("var").text
                p.expect("=")
                terms.add(p.term())
                p.expect(";")
                terms.add(p.term())
            }
            "equal", "alpha" -> {
                terms.add(p.term())
                p.expect(";")
                terms.add(p.term())
            }
            "reduce" -> {
                if (p.tokens[p.at].kind == "macro" && p.tokens[p.at].text in setOf("NORMAL", "APPLICATIVE", "CBN", "CBV")) strategy = p.tokens[p.at++].text
                terms.add(p.term())
            } else -> terms.add(p.term())
        }
        p.end()
        if (command == "let") {
            val t = terms[0]
            if (name in reserved) fail("reserved name $name")
            for (r in references(t)) {
                if (r == name || depends(r, name)) fail("recursive definition of $name")
                if (r !in macros) fail("unbound macro $r")
            }
            free(t).minOrNull()?.let {
                fail("free variable $it in definition of $name")
            }
            val existed = name in macros
            macros[name] = t
            return listOf("${if (existed) "redefined" else "defined"} $name")
        }
        val expanded = terms.map(::expand)
        val t = expanded[0]
        val failure = "no normal form within $limit steps"
        return when (command) {
            "expand" -> listOf(printed(t))
            "subst" -> listOf(printed(substitute(expanded[1], name, t)))
            "alpha" -> listOf(if (debruijn(t) == debruijn(expanded[1])) "yes" else "no")
            "debruijn" -> listOf(printed(debruijn(t), db = true))
            "fv" -> listOf(free(t).sorted().joinToString(" ").ifEmpty {
                "(none)"
            })
            "size", "depth" -> {

                fun measure(t: Term): Int = if (t.kind == "var") 1 else if (t.kind == "lam") 1 + measure(t.left!!) else 1 + if (command == "size") measure(t.left!!) + measure(t.right!!) else maxOf(measure(t.left!!), measure(t.right!!))
                listOf(measure(t).toString())
            }
            "type" -> listOf(infer(t))
            "ski" -> listOf(printed(ski(t)))
            "kam" -> kam(t)
            "equal" -> {
                val a = reduce(t, "NORMAL", etaMode, null)
                val b = reduce(expanded[1], "NORMAL", etaMode, null)
                listOf(if (a == null || b == null) "unknown" else if (debruijn(a.first) == debruijn(b.first)) "yes" else "no")
            }
            "church" -> {
                val result = reduce(t, "NORMAL", false, null)
                listOf(if (result == null) failure else church(canonical(result.first)))
            } else -> {
                val output = mutableListOf<String>()
                val combinators = command == "skireduce"
                val result = reduce(if (combinators) ski(t) else t, strategy, etaMode, output, combinators)
                output.add(if (result == null) failure else "result: ${printed(if (combinators) result.first else canonical(result.first))} (steps: ${result.second})")
                output
            }
        }
    }
}

fun main() {
    val workbench = Workbench()
    while (true) {
        val line = readLine() ?: break
        if (line == "quit") break
        if (line.isEmpty() || line.startsWith("--")) continue
        try {
            workbench.command(line).forEach(::println)
        } catch (e: Problem) {
            println("error: ${e.reason}")
        }
    }
}
