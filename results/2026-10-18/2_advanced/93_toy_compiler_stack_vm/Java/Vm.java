import java.util.*;
final class Vm {
    static final Set<Codegen.Op> BINARY = Set.of(
        Codegen.Op.ADD, Codegen.Op.SUB, Codegen.Op.MUL, Codegen.Op.DIV, Codegen.Op.MOD,
        Codegen.Op.LT, Codegen.Op.LE, Codegen.Op.GT, Codegen.Op.GE, Codegen.Op.EQ, Codegen.Op.NE);
    static final class RuntimeFault extends RuntimeException {
        RuntimeFault(String message) { super(message); }
    }
    static int calculate(Codegen.Op op, int first, int second) {
        long a = first, b = second;
        if ((op == Codegen.Op.DIV || op == Codegen.Op.MOD) && b == 0)
            throw new RuntimeFault("division by zero");
        long value = switch (op) {
            case ADD -> a + b;
            case SUB -> a - b;
            case MUL -> a *b;
            case DIV -> a / b;
            case MOD -> a % b;
            case NEG -> -a;
            case NOT -> a == 0 ? 1 : 0;
            case LT -> a < b ? 1 : 0;
            case LE -> a <= b ? 1 : 0;
            case GT -> a > b ? 1 : 0;
            case GE -> a >= b ? 1 : 0;
            case EQ -> a == b ? 1 : 0;
            case NE -> a != b ? 1 : 0;
            default -> throw new IllegalStateException();
        };
        if (value < Integer.MIN_VALUE || value > Integer.MAX_VALUE)
            throw new RuntimeFault("integer overflow");
        return (int)value;
    }
    record Frame(List<Integer> locals, int returnAddress) {}
    record CallPair(String caller, String callee) {}
    static final class Execution {
        List<Codegen.Instruction> code;
        List<String> owners;
        Map<Integer, String> starts;
        List<Integer> inputs, stack = new ArrayList<>();
        List<Frame> frames = new ArrayList<>();
        int[] globals, counts;
        int readPosition, pc, executed, maxStack, maxDepth, errorPc = -1;
        String error;
        Map<String, Integer> calls = new HashMap<>();
        Map<CallPair, Integer> pairs = new HashMap<>();
        List<String> output = new ArrayList<>();
        Execution(List<Codegen.Instruction> code, List<String> owners, Map<Integer, String> starts,
                  int globalSize, List<Integer> inputs) {
            this.code = code;
            this.owners = owners;
            this.starts = starts;
            this.inputs = inputs;
            globals = new int[globalSize];
            counts = new int[code.size()];
        }
        int pop() { return stack.removeLast(); }
        boolean step() {
            Codegen.Instruction instruction = code.get(pc);
            Codegen.Op op = instruction.op();
            int first = instruction.first(), second = instruction.second(), next = pc + 1;
            switch (op) {
            case PUSH -> stack.add(first);
            case POP -> pop();
            case LOADG -> stack.add(globals[first]);
            case STOREG -> globals[first] = pop();
            case LOADL -> stack.add(frames.getLast().locals().get(first));
            case STOREL -> frames.getLast().locals().set(first, pop());
            case LOADA, STOREA -> {
                int value = op == Codegen.Op.STOREA ? pop() : 0, index = pop();
                if (index < 0 || index >= second)
                    throw new RuntimeFault("index " + index + " out of bounds for array of size " +
                                           second);
                if (op == Codegen.Op.LOADA)
                    stack.add(globals[first + index]);
                else
                    globals[first + index] = value;
            }
            case ADD, SUB, MUL, DIV, MOD, LT, LE, GT, GE, EQ, NE -> {
                int b = pop(), a = pop();
                stack.add(calculate(op, a, b));
            }
            case NEG, NOT -> stack.add(calculate(op, pop(), 0));
            case JUMP -> next = first;
            case JUMPF, JUMPT -> {
                int value = pop();
                if ((value == 0) == (op == Codegen.Op.JUMPF))
                    next = first;
            }
            case CALL -> {
                if (frames.size() == 100)
                    throw new RuntimeFault("call depth limit exceeded");
                int from = stack.size() - second;
                List<Integer> arguments = new ArrayList<>(stack.subList(from, stack.size()));
                stack.subList(from, stack.size()).clear();
                frames.add(new Frame(arguments, next));
                String callee = starts.get(first);
                calls.merge(callee, 1, Integer::sum);
                pairs.merge(new CallPair(owners.get(pc), callee), 1, Integer::sum);
                next = first;
            }
            case ENTER -> {
                List<Integer> local = frames.getLast().locals();
                while (local.size() < first)
                    local.add(0);
            }
            case RET, RETV -> next = frames.removeLast().returnAddress();
            case READ -> {
                if (readPosition == inputs.size())
                    throw new RuntimeFault("read past end of input");
                stack.add(inputs.get(readPosition++));
            }
            case PRINT -> {
                int from = stack.size() - first;
                StringJoiner line = new StringJoiner(" ");
                for (int i = from; i < stack.size(); i++)
                    line.add(stack.get(i).toString());
                stack.subList(from, stack.size()).clear();
                output.add(line.toString());
            }
            case HALT -> {
            }
            }
            maxStack = Math.max(maxStack, stack.size());
            maxDepth = Math.max(maxDepth, frames.size());
            pc = next;
            return op != Codegen.Op.HALT;
        }
        Execution run() {
            while (true) {
                if (executed == 100000) {
                    error = "instruction limit exceeded";
                    errorPc = pc;
                    break;
                }
                executed++;
                counts[pc]++;
                try {
                    if (!step())
                        break;
                } catch (RuntimeFault fault) {
                    error = fault.getMessage();
                    errorPc = pc;
                    break;
                }
            }
            return this;
        }
    }
}
