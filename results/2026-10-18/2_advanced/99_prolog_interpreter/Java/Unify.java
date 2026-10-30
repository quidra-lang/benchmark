import java.util.*;
final class Unify {
    record Pair(Terms.Term first, Terms.Term second) {}
    static final class Trail {
        final List<Terms.Variable> bindings = new ArrayList<>();
        int mark() { return bindings.size(); }
        void undo(int mark) {
            while (bindings.size() > mark)
                bindings.removeLast().binding = null;
        }
        boolean unify(Terms.Term first, Terms.Term second) {
            Deque<Pair> pending = new ArrayDeque<>();
            pending.push(new Pair(first, second));
            while (!pending.isEmpty()) {
                Pair pair = pending.pop();
                Terms.Term a = Terms.dereference(pair.first()),
                           b = Terms.dereference(pair.second());
                if (a == b)
                    continue;
                if (a instanceof Terms.Variable variable) {
                    variable.binding = b;
                    bindings.add(variable);
                } else if (b instanceof Terms.Variable variable) {
                    variable.binding = a;
                    bindings.add(variable);
                } else if (a instanceof Terms.Compound x && b instanceof Terms.Compound y) {
                    if (!x.name().equals(y.name()) || x.args().size() != y.args().size())
                        return false;
                    for (int i = x.args().size() - 1; i >= 0; i--)
                        pending.push(new Pair(x.args().get(i), y.args().get(i)));
                } else if (!a.equals(b))
                    return false;
            }
            return true;
        }
    }
    static boolean identical(Terms.Term first, Terms.Term second) {
        Deque<Pair> pending = new ArrayDeque<>();
        pending.push(new Pair(first, second));
        while (!pending.isEmpty()) {
            Pair pair = pending.pop();
            Terms.Term a = Terms.dereference(pair.first()), b = Terms.dereference(pair.second());
            if (a == b)
                continue;
            if (a instanceof Terms.Variable || b instanceof Terms.Variable)
                return false;
            if (a instanceof Terms.Compound x && b instanceof Terms.Compound y) {
                if (!x.name().equals(y.name()) || x.args().size() != y.args().size())
                    return false;
                for (int i = x.args().size() - 1; i >= 0; i--)
                    pending.push(new Pair(x.args().get(i), y.args().get(i)));
            } else if (!a.equals(b))
                return false;
        }
        return true;
    }
}
