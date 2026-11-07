typealias EpidemicRate=(DoubleArray,Double)->DoubleArray

object Models {
    fun seird(population: Int,sigma: Double,fatality: Double,beta: Double,gamma: Double): EpidemicRate {
        return {
            y,m->val flow=beta*m*y[0]*y[2]/population;
            val progression=sigma*y[1];
            val removal=gamma*y[2];
            doubleArrayOf(-flow,flow-progression,progression-removal,(1-fatality)*gamma*y[2],fatality*gamma*y[2],progression)
        }
    }
    fun sir(population: Int,beta: Double,gamma: Double): EpidemicRate {
        return {
            y,m->val flow=beta*m*y[0]*y[1]/population;
            val removal=gamma*y[1];
            doubleArrayOf(-flow,flow-removal,removal,flow)
        }
    }
    fun age(populations: IntArray,fatalities: DoubleArray,sigma: Double,beta: Double,gamma: Double,contacts: Array<DoubleArray>): EpidemicRate {
        return {
            y,m->val result=DoubleArray(y.size)
            for(g in populations.indices) {
                val p=6*g;
                var pressure=0.0;
                for(h in populations.indices)pressure+=contacts[g][h]*y[6*h+2]/populations[h]
                val force=beta*m*pressure;
                val flow=force*y[p];
                val progression=sigma*y[p+1];
                val removal=gamma*y[p+2]
                result[p]=-flow;
                result[p+1]=flow-progression;
                result[p+2]=progression-removal;
                result[p+3]=(1-fatalities[g])*gamma*y[p+2];
                result[p+4]=fatalities[g]*gamma*y[p+2];
                result[p+5]=progression
            }
            result
        }
    }
    fun generation(sigma: Double,gamma: Double): EpidemicRate {
        return {
            y,_->val progression=sigma*y[0];
            val removal=gamma*y[1];
            doubleArrayOf(-progression,progression-removal,removal)
        }
    }
}
