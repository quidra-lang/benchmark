import kotlin.math.sqrt

object Neighborhood {
    class Model(userCount: Int,itemCount: Int) {
        val users=Array(userCount) {
            DoubleArray(userCount) {
                Double.NaN
            }
        };
        val items=Array(itemCount) {
            DoubleArray(itemCount) {
                Double.NaN
            }
        };
        val userCommon=Array(userCount) {
            IntArray(userCount)
        };
        val common=Array(itemCount) {
            IntArray(itemCount)
        };
        val differences=Array(itemCount) {
            IntArray(itemCount)
        };
        var userPairs=0;
        var userUsable=0;
        var itemPairs=0;
        var itemUsable=0;
        var slopePairs=0
    }
    fun compute(d: Ratings.Data): Model {
        val users=d.users.size;
        val items=d.items.size;
        val shrinkage=d.settings.integer("SHRINKAGE");
        val threshold=d.settings.number("MIN_SIMILARITY");
        val m=Model(users,items);
        for(u in 0 until users)for(v in u+1 until users) {
            var n=0L;
            var sx=0L;
            var sy=0L;
            var sxx=0L;
            var syy=0L;
            var sxy=0L;
            for(i in 0 until items)if(d.ratings[u][i]>0&&d.ratings[v][i]>0) {
                val x=d.ratings[u][i].toLong();
                val y=d.ratings[v][i].toLong();
                n++;
                sx+=x;
                sy+=y;
                sxx+=x*x;
                syy+=y*y;
                sxy+=x*y
            };
            m.userCommon[u][v]=n.toInt();
            m.userCommon[v][u]=n.toInt();
            if(n<2)continue;
            val num=n*sxy-sx*sy;
            val dx=n*sxx-sx*sx;
            val dy=n*syy-sy*sy;
            if(dx==0L||dy==0L)continue;
            val a=(num*n)*(num*n);
            val b=dx*dy*(n+shrinkage)*(n+shrinkage);
            val sim=java.lang.Long.signum(num)*sqrt(a.toDouble()/b);
            m.users[u][v]=sim;
            m.users[v][u]=sim;
            m.userPairs++;
            if(sim>threshold)m.userUsable++
        };
        for(i in 0 until items)for(j in i+1 until items) {
            var n=0;
            var difference=0;
            var num=0.0;
            var ni=0.0;
            var nj=0.0;
            for(u in 0 until users)if(d.ratings[u][i]>0&&d.ratings[u][j]>0) {
                n++;
                difference+=d.ratings[u][i]-d.ratings[u][j];
                val x=d.ratings[u][i]-d.userMeans[u];
                val y=d.ratings[u][j]-d.userMeans[u];
                num+=x*y;
                ni+=x*x;
                nj+=y*y
            };
            m.common[i][j]=n;
            m.common[j][i]=n;
            m.differences[i][j]=difference;
            m.differences[j][i]=-difference;
            if(n>0)m.slopePairs++;
            if(n<2||ni==0.0||nj==0.0)continue;
            val sim=num/sqrt(ni*nj)*n/(n+shrinkage);
            m.items[i][j]=sim;
            m.items[j][i]=sim;
            m.itemPairs++;
            if(sim>threshold)m.itemUsable++
        };
        return m
    }
    fun select(similarities: DoubleArray,candidates: List<Int>,limit: Int)=candidates.sortedWith(compareByDescending<Int> {
        similarities[it]
    }.thenBy {
        it
    }).take(limit)
}
