import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Deque;
import java.util.List;

final class Components {
    private static final class Frame {
        final int node;
        int position;
        Frame(int node) { this.node = node; }
    }
    static List<List<Integer>> strong(List<List<Integer>> adjacency) {
        int count = adjacency.size(), counter = 0;
        int[] order = new int[count], low = new int[count];
        Arrays.fill(order, -1);
        boolean[] onStack = new boolean[count];
        Deque<Integer> stack = new ArrayDeque<>();
        List<List<Integer>> groups = new ArrayList<>();
        for (int root = 0; root < count; root++) {
            if (order[root] >= 0) continue;
            order[root] = low[root] = counter++;
            stack.push(root); onStack[root] = true;
            Deque<Frame> work = new ArrayDeque<>();
            work.push(new Frame(root));
            while (!work.isEmpty()) {
                Frame frame = work.peek(); int node = frame.node;
                if (frame.position < adjacency.get(node).size()) {
                    int child = adjacency.get(node).get(frame.position++);
                    if (order[child] < 0) {
                        order[child] = low[child] = counter++;
                        stack.push(child); onStack[child] = true; work.push(new Frame(child));
                    } else if (onStack[child]) low[node] = Math.min(low[node], order[child]);
                    continue;
                }
                work.pop();
                if (!work.isEmpty()) low[work.peek().node] = Math.min(low[work.peek().node], low[node]);
                if (low[node] == order[node]) {
                    List<Integer> group = new ArrayList<>();
                    int member;
                    do { member = stack.pop(); onStack[member] = false; group.add(member); } while (member != node);
                    groups.add(group);
                }
            }
        }
        return groups;
    }
    static boolean[] reachable(List<List<Integer>> adjacency, List<Integer> starts) {
        boolean[] seen = new boolean[adjacency.size()];
        Deque<Integer> stack = new ArrayDeque<>();
        for (int start : starts) if (!seen[start]) { seen[start] = true; stack.push(start); }
        while (!stack.isEmpty()) for (int neighbor : adjacency.get(stack.pop())) if (!seen[neighbor]) { seen[neighbor] = true; stack.push(neighbor); }
        return seen;
    }
    static int[] distances(List<List<Integer>> adjacency, List<Integer> starts) {
        int[] distance = new int[adjacency.size()]; Arrays.fill(distance, -1);
        Deque<Integer> queue = new ArrayDeque<>();
        for (int start : starts) if (distance[start] < 0) { distance[start] = 0; queue.addLast(start); }
        while (!queue.isEmpty()) {
            int node = queue.removeFirst();
            for (int neighbor : adjacency.get(node)) if (distance[neighbor] < 0) { distance[neighbor] = distance[node] + 1; queue.addLast(neighbor); }
        }
        return distance;
    }
    static int[] weak(List<List<Integer>> neighbors) {
        int[] labels = new int[neighbors.size()]; Arrays.fill(labels, -1);
        int count = 0;
        for (int start = 0; start < labels.length; start++) {
            if (labels[start] >= 0) continue;
            labels[start] = count;
            Deque<Integer> stack = new ArrayDeque<>(); stack.push(start);
            while (!stack.isEmpty()) for (int neighbor : neighbors.get(stack.pop())) if (labels[neighbor] < 0) { labels[neighbor] = count; stack.push(neighbor); }
            count++;
        }
        return labels;
    }
}
