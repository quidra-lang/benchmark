import java.io.File
import java.util.Locale

object Report {
    data class MapImage(val counts: IntArray,val lines: List<String>)
    fun real(value: Double,places: Int): String {
        val s=String.format(Locale.ROOT,"%.${places}f",value);
        return if(s=="-0."+"0".repeat(places))s.substring(1) else s
    }
    fun time(ms: Int)="${ms/1000}.${(ms%1000).toString().padStart(3,'0')}"
    fun field(m: Mesh,x: DoubleArray)=(0 until m.height).map {
        r->(0 until m.width).joinToString(" ") {
            c->real(x[m.cell(r,c)],2)
        }
    }
    fun isotherm(m: Mesh,x: DoubleArray,bands: DoubleArray): MapImage {
        var hottest=0;
        for(p in 1 until x.size)if(x[p]>x[hottest])hottest=p;
        val counts=IntArray(bands.size+1);
        val cells=CharArray(x.size)
        for(p in x.indices) {
            val digit=bands.count {
                it<=x[p]
            };
            counts[digit]++;
            cells[p]=if(p==hottest)'*' else ('0'.code+digit).toChar()
        }
        val lines=(0 until m.height).map {
            r->cells.concatToString(r*m.width,(r+1)*m.width)
        }
        return MapImage(counts,lines)
    }
    fun write(name: String,lines: List<String>) {
        File("output").mkdirs();
        File("output",name).writeText(lines.joinToString("\n")+"\n")
    }
}
