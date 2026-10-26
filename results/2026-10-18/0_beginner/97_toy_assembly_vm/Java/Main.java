public class Main {
    static int value(String token, int[] registers) {
        char first = token.charAt(0);
        return first >= 'A' && first <= 'D' ? registers[first - 'A'] : Integer.parseInt(token);
    }

    public static void main(String[] args) {
        String[] program = {"SET A 1", "SET B 1", "SET D 8", "MUL A B", "PRINT A", "ADD B 1", "SUB D 1",
            "JNZ D -4", "SET A 1071", "SET B 462", "SET C A", "MOD C B", "SET A B",
            "SET B C", "JNZ B -4", "PRINT A", "HALT"};
        int[] registers = new int[4];
        int pc = 0, executed = 0;
        while (pc >= 0 && pc < program.length) {
            String[] parts = program[pc].split(" ");
            executed++;
            if (parts[0].equals("HALT")) {
                break;
            }
            if (parts[0].equals("JNZ")) {
                pc += value(parts[1], registers) != 0 ? Integer.parseInt(parts[2]) : 1;
                continue;
            }
            if (parts[0].equals("PRINT")) {
                System.out.println(value(parts[1], registers));
            } else {
                int target = parts[1].charAt(0) - 'A', operand = value(parts[2], registers);
                switch (parts[0]) {
                    case "SET" -> registers[target] = operand;
                    case "ADD" -> registers[target] += operand;
                    case "SUB" -> registers[target] -= operand;
                    case "MUL" -> registers[target] *= operand;
                    case "MOD" -> registers[target] %= operand;
                }
            }
            pc++;
        }
        System.out.println("executed: " + executed);
    }
}
