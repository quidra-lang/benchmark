import java.io.File
sealed interface Expr {
    data class Word(val text: String) : Expr
    data class Group(val values: List<Expr>) : Expr
    val word: String get() = (this as Word).text
    val list: List<Expr> get() = (this as Group).values
}
data class Atom(val predicate: String, val terms: List<String>) {
    constructor(expr: Expr) : this(expr.list[0].word, expr.list.drop(1).map {
        it.word
    })
    val text: String get() = (listOf(predicate) + terms).joinToString(" ", "(", ")")
    fun replace(values: Map<String, String>): Atom = Atom(predicate, terms.map {
        values.getValue(it)
    })
}
data class Literal(val atom: Atom, val negative: Boolean = false) {
    val text: String get() = if (negative) "(not ${atom.text})" else atom.text
    fun replace(values: Map<String, String>): Literal = Literal(atom.replace(values), negative)
}
data class Typed(val name: String, val type: String)
data class Schema(val name: String, var parameters: List<Typed> = emptyList(), var pre: List<Literal> = emptyList(),
val effects: MutableList<Literal> = mutableListOf(), var cost: Int = 1)
data class Predicate(val name: String, val types: List<String>)
class Domain(val name: String) {
    val typeOrder = mutableListOf("object")
    val parents = mutableMapOf<String, String>()
    val predicates = mutableListOf<Predicate>()
    var actions = mutableListOf<Schema>()
    val diagnostics = mutableListOf<String>()
}
class Problem(val name: String) {
    var objects: List<Typed> = emptyList()
    var initial: List<Atom> = emptyList()
    var goals: List<Atom> = emptyList()
    val diagnostics = mutableListOf<String>()
}
object PDDLParser {
    fun expressions(path: String): List<Expr> {
        val tokens = mutableListOf<String>()
        for (line in File(path).readLines()) {
            val word = StringBuilder()
            fun flush() {
                if (word.isNotEmpty()) {
                    tokens.add(word.toString()); word.clear()
                }
            }
            for (c in line.takeWhile {
                it != ';'
            }) {
                if (c in "() ") {
                    flush(); if (c != ' ') tokens.add(c.toString())
                } else word.append(c)
            }
            flush()
        }
        var i = 0
        fun read(): Expr {
            val token = tokens[i++]
            if (token != "(") return Expr.Word(token)
            val children = mutableListOf<Expr>()
            while (tokens[i] != ")") children.add(read())
            i++
            return Expr.Group(children)
        }
        val result = mutableListOf<Expr>()
        while (i < tokens.size) result.add(read())
        return result
    }
    fun typed(words: List<Expr>): List<Typed> {
        val result = mutableListOf<Typed>()
        val pending = mutableListOf<String>()
        var i = 0
        while (i < words.size) {
            if (words[i].word == "-") {
                i++
                result.addAll(pending.map {
                    Typed(it, words[i].word)
                })
                pending.clear()
            } else pending.add(words[i].word)
            i++
        }
        return result + pending.map {
            Typed(it, "object")
        }
    }
    fun conjunction(expr: Expr): List<Expr> = if (expr.list[0].word == "and") expr.list.drop(1) else listOf(expr)
    fun literal(expr: Expr): Literal = if (expr.list[0].word == "not") Literal(Atom(expr.list[1]), true) else Literal(Atom(expr))
    fun domain(): Domain {
        val a = expressions("input/domain.txt")[0].list
        val domain = Domain(a[1].list[1].word)
        for (expr in a.drop(2)) {
            val s = expr.list
            when (s[0].word) {
                ":types" -> {
                    for (word in s.drop(1)) if (word.word != "-" && word.word !in domain.typeOrder) {
                        domain.typeOrder.add(word.word)
                        if (word.word != "object") domain.parents[word.word] = "object"
                    }
                    for ((name, type) in typed(s.drop(1))) domain.parents[name] = type
                }
                ":predicates" -> for (value in s.drop(1)) domain.predicates.add(Predicate(value.list[0].word, typed(value.list.drop(1)).map {
                    it.type
                }))
                ":action" -> {
                    val action = Schema(s[1].word)
                    var i = 2
                    while (i < s.size) {
                        when (s[i].word) {
                            ":parameters" -> action.parameters = typed(s[i + 1].list)
                            ":precondition" -> action.pre = conjunction(s[i + 1]).map(::literal)
                            else -> for (effect in conjunction(s[i + 1])) {
                                if (effect.list[0].word == "increase") action.cost = effect.list[2].word.toInt()
                                else action.effects.add(literal(effect))
                            }
                        }
                        i += 2
                    }
                    domain.actions.add(action)
                }
            }
        }
        return domain
    }
    fun problems(): List<Problem> = expressions("input/problems.txt").map {
        expr ->
        val a = expr.list
        val problem = Problem(a[1].list[1].word)
        for (section in a.drop(2)) {
            val s = section.list
            when (s[0].word) {
                ":objects" -> problem.objects = typed(s.drop(1))
                ":init" -> problem.initial = s.drop(1).map(::Atom)
                ":goal" -> problem.goals = conjunction(s[1]).map(::Atom)
            }
        }
        problem
    }
}
