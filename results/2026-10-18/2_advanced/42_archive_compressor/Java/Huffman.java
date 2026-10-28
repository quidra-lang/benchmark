import java.util.*;

final class Huffman {
    static final class Node {
        int weight, minimum, symbol;
        Node left, right;
        Node(int weight, int minimum, int symbol, Node left, Node right) {
            this.weight = weight;
            this.minimum = minimum;
            this.symbol = symbol;
            this.left = left;
            this.right = right;
        }
    }
    static void depths(Node n, int depth, int[] lengths) {
        if (n.symbol >= 0) {
            lengths[n.symbol] = Math.max(1, depth);
            return;
        }
        depths(n.left, depth + 1, lengths);
        depths(n.right, depth + 1, lengths);
    }
    static int[] lengths(int[] frequencies) {
        int[] result = new int[frequencies.length];
        PriorityQueue<Node> nodes =
            new PriorityQueue<>((a, b)
                                    -> a.weight != b.weight ? Integer.compare(a.weight, b.weight)
                                                            : Integer.compare(a.minimum, b.minimum));
        for (int i = 0; i < frequencies.length; i++)
            if (frequencies[i] > 0)
                nodes.add(new Node(frequencies[i], i, i, null, null));
        if (nodes.isEmpty())
            return result;
        while (nodes.size() > 1) {
            Node a = nodes.remove(), b = nodes.remove();
            nodes.add(new Node(a.weight + b.weight, Math.min(a.minimum, b.minimum), -1, a, b));
        }
        depths(nodes.remove(), 0, result);
        return result;
    }
    record Limited(int[] lengths, int halvings) {}
    static Limited limited(int[] frequencies, int maximum) {
        int[] current = frequencies.clone();
        int halves = 0;
        while (true) {
            int[] lengths = lengths(current);
            int largest = 0;
            for (int value : lengths)
                largest = Math.max(largest, value);
            if (largest <= maximum)
                return new Limited(lengths, halves);
            for (int i = 0; i < current.length; i++)
                current[i] = (current[i] + 1) / 2;
            halves++;
        }
    }
    static int[] canonical(int[] lengths) {
        List<Integer> order = new ArrayList<>();
        for (int i = 0; i < lengths.length; i++)
            if (lengths[i] > 0)
                order.add(i);
        order.sort((a, b)
                       -> lengths[a] != lengths[b] ? Integer.compare(lengths[a], lengths[b])
                                                   : Integer.compare(a, b));
        int[] codes = new int[lengths.length];
        int code = 0, previous = 0;
        for (int symbol : order) {
            code <<= lengths[symbol] - previous;
            codes[symbol] = code;
            code++;
            previous = lengths[symbol];
        }
        return codes;
    }
}
