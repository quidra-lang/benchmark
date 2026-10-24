type TreeNode = { key: number; left: TreeNode | null; right: TreeNode | null };

function insert(node: TreeNode | null, key: number): TreeNode {
  if (node === null) return {key, left: null, right: null};
  if (key < node.key) node.left = insert(node.left, key);
  else node.right = insert(node.right, key);
  return node;
}
function remove(node: TreeNode, key: number): TreeNode | null {
  if (key < node.key) node.left = remove(node.left!, key);
  else if (key > node.key) node.right = remove(node.right!, key);
  else {
    if (node.left === null) return node.right;
    if (node.right === null) return node.left;
    let successor = node.right;
    while (successor.left !== null) successor = successor.left;
    node.key = successor.key;
    node.right = remove(node.right, successor.key);
  }
  return node;
}
function traverse(node: TreeNode | null, order: string): number[] {
  if (node === null) return [];
  const left = traverse(node.left, order), right = traverse(node.right, order);
  if (order === "inorder") return [...left, node.key, ...right];
  if (order === "preorder") return [node.key, ...left, ...right];
  return [...left, ...right, node.key];
}
function height(node: TreeNode | null): number {
  return node === null ? 0 : 1 + Math.max(height(node.left), height(node.right));
}
let root: TreeNode | null = null;
for (const key of [50, 27, 74, 13, 39, 62, 88, 6, 31, 45, 70, 34]) root = insert(root, key);
for (const order of ["inorder", "preorder", "postorder"]) {
  console.log(`${order}: ${traverse(root, order).join(" ")}`);
}
const queue: TreeNode[] = [root!], levelorder: number[] = [];
for (let head = 0; head < queue.length; head++) {
  const node = queue[head];
  levelorder.push(node.key);
  if (node.left !== null) queue.push(node.left);
  if (node.right !== null) queue.push(node.right);
}
console.log(`levelorder: ${levelorder.join(" ")}`);
console.log(`height: ${height(root)}`);
root = remove(root!, 6);
root = remove(root!, 27);
console.log(`preorder after deletions: ${traverse(root, "preorder").join(" ")}`);
console.log(`height after deletions: ${height(root)}`);
