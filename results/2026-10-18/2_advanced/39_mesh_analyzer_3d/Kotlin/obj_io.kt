import java.io.File

object ObjIo {
    data class Polygon(val number: Int,val line: Int,val group: String,val v: IntArray)
    data class Error(val line: Int,val kind: String)
    data class Face(val triangle: Int,val polygon: Int,val line: Int,val group: String,val v: IntArray) {
        fun duplicate()=copy(v=v.copyOf())
    }
    class Model {
        var lines=0;
        var ignored=0;
        val vertices=mutableListOf(Measure.Vec(0,0,0));
        val polygons=mutableListOf<Polygon>();
        val errors=mutableListOf<Error>()
    }
    private val integer=Regex("-?[0-9]+")
    fun read(): Model {
        val m=Model();
        var group="default";
        val lines=File("input/model.obj").readLines(Charsets.US_ASCII);
        m.lines=lines.size
        for((i,text) in lines.withIndex()) {
            if(text.isEmpty()||text.startsWith("#"))continue;
            val w=text.split(' ')
            when(w[0]) {
                "v"->if(w.size!=4||w.drop(1).any {
                    !integer.matches(it)
                })m.errors+=Error(i+1,"bad_vertex") else m.vertices+=Measure.Vec(w[1].toLong(),w[2].toLong(),w[3].toLong())
                "f"-> {
                    if(w.size<4) {
                        m.errors+=Error(i+1,"short_face");
                        continue
                    };
                    val v=IntArray(w.size-1);
                    var error: String?=null
                    for(j in 1 until w.size) {
                        val word=w[j].substringBefore('/');
                        if(!integer.matches(word)) {
                            error="bad_index";
                            break
                        };
                        var number=word.toLongOrNull();
                        if(number==null) {
                            error="out_of_range";
                            break
                        };
                        if(number==0L) {
                            error="bad_index";
                            break
                        };
                        if(number<0)number+=m.vertices.size;
                        if(number<1||number>=m.vertices.size) {
                            error="out_of_range";
                            break
                        };
                        v[j-1]=number.toInt()
                    }
                    if(error!=null)m.errors+=Error(i+1,error) else m.polygons+=Polygon(m.polygons.size+1,i+1,group,v)
                }
                "g"->group=if(w.size>1)w[1] else "default"
                "vt","vn","s","o","usemtl","mtllib"->m.ignored++
                else->m.errors+=Error(i+1,"unknown_keyword")
            }
        };
        return m
    }
    fun repaired(p: List<Measure.Vec>,f: List<Face>): List<String> {
        val lines=mutableListOf("# vertices ${p.size-1} faces ${f.size}");
        for(i in 1 until p.size)lines+="v ${p[i]}";
        var previous="";
        for(face in f) {
            if(face.group!=previous) {
                lines+="g ${face.group}";
                previous=face.group
            };
            lines+="f ${face.v.joinToString(" ")}"
        };
        return lines
    }
}
