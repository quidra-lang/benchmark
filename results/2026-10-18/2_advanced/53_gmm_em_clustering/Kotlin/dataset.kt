import java.io.File

object Dataset {
    data class Point(val id: String,val x: Double,val y: Double)
    class Params(val values: Map<String,List<String>>) {
        fun integer(key: String)=values.getValue(key)[0].toInt();
        fun get(key: String)=values.getValue(key)[0].toDouble();
        fun words(key: String)=values.getValue(key);
        fun row(key: String)=values.getValue(key).map(String::toDouble).toDoubleArray()
    }
    data class Data(val points: List<Point>,val initial: Map<Int,Em.Model>,val params: Params)
    fun lines(name: String)=File("input/$name").readLines(Charsets.US_ASCII)
    fun read(): Data {
        val points=lines("points.csv").drop(1).map {
            val w=it.split(',');
            Point(w[0],w[1].toDouble(),w[2].toDouble())
        };
        val initial=mutableMapOf<Int,Em.Model>();
        val input=lines("init.txt");
        var cursor=0;
        while(cursor<input.size) {
            if(input[cursor].isEmpty()) {
                cursor++;
                continue
            };
            val k=input[cursor++].split(' ')[1].toInt();
            val model=Em.Model(k);
            val weights=input[cursor++].split(' ');
            for(j in 0 until k)model.weights[j]=weights[j+1].toDouble();
            for(j in 0 until k) {
                val w=input[cursor++].split(' ');
                model.means[j][0]=w[2].toDouble();
                model.means[j][1]=w[3].toDouble();
                for(c in 0..2)model.cov[j][c]=w[c+4].toDouble()
            };
            initial[k]=model
        };
        val values=lines("params.txt").associate {
            val w=it.split(' ');
            w[0] to w.drop(1)
        };
        return Data(points,initial,Params(values))
    }
}
