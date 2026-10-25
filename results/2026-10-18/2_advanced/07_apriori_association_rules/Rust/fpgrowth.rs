use std::collections::BTreeMap;
use crate::baskets::{Frequent, Itemset};

type PatternBase = Vec<(Itemset, i64)>;

struct Node { item: String, parent: usize, count: i64, children: BTreeMap<String, usize> }
struct Tree { header: Itemset, nodes: Vec<Node>, links: BTreeMap<String, Vec<usize>> }

impl Tree {
    fn new(base: PatternBase, minimum: i64) -> Self {
        let mut supports = BTreeMap::<String, i64>::new();
        for (items, weight) in &base { for item in items { *supports.entry(item.clone()).or_default() += weight; } }
        let mut header: Itemset = supports.iter().filter(|&(_, &count)| count >= minimum).map(|(item, _)| item.clone()).collect();
        header.sort_by(|a,b| supports[b].cmp(&supports[a]).then_with(|| a.cmp(b)));
        let order: BTreeMap<String, usize> = header.iter().cloned().enumerate().map(|(index,item)| (item,index)).collect();
        let links = header.iter().cloned().map(|item| (item,Vec::new())).collect();
        let root = Node { item: String::new(), parent: 0, count: 0, children: BTreeMap::new() };
        let mut tree = Self { header, nodes: vec![root], links };
        for (items, weight) in base {
            let mut path: Itemset = items.into_iter().filter(|item| order.contains_key(item)).collect(); path.sort_by_key(|item| order[item]);
            let mut node = 0;
            for item in path {
                let next = if let Some(&index) = tree.nodes[node].children.get(&item) { index } else {
                    let index = tree.nodes.len();
                    tree.nodes.push(Node { item: item.clone(), parent: node, count: 0, children: BTreeMap::new() });
                    tree.nodes[node].children.insert(item.clone(),index); tree.links.get_mut(&item).unwrap().push(index); index
                };
                node = next; tree.nodes[node].count += weight;
            }
        }
        tree
    }
    fn support(&self, item: &str) -> i64 { self.links[item].iter().map(|&index| self.nodes[index].count).sum() }
    fn conditional_base(&self, item: &str) -> PatternBase {
        self.links[item].iter().map(|&index| {
            let mut path = Vec::new(); let mut ancestor = self.nodes[index].parent;
            while ancestor != 0 { path.push(self.nodes[ancestor].item.clone()); ancestor = self.nodes[ancestor].parent; }
            path.reverse(); (path,self.nodes[index].count)
        }).collect()
    }
}

pub struct GrowthResult { pub header: usize, pub nodes: usize, pub conditional_trees: usize, pub conditional_nodes: usize, pub itemsets: Frequent }

pub fn fp_growth(base: Vec<(Itemset, i64)>, minimum: i64, max_size: usize) -> GrowthResult {
    let tree = Tree::new(base,minimum);
    let mut result = GrowthResult { header: tree.header.len(), nodes: tree.nodes.len() - 1, conditional_trees: 0, conditional_nodes: 0, itemsets: BTreeMap::new() };
    let mut stack = vec![(tree,Vec::<String>::new())];
    while let Some((current,suffix)) = stack.pop() {
        for item in current.header.iter().rev() {
            let mut items = suffix.clone(); items.push(item.clone()); items.sort();
            result.itemsets.insert(items.clone(),current.support(item));
            if items.len() < max_size {
                let conditional = Tree::new(current.conditional_base(item),minimum);
                if conditional.nodes.len() > 1 { result.conditional_trees += 1; result.conditional_nodes += conditional.nodes.len() - 1; stack.push((conditional,items)); }
            }
        }
    }
    result
}
