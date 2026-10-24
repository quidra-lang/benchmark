func value(_ token: String, _ registers: [Int]) -> Int {
    let first = Int(token.utf8.first!)
    return first >= 65 && first <= 68 ? registers[first - 65] : Int(token)!
}
let program = ["SET A 1", "SET B 1", "SET D 8", "MUL A B", "PRINT A", "ADD B 1", "SUB D 1",
    "JNZ D -4", "SET A 1071", "SET B 462", "SET C A", "MOD C B", "SET A B",
    "SET B C", "JNZ B -4", "PRINT A", "HALT"]
var registers = [Int](repeating: 0, count: 4), pc = 0, executed = 0
while pc >= 0 && pc < program.count {
    let parts = program[pc].split(separator: " ").map(String.init)
    executed += 1
    if parts[0] == "HALT" { break }
    if parts[0] == "JNZ" {
        pc += value(parts[1],registers) != 0 ? Int(parts[2])! : 1
        continue
    }
    if parts[0] == "PRINT" { print(value(parts[1],registers)) }
    else {
        let target = Int(parts[1].utf8.first!) - 65, operand = value(parts[2],registers)
        switch parts[0] {
        case "SET": registers[target] = operand
        case "ADD": registers[target] += operand
        case "SUB": registers[target] -= operand
        case "MUL": registers[target] *= operand
        default: registers[target] %= operand
        }
    }
    pc += 1
}
print("executed: \(executed)")
