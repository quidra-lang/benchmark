sealed interface Operand {
    data class Constant(val value: Long) : Operand
    data class Variable(val name: String) : Operand
    val text: String get() = when (this) {
        is Constant -> value.toString()
        is Variable -> name
    }
    val variable: String? get() = (this as? Variable)?.name
    val constant: Long? get() = (this as? Constant)?.value
    companion object {
        fun parse(text: String): Operand = if (text[0] == '-' || text[0] in '0'..'9') Constant(text.toLong()) else Variable(text)
    }
}
data class TacExpression(val kind: String, val operation: String, val a: Operand, val b: Operand?) {
    val text: String get() = if (kind == "load") "$operation[${a.text}]" else a.text + operation + b!!.text
    fun uses(name: String): Boolean = a.variable == name || b?.variable == name
}
data class Instruction(var kind: String, var destination: String? = null, var a: Operand? = null, var b: Operand? = null, var operation: String = "", var target: String = "", var array: String = "", var function: String = "", var count: Int = 0) {
    val operands: List<Operand> get() = listOfNotNull(a, b)
    val used: List<String> get() = operands.mapNotNull {
        it.variable
    }
    val expression: TacExpression? get() = if (kind in listOf("bin", "load")) TacExpression(kind, if (kind == "bin") operation else array, a!!, b) else null
    val text: String get() {
        val left = a?.text ?: ""
        val right = b?.text ?: ""
        val d = destination ?: ""
        return when (kind) {
            "copy" -> "$d = $left"
            "bin" -> "$d = $left $operation $right"
            "load" -> "$d = $array[$left]"
            "store" -> "$array[$left] = $right"
            "goto" -> "goto $target"
            "if" -> "if $left $operation $right goto $target"
            "read" -> "read $d"
            "return" -> if (a == null) "return" else "return $left"
            "call" -> (if (destination == null) "" else "$d = ") + "call $function $count"
            else -> "$kind $left"
        }
    }
    companion object {
        fun move(destination: String, a: Operand): Instruction = Instruction("copy", destination, a)
    }
}
sealed interface CodeLine {
    data class Label(val name: String) : CodeLine
    data class Code(val instruction: Instruction) : CodeLine
}
data class Function(val name: String, var parameters: List<String>, var code: List<CodeLine>, var temporary: Int = 0, var preheader: Int = 0) {
    val instructions: List<Instruction> get() = code.mapNotNull {
        (it as? CodeLine.Code)?.instruction
    }
    val text: List<String> get() = listOf("func " + name + parameters.joinToString("") {
        " $it"
    }) + code.map {
        when (it) {
            is CodeLine.Label -> it.name + ":"
            is CodeLine.Code -> "    " + it.instruction.text
        }
    } + "end"
    fun deepCopy(): Function = copy(parameters = parameters.toList(), code = code.map {
        if (it is CodeLine.Code) CodeLine.Code(it.instruction.copy()) else it
    })
}
data class Program(val arrays: List<Pair<String, Int>>, var functions: List<Function>) {
    val text: List<String> get() {
        val lines = arrays.map {
            "array ${it.first} ${it.second}"
        }.toMutableList()
        for (function in functions) {
            if (lines.isNotEmpty()) lines.add("")
            lines.addAll(function.text)
        }
        return lines
    }
}
object TacParser {
    fun indexed(text: String): Pair<String, Operand> {
        val i = text.indexOf('[')
        return text.substring(0, i) to Operand.parse(text.substring(i + 1, text.length - 1))
    }
    fun parse(text: String): Program {
        val arrays = mutableListOf<Pair<String, Int>>()
        val functions = mutableListOf<Function>()
        for (line in text.lineSequence()) {
            val w = line.split(' ').filter {
                it.isNotEmpty()
            }
            if (w.isEmpty() || w[0].startsWith("#")) continue
            if (w[0] == "array") {
                arrays.add(w[1] to w[2].toInt())
                continue
            }
            if (w[0] == "func") {
                functions.add(Function(w[1], w.drop(2), emptyList()))
                continue
            }
            if (w[0] == "end") continue
            val f = functions.last()
            if (w.size == 1 && w[0].endsWith(":")) {
                f.code = f.code + CodeLine.Label(w[0].dropLast(1))
                continue
            }
            val instruction = Instruction("copy")
            when (w[0]) {
                "goto" -> {
                    instruction.kind = "goto"
                    instruction.target = w[1]
                }
                "if" -> {
                    instruction.kind = "if"
                    instruction.a = Operand.parse(w[1])
                    instruction.operation = w[2]
                    instruction.b = Operand.parse(w[3])
                    instruction.target = w[5]
                }
                "param", "return", "read", "print" -> {
                    instruction.kind = w[0]
                    if (w.size > 1) {
                        if (w[0] == "read") instruction.destination = w[1] else instruction.a = Operand.parse(w[1])
                    }
                }
                else -> if ('[' in w[0]) {
                    instruction.kind = "store"
                    val (array, index) = indexed(w[0])
                    instruction.array = array
                    instruction.a = index
                    instruction.b = Operand.parse(w[2])
                }
                else {
                    val start = if (w[0] == "call") 0 else 2
                    if (start == 2) instruction.destination = w[0]
                    if (w[start] == "call") {
                        instruction.kind = "call"
                        instruction.function = w[start + 1]
                        instruction.count = w[start + 2].toInt()
                    }
                    else if (w.size == 5) {
                        instruction.kind = "bin"
                        instruction.a = Operand.parse(w[2])
                        instruction.operation = w[3]
                        instruction.b = Operand.parse(w[4])
                    }
                    else if ('[' in w[2]) {
                        instruction.kind = "load"
                        val (array, index) = indexed(w[2])
                        instruction.array = array
                        instruction.a = index
                    }
                    else instruction.a = Operand.parse(w[2])
                }
            }
            f.code = f.code + CodeLine.Code(instruction)
        }
        return Program(arrays, functions)
    }
    fun operation(op: String, a: Long, b: Long): Long = when (op) {
        "+" -> a + b
        "-" -> a - b
        "*" -> a * b
        "/" -> a / b
        "%" -> a % b
        "<" -> if (a < b) 1 else 0
        "<=" -> if (a <= b) 1 else 0
        ">" -> if (a > b) 1 else 0
        ">=" -> if (a >= b) 1 else 0
        "==" -> if (a == b) 1 else 0
        else -> if (a != b) 1 else 0
    }
    fun labels(function: Function): Map<String, Int> {
        val labels = mutableMapOf<String, Int>()
        var index = 0
        for (line in function.code) {
            when (line) {
                is CodeLine.Label -> labels[line.name] = index
                is CodeLine.Code -> index++
            }
        }
        return labels
    }
}
