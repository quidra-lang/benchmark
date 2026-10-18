import 'dart:io';
import 'dart:math' as math;

class Node {
    int key;
    Node? left, right;
    Node(this.key);
}

Node insert(Node? node, int key) {
    if (node == null)
        return Node(key);
    if (key < node.key)
        node.left = insert(node.left, key);
    else node.right = insert(node.right, key);
    return node;
}

int height(Node? node) => node == null ? 0 : 1 + math.max(height(node.left), height(node.right));
Node? remove(Node? node, int key) {
    if (node == null)
        return null;
    if (key < node.key)
        node.left = remove(node.left, key);
    else if (key > node.key) node.right = remove(node.right, key);
    else {
        if (node.left == null)
            return node.right;
        if (node.right == null)
            return node.left;
        var successor = node.right!;
        while (successor.left != null)
            successor = successor.left!;
        node.key = successor.key;
        node.right = remove(node.right, successor.key);
    }
    return node;
}

void main() {
    final out = StringBuffer();
    Node? root;
    for (final key in [50, 27, 74, 13, 39, 62, 88, 6, 31, 45, 70, 34]) {
        root = insert(root, key);
    }
    List<int> traverse(Node? node, int mode) {
        if (node == null)
            return [];
        return [...(mode == 1 ? [node.key] : <int>[]),...traverse(node.left, mode),...(mode == 0 ? [node.key] : <int>[]),
            ...traverse(node.right, mode),...(mode == 2 ? [node.key] : <int>[])];
    }
    for (var mode = 0; mode < 3; mode++)
        out.writeln('${['inorder','preorder','postorder'][mode]}: ${traverse(root,mode).join(' ')}');
    final queue = [root!], level = <int>[];
    for (var h = 0; h < queue.length; h++) {
        final node = queue[h];
        level.add(node.key);
        if (node.left != null)
            queue.add(node.left!);
        if (node.right != null)
            queue.add(node.right!);
    }
    out.writeln('levelorder: ${level.join(' ')}\nheight: ${height(root)}');
    root = remove(root, 6);
    root = remove(root, 27);
    out.writeln('preorder after deletions: ${traverse(root,1).join(' ')}\nheight after deletions: ${height(root)}');
    stdout.write(out);
}
