private class Fault(val word: String, val reason: String, val code: Long?) : RuntimeException(reason)

private class Exit : RuntimeException()

private class Word(val name: String, val original: String, val kind: String, val here: Int) {
    var value = 0L
    var address = 0
    var token = 0
    var deferred: Word? = null
    var does: Word? = null
    var doesStart = 0
    var locals = 0
    val code = mutableListOf<Instruction>()
}

private class Instruction(val op: String, val spelling: String, val value: Long = 0, val word: Word? = null, val text: String = "", val slots: List<Int> = emptyList(), var target: Int = 0)

private class Control(var kind: String, val index: Int, val begin: Int = 0) {
    val leaves = mutableListOf<Int>()
    val ends = mutableListOf<Int>()
}

private class Compiler(val word: Word, val anonymous: Boolean) {
    val locals = mutableMapOf<String, Int>()
    val control = mutableListOf<Control>()
}

private class Forth {
    val data = mutableListOf<Long>()
    val returns = mutableListOf<Long>()
    val memory = mutableListOf(10L)
    val users = mutableListOf<Word>()
    val builtins = mutableMapOf<String, Word>()
    val tokens = mutableListOf<Word>()
    val output = mutableListOf<String>()
    var pending = ""
    var compiler: Compiler? = null
    var line = ""
    var at = 0
    var depth = 0
    val compileOnly = setOf("IF", "ELSE", "THEN", "DO", "?DO", "LOOP", "+LOOP", "LEAVE", "UNLOOP", "I", "J", "BEGIN", "UNTIL", "WHILE", "REPEAT", "AGAIN", "CASE", "OF", "ENDOF", "ENDCASE", "EXIT", "RECURSE", "DOES>", ";", ">R", "R>", "R@", "ABORT\"", "[']", "{:")
    val interpretOnly = setOf(":", ":NONAME", "FORGET")
    val both = setOf(".\"", "(", "\\", "TO", "IS")
    init {
        val names = "+ - * / MOD /MOD */ */MOD NEGATE ABS MIN MAX 1+ 1- 2* 2/ = <> < > 0= 0<> 0< 0> WITHIN TRUE FALSE AND OR XOR INVERT DUP ?DUP DROP SWAP OVER ROT -ROT NIP TUCK 2DUP 2DROP 2SWAP 2OVER DEPTH PICK ROLL . .R .S ? CR EMIT SPACE SPACES BL ! @ +! , ALLOT HERE CELLS CELL+ BASE HEX DECIMAL CREATE VARIABLE CONSTANT VALUE DEFER ' EXECUTE CATCH THROW ABORT WORDS"
        for (n in names.split(' ')) builtins[n] = Word(n, n, "builtin", 8)
    }

    fun fault(word: String, reason: String, code: Long? = null): Nothing = throw Fault(word, reason, code)

    fun pop(n: Int, word: String): List<Long> {
        if (data.size < n) fault(word, "stack underflow", -4)
        val result = data.takeLast(n)
        repeat(n) {
            data.removeAt(data.lastIndex)
        }
        return result
    }

    fun push(n: Long, word: String) {
        data.add(n)
        if (data.size > 1000) fault(word, "stack overflow", -3)
    }

    fun pushAll(values: List<Long>, word: String) {
        for (n in values) push(n, word)
    }

    fun returnNeed(n: Int, word: String) {
        if (returns.size < n) fault(word, "return stack underflow", -6)
    }

    fun returnPush(n: Long, word: String) {
        returns.add(n)
        if (returns.size > 1000) fault(word, "return stack overflow", -5)
    }

    fun address(n: Long, word: String): Int {
        if (n < 0 || n % 8 != 0L || n >= memory.size * 8L) fault(word, "invalid address", -9)
        return (n / 8).toInt()
    }

    fun readWord(): String? {
        while (at < line.length && line[at] == ' ') at++
        val start = at
        while (at < line.length && line[at] != ' ') at++
        return if (at == start) null else line.substring(start, at)
    }

    fun readName(owner: String) = readWord() ?: fault(owner, "missing name", -16)

    fun find(raw: String): Word? {
        val n = raw.uppercase()
        return users.lastOrNull {
            it.name == n
        } ?: builtins[n]
    }

    fun parseNumber(raw: String, owner: String, base: Long = memory[0]): Long? {
        if (raw.length == 3 && raw.first() == '\'' && raw.last() == '\'') return raw[1].code.toLong()
        var text = raw.uppercase()
        var radix = base
        if (text.firstOrNull() in listOf('$', '#', '%')) {
            radix = when (text[0]) {
                '$' -> 16
                '#' -> 10
                else -> 2
            }
            text = text.drop(1)
        } else if (radix !in 2L..36L) fault(owner, "invalid base", -40)
        var sign = 1L
        if (text.startsWith('-')) {
            sign = -1
            text = text.drop(1)
        }
        if (text.isEmpty()) return null
        val digits = mutableListOf<Int>()
        for (c in text) {
            val digit = if (c in '0'..'9') c - '0' else if (c in 'A'..'Z') c - 'A' + 10 else return null
            if (digit >= radix) return null
            digits.add(digit)
        }
        return sign * digits.fold(0L) {
            value, digit -> value * radix + digit
        }
    }

    fun checkName(raw: String) {
        val n = raw.uppercase()
        if (n in compileOnly || n in interpretOnly || n in both || parseNumber(raw, raw, 10) != null) fault(raw, "invalid name", -19)
    }

    fun token(word: Word): Long {
        if (word.token == 0) {
            tokens.add(word)
            word.token = tokens.size
        }
        return word.token.toLong()
    }

    fun tokenWord(value: Long, owner: String): Word {
        if (value < 1 || value > tokens.size) fault(owner, "invalid argument", -24)
        return tokens[value.toInt() - 1]
    }

    fun radix(owner: String): Int {
        val b = memory[0]
        if (b !in 2L..36L) fault(owner, "invalid base", -40)
        return b.toInt()
    }

    fun formatted(value: Long, base: Int): String {
        var n = kotlin.math.abs(value)
        val out = StringBuilder()
        do {
            out.append("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"[(n % base).toInt()])
            n /= base
        }
        while (n > 0)
        if (value < 0) out.append('-')
        return out.reverse().toString()
    }

    fun flush() {
        output.add(pending.trimEnd(' '))
        pending = ""
    }

    fun quotient(a: Long, b: Long): Long {
        val q = a / b
        return if (a % b != 0L && (a < 0) != (b < 0)) q - 1 else q
    }

    fun executeDefinition(definition: Word, start: Int, owner: String) {
        if (depth == 100) fault(owner, "nesting too deep", -7)
        depth++
        val oldReturn = returns.size
        val locals = LongArray(definition.locals)
        var pc = start
        try {
            while (pc < definition.code.size) {
                val i = definition.code[pc]
                pc++
                when (i.op) {
                    "literal" -> push(i.value, i.spelling)
                    "call" -> execute(i.word!!, i.spelling)
                    "local" -> push(locals[i.value.toInt()], i.spelling)
                    "local-set" -> locals[i.value.toInt()] = pop(1, i.spelling)[0]
                    "locals" -> {
                        val a = pop(i.slots.size, i.spelling)
                        for (j in i.slots.indices) locals[i.slots[j]] = a[j]
                    }
                    "value-set" -> memory[i.word!!.address / 8] = pop(1, i.spelling)[0]
                    "defer-set" -> i.word!!.deferred = tokenWord(pop(1, i.spelling)[0], i.spelling)
                    "jump" -> pc = i.target
                    "zero" -> if (pop(1, i.spelling)[0] == 0L) pc = i.target
                    "exit" -> throw Exit()
                    "does" -> {
                        val latest = users.lastOrNull()
                        if (latest == null || latest.kind != "create") fault(i.spelling, "no CREATE word", -31)
                        latest.does = definition
                        latest.doesStart = pc
                        throw Exit()
                    }
                    "abort-string" -> if (pop(1, i.spelling)[0] != 0L) fault(i.spelling, i.text, -2)
                    "write" -> pending += i.text
                    "do", "?do" -> {
                        val a = pop(2, i.spelling)
                        if (i.op == "?do" && a[0] == a[1]) pc = i.target else {
                            returnPush(a[0], i.spelling)
                            returnPush(a[1], i.spelling)
                        }
                    }
                    "loop", "+loop" -> {
                        val step = if (i.op == "loop") 1L else pop(1, i.spelling)[0]
                        returnNeed(2, i.spelling)
                        val index = returns.last()
                        val limit = returns[returns.lastIndex - 1]
                        val next = index + step
                        if ((index - limit < 0) != (next - limit < 0)) {
                            returns.removeAt(returns.lastIndex)
                            returns.removeAt(returns.lastIndex)
                        } else {
                            returns[returns.lastIndex] = next
                            pc = i.target
                        }
                    }
                    "leave" -> {
                        returnNeed(2, i.spelling)
                        repeat(2) {
                            returns.removeAt(returns.lastIndex)
                        }
                        pc = i.target
                    }
                    "of" -> {
                        val a = pop(2, i.spelling)
                        if (a[0] != a[1]) {
                            push(a[0], i.spelling)
                            pc = i.target
                        }
                    }
                    "endcase" -> pop(1, i.spelling)
                    ">R" -> returnPush(pop(1, i.spelling)[0], i.spelling)
                    "R>" -> {
                        returnNeed(1, i.spelling)
                        push(returns.removeAt(returns.lastIndex), i.spelling)
                    }
                    "R@", "I" -> {
                        returnNeed(1, i.spelling)
                        push(returns.last(), i.spelling)
                    }
                    "J" -> {
                        returnNeed(3, i.spelling)
                        push(returns[returns.size - 3], i.spelling)
                    }
                    "UNLOOP" -> {
                        returnNeed(2, i.spelling)
                        repeat(2) {
                            returns.removeAt(returns.lastIndex)
                        }
                    }
                }
            }
        } catch (_: Exit) {
        }
        while (returns.size > oldReturn) returns.removeAt(returns.lastIndex)
        depth--
    }

    fun execute(initial: Word, originalSpelling: String) {
        var word = initial
        var spelling = originalSpelling
        while (word.kind == "defer") {
            val target = word.deferred ?: fault(spelling, "deferred word not set", -21)
            word = target
            spelling = target.name
        }
        when (word.kind) {
            "colon" -> executeDefinition(word, 0, spelling)
            "create", "variable" -> {
                push(word.address.toLong(), spelling)
                word.does?.let {
                    executeDefinition(it, word.doesStart, spelling)
                }
            }
            "constant" -> push(word.value, spelling)
            "value" -> push(memory[word.address / 8], spelling)
            else -> builtin(word.name, spelling)
        }
    }

    fun builtin(name: String, owner: String) {
        when (name) {
            "+", "-", "*", "/", "MOD", "/MOD", "MIN", "MAX", "=", "<>", "<", ">", "AND", "OR", "XOR" -> {
                val a = pop(2, owner)
                val x = a[0]
                val y = a[1]
                if (name in setOf("/", "MOD", "/MOD") && y == 0L) fault(owner, "division by zero", -10)
                val v = when (name) {
                    "+" -> x + y
                    "-" -> x - y
                    "*" -> x * y
                    "/", "/MOD" -> quotient(x, y)
                    "MOD" -> x - y * quotient(x, y)
                    "MIN" -> minOf(x, y)
                    "MAX" -> maxOf(x, y)
                    "=" -> if (x == y) -1L else 0L
                    "<>" -> if (x != y) -1L else 0L
                    "<" -> if (x < y) -1L else 0L
                    ">" -> if (x > y) -1L else 0L
                    "AND" -> x and y
                    "OR" -> x or y
                    else -> x xor y
                }
                if (name == "/MOD") push(x - y * v, owner)
                push(v, owner)
            }
            "*/", "*/MOD" -> {
                val a = pop(3, owner)
                if (a[2] == 0L) fault(owner, "division by zero", -10)
                val p = a[0] * a[1]
                val q = quotient(p, a[2])
                if (name == "*/MOD") push(p - a[2] * q, owner)
                push(q, owner)
            }
            "NEGATE", "ABS", "1+", "1-", "2*", "2/", "0=", "0<>", "0<", "0>", "INVERT", "CELLS", "CELL+" -> {
                val a = pop(1, owner)[0]
                push(when (name) {
                    "NEGATE" -> -a
                    "ABS" -> kotlin.math.abs(a)
                    "1+" -> a + 1
                    "1-" -> a - 1
                    "2*" -> 2 * a
                    "2/" -> quotient(a, 2)
                    "0=" -> if (a == 0L) -1 else 0
                    "0<>" -> if (a != 0L) -1 else 0
                    "0<" -> if (a < 0) -1 else 0
                    "0>" -> if (a > 0) -1 else 0
                    "INVERT" -> a.inv()
                    "CELLS" -> 8 * a
                    else -> a + 8
                }, owner)
            }
            "WITHIN" -> {
                val a = pop(3, owner)
                push(if (a[1] <= a[0] && a[0] < a[2]) -1 else 0, owner)
            }
            "TRUE" -> push(-1, owner)
            "FALSE", "BASE" -> push(0, owner)
            "BL" -> push(32, owner)
            "DEPTH" -> push(data.size.toLong(), owner)
            "HERE" -> push(memory.size * 8L, owner)
            "DUP", "?DUP", "DROP", "SWAP", "OVER", "ROT", "-ROT", "NIP", "TUCK", "2DUP", "2DROP", "2SWAP", "2OVER" -> {
                val count = when (name) {
                    "DUP", "?DUP", "DROP" -> 1
                    "ROT", "-ROT" -> 3
                    "2SWAP", "2OVER" -> 4
                    else -> 2
                }
                val a = pop(count, owner)
                val values = when (name) {
                    "DUP" -> listOf(a[0], a[0])
                    "?DUP" -> if (a[0] == 0L) a else listOf(a[0], a[0])
                    "DROP", "2DROP" -> emptyList()
                    "SWAP" -> listOf(a[1], a[0])
                    "OVER" -> a + a[0]
                    "ROT" -> listOf(a[1], a[2], a[0])
                    "-ROT" -> listOf(a[2], a[0], a[1])
                    "NIP" -> listOf(a[1])
                    "TUCK" -> listOf(a[1], a[0], a[1])
                    "2DUP" -> a + a
                    "2SWAP" -> listOf(a[2], a[3], a[0], a[1])
                    else -> a + a.take(2)
                }
                pushAll(values, owner)
            }
            "PICK", "ROLL" -> {
                val u = pop(1, owner)[0]
                if (u < 0) fault(owner, "invalid argument", -24)
                if (u >= data.size) fault(owner, "stack underflow", -4)
                val i = data.size - 1 - u.toInt()
                val v = if (name == "ROLL") data.removeAt(i) else data[i]
                push(v, owner)
            }
            "." -> {
                val n = pop(1, owner)[0]
                pending += formatted(n, radix(owner)) + " "
            }
            ".R" -> {
                val a = pop(2, owner)
                val s = formatted(a[0], radix(owner))
                if (a[1] > s.length) pending += " ".repeat((a[1] - s.length).toInt())
                pending += s
            }
            ".S" -> {
                val b = radix(owner)
                pending += "<${formatted(data.size.toLong(), b)}> " + data.joinToString("") {
                    formatted(it, b) + " "
                }
            }
            "?" -> {
                val i = address(pop(1, owner)[0], owner)
                pending += formatted(memory[i], radix(owner)) + " "
            }
            "CR" -> flush()
            "EMIT" -> {
                val c = pop(1, owner)[0]
                if (c !in 32L..126L) fault(owner, "invalid argument", -24)
                pending += c.toInt().toChar()
            }
            "SPACE" -> pending += " "
            "SPACES" -> {
                val n = pop(1, owner)[0]
                if (n > 0) pending += " ".repeat(n.toInt())
            }
            "!", "+!" -> {
                val a = pop(2, owner)
                val i = address(a[1], owner)
                memory[i] = if (name == "!") a[0] else memory[i] + a[0]
            }
            "@" -> {
                val i = address(pop(1, owner)[0], owner)
                push(memory[i], owner)
            }
            "," -> memory.add(pop(1, owner)[0])
            "ALLOT" -> {
                val n = pop(1, owner)[0]
                if (n < 0 || n % 8 != 0L) fault(owner, "invalid argument", -24)
                repeat((n / 8).toInt()) {
                    memory.add(0)
                }
            }
            "HEX" -> memory[0] = 16
            "DECIMAL" -> memory[0] = 10
            "CREATE", "VARIABLE", "CONSTANT", "VALUE", "DEFER" -> {
                val raw = readName(owner)
                checkName(raw)
                val value = if (name in setOf("CONSTANT", "VALUE")) pop(1, owner)[0] else 0L
                val word = Word(raw.uppercase(), raw, name.lowercase(), memory.size * 8)
                word.address = memory.size * 8
                word.value = value
                users.add(word)
                if (name == "VARIABLE" || name == "VALUE") memory.add(value)
            }
            "'" -> {
                val raw = readName(owner)
                val word = find(raw) ?: fault(raw, "undefined word", -13)
                push(token(word), owner)
            }
            "EXECUTE" -> {
                val word = tokenWord(pop(1, owner)[0], owner)
                execute(word, word.name)
            }
            "CATCH" -> {
                val word = tokenWord(pop(1, owner)[0], owner)
                val saved = data.toList()
                val size = returns.size
                val level = depth
                var code = 0L
                try {
                    execute(word, word.name)
                } catch (e: Fault) {
                    if (e.code == null) throw e
                    data.clear()
                    data.addAll(saved)
                    while (returns.size > size) returns.removeAt(returns.lastIndex)
                    depth = level
                    code = e.code
                }
                push(code, owner)
            }
            "THROW" -> {
                val n = pop(1, owner)[0]
                if (n != 0L) fault(owner, "exception $n", n)
            }
            "ABORT" -> fault(owner, "aborted", -1)
            "WORDS" -> for (w in users.asReversed()) pending += w.name + " "
        }
    }

    fun string(owner: String): String {
        if (at == line.length) fault(owner, "unterminated string")
        val start = at + 1
        val end = line.indexOf('"', start)
        if (end < 0) fault(owner, "unterminated string")
        at = end + 1
        return line.substring(start, end)
    }

    fun target(raw: String, kind: String): Word {
        val w = find(raw) ?: fault(raw, "undefined word", -13)
        if (w.kind != kind) fault(raw, if (kind == "value") "not a value" else "not deferred")
        return w
    }

    fun process(raw: String) {
        val name = raw.uppercase()
        val compiling = compiler
        if (name == "\\") {
            at = line.length
            return
        }
        if (name == "(") {
            val end = line.indexOf(')', at)
            if (end < 0) fault(raw, "unterminated comment")
            at = end + 1
            return
        }
        if (compiling == null && name in compileOnly) fault(raw, "compile only")
        if (compiling != null && name in interpretOnly) fault(raw, "interpret only")
        if (name == ".\"" || name == "ABORT\"") {
            val text = string(raw)
            if (compiling == null) pending += text else compiling.word.code.add(Instruction(if (name == ".\"") "write" else "abort-string", raw, text = text))
            return
        }
        if (name == "TO" || name == "IS") {
            val n = readName(raw)
            val upper = n.uppercase()
            if (name == "TO" && compiling != null && upper in compiling.locals) {
                compiling.word.code.add(Instruction("local-set", raw, compiling.locals.getValue(upper).toLong()))
                return
            }
            val w = target(n, if (name == "TO") "value" else "defer")
            if (compiling != null) compiling.word.code.add(Instruction(if (name == "TO") "value-set" else "defer-set", raw, word = w))
            else if (name == "TO") memory[w.address / 8] = pop(1, raw)[0] else w.deferred = tokenWord(pop(1, raw)[0], raw)
            return
        }
        if (name == ":" || name == ":NONAME") {
            val n = if (name == ":") readName(raw).also(::checkName) else raw
            compiler = Compiler(Word(if (name == ":") n.uppercase() else ":NONAME", n, "colon", memory.size * 8), name == ":NONAME")
            return
        }
        if (name == "FORGET") {
            val n = readName(raw)
            val i = users.indexOfLast {
                it.name == n.uppercase()
            }
            if (i < 0) fault(n, "undefined word", -13)
            val here = users[i].here / 8
            while (users.size > i) users.removeAt(users.lastIndex)
            while (memory.size > here) memory.removeAt(memory.lastIndex)
            return
        }
        if (compiling != null) {
            compile(raw, name, compiling)
            return
        }
        val w = find(raw)
        if (w != null) execute(w, raw) else {
            val n = parseNumber(raw, raw) ?: fault(raw, "undefined word", -13)
            push(n, raw)
        }
    }

    fun compile(raw: String, name: String, c: Compiler) {
        val code = c.word.code

        fun mismatch(): Nothing = fault(raw, "control structure mismatch")

        fun top(vararg kinds: String): Control {
            val t = c.control.lastOrNull() ?: mismatch()
            if (t.kind !in kinds) mismatch()
            return t
        }

        fun append(op: String, value: Long = 0, target: Int = 0): Int {
            code.add(Instruction(op, raw, value, target = target))
            return code.lastIndex
        }
        when (name) {
            ";" -> {
                if (c.control.isNotEmpty()) {
                    val k = c.control.last().kind
                    fault(raw, "unclosed " + when (k) {
                        "ELSE" -> "IF"
                        "WHILE" -> "BEGIN"
                        else -> k
                    })
                }
                compiler = null
                if (c.anonymous) push(token(c.word), raw) else users.add(c.word)
            }
            "IF" -> c.control.add(Control("IF", append("zero")))
            "ELSE" -> {
                val t = top("IF")
                c.control.removeAt(c.control.lastIndex)
                val i = append("jump")
                code[t.index].target = code.size
                c.control.add(Control("ELSE", i))
            }
            "THEN" -> {
                val t = top("IF", "ELSE")
                c.control.removeAt(c.control.lastIndex)
                code[t.index].target = code.size
            }
            "BEGIN" -> c.control.add(Control("BEGIN", code.size))
            "UNTIL", "AGAIN" -> {
                val t = top("BEGIN")
                c.control.removeAt(c.control.lastIndex)
                append(if (name == "UNTIL") "zero" else "jump", target = t.index)
            }
            "WHILE" -> {
                val t = top("BEGIN")
                c.control.removeAt(c.control.lastIndex)
                c.control.add(Control("WHILE", append("zero"), t.index))
            }
            "REPEAT" -> {
                val t = top("WHILE")
                c.control.removeAt(c.control.lastIndex)
                append("jump", target = t.begin)
                code[t.index].target = code.size
            }
            "DO", "?DO" -> c.control.add(Control(name, append(if (name == "DO") "do" else "?do")))
            "LOOP", "+LOOP" -> {
                val t = top("DO", "?DO")
                c.control.removeAt(c.control.lastIndex)
                append(if (name == "LOOP") "loop" else "+loop", target = t.index + 1)
                code[t.index].target = code.size
                for (i in t.leaves) code[i].target = code.size
            }
            "LEAVE" -> {
                val t = c.control.lastOrNull {
                    it.kind == "DO" || it.kind == "?DO"
                } ?: mismatch()
                t.leaves.add(append("leave"))
            }
            "CASE" -> c.control.add(Control("CASE", code.size))
            "OF" -> {
                top("CASE")
                c.control.add(Control("OF", append("of")))
            }
            "ENDOF" -> {
                val t = top("OF")
                c.control.removeAt(c.control.lastIndex)
                val i = append("jump")
                code[t.index].target = code.size
                top("CASE").ends.add(i)
            }
            "ENDCASE" -> {
                val t = top("CASE")
                c.control.removeAt(c.control.lastIndex)
                append("endcase")
                for (i in t.ends) code[i].target = code.size
            }
            "EXIT" -> append("exit")
            "DOES>" -> {
                if (c.control.isNotEmpty()) mismatch()
                append("does")
            }
            "RECURSE" -> code.add(Instruction("call", raw, word = c.word))
            "[']" -> {
                val n = readName(raw)
                val word = find(n) ?: fault(n, "undefined word", -13)
                append("literal", token(word))
            }
            "{:" -> {
                val names = mutableListOf<String>()
                var closed = false
                while (true) {
                    val n = readWord() ?: break
                    if (n.uppercase() == ":}") {
                        closed = true
                        break
                    }
                    names.add(n)
                }
                if (!closed) fault(raw, "unterminated locals")
                val slots = mutableListOf<Int>()
                for (n in names.takeWhile {
                    it != "--"
                }) {
                    checkName(n)
                    val slot = c.word.locals++
                    slots.add(slot)
                    c.locals[n.uppercase()] = slot
                }
                code.add(Instruction("locals", raw, slots = slots))
            }
            ">R", "R>", "R@", "I", "J", "UNLOOP" -> append(name)
            else -> if (name in c.locals) append("local", c.locals.getValue(name).toLong()) else {
                val word = find(raw)
                if (word != null) code.add(Instruction("call", raw, word = word)) else append("literal", parseNumber(raw, raw) ?: fault(raw, "undefined word", -13))
            }
        }
    }

    fun input(text: String) {
        line = text
        at = 0
        try {
            while (true) process(readWord() ?: break)
        } catch (e: Fault) {
            if (pending.isNotEmpty()) flush()
            output.add("ERROR ${e.word}: ${e.reason}")
            data.clear()
            returns.clear()
            compiler = null
            depth = 0
        }
        if (pending.isNotEmpty()) flush()
    }
}

fun main() {
    val forth = Forth()
    while (true) {
        val line = readLine() ?: break
        if (line == "BYE") {
            forth.compiler?.let {
                forth.output.add("ERROR ${it.word.original}: unterminated definition")
            }
            break
        }
        forth.input(line)
    }
    for (line in forth.output) println(line)
}
