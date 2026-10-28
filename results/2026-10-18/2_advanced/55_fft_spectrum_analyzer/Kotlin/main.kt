import kotlin.math.*

object Main {
    data class Statistics(val detrended: DoubleArray,val mean: Double,val slope: Double,val rms: Double,
        val minimum: Double,val maximum: Double,val crest: Double,val skewness: Double,val kurtosis: Double,
        val squares: Double)
    class Peak(val bin: Int,val interpolation: Spectral.Interpolation) {
        var level=0.0;
        var phase=0.0;
        var bandwidth=0.0;
        var snr=0.0;
        var coherence=0.0;
        var label="other"
    }
    class Filtered {
        lateinit var bandpass: DoubleArray;
        lateinit var notched: DoubleArray;
        lateinit var smoothed: DoubleArray;
        lateinit var envelope: DoubleArray;
        lateinit var analytic: Array<Fft.Complex>;
        var kept=0;
        var removed=0;
        var envelopeBin=0;
        var envelopeMean=0.0;
        var envelopeFrequency=0.0;
        var envelopeAmplitude=0.0;
        var depth=0.0;
        var instantMean=0.0;
        var instantStd=0.0;
        var firDc=0.0;
        var firGain=0.0
    }
    var fs=0;
    var n=0;
    var m=0;
    var k=0;
    var l=0;
    var frameLength=0;
    var hop=0;
    lateinit var params: SignalIo.Params;
    lateinit var first: Statistics;
    lateinit var second: Statistics;
    lateinit var x: DoubleArray;
    lateinit var y: DoubleArray;
    lateinit var a: DoubleArray;
    lateinit var harmonicAmplitude: DoubleArray;
    lateinit var harmonicPosition: DoubleArray;
    lateinit var power: DoubleArray;
    lateinit var flux: DoubleArray;
    lateinit var kurtosis: DoubleArray;
    lateinit var harmonicBins: IntArray;
    lateinit var dominant: IntArray;
    val peaks=mutableListOf<Peak>();
    lateinit var mainSpectrum: Spectral.Spectrum;
    lateinit var welch: Spectral.Welch;
    lateinit var frames: Spectral.Frames;
    lateinit var filtered: Filtered;
    var noiseFloor=0.0;
    var maxAmplitude=0.0;
    var onsetThreshold=0.0;
    val onsets=mutableListOf<Int>();
    var kurtosisBin=0
    fun f(value: Double)=Report.f(value)
    fun db20(value: Double)=20*log10(value)
    fun db10(value: Double)=10*log10(value)
    fun squares(values: DoubleArray,length: Int): Double {
        var sum=0.0;
        for(i in 0 until length)sum+=values[i]*values[i];
        return sum
    }
    fun rms(values: DoubleArray,length: Int)=sqrt(squares(values,length)/length)
    fun real(values: Array<Fft.Complex>)=DoubleArray(values.size) {
        values[it].re
    }
    fun preprocess(signal: DoubleArray): Statistics {
        val n=signal.size;
        var sum=0.0;
        var minimum=signal[0];
        var maximum=signal[0];
        for(value in signal) {
            sum+=value;
            minimum=minOf(minimum,value);
            maximum=maxOf(maximum,value)
        };
        val mean=sum/n;
        val center=(n-1)/2.0;
        var numerator=0.0;
        var denominator=0.0;
        for(i in 0 until n) {
            numerator+=(i-center)*(signal[i]-mean);
            denominator+=(i-center)*(i-center)
        };
        val slope=numerator/denominator;
        val d=DoubleArray(n);
        var square=0.0;
        var cube=0.0;
        var fourth=0.0;
        var peak=0.0;
        for(i in 0 until n) {
            d[i]=signal[i]-mean-slope*(i-center);
            square+=d[i]*d[i];
            cube+=d[i]*d[i]*d[i];
            fourth+=d[i]*d[i]*d[i]*d[i];
            peak=maxOf(peak,abs(d[i]))
        };
        val rms=sqrt(square/n);
        return Statistics(d,mean,slope*fs,rms,minimum,maximum,peak/rms,(cube/n)/(rms*rms*rms),(fourth/n)/(rms*rms*rms*rms),square)
    }
    fun maxima(values: DoubleArray,limit: Int)=(1 until values.size-1).filter {
        Spectral.local(values,it)
    }.sortedWith(compareByDescending<Int> {
        values[it]
    }.thenBy {
        it
    }).take(limit)
    fun largest(values: DoubleArray,first: Int,last: Int): Int {
        var best=first;
        for(j in first+1..last)if(values[j]>values[best])best=j;
        return best
    }
    fun harmonicBin(values: DoubleArray,h: Int): Int {
        val center=h*params.get("fundamental")*m/fs;
        var best=-1;
        for(bin in 1 until k)if(abs(bin-center)<=params.integer("fundamental",1)&&(best<0||values[bin]>values[best]))best=bin;
        return best
    }
    fun findPeaks() {
        maxAmplitude=a.max();
        noiseFloor=Spectral.median(a.copyOfRange(1,k));
        val bins=(1 until k).filter {
            Spectral.local(a,it)&&db20(a[it]/maxAmplitude)>=params.get("peak_threshold_db")
        }.sortedWith(compareByDescending<Int> {
            a[it]
        }.thenBy {
            it
        }).take(params.integer("peak_count"));
        for(bin in bins) {
            val peak=Peak(bin,Spectral.interpolate(a,bin,true));
            peak.level=db20(a[bin]/maxAmplitude);
            peak.phase=mainSpectrum.transform[bin].argument()*180/Fft.PI;
            peak.snr=db20(a[bin]/noiseFloor);
            peak.coherence=welch.coherence[(2*bin*l+m)/(2*m)];
            val lambda=a[bin]/sqrt(2.0);
            var left=0.0;
            var right=k.toDouble();
            for(j in bin+1..k)if(a[j]<=lambda) {
                right=j-1+(a[j-1]-lambda)/(a[j-1]-a[j]);
                break
            };
            for(j in bin-1 downTo 0)if(a[j]<=lambda) {
                left=j+1-(a[j+1]-lambda)/(a[j+1]-a[j]);
                break
            };
            peak.bandwidth=(right-left)*fs/m;
            peaks+=peak
        };
        for(peak in peaks) {
            val q=peak.interpolation.position;
            val f0=params.get("fundamental");
            var labeled=false;
            for(h in 1..10)if(abs(q-h*f0*m/fs)<=params.integer("fundamental",1)) {
                peak.label="h$h";
                labeled=true;
                break
            };
            if(labeled)continue;
            val frequency=q*fs/m;
            val j=floor(frequency/params.integer("notch")+0.5).toInt();
            if(j>=1&&abs(frequency-j*params.integer("notch"))<=params.integer("notch",1)) {
                peak.label="mains";
                continue
            };
            for(p in peaks.indices) {
                if(labeled)break;
                val center=peaks[p];
                if(center===peak)continue;
                for(other in peaks)if(other!==peak&&other!==center&&a[center.bin]>a[peak.bin]&&a[center.bin]>a[other.bin]&&abs(q+other.interpolation.position-2*center.interpolation.position)<=1) {
                    peak.label="sideband${p+1}";
                    labeled=true;
                    break
                }
            }
        }
    }
    fun harmonics() {
        harmonicBins=IntArray(10);
        harmonicAmplitude=DoubleArray(10);
        harmonicPosition=DoubleArray(10);
        for(h in 1..10) {
            val bin=harmonicBin(a,h);
            val interpolation=Spectral.interpolate(a,bin,true);
            harmonicBins[h-1]=bin;
            harmonicPosition[h-1]=interpolation.position;
            harmonicAmplitude[h-1]=interpolation.value
        };
        power=DoubleArray(k+1) {
            a[it]*a[it]/2
        }
    }
    fun spectrogram() {
        val g=frames.magnitude;
        val count=g.size;
        dominant=IntArray(count);
        flux=DoubleArray(count);
        for(t in 0 until count) {
            dominant[t]=largest(g[t],1,frameLength/2-1);
            if(t>0)for(bin in g[t].indices)flux[t]+=maxOf(0.0,g[t][bin]-g[t-1][bin])
        };
        onsetThreshold=params.get("onset_factor")*Spectral.median(flux.copyOfRange(1,count));
        for(t in 1 until count)if(flux[t]>onsetThreshold&&flux[t]>flux[t-1]&&(t==count-1||flux[t]>flux[t+1]))onsets+=t;
        kurtosis=DoubleArray(frameLength/2+1);
        for(bin in kurtosis.indices) {
            var second=0.0;
            var fourth=0.0;
            for(t in 0 until count) {
                val value=g[t][bin];
                second+=value*value;
                fourth+=value*value*value*value
            };
            kurtosis[bin]=count*fourth/(second*second)-2
        };
        kurtosisBin=largest(kurtosis,1,frameLength/2-1)
    }
    fun filters() {
        filtered=Filtered();
        val spectrum=Fft.transform(Fft.real(x,n),false);
        val bandpass=Fft.zeros(n);
        val notched=Fft.zeros(n);
        val analytic=Fft.zeros(n);
        val b1=params.integer("bandpass");
        val b2=params.integer("bandpass",1);
        val fn=params.integer("notch");
        val wn=params.integer("notch",1);
        val e1=params.integer("envelope_band");
        val e2=params.integer("envelope_band",1);
        for(bin in 0 until n) {
            val g=minOf(bin,n-bin)*fs;
            if(b1*n<=g&&g<=b2*n) {
                bandpass[bin]=spectrum[bin];
                filtered.kept++
            };
            val j=(2*g+fn*n)/(2*fn*n);
            if(j>=1&&abs(g-j*fn*n)<=wn*n)filtered.removed++ else notched[bin]=spectrum[bin];
            if(bin>=1&&bin<=(n-1)/2&&e1*n<=bin*fs&&bin*fs<=e2*n)analytic[bin]=spectrum[bin].scale(2.0)
        };
        filtered.bandpass=real(Fft.transform(bandpass,true));
        filtered.notched=real(Fft.transform(notched,true));
        filtered.analytic=Fft.transform(analytic,true);
        filtered.envelope=DoubleArray(n);
        var sum=0.0;
        for(i in 0 until n) {
            filtered.envelope[i]=filtered.analytic[i].abs();
            sum+=filtered.envelope[i]
        };
        filtered.envelopeMean=sum/n;
        val centered=DoubleArray(n) {
            filtered.envelope[it]-filtered.envelopeMean
        };
        val envelopeSpectrum=Fft.transform(Fft.real(centered,n),false);
        val be=DoubleArray(n) {
            2*envelopeSpectrum[it].abs()/n
        };
        filtered.envelopeBin=largest(be,1,(e2-e1)*n/(2*fs));
        val interpolation=Spectral.interpolate(be,filtered.envelopeBin,true);
        filtered.envelopeFrequency=interpolation.position*fs/n;
        filtered.envelopeAmplitude=interpolation.value;
        filtered.depth=filtered.envelopeAmplitude/filtered.envelopeMean;
        val frequency=DoubleArray(n-1);
        sum=0.0;
        for(i in 1 until n) {
            var delta=filtered.analytic[i].argument()-filtered.analytic[i-1].argument();
            if(delta<=-Fft.PI)delta+=2*Fft.PI;
            if(delta>Fft.PI)delta-=2*Fft.PI;
            frequency[i-1]=delta*fs/(2*Fft.PI);
            sum+=frequency[i-1]
        };
        filtered.instantMean=sum/(n-1);
        sum=0.0;
        for(value in frequency)sum+=(value-filtered.instantMean)*(value-filtered.instantMean);
        filtered.instantStd=sqrt(sum/(n-1));
        val fir=params.row("fir");
        filtered.smoothed=Fft.convolve(y,fir);
        var gain=Fft.Complex(0.0,0.0);
        for(j in fir.indices) {
            filtered.firDc+=fir[j];
            gain=gain.add(Fft.rotation(2*Fft.PI*params.get("fundamental")*j/fs).scale(fir[j]))
        };
        filtered.firGain=db20(gain.abs())
    }
    fun spectrumReport(): List<String> {
        val out=mutableListOf("frequency,amplitude");
        for(bin in 0..k)out+="${f(bin.toDouble()*fs/m)},${f(a[bin])}";
        return out
    }
    fun peakReport(): List<String> {
        val out=mutableListOf("length=$m window=${params.word("main_window")} resolution=${f(fs.toDouble()/m)} threshold_db=${f(params.get("peak_threshold_db"))}",
            "max_amplitude=${f(maxAmplitude)} noise_floor=${f(noiseFloor)} noise_floor_db=${f(db20(noiseFloor))}",
            "peaks=${peaks.size}");
        for(rank in peaks.indices) {
            val p=peaks[rank];
            out+="${rank+1} bin=${p.bin} frequency=${f(p.bin.toDouble()*fs/m)} refined=${f(p.interpolation.position*fs/m)} amplitude=${f(p.interpolation.value)} level_db=${f(p.level)} phase=${f(p.phase)} bandwidth=${f(p.bandwidth)} snr_db=${f(p.snr)} coherence=${f(p.coherence)} label=${p.label}"
        };
        return out
    }
    fun welchReport(): List<String> {
        val out=mutableListOf("frequency,psd_db");
        for(bin in welch.psd.indices)out+="${f(bin.toDouble()*fs/l)},${f(db10(welch.psd[bin]))}";
        return out
    }
    fun spectrogramReport(): List<String> {
        val count=frames.magnitude.size;
        val out=mutableListOf("frames=$count bins=${frameLength/2+1} frame_length=$frameLength hop=$hop window=${params.word("spectrogram",3)} band_db=${params.integer("spectrogram",2)} max_db=${f(db20(frames.maximum))}");
        out.addAll(Report.shades(frames,fs,frameLength,params.integer("spectrogram",2)));
        out+="track";
        for(t in 0 until count)out+="frame=$t time=${f(t.toDouble()*hop/fs)} frequency=${f(dominant[t].toDouble()*fs/frameLength)} level_db=${f(db20(frames.magnitude[t][dominant[t]]/frames.maximum))}";
        out+="onsets=${onsets.size} threshold=${f(onsetThreshold)}";
        for(t in onsets)out+="frame=$t time=${f(t.toDouble()*hop/fs)} flux=${f(flux[t])}";
        out+="kurtosis bin=$kurtosisBin frequency=${f(kurtosisBin.toDouble()*fs/frameLength)} value=${f(kurtosis[kurtosisBin])}";
        return out
    }
    fun filteredReport(): List<String> {
        val out=mutableListOf("index,bandpass,notched,smoothed,envelope");
        for(i in 0 until n)out+="$i,${f(filtered.bandpass[i])},${f(filtered.notched[i])},${f(filtered.smoothed[i])},${f(filtered.envelope[i])}";
        return out
    }

    fun yes(value: Boolean)=if(value)"yes" else "no"
    fun check(error: Double)=if(error<=1e-6)"ok" else "failed"
    fun statistics(channel: Int,s: Statistics)="channel=$channel mean=${f(s.mean)} slope=${f(s.slope)} rms=${f(s.rms)} min=${f(s.minimum)} max=${f(s.maximum)} crest=${f(s.crest)} skewness=${f(s.skewness)} kurtosis=${f(s.kurtosis)}"
    fun lag(values: DoubleArray,maximum: Int): Int {
        val q=values.size;
        var best=-maximum;
        var value=values[q-maximum];
        for(ell in -maximum..maximum) {
            val current=values[if(ell<0)ell+q else ell];
            if(current>value||current==value&&(abs(ell)<abs(best)||abs(ell)==abs(best)&&ell<best)) {
                best=ell;
                value=current
            }
        };
        return best
    }
    fun refinedLag(values: DoubleArray,lag: Int): Double {
        val q=values.size;
        val triple=doubleArrayOf(values[if(lag-1<0)lag-1+q else lag-1],values[if(lag<0)lag+q else lag],values[if(lag+1<0)lag+1+q else lag+1]);
        return lag+(Spectral.interpolate(triple,1,false).position-1)
    }
    fun report(): List<String> {
        val out=mutableListOf("[signal]","sample_rate=$fs samples=$n duration=${f(n.toDouble()/fs)}",statistics(1,first),statistics(2,second),"[levels]");
        val block=params.integer("block_length");
        val blocks=n/block;
        var loudest=0;
        val rms1=DoubleArray(blocks);
        val rms2=DoubleArray(blocks);
        val peak1=DoubleArray(blocks);
        for(g in 0 until blocks) {
            var sx=0.0;
            var sy=0.0;
            for(i in g*block until (g+1)*block) {
                sx+=x[i]*x[i];
                sy+=y[i]*y[i];
                peak1[g]=maxOf(peak1[g],abs(x[i]))
            };
            rms1[g]=sqrt(sx/block);
            rms2[g]=sqrt(sy/block);
            if(rms1[g]>rms1[loudest])loudest=g
        };
        out+="block_length=$block blocks=$blocks loudest=$loudest";
        for(g in 0 until blocks)out+="block=$g time=${f(g.toDouble()*block/fs)} rms1=${f(rms1[g])} rms2=${f(rms2[g])} peak1=${f(peak1[g])}";
        out+="[windows]";
        for(name in Windows.NAMES) {
            val spectrum=Spectral.amplitude(x,m,name,fs);
            val w=spectrum.window;
            val bin=harmonicBin(spectrum.amplitude,1);
            val med=Spectral.median(spectrum.amplitude.copyOfRange(1,k));
            out+="name=$name coherent_gain=${f(w.gain)} enbw_bins=${f(w.bins)} enbw_hz=${f(w.hz)} scalloping_db=${f(w.scalloping)} fundamental_bin=$bin bin_amplitude=${f(spectrum.amplitude[bin])} refined_amplitude=${f(Spectral.interpolate(spectrum.amplitude,bin,true).value)} floor_db=${f(db20(med))}"
        };
        var sum=0.0;
        var weighted=0.0;
        var logs=0.0;
        for(bin in 1 until k) {
            sum+=power[bin];
            weighted+=bin.toDouble()*fs/m*power[bin];
            logs+=ln(power[bin])
        };
        val totalPower=sum/mainSpectrum.window.bins;
        val centroid=weighted/sum;
        var spread=0.0;
        var cumulative=0.0;
        var rolloff=0.0;
        var rolled=false;
        for(bin in 1 until k) {
            val frequency=bin.toDouble()*fs/m;
            spread+=(frequency-centroid)*(frequency-centroid)*power[bin];
            cumulative+=power[bin];
            if(!rolled&&cumulative>=0.85*sum) {
                rolloff=frequency;
                rolled=true
            }
        };
        spread=sqrt(spread/sum);
        val flatness=db10(exp(logs/(k-1))/(sum/(k-1)));
        out+="[main]";
        out+="length=$m window=${params.word("main_window")} method=${if(Fft.powerOfTwo(m))"radix2" else "bluestein"} transform_size=${if(Fft.powerOfTwo(m))m else Fft.pow2(2*m-1)} resolution=${f(fs.toDouble()/m)}";
        out+="total_power=${f(totalPower)} centroid=${f(centroid)} spread=${f(spread)} rolloff=${f(rolloff)} flatness_db=${f(flatness)}";
        out+="[bands]";
        val bandCount=params.values.getValue("bands").size-1;
        for(band in 0 until bandCount) {
            val low=params.integer("bands",band);
            val high=params.integer("bands",band+1);
            var value=0.0;
            for(bin in 1 until k)if(low*m<=bin*fs&&bin*fs<high*m)value+=power[bin];
            value/=mainSpectrum.window.bins;
            out+="range=$low-$high power=${f(value)} percent=${f(100*value/totalPower)}"
        };
        out+="[third_octave]";
        for(b in params.integer("third_octave")..params.integer("third_octave",1)) {
            val center=1000*2.0.pow(b/3.0);
            val lower=1000*2.0.pow((2*b-1)/6.0);
            val upper=1000*2.0.pow((2*b+1)/6.0);
            var value=0.0;
            var bins=0;
            for(bin in 1 until k) {
                val frequency=bin.toDouble()*fs/m;
                if(lower<=frequency&&frequency<upper) {
                    bins++;
                    value+=power[bin]
                }
            };
            value/=mainSpectrum.window.bins;
            out+="band=$b center=${f(center)} lower=${f(lower)} upper=${f(upper)} bins=$bins level_db=${f(db10(value))}"
        };
        out+="[harmonics]";
        out+="fundamental=${f(params.get("fundamental"))} search=${params.integer("fundamental",1)}";
        for(h in 1..10)out+="h=$h target=${f(h*params.get("fundamental"))} bin=${harmonicBins[h-1]} refined=${f(harmonicPosition[h-1]*fs/m)} amplitude=${f(harmonicAmplitude[h-1])} level_db=${f(db20(harmonicAmplitude[h-1]/harmonicAmplitude[0]))}";
        var distortion=0.0;
        var fundamentalPower=0.0;
        for(h in 1 until 10)distortion+=harmonicAmplitude[h]*harmonicAmplitude[h];
        val thd=sqrt(distortion)/harmonicAmplitude[0];
        for(bin in 1 until k)if(abs(bin-harmonicBins[0])<=params.integer("fundamental",1))fundamentalPower+=power[bin];
        fundamentalPower/=mainSpectrum.window.bins;
        val thdn=sqrt((totalPower-fundamentalPower)/fundamentalPower);
        out+="thd_percent=${f(100*thd)} thd_db=${f(db20(thd))}";
        out+="thdn_percent=${f(100*thdn)} thdn_db=${f(db20(thdn))}";
        val p1=params.integer("pitch_range");
        val p2=params.integer("pitch_range",1);
        val lam1=(fs+p2-1)/p2;
        val lam2=fs/p1;
        var hpsBin=-1;
        var best=Double.NEGATIVE_INFINITY;
        for(bin in 1..k/5)if(p1*m<=bin*fs&&bin*fs<=p2*m) {
            var value=0.0;
            for(r in 1..5)value+=ln(a[r*bin]);
            if(value>best) {
                best=value;
                hpsBin=bin
            }
        };
        val q=Fft.pow2(2*n-1);
        val bp=Fft.radix2(Fft.real(filtered.bandpass,q),false);
        for(bin in 0 until q) {
            val abs=bp[bin].abs();
            bp[bin]=Fft.Complex(abs*abs,0.0)
        };
        val rho=real(Fft.radix2(bp,true));
        val ell=largest(rho,lam1,lam2);
        val period=Spectral.interpolate(rho,ell,false);
        var crossings=0;
        for(i in 1 until n)if(filtered.bandpass[i-1]<0&&filtered.bandpass[i]>=0)crossings++;
        out+="[pitch]";
        out+="range=$p1-$p2 lags=$lam1-$lam2";
        out+="hps bin=$hpsBin order=5 frequency=${f(hpsBin.toDouble()*fs/m)}";
        out+="autocorrelation lag=$ell period=${f(period.position)} frequency=${f(fs/period.position)} strength=${f(period.value/rho[0])}";
        out+="zero_crossing count=$crossings frequency=${f(crossings.toDouble()*fs/n)}";
        val z1=params.integer("zoom");
        val z2=params.integer("zoom",1);
        val jCount=params.integer("zoom",2);
        val dz=(z2-z1).toDouble()/(jCount-1);
        val zoom=Fft.chirpZ(mainSpectrum.u,z1.toDouble(),dz,jCount,fs);
        val zoomAmplitude=DoubleArray(jCount) {
            2*zoom[it].abs()/mainSpectrum.window.s1
        };
        val zoomPeaks=maxima(zoomAmplitude,3);
        out+="[zoom]";
        out+="band=$z1-$z2 points=$jCount step=${f(dz)}";
        for(rank in zoomPeaks.indices) {
            val interpolation=Spectral.interpolate(zoomAmplitude,zoomPeaks[rank],true);
            out+="peak=${rank+1} frequency=${f(z1+interpolation.position*dz)} amplitude=${f(interpolation.value)}"
        };
        out+="[welch]";
        out+="segment_length=$l segments=${welch.segments} window=${params.word("welch",1)} resolution=${f(fs.toDouble()/l)}";
        var integrated=0.0;
        for(value in welch.psd)integrated+=value;
        integrated=integrated*fs/l;
        val variance=first.rms*first.rms;
        out+="integrated_power=${f(integrated)} variance=${f(variance)} ratio=${f(integrated/variance)}";
        val welchPeaks=maxima(welch.psd,5);
        for(rank in welchPeaks.indices) {
            val bin=welchPeaks[rank];
            out+="peak=${rank+1} frequency=${f(bin.toDouble()*fs/l)} psd_db=${f(db10(welch.psd[bin]))} coherence=${f(welch.coherence[bin])} gain=${f(welch.transfer[bin].abs())} phase=${f(welch.transfer[bin].argument()*180/Fft.PI)}"
        };
        out+="[filter]";
        out+="bandpass=${params.integer("bandpass")}-${params.integer("bandpass",1)} bins_kept=${filtered.kept} rms=${f(rms(filtered.bandpass,n))} energy_ratio=${f(squares(filtered.bandpass,n)/first.squares)}";
        out+="notch=${params.integer("notch")} width=${params.integer("notch",1)} bins_removed=${filtered.removed} rms=${f(rms(filtered.notched,n))}";
        out+="fir_taps=${params.row("fir").size} dc_gain=${f(filtered.firDc)} gain_at_fundamental_db=${f(filtered.firGain)} rms=${f(rms(filtered.smoothed,n))}";
        out+="[envelope]";
        out+="band=${params.integer("envelope_band")}-${params.integer("envelope_band",1)} mean=${f(filtered.envelopeMean)} bin=${filtered.envelopeBin} frequency=${f(filtered.envelopeFrequency)} amplitude=${f(filtered.envelopeAmplitude)} depth=${f(filtered.depth)}";
        out+="instantaneous_frequency mean=${f(filtered.instantMean)} std=${f(filtered.instantStd)}";
        val fx=Fft.radix2(Fft.real(x,q),false);
        val fy=Fft.radix2(Fft.real(y,q),false);
        val cross=Fft.zeros(q);
        val phat=Fft.zeros(q);
        for(bin in 0 until q) {
            cross[bin]=fx[bin].conjugate().multiply(fy[bin]);
            phat[bin]=cross[bin].divide(cross[bin].abs())
        };
        val correlation=real(Fft.radix2(cross,true));
        val phatCorrelation=real(Fft.radix2(phat,true));
        val maxLag=params.integer("max_lag");
        val chosenLag=lag(correlation,maxLag);
        val phatLag=lag(phatCorrelation,maxLag);
        val refined=refinedLag(correlation,chosenLag);
        val phatRefined=refinedLag(phatCorrelation,phatLag);
        out+="[correlation]";
        out+="max_lag=$maxLag lag=$chosenLag refined_lag=${f(refined)} delay_ms=${f(1000*refined/fs)} coefficient=${f(correlation[if(chosenLag<0)chosenLag+q else chosenLag]/sqrt(first.squares*second.squares))}";
        out+="phat_lag=$phatLag refined_lag=${f(phatRefined)} delay_ms=${f(1000*phatRefined/fs)}";
        val inverse=Fft.transform(mainSpectrum.transform,true);
        var inverseError=0.0;
        var frequencyPower=0.0;
        for(i in 0 until m) {
            inverseError=maxOf(inverseError,inverse[i].subtract(Fft.Complex(mainSpectrum.u[i],0.0)).abs());
            val abs=mainSpectrum.transform[i].abs();
            frequencyPower+=abs*abs
        };
        val timePower=squares(mainSpectrum.u,m);
        val parseval=abs(timePower-frequencyPower/m)/timePower;
        var firError=0.0;
        var spotError=0.0;
        val fir=params.row("fir");
        for(i in filtered.smoothed.indices) {
            var direct=0.0;
            for(j in maxOf(0,i-fir.size+1)..minOf(n-1,i))direct+=y[j]*fir[i-j];
            firError=maxOf(firError,abs(filtered.smoothed[i]-direct))
        };
        for(peak in peaks) {
            var direct=Fft.Complex(0.0,0.0);
            for(i in 0 until m)direct=direct.add(Fft.rotation(2*Fft.PI*((peak.bin*i)%m)/m).scale(mainSpectrum.u[i]));
            spotError=maxOf(spotError,direct.subtract(mainSpectrum.transform[peak.bin]).abs())
        };
        out+="[checks]";
        out+="inverse_roundtrip=${check(inverseError)}";
        out+="parseval=${check(parseval)}";
        out+="real_packing=${check(maxOf(welch.error,frames.error))} transforms=${2*welch.segments+frames.magnitude.size}";
        out+="fir_fft_vs_direct=${check(firError)}";
        out+="dft_spot_check=${check(spotError)} bins=${peaks.size}";
        val ratio=harmonicAmplitude[1]/harmonicAmplitude[0];
        var harmonicCount=0;
        for(h in 2 until 10)if(db20(harmonicAmplitude[h]/harmonicAmplitude[0])>=-30)harmonicCount++;
        val electricalLevel=peaks.firstOrNull {
            it.label=="mains"
        }
        ?.level;
        val misalignment=ratio>=0.5;
        val looseness=harmonicCount>=3;
        val bearing=filtered.depth>=0.2;
        val electrical=electricalLevel!=null&&electricalLevel>=-20;
        val transientFinding=onsets.isNotEmpty();
        val findings=listOf(misalignment,looseness,bearing,electrical,transientFinding).count {
            it
        };
        out+="[diagnosis]";
        out+="misalignment=${yes(misalignment)} ratio=${f(ratio)}";
        out+="looseness=${yes(looseness)} harmonics=$harmonicCount";
        out+="bearing=${yes(bearing)} depth=${f(filtered.depth)}";
        out+="electrical=${yes(electrical)} level_db=${electricalLevel?.let{f(it)}?:"none"}";
        out+="transient=${yes(transientFinding)} onsets=${onsets.size}";
        out+="status=${if(findings==0)"normal" else if(findings==1)"warning" else "alarm"} findings=$findings";
        return out
    }
    @JvmStatic fun main(args: Array<String>) {
        val data=SignalIo.read();
        fs=data.fs;
        params=data.params;
        n=data.first.size;
        m=params.integer("main_length");
        k=m/2;
        l=params.integer("welch");
        frameLength=params.integer("spectrogram");
        hop=params.integer("spectrogram",1);
        first=preprocess(data.first);
        second=preprocess(data.second);
        x=first.detrended;
        y=second.detrended;
        mainSpectrum=Spectral.amplitude(x,m,params.word("main_window"),fs);
        a=mainSpectrum.amplitude;
        welch=Spectral.welch(x,y,l,params.word("welch",1),fs);
        frames=Spectral.frames(x,frameLength,hop,params.word("spectrogram",3),fs);
        findPeaks();
        harmonics();
        spectrogram();
        filters();
        Report.write("spectrum.csv",spectrumReport());
        Report.write("peaks.txt",peakReport());
        Report.write("welch_psd.csv",welchReport());
        Report.write("spectrogram.txt",spectrogramReport());
        Report.write("filtered.csv",filteredReport());
        Report.write("report.txt",report())
    }
}
