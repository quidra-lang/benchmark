import java.io.File

object Dataframe {
    data class Row(val number: Int,val values: Map<String,String?>) {
        fun numeric(name: String)=values[name]?.toDouble()?:Double.NaN
    }
    class Frame(val columns: List<String>,val rows: List<Row>)
    class Settings(val values: Map<String,List<String>>) {
        fun number(key: String)=values.getValue(key)[0].toDouble();
        fun integer(key: String)=values.getValue(key)[0].toInt();
        fun width()=values.getValue("PLOT")[0].toInt();
        fun height()=values.getValue("PLOT")[1].toInt();
        fun limit()=values.getValue("PLOT")[2].toDouble()
    }
    data class Data(val frame: Frame,val predictions: Frame,val categorical: Set<String>,val models: List<String>,val settings: Settings)
    fun lines(name: String)=File("input/$name").readLines(Charsets.US_ASCII)
    fun readFrame(name: String): Frame {
        val lines=lines(name);
        val columns=lines[0].split(',');
        val rows=lines.drop(1).mapIndexed {
            index,line->val words=line.split(',');
            Row(index+1,columns.indices.associate {
                columns[it] to words[it].takeUnless {
                    v->v=="NA"
                }
            })
        };
        return Frame(columns,rows)
    }
    fun read(): Data {
        val frame=readFrame("data.csv");
        val categorical=frame.columns.filter {
            column->frame.rows.any {
                row->row.values[column]?.let { it[0] in 'A'..'Z' } == true
            }
        }.toSet();
        val settings=Settings(lines("params.txt").associate {
            val w=it.split(' ');
            w[0] to w.drop(1)
        });
        return Data(frame,readFrame("predict.csv"),categorical,lines("model.txt"),settings)
    }
}
