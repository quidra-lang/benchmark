object Factors {
    fun entries(variables: List<Int>,sizes: IntArray): Int {
        var count=1;
        for(variable in variables)count*=sizes[variable];
        return count
    }
    fun assignment(index: Int,variables: List<Int>,sizes: IntArray): IntArray {
        var row=index;
        val states=IntArray(sizes.size);
        for(i in variables.indices.reversed()) {
            val v=variables[i];
            states[v]=row%sizes[v];
            row/=sizes[v]
        };
        return states
    }
    class Factor(variables: List<Int>,val values: DoubleArray,val sizes: IntArray) {
        val variables=variables.toList();
        fun value(assignment: IntArray)=values[Learning.parentRow(variables,assignment,sizes)];
        fun reduced(evidence: IntArray): Factor {
            val remaining=variables.filter {
                evidence[it]<0
            };
            val result=DoubleArray(Factors.entries(remaining,sizes));
            for(i in result.indices) {
                val assignment=Factors.assignment(i,remaining,sizes);
                for(v in sizes.indices)if(evidence[v]>=0)assignment[v]=evidence[v];
                result[i]=value(assignment)
            };
            return Factor(remaining,result,sizes)
        };
        fun multiplied(other: Factor): Factor {
            val variables=(this.variables+other.variables).distinct().sorted();
            val result=DoubleArray(Factors.entries(variables,sizes));
            for(i in result.indices) {
                val assignment=Factors.assignment(i,variables,sizes);
                result[i]=value(assignment)*other.value(assignment)
            };
            return Factor(variables,result,sizes)
        };
        fun eliminate(variable: Int,maximize: Boolean): Factor {
            val remaining=variables.filter {
                it!=variable
            };
            val result=DoubleArray(Factors.entries(remaining,sizes));
            for(i in result.indices) {
                val assignment=Factors.assignment(i,remaining,sizes);
                var combined=if(maximize)-1.0 else 0.0;
                for(state in 0 until sizes[variable]) {
                    assignment[variable]=state;
                    val candidate=this.value(assignment);
                    combined=if(maximize)maxOf(combined,candidate) else combined+candidate
                };
                result[i]=combined
            };
            return Factor(remaining,result,sizes)
        }
    }
    fun cpt(variable: Int,parents: List<Int>,cpt: Array<DoubleArray>,sizes: IntArray): Factor {
        val variables=(parents+variable).sorted();
        val values=DoubleArray(Factors.entries(variables,sizes));
        for(i in values.indices) {
            val assignment=Factors.assignment(i,variables,sizes);
            values[i]=cpt[Learning.parentRow(parents,assignment,sizes)][assignment[variable]]
        };
        return Factor(variables,values,sizes)
    }
    fun multiply(factors: List<Factor>,sizes: IntArray): Factor {
        if(factors.isEmpty())return Factor(emptyList(),doubleArrayOf(1.0),sizes);
        var result=factors.first();
        for(factor in factors.drop(1))result=result.multiplied(factor);
        return result
    }
}
