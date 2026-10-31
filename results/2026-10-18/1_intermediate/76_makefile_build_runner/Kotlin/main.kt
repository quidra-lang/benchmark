private class Expansion(val reason: String) : RuntimeException(reason)

private class Abort : RuntimeException()

private fun words(s: String) = s.split(' ').filter {
    it.isNotEmpty()
}

private fun unique(xs: List<String>) = xs.distinct()

private fun stem(pattern: String, word: String): String? {
    val i = pattern.indexOf('%')
    if (i < 0) return if (pattern == word) "" else null
    val a = pattern.take(i)
    val b = pattern.drop(i+1)
    return if (word.length >= a.length+b.length && word.startsWith(a) && word.endsWith(b)) word.substring(a.length,word.length-b.length) else null
}

private fun substitute(s: String,m: String): String {
    val i = s.indexOf('%')
    return if (i < 0) s else s.take(i)+m+s.drop(i+1)
}

private fun replaceWord(w: String,p: String,r: String) = stem(p,w)?.let {
    if ('%' in p) substitute(r,it) else r
}?: w

private fun wildcard(pattern: String, word: String): Boolean {
    var previous = BooleanArray(word.length+1)
    previous[0] = true
    for (c in pattern) {
        val next = BooleanArray(word.length+1)
        if (c == '*') next[0] = previous[0]
        for (j in 1..word.length) next[j] = if (c == '*') previous[j] || (word[j-1] != '/' && next[j-1]) else previous[j-1] && (if (c == '?') word[j-1] != '/' else c == word[j-1])
        previous = next
    }
    return previous.last()
}

private data class Variable(val simple: Boolean,var value: String)

private data class RecipeLine(val number: Int,val text: String)

private class Recipe {
    val lines = mutableListOf<RecipeLine>()
}

private class Rule(val target: String,val deps: MutableList<String> = mutableListOf(),var recipe: Recipe? = null,var stem: String = "")

private data class Current(val targets: List<String>,val patterns: List<Rule>,var recipe: Recipe? = null)

private data class Condition(val outer: Boolean,var value: Boolean,var hadElse: Boolean,val line: Int)

private sealed interface Scope

private data class ForeachScope(val name: String,val value: String) : Scope

private data class CallScope(val values: List<String>) : Scope

private class Simulator {
    var files = sortedMapOf<String,Int>()
    var clock = 0
    var loaded = false
    val variables = sortedMapOf<String,Variable>()
    val rules = sortedMapOf<String,Rule>()
    val patterns = mutableListOf<Rule>()
    val phony = sortedSetOf<String>()
    var goal: String? = null
    val output = mutableListOf<String>()
    var location = "make"
    val scopes = mutableListOf<Scope>()
    val expanding = mutableSetOf<String>()
    var automatic = emptyMap<String,String>()
    fun error(reason: String): Nothing = throw Expansion(reason)
    fun diagnostic(e: Expansion) {
        output.add("$location: *** ${e.reason}.  Stop.")
    }
    fun tick(n: String) {
        clock++
        files[n] = clock
    }
    fun clear() {
        loaded = false
        variables.clear()
        rules.clear()
        patterns.clear()
        phony.clear()
        goal = null
        scopes.clear()
        expanding.clear()
        automatic = emptyMap()
    }
    fun closing(s: String,start: Int): Int {
        val opening = s[start]
        val close = if (opening == '(') ')' else '}'
        var depth = 0
        for (i in start until s.length) {
            if (s[i] == opening) depth++
            if (s[i] == close) {
                depth--
                if (depth == 0) return i
            }
        }
        error("unterminated variable reference")
    }
    fun outside(s: String): Map<Char,Int> {
        val result = mutableMapOf<Char,Int>()
        var i = 0
        while (i < s.length) {
            if (s[i] == '$') {
                if (i+1 < s.length && (s[i+1] == '(' || s[i+1] == '{')) i = closing(s,i+1)+1 else i = minOf(s.length,i+2)
            } else {
                if (s[i] in "=:;" && s[i] !in result) result[s[i]] = i
                i++
            }
        }
        return result
    }
    fun value(name: String): String {
        for (scope in scopes.asReversed()) when(scope) {
            is ForeachScope -> if (scope.name == name) return scope.value
            is CallScope -> if (name.isNotEmpty() && name.all {
                it in '0'..'9'
            }) return scope.values.getOrNull(name.toInt()) ?: ""
        }
        automatic[name]?.let {
            return it
        }
        val v = variables[name] ?: return ""
        if (v.simple) return v.value
        if (!expanding.add(name)) error("Recursive variable '$name' references itself (eventually)")
        try {
            return expand(v.value)
        } finally {
            expanding.remove(name)
        }
    }
    fun expand(s: String): String {
        val out = StringBuilder()
        var i = 0
        while (i < s.length) {
            if (s[i] != '$') {
                out.append(s[i++])
                continue
            }
            if (i+1 == s.length) break
            val c = s[i+1]
            when(c) {
                '$' -> {
                    out.append('$')
                    i += 2
                }
                '(','{' -> {
                    val end = closing(s,i+1)
                    out.append(reference(s.substring(i+2,end),c))
                    i = end+1
                } else -> {
                    out.append(value(c.toString()))
                    i += 2
                }
            }
        }
        return out.toString()
    }
    val functions = mapOf("subst" to (3 to 3),"patsubst" to (3 to 3),"strip" to (1 to 1),"findstring" to (2 to 2),"filter" to (2 to 2),"filter-out" to (2 to 2),"sort" to (1 to 1),"word" to (2 to 2),"wordlist" to (3 to 3),"words" to (1 to 1),"firstword" to (1 to 1),"lastword" to (1 to 1),"dir" to (1 to 1),"notdir" to (1 to 1),"suffix" to (1 to 1),"basename" to (1 to 1),"addsuffix" to (2 to 2),"addprefix" to (2 to 2),"wildcard" to (1 to 1),"foreach" to (3 to 3),"if" to (2 to 3),"call" to (1 to Int.MAX_VALUE),"value" to (1 to 1),"info" to (1 to 1),"warning" to (1 to 1),"error" to (1 to 1))
    fun reference(content: String,opening: Char): String {
        val space = content.indexOf(' ')
        if (space >= 0 && content.take(space) in functions) return function(content.take(space),content.drop(space+1).trimStart(' '),opening)
        val n = expand(content)
        val colon = n.indexOf(':')
        val equal = if (colon >= 0) n.indexOf('=',colon+1) else -1
        if (equal < 0) return value(n)
        var p = n.substring(colon+1,equal)
        var r = n.drop(equal+1)
        if ('%' !in p) {
            p = "%$p"
            r = "%$r"
        }
        return words(value(n.take(colon))).joinToString(" ") {
            replaceWord(it,p,r)
        }
    }
    fun arguments(text: String,opening: Char,maximum: Int): List<String> {
        val close = if (opening == '(') ')' else '}'
        var depth = 0
        var start = 0
        val result = mutableListOf<String>()
        for ((i,c) in text.withIndex()) {
            if (c == opening) depth++
            if (c == close) depth--
            if (c == ',' && depth == 0 && result.size < maximum-1) {
                result.add(text.substring(start,i))
                start = i+1
            }
        }
        result.add(text.drop(start))
        return result
    }
    fun function(name: String,text: String,opening: Char): String {
        val limits = functions.getValue(name)
        val raw = arguments(text,opening,limits.second)
        if (raw.size < limits.first) error("insufficient number of arguments (${raw.size}) to function '$name'")
        if (name == "foreach") {
            val variable = expand(raw[0]).trim(' ')
            val list = words(expand(raw[1]))
            return list.joinToString(" ") {
                word -> scopes.add(ForeachScope(variable,word))
                try {
                    expand(raw[2])
                } finally {
                    scopes.removeAt(scopes.lastIndex)
                }
            }
        }
        if (name == "if") {
            val condition = expand(raw[0]).trim(' ')
            return if (condition.isNotEmpty()) expand(raw[1]) else if (raw.size == 3) expand(raw[2]) else ""
        }
        val args = raw.map {
            val expanded = expand(it)
            if (name == "subst" || name == "call") expanded else expanded.trim(' ')
        }
        fun list(i: Int) = words(args[i])
        fun joined(xs: List<String>) = xs.joinToString(" ")
        when(name) {
            "call" -> {
                val n = args[0].trim(' ')
                val v = variables[n] ?: return ""
                if (v.simple) return v.value
                scopes.add(CallScope(listOf(n)+args.drop(1)))
                try {
                    return expand(v.value)
                } finally {
                    scopes.removeAt(scopes.lastIndex)
                }
            }
            "value" -> return variables[args[0]]?.value ?: ""
            "info" -> {
                output.add(args[0])
                return ""
            }
            "warning" -> {
                output.add("$location: ${args[0]}")
                return ""
            }
            "error" -> error(args[0])
            "subst" -> return if (args[0].isEmpty()) args[2] else args[2].replace(args[0],args[1])
            "patsubst" -> return joined(list(2).map {
                replaceWord(it,args[0],args[1])
            })
            "strip" -> return joined(list(0))
            "findstring" -> return if (args[1].contains(args[0])) args[0] else ""
            "filter","filter-out" -> return joined(list(1).filter {
                w -> list(0).any {
                    stem(it,w) != null
                } == (name == "filter")
            })
            "sort" -> return joined(list(0).toSortedSet().toList())
            "word" -> {
                val n = args[0]
                if (n.isEmpty() || !n.all {
                    it in '0'..'9'
                }) error("non-numeric first argument to 'word' function: '$n'")
                if (n.toInt() == 0) error("first argument to 'word' function must be greater than 0")
                return list(1).getOrNull(n.toInt()-1) ?: ""
            }
            "wordlist" -> {
                val a = args[0]
                val b = args[1]
                if (a.isEmpty() || !a.all {
                    it in '0'..'9'
                }) error("non-numeric first argument to 'wordlist' function: '$a'")
                if (b.isEmpty() || !b.all {
                    it in '0'..'9'
                }) error("non-numeric second argument to 'wordlist' function: '$b'")
                if (a.toInt() == 0) error("invalid first argument to 'wordlist' function: '$a'")
                return joined(list(2).filterIndexed {
                    i,_ -> i+1 >= a.toInt() && i+1 <= b.toInt()
                })
            }
            "words" -> return list(0).size.toString()
            "firstword" -> return list(0).firstOrNull() ?: ""
            "lastword" -> return list(0).lastOrNull() ?: ""
            "dir" -> return joined(list(0).map {
                it.take(it.lastIndexOf('/')+1).ifEmpty {
                    "./"
                }
            })
            "notdir" -> return joined(list(0).map {
                it.substring(it.lastIndexOf('/')+1)
            })
            "suffix" -> return joined(list(0).filter {
                it.lastIndexOf('.') > it.lastIndexOf('/')
            }.map {
                it.substring(it.lastIndexOf('.'))
            })
            "basename" -> return joined(list(0).map {
                if (it.lastIndexOf('.') > it.lastIndexOf('/')) it.take(it.lastIndexOf('.')) else it
            })
            "addsuffix" -> return joined(list(1).map {
                it+args[0]
            })
            "addprefix" -> return joined(list(1).map {
                args[0]+it
            })
            "wildcard" -> return joined(list(0).flatMap {
                glob(it)
            })
        }
        return ""
    }
    fun glob(pattern: String) = if ('*' in pattern || '?' in pattern) files.keys.filter {
        wildcard(pattern,it)
    } else if (pattern in files) listOf(pattern) else emptyList()
    fun register(n: String,deps: List<String>) {
        val r = rules.getOrPut(n) {
            Rule(n)
        }
        for (d in unique(deps)) if (d !in r.deps) r.deps.add(d)
        if (goal == null && !n.startsWith('.')) goal = n
    }
    fun addRecipe(current: Current,line: RecipeLine) {
        if (current.targets.isEmpty() && current.patterns.isEmpty()) return
        if (current.recipe == null) {
            val fresh = Recipe()
            for (n in current.targets) {
                val old = rules.getValue(n).recipe
                if (old != null) {
                    output.add("Makefile:${line.number}: warning: overriding recipe for target '$n'")
                    output.add("Makefile:${old.lines.first().number}: warning: ignoring old recipe for target '$n'")
                }
                rules.getValue(n).recipe = fresh
            }
            for (r in current.patterns) r.recipe = fresh
            current.recipe = fresh
        }
        current.recipe!!.lines.add(line)
    }
    fun load(body: List<String>) {
        clear()
        var current: Current? = null
        val conditions = mutableListOf<Condition>()
        fun active() = conditions.lastOrNull()?.let {
            it.outer && it.value
        }?: true
        var i = 0
        try {
            while (i < body.size) {
                val lineNumber = i+1
                location = "Makefile:$lineNumber"
                var text = body[i++]
                if (text.startsWith('>')) {
                    if (!active()) continue
                    val rule = current ?: error("recipe commences before first target")
                    addRecipe(rule,RecipeLine(lineNumber,text.drop(1).trimStart(' ')))
                    continue
                }
                while (text.endsWith('\\') && i < body.size) text = text.dropLast(1).trimEnd(' ')+" "+body[i++].trimStart(' ')
                text = text.substringBefore('#').trim(' ')
                val first = text.substringBefore(' ')
                val rest = text.substringAfter(' ',"").trim(' ')
                when(first) {
                    "ifdef","ifndef","ifeq","ifneq" -> {
                        val outer = active()
                        var truth = false
                        if (outer) {
                            if (first == "ifdef" || first == "ifndef") {
                                val name = expand(rest).trim(' ')
                                truth = variables[name]?.value?.isNotEmpty() == true
                                if (first == "ifndef") truth = !truth
                            } else {
                                if (rest.length < 2 || !rest.startsWith('(') || !rest.endsWith(')')) error("invalid syntax in conditional")
                                val inner = rest.substring(1,rest.length-1)
                                var depth = 0
                                var comma = -1
                                for ((j,c) in inner.withIndex()) {
                                    if (c == '(') depth++
                                    if (c == ')') depth--
                                    if (c == ',' && depth == 0) {
                                        comma = j
                                        break
                                    }
                                }
                                if (comma < 0) error("invalid syntax in conditional")
                                val left = expand(inner.take(comma)).trim(' ')
                                val right = expand(inner.drop(comma+1)).trim(' ')
                                truth = (left == right) == (first == "ifeq")
                            }
                        }
                        conditions.add(Condition(outer,truth,false,lineNumber))
                        continue
                    }
                    "else" -> {
                        val condition = conditions.lastOrNull() ?: error("extraneous 'else'")
                        if (condition.hadElse) error("only one 'else' per conditional")
                        condition.value = !condition.value
                        condition.hadElse = true
                        continue
                    }
                    "endif" -> {
                        if (conditions.isEmpty()) error("extraneous 'endif'")
                        conditions.removeAt(conditions.lastIndex)
                        continue
                    }
                }
                if (text.isEmpty() || !active()) continue
                val positions = outside(text)
                val equal = positions['=']
                val colon = positions[':']
                if (equal != null && (colon == null || colon >= equal-1)) {
                    val special = equal > 0 && text[equal-1] in ":+?"
                    val op = if (special) text.substring(equal-1,equal+1) else "="
                    val n = text.take(equal - (if (special) 1 else 0)).trim(' ')
                    val rhs = text.drop(equal+1).trim(' ')
                    if (n.isEmpty()) error("empty variable name")
                    val old = variables[n]
                    when(op) {
                        "=" -> variables[n] = Variable(false,rhs)
                        ":=" -> variables[n] = Variable(true,expand(rhs))
                        "?=" -> if (old == null) variables[n] = Variable(false,rhs)
                        "+=" -> if (old == null) variables[n] = Variable(false,rhs) else {
                            val append = if (old.simple) expand(rhs) else rhs
                            old.value = if (old.value.isEmpty()) append else old.value+" "+append
                        }
                    }
                    current = null
                } else if (colon != null) {
                    val targets = unique(words(expand(text.take(colon))))
                    var remainder = text.drop(colon+1)
                    val semi = outside(remainder)[';']
                    val inline = semi?.let {
                        remainder.drop(it+1).trimStart(' ')
                    }
                    if (semi != null) remainder = remainder.take(semi)
                    val secondColon = outside(remainder)[':']
                    val targetPattern = secondColon?.let {
                        expand(remainder.take(it)).trim(' ')
                    }
                    if (secondColon != null) remainder = remainder.drop(secondColon+1)
                    val deps = words(expand(remainder))
                    val registered = mutableListOf<String>()
                    val implicit = mutableListOf<Rule>()
                    if (targets == listOf(".PHONY")) phony.addAll(deps) else if (targetPattern != null) {
                        if ('%' !in targetPattern) error("target pattern contains no '%'")
                        for (t in targets) {
                            val m = stem(targetPattern,t)
                            if (m == null || m.isEmpty()) output.add("Makefile:$lineNumber: target '$t' doesn't match the target pattern") else {
                                register(t,deps.map {
                                    substitute(it,m)
                                })
                                rules.getValue(t).stem = m
                                registered.add(t)
                            }
                        }
                    } else if (targets.any {
                        '%' in it
                    }) {
                        if (targets.any {
                            '%' !in it
                        }) error("mixed implicit and normal rules")
                        for (t in targets) {
                            val rule = Rule(t,deps.toMutableList())
                            patterns.add(rule)
                            implicit.add(rule)
                        }
                    } else for (t in targets) {
                        register(t,deps)
                        registered.add(t)
                    }
                    current = Current(registered,implicit)
                    if (inline != null) addRecipe(current,RecipeLine(lineNumber,inline))
                } else if (expand(text).trim(' ').isNotEmpty()) error("missing separator")
            }
            if (conditions.isNotEmpty()) {
                location = "Makefile:${conditions.last().line}"
                error("missing 'endif'")
            }
            loaded = true
            output.add("Makefile loaded: lines=${body.size} variables=${variables.size} targets=${rules.size} patterns=${patterns.count { it.recipe != null }} goal=${goal ?: "(none)"}")
        } catch (e: Expansion) {
            diagnostic(e)
            clear()
        } finally {
            location = "make"
            scopes.clear()
            expanding.clear()
            automatic = emptyMap()
        }
    }
    data class Determined(val deps: List<String>,val recipe: Recipe?,val stem: String,val source: Boolean = false,val absent: Boolean = false)
    fun determine(t: String): Determined {
        val explicit = rules[t]
        if (explicit?.recipe != null) return Determined(explicit.deps.toList(),explicit.recipe,explicit.stem)
        if (t !in phony) {
            val candidates = patterns.mapIndexedNotNull {
                i,r -> val m = if (r.recipe != null) stem(r.target,t) else null
                if (m.isNullOrEmpty()) null else Triple(r,m,i)
            }.sortedWith(compareBy<Triple<Rule,String,Int>> {
                it.second.length
            }.thenBy {
                it.third
            })
            for ((r,m,_) in candidates) {
                val deps = r.deps.map {
                    substitute(it,m)
                }
                if (deps.all {
                    it in files || it in rules
                }) return Determined(unique(deps+(explicit?.deps ?: emptyList())),r.recipe,m)
            }
        }
        if (explicit != null || t in phony) return Determined(explicit?.deps?.toList() ?: emptyList(),null,explicit?.stem ?: "")
        return Determined(emptyList(),null,"",source=t in files,absent=t !in files)
    }
    fun make(args: List<String>) {
        val options = mutableSetOf<Char>()
        val goals = mutableListOf<String>()
        for (arg in args) if (arg.startsWith('-')) {
            for (c in arg.drop(1)) {
                if (c !in "nBkis") {
                    output.add("make: invalid option -- '$c'")
                    return
                }
                options.add(c)
            }
        } else goals.add(arg)
        if (goals.isEmpty()) {
            if (!loaded) {
                output.add("make: *** No targets specified and no makefile found.  Stop.")
                return
            }
            if (goal == null) {
                output.add("make: *** No targets.  Stop.")
                return
            }
            goals.add(goal!!)
        }
        val dry = 'n' in options
        val keep = 'k' in options
        val original = if (dry) files.toSortedMap() else null
        val oldClock = clock
        val results = mutableMapOf<String,Int>()
        val usedRules = mutableMapOf<String,Determined>()
        val being = mutableSetOf<String>()
        var runs = 0
        fun targetTime(t: String) = if (t in phony) null else files[t]
        fun execute(command: String): Int {
            val w = words(command)
            when(w[0]) {
                "echo" -> output.add(w.drop(1).joinToString(" "))
                "touch" -> for (n in w.drop(1)) tick(n)
                "rm" -> {
                    val force = w.getOrNull(1) == "-f"
                    var status = 0
                    for (p in w.drop(if (force) 2 else 1)) {
                        val names = glob(p).ifEmpty {
                            listOf(p)
                        }
                        for (n in names) if (files.remove(n) == null && !force) {
                            output.add("rm: cannot remove '$n': No such file or directory")
                            status = 1
                        }
                    }
                    return status
                }
                "false" -> return 1
                "exit" -> return w.getOrNull(1)?.toInt() ?: 0
            }
            return 0
        }
        fun run(t: String,d: Determined,deps: List<String>,fresh: List<String>): Int {
            automatic = mapOf("@" to t,"<" to (deps.firstOrNull() ?: ""),"^" to deps.joinToString(" "),"?" to fresh.joinToString(" "),"*" to d.stem)
            val expanded = mutableListOf<Pair<RecipeLine,String>>()
            try {
                for (line in d.recipe!!.lines) {
                    location = "Makefile:${line.number}"
                    expanded.add(line to expand(line.text))
                }
            } catch (e: Expansion) {
                diagnostic(e)
                throw Abort()
            } finally {
                automatic = emptyMap()
                location = "make"
            }
            for ((line,text) in expanded) {
                val prefix = text.takeWhile {
                    it == ' ' || it == '@' || it == '-'
                }
                val command = text.drop(prefix.length).trimEnd(' ')
                if (command.isEmpty()) continue
                if (dry || ('@' !in prefix && 's' !in options)) output.add(command)
                if (dry) continue
                val status = execute(command)
                if (status != 0) {
                    if ('-' in prefix || 'i' in options) output.add("make: [Makefile:${line.number}: $t] Error $status (ignored)") else {
                        output.add("make: *** [Makefile:${line.number}: $t] Error $status")
                        if (!keep) throw Abort()
                        return 2
                    }
                }
            }
            return 1
        }
        fun build(t: String,parent: String?): Int {
            results[t]?.let {
                return it
            }
            val d = determine(t)
            usedRules[t] = d
            if (d.absent) {
                results[t] = 2
                val reason = "make: *** No rule to make target '$t'"+(parent?.let {
                    ", needed by '$it'"
                }?: "")+"."
                output.add(reason+if (keep) "" else "  Stop.")
                if (!keep) throw Abort()
                return 2
            }
            if (d.source) {
                results[t] = 1
                return 1
            }
            being.add(t)
            val deps = mutableListOf<String>()
            var failed = false
            for (q in d.deps) if (q in being) output.add("make: Circular $t <- $q dependency dropped.") else {
                deps.add(q)
                if (build(q,t) != 1) failed = true
            }
            being.remove(t)
            var result = 3
            if (!failed) {
                val time = targetTime(t)
                val fresh = deps.filter {
                    'B' in options || time == null || targetTime(it) == null || targetTime(it)!! > time
                }
                result = if (d.recipe == null || ('B' !in options && time != null && fresh.isEmpty())) 1 else {
                    runs++
                    val status = run(t,d,deps,fresh)
                    if (status == 1 && t !in phony) tick(t)
                    status
                }
            }
            results[t] = result
            return result
        }
        try {
            for (g in goals) {
                val before = runs
                val result = build(g,null)
                if (result == 1 && runs == before) output.add(if (g in phony || usedRules.getValue(g).recipe == null) "make: Nothing to be done for '$g'." else "make: '$g' is up to date.") else if (result == 3) output.add("make: Target '$g' not remade because of errors.")
            }
        } catch (_: Abort) {
        } finally {
            if (dry) {
                files = original!!
                clock = oldClock
            }
            automatic = emptyMap()
            scopes.clear()
            expanding.clear()
            location = "make"
        }
    }
    fun command(line: String) {
        output.add("$ $line")
        val w = words(line)
        when(w[0]) {
            "MAKE" -> make(w.drop(1))
            "TOUCH" -> for (n in w.drop(1)) tick(n)
            "RM" -> for (n in w.drop(1)) if (files.remove(n) == null) output.add("rm: cannot remove '$n': No such file or directory")
            "FILES" -> {
                output.add("clock $clock")
                output.addAll(files.map {
                    (n,t) -> "$n $t"
                })
            }
            "RULES" -> if (loaded) {
                for (r in rules.values+patterns.filter {
                    it.recipe != null
                }) {
                    output.add(r.target+":"+r.deps.joinToString("") {
                        " $it"
                    })
                    r.recipe?.lines?.forEach {
                        output.add(">"+it.text)
                    }
                }
                if (phony.isNotEmpty()) output.add(".PHONY:"+phony.joinToString("") {
                    " $it"
                })
            }
            "VARS" -> if (loaded) {
                try {
                    for ((n,v) in variables) {
                        val s = value(n).trim(' ')
                        output.add(n+" "+if (v.simple) ":="+(if (s.isEmpty()) "" else " $s") else "="+(if (s.isEmpty()) "" else " $s"))
                    }
                } catch (e: Expansion) {
                    diagnostic(e)
                }
            }
            "EXPAND" -> try {
                output.add("["+expand(line.drop(7))+"]")
            } catch (e: Expansion) {
                diagnostic(e)
            }
        }
    }
}

fun main() {
    val input = generateSequence(::readLine).toList()
    val simulator = Simulator()
    var i = 1
    while (input[i] != "END FILES") {
        val w = words(input[i++])
        val time = w[1].toInt()
        simulator.files[w[0]] = time
        simulator.clock = maxOf(simulator.clock,time)
    }
    i++
    while (input[i] != "QUIT") {
        val line = input[i++]
        if (line == "MAKEFILE") {
            simulator.output.add("$ MAKEFILE")
            val body = mutableListOf<String>()
            while (input[i] != "END MAKEFILE") body.add(input[i++])
            i++
            simulator.load(body)
        } else simulator.command(line)
    }
    for (line in simulator.output) println(line)
}
