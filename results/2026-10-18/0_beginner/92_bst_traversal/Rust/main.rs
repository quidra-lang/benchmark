struct Node {
    key: i32,
    left: Option<usize>,
    right: Option<usize>,
}

fn insert(nodes: &mut Vec<Node>, root: Option<usize>, key: i32) -> usize {
    let Some(v) = root else {
        nodes.push(Node {
            key,
            left: None,
            right: None,
        });
        return nodes.len() - 1;
    };
    if key < nodes[v].key {
        let left = nodes[v].left;
        let child = insert(nodes, left, key);
        nodes[v].left = Some(child);
    } else {
        let right = nodes[v].right;
        let child = insert(nodes, right, key);
        nodes[v].right = Some(child);
    }
    v
}

fn traverse(nodes: &[Node], root: Option<usize>, mode: usize) {
    if let Some(v) = root {
        if mode == 1 {
            print!(" {}", nodes[v].key);
        }
        traverse(nodes, nodes[v].left, mode);
        if mode == 0 {
            print!(" {}", nodes[v].key);
        }
        traverse(nodes, nodes[v].right, mode);
        if mode == 2 {
            print!(" {}", nodes[v].key);
        }
    }
}

fn height(nodes: &[Node], root: Option<usize>) -> usize {
    root.map_or(0, |v| {
        1 + height(nodes, nodes[v].left).max(height(nodes, nodes[v].right))
    })
}

fn erase(nodes: &mut [Node], root: Option<usize>, key: i32) -> Option<usize> {
    let v = root?;
    if key < nodes[v].key {
        let left = nodes[v].left;
        nodes[v].left = erase(nodes, left, key);
    } else if key > nodes[v].key {
        let right = nodes[v].right;
        nodes[v].right = erase(nodes, right, key);
    } else {
        if nodes[v].left.is_none() {
            return nodes[v].right;
        }
        if nodes[v].right.is_none() {
            return nodes[v].left;
        }
        let mut successor = nodes[v].right.unwrap();
        while let Some(left) = nodes[successor].left {
            successor = left;
        }
        nodes[v].key = nodes[successor].key;
        let right = nodes[v].right;
        let successor_key = nodes[successor].key;
        nodes[v].right = erase(nodes, right, successor_key);
    }
    Some(v)
}

fn main() {
    let mut nodes = Vec::new();
    let mut root = None;
    for key in [50, 27, 74, 13, 39, 62, 88, 6, 31, 45, 70, 34] {
        root = Some(insert(&mut nodes, root, key));
    }
    for (mode, label) in ["inorder", "preorder", "postorder"].iter().enumerate() {
        print!("{}:", label);
        traverse(&nodes, root, mode);
        println!();
    }
    let mut queue = std::collections::VecDeque::from([root.unwrap()]);
    print!("levelorder:");
    while let Some(v) = queue.pop_front() {
        print!(" {}", nodes[v].key);
        if let Some(child) = nodes[v].left {
            queue.push_back(child);
        }
        if let Some(child) = nodes[v].right {
            queue.push_back(child);
        }
    }
    println!("\nheight: {}", height(&nodes, root));
    root = erase(&mut nodes, root, 6);
    root = erase(&mut nodes, root, 27);
    print!("preorder after deletions:");
    traverse(&nodes, root, 1);
    println!("\nheight after deletions: {}", height(&nodes, root));
}
