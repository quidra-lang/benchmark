#include <iostream>
#include <string>
#include <vector>
#include <array>
#include <algorithm>

struct Node {
    int key, left = -1, right = -1;
};

std::vector<Node> nodes;

int insert(int root, int key) {
    if (root < 0) {
        nodes.push_back({key});
        return static_cast<int>(nodes.size()) - 1;
    }
    if (key < nodes[root].key) {
        int child = insert(nodes[root].left, key);
        nodes[root].left = child;
    } else {
        int child = insert(nodes[root].right, key);
        nodes[root].right = child;
    }
    return root;
}

void traverse(int root, int mode) {
    if (root < 0)
        return;
    if (mode == 1)
        std::cout << ' ' << nodes[root].key;
    traverse(nodes[root].left, mode);
    if (mode == 0)
        std::cout << ' ' << nodes[root].key;
    traverse(nodes[root].right, mode);
    if (mode == 2)
        std::cout << ' ' << nodes[root].key;
}

int height(int root) {
    return root < 0 ? 0 : 1 + std::max(height(nodes[root].left), height(nodes[root].right));
}

int erase(int root, int key) {
    if (root < 0)
        return root;
    if (key < nodes[root].key) {
        nodes[root].left = erase(nodes[root].left, key);
    } else if (key > nodes[root].key) {
        nodes[root].right = erase(nodes[root].right, key);
    } else {
        if (nodes[root].left < 0)
            return nodes[root].right;
        if (nodes[root].right < 0)
            return nodes[root].left;
        int successor = nodes[root].right;
        while (nodes[successor].left >= 0)
            successor = nodes[successor].left;
        nodes[root].key = nodes[successor].key;
        nodes[root].right = erase(nodes[root].right, nodes[successor].key);
    }
    return root;
}

int main() {
    int root = -1;
    for (int key : std::array<int, 12>{50, 27, 74, 13, 39, 62, 88, 6, 31, 45, 70, 34})
        root = insert(root, key);
    std::array<std::string, 3> labels = {"inorder", "preorder", "postorder"};
    for (int mode = 0; mode < 3; mode++) {
        std::cout << labels[mode] << ':';
        traverse(root, mode);
        std::cout << '\n';
    }
    std::vector<int> queue = {root};
    std::cout << "levelorder:";
    for (std::size_t head = 0; head < queue.size(); head++) {
        int v = queue[head];
        std::cout << ' ' << nodes[v].key;
        if (nodes[v].left >= 0)
            queue.push_back(nodes[v].left);
        if (nodes[v].right >= 0)
            queue.push_back(nodes[v].right);
    }
    std::cout << "\nheight: " << height(root) << '\n';
    root = erase(root, 6);
    root = erase(root, 27);
    std::cout << "preorder after deletions:";
    traverse(root, 1);
    std::cout << "\nheight after deletions: " << height(root) << '\n';
}
