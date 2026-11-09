import java.io.File

object SignalIo {
    class Params(val values: Map<String,List<String>>) {
        fun integer(key: String,i: Int=0)=values.getValue(key)[i].toInt();
        fun get(key: String,i: Int=0)=values.getValue(key)[i].toDouble();
        fun word(key: String,i: Int=0)=values.getValue(key)[i];
        fun row(key: String)=values.getValue(key).map(String::toDouble).toDoubleArray()
    }
    data class Data(val fs: Int,val first: DoubleArray,val second: DoubleArray,val params: Params)
    fun lines(name: String)=File("input/$name").readLines(Charsets.US_ASCII)
    fun read(): Data {
        val input=lines("signal.csv");
        val header=input[0].split(',').map(String::toInt);
        val first=DoubleArray(header[1]);
        val second=DoubleArray(header[1]);
        for(i in first.indices) {
            val w=input[i+1].split(',');
            first[i]=w[0].toDouble();
            second[i]=w[1].toDouble()
        };
        val params=lines("params.txt").associate {
            val w=it.split(' ');
            w[0] to w.drop(1)
        };
        return Data(header[0],first,second,Params(params))
    }
}
