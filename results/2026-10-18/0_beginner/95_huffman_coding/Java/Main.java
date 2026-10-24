import java.util.Comparator;
import java.util.HashMap;
import java.util.Map;
import java.util.PriorityQueue;
import java.util.TreeMap;

public class Main {
    record Node(int weight, int minimum, Character symbol, Node left, Node right) {}
    static void codes(Node node, String prefix, Map<Character,String> result) {
        if (node.symbol != null) result.put(node.symbol,prefix);
        else {
            codes(node.left,prefix + "0",result);
            codes(node.right,prefix + "1",result);
        }
    }
    public static void main(String[] args) {
        String text = "she sells sea shells by the sea shore";
        Map<Character,Integer> frequencies = new TreeMap<>();
        for (char ch : text.toCharArray()) frequencies.merge(ch,1,Integer::sum);
        PriorityQueue<Node> queue = new PriorityQueue<>(Comparator.comparingInt((Node n) -> n.weight)
            .thenComparingInt(n -> n.minimum));
        for (var entry : frequencies.entrySet()) queue.add(new Node(entry.getValue(),entry.getKey(),entry.getKey(),null,null));
        while (queue.size() > 1) {
            Node left = queue.remove(), right = queue.remove();
            queue.add(new Node(left.weight + right.weight,Math.min(left.minimum,right.minimum),null,left,right));
        }
        Map<Character,String> codes = new HashMap<>();
        codes(queue.remove(),"",codes);
        for (var entry : frequencies.entrySet()) {
            char ch = entry.getKey();
            String code = codes.get(ch);
            System.out.println("'" + ch + "' freq=" + entry.getValue() + " code=" + code);
        }
        System.out.println("encoded bits: " + frequencies.entrySet().stream().mapToInt(entry -> entry.getValue() * codes.get(entry.getKey()).length()).sum());
        System.out.println("fixed 8-bit: " + text.length() * 8);
    }
}
