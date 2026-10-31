import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;

record Split(Attribute attribute, int point) {
    boolean goesLeft(int value) { return attribute.integer() ? 2 * value <= point : value == point; }
    static String halfText(int value) { return value / 2 + "." + (5 * (value % 2)); }
    String condition(boolean left) {
        return attribute.name() + (attribute.integer() ? (left ? " <= " : " > ") + halfText(point)
            : (left ? " = " : " != ") + attribute.values().get(point));
    }
}

record Surrogate(Split split, boolean left, int score) {
    boolean goesLeft(int value) { return split.goesLeft(value) == left; }
}

record Candidate(Split split, int[] leftCounts, int[] rightCounts) {
    int leftSize() { return Arrays.stream(leftCounts).sum(); }
    int rightSize() { return Arrays.stream(rightCounts).sum(); }
    Fraction quality() { return Impurity.quality(leftCounts, rightCounts); }
}

final class Node {
    final int number, depth, size, prediction, errors;
    final int[] counts;
    Split split;
    List<Surrogate> surrogates = List.of();
    boolean defaultLeft;
    Node left, right;

    Node(int number, int depth, int[] counts) {
        this.number = number;
        this.depth = depth;
        this.counts = counts;
        size = Arrays.stream(counts).sum();
        prediction = Impurity.majority(counts);
        errors = Impurity.errors(counts);
    }
}

final class TreeBuilder {
    final List<Attribute> attributes;
    final int classes;
    final Settings settings;

    TreeBuilder(List<Attribute> attributes, int classes, Settings settings) {
        this.attributes = attributes;
        this.classes = classes;
        this.settings = settings;
    }

    List<Candidate> candidates(Attribute attribute, List<Row> rows, List<Integer> labels, int classCount) {
        Map<Integer, int[]> groups = new TreeMap<>();
        int[] total = new int[classCount];
        for (int i = 0; i < rows.size(); i++) {
            groups.computeIfAbsent(rows.get(i).value(attribute), ignored -> new int[classCount])[labels.get(i)]++;
            total[labels.get(i)]++;
        }
        List<Candidate> found = new ArrayList<>();
        if (groups.size() < 2) return found;
        List<Integer> values = new ArrayList<>(groups.keySet());
        if (attribute.integer()) {
            int[] left = new int[classCount];
            for (int i = 0; i + 1 < values.size(); i++) {
                for (int k = 0; k < classCount; k++) left[k] += groups.get(values.get(i))[k];
                int[] right = new int[classCount];
                for (int k = 0; k < classCount; k++) right[k] = total[k] - left[k];
                found.add(new Candidate(new Split(attribute, values.get(i) + values.get(i + 1)), left.clone(), right));
            }
        } else {
            for (int value : values) {
                int[] left = groups.get(value), right = new int[classCount];
                for (int k = 0; k < classCount; k++) right[k] = total[k] - left[k];
                found.add(new Candidate(new Split(attribute, value), left, right));
            }
        }
        return found;
    }

    Candidate bestSplit(List<Row> rows, List<Attribute> considered) {
        Candidate best = null;
        List<Integer> labels = rows.stream().map(Row::label).toList();
        for (Attribute attribute : considered)
            for (Candidate candidate : candidates(attribute, rows, labels, classes))
                if (candidate.leftSize() >= settings.minLeaf() && candidate.rightSize() >= settings.minLeaf()
                    && (best == null || candidate.quality().compareTo(best.quality()) > 0)) best = candidate;
        return best;
    }

    List<Surrogate> findSurrogates(List<Row> rows, Split primary) {
        List<Integer> directions = rows.stream().map(row -> primary.goesLeft(row.value(primary.attribute())) ? 0 : 1).toList();
        int leftSize = (int) directions.stream().filter(value -> value == 0).count();
        int baseline = Math.max(leftSize, rows.size() - leftSize);
        List<Surrogate> found = new ArrayList<>();
        for (Attribute attribute : attributes) {
            if (attribute.index() == primary.attribute().index()) continue;
            Surrogate best = null;
            for (Candidate candidate : candidates(attribute, rows, directions, 2)) {
                int agreement = candidate.leftCounts()[0] + candidate.rightCounts()[1];
                Surrogate surrogate = new Surrogate(candidate.split(), agreement >= rows.size() - agreement,
                    Math.max(agreement, rows.size() - agreement));
                if (best == null || surrogate.score() > best.score()) best = surrogate;
            }
            if (best != null && best.score() > baseline) found.add(best);
        }
        return found.stream().sorted(Comparator.comparingInt(Surrogate::score).reversed()
            .thenComparingInt(surrogate -> surrogate.split().attribute().index())).limit(settings.maxSurrogates()).toList();
    }

    Node grow(List<Row> rows) { return growNode(rows, 1, 0); }

    Node growNode(List<Row> rows, int number, int depth) {
        Node node = new Node(number, depth, Impurity.counts(rows, classes));
        if (node.errors == 0 || depth == settings.maxDepth() || node.size < settings.minSplit()) return node;
        Candidate best = bestSplit(rows, attributes);
        if (best == null || !Impurity.improves(best.quality(), node.counts)) return node;
        Split split = best.split();
        List<Row> left = rows.stream().filter(row -> split.goesLeft(row.value(split.attribute()))).toList();
        List<Row> right = rows.stream().filter(row -> !split.goesLeft(row.value(split.attribute()))).toList();
        node.split = split;
        node.surrogates = findSurrogates(rows, split);
        node.defaultLeft = left.size() >= right.size();
        node.left = growNode(left, 2 * number, depth + 1);
        node.right = growNode(right, 2 * number + 1, depth + 1);
        return node;
    }
}
