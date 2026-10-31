import java.io.File
import java.util.Locale
object ImageIo {
    data class Image(val width: Int,val height: Int,val pixels: IntArray)
    data class Plane(val width: Int,val height: Int,val pixels: IntArray)
    data class Tables(val transform: IntArray,val basic: Array<IntArray>,val huffman: CodeTables)
    class Parameters {
        val values=mutableMapOf<String,List<String>>();
        fun integer(name: String)=values.getValue(name)[0].toInt();
        fun text(name: String)=values.getValue(name)[0];
        fun integers(name: String)=values.getValue(name).map {
            it.toInt()
        }.toIntArray()
    }
    fun parse(line: String)=line.split(' ').map {
        it.toInt()
    }.toIntArray()
    fun lines(name: String)=File("input",name).readLines()
    fun readImage(): Image {
        val lines=lines("image.ppm");
        val size=parse(lines[1]);
        val pixels=IntArray(3*size[0]*size[1]);
        for(y in 0 until size[1]) {
            val row=parse(lines[y+3]);
            row.copyInto(pixels,3*y*size[0])
        };
        return Image(size[0],size[1],pixels)
    }
    fun parameters(): Parameters {
        val p=Parameters();
        for(line in lines("params.txt")) {
            val w=line.split(' ');
            p.values[w[0]]=w.drop(1)
        };
        return p
    }
    fun tables(): Tables {
        val lines=lines("tables.txt");
        val c=IntArray(64);
        val basic=Array(2) {
            IntArray(64)
        };
        for(y in 0..7) {
            parse(lines[y+1]).copyInto(c,8*y);
            for(t in 0..1)parse(lines[10+9*t+y]).copyInto(basic[t],8*y)
        };
        val tables=Array(2) {
            arrayOfNulls<Entropy.Table>(16)
        };
        for(i in 27 until 39 step 3) {
            val key=lines[i].split(' ');
            tables[key[1].toInt()][key[2].toInt()]=Entropy.Table(parse(lines[i+1]),parse(lines[i+2]))
        };
        return Tables(c,basic,tables)
    }
    fun readHex(): IntArray {
        val s=lines("stream.hex").joinToString("");
        return IntArray(s.length/2) {
            s.substring(2*it,2*it+2).toInt(16)
        }
    }
    fun text(name: String,lines: List<String>) {
        File("output").mkdirs();
        File("output",name).writeText(lines.joinToString("\n")+"\n")
    }
    fun writeImage(name: String,image: Image) {
        val lines=mutableListOf("P3","${image.width} ${image.height}","255");
        for(y in 0 until image.height)lines.add((0 until 3*image.width).joinToString(" ") {
            image.pixels[3*y*image.width+it].toString()
        });
        text(name,lines)
    }
    fun writeHex(name: String,data: IntArray) {
        val lines=mutableListOf<String>();
        for(i in data.indices step 32)lines.add((i until minOf(i+32,data.size)).joinToString("") {
            String.format(Locale.ROOT,"%02x",data[it])
        });
        text(name,lines)
    }
}
