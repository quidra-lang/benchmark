const { compareNames, itemsetKey } = require('./baskets');

class Node {
  constructor(item, parent) {
    this.item = item;
    this.parent = parent;
    this.count = 0;
    this.children = new Map();
  }
}

function buildTree(base, minimum) {
  const counts = new Map();
  for (const { items, weight } of base) {
    for (const item of items) counts.set(item, (counts.get(item) ?? 0) + weight);
  }
  const header = [...counts.keys()].filter(item => counts.get(item) >= minimum);
  header.sort((first, second) => counts.get(second) - counts.get(first) || compareNames(first, second));
  const order = new Map(header.map((item, index) => [item, index]));
  const links = new Map(header.map(item => [item, []]));
  const root = new Node(null, null);
  let nodes = 0;
  for (const { items, weight } of base) {
    const sorted = items.filter(item => order.has(item)).sort((first, second) => order.get(first) - order.get(second));
    let current = root;
    for (const item of sorted) {
      if (!current.children.has(item)) {
        const node = new Node(item, current);
        current.children.set(item, node);
        links.get(item).push(node);
        nodes += 1;
      }
      current = current.children.get(item);
      current.count += weight;
    }
  }
  return { root, header, links, nodes };
}

function conditionalBase(tree, item) {
  return tree.links.get(item).map(node => {
    const items = [];
    let parent = node.parent;
    while (parent.item !== null) {
      items.push(parent.item);
      parent = parent.parent;
    }
    items.reverse();
    return { items, weight: node.count };
  });
}

function mine(baskets, minimum, maximumSize) {
  const whole = buildTree(baskets.map(items => ({ items: [...items], weight: 1 })), minimum);
  const stack = [{ tree: whole, suffix: [] }];
  const frequent = new Map();
  let conditionalTrees = 0;
  let conditionalNodes = 0;
  while (stack.length > 0) {
    const { tree, suffix } = stack.pop();
    for (const item of tree.header.slice().reverse()) {
      const items = [...suffix, item].sort(compareNames);
      let count = 0;
      for (const node of tree.links.get(item)) count += node.count;
      frequent.set(itemsetKey(items), { items, count });
      if (items.length < maximumSize) {
        const conditional = buildTree(conditionalBase(tree, item), minimum);
        if (conditional.nodes > 0) {
          stack.push({ tree: conditional, suffix: items });
          conditionalTrees += 1;
          conditionalNodes += conditional.nodes;
        }
      }
    }
  }
  return { frequent, header: whole.header.length, nodes: whole.nodes, conditionalTrees, conditionalNodes };
}

module.exports = { mine };
