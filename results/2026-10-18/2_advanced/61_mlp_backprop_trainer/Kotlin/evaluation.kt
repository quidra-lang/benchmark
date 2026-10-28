import java.util.Locale

object Evaluation {
    fun real(value: Double,digits: Int): String {
        val s=String.format(Locale.ROOT,"%.${digits}f",value);
        return if(s.startsWith("-")&&s.toDouble()==0.0)s.substring(1) else s
    }
    fun ratio(a: Int,b: Int): String {
        if(b==0)return "-";
        val q=(20000*a+b)/(2*b);
        return "${q/10000}.${(q%10000).toString().padStart(4,'0')}"
    }
    fun prediction(scores: DoubleArray): Int {
        var selected=0;
        for(k in 1 until scores.size)if(scores[k]>scores[selected])selected=k;
        return selected
    }
    fun second(scores: DoubleArray,first: Int): Int {
        var selected=-1;
        for(k in scores.indices)if(k!=first&&(selected<0||scores[k]>scores[selected]))selected=k;
        return selected
    }
    fun confusion(images: List<Dataset.Image>,passes: List<Network.Pass>,classes: Int): Array<IntArray> {
        val counts=Array(classes) {
            IntArray(classes)
        };
        for(i in images.indices)counts[images[i].label][prediction(passes[i].scores)]++;
        return counts
    }
    fun confusionLines(counts: Array<IntArray>): List<String> {
        val lines=mutableListOf<String>();
        val classes=counts.size
        for(k in 0 until classes)lines.add("$k: "+counts[k].joinToString(" "))
        for(k in 0 until classes) {
            var support=0;
            var predicted=0;
            for(j in 0 until classes) {
                support+=counts[k][j];
                predicted+=counts[j][k]
            };
            lines.add("class $k support $support predicted $predicted precision ${ratio(counts[k][k],predicted)} recall ${ratio(counts[k][k],support)} f1 ${ratio(2*counts[k][k],support+predicted)}")
        }
        return lines
    }
    fun maps(levels: Array<IntArray>,width: Int,height: Int)=(0 until height).map {
        r->levels.joinToString(" ") {
            level->(0 until width).joinToString("") {
                c->level[r*width+c].toString()
            }
        }
    }
    fun image(image: Dataset.Image,width: Int,height: Int)=(0 until height).map {
        r->(0 until width).joinToString("") {
            c->if(image.pixels[r*width+c]=='1')"#" else "."
        }
    }
}
