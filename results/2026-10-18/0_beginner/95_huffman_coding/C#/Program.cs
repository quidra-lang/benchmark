using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
static void Codes(Node node, string prefix, Dictionary<char,string> result) {
    if (node.Symbol is char ch) result[ch] = prefix;
    else {
        Codes(node.Left!,prefix + "0",result);
        Codes(node.Right!,prefix + "1",result);
    }
}
string text = "she sells sea shells by the sea shore";
var frequencies = text.GroupBy(ch => ch).ToDictionary(g => g.Key,g => g.Count());
var queue = new PriorityQueue<Node,(int weight,int minimum)>();
foreach (var pair in frequencies) {
    var leaf = new Node(pair.Value,pair.Key,pair.Key);
    queue.Enqueue(leaf,(leaf.Weight,leaf.Minimum));
}
while (queue.Count > 1) {
    Node left = queue.Dequeue(), right = queue.Dequeue();
    var parent = new Node(left.Weight + right.Weight,Math.Min(left.Minimum,right.Minimum),null,left,right);
    queue.Enqueue(parent,(parent.Weight,parent.Minimum));
}
var codes = new Dictionary<char,string>();
Codes(queue.Dequeue(),"",codes);
int bits = 0;
foreach (char ch in frequencies.Keys.Order()) {
    string code = codes[ch];
    bits += frequencies[ch] * code.Length;
    Console.WriteLine($"'{ch}' freq={frequencies[ch]} code={code}");
}
Console.WriteLine($"encoded bits: {bits}");
Console.WriteLine($"fixed 8-bit: {text.Length * 8}");
class Node {
    public int Weight, Minimum;
    public char? Symbol;
    public Node? Left, Right;
    public Node(int weight, int minimum, char? symbol, Node? left = null, Node? right = null) {
        Weight = weight;
        Minimum = minimum;
        Symbol = symbol;
        Left = left;
        Right = right;
    }
}
