import java.io.File
import java.util.Locale

object Evaluation {
    data class Fold(val train: List<Int>,val test: List<Int>)
    data class Counts(val tp: Int,val fp: Int,val tn: Int,val fn: Int) {
        fun correct()=tp+tn
    }
    fun sign(value: Double)=if(value>0)1 else -1
    fun folds(size: Int,count: Int)=(0 until count).map {
        k->Fold((0 until size).filter {
            it%count!=k
        },(0 until size).filter {
            it%count==k
        })
    }
    fun correct(labels: IntArray,values: DoubleArray)=labels.indices.count {
        sign(values[it])==labels[it]
    }
    fun counts(labels: IntArray,values: DoubleArray): Counts {
        var tp=0;
        var fp=0;
        var tn=0;
        var fn=0;
        for(i in labels.indices)if(labels[i]==1) {
            if(sign(values[i])==1)tp++ else fn++
        } else {
            if(sign(values[i])==1)fp++ else tn++
        };
        return Counts(tp,fp,tn,fn)
    }
    fun auc(labels: IntArray,values: DoubleArray): Double {
        val positives=labels.count {
            it==1
        };
        val negatives=labels.count {
            it== -1
        };
        var sum=0.0;
        for(i in labels.indices)if(labels[i]==1)for(j in labels.indices)if(labels[j]== -1) {
            if(values[i]>values[j])sum+=1.0 else if(values[i]==values[j])sum+=0.5
        };
        return sum/(positives*negatives)
    }
    fun confusion(classes: IntArray,predictions: IntArray): Array<IntArray> {
        val matrix=Array(3) {
            IntArray(3)
        };
        for(i in classes.indices)matrix[classes[i]-1][predictions[i]-1]++;
        return matrix
    }
    fun confusionLines(matrix: Array<IntArray>): List<String> {
        val lines=matrix.map {
            it.joinToString(" ")
        }.toMutableList();
        for(i in 0..2) {
            var column=0;
            var row=0;
            for(j in 0..2) {
                column+=matrix[j][i];
                row+=matrix[i][j]
            };
            lines.add("class ${i+1} precision ${ratio(matrix[i][i],column)} recall ${ratio(matrix[i][i],row)}")
        };
        return lines
    }
    fun fixed(value: Double,decimals: Int): String {
        val s=String.format(Locale.ROOT,"%.${decimals}f",value);
        return if(s.startsWith("-")&&s.toDouble()==0.0)s.substring(1) else s
    }
    fun ratio(p: Int,q: Int)=if(q==0)"-" else fixed(p.toDouble()/q,4)
    fun write(name: String,lines: List<String>) {
        File("output").mkdirs();
        File("output",name).writeText(lines.joinToString("\n")+"\n")
    }
}
