import java.io.File

object SignalIo {
    class Annotation(val sample: Int,val label: String) {
        var beat: Beat?=null
    }
    fun ecg()=File("input/ecg.csv").readLines(Charsets.US_ASCII).drop(1).map {
        it.substringAfter(',').toLong()
    }.toLongArray()
    fun annotations()=File("input/annotations.csv").readLines(Charsets.US_ASCII).drop(1).map {
        val w=it.split(',');
        Annotation(w[0].toInt(),w[1])
    }
    fun parameters()=File("input/params.txt").readLines(Charsets.US_ASCII).associate {
        val w=it.split(' ');
        w[0] to w[1].toInt()
    }
    fun write(name: String,lines: List<String>) {
        File("output").mkdirs();
        File("output/$name").writeText(lines.joinToString("\n",postfix="\n"),Charsets.US_ASCII)
    }
}
