import kotlin.math.*

object Spectral {
    data class Spectrum(val u: DoubleArray,val transform: Array<Fft.Complex>,val amplitude: DoubleArray,val window: Windows.Window)
    data class Interpolation(val position: Double,val value: Double)
    data class Welch(val psd: DoubleArray,val coherence: DoubleArray,val transfer: Array<Fft.Complex>,val segments: Int,val error: Double)
    data class Frames(val magnitude: Array<DoubleArray>,val maximum: Double,val error: Double)
    fun amplitude(signal: DoubleArray,length: Int,window: String,fs: Int): Spectrum {
        val w=Windows.create(window,length,fs);
        val u=DoubleArray(length) {
            signal[it]*w.values[it]
        };
        val x=Fft.transform(Fft.real(u,length),false);
        val a=DoubleArray(length/2+1) {
            k->(if(k==0||2*k==length)1 else 2)*x[k].abs()/w.s1
        };
        return Spectrum(u,x,a,w)
    }
    fun median(values: DoubleArray): Double {
        val sorted=values.sortedArray();
        val n=sorted.size;
        return if(n%2==1)sorted[n/2] else (sorted[n/2-1]+sorted[n/2])/2
    }
    fun local(values: DoubleArray,k: Int)=k>0&&k+1<values.size&&values[k]>values[k-1]&&values[k]>values[k+1]
    fun interpolate(values: DoubleArray,k: Int,logarithmic: Boolean): Interpolation {
        if(!local(values,k))return Interpolation(k.toDouble(),values[k]);
        var alpha=values[k-1];
        var beta=values[k];
        var gamma=values[k+1];
        if(logarithmic) {
            alpha=ln(alpha);
            beta=ln(beta);
            gamma=ln(gamma)
        };
        val delta=(alpha-gamma)/(2*(alpha-2*beta+gamma));
        val value=beta-(alpha-gamma)*delta/4;
        return Interpolation(k+delta,if(logarithmic)exp(value) else value)
    }
    fun segment(signal: DoubleArray,window: DoubleArray,start: Int)=DoubleArray(window.size) {
        signal[start+it]*window[it]
    }
    fun packingError(signal: DoubleArray,packed: Array<Fft.Complex>): Double {
        val full=Fft.radix2(Fft.real(signal,signal.size),false);
        var error=0.0;
        for(k in packed.indices)error=maxOf(error,packed[k].subtract(full[k]).abs());
        return error
    }
    fun welch(x: DoubleArray,y: DoubleArray,length: Int,window: String,fs: Int): Welch {
        val w=Windows.create(window,length,fs);
        val count=(x.size-length)/(length/2)+1;
        val bins=length/2+1;
        val xx=DoubleArray(bins);
        val yy=DoubleArray(bins);
        val xy=Fft.zeros(bins);
        var error=0.0;
        for(j in 0 until count) {
            val sx=segment(x,w.values,j*length/2);
            val sy=segment(y,w.values,j*length/2);
            val fx=Fft.packed(sx);
            val fy=Fft.packed(sy);
            error=maxOf(error,packingError(sx,fx));
            error=maxOf(error,packingError(sy,fy));
            for(k in 0 until bins) {
                val ax=fx[k].abs();
                val ay=fy[k].abs();
                xx[k]+=ax*ax;
                yy[k]+=ay*ay;
                xy[k]=xy[k].add(fx[k].conjugate().multiply(fy[k]))
            }
        };
        val psd=DoubleArray(bins);
        val coherence=DoubleArray(bins);
        val transfer=Fft.zeros(bins);
        for(k in 0 until bins) {
            psd[k]=(if(k==0||k==length/2)1 else 2)*xx[k]/(count*fs*w.s2);
            val abs=xy[k].abs();
            coherence[k]=abs*abs/(xx[k]*yy[k]);
            transfer[k]=xy[k].divide(xx[k])
        };
        return Welch(psd,coherence,transfer,count,error)
    }
    fun frames(signal: DoubleArray,length: Int,hop: Int,window: String,fs: Int): Frames {
        val w=Windows.create(window,length,fs).values;
        val count=(signal.size-length)/hop+1;
        val magnitude=Array(count) {
            DoubleArray(length/2+1)
        };
        var maximum=0.0;
        var error=0.0;
        for(t in 0 until count) {
            val segment=segment(signal,w,t*hop);
            val spectrum=Fft.packed(segment);
            error=maxOf(error,packingError(segment,spectrum));
            for(k in spectrum.indices) {
                magnitude[t][k]=spectrum[k].abs();
                maximum=maxOf(maximum,magnitude[t][k])
            }
        };
        return Frames(magnitude,maximum,error)
    }
}
