import java.io.File
import java.util.Locale

object Report {
    fun real(value: Double): String {
        if(value.isNaN())return "-";
        val text=String.format(Locale.ROOT,"%.4f",value);
        return if(text=="-0.0000")"0.0000" else text
    }
    fun write(name: String,lines: List<String>) {
        File("output/$name").writeText(lines.joinToString("\n",postfix="\n"),Charsets.US_ASCII)
    }
}
