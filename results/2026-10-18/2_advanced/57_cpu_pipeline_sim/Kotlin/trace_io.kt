import java.io.File

object TraceIO {
    data class Predictor(val name: String,val scheme: String,val parameters: IntArray)
    data class Variant(val name: String,val forwarding: Boolean,val stage: String,val latency: Int)
    class Config {
        var btb=0;
        var ras=0;
        var first=0;
        var last=0;
        var top=0;
        var interval=0
        var primaryVariant="";
        var primaryPredictor=""
        val predictors=mutableListOf<Predictor>();
        val variants=mutableListOf<Variant>()
    }
    fun lines(name: String)=File("input",name).readLines()
    fun hex(value: String)=if(value.matches(Regex("[0-9a-f]{8}")))value.toInt(16) else -1
    fun register(value: String)=if(value.matches(Regex("r(?:[0-9]|[12][0-9]|3[01])")))value.substring(1).toInt() else -1
    fun read(): Config {
        val c=Config()
        for(line in lines("config.txt")) {
            val w=line.split(' ')
            when(w[0]) {
                "BTB"->c.btb=w[1].toInt()
                "RAS"->c.ras=w[1].toInt()
                "TOP"->c.top=w[1].toInt()
                "INTERVAL"->c.interval=w[1].toInt()
                "PREDICTOR"->c.predictors.add(Predictor(w[1],w[2],w.drop(3).map {
                    it.toInt()
                }.toIntArray()))
                "VARIANT"->c.variants.add(Variant(w[1],w[2]=="ON",w[3],w[4].toInt()))
                "PRIMARY"-> {
                    c.primaryVariant=w[1];
                    c.primaryPredictor=w[2]
                }
                "WINDOW"-> {
                    c.first=w[1].toInt();
                    c.last=w[2].toInt()
                }
            }
        }
        return c
    }
}
