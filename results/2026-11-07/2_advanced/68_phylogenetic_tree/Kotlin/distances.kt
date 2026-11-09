import kotlin.math.ln
object Distances {
    val models=listOf("P","JC","K2P")
    data class Pair(val first: Int,val second: Int,val sites: Int,val transitions: Int,val transversions: Int)
    data class Correction(val value: Double,val saturated: Boolean)
    data class Matrix(val values: Array<DoubleArray>,val saturated: List<Pair>)
    fun pairs(sequences: List<String>,weights: IntArray): List<Pair> {
        val result=mutableListOf<Pair>();
        for(i in sequences.indices)for(j in i+1 until sequences.size) {
            var n=0;
            var s=0;
            var v=0;
            for(c in weights.indices) {
                val a=sequences[i][c];
                val b=sequences[j][c];
                if(a !in Alignment.BASES||b !in Alignment.BASES)continue;
                n+=weights[c];
                if(a!=b) {
                    if((a=='A'&&b=='G')||(a=='G'&&b=='A')||(a=='C'&&b=='T')||(a=='T'&&b=='C'))s+=weights[c] else v+=weights[c]
                }
            };
            result.add(Pair(i,j,n,s,v))
        };
        return result
    }
    fun correct(model: String,n: Int,s: Int,v: Int,replacement: Double): Correction {
        val saturated=n==0||(model=="JC"&&4*(s+v)>=3*n)||(model=="K2P"&&(2*s+v>=n||2*v>=n));
        if(saturated)return Correction(replacement,true);
        val value=when(model) {
            "P"->(s+v).toDouble()/n;
            "JC"->-0.75*ln(1-4.0*(s+v)/(3*n));
            else->-0.5*ln(1-2.0*s/n-v.toDouble()/n)-0.25*ln(1-2.0*v/n)
        };
        return Correction(value,false)
    }
    fun matrix(pairs: List<Pair>,count: Int,model: String,replacement: Double): Matrix {
        val values=Array(count) {
            DoubleArray(count)
        };
        val saturated=mutableListOf<Pair>();
        for(p in pairs) {
            val c=correct(model,p.sites,p.transitions,p.transversions,replacement);
            values[p.first][p.second]=c.value;
            values[p.second][p.first]=c.value;
            if(c.saturated)saturated.add(p)
        };
        return Matrix(values,saturated)
    }
}
