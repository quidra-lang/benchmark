object Scoring {
    const val RACK_SIZE=7;
    const val BINGO_BONUS=50
    data class WordScore(val word: Board.Move,val score: Int)
    data class Result(val score: Int,val tiles: List<Board.Tile>,val words: List<WordScore>)
    fun squares(move: Board.Move)=move.word.mapIndexed {
        i,letter->Board.Tile(move.row+move.direction*i,move.column+(1-move.direction)*i,letter)
    }
    fun placement(board: Array<CharArray>,move: Board.Move)=squares(move).filter {
        board[it.row][it.column]=='.'
    }
    fun apply(board: Array<CharArray>,tiles: List<Board.Tile>): Array<CharArray> {
        val result=Array(board.size) {
            board[it].clone()
        };
        for(tile in tiles)result[tile.row][tile.column]=tile.letter;
        return result
    }
    fun crosses(board: Array<CharArray>,move: Board.Move): List<Board.Move> {
        val tiles=placement(board,move);
        val after=apply(board,tiles);
        return tiles.map {
            Board.run(after,it.row,it.column,1-move.direction)
        }.filter {
            it.word.length>=2
        }
    }
    fun wordScore(board: Array<CharArray>,word: Board.Move,values: IntArray): Int {
        var score=0;
        var multiplier=1;
        for(tile in squares(word)) {
            var value=if(tile.letter in 'A'..'Z')values[tile.letter.code] else 0;
            if(board[tile.row][tile.column]=='.') {
                val premium=Board.premiums[tile.row][tile.column];
                value*=if(premium=='+')2 else if(premium=='^')3 else 1;
                multiplier*=if(premium=='*')2 else if(premium=='#')3 else 1
            };
            score+=value
        };
        return score*multiplier
    }
    fun evaluate(board: Array<CharArray>,move: Board.Move,values: IntArray): Result {
        val words=(listOf(move)+crosses(board,move)).map {
            WordScore(it,wordScore(board,it,values))
        };
        val tiles=placement(board,move);
        return Result(words.sumOf {
            it.score
        }+(if(tiles.size==RACK_SIZE)BINGO_BONUS else 0),tiles,words)
    }
}
