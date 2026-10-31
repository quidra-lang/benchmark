#include <stdio.h>

typedef struct {
    int key, left, right;
} Node;

Node nodes[12];
int used = 0;

int insert(int root, int key) {
    if (root < 0) {
        int v = used++;
        nodes[v] = (Node){key, -1, -1};
        return v;
    }
    if (key < nodes[root].key)
        nodes[root].left = insert(nodes[root].left, key);
    else
        nodes[root].right = insert(nodes[root].right, key);
    return root;
}

void traverse(int root, int mode) {
    if (root < 0)
        return;
    if (mode == 1)
        printf(" %d", nodes[root].key);
    traverse(nodes[root].left, mode);
    if (mode == 0)
        printf(" %d", nodes[root].key);
    traverse(nodes[root].right, mode);
    if (mode == 2)
        printf(" %d", nodes[root].key);
}

int height(int root) {
    if (root < 0)
        return 0;
    int l = height(nodes[root].left), r = height(nodes[root].right);
    return 1 + (l > r ? l : r);
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

int main(void) {
    int keys[] = {50, 27, 74, 13, 39, 62, 88, 6, 31, 45, 70, 34}, root = -1;
    for (int i = 0; i < 12; i++)
        root = insert(root, keys[i]);
    const char *labels[] = {"inorder", "preorder", "postorder"};
    for (int mode = 0; mode < 3; mode++) {
        printf("%s:", labels[mode]);
        traverse(root, mode);
        putchar('\n');
    }
    int queue[12], head = 0, tail = 0;
    queue[tail++] = root;
    printf("levelorder:");
    while (head < tail) {
        int v = queue[head++];
        printf(" %d", nodes[v].key);
        if (nodes[v].left >= 0)
            queue[tail++] = nodes[v].left;
        if (nodes[v].right >= 0)
            queue[tail++] = nodes[v].right;
    }
    printf("\nheight: %d\n", height(root));
    root = erase(root, 6);
    root = erase(root, 27);
    printf("preorder after deletions:");
    traverse(root, 1);
    printf("\nheight after deletions: %d\n", height(root));
    return 0;
}
