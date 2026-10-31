object MoveGenerator {
    const val LETTERS="ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    fun anchors(board: Array<CharArray>): Array<BooleanArray> {
        val result=Array(15) {
            BooleanArray(15)
        };
        if(Board.tiles(board).isEmpty()) {
            result[7][7]=true;
            return result
        };
        for(r in 0..14)for(c in 0..14)if(board[r][c]=='.'&&Board.neighbors(r,c).any {
            board[it.row][it.column]!='.'
        })result[r][c]=true;
        return result
    }
    fun checks(board: Array<CharArray>,trie: DictionaryTrie): Array<IntArray> {
        val result=Array(15) {
            IntArray(15) {
                -1
            }
        };
        for(r in 0..14)for(c in 0..14)if(board[r][c]=='.') {
            var first=r;
            var last=r;
            while(first>0&&board[first-1][c]!='.')first--;
            while(last+1<15&&board[last+1][c]!='.')last++;
            if(first==last)continue;
            val prefix=(first until r).map {
                board[it][c].uppercaseChar()
            }.joinToString("");
            val suffix=(r+1..last).map {
                board[it][c].uppercaseChar()
            }.joinToString("");
            var mask=0;
            for(i in 0..25)if(trie.contains(prefix+('A'+i)+suffix))mask=mask or (1 shl i);
            result[r][c]=mask
        };
        return result
    }
    class Search(val board: Array<CharArray>,rack: String,val trie: DictionaryTrie,val anchors: Array<BooleanArray>,
        val checks: Array<IntArray>) {
        val counts=IntArray(128);
        val result=mutableListOf<Board.Move>();
        var row=0;
        var anchor=0
        init {
            for(c in rack)counts[c.code]++
        }
        fun extend(node: DictionaryTrie.Node,column: Int,word: String,start: Int) {
            val empty=column==15||board[row][column]=='.';
            if(empty&&column>anchor&&node.terminal)result.add(Board.Move(row,start,0,word));
            if(column==15)return;
            if(!empty) {
                val letter=board[row][column];
                val child=node.children[letter.uppercaseChar()-'A'];
                if(child!=null)extend(child,column+1,word+letter,start);
                return
            };
            for(i in 0..25) {
                val child=node.children[i]?:continue;
                if(checks[row][column]!=-1&&(checks[row][column] and (1 shl i))==0)continue;
                val letter='A'+i;
                for(blank in 0..1) {
                    val tile=if(blank==0)letter else '?';
                    val written=if(blank==0)letter else letter.lowercaseChar();
                    if(counts[tile.code]>0) {
                        counts[tile.code]--;
                        extend(child,column+1,word+written,start);
                        counts[tile.code]++
                    }
                }
            }
        }
        fun left(node: DictionaryTrie.Node,prefix: String,remaining: Int) {
            extend(node,anchor,prefix,anchor-prefix.length);
            if(remaining==0)return;
            for(i in 0..25) {
                val child=node.children[i]?:continue;
                val letter='A'+i;
                for(blank in 0..1) {
                    val tile=if(blank==0)letter else '?';
                    val written=if(blank==0)letter else letter.lowercaseChar();
                    if(counts[tile.code]>0) {
                        counts[tile.code]--;
                        left(child,prefix+written,remaining-1);
                        counts[tile.code]++
                    }
                }
            }
        }
        fun generate(): List<Board.Move> {
            for(r in 0..14)for(a in 0..14)if(anchors[r][a]) {
                row=r;
                anchor=a;
                if(anchor>0&&board[row][anchor-1]!='.') {
                    var first=anchor-1;
                    while(first>0&&board[row][first-1]!='.')first--;
                    val prefix=String(board[row],first,anchor-first);
                    val node=trie.prefix(prefix.uppercase());
                    if(node!=null)extend(node,anchor,prefix,first)
                } else {
                    var first=anchor-1;
                    while(first>=0&&board[row][first]=='.'&&!anchors[row][first])first--;
                    left(trie.root,"",anchor-first-1)
                }
            };
            return result
        }
    }
    fun generate(board: Array<CharArray>,rack: String,trie: DictionaryTrie): List<Board.Move> {
        val anchors=anchors(board);
        val across=Search(board,rack,trie,anchors,checks(board,trie)).generate();
        val transposed=Board.transpose(board);
        val downAnchors=Array(15) {
            r->BooleanArray(15) {
                c->anchors[c][r]
            }
        };
        val down=Search(transposed,rack,trie,downAnchors,checks(transposed,trie)).generate().map {
            Board.Move(it.column,it.row,1,it.word)
        };
        val distinct=linkedMapOf<List<Board.Tile>,Board.Move>();
        for(move in across+down) {
            val tiles=Scoring.placement(board,move);
            if(tiles.size==1&&move.direction==1) {
                val tile=tiles.first();
                if(Board.run(Scoring.apply(board,tiles),tile.row,tile.column,0).word.length>=2)continue
            };
            distinct[tiles.sortedWith(compareBy<Board.Tile> {
                it.row
            }.thenBy {
                it.column
            })]=move
        };
        return distinct.values.toList()
    }
}
