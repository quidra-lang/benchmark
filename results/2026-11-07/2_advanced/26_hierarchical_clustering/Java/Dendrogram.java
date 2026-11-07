import java.util.*;

final class Dendrogram {
    static int[][] children(List<Agglomerative.Merge> merges, int count) {
        int[] minimum = new int[2 * count - 1]; for (int u = 0; u < count; u++) minimum[u] = u;
        int[][] children = new int[merges.size()][2];
        for (int step = 0; step < merges.size(); step++) {
            Agglomerative.Merge merge = merges.get(step);
            children[step] = minimum[merge.a()] < minimum[merge.b()] ? new int[]{merge.a(), merge.b()} : new int[]{merge.b(), merge.a()};
            minimum[count + step] = Math.min(minimum[merge.a()], minimum[merge.b()]);
        }
        return children;
    }

    static int[] leafOrder(int[][] children, int count) {
        List<Integer> order = new ArrayList<>(); Deque<Integer> pending = new ArrayDeque<>(); pending.push(count + children.length - 1);
        while (!pending.isEmpty()) {
            int node = pending.pop();
            if (node < count) order.add(node);
            else { pending.push(children[node - count][1]); pending.push(children[node - count][0]); }
        }
        return order.stream().mapToInt(Integer::intValue).toArray();
    }

    static int column(double height, double maximum, int width) {
        double position = Math.floor(height / maximum * width);
        return position > width ? width + 1 : (int) position;
    }
    static void mark(int[][] grid, int row, int column, int priority) { grid[row][column] = Math.max(grid[row][column], priority); }

    static List<String> rows(List<Agglomerative.Merge> merges, int[][] children, int[] order, String[] idents, String[] labels, double maximum, int[] cutColumns, int width) {
        int count = order.length;
        int[][] grid = new int[count][width + 1]; int[] anchor = new int[2 * count - 1];
        for (int row = 0; row < count; row++) anchor[order[row]] = row;
        for (int x : cutColumns) if (x <= width) for (int row = 0; row < count; row++) mark(grid, row, x, 1);
        int[] columns = merges.stream().mapToInt(merge -> column(merge.height(), maximum, width)).toArray();
        for (int step = 0; step < children.length; step++) {
            int upper = children[step][0], lower = children[step][1], x = columns[step];
            mark(grid, anchor[upper], x, 4); mark(grid, anchor[lower], x, 4);
            for (int row = anchor[upper] + 1; row < anchor[lower]; row++) mark(grid, row, x, 3);
            for (int child : children[step]) {
                int start = child < count ? 0 : columns[child - count] + 1;
                for (int position = start; position < x; position++) mark(grid, anchor[child], position, 2);
            }
            anchor[count + step] = (anchor[upper] + anchor[lower]) / 2;
        }
        int idWidth = Arrays.stream(idents).mapToInt(String::length).max().orElseThrow(), labelWidth = Arrays.stream(labels).mapToInt(String::length).max().orElseThrow();
        List<String> rows = new ArrayList<>();
        for (int row = 0; row < count; row++) {
            int leaf = order[row]; StringBuilder text = new StringBuilder(idents[leaf] + " ".repeat(idWidth - idents[leaf].length()) + " " + labels[leaf] + " ".repeat(labelWidth - labels[leaf].length()) + " ");
            for (int mark : grid[row]) text.append(" :-|+".charAt(mark));
            rows.add(text.toString().stripTrailing());
        }
        StringBuilder scale = new StringBuilder(" ".repeat(idWidth + labelWidth + 2));
        for (int x = 0; x <= width; x++) scale.append(x % 10 == 0 ? '+' : '-');
        rows.add(scale.toString());
        return rows;
    }
}
