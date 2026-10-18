import java.math.BigDecimal
import java.math.RoundingMode

fun value(token: String, registers: IntArray): Int =
    if (token[0] in 'A'..'D') registers[token[0] - 'A'] else token.toInt()
fun main() {
    val program = listOf("SET A 1", "SET B 1", "SET D 8", "MUL A B", "PRINT A", "ADD B 1", "SUB D 1",
        "JNZ D -4", "SET A 1071", "SET B 462", "SET C A", "MOD C B", "SET A B",
        "SET B C", "JNZ B -4", "PRINT A", "HALT")
    val registers = IntArray(4)
    var pc = 0
    var executed = 0
    while (pc in program.indices) {
        val parts = program[pc].split(' ')
        executed++
        if (parts[0] == "HALT") break
        if (parts[0] == "JNZ") {
            pc += if (value(parts[1],registers) != 0) parts[2].toInt() else 1
            continue
        }
        if (parts[0] == "PRINT") println(value(parts[1],registers))
        else {
            val target = parts[1][0] - 'A'
            val operand = value(parts[2],registers)
            when (parts[0]) {
                "SET" -> registers[target] = operand
                "ADD" -> registers[target] += operand
                "SUB" -> registers[target] -= operand
                "MUL" -> registers[target] *= operand
                "MOD" -> registers[target] %= operand
            }
        }
        pc++
    }
    println("executed: $executed")
}
