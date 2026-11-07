export interface Node {
  children: Map<string, Node>;
  terminal: boolean;
}
const makeNode = (): Node => ({ children: new Map<string, Node>(), terminal: false });
export class Trie {
  root = makeNode();
  nodes = 1;
  words = 0;
  add(word: string) {
    let node = this.root;
    for (const letter of word) {
      let child = node.children.get(letter);
      if (!child) {
        child = makeNode();
        node.children.set(letter, child);
        this.nodes++;
      }
      node = child;
    }
    if (node.terminal) return false;
    node.terminal = true;
    this.words++;
    return true;
  }
  find(prefix: string): Node | null {
    let node = this.root;
    for (const letter of prefix) {
      const child = node.children.get(letter);
      if (!child) return null;
      node = child;
    }
    return node;
  }
  has(word: string) {
    return this.find(word)?.terminal ?? false;
  }
  anagrams(rack: string) {
    const counts = new Map<string, number>();
    const result: string[] = [];
    for (const tile of rack) counts.set(tile, (counts.get(tile) ?? 0) + 1);
    const visit = (node: Node, word: string) => {
      if (node.terminal) result.push(word);
      for (const [letter, child] of node.children) {
        const tile = (counts.get(letter) ?? 0) > 0 ? letter : '?';
        if (!(counts.get(tile) ?? 0)) continue;
        counts.set(tile, counts.get(tile)! - 1);
        visit(child, word + letter);
        counts.set(tile, counts.get(tile)! + 1);
      }
    };
    visit(this.root, '');
    return result;
  }
}
