import java.io.File

object Dataset {
    data class Row(val id: String,val x: DoubleArray,val label: Int)
    data class Table(val names: List<String>,val rows: List<Row>)
    class Settings(val values: Map<String,List<String>>) {
        fun integer(key: String)=values.getValue(key)[0].toInt();
        fun number(key: String)=values.getValue(key)[0].toDouble();
        fun integers(key: String)=values.getValue(key).map(String::toInt).toIntArray();
        fun numbers(key: String)=values.getValue(key).map(String::toDouble).toDoubleArray();
        fun variants()=values.getValue("VARIANTS")
    }
    data class Data(val train: Table,val test: Table,val multiTrain: Table,val multiTest: Table,val settings: Settings)
    fun lines(name: String)=File("input/$name").readLines(Charsets.US_ASCII)
    fun table(lines: List<String>,multi: Boolean,role: String): Table {
        val header=lines[0].split(',');
        val count=header.size-if(multi)3 else 2;
        val names=header.subList(1,count+1);
        val rows=lines.drop(1).map {
            it.split(',')
        }.filter {
            !multi||it.last()==role
        }.map {
            w->Row(w[0],DoubleArray(count) {
                w[it+1].toDouble()
            },w[count+1].toInt())
        };
        return Table(names,rows)
    }
    fun read(): Data {
        val s=Settings(lines("params.txt").associate {
            val words=it.split(' ');
            words[0] to words.drop(1)
        });
        val multi=lines("multiclass.csv");
        return Data(table(lines("train.csv"),false,""),table(lines("test.csv"),false,""),table(multi,true,"train"),table(multi,true,"test"),s)
    }
}
