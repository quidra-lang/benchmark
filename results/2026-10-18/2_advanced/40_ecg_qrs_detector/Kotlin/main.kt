import kotlin.math.abs

private val LABELS=listOf("N","V","A")
private val CLASSES=listOf("qrs","searchback","twave","refractory","noise")
private class Detection(val peaks: List<Detector.Peak>,f: Filters.Signals,val params: Map<String,Int>) {
    val registered=mutableListOf<Detector.Peak>();
    val intervals=mutableListOf<Int>();
    val initial=Detector.levels(f);
    val levels=initial.copyOf();
    var ra1=200;
    var ra2=200
    fun thresholds(): LongArray {
        val i=levels[1]+Report.div(levels[0]-levels[1],4);
        val f=levels[3]+Report.div(levels[2]-levels[3],4);
        return longArrayOf(i,f,Report.div(i,2),Report.div(f,2))
    }
    fun register(p: Detector.Peak) {
        if(registered.isNotEmpty()) {
            val elapsed=p.time-registered.last().time;
            intervals+=elapsed;
            if(intervals.size>8)intervals.removeAt(0);
            ra1=intervals.sum()/intervals.size;
            if(92L*ra1<=100L*elapsed&&100L*elapsed<=116L*ra1)ra2=ra1
        };
        registered+=p
    }
    fun update(p: Detector.Peak,category: Int) {
        val offset=if(category==1)1 else 0;
        val weight=if(category==2)3 else 7;
        val denominator=(weight+1).toLong();
        levels[offset]=Report.div(p.peakI+weight*levels[offset],denominator);
        levels[offset+2]=Report.div(p.peakF+weight*levels[offset+2],denominator)
    }
    fun searchback(time: Int) {
        while(true) {
            val last=registered.lastOrNull()?.time?:0;
            if(time-last<=ra2.toLong()*params.getValue("searchback_percent")/100)return;
            val t=thresholds();
            var chosen: Detector.Peak?=null;
            for(p in peaks)if(p.kind=="noise"&&p.time>last&&p.time<time&&p.peakI>t[2]&&p.peakF>t[3]&&(chosen==null||p.peakI>chosen.peakI))chosen=p;
            val selected=chosen?:return;
            update(selected,2);
            selected.kind="searchback";
            register(selected)
        }
    }
    fun run(n: Int) {
        for(p in peaks) {
            searchback(p.time);
            val t=thresholds();
            p.thrI=t[0];
            p.thrF=t[1];
            val last=registered.lastOrNull();
            if(last!=null&&p.time-last.time<params.getValue("refractory_ms")/5) {
                p.kind="refractory";
                continue
            };
            if(p.peakI>t[0]&&p.peakF>t[1]) {
                if(last!=null&&p.time-last.time<params.getValue("twave_ms")/5&&2*p.slope<last.slope) {
                    p.kind="twave";
                    update(p,1)
                }else {
                    p.kind="qrs";
                    update(p,0);
                    register(p)
                }
            }else {
                p.kind="noise";
                update(p,1)
            }
        };
        searchback(n)
    }
}
class Beat(val number: Int,val sample: Int,val width: Int,val rr: Long,val method: String) {
    var label="N";
    var offset=0L;
    var annotation: SignalIo.Annotation?=null
}
private fun beats(d: Detection,f: Filters.Signals,p: Map<String,Int>): List<Beat> {
    val result=mutableListOf<Beat>();
    for(peak in d.registered) {
        val number=result.size+1;
        val sample=maxOf(0,peak.r-21);
        val rr=if(result.isEmpty())0L else 5L*(sample-result.last().sample);
        val b=Beat(number,sample,Detector.width(f.band,peak.r),rr,if(peak.kind=="qrs")"threshold" else "searchback");
        if(number>=10) {
            var previous=0L;
            for(j in number-9 until number-1)previous+=result[j].rr;
            if(800*rr<p.getValue("premature_percent").toLong()*previous)b.label=if(b.width>p.getValue("qrs_width_ms"))"V" else "A"
        };
        result+=b
    };
    return result
}
private fun match(beats: List<Beat>,refs: List<SignalIo.Annotation>,tolerance: Int) {
    for(b in beats) {
        var chosen: SignalIo.Annotation?=null;
        var distance=Int.MAX_VALUE;
        for(r in refs)if(r.beat==null) {
            val d=abs(r.sample-b.sample);
            if(d<=tolerance&&d<distance) {
                distance=d;
                chosen=r
            }
        };
        val selected=chosen;
        if(selected!=null) {
            selected.beat=b;
            b.annotation=selected;
            b.offset=5L*(b.sample-selected.sample)
        }
    }
}
private data class Row(val sample: Int,val order: Int,val text: String)
private fun ordered(rows: List<Row>)=rows.sortedWith(compareBy<Row> {
    it.sample
}.thenBy {
    it.order
}).map {
    it.text
}
private fun ref(b: Beat)=b.annotation?.label?:"-"
private fun lists(beats: List<Beat>,refs: List<SignalIo.Annotation>,peaks: List<Detector.Peak>,x: LongArray,f: Filters.Signals,p: Map<String,Int>) {
    var output=mutableListOf("beat,sample,time_ms,rr_ms,hr_bpm,width_ms,label,method,ref_sample,ref_label");
    for(b in beats)output+="${b.number},${b.sample},${5*b.sample},${if(b.number==1)"-" else b.rr.toString()},${if(b.number==1)"-" else Report.two(Report.rdiv(6000000,b.rr))},${b.width},${b.label},${b.method},${b.annotation?.sample?.toString()?:"-"},${ref(b)}";
    SignalIo.write("beats.csv",output);
    output=mutableListOf("peak,sample,r_sample,peak_i,peak_f,slope,thr_i,thr_f,class");
    for((i,peak) in peaks.withIndex())output+="${i+1},${peak.time},${peak.r},${peak.peakI},${peak.peakF},${peak.slope},${peak.thrI},${peak.thrF},${peak.kind}";
    SignalIo.write("peaks.csv",output);
    val rows=mutableListOf<Row>();
    for(r in refs) {
        val b=r.beat;
        val text=if(b==null)"${r.sample},${r.label},-,-,-,-,FN,-" else "${r.sample},${r.label},${b.number},${b.sample},${b.label},${b.offset},TP,${if(b.label==r.label)"yes" else "no"}";
        rows+=Row(r.sample,0,text)
    };
    for(b in beats)if(b.annotation==null)rows+=Row(b.sample,1,"-,-,${b.number},${b.sample},${b.label},-,FP,-");
    output=mutableListOf("ref_sample,ref_label,beat,beat_sample,beat_label,offset_ms,status,agree");
    output+=ordered(rows);
    SignalIo.write("matching.csv",output);
    output=mutableListOf("sample,ecg,lowpass,bandpass,derivative,squared,integrated");
    for(i in 0 until p.getValue("excerpt_ms")/5)output+="$i,${x[i]},${f.low[i]},${f.band[i]},${f.derivative[i]},${f.squared[i]},${f.integrated[i]}";
    SignalIo.write("signals_excerpt.csv",output)
}
private class Segment(val start: Int,val end: Int) {
    var refs=0;
    var tp=0;
    var fp=0;
    var fn=0;
    var noise=0;
    var beats=0;
    val rr=mutableListOf<Long>()
}
private fun segments(beats: List<Beat>,refs: List<SignalIo.Annotation>,peaks: List<Detector.Peak>,n: Int,size: Int): List<Segment> {
    val result=mutableListOf<Segment>();
    for(start in 0 until n step size) {
        val end=minOf(n,start+size);
        val s=Segment(5*start,5*end);
        for(r in refs)if(r.sample in start until end) {
            s.refs++;
            if(r.beat!=null)s.tp++
        };
        s.fn=s.refs-s.tp;
        for(b in beats)if(b.sample in start until end) {
            s.beats++;
            if(b.annotation==null)s.fp++;
            if(b.number>1)s.rr+=b.rr
        };
        s.noise=peaks.count {
            it.kind=="noise"&&it.time in start until end
        };
        result+=s
    };
    return result
}
private fun segmentRange(s: Segment)=Report.pad(s.start.toString(),6)+"-"+Report.pad(s.end.toString(),6)
private fun levelLine(heading: String,l: LongArray)="$heading spki=${l[0]} npki=${l[1]} spkf=${l[2]} npkf=${l[3]}"
private fun performance(d: Detection,beats: List<Beat>,refs: List<SignalIo.Annotation>,segments: List<Segment>,n: Int,p: Map<String,Int>) {
    val rc=IntArray(3);
    val bc=IntArray(3);
    val miss=IntArray(3);
    val extra=IntArray(3);
    val confusion=Array(3) {
        IntArray(3)
    };
    var tp=0;
    var offset=0L;
    var absolute=0L;
    var maxAbs=0L;
    val method=IntArray(2);
    val methodTp=IntArray(2);
    val pc=d.peaks.groupingBy {
        it.kind
    }.eachCount();
    for(r in refs) {
        val i=LABELS.indexOf(r.label);
        rc[i]++;
        val b=r.beat;
        if(b==null)miss[i]++ else confusion[i][LABELS.indexOf(b.label)]++
    };
    for(b in beats) {
        val i=LABELS.indexOf(b.label);
        val m=if(b.method=="threshold")0 else 1;
        bc[i]++;
        method[m]++;
        if(b.annotation==null)extra[i]++ else {
            tp++;
            methodTp[m]++;
            offset+=b.offset;
            absolute+=abs(b.offset);
            maxAbs=maxOf(maxAbs,abs(b.offset))
        }
    };
    val fp=beats.size-tp;
    val fn=refs.size-tp;
    val peakLine="peaks ${d.peaks.size}"+CLASSES.joinToString("") {
        " $it=${pc.getOrDefault(it,0)}"
    };
    val t=d.thresholds();
    val output=mutableListOf("DETECTOR","samples $n","duration_ms ${5*n}",peakLine,levelLine("initial_levels",
        d.initial),levelLine("final_levels",d.levels),"final_thresholds thr_i=${t[0]} thr_f=${t[1]}",
        "final_rr_averages rravg1_ms=${5*d.ra1} rravg2_ms=${5*d.ra2}","MATCHING","tolerance_ms ${p.getValue("match_ms")}",
        "references ${refs.size} N=${rc[0]} V=${rc[1]} A=${rc[2]}","detections ${beats.size} N=${bc[0]} V=${bc[1]} A=${bc[2]}",
        "true_positives $tp","false_positives $fp","false_negatives $fn","sensitivity ${Report.ratio(tp.toLong(),(tp+fn).toLong())}",
        "positive_predictivity ${Report.ratio(tp.toLong(),(tp+fp).toLong())}","detection_error_rate ${Report.ratio((fp+fn).toLong(),refs.size.toLong())}",
        "by_method threshold=${methodTp[0]}/${method[0]} searchback=${methodTp[1]}/${method[1]}",
        if(tp==0)"offset_ms none" else "offset_ms mean=${Report.two(Report.rdiv(100*offset,tp.toLong()))} mean_abs=${Report.two(Report.rdiv(100*absolute,tp.toLong()))} max_abs=$maxAbs",
        "CONFUSION","ref  "+Report.pad("N",6)+Report.pad("V",6)+Report.pad("A",6)+"  miss");
    for(i in 0..2) {
        var line=LABELS[i]+"    ";
        for(j in 0..2)line+=Report.pad(confusion[i][j].toString(),6);
        output+=line+Report.pad(miss[i].toString(),6)
    };
    output+="extra"+extra.joinToString("") {
        Report.pad(it.toString(),6)
    };
    output+=listOf("veb_sensitivity ${Report.ratio(confusion[1][1].toLong(),rc[1].toLong())}",
        "veb_positive_predictivity ${Report.ratio(confusion[1][1].toLong(),bc[1].toLong())}",
        "sveb_sensitivity ${Report.ratio(confusion[2][2].toLong(),rc[2].toLong())}","sveb_positive_predictivity ${Report.ratio(confusion[2][2].toLong(),bc[2].toLong())}",
        "SEGMENTS segment_ms=${p.getValue("segment_ms")} segments=${segments.size}");
    for(s in segments)output+="${segmentRange(s)} refs=${s.refs} tp=${s.tp} fp=${s.fp} fn=${s.fn} noise_peaks=${s.noise}";
    output+="ERRORS count=${fp+fn}";
    val errors=mutableListOf<Row>();
    for(b in beats)if(b.annotation==null)errors+=Row(b.sample,0,"false_positive beat=${b.number} sample=${b.sample} time_ms=${5*b.sample} label=${b.label}");
    for(r in refs)if(r.beat==null)errors+=Row(r.sample,1,"false_negative sample=${r.sample} time_ms=${5*r.sample} label=${r.label}");
    output+=ordered(errors);
    SignalIo.write("performance.txt",output)
}
private fun runs(beats: List<Beat>): List<String> {
    val result=mutableListOf<String>();
    var i=0;
    while(i<beats.size) {
        val b=beats[i];
        if(b.label=="N") {
            i++;
            continue
        };
        var end=i;
        while(end+1<beats.size&&beats[end+1].label==b.label)end++;
        val length=end-i+1;
        result+="${b.label} ${if(length==1)"isolated" else if(length==2)"couplet" else "run"} beats=${b.number}-${beats[end].number} length=$length start_ms=${5*b.sample}";
        i=end+1
    };
    return result
}
private fun events(beats: List<Beat>,p: Map<String,Int>): List<String> {
    val result=mutableListOf<String>();
    for(i in 1 until beats.size) {
        val b=beats[i];
        if(b.rr>p.getValue("pause_ms"))result+="pause beats=$i-${i+1} rr_ms=${b.rr} start_ms=${5*beats[i-1].sample}"
    };
    for(kind in listOf("bradycardia","tachycardia")) {
        val selected=(1 until beats.size).filter {
            if(kind=="bradycardia")beats[it].rr>p.getValue("brady_ms") else beats[it].rr<p.getValue("tachy_ms")
        };
        for(range in Hrv.ranges(selected)) {
            val a=range[0];
            val b=range[1];
            val count=b-a+1;
            if(count<3)continue;
            val sum=(a..b).sumOf {
                beats[it].rr
            };
            result+="$kind beats=$a-${b+1} intervals=$count mean_hr=${Report.two(Report.rdiv(6000000L*count,sum))} start_ms=${5*beats[a-1].sample}"
        }
    };
    val ventricular=beats.indices.filter {
        beats[it].label=="V"
    };
    for(gap in listOf(2,3)) {
        val chain=mutableListOf<Int>();
        for(index in 0..ventricular.size) {
            val v=if(index==ventricular.size)-1 else ventricular[index];
            val linked=chain.isNotEmpty()&&v==chain.last()+gap&&(chain.last()+1 until v).all {
                beats[it].label=="N"
            };
            if(!linked) {
                if(chain.size>=3) {
                    val first=chain.first();
                    val last=chain.last();
                    result+="${if(gap==2)"bigeminy" else "trigeminy"} beats=${first+1}-${last+1} cycles=${chain.size} start_ms=${5*beats[first].sample}"
                };
                chain.clear()
            };
            if(v!=-1)chain+=v
        }
    };
    return result
}
private fun hrv(beats: List<Beat>,segments: List<Segment>,p: Map<String,Int>) {
    val rr=Hrv.rr(beats);
    val nn=Hrv.nn(beats);
    val output=mutableListOf("RR","beats ${beats.size}","intervals ${rr.count}","mean_rr_ms ${Report.maybe(rr.mean)}",
        if(rr.count==0)"min_rr_ms none" else "min_rr_ms ${rr.shortest} beat=${rr.shortBeat}",
        if(rr.count==0)"max_rr_ms none" else "max_rr_ms ${rr.longest} beat=${rr.longBeat}",
        "mean_hr_bpm ${Report.maybe(rr.hr)}","NN","intervals ${nn.e}","mean_nn_ms ${Report.maybe(nn.mean)}",
        "sdnn_ms ${Report.maybe(nn.sdnn)}","differences ${nn.k}","rmssd_ms ${Report.maybe(nn.rmssd)}",
        "sdsd_ms ${Report.maybe(nn.sdsd)}","nn50 ${nn.nn50}",if(nn.k==0)"pnn50 none" else "pnn50 ${Report.two(nn.pnn50)}%",
        "sd1_ms ${Report.maybe(nn.sd1)}","sd2_ms ${Report.maybe(nn.sd2)}","HISTOGRAM bin_ms=7.8125 bins=${nn.histogram.size} max=${nn.maximum}");
    for((bin,count) in nn.histogram)output+=Report.pad(Report.four(78125*bin),10)+" "+Report.pad(Report.four(78125*(bin+1)),
        10)+" "+Report.pad(count.toString(),3)+" |"+"#".repeat(count);
    output+=if(nn.e==0)"triangular_index none" else "triangular_index ${Report.fraction(nn.e.toLong(),nn.maximum.toLong())} ${Report.two(Report.rdiv(100L*nn.e,nn.maximum.toLong()))}";
    val v=beats.count {
        it.label=="V"
    };
    val a=beats.count {
        it.label=="A"
    };
    output+="PREMATURE count=${v+a} V=$v A=$a";
    for(i in beats.indices) {
        val b=beats[i];
        if(b.label=="N")continue;
        val sum=(i-8 until i).sumOf {
            beats[it].rr
        };
        var compensation="-";
        var next="-";
        if(i+1<beats.size) {
            val nextRr=beats[i+1].rr;
            val total=b.rr+nextRr;
            next=nextRr.toString();
            compensation=if(10*abs(4*total-sum)<=sum)"full" else if(4*total<sum)"partial" else "long"
        };
        output+="beat=${b.number} sample=${b.sample} label=${b.label} rr_ms=${b.rr} next_rr_ms=$next mean_ms=${Report.two(Report.rdiv(100*sum,8))} prematurity=${Report.two(Report.rdiv(80000*b.rr,sum))}% compensation=$compensation width_ms=${b.width} ref=${ref(b)}"
    };
    val runs=runs(beats);
    val events=events(beats,p);
    output+="RUNS count=${runs.size}";
    output+=runs;
    output+="EVENTS count=${events.size}";
    output+=events;
    output+="TREND segment_ms=${p.getValue("segment_ms")} segments=${segments.size}";
    for(s in segments) {
        val prefix="${segmentRange(s)} beats=${s.beats}";
        if(s.rr.isEmpty())output+="$prefix mean_hr=none min_hr=none max_hr=none |" else {
            val h=Hrv.heartRate(s.rr);
            output+="$prefix mean_hr=${Report.two(h)} min_hr=${Report.two(Report.rdiv(6000000,s.rr.max()))} max_hr=${Report.two(Report.rdiv(6000000,s.rr.min()))} |"+"#".repeat(Report.rdiv(h,
                500).toInt())
        }
    };
    SignalIo.write("hrv.txt",output)
}
private fun scale(value: Long,top: Long,bottom: Long,rows: Int)=if(top==bottom)0 else Report.rdiv((top-value)*(rows-1),top-bottom).toInt()
private fun waveform(upper: LongArray,lower: LongArray,rows: Int): List<String> {
    val top=upper.max();
    val bottom=lower.min();
    val zero=if(bottom<=0&&top>=0)scale(0,top,bottom,rows) else -1;
    return (0 until rows).map {
        row->val label=if(row==0)top.toString() else if(row==rows-1)bottom.toString() else if(row==zero)"0" else "";
        Report.pad(label,6)+" |"+upper.indices.joinToString("") {
            i->if(scale(upper[i],top,bottom,rows)<=row&&row<=scale(lower[i],top,bottom,rows))"#" else if(row==zero)"-" else " "
        }
        +"|"
    }
}
private fun axis(columns: Int,period: Int,offset: Int)="       +"+(0 until columns).joinToString("") {
    if((it+offset)%period==0)"+" else "-"
}
+"+"
private fun labelRow(heading: String,labels: Map<Int,String>): String {
    val line=StringBuilder(Report.pad(heading,6)+"  ");
    for((i,text) in labels) {
        while(line.length<8+i)line.append(' ');
        line.append(text)
    };
    return line.toString()
}
private fun charts(beats: List<Beat>,x: LongArray,p: Map<String,Int>) {
    val output=mutableListOf<String>();
    val rr=beats.drop(1).map {
        it.rr
    };
    val rows=p.getValue("chart_rows");
    if(rr.isEmpty())output+=listOf("TACHOGRAM intervals=0","POINCARE points=0") else {
        val lo=rr.min();
        val hi=rr.max();
        output+="TACHOGRAM intervals=${rr.size} min_ms=$lo max_ms=$hi rows=$rows";
        for(r in 0 until rows) {
            val label=if(r==0)hi.toString() else if(r==rows-1)lo.toString() else "";
            output+=Report.pad(label,6)+" |"+rr.joinToString("") {
                if(scale(it,hi,lo,rows)==r)"*" else " "
            }
            +"|"
        };
        output+=axis(rr.size,10,2);
        val labels=sortedMapOf<Int,String>();
        for(j in rr.indices)if((j+2)%10==0)labels[j]=(j+2).toString();
        output+=labelRow("beat",labels);
        output+=" label |"+beats.drop(1).joinToString("") {
            it.label
        }
        +"|";
        val size=p.getValue("poincare_size");
        val cells=Array(size) {
            IntArray(size)
        };
        for(j in 0 until rr.size-1) {
            val col=if(hi==lo)0 else Report.rdiv((rr[j]-lo)*(size-1),hi-lo).toInt();
            val row=scale(rr[j+1],hi,lo,size);
            cells[row][col]++
        };
        output+="POINCARE points=${rr.size-1} size=$size min_ms=$lo max_ms=$hi";
        for(r in 0 until size) {
            val label=if(r==0)hi.toString() else if(r==size-1)lo.toString() else "";
            output+=Report.pad(label,6)+" |"+cells[r].joinToString("") {
                if(it==0)"." else if(it<10)it.toString() else "#"
            }
            +"|"
        };
        output+="       +"+"-".repeat(size)+"+";
        val low=lo.toString();
        val high=hi.toString();
        output+="        "+low+" ".repeat(size-low.length-high.length)+high
    };
    for(label in LABELS) {
        val chosen=beats.filter {
            it.label==label&&it.sample>=60&&it.sample<=x.size-100
        };
        if(chosen.isEmpty()) {
            output+="TEMPLATE $label beats=0";
            continue
        };
        val template=LongArray(160);
        for(b in chosen) {
            var baseline=0L;
            for(j in -60 until -50)baseline+=x[b.sample+j];
            for(j in -60 until 100)template[j+60]+=10*x[b.sample+j]-baseline
        };
        var max=0;
        var min=0;
        for(j in template.indices) {
            template[j]=Report.rdiv(template[j],10L*chosen.size);
            if(template[j]>template[max])max=j;
            if(template[j]<template[min])min=j
        };
        output+="TEMPLATE $label beats=${chosen.size} max_uv=${template[max]} max_ms=${5*(max-60)} min_uv=${template[min]} min_ms=${5*(min-60)} rows=$rows";
        val upper=LongArray(80) {
            maxOf(template[2*it],template[2*it+1])
        };
        val lower=LongArray(80) {
            minOf(template[2*it],template[2*it+1])
        };
        output+=waveform(upper,lower,rows);
        output+=axis(80,10,0);
        val labels=sortedMapOf<Int,String>();
        for(i in 0 until 80 step 10)labels[i]=(10*i-300).toString();
        output+=labelRow("ms",labels)
    };
    SignalIo.write("charts.txt",output)
}
private fun rhythm(beats: List<Beat>,refs: List<SignalIo.Annotation>,x: LongArray,p: Map<String,Int>) {
    val start=p.getValue("strip_start_ms")/5;
    val length=p.getValue("strip_ms")/5;
    val columns=length/10;
    val rows=p.getValue("strip_rows");
    val upper=LongArray(columns) {
        Long.MIN_VALUE
    };
    val lower=LongArray(columns) {
        Long.MAX_VALUE
    };
    for(i in 0 until length) {
        val v=x[start+i];
        val c=i/10;
        upper[c]=maxOf(upper[c],v);
        lower[c]=minOf(lower[c],v)
    };
    val output=mutableListOf("RHYTHM start_ms=${p.getValue("strip_start_ms")} end_ms=${p.getValue("strip_start_ms")+p.getValue("strip_ms")} columns=$columns rows=$rows max_uv=${upper.max()} min_uv=${lower.min()}");
    output+=waveform(upper,lower,rows);
    output+=axis(columns,20,0);
    val labels=sortedMapOf<Int,String>();
    for(i in 0 until columns step 20)labels[i]=((p.getValue("strip_start_ms")+50*i)/1000).toString();
    output+=labelRow("s",labels);
    val detected=CharArray(columns) {
        ' '
    };
    val reference=CharArray(columns) {
        ' '
    };
    for(b in beats)if(b.sample in start until start+length)detected[(b.sample-start)/10]=b.label[0];
    for(r in refs)if(r.sample in start until start+length)reference[(r.sample-start)/10]=r.label[0];
    output+=" beats |"+detected.concatToString()+"|";
    output+="  refs |"+reference.concatToString()+"|";
    SignalIo.write("rhythm_strip.txt",output)
}
fun main() {
    val x=SignalIo.ecg();
    val refs=SignalIo.annotations();
    val p=SignalIo.parameters();
    val f=Filters.apply(x);
    val peaks=Detector.peaks(f);
    val d=Detection(peaks,f,p);
    d.run(x.size);
    val beats=beats(d,f,p);
    match(beats,refs,p.getValue("match_ms")/5);
    val segments=segments(beats,refs,peaks,x.size,p.getValue("segment_ms")/5);
    lists(beats,refs,peaks,x,f,p);
    performance(d,beats,refs,segments,x.size,p);
    hrv(beats,segments,p);
    charts(beats,x,p);
    rhythm(beats,refs,x,p)
}
