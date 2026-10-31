import java.io.File

object PgmIo {
    data class Point(val x: Int,val y: Int)
    class Params(val values: Map<String,LongArray>) {
        fun get(key: String)=values.getValue(key)[0].toInt();
        fun value(key: String)=values.getValue(key)[0];
        fun row(key: String)=values.getValue(key)
    }
    data class Data(val image: Array<IntArray>,val trig: Array<IntArray>,val params: Params)
    fun lines(name: String)=File("input/$name").readLines(Charsets.US_ASCII)
    fun read(): Data {
        val input=lines("image.pgm");
        val size=input[1].split(' ').map(String::toInt);
        val image=Array(size[1]) {
            y->input[y+3].split(' ').map(String::toInt).toIntArray()
        };
        val trig=lines("trig.txt").map {
            it.split(' ').drop(1).map(String::toInt).toIntArray()
        }.toTypedArray();
        val values=lines("params.txt").associate {
            val w=it.split(' ');
            w[0] to w.drop(1).map(String::toLong).toLongArray()
        };
        return Data(image,trig,Params(values))
    }
    fun write(name: String,lines: List<String>) {
        File("output/$name").writeText(lines.joinToString("\n",postfix="\n"),Charsets.US_ASCII)
    }
    fun pgm(name: String,image: Array<IntArray>) {
        val out=mutableListOf("P2","${image[0].size} ${image.size}","255");
        for(row in image)out+=row.joinToString(" ");
        write(name,out)
    }
}
