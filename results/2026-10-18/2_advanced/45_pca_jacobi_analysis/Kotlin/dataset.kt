import java.io.File

object Dataset {
    data class Row(val id: String,val values: DoubleArray)
    data class Table(val names: List<String>,val rows: List<Row>)
    class Settings(val values: Map<String,List<String>>) {
        fun text(key: String)=values.getValue(key)[0];
        fun integer(key: String)=text(key).toInt();
        fun number(key: String)=text(key).toDouble();
        fun second(key: String)=values.getValue(key)[1].toInt()
    }
    data class Data(val data: Table,val supplementary: Table,val settings: Settings)
    fun lines(name: String)=File("input/$name").readLines(Charsets.US_ASCII)
    fun table(name: String): Table {
        val lines=lines(name);
        val names=lines[0].split(',').drop(1);
        val rows=lines.drop(1).map {
            val words=it.split(',');
            Row(words[0],DoubleArray(names.size) {
                j->if(words[j+1]=="NA")Double.NaN else words[j+1].toDouble()
            })
        };
        return Table(names,rows)
    }
    fun read()=Data(table("data.csv"),table("supplementary.csv"),Settings(lines("params.txt").associate {
        val w=it.split(' ');
        w[0] to w.drop(1)
    }))
}
