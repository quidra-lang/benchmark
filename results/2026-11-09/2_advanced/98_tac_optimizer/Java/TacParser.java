import java.util.*;
final class TacParser {
    enum Kind {
        COPY,
        BIN,
        LOAD,
        STORE,
        GOTO,
        IF,
        PARAM,
        CALL,
        RETURN,
        READ,
        PRINT;
        public String toString() { return name().toLowerCase(Locale.ROOT); }
    }
    sealed interface Operand permits Variable, Constant {}
    record Variable(String name) implements Operand {
        public String toString() { return name; }
    }
    record Constant(int value) implements Operand {
        public String toString() { return Integer.toString(value); }
    }
    sealed interface Line permits Label, Instruction {}
    record Label(String name) implements Line {}
    record Expression(Kind kind, String operation, Operand a, Operand b) {
        public String toString() {
            return kind == Kind.LOAD ? operation + "[" + a + "]" : a.toString() + operation + b;
        }
    }
    record Instruction(Kind kind, String destination, Operand a, Operand b, String operation,
                       String name, int count) implements Line {
        List<Integer> operandFields() {
            return switch (kind) {
                case BIN, IF, STORE -> List.of(0, 1);
                case COPY, LOAD, PARAM, PRINT -> List.of(0);
                case RETURN -> a == null ? List.of() : List.of(0);
                default -> List.of();
            };
        }
        Operand operand(int field) { return field == 0 ? a : b; }
        List<String> used() {
            List<String> result = new ArrayList<>();
            for (int field : operandFields())
                if (operand(field) instanceof Variable v)
                    result.add(v.name());
            return result;
        }
        Expression expression() {
            return kind == Kind.BIN ? new Expression(kind, operation, a, b)
            : kind == Kind.LOAD     ? new Expression(kind, name, a, null)
                                    : null;
        }
        Instruction withOperand(int field, Operand operand) {
            return new Instruction(kind, destination, field == 0 ? operand : a,
                                   field == 1 ? operand : b, operation, name, count);
        }
        Instruction withDestination(String destination) {
            return new Instruction(kind, destination, a, b, operation, name, count);
        }
        Instruction withName(String name) {
            return new Instruction(kind, destination, a, b, operation, name, count);
        }
        public String toString() {
            return switch (kind) {
                case COPY -> destination + " = " + a;
                case BIN -> destination + " = " + a + " " + operation + " " + b;
                case LOAD -> destination + " = " + name + "[" + a + "]";
                case STORE -> name + "[" + a + "] = " + b;
                case GOTO -> "goto " + name;
                case IF -> "if " + a + " " + operation + " " + b + " goto " + name;
                case CALL ->
                    (destination == null ? "" : destination + " = ") + "call " + name + " " + count;
                case READ -> "read " + destination;
                case RETURN -> a == null ? "return" : "return " + a;
                default -> kind + " " + a;
            };
        }
    }
    static final class Function {
        final String name;
        final List<String> parameters;
        List<Line> code;
        int temporarySerial, preheaderSerial;
        Function(String name, List<String> parameters, List<Line> code) {
            this.name = name;
            this.parameters = List.copyOf(parameters);
            this.code = new ArrayList<>(code);
        }
        Function copy() { return new Function(name, parameters, code); }
        List<Instruction> instructions() {
            List<Instruction> result = new ArrayList<>();
            for (Line line : code)
                if (line instanceof Instruction instruction)
                    result.add(instruction);
            return result;
        }
    }
    record Array(String name, int size) {}
    record Program(List<Array> arrays, List<Function> functions) {}
    static Instruction copy(String destination, Operand a) {
        return new Instruction(Kind.COPY, destination, a, null, null, null, 0);
    }
    static Operand operand(String word) {
        return word.charAt(0) == '-' || Character.isDigit(word.charAt(0))
            ? new Constant(Integer.parseInt(word))
            : new Variable(word);
    }
    record ArrayOperand(String name, Operand index) {}
    static ArrayOperand arrayOperand(String word) {
        int bracket = word.indexOf('[');
        return new ArrayOperand(word.substring(0, bracket),
                                operand(word.substring(bracket + 1, word.length() - 1)));
    }
    static Instruction instruction(String[] words) {
        String first = words[0];
        switch (first) {
        case "goto":
            return new Instruction(Kind.GOTO, null, null, null, null, words[1], 0);
        case "if":
            return new Instruction(Kind.IF, null, operand(words[1]), operand(words[3]), words[2],
                                   words[5], 0);
        case "param", "print":
            return new Instruction(first.equals("param") ? Kind.PARAM : Kind.PRINT, null,
                                   operand(words[1]), null, null, null, 0);
        case "return":
            return new Instruction(Kind.RETURN, null, words.length == 2 ? operand(words[1]) : null,
                                   null, null, null, 0);
        case "read":
            return new Instruction(Kind.READ, words[1], null, null, null, null, 0);
        case "call":
            return new Instruction(Kind.CALL, null, null, null, null, words[1],
                                   Integer.parseInt(words[2]));
        default:
            break;
        }
        if (first.indexOf('[') >= 0) {
            ArrayOperand array = arrayOperand(first);
            return new Instruction(Kind.STORE, null, array.index(), operand(words[2]), null,
                                   array.name(), 0);
        }
        if (words[2].equals("call"))
            return new Instruction(Kind.CALL, first, null, null, null, words[3],
                                   Integer.parseInt(words[4]));
        if (words.length == 5)
            return new Instruction(Kind.BIN, first, operand(words[2]), operand(words[4]), words[3],
                                   null, 0);
        if (words[2].indexOf('[') >= 0) {
            ArrayOperand array = arrayOperand(words[2]);
            return new Instruction(Kind.LOAD, first, array.index(), null, null, array.name(), 0);
        }
        return copy(first, operand(words[2]));
    }
    static Program parse(String text) {
        List<Array> arrays = new ArrayList<>();
        List<Function> functions = new ArrayList<>();
        Function current = null;
        for (String line : text.lines().toList()) {
            String trimmed = line.trim();
            if (trimmed.isEmpty() || trimmed.startsWith("#"))
                continue;
            String[] words = trimmed.split(" +");
            if (words[0].equals("array"))
                arrays.add(new Array(words[1], Integer.parseInt(words[2])));
            else if (words[0].equals("func")) {
                current = new Function(words[1], Arrays.asList(words).subList(2, words.length),
                                       List.of());
                functions.add(current);
            } else if (words[0].equals("end"))
                current = null;
            else if (words.length == 1 && words[0].endsWith(":"))
                current.code.add(new Label(words[0].substring(0, words[0].length() - 1)));
            else
                current.code.add(instruction(words));
        }
        return new Program(arrays, functions);
    }
    static long calculate(String operation, long first, long second) {
        return switch (operation) {
            case "+" -> first + second;
            case "-" -> first - second;
            case "*" -> first *second;
            case "/" -> first / second;
            case "%" -> first % second;
            case "<" -> first < second ? 1 : 0;
            case "<=" -> first <= second ? 1 : 0;
            case ">" -> first > second ? 1 : 0;
            case ">=" -> first >= second ? 1 : 0;
            case "==" -> first == second ? 1 : 0;
            default -> first != second ? 1 : 0;
        };
    }
    static List<String> functionLines(Function function) {
        List<String> result = new ArrayList<>();
        result.add(
            "func " + function.name +
            (function.parameters.isEmpty() ? "" : " " + String.join(" ", function.parameters)));
        for (Line line : function.code)
            result.add(line instanceof Label label ? label.name() + ":" : "    " + line);
        result.add("end");
        return result;
    }
    static List<String> programLines(Program program) {
        List<String> result = new ArrayList<>();
        for (Array array : program.arrays())
            result.add("array " + array.name() + " " + array.size());
        for (Function function : program.functions()) {
            if (!result.isEmpty())
                result.add("");
            result.addAll(functionLines(function));
        }
        return result;
    }
}
