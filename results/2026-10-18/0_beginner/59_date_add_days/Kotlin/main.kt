import java.math.BigDecimal
import java.math.RoundingMode

fun date(y: Int, m: Int, d: Int): String = y.toString().padStart(4,'0') + "-" + m.toString().padStart(2,'0') + "-" + d.toString().padStart(2,'0')
fun main() {
    for (item in listOf(listOf(1999,12,25,10),listOf(2000,2,27,3),listOf(2021,2,20,14),listOf(2023,11,15,120),listOf(2026,10,17,1500))) {
        var year = item[0]; var month = item[1]; var day = item[2]; val original = date(year,month,day)
        repeat(item[3]) {
            val lengths = intArrayOf(31,28,31,30,31,30,31,31,30,31,30,31)
            if (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)) lengths[1] = 29
            day++; if (day > lengths[month - 1]) { day = 1; month++; if (month > 12) { month = 1; year++ } }
        }
        println("$original + ${item[3]} days = ${date(year,month,day)}")
    }
}
