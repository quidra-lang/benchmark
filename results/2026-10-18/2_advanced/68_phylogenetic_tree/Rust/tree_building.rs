use std::collections::{BTreeMap, BTreeSet, VecDeque};

#[derive(Clone)]
pub struct Tree { pub adjacency: Vec<BTreeMap<usize, f64>>, pub taxa_count: usize, pub negative: usize }
pub struct Rooted { pub root: usize, pub parent: Vec<Option<usize>>, pub children: Vec<Vec<usize>>, pub masks: Vec<u32>, pub postorder: Vec<usize>, pub ingroup: u32 }

impl Tree {
    pub fn empty(taxa_count: usize) -> Self { Self { adjacency: vec![BTreeMap::new(); taxa_count], taxa_count, negative: 0 } }
    pub fn node(&mut self) -> usize { let node = self.adjacency.len(); self.adjacency.push(BTreeMap::new()); node }
    pub fn connect(&mut self, a: usize, b: usize, length: f64) { self.adjacency[a].insert(b, length); self.adjacency[b].insert(a, length); }
    pub fn disconnect(&mut self, a: usize, b: usize) { self.adjacency[a].remove(&b); self.adjacency[b].remove(&a); }
    pub fn leaves(&self) -> Vec<usize> { (0..self.taxa_count).filter(|&i| !self.adjacency[i].is_empty()).collect() }
    pub fn root(&self, outgroup: usize, names: &[String]) -> Rooted {
        let root = *self.adjacency[outgroup].keys().next().unwrap();
        let n = self.adjacency.len();
        let mut rooted = Rooted { root, parent: vec![None; n], children: vec![Vec::new(); n], masks: vec![0; n], postorder: Vec::new(), ingroup: 0 };
        fn visit(tree: &Tree, node: usize, parent: Option<usize>, rooted: &mut Rooted) {
            rooted.parent[node] = parent;
            if node < tree.taxa_count { rooted.masks[node] = 1<<node; }
            for &next in tree.adjacency[node].keys() {
                if Some(next) == parent { continue; }
                rooted.children[node].push(next);
                visit(tree, next, Some(node), rooted);
                let child_mask = rooted.masks[next];
                rooted.masks[node] |= child_mask;
            }
            rooted.postorder.push(node);
        }
        visit(self, root, None, &mut rooted);
        rooted.ingroup = rooted.masks[root]&!(1<<outgroup);
        let masks = &rooted.masks;
        for children in &mut rooted.children {
            children.sort_by_key(|&child| (0..names.len()).filter(|&i| masks[child]&(1<<i) != 0).map(|i| names[i].clone()).min().unwrap());
        }
        rooted.masks[root] = rooted.ingroup;
        rooted
    }
    pub fn splits(&self, outgroup: usize, names: &[String]) -> BTreeSet<u32> {
        let rooted = self.root(outgroup, names);
        (self.taxa_count..self.adjacency.len()).filter(|&node| node != rooted.root && !self.adjacency[node].is_empty()).map(|node| rooted.masks[node]).collect()
    }
    pub fn path(&self, start: usize, end: usize) -> (usize, f64) {
        let mut queue = VecDeque::from([(start, usize::MAX, 0usize, 0.0)]);
        while let Some((node, previous, branches, length)) = queue.pop_front() {
            if node == end { return (branches, length); }
            for (&next, &edge) in &self.adjacency[node] { if next != previous { queue.push_back((next, node, branches+1, length+edge)); } }
        }
        unreachable!()
    }
    pub fn patristic(&self) -> Vec<Vec<f64>> { (0..self.taxa_count).map(|i| (0..self.taxa_count).map(|j| if i == j { 0.0 } else { self.path(i, j).1 }).collect()).collect() }
}

pub fn nj(matrix: &[Vec<f64>], taxa: &[usize]) -> Tree {
    let n = matrix.len(); let mut tree = Tree::empty(n);
    let mut distance = vec![vec![0.0; 2*n]; 2*n];
    for i in 0..n { distance[i][..n].copy_from_slice(&matrix[i]); }
    let mut active = taxa.to_vec();
    while active.len() >= 4 {
        let r = active.len();
        let totals: Vec<f64> = active.iter().map(|&x| active.iter().filter(|&&y| y != x).map(|&y| distance[x][y]).sum()).collect();
        let mut chosen = (0, 1); let mut minimum = f64::INFINITY;
        for i in 0..r { for j in i+1..r {
            let q = (r-2) as f64*distance[active[i]][active[j]]-totals[i]-totals[j];
            if q < minimum { minimum = q; chosen = (i, j); }
        } }
        let (i, j) = chosen; let (a, b) = (active[i], active[j]); let u = tree.node();
        let la = distance[a][b]/2.0+(totals[i]-totals[j])/(2.0*(r-2) as f64);
        tree.connect(a, u, la); tree.connect(b, u, distance[a][b]-la);
        for &k in &active { if k != a && k != b { let value = (distance[a][k]+distance[b][k]-distance[a][b])/2.0; distance[u][k] = value; distance[k][u] = value; } }
        active.remove(j); active.remove(i); active.push(u);
    }
    let (a, b, c) = (active[0], active[1], active[2]); let z = tree.node();
    tree.connect(a, z, (distance[a][b]+distance[a][c]-distance[b][c])/2.0);
    tree.connect(b, z, (distance[a][b]+distance[b][c]-distance[a][c])/2.0);
    tree.connect(c, z, (distance[a][c]+distance[b][c]-distance[a][b])/2.0);
    let edges: Vec<_> = tree.adjacency.iter().enumerate().flat_map(|(a, row)| row.iter().filter(move |&(b, _)| a < *b).map(move |(&b, &length)| (a, b, length))).collect();
    for (a, b, length) in edges { if length < 0.0 { tree.negative += 1; tree.connect(a, b, 0.0); } }
    tree
}
