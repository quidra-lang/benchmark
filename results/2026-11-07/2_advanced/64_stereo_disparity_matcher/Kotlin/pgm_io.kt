import java.io.File
object PgmIo {
    data class Image(val width: Int,val height: Int,val pixels: IntArray)
    class Parameters {
        val values=mutableMapOf<String,List<String>>();
        val samples=mutableListOf<IntArray>();
        fun integer(name: String)=values.getValue(name)[0].toInt();
        fun text(name: String)=values.getValue(name)[0];
        fun integers(name: String)=values.getValue(name).map {
            it.toInt()
        }.toIntArray()
    }
    fun read(name: String): Image {
        val lines=File("input",name).readLines();
        val size=lines[1].split(' ');
        val w=size[0].toInt();
        val h=size[1].toInt();
        val pixels=IntArray(w*h);
        for(y in 0 until h) {
            val row=lines[y+3].split(' ');
            for(x in 0 until w)pixels[y*w+x]=row[x].toInt()
        };
        return Image(w,h,pixels)
    }
    fun parameters(): Parameters {
        val p=Parameters();
        for(line in File("input","params.txt").readLines()) {
            val w=line.split(' ');
            if(w[0]=="sample")p.samples.add(intArrayOf(w[1].toInt(),w[2].toInt())) else p.values[w[0]]=w.drop(1)
        };
        return p
    }
    fun write(name: String,w: Int,h: Int,pixels: IntArray) {
        val lines=mutableListOf("P2","$w $h","255");
        for(y in 0 until h)lines.add((0 until w).joinToString(" ") {
            pixels[y*w+it].toString()
        });
        text(name,lines)
    }
    fun text(name: String,lines: List<String>) {
        File("output").mkdirs();
        File("output",name).writeText(lines.joinToString("\n")+"\n")
    }
}
