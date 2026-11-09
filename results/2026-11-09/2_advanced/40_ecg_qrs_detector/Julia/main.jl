include("signal_io.jl")
include("report.jl")
include("filters.jl")
include("detector.jl")
include("hrv.jl")
const LABELS = ("N","V","A")
const CLASSES = ("qrs","searchback","twave","refractory","noise")
mutable struct Beat
    sample::Int
    rr::Union{Nothing,Int}
    hr::Union{Nothing,Int}
    width::Int
    label::String
    method::String
    annotation::Int
    offset::Int
end
function thresholds(levels)
    i = levels[:npki]+fld(levels[:spki]-levels[:npki],4)
    f = levels[:npkf]+fld(levels[:spkf]-levels[:npkf],4)
    (thi1=i,thi2=fld(i,2),thf1=f,thf2=fld(f,2))
end
function detect_beats(peaks,signals,params)
    initial = initial_levels(signals)
    levels = copy(initial)
    registered = Peak[]
    intervals = Int[]
    ra1 = ra2 = 200
    function register(peak)
        if !isempty(registered)
            elapsed = peak.time-registered[end].time
            push!(intervals,elapsed)
            length(intervals)>8 && popfirst!(intervals)
            ra1 = sum(intervals)÷length(intervals)
            92ra1 <= 100elapsed <= 116ra1 && (ra2=ra1)
        end
        push!(registered,peak)
    end
    function update(peak,kind)
        if kind == "noise"
            levels[:npki] = fld(peak.peak_i+7levels[:npki],8)
            levels[:npkf] = fld(peak.peak_f+7levels[:npkf],8)
        else
            weight,divisor = kind == "signal" ? (7,8) : (3,4)
            levels[:spki] = fld(peak.peak_i+weight*levels[:spki],divisor)
            levels[:spkf] = fld(peak.peak_f+weight*levels[:spkf],divisor)
        end
    end
    function searchback(time)
        while true
            last_time = isempty(registered) ? 0 : registered[end].time
            time-last_time <= fld(ra2*params["searchback_percent"],100) && break
            threshold = thresholds(levels)
            candidates = [p for p in peaks if p.kind == "noise" && last_time < p.time < time
                          && p.peak_i > threshold.thi2 && p.peak_f > threshold.thf2]
            isempty(candidates) && break
            chosen = candidates[argmax([p.peak_i for p in candidates])]
            update(chosen,"searchback")
            chosen.kind = "searchback"
            register(chosen)
        end
    end
    for peak in peaks
        searchback(peak.time)
        threshold = thresholds(levels)
        peak.thr_i,peak.thr_f = threshold.thi1,threshold.thf1
        previous = isempty(registered) ? nothing : registered[end]
        elapsed = isnothing(previous) ? 0 : peak.time-previous.time
        if !isnothing(previous) && elapsed < params["refractory_ms"]÷5
            peak.kind = "refractory"
        elseif peak.peak_i > peak.thr_i && peak.peak_f > peak.thr_f
            if !isnothing(previous) && elapsed < params["twave_ms"]÷5 && 2peak.slope < previous.slope
                peak.kind = "twave"
                update(peak,"noise")
            else
                peak.kind = "qrs"
                update(peak,"signal")
                register(peak)
            end
        else
            peak.kind = "noise"
            update(peak,"noise")
        end
    end
    searchback(length(signals.integrated))
    (registered=registered,initial=initial,final=levels,threshold=thresholds(levels),ra1=ra1,ra2=ra2)
end
function build_beats(registered,band,params)
    beats = Beat[]
    for (k,peak) in enumerate(registered)
        sample = max(0,peak.r-21)
        rr = k==1 ? nothing : 5*(sample-beats[end].sample)
        width = width_ms(band,peak.r)
        label = "N"
        if k >= 10 && 800rr < params["premature_percent"]*sum(beats[j].rr for j in k-8:k-1)
            label = width > params["qrs_width_ms"] ? "V" : "A"
        end
        push!(beats,Beat(sample,rr,isnothing(rr) ? nothing : rdiv(6000000,rr),width,label,
                         peak.kind=="qrs" ? "threshold" : "searchback",0,0))
    end
    beats
end
function match_annotations!(beats,annotations,tolerance)
    matched = zeros(Int,length(annotations))
    for (k,beat) in enumerate(beats)
        candidates = [j for j in eachindex(annotations) if matched[j]==0
                      && abs(annotations[j].sample-beat.sample)<=tolerance]
        isempty(candidates) && continue
        j = candidates[argmin([abs(annotations[j].sample-beat.sample) for j in candidates])]
        matched[j] = k
        beat.annotation = j
        beat.offset = 5*(beat.sample-annotations[j].sample)
    end
    matched
end
scale(value,top,bottom,height) = top>bottom ? rdiv((top-value)*(height-1),top-bottom) : 0
axis(columns,marker) = "       +"*join(marker(i) ? "+" : "-" for i in 0:columns-1)*"+"
function label_row(heading,markers)
    text = lpad(heading,6)*"  "
    for (column,value) in markers
        text *= repeat(" ",max(0,8+column-length(text)))*string(value)
    end
    rstrip(text)
end
function waveform(upper,lower,height)
    top,bottom = maximum(upper),minimum(lower)
    zero = bottom<=0<=top ? scale(0,top,bottom,height) : -1
    lines = String[]
    for row in 0:height-1
        label = row==0 ? string(top) : row==height-1 ? string(bottom) : row==zero ? "0" : ""
        cells = join(scale(hi,top,bottom,height)<=row<=scale(lo,top,bottom,height) ? "#" :
                     row==zero ? "-" : " " for (hi,lo) in zip(upper,lower))
        push!(lines,lpad(label,6)*" |"*cells*"|")
    end
    lines
end
function segments_for(beats,annotations,matched,peaks,n,params)
    step = params["segment_ms"]÷5
    segments = NamedTuple[]
    for start in 0:step:n-1
        stop = min(start+step,n)
        refs = [j for j in eachindex(annotations) if start<=annotations[j].sample<stop]
        selected = [b for b in beats if start<=b.sample<stop]
        tp = count(j->matched[j]>0,refs)
        push!(segments,(start=5start,stop=5stop,refs=length(refs),tp=tp,fn=length(refs)-tp,
            fp=count(b->b.annotation==0,selected),beats=length(selected),
            noise=count(p->p.kind=="noise" && start<=p.time<stop,peaks),
            rr=[b.rr for b in selected if !isnothing(b.rr)]))
    end
    segments
end
function csv_outputs(ecg,signals,peaks,beats,annotations,matched,params)
    lines = ["beat,sample,time_ms,rr_ms,hr_bpm,width_ms,label,method,ref_sample,ref_label"]
    for (k,b) in enumerate(beats)
        ref = b.annotation==0 ? nothing : annotations[b.annotation]
        push!(lines,join((k,b.sample,5b.sample,missing_dash(b.rr),isnothing(b.hr) ? "-" : two(b.hr),
             b.width,b.label,b.method,isnothing(ref) ? "-" : ref.sample,isnothing(ref) ? "-" : ref.label),','))
    end
    write_lines("beats.csv",lines)
    lines = ["peak,sample,r_sample,peak_i,peak_f,slope,thr_i,thr_f,class"]
    append!(
        lines,
        [join(
            (k,p.time,p.r,p.peak_i,p.peak_f,p.slope,p.thr_i,p.thr_f,p.kind),
            ','
        ) for (k,p) in enumerate(peaks)]
    )
    write_lines("peaks.csv",lines)
    records = Tuple{Int,Int,String}[]
    for (j,ref) in enumerate(annotations)
        k = matched[j]
        row = if k==0
            (ref.sample,ref.label,"-","-","-","-","FN","-")
        else
            b = beats[k]
            (ref.sample,ref.label,k,b.sample,b.label,b.offset,"TP",ref.label==b.label ? "yes" : "no")
        end
        push!(records,(ref.sample,0,join(row,',')))
    end
    for (k,b) in enumerate(beats)
        b.annotation>0 && continue
        push!(records,(b.sample,1,join(("-","-",k,b.sample,b.label,"-","FP","-"),',')))
    end
    sort!(records;by=r->(r[1],r[2]))
    write_lines(
        "matching.csv",
        vcat(
            ["ref_sample,ref_label,beat,beat_sample,beat_label,offset_ms,status,agree"],
            [r[3] for r in records]
        )
    )
    lines = ["sample,ecg,lowpass,bandpass,derivative,squared,integrated"]
    for i in 1:params["excerpt_ms"]÷5
        push!(
            lines,
            join(
                (
                    i-1,
                    ecg[i],
                    signals.lowpass[i],
                    signals.bandpass[i],
                    signals.derivative[i],
                    signals.squared[i],
                    signals.integrated[i]
                ),
                ','
            )
        )
    end
    write_lines("signals_excerpt.csv",lines)
end
function performance_lines(beats,annotations,matched,peaks,detection,segments,params,n)
    counts = Dict(c=>count(p->p.kind==c,peaks) for c in CLASSES)
    refs = Dict(c=>count(r->r.label==c,annotations) for c in LABELS)
    detected = Dict(c=>count(b->b.label==c,beats) for c in LABELS)
    tp = count(>(0),matched)
    fn,fp = length(annotations)-tp,length(beats)-tp
    level_line(prefix,levels) = prefix*join(("$key=$(levels[key])" for key in (:spki,:npki,:spkf,:npkf))," ")
    lines = ["DETECTOR","samples $n","duration_ms $(5n)",
        "peaks $(length(peaks)) "*join(("$c=$(counts[c])" for c in CLASSES)," "),
        level_line("initial_levels ",detection.initial),level_line("final_levels ",detection.final),
        "final_thresholds thr_i=$(detection.threshold.thi1) thr_f=$(detection.threshold.thf1)",
        "final_rr_averages rravg1_ms=$(5detection.ra1) rravg2_ms=$(5detection.ra2)",
        "MATCHING","tolerance_ms $(params["match_ms"])",
        "references $(length(annotations)) "*join(("$c=$(refs[c])" for c in LABELS)," "),
        "detections $(length(beats)) "*join(("$c=$(detected[c])" for c in LABELS)," "),
        "true_positives $tp","false_positives $fp","false_negatives $fn",
        "sensitivity "*ratio(tp,tp+fn),"positive_predictivity "*ratio(tp,tp+fp),
        "detection_error_rate "*ratio(fp+fn,length(annotations))]
    methods = String[]
    for method in ("threshold","searchback")
        selected = [b for b in beats if b.method==method]
        push!(methods,"$method=$(count(b->b.annotation>0,selected))/$(length(selected))")
    end
    push!(lines,"by_method "*join(methods," "))
    offsets = [b.offset for b in beats if b.annotation>0]
    push!(lines,isempty(offsets) ? "offset_ms none" :
        "offset_ms mean=$(two(rdiv(100sum(offsets),tp))) mean_abs=$(two(rdiv(100sum(abs,offsets),tp))) max_abs=$(maximum(abs,offsets))")
    confusion = Dict{Tuple{String,String},Int}()
    for (j,ref) in enumerate(annotations)
        label = matched[j]==0 ? "miss" : beats[matched[j]].label
        key = (ref.label,label)
        confusion[key] = get(confusion,key,0)+1
    end
    for b in beats
        b.annotation>0 && continue
        key = ("extra",b.label)
        confusion[key] = get(confusion,key,0)+1
    end
    cell(a,b) = get(confusion,(a,b),0)
    push!(lines,"CONFUSION","ref  "*join(lpad(c,6) for c in LABELS)*"  miss")
    for c in LABELS
        push!(lines,c*"    "*join(lpad(cell(c,e),6) for e in (LABELS...,"miss")))
    end
    push!(lines,"extra"*join(lpad(cell("extra",e),6) for e in LABELS))
    for (c,prefix) in (("V","veb"),("A","sveb"))
        push!(lines,prefix*"_sensitivity "*ratio(cell(c,c),refs[c]),
                    prefix*"_positive_predictivity "*ratio(cell(c,c),detected[c]))
    end
    push!(lines,"SEGMENTS segment_ms=$(params["segment_ms"]) segments=$(length(segments))")
    for s in segments
        push!(
            lines,
            "$(lpad(s.start,6))-$(lpad(s.stop,6)) refs=$(s.refs) tp=$(s.tp) fp=$(s.fp) fn=$(s.fn) noise_peaks=$(s.noise)"
        )
    end
    errors = Tuple{Int,Int,String}[]
    for (k,b) in enumerate(beats)
        b.annotation>0 && continue
        push!(
            errors,
            (b.sample,0,"false_positive beat=$k sample=$(b.sample) time_ms=$(5b.sample) label=$(b.label)")
        )
    end
    for (j,ref) in enumerate(annotations)
        matched[j]>0 && continue
        push!(
            errors,
            (ref.sample,1,"false_negative sample=$(ref.sample) time_ms=$(5ref.sample) label=$(ref.label)")
        )
    end
    sort!(errors;by=e->(e[1],e[2]))
    push!(lines,"ERRORS count=$(fp+fn)")
    append!(lines,[e[3] for e in errors])
    lines
end
function hrv_lines(beats,annotations,segments,params)
    rr = [b.rr for b in beats[2:end]]
    stats = rr_statistics(rr)
    lines = ["RR","beats $(length(beats))","intervals $(length(rr))","mean_rr_ms $(maybe_two(stats.mean_rr))"]
    if isempty(rr)
        append!(lines,["min_rr_ms none","max_rr_ms none","mean_hr_bpm none"])
    else
        push!(lines,"min_rr_ms $(minimum(rr)) beat=$(argmin(rr)+1)",
            "max_rr_ms $(maximum(rr)) beat=$(argmax(rr)+1)","mean_hr_bpm $(two(stats.mean_hr))")
    end
    nn = Dict(k=>beats[k].rr for k in 3:length(beats) if beats[k-1].label=="N" && beats[k].label=="N"
              && 5abs(beats[k].rr-beats[k-1].rr)<=beats[k-1].rr)
    pairs = [(nn[k-1],nn[k]) for k in sort(collect(keys(nn))) if haskey(nn,k-1)]
    info = nn_statistics(collect(values(nn)),pairs)
    append!(lines,["NN","intervals $(info.e)","mean_nn_ms $(maybe_two(info.mean_nn))",
        "sdnn_ms $(maybe_two(info.sdnn))","differences $(info.k)","rmssd_ms $(maybe_two(info.rmssd))",
        "sdsd_ms $(maybe_two(info.sdsd))","nn50 $(info.nn50)",
        isnothing(info.pnn50) ? "pnn50 none" : "pnn50 $(two(info.pnn50))%",
        "sd1_ms $(maybe_two(info.sd1))","sd2_ms $(maybe_two(info.sd2))",
        "HISTOGRAM bin_ms=7.8125 bins=$(length(info.histogram)) max=$(info.max_count)"])
    for bin in sort(collect(keys(info.histogram)))
        bin_count = info.histogram[bin]
        push!(
            lines,
            "$(lpad(four(78125bin),10)) $(lpad(four(78125(bin+1)),10)) $(lpad(bin_count,3)) |"*repeat(
                "#",
                bin_count
            )
        )
    end
    push!(
        lines,
        info.e==0 ? "triangular_index none" : "triangular_index $(fraction(info.e,info.max_count)) $(two(info.triangular_index))"
    )
    premature = [k for k in eachindex(beats) if beats[k].label!="N"]
    push!(
        lines,
        "PREMATURE count=$(length(premature)) V=$(count(k->beats[k].label=="V",premature)) A=$(count(k->beats[k].label=="A",premature))"
    )
    for k in premature
        b = beats[k]
        total = sum(beats[j].rr for j in k-8:k-1)
        next_rr = k<length(beats) ? beats[k+1].rr : nothing
        compensation = isnothing(next_rr) ? "-" : 10abs(4*(b.rr+next_rr)-total)<=total ? "full" : 4*(b.rr+next_rr)<total ? "partial" : "long"
        ref = b.annotation==0 ? "-" : annotations[b.annotation].label
        push!(
            lines,
            "beat=$k sample=$(b.sample) label=$(b.label) rr_ms=$(b.rr) next_rr_ms=$(missing_dash(next_rr)) mean_ms=$(two(rdiv(100total,8))) prematurity=$(two(rdiv(80000b.rr,total)))% compensation=$compensation width_ms=$(b.width) ref=$ref"
        )
    end
    runs = Tuple{Int,String}[]
    for label in ("V","A")
        for (a,b) in consecutive_ranges([k for k in eachindex(beats) if beats[k].label==label])
            length_run = b-a+1
            kind = length_run==1 ? "isolated" : length_run==2 ? "couplet" : "run"
            push!(runs,(a,"$label $kind beats=$a-$b length=$length_run start_ms=$(5beats[a].sample)"))
        end
    end
    sort!(runs;by=r->r[1])
    push!(lines,"RUNS count=$(length(runs))")
    append!(lines,[r[2] for r in runs])
    events = String[]
    for k in 2:length(beats)
        beats[k].rr > params["pause_ms"] || continue
        push!(events,"pause beats=$(k-1)-$k rr_ms=$(beats[k].rr) start_ms=$(5beats[k-1].sample)")
    end
    for (kind,key) in (("bradycardia","brady_ms"),("tachycardia","tachy_ms"))
        selected = [k for k in 2:length(beats) if kind=="bradycardia" ? beats[k].rr>params[key] : beats[k].rr<params[key]]
        for (a,b) in consecutive_ranges(selected)
            b-a+1>=3 || continue
            hr = rdiv(6000000*(b-a+1),sum(beats[k].rr for k in a:b))
            push!(
                events,
                "$kind beats=$(a-1)-$b intervals=$(b-a+1) mean_hr=$(two(hr)) start_ms=$(5beats[a-1].sample)"
            )
        end
    end
    ventricular = [k for k in eachindex(beats) if beats[k].label=="V"]
    for (kind,span) in (("bigeminy",2),("trigeminy",3))
        chains = Vector{Int}[]
        for k in ventricular
            if !isempty(chains) && k==chains[end][end]+span && all(beats[j].label=="N" for j in chains[end][end]+1:k-1)
                push!(chains[end],k)
            else
                push!(chains,[k])
            end
        end
        for chain in chains
            length(chain)>=3 || continue
            push!(
                events,
                "$kind beats=$(chain[1])-$(chain[end]) cycles=$(length(chain)) start_ms=$(5beats[chain[1]].sample)"
            )
        end
    end
    push!(lines,"EVENTS count=$(length(events))")
    append!(lines,events)
    push!(lines,"TREND segment_ms=$(params["segment_ms"]) segments=$(length(segments))")
    for s in segments
        header = "$(lpad(s.start,6))-$(lpad(s.stop,6)) beats=$(s.beats) "
        if isempty(s.rr)
            push!(lines,header*"mean_hr=none min_hr=none max_hr=none |")
        else
            hr = rdiv(6000000length(s.rr),sum(s.rr))
            push!(
                lines,
                header*"mean_hr=$(two(hr)) min_hr=$(two(rdiv(6000000,maximum(s.rr)))) max_hr=$(two(rdiv(6000000,minimum(s.rr)))) |"*repeat(
                    "#",
                    rdiv(hr,500)
                )
            )
        end
    end
    lines
end
function chart_lines(ecg,beats,params)
    rr = [b.rr for b in beats[2:end]]
    height = params["chart_rows"]
    lines = String[]
    if isempty(rr)
        append!(lines,["TACHOGRAM intervals=0","POINCARE points=0"])
    else
        lo,hi = minimum(rr),maximum(rr)
        push!(lines,"TACHOGRAM intervals=$(length(rr)) min_ms=$lo max_ms=$hi rows=$height")
        for row in 0:height-1
            label = row==0 ? string(hi) : row==height-1 ? string(lo) : ""
            push!(lines,lpad(label,6)*" |"*join(scale(v,hi,lo,height)==row ? "*" : " " for v in rr)*"|")
        end
        push!(lines,axis(length(rr),j->(j+2)%10==0),label_row("beat",[(j,string(j+2)) for j in 0:length(rr)-1 if (j+2)%10==0]),
              " label |"*join(b.label for b in beats[2:end])*"|")
        size = params["poincare_size"]
        cells = zeros(Int,size,size)
        for k in 1:length(rr)-1
            column = hi>lo ? rdiv((rr[k]-lo)*(size-1),hi-lo) : 0
            row = scale(rr[k+1],hi,lo,size)
            cells[row+1,column+1] += 1
        end
        push!(lines,"POINCARE points=$(length(rr)-1) size=$size min_ms=$lo max_ms=$hi")
        for row in 0:size-1
            label = row==0 ? string(hi) : row==size-1 ? string(lo) : ""
            text = join(c==0 ? "." : c<=9 ? string(c) : "#" for c in cells[row+1,:])
            push!(lines,lpad(label,6)*" |"*text*"|")
        end
        push!(
            lines,
            axis(size,_->false),
            "        "*string(lo)*repeat(" ",max(0,size-length(string(lo))-length(string(hi))))*string(hi)
        )
    end
    for label in LABELS
        chosen = [b for b in beats if b.label==label && 60<=b.sample<=length(ecg)-100]
        if isempty(chosen)
            push!(lines,"TEMPLATE $label beats=0")
            continue
        end
        baselines = [sum(ecg[b.sample-59:b.sample-50]) for b in chosen]
        averaged = [rdiv(
            sum(10ecg[b.sample+j+1]-baselines[k] for (k,b) in enumerate(chosen)),
            10length(chosen)
        ) for j in -60:99]
        push!(
            lines,
            "TEMPLATE $label beats=$(length(chosen)) max_uv=$(maximum(averaged)) max_ms=$(5*(argmax(averaged)-61)) min_uv=$(minimum(averaged)) min_ms=$(5*(argmin(averaged)-61)) rows=$height"
        )
        append!(lines,waveform([max(averaged[2i+1],averaged[2i+2]) for i in 0:79],
                             [min(averaged[2i+1],averaged[2i+2]) for i in 0:79],height))
        push!(lines,axis(80,i->i%10==0),label_row("ms",[(i,string(10i-300)) for i in 0:10:70]))
    end
    lines
end
function rhythm_lines(ecg,beats,annotations,params)
    start = params["strip_start_ms"]÷5
    n = params["strip_ms"]÷5
    columns,height = n÷10,params["strip_rows"]
    excerpt = ecg[start+1:start+n]
    upper = [maximum(excerpt[10i+1:10i+10]) for i in 0:columns-1]
    lower = [minimum(excerpt[10i+1:10i+10]) for i in 0:columns-1]
    lines = ["RHYTHM start_ms=$(params["strip_start_ms"]) end_ms=$(params["strip_start_ms"]+params["strip_ms"]) columns=$columns rows=$height max_uv=$(maximum(excerpt)) min_uv=$(minimum(excerpt))"]
    append!(lines,waveform(upper,lower,height))
    push!(
        lines,
        axis(columns,i->i%20==0),
        label_row("s",[(i,string(fld(params["strip_start_ms"]+50i,1000))) for i in 0:20:columns-1])
    )
    beat_marks,ref_marks = fill(" ",columns),fill(" ",columns)
    for b in beats
        start<=b.sample<start+n && (beat_marks[fld(b.sample-start,10)+1]=b.label)
    end
    for ref in annotations
        start<=ref.sample<start+n && (ref_marks[fld(ref.sample-start,10)+1]=ref.label)
    end
    push!(lines," beats |"*join(beat_marks)*"|","  refs |"*join(ref_marks)*"|")
    lines
end
function main()
    ecg,annotations,params = read_ecg(),read_annotations(),read_params()
    signals = filter_ecg(ecg)
    peaks = find_peaks(signals)
    detection = detect_beats(peaks,signals,params)
    beats = build_beats(detection.registered,signals.bandpass,params)
    matched = match_annotations!(beats,annotations,params["match_ms"]÷5)
    segments = segments_for(beats,annotations,matched,peaks,length(ecg),params)
    csv_outputs(ecg,signals,peaks,beats,annotations,matched,params)
    write_lines(
        "performance.txt",
        performance_lines(beats,annotations,matched,peaks,detection,segments,params,length(ecg))
    )
    write_lines("hrv.txt",hrv_lines(beats,annotations,segments,params))
    write_lines("charts.txt",chart_lines(ecg,beats,params))
    write_lines("rhythm_strip.txt",rhythm_lines(ecg,beats,annotations,params))
end
main()
