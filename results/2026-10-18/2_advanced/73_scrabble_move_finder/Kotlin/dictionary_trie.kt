class DictionaryTrie {
    class Node {
        val children=arrayOfNulls<Node>(26);
        var terminal=false
    }
    val root=Node();
    var nodes=1;
    var words=0
    fun add(word: String): Boolean {
        var node=root;
        for(letter in word) {
            val i=letter-'A';
            var child=node.children[i];
            if(child==null) {
                child=Node();
                node.children[i]=child;
                nodes++
            };
            node=child
        };
        if(node.terminal)return false;
        node.terminal=true;
        words++;
        return true
    }
    fun prefix(word: String): Node? {
        var node=root;
        for(letter in word)node=node.children[letter-'A']?:return null;
        return node
    }
    fun contains(word: String)=prefix(word)?.terminal==true
    fun visit(node: Node,word: String,counts: IntArray,result: MutableList<String>) {
        if(node.terminal)result.add(word);
        for(i in 0..25) {
            val child=node.children[i]?:continue;
            val letter='A'+i;
            val tile=if(counts[letter.code]>0)letter else '?';
            if(counts[tile.code]>0) {
                counts[tile.code]--;
                visit(child,word+letter,counts,result);
                counts[tile.code]++
            }
        }
    }
    fun anagrams(rack: String): MutableList<String> {
        val counts=IntArray(128);
        for(c in rack)counts[c.code]++;
        val result=mutableListOf<String>();
        visit(root,"",counts,result);
        return result
    }
}
