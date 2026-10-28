import kotlin.math.*

object Windows {
    val NAMES=listOf("rectangular","hann","hamming","blackman","flattop")
    data class Window(val values: DoubleArray,val s1: Double,val s2: Double,val gain: Double,val bins: Double,val hz: Double,val scalloping: Double)
    fun coefficients(name: String)=when(name) {
        "rectangular"->doubleArrayOf(1.0);
        "hann"->doubleArrayOf(0.5,0.5);
        "hamming"->doubleArrayOf(0.54,0.46);
        "blackman"->doubleArrayOf(0.42,0.5,0.08);
        else->doubleArrayOf(0.21557895,0.41663158,0.277263158,0.083578947,0.006947368)
    }
    fun create(name: String,length: Int,fs: Int): Window {
        val coefficients=coefficients(name);
        val values=DoubleArray(length);
        var s1=0.0;
        var s2=0.0;
        var sum=Fft.Complex(0.0,0.0);
        for(n in 0 until length) {
            var value=0.0;
            for(j in coefficients.indices)value+=(if(j%2==0)1 else -1)*coefficients[j]*cos(2*Fft.PI*j*n/length);
            values[n]=value;
            s1+=value;
            s2+=value*value;
            sum=sum.add(Fft.rotation(Fft.PI*n/length).scale(value))
        };
        val bins=length*s2/(s1*s1);
        return Window(values,s1,s2,s1/length,bins,bins*fs/length,-20*log10(sum.abs()/s1))
    }
}
