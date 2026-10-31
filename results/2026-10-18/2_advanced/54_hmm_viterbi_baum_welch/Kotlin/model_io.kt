import java.io.File
import java.math.BigDecimal
import java.math.RoundingMode

object ModelIo {
    class Model(val name: String,val states: CharArray,val symbols: CharArray,val missing: Char,pi: DoubleArray,a: Array<DoubleArray>,b: Array<DoubleArray>) {
        val pi=normalize(pi);
        val a=Array(a.size) {
            normalize(a[it])
        };
        val b=Array(b.size) {
            normalize(b[it])
        }
    }
    data class Data(val model: Model,val sequences: List<String>,val labeled: List<String>,val params: Map<String,List<String>>)
    fun normalize(values: DoubleArray): DoubleArray {
        var sum=0.0;
        for(value in values)sum+=value;
        return DoubleArray(values.size) {
            values[it]/sum
        }
    }
    fun lines(name: String)=File("input/$name").readLines(Charsets.US_ASCII)
    fun numbers(words: List<String>,start: Int)=words.drop(start).map(String::toDouble).toDoubleArray()
    fun letters(line: String)=line.split(' ').drop(1).map {
        it[0]
    }.toCharArray()
    fun read(): Data {
        val input=lines("model.txt");
        val states=letters(input[0]);
        val symbols=letters(input[1]);
        val missing=input[2].split(' ')[1][0];
        val k=states.size;
        val pi=numbers(input[3].split(' '),1);
        val a=Array(k) {
            numbers(input[4+it].split(' '),2)
        };
        val b=Array(k) {
            numbers(input[4+k+it].split(' '),2)
        };
        val params=lines("params.txt").associate {
            val words=it.split(' ');
            words[0] to words.drop(1)
        };
        return Data(Model("INITIAL",states,symbols,missing,pi,a,b),lines("sequences.txt"),lines("labeled.txt"),params)
    }
    fun real(value: Double,digits: Int): String {
        if(value.isNaN())return "-";
        var result=BigDecimal.valueOf(value).setScale(digits,RoundingMode.HALF_UP);
        if(result.signum()==0)result=BigDecimal.ZERO.setScale(digits);
        return result.toPlainString()
    }
    fun f(value: Double)=real(value,4)
    fun values(values: DoubleArray)=values.joinToString("") {
        " ${f(it)}"
    }
    fun names(names: CharArray)=names.joinToString("") {
        " $it"
    }
    fun format(model: Model): List<String> {
        val out=mutableListOf("MODEL ${model.name}","STATES${names(model.states)}","SYMBOLS${names(model.symbols)}",
            "MISSING ${model.missing}","INITIAL${values(model.pi)}");
        for(i in model.states.indices)out+="TRANSITION ${model.states[i]}${values(model.a[i])}";
        for(i in model.states.indices)out+="EMISSION ${model.states[i]}${values(model.b[i])}";
        return out
    }
    fun write(name: String,lines: List<String>) {
        File("output/$name").writeText(lines.joinToString("\n",postfix="\n"),Charsets.US_ASCII)
    }
}
