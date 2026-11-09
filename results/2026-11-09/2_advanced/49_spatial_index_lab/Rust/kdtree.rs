use crate::dataset::Point;

pub struct Node {
    pub point: Point,
    pub depth: usize,
    pub left: Option<Box<Node>>,
    pub right: Option<Box<Node>>,
}

pub fn key(point: Point, axis: usize) -> (i64, i64, i64) {
    if axis == 0 { (point.x, point.y, point.id) } else { (point.y, point.x, point.id) }
}

pub fn build(points: &[Point], depth: usize) -> Option<Box<Node>> {
    if points.is_empty() { return None; }
    let mut sorted = points.to_vec();
    sorted.sort_by_key(|&p| key(p, depth % 2));
    let middle = sorted.len() / 2;
    Some(Box::new(Node { point: sorted[middle], depth, left: build(&sorted[..middle], depth + 1), right: build(&sorted[middle + 1..], depth + 1) }))
}

pub fn insert(root: &mut Option<Box<Node>>, point: Point, depth: usize) {
    match root {
        None => *root = Some(Box::new(Node { point, depth, left: None, right: None })),
        Some(node) => {
            if key(point, node.depth % 2) < key(node.point, node.depth % 2) { insert(&mut node.left, point, depth + 1); }
            else { insert(&mut node.right, point, depth + 1); }
        }
    }
}

pub fn minimum(node: &Node, axis: usize) -> Point {
    if node.depth % 2 == axis {
        node.left.as_ref().map_or(node.point, |left| minimum(left, axis))
    } else {
        let mut result = node.point;
        for child in [&node.left, &node.right] {
            if let Some(child) = child {
                let candidate = minimum(child, axis);
                if key(candidate, axis) < key(result, axis) { result = candidate; }
            }
        }
        result
    }
}

pub fn delete(root: Option<Box<Node>>, point: Point) -> Option<Box<Node>> {
    let mut node = root.unwrap();
    let axis = node.depth % 2;
    if node.point.id == point.id {
        if let Some(right) = &node.right {
            let next = minimum(right, axis);
            node.point = next;
            node.right = delete(node.right.take(), next);
        } else if let Some(left) = &node.left {
            let next = minimum(left, axis);
            node.point = next;
            node.right = delete(node.left.take(), next);
        } else { return None; }
    } else if key(point, axis) < key(node.point, axis) {
        node.left = delete(node.left.take(), point);
    } else {
        node.right = delete(node.right.take(), point);
    }
    Some(node)
}
