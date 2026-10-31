mutable struct TreeNode
    value::Int
    left::Union{Nothing,TreeNode}
    right::Union{Nothing,TreeNode}
end

function insert_node(node, value)
    node === nothing && return TreeNode(value, nothing, nothing)
    if value < node.value
        node.left = insert_node(node.left, value)
    else
        node.right = insert_node(node.right, value)
    end
    return node
end

function delete_node(node, value)
    node === nothing && return nothing
    if value < node.value
        node.left = delete_node(node.left, value)
    elseif value > node.value
        node.right = delete_node(node.right, value)
    elseif node.left === nothing
        return node.right
    elseif node.right === nothing
        return node.left
    else
        successor = node.right
        while successor.left !== nothing
            successor = successor.left
        end
        node.value = successor.value
        node.right = delete_node(node.right, successor.value)
    end
    return node
end

function traversal(node, mode)
    node === nothing && return Int[]
    left, right = traversal(node.left, mode), traversal(node.right, mode)
    if mode == "inorder"
        return vcat(left, node.value, right)
    elseif mode == "preorder"
        return vcat(node.value, left, right)
    else
        return vcat(left, right, node.value)
    end
end

tree_height(node) =
    node === nothing ? 0 : 1+max(tree_height(node.left), tree_height(node.right))

function main()
    tree = nothing
    for value in [50, 27, 74, 13, 39, 62, 88, 6, 31, 45, 70, 34]
        tree = insert_node(tree, value)
    end
    for mode in ["inorder", "preorder", "postorder"]
        println(mode, ": ", join(traversal(tree, mode), " "))
    end
    queue, levelorder = [tree], Int[]
    head = 1
    while head <= length(queue)
        node = queue[head]
        head += 1
        push!(levelorder, node.value)
        node.left !== nothing && push!(queue, node.left)
        node.right !== nothing && push!(queue, node.right)
    end
    println("levelorder: ", join(levelorder, " "))
    println("height: ", tree_height(tree))
    tree = delete_node(tree, 6)
    tree = delete_node(tree, 27)
    println("preorder after deletions: ", join(traversal(tree, "preorder"), " "))
    println("height after deletions: ", tree_height(tree))
end

main()
