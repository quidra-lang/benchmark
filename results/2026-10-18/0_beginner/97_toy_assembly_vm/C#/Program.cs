using System;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
static int Value(string token, int[] registers) {
    char first = token[0];
    return first >= 'A' && first <= 'D' ? registers[first - 'A'] : int.Parse(token,CultureInfo.InvariantCulture);
}
string[] program = { "SET A 1", "SET B 1", "SET D 8", "MUL A B", "PRINT A", "ADD B 1", "SUB D 1",
    "JNZ D -4", "SET A 1071", "SET B 462", "SET C A", "MOD C B", "SET A B",
    "SET B C", "JNZ B -4", "PRINT A", "HALT" };
int[] registers = new int[4];
int pc = 0, executed = 0;
while (pc >= 0 && pc < program.Length) {
    string[] parts = program[pc].Split(' ');
    executed++;
    if (parts[0] == "HALT") break;
    if (parts[0] == "JNZ") {
        pc += Value(parts[1],registers) != 0 ? int.Parse(parts[2],CultureInfo.InvariantCulture) : 1;
        continue;
    }
    if (parts[0] == "PRINT") Console.WriteLine(Value(parts[1],registers));
    else {
        int target = parts[1][0] - 'A', operand = Value(parts[2],registers);
        switch (parts[0]) {
            case "SET":
                registers[target] = operand;
                break;
            case "ADD":
                registers[target] += operand;
                break;
            case "SUB":
                registers[target] -= operand;
                break;
            case "MUL":
                registers[target] *= operand;
                break;
            case "MOD":
                registers[target] %= operand;
                break;
        }
    }
    pc++;
}
Console.WriteLine($"executed: {executed}");
