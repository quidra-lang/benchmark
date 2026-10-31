pub struct Node {
    pub children: [Option<usize>;26],
    pub terminal: bool
}
pub struct Trie {
    pub nodes: Vec<Node>,
    pub words: usize
}
impl Trie {
    pub fn new() -> Self {
        Self {
            nodes: vec![Node {
                children: [None;26],terminal: false
            }],
            words: 0
        }
    }
    pub fn insert(&mut self, word: &[u8]) -> bool {
        let mut node = 0;
        for &letter in word {
            let index = (letter-b'A') as usize;
            node = if let Some(child) = self.nodes[node].children[index] {
                child
            } else {
                let child = self.nodes.len();
                self.nodes.push(Node {
                    children: [None;26],
                    terminal: false
                });
                self.nodes[node].children[index] = Some(child);
                child
            };
        }
        if self.nodes[node].terminal {
            false
        } else {
            self.nodes[node].terminal = true;
            self.words += 1;
            true
        }
    }
    pub fn prefix(&self, word: &[u8]) -> Option<usize> {
        let mut node = 0;
        for &letter in word {
            node = self.nodes[node].children[(letter.to_ascii_uppercase()-b'A') as usize]?;
        }
        Some(node)
    }
    pub fn contains(&self, word: &[u8]) -> bool {
        self.prefix(word).map_or(false,|n| self.nodes[n].terminal)
    }
    pub fn anagrams(&self, rack: &[u8]) -> Vec<String> {
        fn visit(trie: &Trie, node: usize, counts: &mut [usize;27], word: &mut Vec<u8>, result: &mut Vec<String>) {
            if trie.nodes[node].terminal {
                result.push(String::from_utf8(word.clone()).unwrap());
            }
            for l in 0..26 {
                if let Some(child) = trie.nodes[node].children[l] {
                    let tile = if counts[l] > 0 {
                        l
                    } else {
                        26
                    };
                    if counts[tile] > 0 {
                        counts[tile] -= 1;
                        word.push(b'A'+l as u8);
                        visit(trie,child,counts,word,result);
                        word.pop();
                        counts[tile] += 1;
                    }
                }
            }
        }
        let mut counts = [0usize;27];
        for &tile in rack {
            counts[if tile == b'?' {
                26
            } else {
                (tile-b'A') as usize
            }] += 1;
        }
        let mut result = Vec::new();
        visit(self,0,&mut counts,&mut Vec::new(),&mut result);
        result
    }
}
