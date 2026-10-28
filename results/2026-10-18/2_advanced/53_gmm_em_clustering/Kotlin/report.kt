import java.io.File
import java.math.BigDecimal
import java.math.RoundingMode

object Report {
    fun decimal(value: Double,digits: Int): String {
        if(value.isNaN())return "-";
        var result=BigDecimal.valueOf(value).setScale(digits,RoundingMode.HALF_UP);
        if(result.signum()==0)result=BigDecimal.ZERO.setScale(digits);
        return result.toPlainString()
    }
    fun f(value: Double)=decimal(value,4)
    fun rounded(value: Double)=BigDecimal.valueOf(value).setScale(4,RoundingMode.HALF_UP)
    fun frame(map: Array<CharArray>): List<String> {
        val edge="+"+"-".repeat(map[0].size)+"+";
        val out=mutableListOf(edge);
        for(row in map)out+="|"+row.concatToString()+"|";
        out+=edge;
        return out
    }
    fun write(name: String,lines: List<String>) {
        File("output/$name").writeText(lines.joinToString("\n",postfix="\n"),Charsets.US_ASCII)
    }
}
