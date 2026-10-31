import kotlin.math.*

class Kalman(val model: String,val q: Double,sigma: Double,velocity: Double,acceleration: Double,measurement: DoubleArray) {
    var x=DoubleArray(if(model=="CV")4 else 6);
    var p: Array<DoubleArray>;
    val h=Array(2) {
        DoubleArray(x.size)
    };
    val r=Matrix.diagonal(doubleArrayOf(sigma*sigma,sigma*sigma));
    var xp: DoubleArray?=null;
    var pp: Array<DoubleArray>?=null;
    var f: Array<DoubleArray>?=null
    data class Innovation(val residual: DoubleArray,val covariance: Array<DoubleArray>,val precision: Array<DoubleArray>,val distance: Double)
    data class Update(val distance: Double,val likelihood: Double,val covariance: Array<DoubleArray>)
    data class Snapshot(val x: DoubleArray,val p: Array<DoubleArray>,val xp: DoubleArray?,val pp: Array<DoubleArray>?,val f: Array<DoubleArray>?)
    init {
        x[0]=measurement[0];
        x[1]=measurement[1];
        val variance=DoubleArray(x.size);
        variance[0]=sigma*sigma;
        variance[1]=sigma*sigma;
        variance[2]=velocity;
        variance[3]=velocity;
        if(x.size==6) {
            variance[4]=acceleration;
            variance[5]=acceleration
        };
        p=Matrix.diagonal(variance);
        h[0][0]=1.0;
        h[1][1]=1.0
    }
    fun predict(interval: Double) {
        val transition=transition(model,interval);
        f=transition;
        x=Matrix.product(transition,x);
        p=Matrix.add(Matrix.product(Matrix.product(transition,p),Matrix.transpose(transition)),processNoise(model,interval,q));
        xp=x;
        pp=p
    }
    fun innovation(measurement: DoubleArray): Innovation {
        val nu=Matrix.subtract(measurement,Matrix.product(h,x));
        val s=Matrix.add(Matrix.product(Matrix.product(h,p),Matrix.transpose(h)),r);
        val si=Matrix.inverse(s);
        return Innovation(nu,s,si,Matrix.quadratic2(nu,si))
    }
    fun update(measurement: DoubleArray,v: Innovation=innovation(measurement)): Update {
        val k=Matrix.product(Matrix.product(p,Matrix.transpose(h)),v.precision);
        val j=Matrix.subtract(Matrix.identity(x.size),Matrix.product(k,h));
        x=Matrix.add(x,Matrix.product(k,v.residual));
        p=Matrix.add(Matrix.product(Matrix.product(j,p),Matrix.transpose(j)),Matrix.product(Matrix.product(k,r),Matrix.transpose(k)));
        val likelihood=-ln(2*PI)-ln(Matrix.determinant2(v.covariance))/2-v.distance/2;
        return Update(v.distance,likelihood,v.covariance)
    }
    fun snapshot()=Snapshot(x,p,xp,pp,f)
    companion object {
        fun transition(model: String,t: Double): Array<DoubleArray> {
            val f=Matrix.identity(if(model=="CV")4 else 6);
            f[0][2]=t;
            f[1][3]=t;
            if(model=="CA") {
                f[0][4]=t*t/2;
                f[1][5]=t*t/2;
                f[2][4]=t;
                f[3][5]=t
            };
            return f
        }
        fun processNoise(model: String,t: Double,q: Double): Array<DoubleArray> {
            val ca=model=="CA";
            val result=Array(if(ca)6 else 4) {
                DoubleArray(if(ca)6 else 4)
            };
            val rows=if(ca)intArrayOf(0,0,0,2,2,4) else intArrayOf(0,0,2);
            val cols=if(ca)intArrayOf(0,2,4,2,4,4) else intArrayOf(0,2,2);
            val values=if(ca)doubleArrayOf(q*t*t*t*t*t/20,q*t*t*t*t/8,q*t*t*t/6,q*t*t*t/3,q*t*t/2,q*t) else doubleArrayOf(q*t*t*t/3,q*t*t/2,q*t);
            for(axis in 0..1)for(k in values.indices) {
                result[rows[k]+axis][cols[k]+axis]=values[k];
                result[cols[k]+axis][rows[k]+axis]=values[k]
            };
            return result
        }
        fun smooth(history: List<Snapshot>): List<DoubleArray> {
            val states=MutableList(history.size) {
                DoubleArray(0)
            };
            states[history.lastIndex]=history.last().x;
            for(i in history.size-2 downTo 0) {
                val current=history[i];
                val next=history[i+1];
                val gain=Matrix.product(Matrix.product(current.p,Matrix.transpose(next.f!!)),Matrix.inverse(next.pp!!));
                states[i]=Matrix.add(current.x,Matrix.product(gain,Matrix.subtract(states[i+1],next.xp!!)))
            };
            return states
        }
    }
}
