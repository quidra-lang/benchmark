<?php
class TreeNode {
    public ?TreeNode $left = null;
    public ?TreeNode $right = null;
    public function __construct(public int $value) {}
}
function insertNode(?TreeNode $node, int $value): TreeNode {
    if ($node === null) return new TreeNode($value);
    if ($value < $node->value) $node->left = insertNode($node->left,$value);
    else $node->right = insertNode($node->right,$value);
    return $node;
}
function deleteNode(?TreeNode $node, int $value): ?TreeNode {
    if ($node === null) return null;
    if ($value < $node->value) $node->left = deleteNode($node->left,$value);
    elseif ($value > $node->value) $node->right = deleteNode($node->right,$value);
    elseif ($node->left === null) return $node->right;
    elseif ($node->right === null) return $node->left;
    else {
        $successor = $node->right;
        while ($successor->left !== null) $successor = $successor->left;
        $node->value = $successor->value;
        $node->right = deleteNode($node->right,$successor->value);
    }
    return $node;
}
function traversal(?TreeNode $node, string $mode): array {
    if ($node === null) return [];
    $left = traversal($node->left,$mode);
    $right = traversal($node->right,$mode);
    return match ($mode) {
        'inorder' => array_merge($left,[$node->value],$right),
        'preorder' => array_merge([$node->value],$left,$right),
        'postorder' => array_merge($left,$right,[$node->value])
    };
}
function treeHeight(?TreeNode $node): int {
    return $node === null ? 0 : 1+max(treeHeight($node->left),treeHeight($node->right));
}
$tree = null;
foreach ([50,27,74,13,39,62,88,6,31,45,70,34] as $value) $tree = insertNode($tree,$value);
foreach (['inorder','preorder','postorder'] as $mode) echo $mode, ': ', implode(' ',traversal($tree,$mode)), "\n";
$queue = [$tree]; $levelorder = []; $head = 0;
while ($head < count($queue)) {
    $node = $queue[$head++];
    $levelorder[] = $node->value;
    if ($node->left !== null) $queue[] = $node->left;
    if ($node->right !== null) $queue[] = $node->right;
}
printf("levelorder: %s\nheight: %d\n",implode(' ',$levelorder),treeHeight($tree));
$tree = deleteNode($tree,6);
$tree = deleteNode($tree,27);
printf("preorder after deletions: %s\nheight after deletions: %d\n",implode(' ',traversal($tree,'preorder')),treeHeight($tree));
