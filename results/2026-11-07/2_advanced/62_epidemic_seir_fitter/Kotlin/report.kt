import java.util.Locale
import kotlin.math.floor

object Report {
    fun f(value: Double,places: Int): String {
        val s=String.format(Locale.ROOT,"%.${places}f",value);
        return if(s.startsWith("-")&&s.toDouble()==0.0)s.substring(1) else s
    }
    fun plot(observed: IntArray,fitted: DoubleArray): List<String> {
        val n=observed.size;
        var maximum=0;
        for(value in observed)maximum=maxOf(maximum,value);
        val width=maximum.toString().length;
        val grid=Array(20) {
            CharArray(70) {
                '.'
            }
        }
        for(x in 0 until 70) {
            val day=x*(n-1)/69;
            val oy=minOf(19,20*observed[day]/maximum);
            val fy=minOf(19,floor(20*fitted[day]/maximum).toInt());
            grid[oy][x]='o';
            grid[fy][x]=if(oy==fy)'#' else '*'
        }
        val lines=mutableListOf("plot observed o fitted * both # days 1 $n max $maximum")
        for(y in 19 downTo 0)lines.add((maximum*y/20).toString().padStart(width)+" |"+grid[y].concatToString())
        val ticks=(0 until 70).joinToString("") {
            if(it%10==0)"+" else "-"
        };
        lines.add(" ".repeat(width+1)+"+"+ticks)
        val labels=CharArray(70) {
            ' '
        };
        for(x in 0..60 step 10) {
            val label=(1+x*(n-1)/69).toString();
            for(i in label.indices)labels[x+i]=label[i]
        }
        lines.add((" ".repeat(width+2)+labels.concatToString()).trimEnd(' '));
        return lines
    }
}
