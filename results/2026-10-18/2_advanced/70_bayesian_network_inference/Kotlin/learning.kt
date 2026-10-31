import kotlin.math.ln
object Learning {
    fun total(values: DoubleArray): Double {
        var total=0.0;
        for(value in values)total+=value;
        return total
    }
    fun parentRow(parents: List<Int>,assignment: IntArray,sizes: IntArray): Int {
        var row=0;
        for(parent in parents)row=row*sizes[parent]+assignment[parent];
        return row
    }
    fun counts(variable: Int,parents: List<Int>,samples: List<IntArray>,sizes: IntArray): Array<IntArray> {
        var rows=1;
        for(parent in parents)rows*=sizes[parent];
        val counts=Array(rows) {
            IntArray(sizes[variable])
        };
        for(sample in samples)counts[parentRow(parents,sample,sizes)][sample[variable]]++;
        return counts
    }
    fun learn(counts: Array<IntArray>,alpha: Double): Array<DoubleArray> {
        val cpt=Array(counts.size) {
            DoubleArray(counts[0].size)
        };
        for(r in counts.indices) {
            var total=0.0;
            for(count in counts[r])total+=count+alpha;
            for(s in counts[r].indices)cpt[r][s]=(counts[r][s]+alpha)/total
        };
        return cpt
    }
    fun likelihood(counts: Array<IntArray>,cpt: Array<DoubleArray>): Double {
        var result=0.0;
        for(r in counts.indices)for(s in counts[r].indices)if(counts[r][s]>0)result+=counts[r][s]*ln(cpt[r][s]);
        return result
    }
    fun parameters(counts: Array<IntArray>)=counts.size*(counts[0].size-1)
    fun familyScore(variable: Int,parentSet: Collection<Int>,samples: List<IntArray>,sizes: IntArray,
        alpha: Double): Double {
        val observed=counts(variable,parentSet.sorted(),samples,sizes);
        return likelihood(observed,learn(observed,alpha))-parameters(observed)*ln(samples.size.toDouble())/2
    }
}
