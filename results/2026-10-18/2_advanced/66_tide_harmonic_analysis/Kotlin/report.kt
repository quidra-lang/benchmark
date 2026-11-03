import java.io.File
import java.util.Locale
object Report {
    fun f(value: Double,places: Int): String {
        val result=String.format(Locale.ROOT,"%.${places}f",value);
        return if(result.startsWith("-")&&result.toDouble()==0.0)result.substring(1) else result
    }
    fun optional(value: Double?,places: Int)=if(value==null)"none" else f(value,places)
    fun write(name: String,lines: List<String>) {
        File("output").mkdirs();
        File("output",name).writeText(lines.joinToString("\n")+"\n")
    }
    fun plot(cells: Array<CharArray>,labels: Array<String>): List<String> {
        val width=labels.maxOf {
            it.length
        };
        val lines=mutableListOf<String>();
        for(q in cells.indices)lines.add(labels[q].padStart(width)+" |"+cells[q].concatToString()+"|");
        val axis=" ".repeat(width)+" +"+(cells[0].indices).joinToString("") {
            if(it%6==0)"+" else "-"
        }+"+";
        lines.add(axis);
        return lines
    }
}
