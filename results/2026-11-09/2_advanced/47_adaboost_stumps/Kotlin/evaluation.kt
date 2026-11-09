import java.io.File
import java.util.Locale

object Evaluation {
    fun format(value: Double,digits: Int): String {
        if(value.isNaN())return "-";
        val text=String.format(Locale.ROOT,"%.${digits}f",value);
        return if(text.toDouble()==0.0&&text.startsWith('-'))text.substring(1) else text
    }
    fun real(value: Double)=format(value,4)
    fun ratio(a: Int,b: Int)=if(b>0)real(a.toDouble()/b) else "-"
    fun prediction(score: Double)=if(score>0)1 else -1
    fun auc(rows: List<Dataset.Row>,scores: DoubleArray): Double {
        var positives=0;
        var negatives=0;
        var wins=0;
        var ties=0;
        for(i in rows.indices)if(rows[i].label==1) {
            positives++;
            for(j in rows.indices)if(rows[j].label==-1) {
                if(scores[i]>scores[j])wins++ else if(scores[i]==scores[j])ties++
            }
        } else negatives++;
        return if(positives*negatives==0)Double.NaN else (2*wins+ties).toDouble()/(2*positives*negatives)
    }
    fun confusion(rows: List<Dataset.Row>,predictions: IntArray,classes: Int): Array<IntArray> {
        val result=Array(classes) {
            IntArray(classes)
        };
        for(i in rows.indices)result[rows[i].label-1][predictions[i]-1]++;
        return result
    }
    fun le(values: DoubleArray,threshold: Double)=values.count {
        it<=threshold
    }
    fun write(name: String,lines: List<String>) {
        File("output/$name").writeText(lines.joinToString("\n",postfix="\n"),Charsets.US_ASCII)
    }
}
