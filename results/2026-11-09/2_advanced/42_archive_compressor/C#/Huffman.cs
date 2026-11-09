using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Huffman {
    public static Node Take(SortedSet<Node> nodes) {
        Node n = nodes.Min;
        nodes.Remove(n);
        return n;
    }
    public sealed class Node {

        public int weight, minimum, symbol;
        public Node left, right;
        public Node(int weight, int minimum, int symbol, Node left, Node right) {
            this.weight = weight;
            this.minimum = minimum;
            this.symbol = symbol;
            this.left = left;
            this.right = right;
        }
    }
    public static void Depths(Node n, int depth, int[] lengths) {
        if (n.symbol >= 0) {
            lengths[n.symbol] = Math.Max(1, depth);
            return;
        }
        Depths(n.left, depth + 1, lengths);
        Depths(n.right, depth + 1, lengths);
    }
    public static int[] Lengths(int[] frequencies) {
        int[] result = new int[frequencies.Length];
        SortedSet<Node> nodes = new SortedSet<Node>(Comparer<Node>.Create(
            (a, b) => a.weight != b.weight ? a.weight.CompareTo(b.weight) : a.minimum.CompareTo(b.minimum)));
        for (int i = 0; i < frequencies.Length; i++)
            if (frequencies[i] > 0)
                nodes.Add(new Node(frequencies[i], i, i, null, null));
        if (nodes.Count == 0)
            return result;
        while (nodes.Count > 1) {
            Node a = Take(nodes), b = Take(nodes);
            nodes.Add(new Node(a.weight + b.weight, Math.Min(a.minimum, b.minimum), -1, a, b));
        }
        Depths(Take(nodes), 0, result);
        return result;
    }
    public record Limited(int[] lengths, int halvings) {
    }
    public static Limited LimitLengths(int[] frequencies, int maximum) {
        int[] current = frequencies.ToArray();
        int halves = 0;
        while (true) {
            int[] lengths = Lengths(current);
            int largest = 0;
            foreach (int value in lengths)
                largest = Math.Max(largest, value);
            if (largest <= maximum)
                return new Limited(lengths, halves);
            for (int i = 0; i < current.Length; i++)
                current[i] = (current[i] + 1) / 2;
            halves++;
        }
    }
    public static int[] Canonical(int[] lengths) {
        List<int> order = new();
        for (int i = 0; i < lengths.Length; i++)
            if (lengths[i] > 0)
                order.Add(i);
        order.Sort((a, b) => lengths[a] != lengths[b] ? lengths[a].CompareTo(lengths[b]) : a.CompareTo(b));
        int[] codes = new int[lengths.Length];
        int code = 0, previous = 0;
        foreach (int symbol in order) {
            code <<= lengths[symbol] - previous;
            codes[symbol] = code;
            code++;
            previous = lengths[symbol];
        }
        return codes;
    }
}
