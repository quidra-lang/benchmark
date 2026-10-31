import java.io.File
import java.math.BigDecimal
import java.math.RoundingMode
object Report {
    fun decimal(value: Double,digits: Int=3)=BigDecimal.valueOf(value).setScale(digits,RoundingMode.HALF_UP).toPlainString()
    fun signed(value: Int)=if(value>0)"+$value" else value.toString()
    fun chart(rows: List<String>): List<String> {
        val border="+"+"-".repeat(rows.first().length)+"+";
        return listOf(border)+rows.map {
            "|$it|"
        }+border
    }
    fun write(name: String,lines: List<String>) {
        File("output").mkdirs();
        File("output",name).writeText(lines.joinToString("\n")+if(lines.isEmpty())"" else "\n")
    }
}
