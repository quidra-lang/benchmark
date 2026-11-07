import kotlin.math.*

object Locator {
    const val PI=3.141592653589793
    data class Observation(val station: WaveformIo.Station,val time: Double)
    data class Iteration(val number: Int,val solution: DoubleArray,val rms: Double)
    data class Grid(val solution: DoubleArray,val rms: Double,val profile: List<Double>)
    data class Normals(val matrix: Array<DoubleArray>,val right: DoubleArray)
    data class Ellipse(val smaj: Double,val smin: Double,val az: Double,val erz: Double,val ert: Double)
    class Run(val solution: DoubleArray,val residuals: DoubleArray,val rms: Double,val trace: List<Iteration>) {
        var grid: Grid?=null
    }
    fun sq(x: Double)=x*x
    fun distance(s: DoubleArray,station: WaveformIo.Station)=sqrt(sq(s[0]-station.x)+sq(s[1]-station.y)+sq(s[2]+station.elevation))
    fun residuals(s: DoubleArray,obs: List<Observation>,v: Double)=DoubleArray(obs.size) {
        i->obs[i].time-s[3]-distance(s,obs[i].station)/v
    }
    fun rms(s: DoubleArray,obs: List<Observation>,v: Double): Double {
        var sum=0.0;
        for(value in residuals(s,obs,v))sum+=value*value;
        return sqrt(sum/obs.size)
    }
    fun grid(obs: List<Observation>,p: WaveformIo.Params): Grid {
        val rx=p.row("grid_x");
        val ry=p.row("grid_y");
        val rz=p.row("grid_z");
        val v=p.get("velocity");
        var best=Double.POSITIVE_INFINITY;
        var solution=DoubleArray(4);
        val profile=sortedMapOf<Int,Double>();
        for(x in rx[0].toInt()..rx[1].toInt() step rx[2].toInt())for(y in ry[0].toInt()..ry[1].toInt() step ry[2].toInt())for(z in rz[0].toInt()..rz[1].toInt() step rz[2].toInt()) {
            val current=doubleArrayOf(x.toDouble(),y.toDouble(),z.toDouble(),0.0);
            val delta=DoubleArray(obs.size);
            var sum=0.0;
            for(i in delta.indices) {
                delta[i]=obs[i].time-distance(current,obs[i].station)/v;
                sum+=delta[i]
            };
            current[3]=sum/delta.size;
            var error=0.0;
            for(value in delta)error+=sq(value-current[3]);
            if(error<best) {
                best=error;
                solution=current
            };
            if(z !in profile||error<profile.getValue(z))profile[z]=error
        };
        return Grid(solution,sqrt(best/obs.size),profile.values.map {
            sqrt(it/obs.size)
        })
    }
    fun cholesky(matrix: Array<DoubleArray>): Array<DoubleArray> {
        val n=matrix.size;
        val lower=Array(n) {
            DoubleArray(n)
        };
        for(a in 0 until n)for(c in 0..a) {
            var sum=0.0;
            for(k in 0 until c)sum+=lower[a][k]*lower[c][k];
            val value=matrix[a][c]-sum;
            lower[a][c]=if(a==c)sqrt(value) else value/lower[c][c]
        };
        return lower
    }
    fun solve(lower: Array<DoubleArray>,right: DoubleArray): DoubleArray {
        val n=right.size;
        val u=DoubleArray(n);
        val delta=DoubleArray(n);
        for(a in 0 until n) {
            var sum=0.0;
            for(c in 0 until a)sum+=lower[a][c]*u[c];
            u[a]=(right[a]-sum)/lower[a][a]
        };
        for(a in n-1 downTo 0) {
            var sum=0.0;
            for(c in a+1 until n)sum+=lower[c][a]*delta[c];
            delta[a]=(u[a]-sum)/lower[a][a]
        };
        return delta
    }
    fun normals(s: DoubleArray,obs: List<Observation>,v: Double): Normals {
        val matrix=Array(4) {
            DoubleArray(4)
        };
        val right=DoubleArray(4);
        val errors=residuals(s,obs,v);
        for(j in obs.indices) {
            val station=obs[j].station;
            val distance=distance(s,station);
            val g=doubleArrayOf((s[0]-station.x)/(v*distance),(s[1]-station.y)/(v*distance),(s[2]+station.elevation)/(v*distance),1.0);
            for(a in 0..3) {
                right[a]+=g[a]*errors[j];
                for(c in 0..3)matrix[a][c]+=g[a]*g[c]
            }
        };
        return Normals(matrix,right)
    }
    fun geiger(initial: DoubleArray,obs: List<Observation>,v: Double): Run {
        val s=initial.copyOf();
        val trace=mutableListOf<Iteration>();
        for(iteration in 1..8) {
            val normal=normals(s,obs,v);
            val delta=solve(cholesky(normal.matrix),normal.right);
            for(a in 0..3)s[a]+=delta[a];
            if(s[2]<0)s[2]=0.0;
            trace+=Iteration(iteration,s.copyOf(),rms(s,obs,v))
        };
        return Run(s,residuals(s,obs,v),rms(s,obs,v),trace)
    }
    fun locate(obs: List<Observation>,p: WaveformIo.Params): Run {
        val grid=grid(obs,p);
        val run=geiger(grid.solution,obs,p.get("velocity"));
        run.grid=grid;
        return run
    }
    fun ellipse(s: DoubleArray,obs: List<Observation>,v: Double): Ellipse {
        val lower=cholesky(normals(s,obs,v).matrix);
        var sum=0.0;
        for(value in residuals(s,obs,v))sum+=value*value;
        val variance=sum/(obs.size-4);
        val covariance=Array(4) {
            DoubleArray(4)
        };
        for(c in 0..3) {
            val unit=DoubleArray(4);
            unit[c]=1.0;
            val column=solve(lower,unit);
            for(a in 0..3)covariance[a][c]=variance*column[a]
        };
        val xx=covariance[0][0];
        val yy=covariance[1][1];
        val xy=covariance[0][1];
        val mu=(xx+yy)/2;
        val rho=sqrt(sq((xx-yy)/2)+xy*xy);
        val theta=atan2(2*xy,xx-yy)/2*180/PI;
        return Ellipse(sqrt(mu+rho),sqrt(mu-rho),90-theta,sqrt(covariance[2][2]),sqrt(covariance[3][3]))
    }
}
