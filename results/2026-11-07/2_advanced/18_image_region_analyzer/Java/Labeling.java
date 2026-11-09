import java.util.ArrayList;
import java.util.List;

record LabelResult(int[][] labels, int count, int provisional) {}
final class Labeling {
    static List<Pixel> previous(int connectivity) {
        return connectivity == 4 ? List.of(new Pixel(-1, 0), new Pixel(0, -1)) : List.of(new Pixel(-1, 0), new Pixel(-1, -1), new Pixel(0, -1), new Pixel(1, -1));
    }
    static int find(List<Integer> parents, int label) {
        while (parents.get(label) != label) { parents.set(label, parents.get(parents.get(label))); label = parents.get(label); }
        return label;
    }
    static void union(List<Integer> parents, int first, int second) {
        int a = find(parents, first), b = find(parents, second);
        if (a != b) parents.set(Math.max(a, b), Math.min(a, b));
    }
    static LabelResult label(boolean[][] mask, int connectivity) {
        int height = mask.length, width = mask[0].length;
        int[][] provisional = new int[height][width];
        List<Integer> parents = new ArrayList<>(List.of(0));
        for (int y = 0; y < height; y++) for (int x = 0; x < width; x++) {
            if (!mask[y][x]) continue;
            List<Integer> neighbors = new ArrayList<>();
            for (Pixel offset : previous(connectivity)) {
                int nx = x + offset.x(), ny = y + offset.y();
                if (nx >= 0 && nx < width && ny >= 0 && mask[ny][nx]) neighbors.add(provisional[ny][nx]);
            }
            if (neighbors.isEmpty()) { provisional[y][x] = parents.size(); parents.add(parents.size()); }
            else { provisional[y][x] = neighbors.getFirst(); for (int other : neighbors.subList(1, neighbors.size())) union(parents, neighbors.getFirst(), other); }
        }
        int[] numbers = new int[parents.size()]; int[][] labels = new int[height][width]; int count = 0;
        for (int y = 0; y < height; y++) for (int x = 0; x < width; x++) {
            if (provisional[y][x] == 0) continue;
            int root = find(parents, provisional[y][x]);
            if (numbers[root] == 0) numbers[root] = ++count;
            labels[y][x] = numbers[root];
        }
        return new LabelResult(labels, count, parents.size() - 1);
    }
    static int bitQuad(boolean[][] mask, int connectivity) {
        int singles = 0, triples = 0, diagonals = 0;
        for (int y = -1; y < mask.length; y++) for (int x = -1; x < mask[0].length; x++) {
            boolean a = Morphology.occupied(mask, x, y), b = Morphology.occupied(mask, x + 1, y), c = Morphology.occupied(mask, x, y + 1), d = Morphology.occupied(mask, x + 1, y + 1);
            int count = (a ? 1 : 0) + (b ? 1 : 0) + (c ? 1 : 0) + (d ? 1 : 0);
            if (count == 1) singles++; else if (count == 3) triples++; else if (count == 2 && (a && d || b && c)) diagonals++;
        }
        return (singles - triples + (connectivity == 8 ? -2 : 2) * diagonals) / 4;
    }
}
