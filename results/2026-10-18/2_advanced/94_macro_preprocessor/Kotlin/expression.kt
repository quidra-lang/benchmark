sealed interface PPExpression {
    data class Value(val value: Long) : PPExpression
    data class Name(val name: String) : PPExpression
    data class Unary(val op: String, val operand: PPExpression) : PPExpression
    data class Binary(val op: String, val left: PPExpression, val right: PPExpression) : PPExpression
    data class Conditional(val condition: PPExpression, val yes: PPExpression, val no: PPExpression) : PPExpression
}
class ExpressionParser(val tokens: List<Token>) {
    var index = 0
    val text: String get() = tokens.getOrNull(index)?.text ?: ""
    fun priority(op: String): Int = when (op) {
        "||" -> 1; "&&" -> 2; "|" -> 3; "^" -> 4; "&" -> 5; "==", "!=" -> 6; "<", ">", "<=", ">=" -> 7; "<<", ">>" -> 8; "+", "-" -> 9; "*", "/", "%" -> 10; else -> 0
    }
    fun expression(): PPExpression {
        val left = binary(1); if (text != "?") return left; index++; val yes = expression(); if (text != ":") throw PPError("'?' without following ':'"); index++; return PPExpression.Conditional(left, yes, expression())
    }
    fun binary(minimum: Int): PPExpression {
        var left = unary(); while (priority(text) >= minimum) {
            val op = text; index++; left = PPExpression.Binary(op, left, binary(priority(op) + 1))
        }; return left
    }
    fun unary(): PPExpression {
        if (text in listOf("+", "-", "!", "~")) {
            val op = text; index++; return PPExpression.Unary(op, unary())
        }
        val token = tokens.getOrNull(index) ?: throw PPError("expected value at end of expression"); index++
        if (token.kind in listOf("number", "character")) return PPExpression.Value(constant(token))
        if (token.kind == "identifier") return PPExpression.Name(token.text)
        if (token.text == "(") {
            val value = expression(); if (text != ")") throw PPError("missing ')' in expression"); index++; return value
        }
        throw PPError("expected value before \"${token.text}\"")
    }
    companion object {
        fun constant(token: Token): Long {
            val original = token.text
            if (token.kind == "character") {
                val body = original.drop(1).dropLast(1); if (body.length == 1 && body[0].code !in listOf(39, 92)) return body[0].code.toLong(); if (body.length == 2 && body[0].code == 92) {
                    val value = mapOf('n' to 10L, 't' to 9L, 92.toChar() to 92L, 39.toChar() to 39L, '"' to 34L, '0' to 0L)[body[1]]; if (value != null) return value
                }; throw PPError("invalid character constant $original")
            }
            var body = original; for (suffix in listOf("ll", "LL", "l", "L")) if (body.length > suffix.length && body.endsWith(suffix)) {
                body = body.dropLast(suffix.length); break
            }
            val base: Int; val digits: String
            if (body.startsWith("0x") || body.startsWith("0X")) {
                base = 16; digits = body.drop(2)
            } else if (body.startsWith("0")) {
                base = 8; digits = body
            } else {
                base = 10; digits = body
            }
            val valid = digits.isNotEmpty() && digits.all {
                c -> when (base) {
                    16 -> c in '0'..'9' || c in 'a'..'f' || c in 'A'..'F'; 8 -> c in '0'..'7'; else -> c in '0'..'9'
                }
            }
            if (valid) digits.toLongOrNull(base)?.let {
                return it
            }
            throw PPError("invalid integer constant \"$original\"")
        }
        fun evaluate(expression: PPExpression, diagnostics: MutableList<Pair<String, String>>): Long = when (expression) {
            is PPExpression.Value -> expression.value
            is PPExpression.Name -> {
                diagnostics.add(Pair("warning", "identifier \"${expression.name}\" evaluates to 0")); 0
            }
            is PPExpression.Unary -> {
                val value = evaluate(expression.operand, diagnostics); when (expression.op) {
                    "+" -> value; "-" -> -value; "!" -> if (value == 0L) 1 else 0; else -> -value - 1
                }
            }
            is PPExpression.Conditional -> {
                val value = evaluate(expression.condition, diagnostics); evaluate(if (value != 0L) expression.yes else expression.no, diagnostics)
            }
            is PPExpression.Binary -> {
                val a = evaluate(expression.left, diagnostics)
                if (expression.op == "&&" && a == 0L) 0 else if (expression.op == "||" && a != 0L) 1 else {
                    val b = evaluate(expression.right, diagnostics); if (expression.op in listOf("/", "%") && b == 0L) throw PPError("division by zero in #if")
                    when (expression.op) {
                        "+" -> a + b; "-" -> a - b; "*" -> a * b; "/" -> a / b; "%" -> a % b; "<<" -> a shl b.toInt(); ">>" -> a shr b.toInt(); "&" -> a and b; "|" -> a or b; "^" -> a xor b; "&&", "||" -> if (b == 0L) 0 else 1; "<" -> if (a < b) 1 else 0; ">" -> if (a > b) 1 else 0; "<=" -> if (a <= b) 1 else 0; ">=" -> if (a >= b) 1 else 0; "==" -> if (a == b) 1 else 0; else -> if (a != b) 1 else 0
                    }
                }
            }
        }
        fun test(tokens: List<Token>, directive: String): Pair<Long?, List<Pair<String, String>>> {
            val parser = ExpressionParser(tokens); val diagnostics = mutableListOf<Pair<String, String>>()
            try {
                if (tokens.isEmpty()) throw PPError("#$directive with no expression"); val expression = parser.expression(); if (parser.index != tokens.size) throw PPError("missing binary operator before \"${tokens[parser.index].text}\""); val value = evaluate(expression, diagnostics); return Pair(value, diagnostics)
            }
            catch (error: PPError) {
                diagnostics.add(Pair("error", error.reason)); return Pair(null, diagnostics)
            }
        }
    }
}
