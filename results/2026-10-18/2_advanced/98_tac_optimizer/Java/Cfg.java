import java.util.*;
final class Cfg {
    static final class Block {
        final int number, start;
        int end;
        final List<String> labels;
        final List<Integer> instructions = new ArrayList<>(), predecessors = new ArrayList<>(),
                            successors = new ArrayList<>();
        Block(int number, List<String> labels, int start) {
            this.number = number;
            this.labels = List.copyOf(labels);
            this.start = start;
        }
    }
    static final class Loop {
        final int header;
        final List<Integer> latches;
        final Set<Integer> blocks, exits = new TreeSet<>(), outside = new TreeSet<>();
        int depth;
        Loop(int header, List<Integer> latches, Set<Integer> blocks) {
            this.header = header;
            this.latches = latches;
            this.blocks = blocks;
        }
    }
    final TacParser.Function function;
    final TreeMap<Integer, Block> blocks = new TreeMap<>();
    final TreeMap<Integer, TacParser.Instruction> instructions = new TreeMap<>();
    final Map<Integer, Integer> positions = new HashMap<>(), blockOf = new HashMap<>(),
                                immediate = new HashMap<>(), depth = new HashMap<>();
    final Set<Integer> reachable = new TreeSet<>();
    final List<Integer> postorder = new ArrayList<>(), reversePostorder = new ArrayList<>();
    final Map<Integer, List<Integer>> reachablePredecessors = new HashMap<>();
    final Map<Integer, Set<Integer>> dominators = new HashMap<>();
    final List<Loop> loops = new ArrayList<>();
    Cfg(TacParser.Function function) {
        this.function = function;
        split();
        connect();
        visit(1);
        reversePostorder.addAll(postorder);
        Collections.reverse(reversePostorder);
        for (int number : reachable) {
            List<Integer> predecessors = new ArrayList<>();
            for (int predecessor : blocks.get(number).predecessors)
                if (reachable.contains(predecessor))
                    predecessors.add(predecessor);
            reachablePredecessors.put(number, predecessors);
        }
        dominance();
        loops();
    }
    void split() {
        List<String> pending = new ArrayList<>();
        int firstLabel = 0;
        Block current = null;
        TacParser.Kind previous = null;
        for (int index = 0; index < function.code.size(); index++) {
            TacParser.Line line = function.code.get(index);
            if (line instanceof TacParser.Label label) {
                if (pending.isEmpty())
                    firstLabel = index;
                pending.add(label.name());
                continue;
            }
            TacParser.Instruction instruction = (TacParser.Instruction)line;
            int number = instructions.size() + 1;
            if (current == null || !pending.isEmpty() || previous == TacParser.Kind.GOTO ||
                previous == TacParser.Kind.IF || previous == TacParser.Kind.RETURN) {
                int start = pending.isEmpty() ? index : firstLabel;
                if (current != null)
                    current.end = start;
                current = new Block(blocks.size() + 1, pending, start);
                blocks.put(current.number, current);
                pending.clear();
            }
            instructions.put(number, instruction);
            positions.put(number, index);
            blockOf.put(number, current.number);
            current.instructions.add(number);
            previous = instruction.kind();
        }
        current.end = function.code.size();
    }
    void connect() {
        Map<String, Integer> labels = new HashMap<>();
        for (Block block : blocks.values())
            for (String label : block.labels)
                labels.put(label, block.number);
        for (Block block : blocks.values()) {
            TacParser.Instruction last = instructions.get(block.instructions.getLast());
            if (last.kind() == TacParser.Kind.GOTO)
                block.successors.add(labels.get(last.name()));
            else if (last.kind() == TacParser.Kind.IF) {
                block.successors.add(block.number + 1);
                int target = labels.get(last.name());
                if (target != block.number + 1)
                    block.successors.add(target);
            } else if (last.kind() != TacParser.Kind.RETURN)
                block.successors.add(block.number + 1);
            for (int successor : block.successors)
                blocks.get(successor).predecessors.add(block.number);
        }
    }
    void visit(int number) {
        reachable.add(number);
        for (int successor : blocks.get(number).successors)
            if (!reachable.contains(successor))
                visit(successor);
        postorder.add(number);
    }
    void dominance() {
        for (int number : reachable)
            dominators.put(number, new HashSet<>(reachable));
        dominators.put(1, new HashSet<>(Set.of(1)));
        boolean changed;
        do {
            changed = false;
            for (int number : reversePostorder.subList(1, reversePostorder.size())) {
                List<Integer> predecessors = reachablePredecessors.get(number);
                Set<Integer> value = new HashSet<>(dominators.get(predecessors.getFirst()));
                for (int predecessor : predecessors)
                    value.retainAll(dominators.get(predecessor));
                value.add(number);
                if (!value.equals(dominators.get(number))) {
                    dominators.put(number, value);
                    changed = true;
                }
            }
        } while (changed);
        for (int number : reachable)
            if (number != 1) {
                int parent = 0;
                for (int candidate : dominators.get(number))
                    if (candidate != number && (parent == 0 || dominators.get(candidate).size() >
                                                                   dominators.get(parent).size()))
                        parent = candidate;
                immediate.put(number, parent);
            }
    }
    void loops() {
        for (int header : reachable) {
            List<Integer> latches = new ArrayList<>();
            for (int number : reachablePredecessors.get(header))
                if (dominators.get(number).contains(header))
                    latches.add(number);
            if (latches.isEmpty())
                continue;
            Set<Integer> members = new TreeSet<>();
            members.add(header);
            members.addAll(latches);
            Deque<Integer> pending = new ArrayDeque<>();
            for (int latch : latches)
                if (latch != header)
                    pending.push(latch);
            while (!pending.isEmpty()) {
                int number = pending.pop();
                for (int predecessor : reachablePredecessors.get(number))
                    if (members.add(predecessor))
                        pending.push(predecessor);
            }
            loops.add(new Loop(header, latches, members));
        }
        for (int number : blocks.keySet()) {
            int count = 0;
            for (Loop loop : loops)
                if (loop.blocks.contains(number))
                    count++;
            depth.put(number, count);
        }
        for (Loop loop : loops) {
            for (Loop other : loops)
                if (other.blocks.contains(loop.header))
                    loop.depth++;
            for (int number : loop.blocks) {
                Block block = blocks.get(number);
                boolean exit = false;
                for (int successor : block.successors)
                    if (!loop.blocks.contains(successor)) {
                        loop.outside.add(successor);
                        exit = true;
                    }
                if (exit ||
                    instructions.get(block.instructions.getLast()).kind() == TacParser.Kind.RETURN)
                    loop.exits.add(number);
            }
        }
    }
}
