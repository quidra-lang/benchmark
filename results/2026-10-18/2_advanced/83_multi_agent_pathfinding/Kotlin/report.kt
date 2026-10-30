import java.io.File
object Report {
    fun cell(cell:GridMap.Cell)="${cell.x},${cell.y}"
    fun name(number:Int)=('A'.code+number).toChar()
    fun actions(path:List<GridMap.Cell>):String {
        val result=StringBuilder();
        for(i in 1 until path.size) {
            val dx=path[i].x-path[i-1].x;
            val dy=path[i].y-path[i-1].y;
            result.append(when {
                dx==1->'E';
                dx == -1->'W';
                dy==1->'S';
                dy == -1->'N';
                else->'.'
            })
        }
        return result.toString()
    }
    fun conflict(c:Cbs.Conflict):String {
        val start="${c.kind} t ${c.time} ${name(c.a)} ${name(c.b)}";
        return if(c.kind=="vertex")"$start at ${c.v}" else "$start from ${c.u} to ${c.v}"
    }
    fun fraction(numerator:Int,denominator:Int):String {
        var a=numerator;
        var b=denominator;
        while(b!=0) {
            val r=a%b;
            a=b;
            b=r
        }
        return "${numerator/a}/${denominator/a}"
    }
    fun csv(values:List<String>)=values.joinToString(",")
    fun write(name:String,lines:List<String>) {
        File("output").mkdirs();
        File("output",name).writeText(lines.joinToString("\n")+"\n",Charsets.US_ASCII)
    }
}
