object Multiclass {
    val PAIRS=arrayOf(intArrayOf(1,2),intArrayOf(1,3),intArrayOf(2,3))
    data class Classification(val restValues: DoubleArray,val pairValues: DoubleArray,val rest: Int,val pair: Int,val votes: IntArray,val tied: Boolean)
    class Models(examples: List<Dataset.Example>,kernel: Kernels.Kernel,c: Double,settings: Dataset.Settings) {
        val rest=mutableListOf<Smo.Model>();
        val pairs=mutableListOf<Smo.Model>()
        init {
            val points=Dataset.points(examples);
            val classes=Dataset.labels(examples);
            val matrix=kernel.matrix(points)
            for(k in 1..3) {
                val labels=IntArray(classes.size) {
                    if(classes[it]==k)1 else -1
                };
                rest.add(Smo.train(points,labels,kernel,matrix,c,settings))
            }
            for(pair in PAIRS) {
                val indices=classes.indices.filter {
                    classes[it]==pair[0]||classes[it]==pair[1]
                };
                val selected=indices.map {
                    points[it]
                };
                val labels=IntArray(indices.size) {
                    if(classes[indices[it]]==pair[0])1 else -1
                };
                pairs.add(Smo.train(selected,labels,kernel,Kernels.submatrix(matrix,indices),c,settings))
            }
        }
        fun classify(point: Kernels.Point): Classification {
            val rv=DoubleArray(3);
            val pv=DoubleArray(3);
            val score=DoubleArray(3);
            val votes=IntArray(3);
            var restPrediction=0
            for(i in 0..2) {
                rv[i]=rest[i].decision(point);
                if(rv[i]>rv[restPrediction])restPrediction=i
            }
            for(i in 0..2) {
                val a=PAIRS[i][0]-1;
                val b=PAIRS[i][1]-1;
                val h=pairs[i].decision(point);
                pv[i]=h;
                votes[if(h>0)a else b]++;
                score[a]+=h;
                score[b]-=h
            }
            val most=maxOf(votes[0],votes[1],votes[2]);
            var chosen=-1;
            var count=0
            for(i in 0..2)if(votes[i]==most) {
                count++;
                if(chosen<0||score[i]>score[chosen])chosen=i
            }
            return Classification(rv,pv,restPrediction+1,chosen+1,votes,count>1)
        }
    }
}
