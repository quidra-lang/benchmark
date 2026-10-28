import java.io.File

object Dataset {
    data class Box(val x1: Long,val y1: Long,val x2: Long,val y2: Long)
    data class Obj(val id: Int,val box: Box)
    data class Command(val name: String,val values: IntArray)
    data class Data(val points: List<Obj>,val rectangles: List<Obj>,val world: Int,val bucket: Int,
        val maximum: Int,val minimum: Int,val grid: Int,val commands: List<Command>)
    fun point(id: Int,x: Int,y: Int)=Obj(id,Box(x.toLong(),y.toLong(),x.toLong(),y.toLong()))
    fun lines(name: String)=File("input/$name").readLines(Charsets.US_ASCII)
    fun read(): Data {
        val points=lines("points.csv").drop(1).map {
            val w=it.split(',');
            point(w[0].toInt(),w[1].toInt(),w[2].toInt())
        };
        val rectangles=lines("rects.csv").drop(1).map {
            val w=it.split(',');
            Obj(w[0].toInt(),Box(w[1].toLong(),w[2].toLong(),w[3].toLong(),w[4].toLong()))
        };
        val params=lines("params.txt").map {
            it.split(' ')
        };
        val commands=lines("queries.txt").map {
            val w=it.split(' ');
            Command(w[0],w.drop(1).map(String::toInt).toIntArray())
        };
        return Data(points,rectangles,params[0][1].toInt(),params[1][1].toInt(),params[2][1].toInt(),params[2][2].toInt(),params[3][1].toInt(),commands)
    }
}
