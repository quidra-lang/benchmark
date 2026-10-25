local dataset=require("dataset")
local variable=require("variable_charts")
local attribute=require("attribute_charts")
local rules=require("run_rules")
local capability=require("capability")
local plot=require("plot")
local format=string.format
local function real(v) local text=format("%.4f",v);return text=="-0.0000" and "0.0000" or text end
local function numbers(first,last) local r={};for i=first,last do r[#r+1]=i end;return r end
local function append(a,b) for _,v in ipairs(b) do a[#a+1]=v end end
local function without(all,removed) local set={};for _,i in ipairs(removed) do set[i]=true end;local r={};for _,i in ipairs(all) do if not set[i] then r[#r+1]=i end end;return r end
local function contains(all,n) for _,i in ipairs(all) do if i==n then return true end end;return false end
local function list(all) return #all==0 and "none" or table.concat(all," ") end
local function status(ok) return ok and "converged" or "stopped" end
local function rule_name(r) return r==9 and "UPPER" or r==10 and "LOWER" or tostring(r) end
local function limits_text(label,l) return label.." lcl "..real(l.lcl).." cl "..real(l.cl).." ucl "..real(l.ucl) end
local function pair_text(f,l) local labels={{"XBAR","R"},{"XBAR","S"},{"I","MR"}};return limits_text(labels[f][1],l[1]).." "..limits_text(labels[f][2],l[2]) end
local A={};A.__index=A
function A:family_limits(f,ns) return variable.limits(f,ns,self.groups,self.values,self.s.subgroup_size,self.c) end
function A:estimate(f)
 local last=self.s.phase1_subgroups;if f==3 then last=last*self.s.subgroup_size end
 local initial=numbers(1,last);local chosen=initial;local e={passes={},converged=false}
 for p=1,self.s.max_passes do
  local limits=self:family_limits(f,chosen);local series=variable.series(f,chosen,self.groups,self.values);local found={}
  for j,seq in ipairs(series) do for k,v in ipairs(seq.values) do if variable.outside(limits[j],v) then found[seq.numbers[k]]=true end end end
  local out={};for _,i in ipairs(chosen) do if found[i] then out[#out+1]=i end end
  e.passes[#e.passes+1]={count=#chosen,limits=limits,out=out};e.limits=limits
  if #out==0 then e.converged=true;break end
  if p==self.s.max_passes then break end
  chosen=without(chosen,out)
 end
 e.retained=chosen;e.removed=without(initial,chosen);self.estimates[f]=e
 for j,seq in ipairs(variable.series(f,chosen,self.groups,self.values)) do local chart=2*(f-1)+j;self.patterns[chart]={count=#seq.values,signals=rules.check(chart,seq,e.limits[j],self.s.rules[dataset.charts[chart]])} end
end
function A:signal_group(signal) if signal.chart==5 or signal.chart==6 then return (signal.finish-1)//self.s.subgroup_size+1 end;return signal.finish end
function A:event_of(i) for j,e in ipairs(self.events) do if e.start<=i and i<=e.finish then return j end end end
function A:has_signal(chart,finish,rule) for _,s in ipairs(self.signals) do if s.chart==chart and s.finish==finish and (not rule or s.rule==rule) then return true end end;return false end
function A:band_signal(chart,first,last,p)
 local direction,rule
 if p.value>self.mu+p.width then direction,rule="UP",9 elseif p.value<self.mu-p.width then direction,rule="DOWN",10 end
 if direction then self.signals[#self.signals+1]={chart=chart,rule=rule,start=first,finish=last,value=p.value,direction=direction} end
end
function A:monitor()
 local s=self.s;self.mu=self.estimates[1].limits[1].cl;self.sigma=self.estimates[1].limits[2].cl/self.c.d2/math.sqrt(s.subgroup_size);self.reference=s.cusum_k*self.sigma;self.h=s.cusum_h*self.sigma;self.sbar=self.estimates[2].limits[2].cl
 for chart=1,6 do
  local seq={numbers={},values={}};local first,last=s.phase1_subgroups+1,#self.groups
  if chart>=5 then first,last=s.phase1_subgroups*s.subgroup_size+1,#self.values end
  for i=first,last do
   local v;if chart==1 or chart==3 then v=self.groups[i].mean elseif chart==2 then v=self.groups[i].range elseif chart==4 then v=self.groups[i].sd elseif chart==5 then v=self.values[i] else v=math.abs(self.values[i]-self.values[i-1]) end
   seq.numbers[#seq.numbers+1]=i;seq.values[#seq.values+1]=v
  end
  append(self.signals,rules.check(chart,seq,self.estimates[(chart-1)//2+1].limits[(chart-1)%2+1],s.rules[dataset.charts[chart]]))
 end
 local upper,lower,ur,lr=0.0,0.0,0,0;local z,factor=self.mu,1.0;local q=(1-s.ewma_lambda)*(1-s.ewma_lambda);local rho=s.ewma_lambda/(2-s.ewma_lambda)
 self.ew=s.ewma_l*self.sigma*math.sqrt(rho);self.mw=3*self.sigma/math.sqrt(s.ma_span)
 for i=s.phase1_subgroups+1,#self.groups do
  local mean=self.groups[i].mean;upper=math.max(0,upper+(mean-self.mu-self.reference));lower=math.max(0,lower+(self.mu-mean-self.reference));ur=upper>0 and ur+1 or 0;lr=lower>0 and lr+1 or 0;self.upper[i]=upper;self.lower[i]=lower
  if upper>self.h then self.signals[#self.signals+1]={chart=7,rule=9,start=i-ur+1,finish=i,value=upper,direction="UP"};upper,ur=0,0 end
  if lower>self.h then self.signals[#self.signals+1]={chart=7,rule=10,start=i-lr+1,finish=i,value=lower,direction="DOWN"};lower,lr=0,0 end
  z=s.ewma_lambda*mean+(1-s.ewma_lambda)*z;factor=factor*q;local width=s.ewma_l*self.sigma*math.sqrt(rho*(1-factor));self.ewma[i]={value=z,width=width};self:band_signal(8,i,i,self.ewma[i])
  local first=math.max(s.phase1_subgroups+1,i-s.ma_span+1);local total=0;for j=first,i do total=total+self.groups[j].total end
  self.ma[i]={value=total/(s.subgroup_size*(i-first+1)),width=3*self.sigma/math.sqrt(i-first+1)};self:band_signal(9,first,i,self.ma[i])
 end
 table.sort(self.signals,function(x,y) if x.chart~=y.chart then return x.chart<y.chart end;if x.finish~=y.finish then return x.finish<y.finish end;return x.rule<y.rule end)
end
function A:build_events()
 local found={};for _,s in ipairs(self.signals) do found[self:signal_group(s)]=true end
 for i=self.s.phase1_subgroups+1,#self.groups do
  if found[i] then local e=self.events[#self.events];if e and i-e.finish-1<=self.s.event_gap then e.finish=i else self.events[#self.events+1]={start=i,finish=i,counts={0,0,0,0,0},detection={},total=0,kind=1,out=0} end end
 end
 for _,e in ipairs(self.events) do
  e.onset=e.start;local cusum=false
  for _,s in ipairs(self.signals) do
   local g=self:signal_group(s)
   if e.start<=g and g<=e.finish then
    e.total=e.total+1;e.detection[s.chart]=math.min(e.detection[s.chart] or g,g)
    local ix=5;if s.direction~="NONE" then ix=(s.chart==2 or s.chart==4 or s.chart==6) and 3 or 1;if s.direction=="DOWN" then ix=ix+1 end end;e.counts[ix]=e.counts[ix]+1
    if s.chart==7 and (not cusum or s.start<e.onset) then e.onset=s.start;cusum=true end
   end
  end
  for j=2,5 do if e.counts[j]>e.counts[e.kind] then e.kind=j end end
  local total,sd=0,0.0;for i=e.start,e.finish do local g=self.groups[i];total=total+g.total;sd=sd+g.sd;for _,v in ipairs(g.values) do if v<self.s.lsl or v>self.s.usl then e.out=e.out+1 end end end
  local length=e.finish-e.start+1;local mean=total/(self.s.subgroup_size*length);e.shift=(mean-self.mu)/self.sigma;e.spread=(sd/length)/self.sbar
 end
 for f=1,3 do
  local ns={};append(ns,self.estimates[f].retained)
  for i=self.s.phase1_subgroups+1,#self.groups do if not self:event_of(i) then if f==3 then append(ns,numbers((i-1)*self.s.subgroup_size+1,i*self.s.subgroup_size)) else ns[#ns+1]=i end end end
  self.proposals[f]={count=#ns,limits=self:family_limits(f,ns)}
 end
end
function A:estimate_attributes()
 for chart=1,4 do
  local initial=numbers(1,#self.lots);local chosen=initial;local r={passes={},converged=false,points={}};local center
  for p=1,self.s.max_passes do
   center=attribute.center(chart,chosen,self.lots);local out={};for _,i in ipairs(chosen) do if attribute.point(chart,self.lots[i],center).status~="ok" then out[#out+1]=i end end
   r.passes[#r.passes+1]={count=#chosen,center=center,out=out};if #out==0 then r.converged=true;break end;if p==self.s.max_passes then break end;chosen=without(chosen,out)
  end
  r.retained=chosen;r.removed=without(initial,chosen);local seq={numbers=initial,values={}}
  for _,l in ipairs(self.lots) do local p=attribute.point(chart,l,center);r.points[#r.points+1]=p;seq.values[#seq.values+1]=p.z end
  r.signals=rules.check(chart,seq,{lcl=-3,cl=0,ucl=3},self.s.rules.STD);self.attributes[chart]=r
 end
end
function A:limits_lines()
 local s=self.s;local lines={"characteristic "..s.characteristic,"subgroup_size "..s.subgroup_size,"subgroups "..#self.groups,"samples "..#self.values,"phase1_subgroups "..s.phase1_subgroups}
 for f,e in ipairs(self.estimates) do
  lines[#lines+1]="family "..dataset.families[f]
  for p,r in ipairs(e.passes) do lines[#lines+1]=format("pass %d points %d %s out %s",p,r.count,pair_text(f,r.limits),list(r.out)) end
  lines[#lines+1]=format("result %s passes %d retained %d removed %s",status(e.converged),#e.passes,#e.retained,list(e.removed))
 end
 for chart,p in ipairs(self.patterns) do
  for _,signal in ipairs(p.signals) do lines[#lines+1]=format("phase1_signal %s %d %d %d %s",dataset.charts[chart],signal.rule,signal.start,signal.finish,real(signal.value)) end
  lines[#lines+1]=format("phase1_check %s points %d signals %d",dataset.charts[chart],p.count,#p.signals)
 end
 for f,p in ipairs(self.proposals) do lines[#lines+1]=format("proposed %s points %d %s",dataset.families[f],p.count,pair_text(f,p.limits)) end
 local target="target "..real(self.mu).." sigma "..real(self.sigma)
 lines[#lines+1]="cusum "..target.." k "..real(self.reference).." h "..real(self.h)
 lines[#lines+1]="ewma "..target.." lcl "..real(self.mu-self.ew).." ucl "..real(self.mu+self.ew)
 lines[#lines+1]=format("ma %s span %d lcl %s ucl %s",target,s.ma_span,real(self.mu-self.mw),real(self.mu+self.mw))
 for chart,name in ipairs(dataset.charts) do
  local count,ends,counts,first=0,{},{},nil
  for _,signal in ipairs(self.signals) do if signal.chart==chart then count=count+1;ends[signal.finish]=true;counts[signal.rule]=(counts[signal.rule] or 0)+1;first=math.min(first or signal.finish,signal.finish) end end
  local distinct=0;for _ in pairs(ends) do distinct=distinct+1 end
  local points=#self.groups-s.phase1_subgroups;if chart==5 or chart==6 then points=points*s.subgroup_size end
  local selected=chart<=6 and s.rules[name] or {9,10};local by={};for _,r in ipairs(selected) do by[#by+1]=rule_name(r)..":"..(counts[r] or 0) end
  lines[#lines+1]=format("phase2 %s points %d signals %d signalled %d first %s by_rule %s",name,points,count,distinct,first and tostring(first) or "none",table.concat(by," "))
 end
 return lines
end
function A:signal_lines()
 local lines={"chart,rule,start,end,value,direction"}
 for _,s in ipairs(self.signals) do lines[#lines+1]=format("%s,%s,%d,%d,%s,%s",dataset.charts[s.chart],rule_name(s.rule),s.start,s.finish,real(s.value),s.direction) end
 return lines
end
function A:event_lines()
 local lines={"events "..#self.events};local kinds={"SHIFT_UP","SHIFT_DOWN","SPREAD_UP","SPREAD_DOWN","PATTERN"}
 for j,e in ipairs(self.events) do
  local charts,detection={},{}
  for c,name in ipairs(dataset.charts) do local g=e.detection[c];if g then charts[#charts+1]=name end;detection[#detection+1]=name..":"..(g and tostring(g) or "-") end
  lines[#lines+1]=format("event %d start %d end %d length %d signals %d charts %s location_up %d location_down %d spread_up %d spread_down %d pattern %d onset %d shift %s spread %s out_of_spec %d type %s",j,e.start,e.finish,e.finish-e.start+1,e.total,table.concat(charts,","),e.counts[1],e.counts[2],e.counts[3],e.counts[4],e.counts[5],e.onset,real(e.shift),real(e.spread),e.out,kinds[e.kind])
  lines[#lines+1]="detection "..j.." "..table.concat(detection," ")
 end
 return lines
end
function A:subgroup_lines()
 local lines={"subgroup,phase,mean,zone,range,sd,cusum_upper,cusum_lower,ewma,ma,signals,event"}
 for i,g in ipairs(self.groups) do
  local phase,monitored="phase1","-,-,-,-"
  if i>self.s.phase1_subgroups then phase="phase2";monitored=table.concat({real(self.upper[i]),real(self.lower[i]),real(self.ewma[i].value),real(self.ma[i].value)},",") elseif contains(self.estimates[1].removed,i) then phase="excluded" end
  local count=0;for _,s in ipairs(self.signals) do if self:signal_group(s)==i then count=count+1 end end
  lines[#lines+1]=format("%d,%s,%s,%s,%d,%s,%s,%d,%s",i,phase,real(g.mean),rules.zone(self.estimates[1].limits[1],g.mean),g.range,real(g.sd),monitored,count,tostring(self:event_of(i) or "-"))
 end
 return lines
end
function A:attribute_lines()
 local lines={}
 for chart,r in ipairs(self.attributes) do
  lines[#lines+1]="chart "..dataset.attributes[chart]
  for p,record in ipairs(r.passes) do lines[#lines+1]=format("pass %d lots %d center %s out %s",p,record.count,real(record.center.value),list(record.out)) end
  lines[#lines+1]=format("result %s passes %d retained %d removed %s",status(r.converged),#r.passes,#r.retained,list(r.removed))
  for j,p in ipairs(r.points) do local l=self.lots[j];local value=(chart==2 or chart==3) and tostring(p.value) or real(p.value);lines[#lines+1]=format("lot %d size %d value %s lcl %s ucl %s z %s status %s",l.number,l.inspected,value,real(p.lcl),real(p.ucl),real(p.z),p.status) end
  for _,signal in ipairs(r.signals) do lines[#lines+1]=format("signal %d %d %d %s",signal.rule,signal.start,signal.finish,real(signal.value)) end
  lines[#lines+1]="signals "..#r.signals
 end
 return lines
end
function A:capability_lines()
 local lines={};local keys={"mean","sigma_within","sigma_sbar","sigma_overall","cp","cpu","cpl","cpk","pp","ppu","ppl","ppk","cpm"}
 for j,name in ipairs({"phase1","phase2"}) do
  local chosen=j==1 and self.estimates[1].retained or numbers(self.s.phase1_subgroups+1,#self.groups);local r=capability.compute(chosen,self.groups,self.s,self.c)
  lines[#lines+1]=format("group %s subgroups %d values %d",name,#chosen,r.count)
  for _,key in ipairs(keys) do lines[#lines+1]=key.." "..real(r[key]) end
  for _,key in ipairs({"cpk_ci","ppk_ci"}) do lines[#lines+1]=key.." "..real(r[key][1]).." "..real(r[key][2]) end
  lines[#lines+1]="below_lsl "..r.below;lines[#lines+1]="above_usl "..r.above;lines[#lines+1]="ppm "..real(r.ppm)
  for _,i in ipairs(chosen) do for p,v in ipairs(self.groups[i].values) do local side;if v<self.s.lsl then side="low" elseif v>self.s.usl then side="high" end;if side then lines[#lines+1]=format("out_of_spec sample %d subgroup %d value %d side %s",(i-1)*self.s.subgroup_size+p,i,v,side) end end end
  lines[#lines+1]="verdict "..r.verdict;append(lines,capability.histogram(r.values,self.s))
 end
 for first=self.s.phase1_subgroups+1,#self.groups-self.s.rolling_window+1,self.s.rolling_step do
  local last=first+self.s.rolling_window-1;local r=capability.compute(numbers(first,last),self.groups,self.s,self.c)
  lines[#lines+1]=format("rolling %d %d mean %s sigma_within %s sigma_overall %s cpk %s ppk %s verdict %s",first,last,real(r.mean),real(r.sigma_within),real(r.sigma_overall),real(r.cpk),real(r.ppk),r.verdict)
 end
 return lines
end
function A:chart_lines()
 local lines={}
 for _,chart in ipairs({1,2,4}) do
  local f=(chart-1)//2+1;local l=self.estimates[f].limits[(chart-1)%2+1];local name=chart==1 and "XBAR" or dataset.charts[chart];lines[#lines+1]=limits_text("chart "..name,l)
  for i,g in ipairs(self.groups) do local mark=i>self.s.phase1_subgroups and "2" or contains(self.estimates[f].removed,i) and "x" or "1";local v=chart==1 and g.mean or chart==2 and g.range or g.sd;lines[#lines+1]=format("%3d %s %s %s",i,mark,plot.limits(l,v,i>self.s.phase1_subgroups and self:has_signal(chart,i)),real(v)) end
 end
 lines[#lines+1]="chart CUSUM h "..real(self.h)
 for i=self.s.phase1_subgroups+1,#self.groups do lines[#lines+1]=format("%3d %s %s %s",i,plot.cusum(self.upper[i],self.lower[i],self.h,self:has_signal(7,i,9),self:has_signal(7,i,10)),real(self.upper[i]),real(self.lower[i])) end
 for _,chart in ipairs({8,9}) do
  local scale=chart==8 and self.ew or self.mw;local points=chart==8 and self.ewma or self.ma;lines[#lines+1]=limits_text("chart "..dataset.charts[chart],{lcl=self.mu-scale,cl=self.mu,ucl=self.mu+scale})
  for i=self.s.phase1_subgroups+1,#self.groups do local p=points[i];lines[#lines+1]=format("%3d %s %s %s %s",i,plot.width(scale,p.width,p.value,self.mu,self:has_signal(chart,i)),real(p.value),real(self.mu-p.width),real(self.mu+p.width)) end
 end
 local names={"P_STD","NP_STD","C_STD","U_STD"}
 for chart,r in ipairs(self.attributes) do lines[#lines+1]="chart "..names[chart].." lcl -3.0000 cl 0.0000 ucl 3.0000";for j,p in ipairs(r.points) do lines[#lines+1]=format("%3d %s %s",self.lots[j].number,plot.standard(p.z,p.status=="ok"),real(p.z)) end end
 return lines
end
local s,values,lots=dataset.read()
local a=setmetatable({s=s,values=values,lots=lots,c=dataset.constants[s.subgroup_size-1],groups=variable.subgroups(values,s.subgroup_size),estimates={},patterns={},signals={},events={},proposals={},attributes={},upper={},lower={},ewma={},ma={}},A)
for f=1,3 do a:estimate(f) end
a:monitor();a:build_events();a:estimate_attributes()
assert(os.execute("mkdir -p output"))
local reports={{"limits.txt",a:limits_lines()},{"signals.csv",a:signal_lines()},{"events.txt",a:event_lines()},{"subgroups.csv",a:subgroup_lines()},{"attribute_charts.txt",a:attribute_lines()},{"capability.txt",a:capability_lines()},{"charts.txt",a:chart_lines()}}
for _,report in ipairs(reports) do local file=assert(io.open("output/"..report[1],"w"));file:write(table.concat(report[2],"\n"),"\n");file:close() end
