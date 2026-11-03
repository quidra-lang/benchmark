import java.io.File

data class Diagnostic(val line: Int, val code: String, val message: String)
data class Substitution(val source: String, val replacement: List<String>, val line: Int)
data class SynonymGroup(val name: String, val members: Set<String>, val line: Int)
data class Item(val kind: String, val text: String, val arguments: List<String>, val line: Int)
data class Rule(val kind: String, val pattern: List<String>, val line: Int, val items: MutableList<Int> = mutableListOf())
data class Keyword(val word: String, val rank: Int, val line: Int, val memories: MutableList<Int> = mutableListOf(), val decomps: MutableList<Int> = mutableListOf())

val textDirectives = setOf("INITIAL", "FINAL", "DEFAULT", "QUESTION", "REPEAT")
val globalDirectives = textDirectives + setOf("QUIT", "STOP", "MEMSIZE", "PERSIST", "PRE", "POST", "SYNON")
val ruleDirectives = setOf("DECOMP", "MEMORY")
val itemDirectives = setOf("REASM", "GOTO", "NEWKEY", "RESTATE")

class Script(val lines: List<String>) {
    val texts = textDirectives.associateWith { mutableListOf<String>() }
    val quit = mutableSetOf<String>()
    val stop = mutableSetOf<String>()
    var capacity = 3
    val persist = mutableSetOf<String>()
    val pres = mutableListOf<Substitution>()
    val posts = mutableListOf<Substitution>()
    val pre = mutableMapOf<String, List<String>>()
    val post = mutableMapOf<String, List<String>>()
    val groups = mutableListOf<SynonymGroup>()
    val groupWords = mutableMapOf<String, Set<String>>()
    val keywords = mutableListOf<Keyword>()
    val keywordMap = mutableMapOf<String, Int>()
    val rules = mutableListOf<Rule>()
    val items = mutableListOf<Item>()
    val diagnostics = mutableListOf<Diagnostic>()
}

fun isWord(text: String) = text.isNotEmpty() && text.first() != '\'' && text.last() != '\'' && text.all { it in 'a'..'z' || it in '0'..'9' || it == '\'' }
fun isNumber(text: String) = text.length in 1..2 && text.all { it in '0'..'9' }
fun isReference(text: String) = text.length == 3 && text[0] == '(' && text[1] in '0'..'9' && text[2] == ')'
fun isElement(text: String) = text == "*" || text == "#" || if (text.startsWith("@")) isWord(text.drop(1)) else isWord(text)

fun wellFormed(name: String, args: List<String>): Boolean = when (name) {
    in textDirectives, "REASM" -> args.isNotEmpty()
    "QUIT", "STOP" -> args.isNotEmpty() && args.all(::isWord)
    "MEMSIZE" -> args.size == 1 && isNumber(args[0]) && args[0].toInt() in 1..20
    "PERSIST" -> args.size == 1 && args[0] in setOf("cycles", "memory")
    "PRE", "SYNON" -> args.size >= 2 && args.all(::isWord)
    "POST" -> args.size >= 2 && isWord(args[0])
    "KEY" -> args.size == 2 && isWord(args[0]) && isNumber(args[1])
    "DECOMP", "MEMORY" -> args.isNotEmpty() && args.all(::isElement)
    "GOTO" -> args.size == 1 && isWord(args[0])
    "NEWKEY" -> args.isEmpty()
    "RESTATE" -> args.size >= 2 && isWord(args[0]) && args.drop(1).all { isWord(it) || isReference(it) }
    else -> false
}

fun loadScript(path: String): Script {
    val script = Script(File(path).readLines())
    var keyword: Int? = null
    var rule: Int? = null
    var ignoring = false
    val definitions = mutableMapOf<String, Int>()
    for ((offset, line) in script.lines.withIndex()) {
        if (line.isEmpty() || line.startsWith("#")) continue
        val number = offset + 1
        val words = line.split(' ')
        val name = words[0]
        val args = words.drop(1)
        val text = line.substringAfter(' ', "")
        if (name in globalDirectives || name == "KEY") {
            keyword = null
            rule = null
            ignoring = false
        } else if (name in ruleDirectives || name in itemDirectives) {
            if (ignoring) continue
            if (name in ruleDirectives) rule = null
        }
        val identity = when (name) {
            "MEMSIZE" -> name
            "KEY", "SYNON", "PRE", "POST", "PERSIST" -> if (args.isEmpty()) null else "$name ${args[0]}"
            else -> null
        }
        val problem = when {
            name !in globalDirectives && name != "KEY" && name !in ruleDirectives && name !in itemDirectives -> "SYNTAX" to "unknown directive $name"
            !wellFormed(name, args) -> "SYNTAX" to "bad arguments for $name"
            name in ruleDirectives && keyword == null -> "ORPHAN" to "$name without KEY"
            name == "REASM" && rule == null -> "ORPHAN" to "REASM without DECOMP or MEMORY"
            name in setOf("GOTO", "NEWKEY", "RESTATE") && (rule == null || script.rules[rule].kind == "MEMORY") -> "ORPHAN" to "$name without DECOMP"
            identity != null && identity in definitions -> "DUPLICATE" to "$identity first defined at line ${definitions[identity]}"
            else -> null
        }
        if (problem != null) {
            script.diagnostics += Diagnostic(number, problem.first, problem.second)
            if (name == "KEY" && problem.first == "DUPLICATE") ignoring = true
            continue
        }
        if (identity != null) definitions[identity] = number
        when (name) {
            in textDirectives -> script.texts.getValue(name).add(text)
            "QUIT" -> script.quit.addAll(args)
            "STOP" -> script.stop.addAll(args)
            "MEMSIZE" -> script.capacity = args[0].toInt()
            "PERSIST" -> script.persist += args[0]
            "PRE", "POST" -> {
                val substitution = Substitution(args[0], args.drop(1), number)
                if (name == "PRE") { script.pres += substitution; script.pre[args[0]] = substitution.replacement }
                else { script.posts += substitution; script.post[args[0]] = substitution.replacement }
            }
            "SYNON" -> {
                script.groups += SynonymGroup(args[0], args.toSet(), number)
                script.groupWords[args[0]] = args.toSet()
            }
            "KEY" -> {
                keyword = script.keywords.size
                script.keywordMap[args[0]] = keyword!!
                script.keywords += Keyword(args[0], args[1].toInt(), number)
            }
            "DECOMP", "MEMORY" -> {
                rule = script.rules.size
                script.rules += Rule(name, args, number)
                if (name == "DECOMP") script.keywords[keyword!!].decomps += rule!!
                else script.keywords[keyword!!].memories += rule!!
            }
            else -> {
                script.rules[rule!!].items += script.items.size
                script.items += Item(name, text, args, number)
            }
        }
    }
    return script
}
