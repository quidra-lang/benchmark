object Board {
    const val SIZE=15;
    const val COLUMNS="ABCDEFGHIJKLMNO"
    val premiums=listOf("#..+...#...+..#",".*...^...^...*.","..*...+.+...*..","+..*...+...*..+","....*.....*....",
        ".^...^...^...^.","..+...+.+...+..","#..+...*...+..#","..+...+.+...+..",".^...^...^...^.","....*.....*....",
        "+..*...+...*..+","..*...+.+...*..",".*...^...^...*.","#..+...#...+..#")
    data class Move(val row: Int,val column: Int,val direction: Int,val word: String)
    data class Tile(val row: Int,val column: Int,val letter: Char)
    data class Cell(val row: Int,val column: Int)
    fun inside(r: Int,c: Int)=r in 0 until SIZE&&c in 0 until SIZE
    fun square(r: Int,c: Int)="${COLUMNS[c]}${r+1}"
    fun position(move: Move)=if(move.direction==0)"${move.row+1}${COLUMNS[move.column]}" else "${COLUMNS[move.column]}${move.row+1}"
    fun parse(text: String,word: String): Move? {
        if(text.matches(Regex("([1-9]|1[0-5])[A-O]")))return Move(text.dropLast(1).toInt()-1,COLUMNS.indexOf(text.last()),
            0,word);
        if(text.matches(Regex("[A-O]([1-9]|1[0-5])")))return Move(text.drop(1).toInt()-1,COLUMNS.indexOf(text.first()),
            1,word);
        return null
    }
    fun empty()=Array(SIZE) {
        CharArray(SIZE) {
            '.'
        }
    }
    fun transpose(board: Array<CharArray>)=Array(SIZE) {
        r->CharArray(SIZE) {
            c->board[c][r]
        }
    }
    fun transposeTiles(tiles: List<Tile>)=tiles.map {
        Tile(it.column,it.row,it.letter)
    }
    fun tiles(board: Array<CharArray>): List<Tile> {
        val result=mutableListOf<Tile>();
        for(r in 0 until SIZE)for(c in 0 until SIZE)if(board[r][c]!='.')result.add(Tile(r,c,board[r][c]));
        return result
    }
    fun neighbors(r: Int,c: Int)=listOf(Cell(r-1,c),Cell(r+1,c),Cell(r,c-1),Cell(r,c+1)).filter {
        inside(it.row,it.column)
    }
    fun run(board: Array<CharArray>,row: Int,column: Int,direction: Int): Move {
        val dr=direction;
        val dc=1-direction;
        var r=row;
        var c=column;
        while(inside(r-dr,c-dc)&&board[r-dr][c-dc]!='.') {
            r-=dr;
            c-=dc
        };
        val firstRow=r;
        val firstColumn=c;
        val word=StringBuilder();
        while(inside(r,c)&&board[r][c]!='.') {
            word.append(board[r][c]);
            r+=dr;
            c+=dc
        };
        return Move(firstRow,firstColumn,direction,word.toString())
    }
    fun words(board: Array<CharArray>): List<Move> {
        val result=mutableListOf<Move>();
        for(direction in 0..1)for(line in 0 until SIZE) {
            var offset=0;
            while(offset<SIZE) {
                val r=if(direction==0)line else offset;
                val c=if(direction==0)offset else line;
                if(board[r][c]=='.') {
                    offset++;
                    continue
                };
                val word=run(board,r,c,direction);
                if(word.word.length>=2)result.add(word);
                offset+=word.word.length
            }
        };
        return result
    }
    fun connected(board: Array<CharArray>): Boolean {
        val occupied=tiles(board);
        if(occupied.isEmpty())return true;
        val seen=mutableSetOf(Cell(occupied.first().row,occupied.first().column));
        val pending=ArrayDeque(seen);
        while(pending.isNotEmpty()) {
            val cell=pending.removeLast();
            for(next in neighbors(cell.row,cell.column))if(board[next.row][next.column]!='.'&&seen.add(next))pending.add(next)
        };
        return seen.size==occupied.size
    }
    fun display(board: Array<CharArray>)=listOf("   "+COLUMNS.toList().joinToString(" "))+(0 until SIZE).map {
        r->(r+1).toString().padStart(2)+" "+(0 until SIZE).joinToString(" ") {
            c->(if(board[r][c]=='.')premiums[r][c] else board[r][c]).toString()
        }
    }
}
