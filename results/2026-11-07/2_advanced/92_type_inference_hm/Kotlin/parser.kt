sealed class Expr(open val position: Position)
data class IntExpr(override val position: Position, val value: Long) : Expr(position)
data class BoolExpr(override val position: Position, val value: Boolean) : Expr(position)
data class StringExpr(override val position: Position, val value: String) : Expr(position)
data class NameExpr(override val position: Position, val name: String) : Expr(position)
data class Lambda(override val position: Position, val parameter: Parameter, val body: Expr) : Expr(position)
data class Apply(override val position: Position, val function: Expr, val argument: Expr) : Expr(position)
data class Binary(override val position: Position, val op: String, val operatorPosition: Position, val left: Expr, val right: Expr) : Expr(position)
data class Negate(override val position: Position, val operand: Expr) : Expr(position)
data class Conditional(override val position: Position, val condition: Expr, val yes: Expr, val no: Expr) : Expr(position)
data class PairExpr(override val position: Position, val first: Expr, val second: Expr) : Expr(position)
data class ListExpr(override val position: Position, val elements: List<Expr>) : Expr(position)
data class Match(override val position: Position, val value: Expr, val arms: List<Pair<Pattern, Expr>>) : Expr(position)
data class LetIn(override val position: Position, val group: Group, val body: Expr) : Expr(position)
data class Parameter(val name: String?, val position: Position)
data class Binding(val name: String, val position: Position, val expression: Expr)
data class Group(val recursive: Position?, val bindings: List<Binding>)
sealed class Pattern(open val position: Position)
data class WildPattern(override val position: Position) : Pattern(position)
data class NamePattern(override val position: Position, val name: String) : Pattern(position)
data class IntPattern(override val position: Position, val value: Long) : Pattern(position)
data class BoolPattern(override val position: Position, val value: Boolean) : Pattern(position)
data class StringPattern(override val position: Position, val value: String) : Pattern(position)
data class ConsPattern(override val position: Position, val head: Pattern, val tail: Pattern) : Pattern(position)
data class ListPattern(override val position: Position, val elements: List<Pattern>) : Pattern(position)
data class PairPattern(override val position: Position, val first: Pattern, val second: Pattern) : Pattern(position)
sealed interface TypeExpression {
    data class Primitive(val name: String) : TypeExpression
    data class Variable(val name: String) : TypeExpression
    data class ListType(val element: TypeExpression) : TypeExpression
    data class PairType(val first: TypeExpression, val second: TypeExpression) : TypeExpression
    data class Function(val argument: TypeExpression, val result: TypeExpression) : TypeExpression
}
sealed interface Item {
    data class Signature(val name: String, val position: Position, val type: TypeExpression) : Item
    data class Declaration(val group: Group) : Item
    data class Expression(val expression: Expr) : Item
}
class SyntaxError(val token: Token) : Exception()
fun precedence(op: String): Int = when (op) {
    "||" -> 1; "&&" -> 2; "=", "<>", "<", ">", "<=", ">=" -> 3; "::", "^" -> 4; "+", "-" -> 5; "*", "/", "mod" -> 6; else -> 0
}
fun rightAssociative(op: String): Boolean = op in listOf("||", "&&", "::", "^")
class Parser(val tokens: List<Token>) {
    var index = 0
    val peek: Token get() = tokens[index]
    val word: String get() = peek.value
    fun failure(): Nothing = throw SyntaxError(peek)
    fun take(): Token {
        val token = peek; if (token.kind != "eof") index++; return token
    }
    fun expect(word: String): Token {
        if (this.word != word || peek.kind == "invalid") failure(); return take()
    }
    fun name(): Token {
        if (peek.kind != "identifier" || word == "_") failure(); return take()
    }
    fun parameter(): Parameter {
        if (peek.kind != "identifier") failure(); val token = take(); return Parameter(token.value.takeUnless {
            it == "_"
        }, token.position)
    }
    val atomicStart: Boolean get() = peek.kind in listOf("integer", "string") || peek.kind == "identifier" && word != "_" || peek.kind != "invalid" && word in listOf("true", "false", "(", "[")
    fun group(): Group {
        expect("let"); val recursive = if (word == "rec") take().position else null; val bindings = mutableListOf<Binding>()
        while (true) {
            val token = name(); val parameters = mutableListOf<Parameter>()
            while (peek.kind == "identifier") parameters.add(parameter())
            expect("="); var body = expr()
            for (parameter in parameters.asReversed()) body = Lambda(parameter.position, parameter, body)
            bindings.add(Binding(token.value, token.position, body)); if (word != "and") break; take()
        }
        return Group(recursive, bindings)
    }
    fun item(): Item {
        val result: Item
        if (word == "val") {
            take(); val token = name(); expect(":"); result = Item.Signature(token.value, token.position, typeExpression())
        }
        else if (word == "let") {
            val position = peek.position; val group = group(); result = if (word == "in") {
                take(); Item.Expression(LetIn(position, group, expr()))
            } else Item.Declaration(group)
        }
        else result = Item.Expression(expr())
        expect(";;"); return result
    }
    fun expr(): Expr {
        val position = peek.position
        return when (word) {
            "let" -> {
                val group = group(); expect("in"); LetIn(position, group, expr())
            }
            "fun" -> {
                take(); val parameters = mutableListOf(parameter()); while (peek.kind == "identifier") parameters.add(parameter()); expect("->"); var body = expr(); for (i in parameters.indices.reversed()) body = Lambda(if (i == 0) position else parameters[i].position, parameters[i], body); body
            }
            "if" -> {
                take(); val condition = expr(); expect("then"); val yes = expr(); expect("else"); val no = expr(); Conditional(position, condition, yes, no)
            }
            "match" -> {
                take(); val value = expr(); expect("with"); if (word == "|") take(); val arms = mutableListOf<Pair<Pattern, Expr>>(); while (true) {
                    val pattern = pattern(); expect("->"); arms.add(Pair(pattern, expr())); if (word != "|") break; take()
                }; Match(position, value, arms)
            }
            else -> binary(1)
        }
    }
    fun binary(minimum: Int): Expr {
        var left = unary()
        while (true) {
            val p = precedence(word); if (p == 0 || p < minimum) break; val op = take(); val right = binary(if (rightAssociative(op.value)) p else p + 1); left = Binary(left.position, op.value, op.position, left, right)
        }
        return left
    }
    fun unary(): Expr {
        if (word == "-") {
            val token = take(); return Negate(token.position, unary())
        }
        var function = atomic(); while (atomicStart) {
            val argument = atomic(); function = Apply(function.position, function, argument)
        }; return function
    }
    fun atomic(): Expr {
        val token = peek; val position = token.position
        when (token.kind) {
            "integer" -> {
                take(); return IntExpr(position, token.value.toLong())
            }; "string" -> {
                take(); return StringExpr(position, token.value)
            }; "identifier" -> if (word != "_") {
                take(); return NameExpr(position, token.value)
            }
        }
        if (token.kind == "invalid") failure()
        return when (word) {
            "true", "false" -> {
                take(); BoolExpr(position, token.value == "true")
            }
            "(" -> {
                take(); val first = expr(); if (word == ",") {
                    take(); val second = expr(); expect(")"); PairExpr(position, first, second)
                } else {
                    expect(")"); first
                }
            }
            "[" -> {
                take(); val elements = mutableListOf<Expr>(); if (word != "]") {
                    elements.add(expr()); while (word == ";") {
                        take(); elements.add(expr())
                    }
                }; expect("]"); ListExpr(position, elements)
            }
            else -> failure()
        }
    }
    fun pattern(): Pattern {
        val head = atomicPattern(); return if (word == "::") {
            take(); ConsPattern(head.position, head, pattern())
        } else head
    }
    fun atomicPattern(): Pattern {
        val token = peek; val position = token.position
        when (token.kind) {
            "integer" -> {
                take(); return IntPattern(position, token.value.toLong())
            }; "string" -> {
                take(); return StringPattern(position, token.value)
            }; "identifier" -> {
                take(); return if (token.value == "_") WildPattern(position) else NamePattern(position, token.value)
            }
        }
        if (token.kind == "invalid") failure()
        return when (word) {
            "true", "false" -> {
                take(); BoolPattern(position, token.value == "true")
            }
            "-" -> {
                take(); if (peek.kind != "integer") failure(); IntPattern(position, -take().value.toLong())
            }
            "(" -> {
                take(); val first = pattern(); if (word == ",") {
                    take(); val second = pattern(); expect(")"); PairPattern(position, first, second)
                } else {
                    expect(")"); first
                }
            }
            "[" -> {
                take(); val elements = mutableListOf<Pattern>(); if (word != "]") {
                    elements.add(pattern()); while (word == ";") {
                        take(); elements.add(pattern())
                    }
                }; expect("]"); ListPattern(position, elements)
            }
            else -> failure()
        }
    }
    fun typeExpression(): TypeExpression {
        val first = productType(); return if (word == "->") {
            take(); TypeExpression.Function(first, typeExpression())
        } else first
    }
    fun productType(): TypeExpression {
        val first = listType(); return if (word == "*") {
            take(); TypeExpression.PairType(first, listType())
        } else first
    }
    fun listType(): TypeExpression {
        var type = typeAtom(); while (peek.kind == "identifier" && word == "list") {
            take(); type = TypeExpression.ListType(type)
        }; return type
    }
    fun typeAtom(): TypeExpression {
        if (peek.kind == "type_variable") return TypeExpression.Variable(take().value)
        if (peek.kind == "identifier" && word in listOf("int", "bool", "string")) return TypeExpression.Primitive(take().value)
        if (peek.kind == "symbol" && word == "(") {
            take(); val type = typeExpression(); expect(")"); return type
        }; failure()
    }
    fun recover() {
        while (peek.kind != "eof" && word != ";;") take(); if (word == ";;") take()
    }
}
