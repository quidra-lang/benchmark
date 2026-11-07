local signals=require("signals")
local effects=require("effects")
local filters=require("filters")
local dynamics=require("dynamics")
local analysis=require("analysis")
local format=string.format
local function append(a,b) for _,v in ipairs(b) do a[#a+1]=v end end
local function slice(x,first,last) local out={};for j=first,last do out[#out+1]=x[j] end;return out end
local function named(name) return {name=name,kind="name"} end
local function source() return {name="src",kind="signal"} end
local function bounded(name,low,high) return {name=name,kind="integer",low=low,high=high} end
local function commands()
 local dst,src=named("dst"),source()
 return {
  SET={args={named("var"),bounded("value",-10000000,10000000),{name="op",kind="setop"},bounded("operand",-10000000,10000000)}},
  IMPULSE={args={dst,bounded("rate",1000,48000),bounded("count",1,20000),bounded("pos",0,20000),bounded("amp",-32768,32767)}},
  STEP={args={dst,bounded("rate",1000,48000),bounded("count",1,20000),bounded("pos",0,20000),bounded("amp",-32768,32767)}},
  NOISE={args={dst,bounded("rate",1000,48000),bounded("count",1,20000),bounded("seed",1,2147483646)}},
  GAIN={args={dst,src,bounded("num",-65536,65536),bounded("den",1,65536)}},
  MIX={args={dst,bounded("den",1,65536)},repeated={src,bounded("weight",-65536,65536)},minimum=1,maximum=8},
  DELAY={args={dst,src,bounded("samples",0,20000)}},
  ECHO={args={dst,src,bounded("delay",1,20000),bounded("num",-65536,65536),bounded("den",1,65536),bounded("tail",0,20000)}},
  RESAMPLE={args={dst,src,bounded("new_rate",1000,48000)}},
  FADE={args={dst,src,bounded("in",0,20000),bounded("out",0,20000)}},
  TRIM={args={dst,src,bounded("start",0,20000),bounded("count",1,20000)}},
  CONCAT={args={dst},repeated={src},minimum=2,maximum=8},
  FIR={args={dst,src,bounded("divisor",1,1000000)},repeated={bounded("tap",-32768,32767)},minimum=1,maximum=64},
  BIQUAD={args={dst,src},repeated={bounded("b0",-65536,65536),bounded("b1",-65536,65536),bounded("b2",-65536,65536),bounded("a1",-65536,65536),bounded("a2",-65536,65536)},minimum=1,maximum=4},
  MOVAVG={args={dst,src,bounded("width",1,1000)}},
  DCBLOCK={args={dst,src,bounded("num",0,65535),bounded("den",1,65536)}},
  NORMALIZE={args={dst,src,bounded("target",1,32767)}},
  GATE={args={dst,src,bounded("threshold",1,32768),bounded("hold",0,20000)}},
  ENVELOPE={args={dst,src,bounded("attack",1,32768),bounded("release",1,32768)}},
  COMPRESS={args={dst,src,bounded("threshold",1,32767),bounded("ratio_num",1,100),bounded("ratio_den",1,100),bounded("attack",1,32768),bounded("release",1,32768)}},
  ANALYZE={args={src,bounded("min_hz",1,48000),bounded("max_hz",1,48000)}},
  COMPARE={args={src,src}},
  EXPECT={args={src,{name="metric",kind="metric"},{name="op",kind="expectop"},bounded("value",-1000000000,1000000000)}},
  SEGMENTS={args={src,bounded("threshold",1,32768),bounded("gap",1,20000),bounded("min_length",1,20000)}},
  ONSETS={args={src,bounded("attack",1,32768),bounded("release",1,32768),bounded("threshold",1,32767),bounded("min_gap",1,20000)}},
  PITCHTRACK={args={src,bounded("frame",16,20000),bounded("hop",1,20000),bounded("min_hz",1,48000),bounded("max_hz",1,48000),bounded("threshold",0,32767)}},
  EXCERPT={args={src,bounded("start",0,20000),bounded("count",1,1000)}},
  PLOT={args={src,bounded("start",0,20000),bounded("count",1,20000),bounded("columns",8,120),bounded("half",2,20),bounded("attack",1,32768),bounded("release",1,32768)}},
  METER={args={src,bounded("block",1,20000)}},
  HISTOGRAM={args={src,bounded("bins",2,64)}},TRACE={args={src}},SAVE={args={src}}
 }
end
local function argument_specs(name,command,count)
 if name=="SET" then if count==2 then return {command.args[1],command.args[2]} end;return count==4 and command.args or nil end
 if not command.repeated then return count==#command.args and command.args or nil end
 local remaining=count-#command.args;if remaining<0 or remaining%#command.repeated~=0 then return nil end;local groups=remaining//#command.repeated;if groups<command.minimum or groups>command.maximum then return nil end
 local out={};append(out,command.args);for _=1,groups do append(out,command.repeated) end;return out
end
local function valid_name(token)
 if #token<1 or #token>16 then return false end;local first=token:byte(1);if first<97 or first>122 then return false end
 for j=2,#token do local c=token:byte(j);if not (c>=97 and c<=122 or c>=48 and c<=57 or c==95) then return false end end;return true
end
local function valid_integer(token)
 local digits=token:sub(1,1)=="-" and token:sub(2) or token
 if #digits<1 or #digits>10 or #digits>1 and digits:sub(1,1)=="0" or token=="-0" then return false end
 for j=1,#digits do local c=digits:byte(j);if c<48 or c>57 then return false end end;return true
end
local function value(args,name) for _,arg in ipairs(args) do if arg.spec.name==name then return arg.integer end end;return 0 end
local function first_signal(args) for _,arg in ipairs(args) do if arg.signal then return arg.signal end end end
local function bounds(command,spec,args)
 local low,high=spec.low,spec.high;local s=first_signal(args);local name=spec.name
 if name=="pos" then high=value(args,"count")-1 elseif name=="in" or name=="out" then high=#s.samples elseif name=="start" then high=#s.samples-1
 elseif name=="count" then if command=="TRIM" or command=="PLOT" then high=#s.samples-value(args,"start") end
 elseif name=="den" then if command=="DCBLOCK" then low=value(args,"num")+1 end
 elseif name=="ratio_den" then high=value(args,"ratio_num") elseif name=="frame" then high=#s.samples elseif name=="hop" then high=value(args,"frame")
 elseif name=="min_hz" then high=s.rate//2-1 elseif name=="max_hz" then low=value(args,"min_hz")+1;high=s.rate//2 elseif name=="columns" then high=math.min(120,value(args,"count")) end
 return low,high
end
local function member(token,choices) for _,choice in ipairs(choices) do if token==choice then return true end end;return false end
local P={};P.__index=P
function P:parse(name,specs,tokens)
 local args={}
 for j,spec in ipairs(specs) do local token=tokens[j];local arg={spec=spec,token=token}
  if spec.kind=="name" then if not valid_name(token) then return nil,"bad name "..token end
  elseif spec.kind=="signal" then arg.signal=self.signals[token];if not arg.signal then return nil,"unknown signal "..token end
  elseif spec.kind=="metric" then if not member(token,{"samples","peak","rms","sum","zero_crossings","clipped"}) then return nil,"unknown metric "..token end
  elseif spec.kind=="setop" then if not member(token,{"+","-","*","/"}) then return nil,"unknown operator "..token end
  elseif spec.kind=="expectop" then if not member(token,{"eq","ne","lt","le","gt","ge"}) then return nil,"unknown operator "..token end
  else
   if token:sub(1,1)=="$" then arg.integer=self.variables[token:sub(2)];if arg.integer==nil then return nil,"undefined variable "..token end else if not valid_integer(token) then return nil,"bad integer "..token end;arg.integer=tonumber(token) end
   local low,high=bounds(name,spec,args);if arg.integer<low or arg.integer>high then return nil,spec.name.." out of range" end
  end;args[#args+1]=arg
 end
 return args
end
local function lag_range(args) local s=first_signal(args);local minimum,maximum=value(args,"min_hz"),value(args,"max_hz");return (s.rate+maximum-1)//maximum,s.rate//minimum end
local function set_result(args)
 local v=args[2].integer;if #args==2 then return v end;local operand=args[4].integer;local op=args[3].token
 if op=="+" then return v+operand elseif op=="-" then return v-operand elseif op=="*" then return v*operand end;return v//operand
end
local function checks(name,args)
 local s=first_signal(args)
 if name=="SET" then if #args==4 and args[3].token=="/" and args[4].integer==0 then return "division by zero" end;if math.abs(set_result(args))>10000000 then return "value out of range" end
 elseif name=="MIX" or name=="CONCAT" or name=="COMPARE" then local total=0;for _,arg in ipairs(args) do if arg.signal then if arg.signal.rate~=s.rate then return "rate mismatch" end;total=total+#arg.signal.samples end end;if name=="CONCAT" and total>20000 then return "result too long" end
 elseif name=="DELAY" then if #s.samples+value(args,"samples")>20000 then return "result too long" end
 elseif name=="ECHO" then if math.abs(value(args,"num"))>=value(args,"den") then return "unstable feedback" end;if #s.samples+value(args,"tail")>20000 then return "result too long" end
 elseif name=="RESAMPLE" then if (#s.samples-1)*value(args,"new_rate")//s.rate+1>20000 then return "result too long" end
 elseif name=="ANALYZE" or name=="PITCHTRACK" then local low,high=lag_range(args);if low>high then return "empty lag range" end;if name=="ANALYZE" and high>=#s.samples then return "signal too short" end;if name=="PITCHTRACK" and high>=value(args,"frame") then return "frame too short" end
 end
end
function P:generate(name,args,line)
 local s=first_signal(args);local x=s and s.samples or nil;local rate=s and s.rate or value(args,"rate");local function v(key) return value(args,key) end;local y,count;local extra=""
 if name=="IMPULSE" or name=="STEP" or name=="NOISE" then y=signals.test(name,v("count"),v("pos"),v("amp"),v("seed"))
 elseif name=="GAIN" then y,count=effects.gain(x,v("num"),v("den"));extra=" clipped="..count
 elseif name=="MIX" then local tracks,weights={},{};for j=3,#args,2 do tracks[#tracks+1]=args[j].signal;weights[#weights+1]=args[j+1].integer end;y,count=effects.mix(tracks,weights,v("den"));extra=" clipped="..count
 elseif name=="DELAY" then y=effects.delay(x,v("samples"))
 elseif name=="ECHO" then y,count=effects.echo(x,v("delay"),v("num"),v("den"),v("tail"));extra=" clipped="..count
 elseif name=="RESAMPLE" then rate=v("new_rate");y=effects.resample(x,s.rate,rate)
 elseif name=="FADE" then y=effects.fade(x,v("in"),v("out"))
 elseif name=="TRIM" then y=slice(x,v("start")+1,v("start")+v("count"))
 elseif name=="CONCAT" then y={};for _,arg in ipairs(args) do if arg.signal then append(y,arg.signal.samples) end end
 elseif name=="FIR" then local taps={};for j=4,#args do taps[#taps+1]=args[j].integer end;y,count=filters.fir(x,v("divisor"),taps);extra=" clipped="..count
 elseif name=="BIQUAD" then local coefficients={};for j=3,#args do coefficients[#coefficients+1]=args[j].integer end;y,count=filters.biquad(x,coefficients);extra=format(" sections=%d clipped=%d",#coefficients//5,count)
 elseif name=="MOVAVG" then y=filters.moving_average(x,v("width"))
 elseif name=="DCBLOCK" then y,count=filters.dc_block(x,v("num"),v("den"));extra=" clipped="..count
 elseif name=="NORMALIZE" then y,count=dynamics.normalize(x,v("target"));extra=" source_peak="..count
 elseif name=="GATE" then y,count=dynamics.gate(x,v("threshold"),v("hold"));extra=" muted="..count
 elseif name=="ENVELOPE" then y=dynamics.envelope(x,v("attack"),v("release"))
 elseif name=="COMPRESS" then local reduced;y,count,reduced=dynamics.compress(x,v("threshold"),v("ratio_num"),v("ratio_den"),v("attack"),v("release"));extra=format(" min_gain=%d reduced=%d",count,reduced)
 else return nil end
 local result={name=args[1].token,rate=rate,samples=y,origin=format("line %d %s",line,name),ingredients={}};for _,arg in ipairs(args) do if arg.signal then result.ingredients[#result.ingredients+1]=arg.signal end end;self.signals[result.name]=result
 return format("%s rate=%d samples=%d peak=%d sum=%d%s",result.name,result.rate,#y,signals.peak(y),signals.sum(y),extra)
end
local function metric(s,name)
 local x=s.samples;if name=="samples" then return #x elseif name=="peak" then return signals.peak(x) elseif name=="rms" then return analysis.rms(x) elseif name=="sum" then return signals.sum(x) elseif name=="zero_crossings" then return analysis.crossings(x) end;return analysis.clipped(x)
end
local function comparison(a,b,op)
 if op=="eq" then return a==b elseif op=="ne" then return a~=b elseif op=="lt" then return a<b elseif op=="le" then return a<=b elseif op=="gt" then return a>b end;return a>=b
end
local function trace_lines(s,depth)
 local lines={string.rep(" ",2*depth)..s.name.." <- "..s.origin};for _,ingredient in ipairs(s.ingredients) do append(lines,trace_lines(ingredient,depth+1)) end;return lines
end
local function segment_lines(s,threshold,gap,min_length)
 local segments={};for n,v in ipairs(s.samples) do if math.abs(v)>=threshold then local i=n-1;local last=segments[#segments];if not last or i-last.last>gap then segments[#segments+1]={first=i,last=i} else last.last=i end end end
 local lines={};for _,segment in ipairs(segments) do if segment.last-segment.first+1>=min_length then local x=slice(s.samples,segment.first+1,segment.last+1);lines[#lines+1]=format("  segment %d start=%d end=%d start_ms=%d end_ms=%d peak=%d rms=%d crossings=%d",#lines+1,segment.first,segment.last,segment.first*1000//s.rate,segment.last*1000//s.rate,signals.peak(x),analysis.rms(x),analysis.crossings(x)) end end;return lines
end
local function onset_lines(s,attack,release,threshold,min_gap)
 local env=dynamics.envelope(s.samples,attack,release);local onsets={};for n,e in ipairs(env) do local i=n-1;if e>=threshold and (n==1 or env[n-1]<threshold) and (#onsets==0 or i-onsets[#onsets]>=min_gap) then onsets[#onsets+1]=i end end
 local tempo="none";if #onsets>=2 then local differences={};for j=2,#onsets do differences[#differences+1]=onsets[j]-onsets[j-1] end;table.sort(differences);tempo=analysis.decimal_two(signals.rdiv(6000*s.rate,differences[(#onsets-2)//2+1])) end
 local lines={};for j,n in ipairs(onsets) do lines[#lines+1]=format("  onset %d sample=%d ms=%d interval=%s",j,n,n*1000//s.rate,j==1 and "none" or tostring(n-onsets[j-1])) end;return tempo,lines
end
local function waveform(s,start,count,columns,half,attack,release)
 local x=slice(s.samples,start+1,start+count);local env=dynamics.envelope(s.samples,attack,release);local scale=math.max(1,signals.peak(x));local rows=2*half+1;local top,bottom,ec={},{},{}
 for c=0,columns-1 do local first,last=c*count//columns,(c+1)*count//columns;top[c+1],bottom[c+1],ec[c+1]=x[first+1],x[first+1],0
  for j=first,last-1 do top[c+1]=math.max(top[c+1],x[j+1]);bottom[c+1]=math.min(bottom[c+1],x[j+1]);ec[c+1]=math.max(ec[c+1],env[start+j+1]) end;ec[c+1]=math.min(scale,ec[c+1])
 end
 local function row_of(v) return signals.rdiv((scale-v)*(rows-1),2*scale) end
 local lines={format("PLOT %s rate=%d start=%d count=%d columns=%d rows=%d scale=%d attack=%d release=%d",s.name,s.rate,start,count,columns,rows,scale,attack,release)}
 for r=0,rows-1 do local band={};for c=1,columns do local symbol=" ";if r==row_of(ec[c]) or r==row_of(-ec[c]) then symbol="*" elseif row_of(top[c])<=r and r<=row_of(bottom[c]) then symbol="#" elseif r==half then symbol="-" end;band[c]=symbol end
  local label="";if r==0 then label=tostring(scale) elseif r==half then label="0" elseif r==rows-1 then label=tostring(-scale) end;lines[#lines+1]=format("%6s |%s|",label,table.concat(band))
 end
 local axis={};for c=0,columns-1 do axis[c+1]=c%10==0 and "+" or "-" end;lines[#lines+1]="       +"..table.concat(axis).."+"
 local time={};for j=1,columns+48 do time[j]=" " end;local prefix="    ms";for j=1,#prefix do time[j]=prefix:sub(j,j) end;local used=6
 for c=0,columns-1,10 do local text=tostring((start+c*count//columns)*1000//s.rate);local position=8+c;for j=1,#text do time[position+j]=text:sub(j,j) end;used=position+#text end
 lines[#lines+1]=table.concat(time,"",1,used);return lines
end
local function meter(s,block)
 local blocks=(#s.samples+block-1)//block;local lines={format("METER %s rate=%d samples=%d block=%d blocks=%d",s.name,s.rate,#s.samples,block,blocks)}
 for b=0,blocks-1 do local first,last=b*block,math.min((b+1)*block,#s.samples);local x=slice(s.samples,first+1,last);local p,q,k=signals.peak(x),analysis.rms(x),analysis.clipped(x);local np,nq=signals.rdiv(p*40,32768),signals.rdiv(q*40,32768);local bar={};for j=0,39 do bar[j+1]=j<nq and "#" or j<np and "-" or " " end;lines[#lines+1]=format("%6d |%s| peak=%d rms=%d clipped=%d",first*1000//s.rate,table.concat(bar),p,q,k) end;return lines
end
local function histogram(s,bins)
 local counts={};for j=1,bins do counts[j]=0 end;local largest=0;for _,v in ipairs(s.samples) do local b=(v+32768)*bins//65536+1;counts[b]=counts[b]+1;largest=math.max(largest,counts[b]) end
 local lines={format("HISTOGRAM %s rate=%d samples=%d bins=%d max=%d",s.name,s.rate,#s.samples,bins,largest)}
 for b=0,bins-1 do local low=(b*65536+bins-1)//bins-32768;local high=((b+1)*65536+bins-1)//bins-32768-1;lines[#lines+1]=format("%6d %6d %5d |%s",low,high,counts[b+1],string.rep("#",signals.rdiv(counts[b+1]*50,largest))) end;return lines
end
local function pitch_track(s,frame,hop,low,high,threshold)
 local frames=(#s.samples-frame)//hop+1;local levels,lags={},{};local voiced=0
 for t=0,frames-1 do local x=slice(s.samples,t*hop+1,t*hop+frame);levels[t+1]=analysis.rms(x);lags[t+1]=0;if levels[t+1]>=threshold then lags[t+1]=analysis.pitch(x,low,high);if lags[t+1]>0 then voiced=voiced+1 end end end
 local lines={format("PITCHTRACK %s rate=%d frame=%d hop=%d lags=%d-%d threshold=%d frames=%d voiced=%d",s.name,s.rate,frame,hop,low,high,threshold,frames,voiced)}
 for t=0,frames-1 do local bar={};for j=1,41 do bar[j]=" " end;local lag=lags[t+1];local suffix=format(" unvoiced rms=%d",levels[t+1]);if lag>0 then local position=high>low and signals.rdiv((high-lag)*40,high-low) or 0;bar[position+1]="o";suffix=format(" lag=%d hz=%s rms=%d",lag,analysis.frequency(s.rate,lag),levels[t+1]) end;lines[#lines+1]=format("%6d |%s|%s",t*hop*1000//s.rate,table.concat(bar),suffix) end;return lines,voiced
end
function P:execute(name,args,line)
 local generated=self:generate(name,args,line);if generated then return generated end;local s=first_signal(args);local function v(key) return value(args,key) end
 if name=="SET" then local result=set_result(args);self.variables[args[1].token]=result;return format("%s=%d",args[1].token,result)
 elseif name=="ANALYZE" then local low,high=lag_range(args);local lag=analysis.pitch(s.samples,low,high);self.analysis[#self.analysis+1]=format("%s,%d,%d,%d,%d,%s,%s,%s",s.name,signals.peak(s.samples),analysis.rms(s.samples),analysis.crossings(s.samples),analysis.clipped(s.samples),analysis.crest(s.samples),lag>0 and tostring(lag) or "none",lag>0 and analysis.frequency(s.rate,lag) or "none");return format("%s lags=%d-%d",args[1].token,low,high)
 elseif name=="COMPARE" then local a,b=args[1].signal.samples,args[2].signal.samples;local first=nil;local differing,maximum,error_energy=0,0,0;for n=1,math.max(#a,#b) do local d=(a[n] or 0)-(b[n] or 0);if d~=0 then differing=differing+1;if first==nil then first=n-1 end end;maximum=math.max(maximum,math.abs(d));error_energy=error_energy+d*d end;return format("%s %s differing=%d max_diff=%d first=%s error_energy=%d",args[1].token,args[2].token,differing,maximum,first~=nil and tostring(first) or "none",error_energy)
 elseif name=="EXPECT" then local measured=metric(s,args[2].token);local result="fail";if comparison(measured,args[4].integer,args[3].token) then result="pass";self.passed=self.passed+1 else self.failed=self.failed+1 end;return format("%s %s=%d %s %d %s",args[1].token,args[2].token,measured,args[3].token,args[4].integer,result)
 elseif name=="SEGMENTS" then local lines=segment_lines(s,v("threshold"),v("gap"),v("min_length"));return format("%s segments=%d",args[1].token,#lines),lines
 elseif name=="ONSETS" then local tempo,lines=onset_lines(s,v("attack"),v("release"),v("threshold"),v("min_gap"));return format("%s onsets=%d tempo=%s",args[1].token,#lines,tempo),lines
 elseif name=="PITCHTRACK" then local low,high=lag_range(args);local lines,voiced=pitch_track(s,v("frame"),v("hop"),low,high,v("threshold"));append(self.waveforms,lines);return format("%s frames=%d voiced=%d",args[1].token,(#s.samples-v("frame"))//v("hop")+1,voiced)
 elseif name=="EXCERPT" then local start=v("start");local count=math.min(v("count"),#s.samples-start);self.excerpts[#self.excerpts+1]=format("EXCERPT %s rate=%d samples=%d start=%d count=%d",s.name,s.rate,#s.samples,start,count)
  for first=0,count-1,8 do local text=format("%5d:",start+first);for j=first,math.min(first+7,count-1) do text=text..format(" %6d",s.samples[start+j+1]) end;self.excerpts[#self.excerpts+1]=text end;return format("%s start=%d count=%d",args[1].token,start,count)
 elseif name=="PLOT" then append(self.waveforms,waveform(s,v("start"),v("count"),v("columns"),v("half"),v("attack"),v("release")));return format("%s start=%d count=%d columns=%d rows=%d",args[1].token,v("start"),v("count"),v("columns"),2*v("half")+1)
 elseif name=="METER" then append(self.waveforms,meter(s,v("block")));return format("%s block=%d",args[1].token,v("block"))
 elseif name=="HISTOGRAM" then append(self.waveforms,histogram(s,v("bins")));return format("%s bins=%d",args[1].token,v("bins"))
 elseif name=="TRACE" then return args[1].token,trace_lines(s,1)
 elseif name=="SAVE" then append(self.saved,signals.lines(s));return format("%s samples=%d",args[1].token,#s.samples)
 end
 error("unhandled command")
end
local p=setmetatable({signals={},variables={},log={},analysis={"signal,peak,rms,zero_crossings,clipped,crest,pitch_lag,pitch_hz"},excerpts={},waveforms={},saved={},steps=0,errors=0,passed=0,failed=0},P)
for _,s in ipairs(signals.read()) do p.signals[s.name]=s;p.log[#p.log+1]=format("load %s rate=%d samples=%d peak=%d",s.name,s.rate,#s.samples,signals.peak(s.samples)) end
local file=assert(io.open("input/pipeline.txt"));local table_commands=commands();local number=0
for line in file:lines() do number=number+1;if line~="" and line:sub(1,1)~="#" then
 local tokens={};for token in line:gmatch("%S+") do tokens[#tokens+1]=token end;local name=table.remove(tokens,1);local command=table_commands[name];local args,reason
 if not command then reason="unknown command "..name else local specs=argument_specs(name,command,#tokens);if not specs then reason="wrong number of arguments" else args,reason=p:parse(name,specs,tokens);if not reason then reason=checks(name,args) end end end
 if reason then p.errors=p.errors+1;p.log[#p.log+1]=format("line %d: error: %s",number,reason) else local details,extra=p:execute(name,args,number);p.steps=p.steps+1;p.log[#p.log+1]=format("line %d: %s %s",number,name,details);if extra then append(p.log,extra) end end
end end;file:close()
local names={};for name in pairs(p.signals) do names[#names+1]=name end;table.sort(names)
for _,name in ipairs(names) do local s=p.signals[name];p.log[#p.log+1]=format("signal %s rate=%d samples=%d peak=%d rms=%d",s.name,s.rate,#s.samples,signals.peak(s.samples),analysis.rms(s.samples)) end
p.log[#p.log+1]=format("summary steps=%d errors=%d signals=%d passed=%d failed=%d",p.steps,p.errors,#names,p.passed,p.failed)
assert(os.execute("mkdir -p output"))
for _,entry in ipairs({{"log.txt",p.log},{"analysis.csv",p.analysis},{"excerpts.txt",p.excerpts},{"waveforms.txt",p.waveforms},{"signals_out.txt",p.saved}}) do local output=assert(io.open("output/"..entry[1],"w"));for _,line in ipairs(entry[2]) do output:write(line,"\n") end;output:close() end
