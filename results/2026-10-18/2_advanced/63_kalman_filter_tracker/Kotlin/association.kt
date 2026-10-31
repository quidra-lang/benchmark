object Association {
    data class Pair(val row: Int,val column: Int)
    val order=compareBy<Pair> {
        it.row
    }.thenBy {
        it.column
    }
    fun minimum(costs: Array<DoubleArray>): List<Pair> {
        val result=mutableListOf<Pair>();
        if(costs.isEmpty()||costs[0].isEmpty())return result;
        val transpose=costs.size>costs[0].size;
        val a=if(transpose)Matrix.transpose(costs) else costs;
        val rows=a.size;
        val columns=a[0].size;
        val u=DoubleArray(rows+1);
        val v=DoubleArray(columns+1);
        val matched=IntArray(columns+1);
        val previous=IntArray(columns+1)
        for(row in 1..rows) {
            matched[0]=row;
            var column=0;
            val distances=DoubleArray(columns+1) {
                Double.POSITIVE_INFINITY
            };
            val used=BooleanArray(columns+1)
            do {
                used[column]=true;
                val current=matched[column];
                var following=0;
                var delta=Double.POSITIVE_INFINITY;
                for(candidate in 1..columns)if(!used[candidate]) {
                    val reduced=a[current-1][candidate-1]-u[current]-v[candidate];
                    if(reduced<distances[candidate]) {
                        distances[candidate]=reduced;
                        previous[candidate]=column
                    };
                    if(distances[candidate]<delta) {
                        delta=distances[candidate];
                        following=candidate
                    }
                }
                for(candidate in 0..columns)if(used[candidate]) {
                    u[matched[candidate]]+=delta;
                    v[candidate]-=delta
                } else distances[candidate]-=delta;
                column=following
            }
            while(matched[column]!=0)
            while(column!=0) {
                val following=previous[column];
                matched[column]=matched[following];
                column=following
            }
        }
        for(c in 1..columns)if(matched[c]!=0)result.add(if(transpose)Pair(c-1,matched[c]-1) else Pair(matched[c]-1,c-1));
        result.sortWith(order);
        return result
    }
    fun optimal(costs: Array<DoubleArray>,usable: Array<BooleanArray>): List<Pair> {
        if(costs.isEmpty()||costs[0].isEmpty())return emptyList();
        var largest=1.0;
        for(r in costs.indices)for(c in costs[0].indices)if(usable[r][c])largest=maxOf(largest,costs[r][c]);
        val penalty=(minOf(costs.size,costs[0].size)+1)*(largest+1);
        val a=Array(costs.size) {
            r->DoubleArray(costs[0].size) {
                c->if(usable[r][c])costs[r][c] else penalty
            }
        };
        return minimum(a).filter {
            usable[it.row][it.column]
        }
    }
}
