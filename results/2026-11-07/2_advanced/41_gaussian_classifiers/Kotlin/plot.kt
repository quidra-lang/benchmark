import java.io.File
import java.util.Locale
import kotlin.math.floor

object Plot {
    fun real(value: Double)=String.format(Locale.ROOT,"%.4f",value).let {
        if(it=="-0.0000")"0.0000" else it
    }
    fun reals(values: DoubleArray)=values.joinToString(" ") {
        real(it)
    }
    fun fraction(f: Evaluation.Fraction?)=if(f==null)"-" else "${f.n}/${f.d} ${real(f.n.toDouble()/f.d)}"
    fun ratio(n: Long,d: Long)=fraction(Evaluation.fraction(n,d))
    fun frame(grid: Array<CharArray>): List<String> {
        val border="+"+"-".repeat(grid[0].size)+"+";
        return listOf(border)+grid.map {
            "|"+it.concatToString()+"|"
        }
        +border
    }
    fun grid(width: Int,height: Int)=Array(height) {
        CharArray(width) {
            ' '
        }
    }
    fun cell(value: Double,lo: Double,hi: Double,size: Int)=floor((value-lo)/(hi-lo)*(size-1)+0.5).toInt()
    fun place(grid: Array<CharArray>,col: Int,row: Int,letter: Char) {
        val previous=grid[row][col];
        grid[row][col]=if(previous==' '||previous==letter)letter else '*'
    }
    fun section(output: MutableList<String>,part: List<String>) {
        if(output.isNotEmpty())output+="";
        output+=part
    }
    fun write(name: String,lines: List<String>) {
        File("output").mkdirs();
        File("output/$name").writeText(lines.joinToString("\n",postfix="\n"),Charsets.US_ASCII)
    }
}
