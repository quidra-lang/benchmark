import java.util.*;
import java.math.*;

public class Main {
    static class Node {
        int key;
        Node left, right;
        Node(int key) { this.key = key; }
    }
    static Node insert(Node node, int key) {
        if (node == null) return new Node(key);
        if (key < node.key) node.left = insert(node.left,key);
        else node.right = insert(node.right,key);
        return node;
    }
    static Node delete(Node node, int key) {
        if (node == null) return null;
        if (key < node.key) node.left = delete(node.left,key);
        else if (key > node.key) node.right = delete(node.right,key);
        else {
            if (node.left == null) return node.right;
            if (node.right == null) return node.left;
            Node successor = node.right;
            while (successor.left != null) successor = successor.left;
            node.key = successor.key;
            node.right = delete(node.right,successor.key);
        }
        return node;
    }
    static void traverse(Node node, int mode, List<Integer> order) {
        if (node == null) return;
        if (mode == 1) order.add(node.key);
        traverse(node.left,mode,order);
        if (mode == 0) order.add(node.key);
        traverse(node.right,mode,order);
        if (mode == 2) order.add(node.key);
    }
    static int height(Node node) {
        return node == null ? 0 : 1 + Math.max(height(node.left),height(node.right));
    }
    static String joined(List<Integer> values) {
        return String.join(" ",values.stream().map(String::valueOf).toList());
    }
    public static void main(String[] args) {
        Node root = null;
        for (int key : new int[]{50,27,74,13,39,62,88,6,31,45,70,34}) root = insert(root,key);
        String[] labels = {"inorder", "preorder", "postorder"};
        for (int mode = 0; mode < 3; mode++) {
            List<Integer> order = new ArrayList<>();
            traverse(root,mode,order);
            System.out.println(labels[mode] + ": " + joined(order));
        }
        Deque<Node> queue = new ArrayDeque<>();
        List<Integer> level = new ArrayList<>();
        queue.add(root);
        while (!queue.isEmpty()) {
            Node node = queue.remove();
            level.add(node.key);
            if (node.left != null) queue.add(node.left);
            if (node.right != null) queue.add(node.right);
        }
        System.out.println("levelorder: " + joined(level));
        System.out.println("height: " + height(root));
        root = delete(root,6);
        root = delete(root,27);
        List<Integer> after = new ArrayList<>();
        traverse(root,1,after);
        System.out.println("preorder after deletions: " + joined(after));
        System.out.println("height after deletions: " + height(root));
    }
}
