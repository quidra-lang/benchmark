import java.io.File
data class Flags(val i: Boolean, val m: Boolean, val s: Boolean)
typealias Capture = List<Int?>
sealed interface Instruction {
    data class Char(val code: Int) : Instruction
    data object Any : Instruction
    data class Class(val set: Set<Int>, val negated: Boolean) : Instruction
    data class Split(val x: Int, val y: Int) : Instruction
    data class Jump(val target: Int) : Instruction
    data class Save(val slot: Int) : Instruction
    data class Assert(val kind: String) : Instruction
    data class Backref(val group: Int) : Instruction
    data class Look(val kind: String, val target: Int) : Instruction
    data object Match : Instruction
}
sealed interface Node {
    data class Literal(val code: Int) : Node
    data object Any : Node
    data class Class(val set: Set<Int>, val negated: Boolean) : Node
    data class Assert(val kind: String) : Node
    data class Backref(val group: Int) : Node
    data class Named(val name: String) : Node
    data class Group(val group: Int, val content: Node) : Node
    data class Look(val positive: Boolean, val content: Node) : Node
    data class Concat(val nodes: List<Node>) : Node
    data class Alternate(val nodes: List<Node>) : Node
    data class Repeat(val content: Node, val minimum: Int, val maximum: Int?, val kind: String) : Node
}
class PatternError(val reason: String, val column: Int) : Exception(reason)
data class RegexPattern(val name: String, val flagsText: String, val flags: Flags, val text: String, val groups: Int, val names: Map<String, Int>, val root: Node?, val code: List<Instruction>, val error: PatternError?, val pike: Boolean)
fun oneOf(text: String, c: Int?): Boolean = c != null && c.toChar() in text
class PatternParser(val text: String) {
    val bytes = text.map {
        it.code
    };
    var index = 0;
    var groups = 0;
    val names = mutableMapOf<String, Int>();
    val references = mutableListOf<Triple<Int, Int?, String>>()
    val peek: Int? get() = bytes.getOrNull(index)
    fun error(message: String, at: Int): PatternError = PatternError(message, at + 1)
    fun alternation(): Node {
        val nodes = mutableListOf(concatenation());
        while (peek == 124) {
            index++;
            nodes.add(concatenation())
        };
        return if (nodes.size == 1) nodes[0] else Node.Alternate(nodes)
    }
    fun concatenation(): Node {
        val nodes = mutableListOf<Node>();
        while (peek != null && !oneOf("|)", peek)) nodes.add(quantified());
        return if (nodes.size == 1) nodes[0] else Node.Concat(nodes)
    }
    fun quantified(): Node {
        if (oneOf("*+?{", peek)) throw error("nothing to repeat", index)
        val node = element();
        if (!oneOf("*+?{", peek)) return node
        if (node is Node.Assert || node is Node.Look) throw error("nothing to repeat", index)
        val minimum: Int;
        val maximum: Int?
        if (peek == 123) {
            val bounds = braces();
            minimum = bounds.first;
            maximum = bounds.second
        } else {
            val c = bytes[index++];
            minimum = if (c == 43) 1 else 0;
            maximum = if (c == 63) 1 else null
        }
        val kind = if (peek == 63) {
            index++;
            "lazy"
        } else if (peek == 43) {
            index++;
            "possessive"
        } else "greedy"
        if (oneOf("*+?{", peek)) throw error("nested quantifier", index)
        return Node.Repeat(node, minimum, maximum, kind)
    }
    fun digits(): Int? {
        val start = index;
        while (peek?.let {
            Charset.digit(it)
        } == true) index++;
        return if (start == index) null else text.substring(start, index).toInt()
    }
    fun braces(): Pair<Int, Int?> {
        val start = index++;
        val minimum = digits() ?: throw error("invalid quantifier", start)
        val maximum = if (peek == 125) minimum else if (peek == 44) {
            index++;
            if (peek == 125) null else digits() ?: throw error("invalid quantifier", start)
        } else throw error("invalid quantifier", start)
        if (peek != 125) throw error("invalid quantifier", start);
        index++
        if (minimum > 100 || maximum != null && maximum > 100) throw error("quantifier too large", start)
        if (maximum != null && minimum > maximum) throw error("quantifier range out of order", start)
        return Pair(minimum, maximum)
    }
    fun name(): String {
        val start = index
        if (peek?.let {
            Charset.letter(it) || it == 95
        } == true) {
            index++;
            while (peek?.let {
                Charset.word(it)
            } == true) index++
        }
        if (index == start || peek != 62) throw error("invalid group name", index)
        val name = text.substring(start, index);
        index++;
        return name
    }
    fun group(): Node {
        val start = index++;
        var mode = "capture";
        var named: String? = null
        if (peek == 63) {
            index++;
            mode = when (peek) {
                58 -> "plain";
                61 -> "ahead";
                33 -> "negative";
                60 -> "capture";
                else -> throw error("invalid group", start)
            };
            val namedGroup = peek == 60;
            index++
            if (namedGroup) {
                val nameStart = index;
                val name = this.name();
                if (name in names) throw error("duplicate group name", nameStart);
                named = name
            }
        }
        var number: Int? = null
        if (mode == "capture") {
            groups++;
            number = groups;
            if (named != null) names[named] = groups
        }
        val content = alternation();
        if (peek != 41) throw error("missing )", start);
        index++
        return if (number != null) Node.Group(number, content) else if (mode == "plain") content else Node.Look(mode == "ahead", content)
    }
    fun classItem(): Pair<Set<Int>, Boolean> {
        val start = index;
        val c = peek ?: throw error("missing ]", start);
        index++;
        if (c != 92) return Pair(setOf(c), false)
        val escaped = peek ?: throw error("trailing backslash", start);
        index++
        if (oneOf("dDwWsS", escaped)) return Pair(Charset.base(escaped), true)
        if (escaped == 110) return Pair(setOf(10), false)
        if (escaped == 116) return Pair(setOf(9), false)
        if (Charset.letter(escaped) || Charset.digit(escaped)) throw error("invalid escape", start)
        return Pair(setOf(escaped), false)
    }
    fun characterClass(): Node {
        val start = index++;
        val negated = peek == 94;
        if (negated) index++
        if (peek == 93) throw error("empty class", index)
        val set = mutableSetOf<Int>()
        while (true) {
            if (peek == null) throw error("missing ]", start)
            if (peek == 93) {
                index++;
                break
            }
            val (left, leftSet) = classItem()
            if (peek == 45 && index + 1 < bytes.size && bytes[index + 1] != 93) {
                val hyphen = index++;
                if (leftSet) throw error("invalid range", hyphen);
                val (right, rightSet) = classItem();
                val a = left.first();
                val b = right.first();
                if (rightSet || a > b) throw error("invalid range", hyphen);
                set.addAll(a..b)
            } else set.addAll(left)
        }
        return Node.Class(set.toSet(), negated)
    }
    fun escape(): Node {
        val start = index++;
        val c = peek ?: throw error("trailing backslash", start);
        index++
        if (oneOf("dDwWsS", c)) return Node.Class(Charset.base(if (c in 65..90) c + 32 else c), c in 65..90)
        return when (c) {
            98 -> Node.Assert("WORD")
            66 -> Node.Assert("NOTWORD")
            110 -> Node.Literal(10)
            116 -> Node.Literal(9)
            in 49..57 -> {
                index--;
                val number = digits()!!;
                references.add(Triple(start, number, ""));
                Node.Backref(number)
            }
            107 -> {
                if (peek != 60) throw error("invalid escape", start);
                index++;
                val name = this.name();
                references.add(Triple(start, null, name));
                Node.Named(name)
            }
            else -> {
                if (Charset.letter(c) || Charset.digit(c)) throw error("invalid escape", start);
                Node.Literal(c)
            }
        }
    }
    fun element(): Node = when (val c = peek!!) {
        40 -> group();
        91 -> characterClass();
        92 -> escape();
        46 -> {
            index++;
            Node.Any
        };
        94 -> {
            index++;
            Node.Assert("BOL")
        };
        36 -> {
            index++;
            Node.Assert("EOL")
        };
        else -> {
            index++;
            Node.Literal(c)
        }
    }
    fun parse(): Node {
        val root = alternation();
        if (index < bytes.size) throw error("unmatched )", index)
        for ((column, number, name) in references) {
            if (number != null) {
                if (number > groups) throw error("invalid group reference", column)
            } else if (name !in names) throw error("unknown group name", column)
        };
        return root
    }
}
fun compile(node: Node, code: MutableList<Instruction>, names: Map<String, Int>) {
    when (node) {
        is Node.Literal -> code.add(Instruction.Char(node.code))
        Node.Any -> code.add(Instruction.Any)
        is Node.Class -> code.add(Instruction.Class(node.set, node.negated))
        is Node.Assert -> code.add(Instruction.Assert(node.kind))
        is Node.Backref -> code.add(Instruction.Backref(node.group))
        is Node.Named -> code.add(Instruction.Backref(names.getValue(node.name)))
        is Node.Group -> {
            code.add(Instruction.Save(2 * node.group));
            compile(node.content, code, names);
            code.add(Instruction.Save(2 * node.group + 1))
        }
        is Node.Look -> {
            val start = code.size;
            val kind = if (node.positive) "AHEAD" else "NOT";
            code.add(Instruction.Look(kind, 0));
            compile(node.content, code, names);
            code.add(Instruction.Match);
            code[start] = Instruction.Look(kind, code.size)
        }
        is Node.Concat -> for (child in node.nodes) compile(child, code, names)
        is Node.Alternate -> {
            val jumps = mutableListOf<Int>();
            for (child in node.nodes.dropLast(1)) {
                val split = code.size;
                code.add(Instruction.Split(split + 1, 0));
                compile(child, code, names);
                jumps.add(code.size);
                code.add(Instruction.Jump(0));
                code[split] = Instruction.Split(split + 1, code.size)
            };
            compile(node.nodes.last(), code, names);
            val end = code.size;
            for (jump in jumps) code[jump] = Instruction.Jump(end)
        }
        is Node.Repeat -> {
            if (node.kind == "possessive") {
                val start = code.size;
                code.add(Instruction.Look("ATOMIC", 0));
                compile(node.copy(kind = "greedy"), code, names);
                code.add(Instruction.Match);
                code[start] = Instruction.Look("ATOMIC", code.size);
                return
            }
            val greedy = node.kind == "greedy";
            val maximum = node.maximum
            if (maximum != null) {
                repeat(node.minimum) {
                    compile(node.content, code, names)
                };
                val splits = mutableListOf<Int>();
                repeat(maximum - node.minimum) {
                    splits.add(code.size);
                    code.add(Instruction.Split(0, 0));
                    compile(node.content, code, names)
                };
                val end = code.size;
                for (split in splits) code[split] = if (greedy) Instruction.Split(split + 1, end) else Instruction.Split(end, split + 1)
            }
            else if (node.minimum == 0) {
                val split = code.size;
                code.add(Instruction.Split(0, 0));
                compile(node.content, code, names);
                code.add(Instruction.Jump(split));
                code[split] = if (greedy) Instruction.Split(split + 1, code.size) else Instruction.Split(code.size, split + 1)
            }
            else {
                repeat(node.minimum - 1) {
                    compile(node.content, code, names)
                };
                val start = code.size;
                compile(node.content, code, names);
                val end = code.size + 1;
                code.add(if (greedy) Instruction.Split(start, end) else Instruction.Split(end, start))
            }
        }
    }
}
fun length(node: Node): Pair<Int, Int?> = when (node) {
    is Node.Literal -> Pair(1, 1)
    Node.Any -> Pair(1, 1)
    is Node.Class -> Pair(1, 1)
    is Node.Assert, is Node.Look -> Pair(0, 0)
    is Node.Backref, is Node.Named -> Pair(0, null)
    is Node.Group -> length(node.content)
    is Node.Concat -> {
        val ranges = node.nodes.map {
            length(it)
        };
        Pair(ranges.sumOf {
            it.first
        }, if (ranges.any {
            it.second == null
        }) null else ranges.sumOf {
            it.second!!
        })
    }
    is Node.Alternate -> {
        val ranges = node.nodes.map {
            length(it)
        };
        Pair(ranges.minOf {
            it.first
        }, if (ranges.any {
            it.second == null
        }) null else ranges.maxOf {
            it.second!!
        })
    }
    is Node.Repeat -> {
        val (a, b) = length(node.content);
        Pair(a * node.minimum, if (b == 0) 0 else if (b == null || node.maximum == null) null else node.maximum * b)
    }
}
fun first(node: Node, flags: Flags): Pair<Set<Int>, Boolean> = when (node) {
    is Node.Literal -> Pair(if (flags.i && Charset.letter(node.code)) setOf(node.code, Charset.swap(node.code)) else setOf(node.code), false)
    Node.Any -> Pair((0..127).filter {
        flags.s || it != 10
    }.toSet(), false)
    is Node.Class -> Pair((0..127).filter {
        Charset.classMatches(it, node.set, node.negated, flags)
    }.toSet(), false)
    is Node.Assert, is Node.Look -> Pair(emptySet(), true)
    is Node.Backref, is Node.Named -> Pair((0..127).toSet(), true)
    is Node.Group -> first(node.content, flags)
    is Node.Concat -> {
        val set = mutableSetOf<Int>();
        var nullable = true;
        for (child in node.nodes) {
            val part = first(child, flags);
            set.addAll(part.first);
            if (!part.second) {
                nullable = false;
                break
            }
        };
        Pair(set, nullable)
    }
    is Node.Alternate -> {
        val parts = node.nodes.map {
            first(it, flags)
        };
        Pair(parts.flatMap {
            it.first
        }.toSet(), parts.any {
            it.second
        })
    }
    is Node.Repeat -> if (node.maximum == 0) Pair(emptySet(), true) else {
        val (set, nullable) = first(node.content, flags);
        Pair(set, nullable || node.minimum == 0)
    }
}
fun consumes(instruction: Instruction, subject: List<Int>, q: Int, flags: Flags): Boolean {
    if (q == subject.size) return false
    return when (instruction) {
        is Instruction.Char -> Charset.equal(instruction.code, subject[q], flags);
        Instruction.Any -> flags.s || subject[q] != 10;
        is Instruction.Class -> Charset.classMatches(subject[q], instruction.set, instruction.negated, flags);
        else -> false
    }
}
fun readPattern(line: String): RegexPattern {
    val f = line.split(' ', limit = 3);
    val parser = PatternParser(f[2]);
    val flags = Flags('i' in f[1], 'm' in f[1], 's' in f[1]);
    var root: Node? = null;
    var error: PatternError? = null;
    val code = mutableListOf<Instruction>()
    try {
        val parsed = parser.parse();
        root = parsed;
        code.add(Instruction.Save(0));
        compile(parsed, code, parser.names);
        code.add(Instruction.Save(1));
        code.add(Instruction.Match)
    } catch (failure: PatternError) {
        error = failure
    }
    val pike = code.none {
        it is Instruction.Backref || it is Instruction.Look
    }
    return RegexPattern(f[0], f[1], flags, f[2], parser.groups, parser.names.toMap(), root, code, error, pike)
}
fun decode(quoted: String): List<Int> {
    val result = mutableListOf<Int>()
    var i = 1
    while (i + 1 < quoted.length) {
        if (quoted[i].code == 92) {
            i++
            result.add(when (quoted[i]) {
                'n' -> 10;
                't' -> 9;
                else -> quoted[i].code
            })
        } else result.add(quoted[i].code)
        i++
    }
    return result
}
sealed interface TemplatePart {
    data class Character(val code: Int) : TemplatePart
    data class Group(val group: Int) : TemplatePart
}
fun template(bytes: List<Int>, pattern: RegexPattern): List<TemplatePart>? {
    val parts = mutableListOf<TemplatePart>()
    var i = 0
    while (i < bytes.size) {
        if (bytes[i] != 36) {
            parts.add(TemplatePart.Character(bytes[i++]))
            continue
        }
        i++
        if (bytes.getOrNull(i) == 36) {
            parts.add(TemplatePart.Character(36))
            i++
            continue
        }
        val number: Int
        if (bytes.getOrNull(i)?.let {
            Charset.digit(it)
        } == true) {
            number = bytes[i++] - 48
        } else if (bytes.getOrNull(i) == 123) {
            i++
            val end = (i until bytes.size).firstOrNull {
                bytes[it] == 125
            } ?: return null
            val name = bytes.subList(i, end).map {
                it.toChar()
            }.joinToString("")
            i = end + 1
            number = if (name.isNotEmpty() && name.all {
                Charset.digit(it.code)
            }) name.toInt() else pattern.names[name] ?: return null
        } else return null
        if (number > pattern.groups) return null
        parts.add(TemplatePart.Group(number))
    }
    return parts
}
fun group(capture: Capture, k: Int, subject: List<Int>): List<Int>? {
    val a = capture[2 * k] ?: return null
    val b = capture[2 * k + 1] ?: return null
    return subject.subList(a, b).toList()
}
fun matchLines(capture: Capture, pattern: RegexPattern, subject: List<Int>): List<String> = (0..pattern.groups).map {
    k ->
    val heading = if (k == 0) "match" else "group $k"
    val value = group(capture, k, subject)
    if (value == null) "$heading -" else "$heading ${capture[2 * k]}-${capture[2 * k + 1]} ${Formatter.quote(value)}"
}
fun scanBacktrack(vm: Backtrack, length: Int, scan: Boolean): List<Capture> {
    val matches = mutableListOf<Capture>()
    var start = 0
    while (start <= length) {
        val capture = vm.search(start) ?: break
        matches.add(capture)
        start = capture[1]!! + if (capture[0] == capture[1]) 1 else 0
        if (!scan) break
    }
    return matches
}
fun scanPike(vm: Pike, length: Int, scan: Boolean): List<Capture> {
    val matches = mutableListOf<Capture>()
    var start = 0
    while (start <= length) {
        val capture = vm.search(start) ?: break
        matches.add(capture)
        start = capture[1]!! + if (capture[0] == capture[1]) 1 else 0
        if (!scan) break
    }
    return matches
}
fun listPattern(pattern: RegexPattern): List<String> {
    val names = pattern.names.entries.sortedBy {
        it.value
    }.map {
        "${it.key}:${it.value}"
    }
    val root = pattern.root!!
    val (minimum, maximum) = length(root)
    val (set, _) = first(root, pattern.flags)
    val lines = mutableListOf("=== " + pattern.name, "flags=${pattern.flagsText} groups=${pattern.groups} names=${if (names.isEmpty()) "-" else names.joinToString(",")} length=$minimum..${maximum ?: "inf"} first=${if (set.isEmpty()) "-" else Formatter.set(set)} pike=${if (pattern.pike) "yes" else "no"} size=${pattern.code.size}")
    lines.addAll(pattern.code.mapIndexed {
        i, instruction -> "$i ${Formatter.instruction(instruction)}"
    })
    return lines
}
fun readLines(name: String): List<String> = File("input/$name").readLines()
fun write(name: String, lines: List<String>) {
    File("output").mkdirs()
    File("output/$name").writeText(if (lines.isEmpty()) "" else lines.joinToString("\n") + "\n")
}
fun main() {
    val patterns = readLines("patterns.txt").map(::readPattern)
    val byName = patterns.associateBy {
        it.name
    }
    val subjects = readLines("subjects.txt").associate {
        line -> val f = line.split(' ', limit = 2);
        f[0] to decode(f[1])
    }
    val errors = mutableListOf<String>()
    val results = mutableListOf<String>()
    val programs = mutableListOf<String>()
    val steps = mutableListOf("command,engine,steps")
    for (pattern in patterns) {
        val error = pattern.error ?: continue
        errors.addAll(listOf("${pattern.name}: ${error.reason} at column ${error.column}", "  " + pattern.text, " ".repeat(error.column + 1) + "^"))
    }
    if (errors.isEmpty()) errors.add("no errors")
    for ((index, line) in readLines("commands.txt").withIndex()) {
        results.add("#${index + 1} $line")
        val f = line.split(' ', limit = 5)
        val command = f[0]
        val replacing = command == "REPLACE"
        val pattern = byName[f[if (replacing) 2 else 1]]!!
        if (pattern.error != null) {
            results.add("invalid pattern");
            continue
        }
        if (command == "LIST") {
            results.add("instructions ${pattern.code.size}");
            programs.addAll(listPattern(pattern));
            continue
        }
        val subject = subjects[f[if (replacing) 3 else 2]]!!
        val parts: List<TemplatePart>
        if (replacing) {
            val parsed = template(decode(f[4]), pattern)
            if (parsed == null) {
                results.add("invalid template");
                continue
            }
            parts = parsed
        } else parts = emptyList()
        val scan = command in listOf("FINDALL", "SPLIT") || replacing && f[1] == "ALL"
        val full = command == "MATCH"
        val backtrack = Backtrack(pattern.code, subject, pattern.flags, pattern.groups, full)
        val backtrackMatches = try {
            scanBacktrack(backtrack, subject.size, scan)
        } catch (_: StepLimit) {
            null
        }
        steps.add("${index + 1},backtrack,${backtrack.steps}")
        val matches: List<Capture>
        val label: String
        if (pattern.pike) {
            val pike = Pike(pattern.code, subject, pattern.flags, pattern.groups, full)
            val found = scanPike(pike, subject.size, scan)
            steps.add("${index + 1},pike,${pike.steps}")
            if (backtrackMatches != null && backtrackMatches != found) {
                results.add("MISMATCH");
                continue
            }
            matches = found
            label = if (backtrackMatches == null) "pike (backtrack: TOO_MANY_STEPS)" else "both"
        } else {
            if (backtrackMatches == null) {
                results.add("TOO_MANY_STEPS");
                continue
            }
            matches = backtrackMatches
            label = "backtrack"
        }
        results.add("engine $label")
        if (command == "MATCH" || command == "SEARCH") {
            if (matches.isEmpty()) results.add("no match") else results.addAll(matchLines(matches[0], pattern, subject))
        } else if (command == "FINDALL") {
            results.add("matches ${matches.size}")
            for (capture in matches) results.addAll(matchLines(capture, pattern, subject))
        } else if (replacing) {
            val result = mutableListOf<Int>()
            var last = 0
            for (capture in matches) {
                result.addAll(subject.subList(last, capture[0]!!))
                for (part in parts) {
                    when (part) {
                        is TemplatePart.Character -> result.add(part.code);
                        is TemplatePart.Group -> result.addAll(group(capture, part.group, subject) ?: emptyList())
                    }
                }
                last = capture[1]!!
            }
            result.addAll(subject.subList(last, subject.size))
            results.addAll(listOf("replacements ${matches.size}", "result " + Formatter.quote(result)))
        } else {
            results.addAll(listOf("pieces ${matches.size + 1}", "piece " + Formatter.quote(subject.subList(0, matches.firstOrNull()?.get(0) ?: subject.size))))
            for ((i, capture) in matches.withIndex()) {
                for (k in 1..pattern.groups) results.add("group $k " + (group(capture, k, subject)?.let(Formatter::quote) ?: "-"))
                val end = if (i + 1 < matches.size) matches[i + 1][0]!! else subject.size
                results.add("piece " + Formatter.quote(subject.subList(capture[1]!!, end)))
            }
        }
    }
    if (programs.isEmpty()) programs.add("no programs")
    write("results.txt", results)
    write("programs.txt", programs)
    write("steps.csv", steps)
    write("errors.txt", errors)
}
