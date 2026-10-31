import kotlin.math.*

object Stumps {
    data class Stump(val feature: Int,val thresholds: DoubleArray,val values: DoubleArray) {
        fun output(x: DoubleArray): Double {
            var bin=0;
            for(threshold in thresholds)if(x[feature]>threshold)bin++;
            return values[bin]
        };
        fun magnitude(): Double {
            var result=0.0;
            for(value in values)result=maxOf(result,abs(value));
            return result
        }
    }
    data class Candidate(val stump: Stump,val error: Double,val polarity: Int)
    class Search(val rows: List<Dataset.Row>) {
        val sorted: Array<IntArray>;
        val ends: Array<IntArray>;
        val thresholds: Array<DoubleArray>
        init {
            val d=rows[0].x.size;
            val n=rows.size;
            sorted=Array(d) {
                IntArray(n)
            };
            ends=Array(d) {
                intArrayOf()
            };
            thresholds=Array(d) {
                doubleArrayOf()
            };
            for(j in 0 until d) {
                val order=(0 until n).sortedWith(compareBy<Int> {
                    rows[it].x[j]
                }.thenBy {
                    it
                });
                val distinct=mutableListOf<Double>();
                val starts=mutableListOf<Int>();
                for(i in 0 until n) {
                    sorted[j][i]=order[i];
                    val value=rows[order[i]].x[j];
                    if(i==0||value!=rows[order[i-1]].x[j]) {
                        distinct+=value;
                        starts+=i
                    }
                };
                val q=distinct.size;
                ends[j]=starts.toIntArray();
                thresholds[j]=DoubleArray(q) {
                    c->if(c==0)distinct[0]-1 else (distinct[c-1]+distinct[c])/2
                }
            }
        }
    }
    fun choose(candidates: List<Candidate>): Candidate {
        var minimum=Double.POSITIVE_INFINITY;
        for(candidate in candidates)minimum=minOf(minimum,candidate.error);
        return candidates.first {
            it.error<=minimum+0.000000001
        }
    }
    fun discrete(search: Search,weights: DoubleArray): Candidate {
        var plus=0.0;
        var minus=0.0;
        for(i in weights.indices)if(search.rows[i].label==1)plus+=weights[i] else minus+=weights[i];
        val candidates=mutableListOf<Candidate>();
        for(j in search.sorted.indices) {
            var position=0;
            var leftPlus=0.0;
            var leftMinus=0.0;
            for(c in search.thresholds[j].indices) {
                while(position<search.ends[j][c]) {
                    val i=search.sorted[j][position++];
                    if(search.rows[i].label==1)leftPlus+=weights[i] else leftMinus+=weights[i]
                };
                val threshold=search.thresholds[j][c];
                candidates+=Candidate(Stump(j,doubleArrayOf(threshold),doubleArrayOf(-1.0,1.0)),leftPlus+(minus-leftMinus),1);
                candidates+=Candidate(Stump(j,doubleArrayOf(threshold),doubleArrayOf(1.0,-1.0)),leftMinus+(plus-leftPlus),-1)
            }
        };
        return choose(candidates)
    }
    fun regression(search: Search,targets: DoubleArray,weights: DoubleArray): Candidate {
        var total=0.0;
        var s=0.0;
        var q=0.0;
        for(i in weights.indices) {
            total+=weights[i];
            s+=weights[i]*targets[i];
            q+=weights[i]*targets[i]*targets[i]
        };
        val candidates=mutableListOf<Candidate>();
        for(j in search.sorted.indices) {
            var position=0;
            var wl=0.0;
            var sl=0.0;
            for(c in search.thresholds[j].indices) {
                while(position<search.ends[j][c]) {
                    val i=search.sorted[j][position++];
                    wl+=weights[i];
                    sl+=weights[i]*targets[i]
                };
                val wr=total-wl;
                val sr=s-sl;
                val left=if(c==0)0.0 else sl/wl;
                val right=sr/wr;
                val g=if(c==0)sr*sr/wr else sl*sl/wl+sr*sr/wr;
                candidates+=Candidate(Stump(j,doubleArrayOf(search.thresholds[j][c]),doubleArrayOf(left,right)),q-g,0)
            }
        };
        return choose(candidates)
    }
    fun multiclass(search: Search,weights: DoubleArray,classes: Int): Candidate {
        var total=0.0;
        val totals=DoubleArray(classes);
        for(i in weights.indices) {
            total+=weights[i];
            totals[search.rows[i].label-1]+=weights[i]
        };
        val candidates=mutableListOf<Candidate>();
        for(j in search.sorted.indices) {
            var position=0;
            val left=DoubleArray(classes);
            for(c in search.thresholds[j].indices) {
                while(position<search.ends[j][c]) {
                    val i=search.sorted[j][position++];
                    left[search.rows[i].label-1]+=weights[i]
                };
                var a=0;
                var b=0;
                for(h in 1 until classes) {
                    if(left[h]>left[a])a=h;
                    if(totals[h]-left[h]>totals[b]-left[b])b=h
                };
                candidates+=Candidate(Stump(j,doubleArrayOf(search.thresholds[j][c]),doubleArrayOf((a+1).toDouble(),
                    (b+1).toDouble())),total-(left[a]+(totals[b]-left[b])),0)
            }
        };
        return choose(candidates)
    }
    fun cuts(search: Search,bins: Int): Array<DoubleArray> {
        val n=search.rows.size;
        return Array(search.sorted.size) {
            j->DoubleArray(bins-1) {
                b0->val b=b0+1;
                val r=b*n/bins;
                (search.rows[search.sorted[j][r-1]].x[j]+search.rows[search.sorted[j][r]].x[j])/2
            }
        }
    }
    fun real(search: Search,weights: DoubleArray,cuts: Array<DoubleArray>,bins: Int,smoothing: Double): Candidate {
        val candidates=mutableListOf<Candidate>();
        for(j in cuts.indices) {
            val plus=DoubleArray(bins);
            val minus=DoubleArray(bins);
            for(i in weights.indices) {
                var bin=0;
                for(cut in cuts[j])if(cut<search.rows[i].x[j])bin++;
                if(search.rows[i].label==1)plus[bin]+=weights[i] else minus[bin]+=weights[i]
            };
            var z=0.0;
            val values=DoubleArray(bins);
            for(bin in 0 until bins) {
                z+=sqrt(plus[bin]*minus[bin]);
                values[bin]=0.5*ln((plus[bin]+smoothing)/(minus[bin]+smoothing))
            };
            candidates+=Candidate(Stump(j,cuts[j],values),2*z,0)
        };
        return choose(candidates)
    }
}
