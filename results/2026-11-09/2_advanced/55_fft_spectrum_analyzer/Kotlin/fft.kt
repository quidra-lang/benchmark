import kotlin.math.*

object Fft {
    const val PI=3.141592653589793
    data class Complex(val re: Double,val im: Double) {
        fun add(z: Complex)=Complex(re+z.re,im+z.im);
        fun subtract(z: Complex)=Complex(re-z.re,im-z.im);
        fun multiply(z: Complex)=Complex(re*z.re-im*z.im,re*z.im+im*z.re);
        fun scale(x: Double)=Complex(re*x,im*x);
        fun divide(x: Double)=Complex(re/x,im/x);
        fun conjugate()=Complex(re,-im);
        fun abs()=sqrt(re*re+im*im);
        fun argument()=atan2(im,re)
    }
    fun rotation(angle: Double)=Complex(cos(angle),-sin(angle))
    fun pow2(n: Int): Int {
        var q=1;
        while(q<n)q*=2;
        return q
    }
    fun powerOfTwo(n: Int)=(n and (n-1))==0
    fun zeros(length: Int)=Array(length) {
        Complex(0.0,0.0)
    }
    fun real(values: DoubleArray,length: Int): Array<Complex> {
        val result=zeros(length);
        for(i in values.indices)result[i]=Complex(values[i],0.0);
        return result
    }
    fun radix2(input: Array<Complex>,inverse: Boolean): Array<Complex> {
        val q=input.size;
        val a=input.copyOf();
        var bits=0;
        var count=q;
        while(count>1) {
            bits++;
            count/=2
        };
        for(n in 1 until q) {
            var r=0;
            var value=n;
            for(b in 0 until bits) {
                r=2*r+(value and 1);
                value=value ushr 1
            };
            if(n<r) {
                val swap=a[n];
                a[n]=a[r];
                a[r]=swap
            }
        };
        val w=Array(q/2) {
            k->val value=rotation(2*PI*k/q);
            if(inverse)value.conjugate() else value
        };
        var s=2;
        while(s<=q) {
            for(b in 0 until q step s)for(j in 0 until s/2) {
                val t=w[j*(q/s)].multiply(a[b+j+s/2]);
                val u=a[b+j];
                a[b+j]=u.add(t);
                a[b+j+s/2]=u.subtract(t)
            };
            s*=2
        };
        if(inverse)for(n in 0 until q)a[n]=a[n].divide(q.toDouble());
        return a
    }
    fun bluestein(v: Array<Complex>): Array<Complex> {
        val m=v.size;
        val q=pow2(2*m-1);
        val w=Array(m) {
            n->rotation(PI*((n*n)%(2*m))/m)
        };
        val a=zeros(q);
        val b=zeros(q);
        for(n in 0 until m) {
            a[n]=v[n].multiply(w[n]);
            if(n==0)b[0]=w[0].conjugate() else {
                b[n]=w[n].conjugate();
                b[q-n]=w[n].conjugate()
            }
        };
        val g=convolution(a,b);
        return Array(m) {
            k->w[k].multiply(g[k])
        }
    }
    fun transform(input: Array<Complex>,inverse: Boolean): Array<Complex> {
        if(powerOfTwo(input.size))return radix2(input,inverse);
        if(!inverse)return bluestein(input);
        val output=bluestein(Array(input.size) {
            input[it].conjugate()
        });
        return Array(output.size) {
            output[it].conjugate().divide(output.size.toDouble())
        }
    }
    fun packed(values: DoubleArray): Array<Complex> {
        val q=values.size;
        val h=q/2;
        val z=Array(h) {
            j->Complex(values[2*j],values[2*j+1])
        };
        val spectrum=radix2(z,false);
        return Array(h+1) {
            k->val a=spectrum[k%h];
            val b=spectrum[(h-k)%h].conjugate();
            val even=a.add(b).divide(2.0);
            val difference=a.subtract(b);
            val odd=Complex(difference.im/2,-difference.re/2);
            even.add(rotation(2*PI*k/q).multiply(odd))
        }
    }
    fun convolution(a: Array<Complex>,b: Array<Complex>): Array<Complex> {
        val fa=radix2(a,false);
        val fb=radix2(b,false);
        for(k in fa.indices)fa[k]=fa[k].multiply(fb[k]);
        return radix2(fa,true)
    }
    fun convolve(a: DoubleArray,b: DoubleArray): DoubleArray {
        val length=a.size+b.size-1;
        val q=pow2(length);
        val result=convolution(real(a,q),real(b,q));
        return DoubleArray(length) {
            result[it].re
        }
    }
    fun chirpZ(u: DoubleArray,z1: Double,dz: Double,points: Int,fs: Int): Array<Complex> {
        val m=u.size;
        val q=pow2(m+points-1);
        val a=zeros(q);
        val b=zeros(q);
        for(n in 0 until m)a[n]=Complex(u[n],0.0).multiply(rotation(2*PI*z1*n/fs)).multiply(rotation(PI*dz*n*n/fs));
        for(n in -(m-1) until points)b[if(n<0)n+q else n]=rotation(PI*dz*n*n/fs).conjugate();
        val g=convolution(a,b);
        return Array(points) {
            j->rotation(PI*dz*j*j/fs).multiply(g[j])
        }
    }
}
