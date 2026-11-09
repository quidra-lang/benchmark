import java.io.File

object Report {
    fun fraction(a: Long,b: Long): String {
        var x=a;
        var y=b;
        while(y!=0L) {
            val rest=x%y;
            x=y;
            y=rest
        };
        return "${a/x}/${b/x}"
    }
    fun ids(objects: List<Dataset.Obj>)=if(objects.isEmpty())"-" else objects.joinToString(" ") {
        it.id.toString()
    }
    fun write(name: String,lines: List<String>) {
        File("output/$name").writeText(lines.joinToString("\n",postfix="\n"),Charsets.US_ASCII)
    }
}
