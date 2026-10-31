import kotlin.math.sqrt

object Factorization {
    class Generator(seed: Int) {
        var state=seed.toLong();
        fun draw(): Long {
            state=48271*state%2147483647;
            return state
        };
        fun factor()=((draw()%2001)-1000)/10000.0
    }
    data class Log(val method: String,val epoch: Int,val rmse: Double)
    class Model(val mean: Double,val users: Array<DoubleArray>,val items: Array<DoubleArray>,val userBias: DoubleArray,val itemBias: DoubleArray) {
        val log=mutableListOf<Log>();
        fun predict(u: Int,i: Int)=((mean+userBias[u])+itemBias[i])+dot(users[u],items[i])
    }
    fun dot(a: DoubleArray,b: DoubleArray): Double {
        var sum=0.0;
        for(f in a.indices)sum+=a[f]*b[f];
        return sum
    }
    fun rmse(data: Ratings.Data,model: Model): Double {
        var sum=0.0;
        for(row in data.training) {
            val e=row.rating-model.predict(row.user,row.item);
            sum+=e*e
        };
        return sqrt(sum/data.training.size)
    }
    fun svd(d: Ratings.Data): Model {
        val factors=d.settings.integer("FACTORS");
        val random=Generator(d.settings.integer("SEED"));
        val userFactors=Array(d.users.size) {
            DoubleArray(factors) {
                random.factor()
            }
        };
        val itemFactors=Array(d.items.size) {
            DoubleArray(factors) {
                random.factor()
            }
        };
        val m=Model(d.mean,userFactors,itemFactors,DoubleArray(d.users.size),DoubleArray(d.items.size));
        val order=IntArray(d.training.size) {
            it
        };
        val rate=d.settings.number("LEARNING_RATE");
        val regularization=d.settings.number("REGULARIZATION");
        for(epoch in 1..d.settings.integer("EPOCHS")) {
            for(t in order.size-1 downTo 1) {
                val other=(random.draw()%(t+1)).toInt();
                val temporary=order[t];
                order[t]=order[other];
                order[other]=temporary
            };
            for(position in order) {
                val row=d.training[position];
                val u=row.user;
                val i=row.item;
                val e=row.rating-m.predict(u,i);
                m.userBias[u]+=rate*(e-regularization*m.userBias[u]);
                m.itemBias[i]+=rate*(e-regularization*m.itemBias[i]);
                for(f in 0 until factors) {
                    val a=m.users[u][f];
                    val b=m.items[i][f];
                    m.users[u][f]=a+rate*(e*b-regularization*a);
                    m.items[i][f]=b+rate*(e*a-regularization*b)
                }
            };
            m.log+=Log("SVD",epoch,rmse(d,m))
        };
        return m
    }
    fun solve(a: Array<DoubleArray>,w: DoubleArray): DoubleArray {
        val n=w.size;
        val l=Array(n) {
            DoubleArray(n)
        };
        for(row in 0 until n)for(col in 0..row) {
            var sum=0.0;
            for(t in 0 until col)sum+=l[row][t]*l[col][t];
            val s=a[row][col]-sum;
            l[row][col]=if(row==col)sqrt(s) else s/l[col][col]
        };
        val z=DoubleArray(n);
        val x=DoubleArray(n);
        for(row in 0 until n) {
            var sum=0.0;
            for(t in 0 until row)sum+=l[row][t]*z[t];
            z[row]=(w[row]-sum)/l[row][row]
        };
        for(row in n-1 downTo 0) {
            var sum=0.0;
            for(t in row+1 until n)sum+=l[t][row]*x[t];
            x[row]=(z[row]-sum)/l[row][row]
        };
        return x
    }
    fun vector(indices: List<Int>,vectors: Array<DoubleArray>,residuals: DoubleArray,factors: Int,regularization: Double): DoubleArray {
        val a=Array(factors) {
            DoubleArray(factors)
        };
        val w=DoubleArray(factors);
        for(index in indices)for(row in 0 until factors) {
            w[row]+=residuals[index]*vectors[index][row];
            for(col in 0 until factors)a[row][col]+=vectors[index][row]*vectors[index][col]
        };
        for(row in 0 until factors)a[row][row]+=regularization*indices.size;
        return solve(a,w)
    }
    fun als(d: Ratings.Data,userBias: DoubleArray,itemBias: DoubleArray): Model {
        val factors=d.settings.integer("FACTORS");
        val random=Generator(d.settings.integer("SEED"));
        val m=Model(d.mean,Array(d.users.size) {
            DoubleArray(factors)
        },Array(d.items.size) {
            DoubleArray(factors) {
                random.factor()
            }
        },userBias,itemBias);
        val residuals=Array(d.users.size) {
            DoubleArray(d.items.size)
        };
        for(row in d.training)residuals[row.user][row.item]=row.rating-((d.mean+userBias[row.user])+itemBias[row.item]);
        for(iteration in 1..d.settings.integer("ALS_ITERATIONS")) {
            for(u in d.users.indices)m.users[u]=vector(d.byUser[u],m.items,residuals[u],factors,d.settings.number("ALS_REG"));
            for(i in d.items.indices) {
                val column=DoubleArray(d.users.size) {
                    residuals[it][i]
                };
                m.items[i]=vector(d.byItem[i],m.users,column,factors,d.settings.number("ALS_REG"))
            };
            m.log+=Log("ALS",iteration,rmse(d,m))
        };
        return m
    }
}
