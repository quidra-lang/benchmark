local baskets=require("baskets")
local apriori=require("apriori")
local growth=require("fpgrowth")
local rules=require("rules")
local report=require("report")
local format=string.format
local F,FT=rules.fraction,report.fraction
local function append(a,b) for _,v in ipairs(b) do a[#a+1]=v end end
local function keys(map) local out={};for key in pairs(map) do out[#out+1]=key end;table.sort(out);return out end
local function has(ids,id) for _,i in ipairs(ids) do if i==id then return true end end;return false end
local function count_keys(map) local count=0;for _ in pairs(map) do count=count+1 end;return count end
local function read_params()
 local p={};for _,line in ipairs(baskets.lines("params.txt")) do local key,value=line:match("^(%S+) (%S+)$");local n,d=value:match("^(%d+)/(%d+)$");p[key]=n and F(tonumber(n),tonumber(d)) or tonumber(value) end;return p
end
local A={};A.__index=A
function A.read()
 local a=setmetatable({p=read_params(),names={},products={},product_ids={},category_ids={},taxonomy={},errors={},item_rows=0,transaction_rows=0,adopted=0,duplicates=0,transactions=0,empty=0,baskets={},train={},test={},buyers={},heldout={},hits={},units={},revenue={},evaluation={},total_evaluation={cases=0,covered=0,hit1=0,hit=0,baseline=0},validation={},emerging=0,hold=0,fail=0,unseen=0,sequence_lines={},sequence_pairs=0,frequent_sequences=0,multi_day=0,total_units=0,total_revenue=0},A)
 local by_name,categories={},{}
 for j,row in ipairs(baskets.records("items.csv")) do
  a.item_rows=a.item_rows+1;local p={name=row[1],category=row[2],price=tonumber(row[3])};local reason
  if by_name[p.name] then reason="duplicate item "..p.name elseif p.price==0 then reason="bad price 0" end
  if reason then a.errors[#a.errors+1]=format("items.csv line %d: %s",j+1,reason) else by_name[p.name]=p;categories[p.category]=true end
 end
 local category_names,product_names=keys(categories),keys(by_name);append(a.names,category_names);append(a.names,product_names);local index={}
 for i,name in ipairs(a.names) do index[name]=i;if i<=#category_names then a.category_ids[#a.category_ids+1]=i else a.product_ids[#a.product_ids+1]=i;a.products[i]=by_name[name] end end
 for i,p in pairs(a.products) do a.taxonomy[i]=index[p.category];a.buyers[i]=0;a.heldout[i]=0;a.hits[i]=0;a.units[i]=0;a.revenue[i]=0 end
 local transactions,ordered,previous={},{},nil
 for j,row in ipairs(baskets.records("transactions.csv")) do
  a.transaction_rows=a.transaction_rows+1;local tid,customer,day,name=row[1],row[2],tonumber(row[3]),row[4];local existing=transactions[tid]
  if previous and tid~=previous.id and existing then a.errors[#a.errors+1]=format("transactions.csv line %d: tid %s not contiguous",j+1,tid)
  else
   if not existing then existing={id=tid,customer=customer,day=day,counts={}};transactions[tid]=existing;ordered[#ordered+1]=existing;previous=existing;a.transactions=a.transactions+1 end
   local reason
   if customer~=existing.customer then reason=format("tid %s customer %s differs from %s",tid,customer,existing.customer) elseif day~=existing.day then reason=format("tid %s day %d differs from %d",tid,day,existing.day) elseif not by_name[name] then reason="unknown item "..name end
   if reason then a.errors[#a.errors+1]=format("transactions.csv line %d: %s",j+1,reason) else local i=index[name];if existing.counts[i] then a.duplicates=a.duplicates+1 end;existing.counts[i]=(existing.counts[i] or 0)+1;a.adopted=a.adopted+1 end
  end
 end
 for _,b in ipairs(ordered) do if not next(b.counts) then a.empty=a.empty+1 else a.baskets[#a.baskets+1]=b;local period=b.day<=a.p.split_day and a.train or a.test;period[#period+1]=b end end
 a.main_support=baskets.support(baskets.sets(a.baskets,a.taxonomy,false));a.extended_support=baskets.support(baskets.sets(a.baskets,a.taxonomy,true));a.train_support=baskets.support(baskets.sets(a.train,a.taxonomy,false));a.test_support=baskets.support(baskets.sets(a.test,a.taxonomy,false));return a
end
function A:apriori(support,universe,minimum,exclude)
 local result={levels={},entries={},counts={[""]=#support.sets}};local previous={}
 for size=1,self.p.max_size do
  local candidates
  if size==1 then candidates={joined=#universe,excluded=0,pruned=0,sets={}};for _,i in ipairs(universe) do candidates.sets[#candidates.sets+1]={i} end
  else if #previous==0 then break end;candidates=apriori.candidates(previous,size,self.taxonomy,exclude) end
  local frequent=apriori.count(support,candidates.sets,minimum);result.levels[#result.levels+1]={size=size,joined=candidates.joined,excluded=candidates.excluded,pruned=candidates.pruned,counted=#candidates.sets,frequent=frequent};append(result.entries,frequent);for _,e in ipairs(frequent) do result.counts[baskets.key(e.set)]=e.count end;previous=frequent
 end;return result
end
function A:make_rules(g,total,category)
 local result={generated=0,productive=0,rules={}}
 for _,e in ipairs(g.entries) do
  if #e.set>=2 and (not category or e.set[1]<=#self.category_ids) then
   local full=(1 << #e.set)-1
   for mask=1,full-1 do
    result.generated=result.generated+1;local x,y=baskets.selected(e.set,mask),baskets.selected(e.set,full ~ mask);local r=rules.metrics(e.set,x,y,e.count,total,g.counts[baskets.key(x)],g.counts[baskets.key(y)])
    if rules.thresholds(r.confidence,r.lift,self.p) then
     local best=F(0,1)
     for part=0,(1 << #x)-2 do local w=baskets.selected(x,part);local confidence=F(g.counts[baskets.key(baskets.union(w,y))],g.counts[baskets.key(w)]);if rules.compare(confidence,best)>0 then best=confidence end end
     r.improvement=rules.subtract(r.confidence,best);if r.improvement.n>0 then result.productive=result.productive+1 end;result.rules[#result.rules+1]=r
    end
   end
  end
 end
 table.sort(result.rules,rules.order);for rank,r in ipairs(result.rules) do r.rank=rank end;return result
end
function A:classify()
 self.closed,self.maximal,self.generators={},{},{}
 for _,x in ipairs(self.frequent.entries) do
  local closed,maximal,generator=true,true,true
  for _,y in ipairs(self.frequent.entries) do if #y.set>#x.set and baskets.subset(x.set,y.set) then maximal=false;if x.count==y.count then closed=false end end end
  for j=1,#x.set do local part={};for k,i in ipairs(x.set) do if k~=j then part[#part+1]=i end end;if self.frequent.counts[baskets.key(part)]<=x.count then generator=false;break end end
  if closed then self.closed[#self.closed+1]=x end;if maximal then self.maximal[#self.maximal+1]=x end;if generator then self.generators[#self.generators+1]=x end
 end
end
function A:build_customers()
 local found={};self.first,self.last=113,0
 for _,b in ipairs(self.baskets) do
  local c=found[b.customer];if not c then c={id=b.customer,baskets={},days={},purchased={},product_days={},category_units={},first=113,last=0,units=0,revenue=0};for _,i in ipairs(self.category_ids) do c.category_units[i]=0 end;found[b.customer]=c end
  c.baskets[#c.baskets+1]=b;c.days[b.day]=true;c.first=math.min(c.first,b.day);c.last=math.max(c.last,b.day);self.first=math.min(self.first,b.day);self.last=math.max(self.last,b.day)
  for i,units in pairs(b.counts) do c.purchased[i]=true;c.product_days[i]=c.product_days[i] or {};c.product_days[i][b.day]=true;c.category_units[self.taxonomy[i]]=c.category_units[self.taxonomy[i]]+units;local value=units*self.products[i].price;c.units=c.units+units;c.revenue=c.revenue+value;self.units[i]=self.units[i]+units;self.revenue[i]=self.revenue[i]+value;self.total_units=self.total_units+units;self.total_revenue=self.total_revenue+value end
 end
 self.customers={};for _,id in ipairs(keys(found)) do local c=found[id];if count_keys(c.days)>=2 then self.multi_day=self.multi_day+1 end;for i,days in pairs(c.product_days) do c.product_days[i]=keys(days);self.buyers[i]=self.buyers[i]+1 end;self.customers[#self.customers+1]=c end
end
local function median(values) table.sort(values);local n=#values;if n%2==1 then return F(values[n//2+1],1) end;return F(values[n//2]+values[n//2+1],2) end
local function minimum_gap(first,second)
 local best,j=113,1;for _,x in ipairs(first) do while j<=#second and second[j]<=x do j=j+1 end;if j<=#second then best=math.min(best,second[j]-x) end end;return best
end
function A:sequences()
 local sequences,repeats={},{}
 for _,i in ipairs(self.product_ids) do
  for _,j in ipairs(self.product_ids) do
   local gaps={};for _,c in ipairs(self.customers) do local x,y=c.product_days[i],c.product_days[j];if x and y and x[1]<y[#y] then gaps[#gaps+1]=minimum_gap(x,y) end end
   local q=#gaps;if q>0 then self.sequence_pairs=self.sequence_pairs+1 end;if q>=self.p.sequence_min_support then sequences[#sequences+1]={a=i,b=j,count=q,confidence=F(q,self.buyers[i]),lift=F(q*#self.customers,self.buyers[i]*self.buyers[j]),gap=median(gaps)} end
  end
  local r={item=i,customers=0,intervals={}};local total=0
  for _,c in ipairs(self.customers) do local days=c.product_days[i];if days and #days>=2 then r.customers=r.customers+1;for j=2,#days do local d=days[j]-days[j-1];r.intervals[#r.intervals+1]=d;total=total+d end end end
  if #r.intervals>0 then r.mean=F(total,#r.intervals);r.median=median(r.intervals);repeats[#repeats+1]=r end
 end
 table.sort(sequences,function(a,b) if a.count~=b.count then return a.count>b.count end;local c=rules.compare(a.confidence,b.confidence);if c~=0 then return c>0 end;if a.a~=b.a then return a.a<b.a end;return a.b<b.b end);self.frequent_sequences=#sequences
 for rank,s in ipairs(sequences) do self.sequence_lines[#self.sequence_lines+1]=format("SEQ %d %s -> %s customers %d base %d confidence %s lift %s gap %s",rank,self.names[s.a],self.names[s.b],s.count,self.buyers[s.a],FT(s.confidence),FT(s.lift),FT(s.gap)) end
 table.sort(repeats,function(a,b) local c=rules.compare(a.mean,b.mean);return c~=0 and c<0 or c==0 and a.item<b.item end)
 for _,r in ipairs(repeats) do self.sequence_lines[#self.sequence_lines+1]=format("REPEAT %s customers %d intervals %d min %d max %d mean %s median %s",self.names[r.item],r.customers,#r.intervals,r.intervals[1],r.intervals[#r.intervals],FT(r.mean),FT(r.median)) end
end
local function recommendations(held,candidates,top)
 local out,selected={},{};for _,i in ipairs(candidates) do if not held[i] and not selected[i] then selected[i]=true;out[#out+1]=i;if #out==top then break end end end;return out
end
local function rule_candidates(list,held) local out={};for _,r in ipairs(list) do if #r.y==1 and baskets.contains(held,r.x) then out[#out+1]=r.y[1] end end;return out end
function A:popular(support,ids)
 local out={};append(out,ids);table.sort(out,function(a,b) local x,y=support:count({a}),support:count({b});return x~=y and x>y or x==y and a<b end);return out
end
local function evaluation_text(e) return format("cases %d covered %d hit1 %d hit %d rate %s baseline %d rate %s",e.cases,e.covered,e.hit1,e.hit,FT(F(e.hit,e.cases)),e.baseline,FT(F(e.baseline,e.cases))) end
function A:validate()
 local training={}
 for _,r in ipairs(self.train_rules.rules) do
  training[baskets.key(r.x).."->"..baskets.key(r.y)]=true;local nx,ny,nz=self.test_support:count(r.x),self.test_support:count(r.y),self.test_support:count(r.set);local confidence,lift,verdict="-","-","UNSEEN"
  if nx==0 or ny==0 then self.unseen=self.unseen+1 else local c,l=F(nz,nx),rules.lift(#self.test,nz,nx,ny);confidence,lift=FT(c),FT(l);if rules.thresholds(c,l,self.p) then verdict="HOLD";self.hold=self.hold+1 else verdict="FAIL";self.fail=self.fail+1 end end
  self.validation[#self.validation+1]=format("RULE %d %s train %d confidence %s lift %s test %d of %d confidence %s lift %s %s",r.rank,report.arrow(r,self.names),r.count,FT(r.confidence),FT(r.lift),nz,nx,confidence,lift,verdict)
 end
 for _,r in ipairs(self.test_rules.rules) do if not training[baskets.key(r.x).."->"..baskets.key(r.y)] then self.emerging=self.emerging+1;self.validation[#self.validation+1]=format("EMERGING %d %s test %d confidence %s lift %s",r.rank,report.arrow(r,self.names),r.count,FT(r.confidence),FT(r.lift)) end end
 self.validation[#self.validation+1]=format("VALIDATION train %d test %d itemsets %d rules %d hold %d fail %d unseen %d emerging %d",#self.train,#self.test,#self.training.entries,#self.train_rules.rules,self.hold,self.fail,self.unseen,self.emerging)
 local popular=self:popular(self.train_support,self.product_ids)
 for _,b in ipairs(self.test) do
  local items=baskets.items(b,self.taxonomy,false);local size=#items
  if size>=2 then for _,h in ipairs(items) do
   local held={};for _,i in ipairs(items) do held[i]=i~=h end
   local rec=recommendations(held,rule_candidates(self.train_rules.rules,held),self.p.recommend_top);local baseline=recommendations(held,popular,self.p.recommend_top)
   local e={cases=1,covered=#rec>0 and 1 or 0,hit1=rec[1]==h and 1 or 0,hit=has(rec,h) and 1 or 0,baseline=has(baseline,h) and 1 or 0};self.heldout[h]=self.heldout[h]+1;self.hits[h]=self.hits[h]+e.hit
   self.evaluation[size]=self.evaluation[size] or {cases=0,covered=0,hit1=0,hit=0,baseline=0};for key,value in pairs(e) do self.evaluation[size][key]=self.evaluation[size][key]+value;self.total_evaluation[key]=self.total_evaluation[key]+value end
  end end
 end
 for _,size in ipairs(keys(self.evaluation)) do self.validation[#self.validation+1]=format("RECOMMEND size %d %s",size,evaluation_text(self.evaluation[size])) end;self.validation[#self.validation+1]="RECOMMEND total "..evaluation_text(self.total_evaluation)
end
function A:summary_lines()
 local lines={};for _,e in ipairs(self.errors) do lines[#lines+1]="ERROR "..e end
 local sizes,total,largest={},0,0;for _,b in ipairs(self.baskets) do local size=count_keys(b.counts);sizes[size]=(sizes[size] or 0)+1;total=total+size;largest=math.max(largest,size) end
 lines[#lines+1]=format("ITEMS rows %d adopted %d categories %d",self.item_rows,#self.product_ids,#self.category_ids)
 lines[#lines+1]=format("TRANSACTIONS lines %d adopted %d rejected %d duplicates %d transactions %d empty %d",self.transaction_rows,self.adopted,self.transaction_rows-self.adopted,self.duplicates,self.transactions,self.empty)
 lines[#lines+1]=format("BASKETS count %d customers %d first_day %d last_day %d average_size %s largest %d",#self.baskets,#self.customers,self.first,self.last,FT(F(total,#self.baskets)),largest)
 for size=1,largest do lines[#lines+1]=format("SIZE %d baskets %d share %s",size,sizes[size] or 0,report.percent(sizes[size] or 0,#self.baskets)) end
 lines[#lines+1]=format("FREQUENT itemsets %d closed %d maximal %d generators %d levels %d",#self.frequent.entries,#self.closed,#self.maximal,#self.generators,#self.frequent.levels)
 local same=#self.frequent.entries==#self.growth.entries;local fp={};for _,e in ipairs(self.growth.entries) do fp[baskets.key(e.set)]=e.count end;for _,e in ipairs(self.frequent.entries) do if fp[baskets.key(e.set)]~=e.count then same=false end end
 local g=self.growth;lines[#lines+1]=format("FPGROWTH header %d nodes %d conditional_trees %d conditional_nodes %d itemsets %d %s",g.header,g.nodes,g.trees,g.conditional_nodes,#g.entries,same and "MATCH" or "MISMATCH")
 if not same then for _,e in ipairs(self.frequent.entries) do if fp[baskets.key(e.set)]~=e.count then lines[#lines+1]=format("ONLY_APRIORI %s %d",report.itemset(e.set,self.names),e.count) end end;for _,e in ipairs(g.entries) do if self.frequent.counts[baskets.key(e.set)]~=e.count then lines[#lines+1]=format("ONLY_FPGROWTH %s %d",report.itemset(e.set,self.names),e.count) end end end
 lines[#lines+1]=format("RULES generated %d passed %d productive %d",self.rules.generated,#self.rules.rules,self.rules.productive)
 for _,l in ipairs(self.category.levels) do lines[#lines+1]=format("CATEGORY_LEVEL %d candidates %d taxonomy %d pruned %d counted %d frequent %d",l.size,l.joined,l.excluded,l.pruned,l.counted,#l.frequent) end
 lines[#lines+1]=format("CATEGORY_RULES itemsets %d generated %d passed %d productive %d",#self.category.entries,self.category_rules.generated,#self.category_rules.rules,self.category_rules.productive)
 lines[#lines+1]=format("SEQUENCES customers %d multi_day %d pairs %d frequent %d",#self.customers,self.multi_day,self.sequence_pairs,self.frequent_sequences);return lines
end
function A:itemset_lines()
 local lines={};for _,l in ipairs(self.frequent.levels) do lines[#lines+1]=format("LEVEL %d candidates %d pruned %d counted %d frequent %d",l.size,l.joined,l.pruned,l.counted,#l.frequent);for _,e in ipairs(l.frequent) do lines[#lines+1]=format("%s %d",report.itemset(e.set,self.names),e.count) end end;return lines
end
function A:closed_lines()
 local lines={};local labels={"CLOSED","MAXIMAL","GENERATOR"};for j,entries in ipairs({self.closed,self.maximal,self.generators}) do for _,e in ipairs(entries) do lines[#lines+1]=format("%s %s %d",labels[j],report.itemset(e.set,self.names),e.count) end end;return lines
end
function A:matrix_lines(ids,support,label)
 local lines={};for j,i in ipairs(ids) do lines[#lines+1]=format("%s %d %s baskets %d",label,j,self.names[i],support:count({i})) end
 local heading="    ";for j=1,#ids do heading=heading..format("%7d",j) end;lines[#lines+1]=heading
 for j,i in ipairs(ids) do local row=format("%4d",j);for _,k in ipairs(ids) do if i==k then row=row..format("%7s","-") else local cell=100*#support.sets*support:count(baskets.union({i},{k}))//(support:count({i})*support:count({k}));row=row..format("%7d",cell) end end;lines[#lines+1]=row end;return lines
end
function A:relationship_lines()
 local lines,adj={},{};for _,i in ipairs(self.product_ids) do adj[i]={} end
 for _,e in ipairs(self.frequent.entries) do if #e.set==2 then local i,j=e.set[1],e.set[2];local lift=rules.lift(#self.baskets,e.count,self.main_support:count({i}),self.main_support:count({j}));if rules.compare(lift,self.p.group_min_lift)>=0 then adj[i][#adj[i]+1]=j;adj[j][#adj[j]+1]=i end end end
 local groups,visited={},{}
 for _,i in ipairs(self.product_ids) do
  if #adj[i]>0 and not visited[i] then local group,queue={}, {i};local first=1;visited[i]=true
   while first<=#queue do local x=queue[first];first=first+1;group[#group+1]=x;for _,y in ipairs(adj[x]) do if not visited[y] then visited[y]=true;queue[#queue+1]=y end end end
   table.sort(group);groups[#groups+1]=group
  end
 end
 table.sort(groups,function(a,b) return #a~=#b and #a>#b or #a==#b and a[1]<b[1] end)
 for rank,group in ipairs(groups) do
  local core,edges,revenue=group[1],0,0;for _,i in ipairs(group) do edges=edges+#adj[i];revenue=revenue+self.revenue[i];if #adj[i]>#adj[core] or #adj[i]==#adj[core] and self.main_support:count({i})>self.main_support:count({core}) then core=i end end
  lines[#lines+1]=format("GROUP %d items %d edges %d core %s revenue %s share %s members %s",rank,#group,edges//2,self.names[core],report.money(revenue),report.percent(revenue,self.total_revenue),report.itemset(group,self.names))
 end
 local singles,substitutes={},{};for _,e in ipairs(self.frequent.levels[1].frequent) do singles[#singles+1]=e.set[1] end
 for j,i in ipairs(singles) do for k=j+1,#singles do local other=singles[k];local ni,nj=self.main_support:count({i}),self.main_support:count({other})
  if ni*nj>=self.p.negative_min_expected*#self.baskets then local count=self.main_support:count({i,other});local lift=rules.lift(#self.baskets,count,ni,nj);if rules.compare(lift,self.p.negative_max_lift)<=0 then substitutes[#substitutes+1]={a=i,b=other,count=count,expected=F(ni*nj,#self.baskets),lift=lift} end end
 end end
 table.sort(substitutes,function(a,b) local c=rules.compare(a.lift,b.lift);if c~=0 then return c<0 end;c=rules.compare(a.expected,b.expected);if c~=0 then return c>0 end;if a.a~=b.a then return a.a<b.a end;return a.b<b.b end)
 for _,s in ipairs(substitutes) do lines[#lines+1]=format("SUBSTITUTE %s %s count %d expected %s lift %s",self.names[s.a],self.names[s.b],s.count,FT(s.expected),FT(s.lift)) end
 local popular=self:popular(self.main_support,self.product_ids);local matrix={};for j=1,self.p.matrix_size do matrix[j]=popular[j] end
 append(lines,self:matrix_lines(matrix,self.main_support,"MATRIX"));append(lines,self:matrix_lines(self:popular(self.extended_support,self.category_ids),self.extended_support,"CATEGORY_MATRIX"));return lines
end
function A:items_report()
 local lines={};local ranked={};append(ranked,self.product_ids);table.sort(ranked,function(a,b) return self.revenue[a]~=self.revenue[b] and self.revenue[a]>self.revenue[b] or self.revenue[a]==self.revenue[b] and a<b end)
 local category_revenue,category_units,category_items={},{},{};for _,i in ipairs(self.category_ids) do category_revenue[i],category_units[i],category_items[i]=0,0,0 end
 for rank,i in ipairs(ranked) do
  local p=self.products[i];local count=self.main_support:count({i});local sets,partner,partner_count,partner_lift=0,nil,0,F(0,1)
  for _,e in ipairs(self.frequent.entries) do if has(e.set,i) then sets=sets+1;if #e.set==2 then local other=e.set[1]==i and e.set[2] or e.set[1];local lift=rules.lift(#self.baskets,e.count,count,self.main_support:count({other}));local cmp=rules.compare(lift,partner_lift)
   if not partner or cmp>0 or cmp==0 and (e.count>partner_count or e.count==partner_count and other<partner) then partner,partner_count,partner_lift=other,e.count,lift end
  end end end
  local partner_text=partner and self.names[partner].." "..FT(partner_lift) or "none";local best="none";for _,r in ipairs(self.rules.rules) do if has(r.set,i) then best=r.rank.." "..report.arrow(r,self.names);break end end
  lines[#lines+1]=format("ITEM %d %s %s price %s units %d revenue %s share %s baskets %d support %s customers %d itemsets %d heldout %d hits %d partner %s best %s",rank,p.name,p.category,report.money(p.price),self.units[i],report.money(self.revenue[i]),report.percent(self.revenue[i],self.total_revenue),count,FT(F(count,#self.baskets)),self.buyers[i],sets,self.heldout[i],self.hits[i],partner_text,best)
  local category=self.taxonomy[i];category_revenue[category]=category_revenue[category]+self.revenue[i];category_units[category]=category_units[category]+self.units[i];category_items[category]=category_items[category]+1
 end
 local categories={};append(categories,self.category_ids);table.sort(categories,function(a,b) return category_revenue[a]~=category_revenue[b] and category_revenue[a]>category_revenue[b] or category_revenue[a]==category_revenue[b] and a<b end)
 for _,i in ipairs(categories) do local count=self.extended_support:count({i});lines[#lines+1]=format("CATEGORY %s items %d units %d revenue %s share %s baskets %d support %s",self.names[i],category_items[i],category_units[i],report.money(category_revenue[i]),report.percent(category_revenue[i],self.total_revenue),count,FT(F(count,#self.baskets))) end
 lines[#lines+1]=format("TOTAL items %d units %d revenue %s baskets %d customers %d",#self.product_ids,self.total_units,report.money(self.total_revenue),#self.baskets,#self.customers);append(lines,self:relationship_lines());return lines
end
local function table_row(label,values) local row=format("%-17s",label);for _,v in ipairs(values) do row=row..format("%6d",v) end;return row end
function A:trend_lines()
 local weeks=(self.last-1)//7+1;local week_numbers,basket_counts,units,customers,customer_sets,series={},{},{},{},{},{}
 for i=1,#self.names do series[i]={};for w=1,weeks do series[i][w]=0 end end
 for w=1,weeks do week_numbers[w]=w;basket_counts[w],units[w],customers[w]=0,0,0;customer_sets[w]={} end
 for _,b in ipairs(self.baskets) do local w=(b.day-1)//7+1;basket_counts[w]=basket_counts[w]+1;customer_sets[w][b.customer]=true;for i,count in pairs(b.counts) do units[w]=units[w]+count;series[i][w]=series[i][w]+count;local category=self.taxonomy[i];series[category][w]=series[category][w]+count end end
 for w=1,weeks do customers[w]=count_keys(customer_sets[w]) end
 local lines={table_row("WEEK",week_numbers),table_row("BASKETS",basket_counts),table_row("UNITS",units),table_row("CUSTOMERS",customers)};local sw,sw2=0,0;for w=1,weeks do sw=sw+w;sw2=sw2+w*w end;local den=weeks*sw2-sw*sw;local trends={}
 for i,ys in ipairs(series) do
  lines[#lines+1]=table_row(self.names[i],ys);local total,weighted=0,0;for w,y in ipairs(ys) do total=total+y;weighted=weighted+w*y end;local slope=F(weeks*weighted-sw*total,den);local r={item=i,units=total,slope=slope,verdict="NONE"}
  if total>0 then r.relative=F(slope.n*weeks,slope.d*total);r.verdict="FLAT";if rules.compare(r.relative,self.p.trend_threshold)>=0 then r.verdict="RISING" elseif rules.compare(r.relative,F(-self.p.trend_threshold.n,self.p.trend_threshold.d))<=0 then r.verdict="FALLING" end end;trends[#trends+1]=r
 end
 table.sort(trends,function(a,b) if (a.units>0)~=(b.units>0) then return a.units>0 end;if a.units>0 then local c=rules.compare(a.relative,b.relative);if c~=0 then return c>0 end end;return a.item<b.item end)
 for _,t in ipairs(trends) do lines[#lines+1]=format("TREND %s units %d slope %s relative %s %s",self.names[t.item],t.units,FT(t.slope),t.relative and FT(t.relative) or "-",t.verdict) end;return lines
end
function A:customer_lines()
 local lines={};local segments={"NEW","LOYAL","AT_RISK","REGULAR"};local counts,revenues={0,0,0,0},{0,0,0,0}
 for _,c in ipairs(self.customers) do
  local favorite=1;for i=2,#c.category_units do if c.category_units[i]>c.category_units[favorite] then favorite=i end end
  local segment=4;if c.first>self.last-28 then segment=1 elseif #c.baskets>=4 and self.last-c.last<=14 then segment=2 elseif self.last-c.last>28 then segment=3 end;counts[segment]=counts[segment]+1;revenues[segment]=revenues[segment]+c.revenue
  local offer=recommendations(c.purchased,rule_candidates(self.rules.rules,c.purchased),self.p.recommend_top)
  lines[#lines+1]=format("CUSTOMER %s baskets %d days %d first %d last %d items %d units %d revenue %s average %s favorite %s segment %s offer %s",c.id,#c.baskets,count_keys(c.days),c.first,c.last,count_keys(c.purchased),c.units,report.money(c.revenue),report.money(c.revenue//#c.baskets),self.names[favorite],segments[segment],#offer>0 and report.itemset(offer,self.names) or "none")
 end
 for i,name in ipairs(segments) do lines[#lines+1]=format("SEGMENT %s customers %d revenue %s share %s",name,counts[i],report.money(revenues[i]),report.percent(revenues[i],self.total_revenue)) end;return lines
end
local a=A.read();local universe={};append(universe,a.category_ids);append(universe,a.product_ids)
a.frequent=a:apriori(a.main_support,a.product_ids,a.p.min_support,false);a.category=a:apriori(a.extended_support,universe,a.p.category_min_support,true)
a.training=a:apriori(a.train_support,a.product_ids,a.p.train_min_support,false);a.testing=a:apriori(a.test_support,a.product_ids,a.p.test_min_support,false)
a.growth=growth.grow(a.baskets,a.taxonomy,a.p.min_support,a.p.max_size);a:classify();a.rules=a:make_rules(a.frequent,#a.baskets,false);a.category_rules=a:make_rules(a.category,#a.baskets,true);a.train_rules=a:make_rules(a.training,#a.train,false);a.test_rules=a:make_rules(a.testing,#a.test,false)
a:build_customers();a:sequences();a:validate();assert(os.execute("mkdir -p output"))
local reports={{"summary.txt",a:summary_lines()},{"itemsets.txt",a:itemset_lines()},{"closed_maximal.txt",a:closed_lines()},{"rules.csv",report.rules_csv(a.rules.rules,a.names)},{"category_rules.csv",report.rules_csv(a.category_rules.rules,a.names)},{"sequences.txt",a.sequence_lines},{"validation.txt",a.validation},{"items_report.txt",a:items_report()},{"trends.txt",a:trend_lines()},{"customers.txt",a:customer_lines()}}
for _,r in ipairs(reports) do report.write(r[1],r[2]) end
