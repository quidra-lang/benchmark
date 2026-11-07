class Node:
    def __init__(self, key):
        self.key = key
        self.left = None
        self.right = None


def insert(node, key):
    if node is None:
        return Node(key)
    if key < node.key:
        node.left = insert(node.left, key)
    else:
        node.right = insert(node.right, key)
    return node


def delete(node, key):
    if key < node.key:
        node.left = delete(node.left, key)
    elif key > node.key:
        node.right = delete(node.right, key)
    else:
        if node.left is None:
            return node.right
        if node.right is None:
            return node.left
        successor = node.right
        while successor.left is not None:
            successor = successor.left
        node.key = successor.key
        node.right = delete(node.right, successor.key)
    return node


def traverse(node, order):
    if node is None:
        return []
    left, right = traverse(node.left, order), traverse(node.right, order)
    if order == "inorder":
        return left + [node.key] + right
    if order == "preorder":
        return [node.key] + left + right
    return left + right + [node.key]


def height(node):
    return 0 if node is None else 1 + max(height(node.left), height(node.right))


root = None
for key in [50, 27, 74, 13, 39, 62, 88, 6, 31, 45, 70, 34]:
    root = insert(root, key)
for order in ["inorder", "preorder", "postorder"]:
    print(f"{order}:", *traverse(root, order))
queue = [root]
levelorder = []
while queue:
    node = queue.pop(0)
    levelorder.append(node.key)
    if node.left is not None:
        queue.append(node.left)
    if node.right is not None:
        queue.append(node.right)
print("levelorder:", *levelorder)
print(f"height: {height(root)}")
root = delete(root, 6)
root = delete(root, 27)
print("preorder after deletions:", *traverse(root, "preorder"))
print(f"height after deletions: {height(root)}")
