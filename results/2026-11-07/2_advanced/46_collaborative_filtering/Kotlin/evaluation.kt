import kotlin.math.*

object Evaluation {
    fun clip(prediction: Double)=maxOf(1.0,minOf(5.0,prediction))
    fun rmse(errors: List<Double>): Double {
        if(errors.isEmpty())return Double.NaN;
        var sum=0.0;
        for(e in errors)sum+=e*e;
        return sqrt(sum/errors.size)
    }
    fun mae(errors: List<Double>): Double {
        if(errors.isEmpty())return Double.NaN;
        var sum=0.0;
        for(e in errors)sum+=abs(e);
        return sum/errors.size
    }
    fun weight(rank: Int)=1/(ln((rank+1).toDouble())/ln(2.0))
    data class Metrics(val hits: Int,val recall: Double,val ndcg: Double,val ap: Double,val rr: Double)
    fun ranking(ranked: List<Int>,relevant: Set<Int>,cutoff: Int): Metrics {
        var hits=0;
        var dcg=0.0;
        var ap=0.0;
        var rr=0.0;
        for(rank in 1..cutoff)if(ranked[rank-1] in relevant) {
            hits++;
            dcg+=weight(rank);
            ap+=hits.toDouble()/rank;
            if(rr==0.0)rr=1.0/rank
        };
        val ideal=minOf(cutoff,relevant.size);
        var idcg=0.0;
        for(rank in 1..ideal)idcg+=weight(rank);
        return Metrics(hits,hits.toDouble()/relevant.size,dcg/idcg,ap/ideal,rr)
    }
}
