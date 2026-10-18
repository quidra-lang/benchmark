class Node(var key: Int, var left: Node? = null, var right: Node? = null)
fun insert(node: Node?, key: Int): Node {
    if (node == null) return Node(key)
    if (key < node.key) node.left = insert(node.left,key) else node.right = insert(node.right,key)
    return node
}
fun delete(node: Node?, key: Int): Node? {
    if (node == null) return null
    if (key < node.key) node.left = delete(node.left,key)
    else if (key > node.key) node.right = delete(node.right,key)
    else {
        if (node.left == null) return node.right
        if (node.right == null) return node.left
        var successor = node.right!!
        while (successor.left != null) successor = successor.left!!
        node.key = successor.key
        node.right = delete(node.right,successor.key)
    }
    return node
}
fun traverse(node: Node?, mode: Int, order: MutableList<Int>) {
    if (node == null) return
    if (mode == 1) order.add(node.key)
    traverse(node.left,mode,order)
    if (mode == 0) order.add(node.key)
    traverse(node.right,mode,order)
    if (mode == 2) order.add(node.key)
}
fun height(node: Node?): Int = if (node == null) 0 else 1 + maxOf(height(node.left),height(node.right))
fun main() {
    var root: Node? = null
    for (key in intArrayOf(50,27,74,13,39,62,88,6,31,45,70,34)) root = insert(root,key)
    val labels = listOf("inorder", "preorder", "postorder")
    for (mode in 0 until 3) {
        val order = mutableListOf<Int>()
        traverse(root,mode,order)
        println("${labels[mode]}: ${order.joinToString(" ")}")
    }
    val queue = ArrayDeque<Node>()
    val level = mutableListOf<Int>()
    queue.addLast(root!!)
    while (queue.isNotEmpty()) {
        val node = queue.removeFirst()
        level.add(node.key)
        node.left?.let { queue.addLast(it) }
        node.right?.let { queue.addLast(it) }
    }
    println("levelorder: ${level.joinToString(" ")}")
    println("height: ${height(root)}")
    root = delete(root,6)
    root = delete(root,27)
    val after = mutableListOf<Int>()
    traverse(root,1,after)
    println("preorder after deletions: ${after.joinToString(" ")}")
    println("height after deletions: ${height(root)}")
}
