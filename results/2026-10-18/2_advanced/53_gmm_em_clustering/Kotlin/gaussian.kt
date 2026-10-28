import kotlin.math.*

object Gaussian {
    data class Eigen(val leading: Double,val trailing: Double,val ux: Double,val uy: Double,
        val angle: Double,val major: Double,val minor: Double,val area: Double,val correlation: Double)
    fun det(s: DoubleArray)=s[0]*s[2]-s[1]*s[1]
    fun q(x: Double,y: Double,mean: DoubleArray,s: DoubleArray): Double {
        val dx=x-mean[0];
        val dy=y-mean[1];
        return (s[2]*dx*dx-2*s[1]*dx*dy+s[0]*dy*dy)/det(s)
    }
    fun logDensity(x: Double,y: Double,weight: Double,mean: DoubleArray,s: DoubleArray)=ln(weight)-ln(2*PI)-ln(det(s))/2-q(x,y,mean,s)/2
    fun eigen(s: DoubleArray): Eigen {
        val a=s[0];
        val b=s[1];
        val c=s[2];
        val h=(a+c)/2;
        val g=sqrt(((a-c)/2)*((a-c)/2)+b*b);
        val l1=h+g;
        val l2=h-g;
        var ux: Double;
        var uy: Double;
        if(b==0.0) {
            ux=if(a>=c)1.0 else 0.0;
            uy=if(a>=c)0.0 else 1.0
        } else {
            val vx=if(a>=c)l1-c else b;
            val vy=if(a>=c)b else l1-a;
            val length=sqrt(vx*vx+vy*vy);
            ux=vx/length;
            uy=vy/length;
            if(vx<0) {
                ux=-ux;
                uy=-uy
            }
        };
        return Eigen(l1,l2,ux,uy,atan2(uy,ux)*180/PI,sqrt(l1),sqrt(l2),PI*sqrt(l1*l2),b/sqrt(a*c))
    }
    fun bhattacharyya(m1: DoubleArray,s1: DoubleArray,m2: DoubleArray,s2: DoubleArray): Double {
        val average=DoubleArray(3) {
            (s1[it]+s2[it])/2
        };
        return q(m2[0],m2[1],m1,average)/8+ln(det(average)/sqrt(det(s1)*det(s2)))/2
    }
}
