import java.util.*;
final class Optimizations {
    static void rewrite(TacParser.Function function,
                        Map<Integer, List<TacParser.Line>> replacements,
                        Map<Integer, List<TacParser.Line>> insertions) {
        List<TacParser.Line> result = new ArrayList<>();
        int number = 0;
        for (int index = 0; index < function.code.size(); index++) {
            result.addAll(insertions.getOrDefault(index, List.of()));
            TacParser.Line line = function.code.get(index);
            if (line instanceof TacParser.Label)
                result.add(line);
            else
                result.addAll(replacements.getOrDefault(++number, List.of(line)));
        }
        result.addAll(insertions.getOrDefault(function.code.size(), List.of()));
        function.code = result;
    }
    static void rewrite(TacParser.Function function,
                        Map<Integer, List<TacParser.Line>> replacements) {
        rewrite(function, replacements, Map.of());
    }
    static boolean constant(TacParser.Operand operand, int value) {
        return operand instanceof TacParser.Constant c && c.value() == value;
    }
    static TacParser.Instruction fold(TacParser.Instruction instruction) {
        if (instruction.kind() != TacParser.Kind.BIN && instruction.kind() != TacParser.Kind.IF)
            return instruction;
        TacParser.Operand first = instruction.a(), second = instruction.b();
        boolean a = first instanceof TacParser.Constant, b = second instanceof TacParser.Constant;
        if (a && b) {
            int x = ((TacParser.Constant)first).value(), y = ((TacParser.Constant)second).value();
            if ((instruction.operation().equals("/") || instruction.operation().equals("%")) &&
                y == 0)
                return instruction;
            long result = TacParser.calculate(instruction.operation(), x, y);
            if (instruction.kind() == TacParser.Kind.IF)
                return result != 0 ? new TacParser.Instruction(TacParser.Kind.GOTO, null, null,
                                                               null, null, instruction.name(), 0)
                                   : null;
            if (result >= Integer.MIN_VALUE && result <= Integer.MAX_VALUE)
                return TacParser.copy(instruction.destination(),
                                      new TacParser.Constant((int)result));
            return instruction;
        }
        if (instruction.kind() != TacParser.Kind.BIN || a == b)
            return instruction;
        TacParser.Operand replacement = null;
        String op = instruction.operation();
        if (op.equals("+") && (constant(first, 0) || constant(second, 0)))
            replacement = a ? second : first;
        else if (op.equals("-") && constant(second, 0))
            replacement = first;
        else if (op.equals("*") && (constant(first, 1) || constant(second, 1)))
            replacement = a ? second : first;
        else if (op.equals("/") && constant(second, 1))
            replacement = first;
        else if (op.equals("*") && (constant(first, 0) || constant(second, 0)))
            replacement = new TacParser.Constant(0);
        return replacement == null ? instruction
                                   : TacParser.copy(instruction.destination(), replacement);
    }
    record CseEdits(String temporary, Map<Integer, List<TacParser.Line>> replacements) {}
    static CseEdits cse(TacParser.Function function, Cfg graph, Set<Integer> sources,
                        List<Integer> candidates) {
        String temporary = "_t" + (++function.temporarySerial);
        Map<Integer, List<TacParser.Line>> result = new HashMap<>();
        for (int number : sources) {
            TacParser.Instruction instruction = graph.instructions.get(number);
            result.put(number, List.of(instruction.withDestination(temporary),
                                       TacParser.copy(instruction.destination(),
                                                      new TacParser.Variable(temporary))));
        }
        for (int number : candidates)
            result.put(number, List.of(TacParser.copy(graph.instructions.get(number).destination(),
                                                      new TacParser.Variable(temporary))));
        return new CseEdits(temporary, result);
    }
    static String hoist(TacParser.Function function, Cfg graph, Cfg.Loop loop,
                        List<Integer> moves) {
        Cfg.Block header = graph.blocks.get(loop.header);
        List<Integer> outside = new ArrayList<>();
        for (int number : header.predecessors)
            if (!loop.blocks.contains(number))
                outside.add(number);
        Map<Integer, List<TacParser.Line>> replacements = new HashMap<>();
        List<TacParser.Line> instructions = new ArrayList<>();
        for (int number : moves) {
            replacements.put(number, List.of());
            instructions.add(graph.instructions.get(number));
        }
        int position;
        String destination;
        List<TacParser.Line> insertion;
        if (loop.header != 1 && outside.size() == 1 &&
            graph.blocks.get(outside.getFirst()).successors.equals(List.of(loop.header))) {
            Cfg.Block preheader = graph.blocks.get(outside.getFirst());
            int last = preheader.instructions.getLast();
            position = graph.positions.get(last);
            TacParser.Kind kind = graph.instructions.get(last).kind();
            if (kind != TacParser.Kind.GOTO && kind != TacParser.Kind.IF)
                position++;
            insertion = instructions;
            destination = "B" + preheader.number;
        } else {
            String label = "_p" + (++function.preheaderSerial);
            position = header.start;
            insertion = new ArrayList<>();
            insertion.add(new TacParser.Label(label));
            insertion.addAll(instructions);
            destination = "new " + label;
            for (int number : outside) {
                int last = graph.blocks.get(number).instructions.getLast();
                TacParser.Instruction instruction = graph.instructions.get(last);
                if ((instruction.kind() == TacParser.Kind.GOTO ||
                     instruction.kind() == TacParser.Kind.IF) &&
                    header.labels.contains(instruction.name()))
                    replacements.put(last, List.of(instruction.withName(label)));
            }
        }
        rewrite(function, replacements, Map.of(position, insertion));
        return destination;
    }
    record Removal(List<Integer> blocks, List<Integer> jumps, List<String> labels) {}
    record NumberedLine(TacParser.Line line, Integer number) {}
    static Removal removeUnreachable(TacParser.Function function, Cfg graph) {
        List<Integer> removedBlocks = new ArrayList<>(), jumps = new ArrayList<>();
        Set<Integer> deleted = new HashSet<>();
        for (Cfg.Block block : graph.blocks.values())
            if (!graph.reachable.contains(block.number)) {
                removedBlocks.add(block.number);
                for (int i = block.start; i < block.end; i++)
                    deleted.add(i);
            }
        Map<Integer, Integer> numbers = new HashMap<>();
        for (var entry : graph.positions.entrySet())
            numbers.put(entry.getValue(), entry.getKey());
        List<NumberedLine> remaining = new ArrayList<>();
        for (int i = 0; i < function.code.size(); i++)
            if (!deleted.contains(i))
                remaining.add(new NumberedLine(function.code.get(i), numbers.get(i)));
        for (int i = 0; i < remaining.size(); i++)
            if (remaining.get(i).line() instanceof TacParser.Instruction instruction &&
                (instruction.kind() == TacParser.Kind.GOTO ||
                 instruction.kind() == TacParser.Kind.IF)) {
                for (int next = i + 1; next < remaining.size() &&
                                       remaining.get(next).line() instanceof TacParser.Label;
                     next++)
                    if (((TacParser.Label)remaining.get(next).line())
                            .name()
                            .equals(instruction.name())) {
                        jumps.add(remaining.get(i).number());
                        break;
                    }
            }
        Set<Integer> removedJumps = new HashSet<>(jumps);
        remaining.removeIf(line -> removedJumps.contains(line.number()));
        Set<String> targets = new HashSet<>();
        for (NumberedLine line : remaining)
            if (line.line() instanceof TacParser.Instruction instruction &&
                (instruction.kind() == TacParser.Kind.GOTO ||
                 instruction.kind() == TacParser.Kind.IF))
                targets.add(instruction.name());
        List<String> labels = new ArrayList<>();
        List<TacParser.Line> code = new ArrayList<>();
        for (NumberedLine line : remaining) {
            if (line.line() instanceof TacParser.Label label && !targets.contains(label.name()))
                labels.add(label.name());
            else
                code.add(line.line());
        }
        function.code = code;
        return new Removal(removedBlocks, jumps, labels);
    }
}
