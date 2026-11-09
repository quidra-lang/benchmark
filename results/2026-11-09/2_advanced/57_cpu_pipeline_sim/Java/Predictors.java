import java.util.*;

final class Predictors {
    static final class BTB {
        int[] pcs, targets;
        BTB(int entries) {
            pcs = new int[entries];
            targets = new int[entries];
            Arrays.fill(pcs, -1);
        }
        int lookup(int pc) {
            int i = pc / 4 % pcs.length;
            return pcs[i] == pc ? targets[i] : -1;
        }
        void insert(int pc, int target) {
            int i = pc / 4 % pcs.length;
            pcs[i] = pc;
            targets[i] = target;
        }
    }
    static final class RAS {
        int depth;
        List<Integer> stack = new ArrayList<>();
        RAS(int depth) {
            this.depth = depth;
        }
        void push(int address) {
            if (depth == 0)
                return;
            if (stack.size() == depth)
                stack.remove(0);
            stack.add(address);
        }
        int pop() {
            return stack.isEmpty() ? -1 : stack.remove(stack.size() - 1);
        }
    }
    static int updated(int counter, boolean taken) {
        return taken ? Math.min(3, counter + 1) : Math.max(0, counter - 1);
    }
    static final class Direction {
        String scheme;
        int[] parameters, table, local, global, chooser;
        int history;
        Direction(TraceIO.Predictor definition) {
            scheme = definition.scheme();
            parameters = definition.parameters();
            if (scheme.equals("TOURNAMENT")) {
                local = ones(parameters[0]);
                global = ones(parameters[1]);
                chooser = ones(parameters[3]);
            } else if (parameters.length > 0) {
                table = ones(parameters[0]);
                if (scheme.equals("ONEBIT"))
                    Arrays.fill(table, 0);
            }
        }
        static int[] ones(int size) {
            int[] a = new int[size];
            Arrays.fill(a, 1);
            return a;
        }
        boolean prediction(int pc, int target) {
            int q = pc / 4;
            return switch (scheme) {
                case "STATIC_NT", "PERFECT" -> false;
                case "BTFN" -> target < pc;
                case "ONEBIT" -> table[q % table.length] == 1;
                case "TWOBIT" -> table[q % table.length] >= 2;
                case "GSHARE" -> table[(q ^ history) % table.length] >= 2;
                default ->
                    chooser[q % chooser.length] >= 2 ? global[(q ^ history) % global.length] >= 2
                                                     : local[q % local.length] >= 2;
            };
        }
        void update(int pc, boolean taken) {
            int q = pc / 4;
            if (scheme.equals("TOURNAMENT")) {
                int l = q % local.length, g = (q ^ history) % global.length, c = q % chooser.length;
                boolean lp = local[l] >= 2, gp = global[g] >= 2;
                if (lp != gp)
                    chooser[c] = updated(chooser[c], gp == taken);
                local[l] = updated(local[l], taken);
                global[g] = updated(global[g], taken);
                history = (2 * history + (taken ? 1 : 0)) % (1 << parameters[2]);
            } else if (table != null) {
                int i = (scheme.equals("GSHARE") ? q ^ history : q) % table.length;
                table[i] = scheme.equals("ONEBIT") ? (taken ? 1 : 0) : updated(table[i], taken);
                if (scheme.equals("GSHARE"))
                    history = (2 * history + (taken ? 1 : 0)) % (1 << parameters[1]);
            }
        }
        int bits() {
            return switch (scheme) {
                case "ONEBIT" -> parameters[0];
                case "TWOBIT" -> 2 * parameters[0];
                case "GSHARE" -> 2 * parameters[0] + parameters[1];
                case "TOURNAMENT" -> 2 * (parameters[0] + parameters[1] + parameters[3]) + parameters[2];
                default -> 0;
            };
        }
    }
}
