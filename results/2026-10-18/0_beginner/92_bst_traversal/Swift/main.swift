class Node {
    var key: Int
    var left: Node?, right: Node?
    init(_ key: Int) { self.key = key }
}

func insert(_ node: Node?, _ key: Int) -> Node {
    guard let node else { return Node(key) }
    if key < node.key {
        node.left = insert(node.left, key)
    } else {
        node.right = insert(node.right, key)
    }
    return node
}

func delete(_ node: Node?, _ key: Int) -> Node? {
    guard let node else { return nil }
    if key < node.key {
        node.left = delete(node.left, key)
    } else if key > node.key {
        node.right = delete(node.right, key)
    } else {
        if node.left == nil { return node.right }
        if node.right == nil { return node.left }
        var successor = node.right!
        while let left = successor.left { successor = left }
        node.key = successor.key
        node.right = delete(node.right, successor.key)
    }
    return node
}

func traverse(_ node: Node?, _ mode: Int, _ order: inout [Int]) {
    guard let node else { return }
    if mode == 1 { order.append(node.key) }
    traverse(node.left, mode, &order)
    if mode == 0 { order.append(node.key) }
    traverse(node.right, mode, &order)
    if mode == 2 { order.append(node.key) }
}

func height(_ node: Node?) -> Int {
    guard let node else { return 0 }
    return 1 + max(height(node.left), height(node.right))
}

var root: Node? = nil
for key in [50, 27, 74, 13, 39, 62, 88, 6, 31, 45, 70, 34] { root = insert(root, key) }
let labels = ["inorder", "preorder", "postorder"]
for mode in 0..<3 {
    var order = [Int]()
    traverse(root, mode, &order)
    print("\(labels[mode]): \(order.map(String.init).joined(separator: " "))")
}
var queue = [root!], head = 0, level = [Int]()
while head < queue.count {
    let node = queue[head]
    head += 1
    level.append(node.key)
    if let left = node.left { queue.append(left) }
    if let right = node.right { queue.append(right) }
}
print("levelorder: \(level.map(String.init).joined(separator: " "))")
print("height: \(height(root))")
root = delete(root, 6)
root = delete(root, 27)
var after = [Int]()
traverse(root, 1, &after)
print("preorder after deletions: \(after.map(String.init).joined(separator: " "))")
print("height after deletions: \(height(root))")
