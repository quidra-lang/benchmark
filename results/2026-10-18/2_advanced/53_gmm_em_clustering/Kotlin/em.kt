import kotlin.math.*

object Em {
    class Model(val k: Int) {
        val weights=DoubleArray(k);
        val means=Array(k) {
            DoubleArray(2)
        };
        val cov=Array(k) {
            DoubleArray(3)
        }
    }
    data class Step(val responsibilities: Array<DoubleArray>,val density: DoubleArray,val scores: Array<DoubleArray>,val loglik: Double)
    data class Run(val model: Model,val step: Step,val trace: List<Double>)
    fun adjust(source: Model,type: String): Model {
        val k=source.k;
        val result=Model(k);
        for(j in 0 until k) {
            result.weights[j]=source.weights[j];
            result.means[j]=source.means[j].copyOf();
            result.cov[j]=source.cov[j].copyOf()
        };
        when(type) {
            "TIED"-> {
                val shared=DoubleArray(3);
                for(j in 0 until k)for(c in 0..2)shared[c]+=source.weights[j]*source.cov[j][c];
                for(j in 0 until k)result.cov[j]=shared.copyOf()
            };
            "DIAG"->for(j in 0 until k)result.cov[j][1]=0.0;
            "SPHERICAL"->for(j in 0 until k) {
                val v=(source.cov[j][0]+source.cov[j][2])/2;
                result.cov[j]=doubleArrayOf(v,0.0,v)
            }
        };
        return result
    }
    fun expectation(points: List<Dataset.Point>,model: Model): Step {
        val n=points.size;
        val k=model.k;
        val r=Array(n) {
            DoubleArray(k)
        };
        val scores=Array(n) {
            DoubleArray(k)
        };
        val density=DoubleArray(n);
        var loglik=0.0;
        for(i in 0 until n) {
            val point=points[i];
            var maximum=Double.NEGATIVE_INFINITY;
            for(j in 0 until k) {
                scores[i][j]=Gaussian.logDensity(point.x,point.y,model.weights[j],model.means[j],model.cov[j]);
                maximum=maxOf(maximum,scores[i][j])
            };
            var sum=0.0;
            for(j in 0 until k) {
                r[i][j]=exp(scores[i][j]-maximum);
                sum+=r[i][j]
            };
            for(j in 0 until k)r[i][j]/=sum;
            density[i]=maximum+ln(sum);
            loglik+=density[i]
        };
        return Step(r,density,scores,loglik)
    }
    fun maximization(points: List<Dataset.Point>,step: Step,type: String,eps: Double): Model {
        val n=points.size;
        val k=step.responsibilities[0].size;
        val result=Model(k);
        val counts=DoubleArray(k);
        val scatter=Array(k) {
            DoubleArray(3)
        };
        for(j in 0 until k) {
            var x=0.0;
            var y=0.0;
            for(i in 0 until n) {
                val r=step.responsibilities[i][j];
                counts[j]+=r;
                x+=r*points[i].x;
                y+=r*points[i].y
            };
            result.weights[j]=counts[j]/n;
            result.means[j][0]=x/counts[j];
            result.means[j][1]=y/counts[j];
            for(i in 0 until n) {
                val r=step.responsibilities[i][j];
                val dx=points[i].x-result.means[j][0];
                val dy=points[i].y-result.means[j][1];
                scatter[j][0]+=r*dx*dx;
                scatter[j][1]+=r*dx*dy;
                scatter[j][2]+=r*dy*dy
            }
        };
        if(type=="TIED") {
            val shared=DoubleArray(3);
            for(j in 0 until k)for(c in 0..2)shared[c]+=scatter[j][c];
            shared[0]=shared[0]/n+eps;
            shared[1]/=n.toDouble();
            shared[2]=shared[2]/n+eps;
            for(j in 0 until k)result.cov[j]=shared.copyOf()
        } else for(j in 0 until k) {
            val a=scatter[j][0]/counts[j];
            val b=scatter[j][1]/counts[j];
            val c=scatter[j][2]/counts[j];
            if(type=="SPHERICAL") {
                val v=(a+c)/2+eps;
                result.cov[j]=doubleArrayOf(v,0.0,v)
            } else result.cov[j]=doubleArrayOf(a+eps,if(type=="DIAG")0.0 else b,c+eps)
        };
        return result
    }
    fun fit(points: List<Dataset.Point>,initial: Model,type: String,iterations: Int,eps: Double): Run {
        var model=adjust(initial,type);
        var step=expectation(points,model);
        val trace=mutableListOf(step.loglik);
        for(t in 1..iterations) {
            model=maximization(points,step,type,eps);
            step=expectation(points,model);
            trace+=step.loglik
        };
        return Run(model,step,trace)
    }
}
