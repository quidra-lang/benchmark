import kotlin.math.*

object Plot {
    data class Cell(val row: Int,val col: Int)
    fun grid(rows: Int,cols: Int)=Array(rows) {
        CharArray(cols) {
            ' '
        }
    }
    fun framed(grid: Array<CharArray>): List<String> {
        val border="+"+"-".repeat(grid[0].size)+"+";
        val output=mutableListOf(border)
        for(row in grid)output+="|"+row.concatToString()+"|"
        output+=border
        return output
    }
    fun index(fraction: Double,size: Int)=minOf(floor(fraction*size).toInt(),size-1)
    fun rounded(fraction: Double,size: Int)=floor(fraction*size+0.5).toInt()
    fun biplot(x: Double,y: Double,mx: Double,my: Double,width: Int,height: Int)=Cell(index((my-y)/(2*my),height),index((x+mx)/(2*mx),width))
    fun circle(first: Double,second: Double,radius: Int)=Cell(radius/2+1-rounded(second,radius/2),radius+1+rounded(first,radius))
    fun diagnostic(t2: Double,spe: Double,xmax: Double,ymax: Double,width: Int,height: Int)=Cell(height-1-index(spe/ymax,height),index(t2/xmax,width))
    fun shaft(origin: Cell,tip: Cell): List<Cell> {
        val dr=tip.row-origin.row;
        val dc=tip.col-origin.col;
        val steps=maxOf(abs(dc),abs(dr));
        return (1 until steps).map {
            s->Cell(origin.row+Integer.signum(dr)*((2*s*abs(dr)+steps)/(2*steps)),origin.col+Integer.signum(dc)*((2*s*abs(dc)+steps)/(2*steps)))
        }
    }
    fun shaftCharacter(origin: Cell,tip: Cell): Char {
        val dr=tip.row-origin.row;
        val dc=tip.col-origin.col;
        return if(2*abs(dr)<=abs(dc))'-' else if(2*abs(dc)<=abs(dr))'|' else if(dc*dr<0)'/' else '\\'
    }
    fun scree(length: Int,kaiser: Int,broken: Int,width: Int): String {
        var line="|";
        for(p in 1..width)line+=if(p==broken)'o' else if(p==kaiser)':' else if(p<=length)'#' else ' ';
        return line+"|"
    }
}
