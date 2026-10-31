import java.io.File
import java.time.LocalDate
object SchemaIo {
    val types=listOf("INT","STRING","BOOL","DATE")
    sealed interface Value
    data class NumberValue(val value: Long): Value
    data class TextValue(val value: String): Value
    data class BoolValue(val value: Boolean): Value
    data object Unknown: Value
    data class Column(val name: String,val kind: String,val nullable: Boolean)
    data class Options(val rowGroupSize: Int,val pageSize: Int,val dictionaryLimit: Int,val encodings: Map<String,String>)
    data class Inputs(val columns: List<Column>,val rows: List<Array<Value?>>,val options: Options,val queries: List<String>,
        val damaged: ByteArray)
    fun dayNumber(text: String)=LocalDate.parse(text).toEpochDay().toInt()
    fun parseValue(kind: String,field: String): Value?=if(field.isEmpty())null else when(kind) {
        "INT"->NumberValue(field.toLong());
        "DATE"->NumberValue(dayNumber(field).toLong());
        "BOOL"->BoolValue(field=="true");
        else->TextValue(field)
    }
    fun compare(a: Value?,b: Value?): Int {
        if(a===b)return 0;
        if(a==null)return -1;
        if(b==null)return 1;
        return when(a) {
            is NumberValue->a.value.compareTo((b as NumberValue).value);
            is TextValue->a.value.compareTo((b as TextValue).value);
            is BoolValue->a.value.compareTo((b as BoolValue).value);
            Unknown->0
        }
    }
    fun valueText(kind: String,value: Value?,nullText: String="NULL"): String=when(value) {
        null->nullText;
        is NumberValue->if(kind=="DATE")LocalDate.ofEpochDay(value.value).toString() else value.value.toString();
        is BoolValue->if(value.value)"true" else "false";
        is TextValue->value.value;
        Unknown->"?"
    }
    fun read(name: String)=File("input/$name").readLines(Charsets.US_ASCII)
    fun readInputs(): Inputs {
        val columns=read("schema.txt").map {
            val f=it.split(' ');
            Column(f[0],f[1],f[2]=="NULLABLE")
        };
        val rows=read("table.csv").drop(1).map {
            line->val f=line.split(',');
            Array<Value?>(columns.size) {
                parseValue(columns[it].kind,f[it])
            }
        };
        val options=read("options.txt");
        val encodings=options.drop(3).associate {
            val f=it.split(' ');
            f[1] to f[2]
        };
        val settings=Options(options[0].split(' ')[1].toInt(),options[1].split(' ')[1].toInt(),options[2].split(' ')[1].toInt(),
            encodings);
        val damaged=read("damaged.hex").joinToString("");
        val bytes=ByteArray(damaged.length/2) {
            damaged.substring(2*it,2*it+2).toInt(16).toByte()
        };
        return Inputs(columns,rows,settings,read("queries.txt"),bytes)
    }
    fun writeOutputs(outputs: Map<String,List<String>>) {
        File("output").mkdirs();
        for((name,lines) in outputs)File("output/$name").writeText(if(lines.isEmpty())"" else lines.joinToString("\n")+"\n",
            Charsets.US_ASCII)
    }
}
