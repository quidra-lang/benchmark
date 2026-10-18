const program = [
  "SET A 1", "SET B 1", "SET D 8", "MUL A B", "PRINT A", "ADD B 1", "SUB D 1",
  "JNZ D -4", "SET A 1071", "SET B 462", "SET C A", "MOD C B", "SET A B",
  "SET B C", "JNZ B -4", "PRINT A", "HALT"
];
const registers = new Map([..."ABCD"].map(register => [register, 0]));
const value = token => registers.has(token) ? registers.get(token) : Number(token);
let pc = 0, executed = 0;
while (pc >= 0 && pc < program.length) {
  const parts = program[pc].split(" "), operation = parts[0];
  executed++;
  if (operation === "HALT") break;
  if (operation === "JNZ") {
    pc += value(parts[1]) !== 0 ? Number(parts[2]) : 1;
    continue;
  }
  if (operation === "PRINT") console.log(value(parts[1]));
  else {
    const register = parts[1], operand = value(parts[2]), current = registers.get(register);
    if (operation === "SET") registers.set(register, operand);
    else if (operation === "ADD") registers.set(register, current + operand);
    else if (operation === "SUB") registers.set(register, current - operand);
    else if (operation === "MUL") registers.set(register, current * operand);
    else if (operation === "MOD") registers.set(register, current % operand);
  }
  pc++;
}
console.log(`executed: ${executed}`);
