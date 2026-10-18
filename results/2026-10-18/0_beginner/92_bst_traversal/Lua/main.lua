local function insert_node(node,value)
    if not node then return {value=value} end
    if value < node.value then node.left = insert_node(node.left,value)
    else node.right = insert_node(node.right,value) end
    return node
end
local function delete_node(node,value)
    if not node then return nil end
    if value < node.value then node.left = delete_node(node.left,value)
    elseif value > node.value then node.right = delete_node(node.right,value)
    elseif not node.left then return node.right
    elseif not node.right then return node.left
    else
        local successor = node.right
        while successor.left do successor = successor.left end
        node.value = successor.value
        node.right = delete_node(node.right,successor.value)
    end
    return node
end
local function traversal(node,mode,result)
    if not node then return end
    if mode == "preorder" then result[#result+1] = node.value end
    traversal(node.left,mode,result)
    if mode == "inorder" then result[#result+1] = node.value end
    traversal(node.right,mode,result)
    if mode == "postorder" then result[#result+1] = node.value end
end
local function height(node)
    if not node then return 0 end
    return 1+math.max(height(node.left),height(node.right))
end
local tree
for _,value in ipairs({50,27,74,13,39,62,88,6,31,45,70,34}) do tree = insert_node(tree,value) end
for _,mode in ipairs({"inorder","preorder","postorder"}) do
    local result = {}
    traversal(tree,mode,result)
    io.write(mode,": ",table.concat(result," "),"\n")
end
local queue,levelorder,head = {tree},{},1
while head <= #queue do
    local node = queue[head]
    head = head+1
    levelorder[#levelorder+1] = node.value
    if node.left then queue[#queue+1] = node.left end
    if node.right then queue[#queue+1] = node.right end
end
io.write(string.format("levelorder: %s\nheight: %d\n",table.concat(levelorder," "),height(tree)))
tree = delete_node(tree,6)
tree = delete_node(tree,27)
local result = {}
traversal(tree,"preorder",result)
io.write(string.format("preorder after deletions: %s\nheight after deletions: %d\n",table.concat(result," "),height(tree)))
