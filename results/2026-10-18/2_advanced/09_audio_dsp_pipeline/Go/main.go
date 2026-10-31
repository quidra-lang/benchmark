package main

import (
 "fmt"
 "os"
 "sort"
 "strconv"
 "strings"
)

type ArgKind int
const (NameArg ArgKind=iota;SignalArg;IntegerArg;MetricArg;SetOperatorArg;ExpectOperatorArg)
type ArgSpec struct { Name string; Kind ArgKind; Low,High int64 }
type Command struct { Args,Repeated []ArgSpec; Minimum,Maximum int }
type Argument struct { Spec ArgSpec; Token string; Integer int64; Signal *Signal }
type Pipeline struct { Signals map[string]*Signal; Variables map[string]int64; Log,Analysis,Excerpts,Waveforms,Saved []string; Steps,Errors,Passed,Failed int }
func named(name string) ArgSpec {return ArgSpec{Name:name,Kind:NameArg}}
func source() ArgSpec {return ArgSpec{Name:"src",Kind:SignalArg}}
func bounded(name string,low,high int64) ArgSpec {return ArgSpec{name,IntegerArg,low,high}}
func commands() map[string]Command {
 dst,src:=named("dst"),source();return map[string]Command{
  "SET":{Args:[]ArgSpec{named("var"),bounded("value",-10000000,10000000),{Name:"op",Kind:SetOperatorArg},bounded("operand",-10000000,10000000)}},
  "IMPULSE":{Args:[]ArgSpec{dst,bounded("rate",1000,48000),bounded("count",1,20000),bounded("pos",0,20000),bounded("amp",-32768,32767)}},
  "STEP":{Args:[]ArgSpec{dst,bounded("rate",1000,48000),bounded("count",1,20000),bounded("pos",0,20000),bounded("amp",-32768,32767)}},
  "NOISE":{Args:[]ArgSpec{dst,bounded("rate",1000,48000),bounded("count",1,20000),bounded("seed",1,2147483646)}},
  "GAIN":{Args:[]ArgSpec{dst,src,bounded("num",-65536,65536),bounded("den",1,65536)}},
  "MIX":{Args:[]ArgSpec{dst,bounded("den",1,65536)},Repeated:[]ArgSpec{src,bounded("weight",-65536,65536)},Minimum:1,Maximum:8},
  "DELAY":{Args:[]ArgSpec{dst,src,bounded("samples",0,20000)}},
  "ECHO":{Args:[]ArgSpec{dst,src,bounded("delay",1,20000),bounded("num",-65536,65536),bounded("den",1,65536),bounded("tail",0,20000)}},
  "RESAMPLE":{Args:[]ArgSpec{dst,src,bounded("new_rate",1000,48000)}},
  "FADE":{Args:[]ArgSpec{dst,src,bounded("in",0,20000),bounded("out",0,20000)}},
  "TRIM":{Args:[]ArgSpec{dst,src,bounded("start",0,20000),bounded("count",1,20000)}},
  "CONCAT":{Args:[]ArgSpec{dst},Repeated:[]ArgSpec{src},Minimum:2,Maximum:8},
  "FIR":{Args:[]ArgSpec{dst,src,bounded("divisor",1,1000000)},Repeated:[]ArgSpec{bounded("tap",-32768,32767)},Minimum:1,Maximum:64},
  "BIQUAD":{Args:[]ArgSpec{dst,src},Repeated:[]ArgSpec{bounded("b0",-65536,65536),bounded("b1",-65536,65536),bounded("b2",-65536,65536),bounded("a1",-65536,65536),bounded("a2",-65536,65536)},Minimum:1,Maximum:4},
  "MOVAVG":{Args:[]ArgSpec{dst,src,bounded("width",1,1000)}},
  "DCBLOCK":{Args:[]ArgSpec{dst,src,bounded("num",0,65535),bounded("den",1,65536)}},
  "NORMALIZE":{Args:[]ArgSpec{dst,src,bounded("target",1,32767)}},
  "GATE":{Args:[]ArgSpec{dst,src,bounded("threshold",1,32768),bounded("hold",0,20000)}},
  "ENVELOPE":{Args:[]ArgSpec{dst,src,bounded("attack",1,32768),bounded("release",1,32768)}},
  "COMPRESS":{Args:[]ArgSpec{dst,src,bounded("threshold",1,32767),bounded("ratio_num",1,100),bounded("ratio_den",1,100),bounded("attack",1,32768),bounded("release",1,32768)}},
  "ANALYZE":{Args:[]ArgSpec{src,bounded("min_hz",1,48000),bounded("max_hz",1,48000)}},
  "COMPARE":{Args:[]ArgSpec{src,src}},
  "EXPECT":{Args:[]ArgSpec{src,{Name:"metric",Kind:MetricArg},{Name:"op",Kind:ExpectOperatorArg},bounded("value",-1000000000,1000000000)}},
  "SEGMENTS":{Args:[]ArgSpec{src,bounded("threshold",1,32768),bounded("gap",1,20000),bounded("min_length",1,20000)}},
  "ONSETS":{Args:[]ArgSpec{src,bounded("attack",1,32768),bounded("release",1,32768),bounded("threshold",1,32767),bounded("min_gap",1,20000)}},
  "PITCHTRACK":{Args:[]ArgSpec{src,bounded("frame",16,20000),bounded("hop",1,20000),bounded("min_hz",1,48000),bounded("max_hz",1,48000),bounded("threshold",0,32767)}},
  "EXCERPT":{Args:[]ArgSpec{src,bounded("start",0,20000),bounded("count",1,1000)}},
  "PLOT":{Args:[]ArgSpec{src,bounded("start",0,20000),bounded("count",1,20000),bounded("columns",8,120),bounded("half",2,20),bounded("attack",1,32768),bounded("release",1,32768)}},
  "METER":{Args:[]ArgSpec{src,bounded("block",1,20000)}},
  "HISTOGRAM":{Args:[]ArgSpec{src,bounded("bins",2,64)}},
  "TRACE":{Args:[]ArgSpec{src}},"SAVE":{Args:[]ArgSpec{src}},
 }
}
func argumentSpecs(name string,command Command,count int) ([]ArgSpec,bool) {if name=="SET" {if count==2 {return command.Args[:2],true};return command.Args,count==4};if len(command.Repeated)==0 {return command.Args,count==len(command.Args)};remaining:=count-len(command.Args);if remaining<0||remaining%len(command.Repeated)!=0 {return nil,false};groups:=remaining/len(command.Repeated);if groups<command.Minimum||groups>command.Maximum {return nil,false};specs:=append([]ArgSpec(nil),command.Args...);for j:=0;j<groups;j++ {specs=append(specs,command.Repeated...)};return specs,true}
func validName(token string) bool {if len(token)<1||len(token)>16||token[0]<'a'||token[0]>'z' {return false};for j:=1;j<len(token);j++ {c:=token[j];if !(c>='a'&&c<='z'||c>='0'&&c<='9'||c=='_') {return false}};return true}
func validInteger(token string) bool {digits:=token;if strings.HasPrefix(digits,"-") {digits=digits[1:]};if len(digits)<1||len(digits)>10||len(digits)>1&&digits[0]=='0'||token=="-0" {return false};for _,c:=range []byte(digits) {if c<'0'||c>'9' {return false}};return true}
func valueOf(args []Argument,name string) int64 {for _,arg:=range args {if arg.Spec.Name==name {return arg.Integer}};return 0}
func firstSignal(args []Argument) *Signal {for _,arg:=range args {if arg.Signal!=nil {return arg.Signal}};return nil}
func bounds(command string,spec ArgSpec,args []Argument) (int64,int64) {low,high:=spec.Low,spec.High;s:=firstSignal(args);switch spec.Name {case "pos":high=valueOf(args,"count")-1;case "in","out":high=int64(len(s.Samples));case "start":high=int64(len(s.Samples))-1;case "count":if command=="TRIM"||command=="PLOT" {high=int64(len(s.Samples))-valueOf(args,"start")};case "den":if command=="DCBLOCK" {low=valueOf(args,"num")+1};case "ratio_den":high=valueOf(args,"ratio_num");case "frame":high=int64(len(s.Samples));case "hop":high=valueOf(args,"frame");case "min_hz":high=s.Rate/2-1;case "max_hz":low=valueOf(args,"min_hz")+1;high=s.Rate/2;case "columns":high=min(int64(120),valueOf(args,"count"))};return low,high}
func member(token string,choices ...string) bool {for _,value:=range choices {if token==value {return true}};return false}
func (p *Pipeline) parse(name string,specs []ArgSpec,tokens []string) ([]Argument,string) {
 var args []Argument
 for j,spec:=range specs {token:=tokens[j];arg:=Argument{Spec:spec,Token:token};switch spec.Kind {
  case NameArg:if !validName(token) {return nil,"bad name "+token}
  case SignalArg:signal,ok:=p.Signals[token];if !ok {return nil,"unknown signal "+token};arg.Signal=signal
  case MetricArg:if !member(token,"samples","peak","rms","sum","zero_crossings","clipped") {return nil,"unknown metric "+token}
  case SetOperatorArg:if !member(token,"+","-","*","/") {return nil,"unknown operator "+token}
  case ExpectOperatorArg:if !member(token,"eq","ne","lt","le","gt","ge") {return nil,"unknown operator "+token}
  case IntegerArg:if strings.HasPrefix(token,"$") {value,ok:=p.Variables[token[1:]];if !ok {return nil,"undefined variable "+token};arg.Integer=value} else {if !validInteger(token) {return nil,"bad integer "+token};arg.Integer=integer(token)};low,high:=bounds(name,spec,args);if arg.Integer<low||arg.Integer>high {return nil,spec.Name+" out of range"}
 };args=append(args,arg)};return args,""
}
func lagRange(args []Argument) (int64,int64) {s:=firstSignal(args);minHz,maxHz:=valueOf(args,"min_hz"),valueOf(args,"max_hz");return (s.Rate+maxHz-1)/maxHz,s.Rate/minHz}
func setResult(args []Argument) int64 {value:=args[1].Integer;if len(args)==2 {return value};operand:=args[3].Integer;switch args[2].Token {case "+":return value+operand;case "-":return value-operand;case "*":return value*operand};return floorDiv(value,operand)}
func checks(name string,args []Argument) string {s:=firstSignal(args);switch name {
 case "SET":if len(args)==4&&args[2].Token=="/"&&args[3].Integer==0 {return "division by zero"};if absolute(setResult(args))>10000000 {return "value out of range"}
 case "MIX","CONCAT","COMPARE":var signals []*Signal;var total int64;for _,arg:=range args {if arg.Signal!=nil {signals=append(signals,arg.Signal);total+=int64(len(arg.Signal.Samples))}};for _,signal:=range signals[1:] {if signal.Rate!=signals[0].Rate {return "rate mismatch"}};if name=="CONCAT"&&total>20000 {return "result too long"}
 case "DELAY":if int64(len(s.Samples))+valueOf(args,"samples")>20000 {return "result too long"}
 case "ECHO":if absolute(valueOf(args,"num"))>=valueOf(args,"den") {return "unstable feedback"};if int64(len(s.Samples))+valueOf(args,"tail")>20000 {return "result too long"}
 case "RESAMPLE":if int64(len(s.Samples)-1)*valueOf(args,"new_rate")/s.Rate+1>20000 {return "result too long"}
 case "ANALYZE","PITCHTRACK":low,high:=lagRange(args);if low>high {return "empty lag range"};if name=="ANALYZE"&&high>=int64(len(s.Samples)) {return "signal too short"};if name=="PITCHTRACK"&&high>=valueOf(args,"frame") {return "frame too short"}
 };return ""
}
func (p *Pipeline) generate(name string,args []Argument,line int) (string,bool) {
 s:=firstSignal(args);var x []int64;rate:=valueOf(args,"rate");if s!=nil {x=s.Samples;rate=s.Rate};v:=func(key string)int64{return valueOf(args,key)};var y []int64;extra:="";var count int64
 switch name {
 case "IMPULSE","STEP","NOISE":y=testSignal(name,rate,v("count"),v("pos"),v("amp"),v("seed"))
 case "GAIN":y,count=gain(x,v("num"),v("den"));extra=fmt.Sprintf(" clipped=%d",count)
 case "MIX":var signals []*Signal;var weights []int64;for j:=2;j<len(args);j+=2 {signals=append(signals,args[j].Signal);weights=append(weights,args[j+1].Integer)};y,count=mix(signals,weights,v("den"));extra=fmt.Sprintf(" clipped=%d",count)
 case "DELAY":y=delay(x,v("samples"))
 case "ECHO":y,count=echo(x,v("delay"),v("num"),v("den"),v("tail"));extra=fmt.Sprintf(" clipped=%d",count)
 case "RESAMPLE":rate=v("new_rate");y=resample(x,s.Rate,rate)
 case "FADE":y=fade(x,v("in"),v("out"))
 case "TRIM":start,count:=int(v("start")),int(v("count"));y=append([]int64(nil),x[start:start+count]...)
 case "CONCAT":for _,arg:=range args {if arg.Signal!=nil {y=append(y,arg.Signal.Samples...)}}
 case "FIR":var taps []int64;for _,arg:=range args[3:] {taps=append(taps,arg.Integer)};y,count=fir(x,v("divisor"),taps);extra=fmt.Sprintf(" clipped=%d",count)
 case "BIQUAD":var coefficients []int64;for _,arg:=range args[2:] {coefficients=append(coefficients,arg.Integer)};y,count=biquad(x,coefficients);extra=fmt.Sprintf(" sections=%d clipped=%d",len(coefficients)/5,count)
 case "MOVAVG":y=movingAverage(x,v("width"))
 case "DCBLOCK":y,count=dcBlock(x,v("num"),v("den"));extra=fmt.Sprintf(" clipped=%d",count)
 case "NORMALIZE":y,count=normalize(x,v("target"));extra=fmt.Sprintf(" source_peak=%d",count)
 case "GATE":y,count=gate(x,v("threshold"),v("hold"));extra=fmt.Sprintf(" muted=%d",count)
 case "ENVELOPE":y=envelope(x,v("attack"),v("release"))
 case "COMPRESS":var reduced int64;y,count,reduced=compress(x,v("threshold"),v("ratio_num"),v("ratio_den"),v("attack"),v("release"));extra=fmt.Sprintf(" min_gain=%d reduced=%d",count,reduced)
 default:return "",false
 }
 result:=&Signal{Name:args[0].Token,Rate:rate,Samples:y,Origin:fmt.Sprintf("line %d %s",line,name)};for _,arg:=range args {if arg.Signal!=nil {result.Ingredients=append(result.Ingredients,arg.Signal)}};p.Signals[result.Name]=result;return fmt.Sprintf("%s rate=%d samples=%d peak=%d sum=%d%s",result.Name,result.Rate,len(y),peak(y),sampleSum(y),extra),true
}
func metric(s *Signal,name string) int64 {switch name {case "samples":return int64(len(s.Samples));case "peak":return peak(s.Samples);case "rms":return rms(s.Samples);case "sum":return sampleSum(s.Samples);case "zero_crossings":return zeroCrossings(s.Samples);case "clipped":return clipped(s.Samples)};return 0}
func comparison(a,b int64,op string) bool {switch op {case "eq":return a==b;case "ne":return a!=b;case "lt":return a<b;case "le":return a<=b;case "gt":return a>b;case "ge":return a>=b};return false}
func traceLines(s *Signal,depth int) []string {lines:=[]string{strings.Repeat(" ",2*depth)+s.Name+" <- "+s.Origin};for _,ingredient:=range s.Ingredients {lines=append(lines,traceLines(ingredient,depth+1)...)};return lines}
func segmentLines(s *Signal,threshold,gap,minLength int64) []string {
 type Segment struct {Start,End int};var segments []Segment
 for n,value:=range s.Samples {if absolute(value)<threshold {continue};last:=len(segments)-1;if last<0||int64(n-segments[last].End)>gap {segments=append(segments,Segment{n,n})} else {segments[last].End=n}}
 var lines []string;for _,segment:=range segments {if int64(segment.End-segment.Start+1)<minLength {continue};x:=s.Samples[segment.Start:segment.End+1];lines=append(lines,fmt.Sprintf("  segment %d start=%d end=%d start_ms=%d end_ms=%d peak=%d rms=%d crossings=%d",len(lines)+1,segment.Start,segment.End,int64(segment.Start)*1000/s.Rate,int64(segment.End)*1000/s.Rate,peak(x),rms(x),zeroCrossings(x)))};return lines
}
func onsetLines(s *Signal,attack,release,threshold,minGap int64) (string,[]string) {env:=envelope(s.Samples,attack,release);var onsets []int;for n,e:=range env {if e>=threshold&&(n==0||env[n-1]<threshold)&&(len(onsets)==0||int64(n-onsets[len(onsets)-1])>=minGap) {onsets=append(onsets,n)}};tempo:="none";if len(onsets)>=2 {var differences []int;for j:=1;j<len(onsets);j++ {differences=append(differences,onsets[j]-onsets[j-1])};sort.Ints(differences);m:=int64(differences[(len(onsets)-2)/2]);tempo=decimalTwo(rdiv(6000*s.Rate,m))};var lines []string;for j,n:=range onsets {interval:="none";if j>0 {interval=strconv.Itoa(n-onsets[j-1])};lines=append(lines,fmt.Sprintf("  onset %d sample=%d ms=%d interval=%s",j+1,n,int64(n)*1000/s.Rate,interval))};return tempo,lines}
func waveform(s *Signal,start,count,columns,half,attack,release int64) []string {
 x:=s.Samples[int(start):int(start+count)];env:=envelope(s.Samples,attack,release);scale:=max(int64(1),peak(x));rows:=2*half+1;top,bottom,ec:=make([]int64,int(columns)),make([]int64,int(columns)),make([]int64,int(columns));for c:=int64(0);c<columns;c++ {first,last:=c*count/columns,(c+1)*count/columns;top[int(c)],bottom[int(c)]=x[int(first)],x[int(first)];for j:=first;j<last;j++ {top[int(c)]=max(top[int(c)],x[int(j)]);bottom[int(c)]=min(bottom[int(c)],x[int(j)]);ec[int(c)]=max(ec[int(c)],env[int(start+j)])};ec[int(c)]=min(scale,ec[int(c)])};rowOf:=func(value int64)int64{return rdiv((scale-value)*(rows-1),2*scale)}
 lines:=[]string{fmt.Sprintf("PLOT %s rate=%d start=%d count=%d columns=%d rows=%d scale=%d attack=%d release=%d",s.Name,s.Rate,start,count,columns,rows,scale,attack,release)}
 for r:=int64(0);r<rows;r++ {band:=make([]byte,int(columns));for c:=int64(0);c<columns;c++ {symbol:=byte(' ');if r==rowOf(ec[int(c)])||r==rowOf(-ec[int(c)]) {symbol='*'} else if rowOf(top[int(c)])<=r&&r<=rowOf(bottom[int(c)]) {symbol='#'} else if r==half {symbol='-'};band[int(c)]=symbol};label:="";if r==0 {label=strconv.FormatInt(scale,10)} else if r==half {label="0"} else if r==rows-1 {label=strconv.FormatInt(-scale,10)};lines=append(lines,fmt.Sprintf("%6s |%s|",label,string(band)))}
 axis:=[]byte(strings.Repeat("-",int(columns)));for c:=0;c<len(axis);c+=10 {axis[c]='+'};lines=append(lines,"       +"+string(axis)+"+");time:=[]byte(strings.Repeat(" ",int(columns)+48));copy(time,"    ms");used:=6;for c:=int64(0);c<columns;c+=10 {text:=strconv.FormatInt((start+c*count/columns)*1000/s.Rate,10);position:=8+int(c);copy(time[position:],text);used=position+len(text)};return append(lines,string(time[:used]))
}
func meter(s *Signal,block int64) []string {blocks:=(int64(len(s.Samples))+block-1)/block;lines:=[]string{fmt.Sprintf("METER %s rate=%d samples=%d block=%d blocks=%d",s.Name,s.Rate,len(s.Samples),block,blocks)};for b:=int64(0);b<blocks;b++ {first:=b*block;last:=min((b+1)*block,int64(len(s.Samples)));x:=s.Samples[int(first):int(last)];p,q,k:=peak(x),rms(x),clipped(x);np,nq:=rdiv(p*40,32768),rdiv(q*40,32768);bar:=[]byte(strings.Repeat(" ",40));for j:=int64(0);j<40;j++ {if j<nq {bar[int(j)]='#'} else if j<np {bar[int(j)]='-'}};lines=append(lines,fmt.Sprintf("%6d |%s| peak=%d rms=%d clipped=%d",first*1000/s.Rate,string(bar),p,q,k))};return lines}
func histogram(s *Signal,bins int64) []string {counts:=make([]int64,int(bins));var largest int64;for _,value:=range s.Samples {b:=(value+32768)*bins/65536;counts[int(b)]++;largest=max(largest,counts[int(b)])};lines:=[]string{fmt.Sprintf("HISTOGRAM %s rate=%d samples=%d bins=%d max=%d",s.Name,s.Rate,len(s.Samples),bins,largest)};for b:=int64(0);b<bins;b++ {low:=(b*65536+bins-1)/bins-32768;high:=((b+1)*65536+bins-1)/bins-32768-1;lines=append(lines,fmt.Sprintf("%6d %6d %5d |%s",low,high,counts[int(b)],strings.Repeat("#",int(rdiv(counts[int(b)]*50,largest)))))};return lines}
func pitchTrack(s *Signal,frame,hop,low,high,threshold int64) ([]string,int) {frames:=(int64(len(s.Samples))-frame)/hop+1;levels,lags:=make([]int64,int(frames)),make([]int64,int(frames));voiced:=0;for t:=int64(0);t<frames;t++ {x:=s.Samples[int(t*hop):int(t*hop+frame)];levels[int(t)]=rms(x);if levels[int(t)]>=threshold {lags[int(t)]=pitchLag(x,low,high);if lags[int(t)]>0 {voiced++}}};lines:=[]string{fmt.Sprintf("PITCHTRACK %s rate=%d frame=%d hop=%d lags=%d-%d threshold=%d frames=%d voiced=%d",s.Name,s.Rate,frame,hop,low,high,threshold,frames,voiced)};for t:=int64(0);t<frames;t++ {bar:=[]byte(strings.Repeat(" ",41));lag:=lags[int(t)];suffix:=fmt.Sprintf(" unvoiced rms=%d",levels[int(t)]);if lag>0 {position:=int64(0);if high>low {position=rdiv((high-lag)*40,high-low)};bar[int(position)]='o';suffix=fmt.Sprintf(" lag=%d hz=%s rms=%d",lag,frequency(s.Rate,lag),levels[int(t)])};lines=append(lines,fmt.Sprintf("%6d |%s|%s",t*hop*1000/s.Rate,string(bar),suffix))};return lines,voiced}
func (p *Pipeline) execute(name string,args []Argument,line int) (string,[]string) {
 if details,ok:=p.generate(name,args,line);ok {return details,nil};s:=firstSignal(args);v:=func(key string)int64{return valueOf(args,key)}
 switch name {
 case "SET":result:=setResult(args);p.Variables[args[0].Token]=result;return fmt.Sprintf("%s=%d",args[0].Token,result),nil
 case "ANALYZE":low,high:=lagRange(args);lag:=pitchLag(s.Samples,low,high);lagText,hz:="none","none";if lag>0 {lagText=strconv.FormatInt(lag,10);hz=frequency(s.Rate,lag)};p.Analysis=append(p.Analysis,fmt.Sprintf("%s,%d,%d,%d,%d,%s,%s,%s",s.Name,peak(s.Samples),rms(s.Samples),zeroCrossings(s.Samples),clipped(s.Samples),crest(s.Samples),lagText,hz));return fmt.Sprintf("%s lags=%d-%d",args[0].Token,low,high),nil
 case "COMPARE":a,b:=args[0].Signal.Samples,args[1].Signal.Samples;first:=-1;var differing,maximum,errorEnergy int64;for n:=0;n<max(len(a),len(b));n++ {var difference int64;if n<len(a) {difference+=a[n]};if n<len(b) {difference-=b[n]};if difference!=0 {differing++;if first<0 {first=n}};maximum=max(maximum,absolute(difference));errorEnergy+=difference*difference};firstText:="none";if first>=0 {firstText=strconv.Itoa(first)};return fmt.Sprintf("%s %s differing=%d max_diff=%d first=%s error_energy=%d",args[0].Token,args[1].Token,differing,maximum,firstText,errorEnergy),nil
 case "EXPECT":measured:=metric(s,args[1].Token);result:="fail";if comparison(measured,args[3].Integer,args[2].Token) {result="pass";p.Passed++} else {p.Failed++};return fmt.Sprintf("%s %s=%d %s %d %s",args[0].Token,args[1].Token,measured,args[2].Token,args[3].Integer,result),nil
 case "SEGMENTS":lines:=segmentLines(s,v("threshold"),v("gap"),v("min_length"));return fmt.Sprintf("%s segments=%d",args[0].Token,len(lines)),lines
 case "ONSETS":tempo,lines:=onsetLines(s,v("attack"),v("release"),v("threshold"),v("min_gap"));return fmt.Sprintf("%s onsets=%d tempo=%s",args[0].Token,len(lines),tempo),lines
 case "PITCHTRACK":low,high:=lagRange(args);lines,voiced:=pitchTrack(s,v("frame"),v("hop"),low,high,v("threshold"));p.Waveforms=append(p.Waveforms,lines...);frames:=(int64(len(s.Samples))-v("frame"))/v("hop")+1;return fmt.Sprintf("%s frames=%d voiced=%d",args[0].Token,frames,voiced),nil
 case "EXCERPT":start:=int(v("start"));count:=min(int(v("count")),len(s.Samples)-start);p.Excerpts=append(p.Excerpts,fmt.Sprintf("EXCERPT %s rate=%d samples=%d start=%d count=%d",s.Name,s.Rate,len(s.Samples),start,count));for first:=0;first<count;first+=8 {text:=fmt.Sprintf("%5d:",start+first);for _,sample:=range s.Samples[start+first:start+min(first+8,count)] {text+=fmt.Sprintf(" %6d",sample)};p.Excerpts=append(p.Excerpts,text)};return fmt.Sprintf("%s start=%d count=%d",args[0].Token,start,count),nil
 case "PLOT":p.Waveforms=append(p.Waveforms,waveform(s,v("start"),v("count"),v("columns"),v("half"),v("attack"),v("release"))...);return fmt.Sprintf("%s start=%d count=%d columns=%d rows=%d",args[0].Token,v("start"),v("count"),v("columns"),2*v("half")+1),nil
 case "METER":p.Waveforms=append(p.Waveforms,meter(s,v("block"))...);return fmt.Sprintf("%s block=%d",args[0].Token,v("block")),nil
 case "HISTOGRAM":p.Waveforms=append(p.Waveforms,histogram(s,v("bins"))...);return fmt.Sprintf("%s bins=%d",args[0].Token,v("bins")),nil
 case "TRACE":return args[0].Token,traceLines(s,1)
 case "SAVE":p.Saved=append(p.Saved,signalLines(s)...);return fmt.Sprintf("%s samples=%d",args[0].Token,len(s.Samples)),nil
 };panic("unhandled command")
}
func writeReport(name string,lines []string) {text:="";if len(lines)>0 {text=strings.Join(lines,"\n")+"\n"};if err:=os.WriteFile("output/"+name,[]byte(text),0644);err!=nil {panic(err)}}
func main() {
 pipeline:=Pipeline{Signals:map[string]*Signal{},Variables:map[string]int64{},Analysis:[]string{"signal,peak,rms,zero_crossings,clipped,crest,pitch_lag,pitch_hz"}}
 for _,signal:=range readSignals() {pipeline.Signals[signal.Name]=signal;pipeline.Log=append(pipeline.Log,fmt.Sprintf("load %s rate=%d samples=%d peak=%d",signal.Name,signal.Rate,len(signal.Samples),peak(signal.Samples)))}
 data,err:=os.ReadFile("input/pipeline.txt");if err!=nil {panic(err)};table:=commands();lines:=strings.Split(strings.TrimSuffix(string(data),"\n"),"\n")
 for index,line:=range lines {if line==""||line[0]=='#' {continue};tokens:=strings.Split(line," ");name:=tokens[0];command,known:=table[name];reason:="";var args []Argument
  if !known {reason="unknown command "+name} else {specs,valid:=argumentSpecs(name,command,len(tokens)-1);if !valid {reason="wrong number of arguments"} else {args,reason=pipeline.parse(name,specs,tokens[1:]);if reason=="" {reason=checks(name,args)}}}
  if reason!="" {pipeline.Errors++;pipeline.Log=append(pipeline.Log,fmt.Sprintf("line %d: error: %s",index+1,reason));continue};details,extra:=pipeline.execute(name,args,index+1);pipeline.Steps++;pipeline.Log=append(pipeline.Log,fmt.Sprintf("line %d: %s %s",index+1,name,details));pipeline.Log=append(pipeline.Log,extra...)
 }
 var names []string;for name:=range pipeline.Signals {names=append(names,name)};sort.Strings(names);for _,name:=range names {s:=pipeline.Signals[name];pipeline.Log=append(pipeline.Log,fmt.Sprintf("signal %s rate=%d samples=%d peak=%d rms=%d",s.Name,s.Rate,len(s.Samples),peak(s.Samples),rms(s.Samples)))};pipeline.Log=append(pipeline.Log,fmt.Sprintf("summary steps=%d errors=%d signals=%d passed=%d failed=%d",pipeline.Steps,pipeline.Errors,len(names),pipeline.Passed,pipeline.Failed));if err:=os.MkdirAll("output",0755);err!=nil {panic(err)};writeReport("log.txt",pipeline.Log);writeReport("analysis.csv",pipeline.Analysis);writeReport("excerpts.txt",pipeline.Excerpts);writeReport("waveforms.txt",pipeline.Waveforms);writeReport("signals_out.txt",pipeline.Saved)
}
