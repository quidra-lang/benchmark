local function yes(b) return b and 'yes' or 'no' end
local function copy(a) local r={} for i,v in ipairs(a) do r[i]=v end return r end
local function key(a) return table.concat(a,',') end
local function mark(a) local r={} for i,v in ipairs(a) do r[i]=v<0 and 'w' or tostring(v) end return '('..table.concat(r,',')..')' end
local function listed(a) return #a==0 and 'none' or table.concat(a,' ') end
local function words(s,sep) local a={} for w in s:gmatch(sep or '%S+') do a[#a+1]=w end return a end
local function number(s,lo,hi) if #s==0 or #s>10 or not s:match('^%d+$') or (#s>1 and s:sub(1,1)=='0') then return nil end local v=tonumber(s) if v>=lo and v<=hi then return v end end
local function bad(s) error(s,0) end
local function locate(a,s) for i,v in ipairs(a) do if v==s then return i end end end
local function visit(adj,start) local seen,q={}, {start};seen[start]=true;local i=1 while i<=#q do for _,v in ipairs(adj[q[i]]) do if not seen[v] then seen[v]=true;q[#q+1]=v end end i=i+1 end return seen end
local function all(seen,n) for i=1,n do if not seen[i] then return false end end return true end
local function lex(a,b) for i=1,#a do if a[i]~=b[i] then return a[i]<b[i] end end return false end
local function gcd(a,b) while b~=0 do a,b=b,a%b end return math.abs(a) end
local function flows(matrix)
  local n,m=#matrix,#matrix[1];local rows={}
  for i,r in ipairs(matrix) do rows[i]=copy(r);for j=1,n do rows[i][m+j]=i==j and 1 or 0 end end
  for j=1,m do
    local unique={};for _,r in ipairs(rows) do if r[j]==0 then unique[key(r)]=r end end
    for _,r in ipairs(rows) do if r[j]>0 then for _,s in ipairs(rows) do if s[j]<0 then local v,d={},0;for k=1,m+n do v[k]=-s[j]*r[k]+r[j]*s[k];d=gcd(d,v[k]) end for k=1,m+n do v[k]=v[k]//d end unique[key(v)]=v end end end end
    local values,supports={},{};for _,r in pairs(unique) do values[#values+1]=r;local mask=0;for i=1,n do if r[m+i]>0 then mask=mask|(1<<(i-1)) end end supports[#supports+1]=mask end
    rows={};for i,r in ipairs(values) do local minimal=true;for _,s in ipairs(supports) do if s~=supports[i] and s&supports[i]==s then minimal=false;break end end if minimal then rows[#rows+1]=r end end
  end
  local result={};for _,r in ipairs(rows) do local c={} for i=1,n do c[i]=r[m+i] end result[#result+1]=c end table.sort(result,function(a,b)return lex(b,a)end);return result
end
local Net={};Net.__index=Net
function Net.new(name)
  local n=setmetatable({name=name,p={},t={},initial={},cap={},priority={},pre={},post={},inh={},arcs=0,inhibitors=0,current={},history={}},Net)
  for _,field in ipairs({'pre','post','inh'}) do for p=1,16 do n[field][p]={} for t=1,16 do n[field][p][t]=0 end end end return n
end
function Net:define(w)
  local cmd,n=w[1],#w-1
  if cmd~='place' and cmd~='transition' and cmd~='arc' and cmd~='inhibit' then bad('unknown definition '..cmd) end
  if not (cmd=='place' and (n==2 or n==3) or cmd=='transition' and (n==1 or n==2) or (cmd=='arc' or cmd=='inhibit') and n==3) then bad('wrong number of arguments') end
  local a=w[2]
  if cmd=='place' or cmd=='transition' then
    if locate(self.p,a) or locate(self.t,a) then bad('duplicate name '..a) end
    if cmd=='place' then if n==3 and tonumber(w[3])>tonumber(w[4]) then bad('tokens exceed capacity of '..a) end self.p[#self.p+1]=a;self.initial[#self.initial+1]=tonumber(w[3]);self.cap[#self.cap+1]=n==3 and tonumber(w[4]) or 0
    else self.t[#self.t+1]=a;self.priority[#self.priority+1]=n==2 and tonumber(w[3]) or 0 end
  elseif cmd=='arc' then
    local b=w[3];for _,x in ipairs({a,b}) do if not locate(self.p,x) and not locate(self.t,x) then bad('unknown node '..x) end end
    local pa,pb=locate(self.p,a),locate(self.p,b);if (pa~=nil)==(pb~=nil) then bad('arc must connect a place and a transition') end
    local p,t,mat=pa or pb,locate(self.t,pa and b or a),pa and self.pre or self.post
    if mat[p][t]>0 then bad('duplicate arc '..a..' '..b) end mat[p][t]=tonumber(w[4]);self.arcs=self.arcs+1
  else local p,t=locate(self.p,a),locate(self.t,w[3]);if not p then bad('unknown place '..a) end if not t then bad('unknown transition '..w[3]) end if self.inh[p][t]>0 then bad('duplicate inhibitor '..a..' '..w[3]) end self.inh[p][t]=tonumber(w[4]);self.inhibitors=self.inhibitors+1 end
end
function Net:reason(m,t)
  for p,name in ipairs(self.p) do if m[p]>=0 and m[p]<self.pre[p][t] then return 'insufficient tokens in '..name end end
  for p,name in ipairs(self.p) do if self.inh[p][t]>0 and (m[p]<0 or m[p]>=self.inh[p][t]) then return 'inhibited by '..name end end
  for p,name in ipairs(self.p) do if self.cap[p]>0 and (m[p]<0 or m[p]-self.pre[p][t]+self.post[p][t]>self.cap[p]) then return 'capacity of '..name..' exceeded' end end
end
function Net:enabled(m) local a={} for t=1,#self.t do if not self:reason(m,t) then a[#a+1]=t end end return a end
function Net:fire(m,t) local a={} for p,v in ipairs(m) do a[p]=v<0 and -1 or v-self.pre[p][t]+self.post[p][t] end return a end
function Net:commit(t) self.history[#self.history+1]=self.current;self.current=self:fire(self.current,t) end
function Net:names(ts) local a={} for i,t in ipairs(ts) do a[i]=self.t[t] end return a end
function Net:graph(start,limit,target)
  local g={states={copy(start)},parent={0},via={0},edges={{}},found=0,aborted=false};local index={[key(start)]=1}
  local function matches(m) if not target then return false end for p,v in ipairs(m) do if v<target[p][1] or target[p][2]>=0 and v~=target[p][2] then return false end end return true end
  if matches(start) then g.found=1;return g end
  local q=1;while q<=#g.states do for _,t in ipairs(self:enabled(g.states[q])) do
    local m=self:fire(g.states[q],t);local k=index[key(m)]
    if not k then if #g.states==limit then g.aborted=true;return g end k=#g.states+1;index[key(m)]=k;g.states[k]=m;g.parent[k]=q;g.via[k]=t;g.edges[k]={};if matches(m) then g.found=k;return g end end
    g.edges[q][#g.edges[q]+1]={t,k}
  end q=q+1 end return g
end
function Net:path(g,k) local a={} while g.parent[k]>0 do table.insert(a,1,g.via[k]);k=g.parent[k] end return a end
function Net:reach(limit,display)
  local g=self:graph(self.current,limit);if g.aborted then print('reachability graph limit '..limit..' exceeded');return end local N=#g.states
  if display then for i,m in ipairs(g.states) do local a={} for _,e in ipairs(g.edges[i]) do a[#a+1]=self.t[e[1]]..'->M'..(e[2]-1) end print('M'..(i-1)..' '..mark(m)..': '..(#a==0 and 'dead' or table.concat(a,' '))) end return end
  local adj,closure,comp={},{},{};for i,e in ipairs(g.edges) do adj[i]={};for _,v in ipairs(e) do adj[i][#adj[i]+1]=v[2] end end for i=1,N do closure[i]=visit(adj,i) end
  local count=0;for i=1,N do if not comp[i] then count=count+1;for j=i,N do if closure[i][j] and closure[j][i] then comp[j]=count end end end end
  local terminal,home,maximum,dead={},{},{},{};for c=1,count do terminal[c]=true end for i=1,N do home[i]=true end for p=1,#self.p do maximum[p]=0 end local edgeCount,persistent=0,true
  for i,m in ipairs(g.states) do if #g.edges[i]==0 then dead[#dead+1]=i end edgeCount=edgeCount+#g.edges[i];for p,v in ipairs(m) do maximum[p]=math.max(maximum[p],v) end for j=1,N do home[j]=home[j] and closure[i][j] end for _,e in ipairs(g.edges[i]) do local t,k=e[1],e[2];if comp[i]~=comp[k] then terminal[comp[i]]=false end for _,f in ipairs(g.edges[i]) do if t~=f[1] and self:reason(g.states[k],f[1]) then persistent=false end end end end
  local terminals,homes=0,0;for c=1,count do if terminal[c] then terminals=terminals+1 end end for i=1,N do if home[i] then homes=homes+1 end end
  print('reachable markings: '..N);print('edges: '..edgeCount);print('components: '..count..' (terminal '..terminals..')');print('dead markings: '..#dead)
  for _,i in ipairs(dead) do local a=self:names(self:path(g,i));print('  M'..(i-1)..' '..mark(g.states[i])..' path '..(#a==0 and 'empty' or table.concat(a,' '))) end
  local bound=math.max(table.unpack(maximum));print('max tokens: '..mark(maximum));print('bound: '..bound);print('safe: '..yes(bound<=1));print('home markings: '..homes);print('reversible: '..yes(home[1]));print('persistent: '..yes(persistent))
  local levels={};for t,name in ipairs(self.t) do local present,used,cycle={},false,false;for i,e in ipairs(g.edges) do for _,v in ipairs(e) do if v[1]==t then used=true;present[comp[i]]=true;if comp[i]==comp[v[2]] then cycle=true end end end end local live=true;for c=1,count do if terminal[c] and not present[c] then live=false end end levels[t]=name..'='..(live and 'L4' or cycle and 'L3' or used and 'L1' or 'L0') end print('liveness: '..table.concat(levels,' '))
end
function Net:cover(limit)
  local states,parent,via,old,dead={copy(self.current)},{0},{0},{false},{false};local function rank(v)return v<0 and math.huge or v end
  local q=1;while q<=#states do if not old[q] then local es=self:enabled(states[q]);dead[q]=#es==0;local anc={};local a=q;while a>0 do table.insert(anc,1,a);a=parent[a] end
    for _,t in ipairs(es) do local m=self:fire(states[q],t);for _,a in ipairs(anc) do local ge,gt=true,false;for p,v in ipairs(m) do ge=ge and rank(v)>=rank(states[a][p]);gt=gt or rank(v)>rank(states[a][p]) end if ge and gt then for p,v in ipairs(m) do if self.cap[p]==0 and rank(v)>rank(states[a][p]) then m[p]=-1 end end end end
      if #states==limit then print('coverability tree limit '..limit..' exceeded');return end local seen=false;for _,s in ipairs(states) do if key(s)==key(m) then seen=true;break end end local k=#states+1;old[k]=seen;states[k]=m;parent[k]=q;via[k]=t;dead[k]=false
    end end q=q+1 end
  print('coverability tree nodes: '..#states);local maximum={} for p=1,#self.p do maximum[p]=0 end
  for i,m in ipairs(states) do print('  '..(i-1)..' '..mark(m)..' '..(i==1 and 'root' or '<- '..(parent[i]-1)..' '..self.t[via[i]])..(old[i] and ' old' or '')..(dead[i] and ' dead' or ''));for p,v in ipairs(m) do if rank(v)>rank(maximum[p]) then maximum[p]=v end end end
  local unbounded={} for p,v in ipairs(maximum) do if v<0 then unbounded[#unbounded+1]=self.p[p] end end print('bounds: '..mark(maximum));print('unbounded: '..listed(unbounded))
end
function Net:sets(trap)
  local found={};for mask=1,(1<<#self.p)-1 do local valid=true;for t=1,#self.t do local input,output=false,false;for p=1,#self.p do if mask&(1<<(p-1))~=0 then input=input or self.post[p][t]>0;output=output or self.pre[p][t]>0 end end if trap and output and not input or not trap and input and not output then valid=false;break end end if valid then found[#found+1]=mask end end
  local result={};for _,m in ipairs(found) do local minimal=true;for _,s in ipairs(found) do if s~=m and s&m==s then minimal=false;break end end if minimal then result[#result+1]=m end end
  local function bits(m)local a={} for p=1,#self.p do if m&(1<<(p-1))~=0 then a[#a+1]=p end end return a end
  table.sort(result,function(a,b)local x,y=bits(a),bits(b);if #x~=#y then return #x<#y end return lex(x,y) end);return result
end
function Net:setText(mask) local a={} for p,name in ipairs(self.p) do if mask&(1<<(p-1))~=0 then a[#a+1]=name end end return '{'..table.concat(a,',')..'}' end
function Net:realize(counts)
  local used,stack,choices,path,seen={},{self.current},{1},{},{};local total=0;for t,v in ipairs(counts) do used[t]=0;total=total+v end
  while #stack>0 do local d=#path+1;if #path==total then return path end local chosen
    for t=choices[d],#counts do choices[d]=t+1;if used[t]<counts[t] and not self:reason(stack[d],t) then used[t]=used[t]+1;local k=key(used);used[t]=used[t]-1;if not seen[k] then seen[k]=true;chosen=t;break end end end
    if chosen then used[chosen]=used[chosen]+1;path[#path+1]=chosen;stack[#stack+1]=self:fire(stack[d],chosen);choices[#choices+1]=1
    else table.remove(stack);table.remove(choices);if #path>0 then local t=table.remove(path);used[t]=used[t]-1 end end
  end
end
function Net:invariants(transpose)
  local a={};if transpose then for t=1,#self.t do a[t]={} for p=1,#self.p do a[t][p]=self.post[p][t]-self.pre[p][t] end end else for p=1,#self.p do a[p]={} for t=1,#self.t do a[p][t]=self.post[p][t]-self.pre[p][t] end end end
  local f,ns=flows(a),transpose and self.t or self.p;local covered,bounds={},{};print((transpose and 'T' or 'P')..'-semiflows: '..#f)
  for _,c in ipairs(f) do local terms,value={},0;for i,v in ipairs(c) do if v>0 then terms[#terms+1]=(v==1 and '' or v..'*')..ns[i];covered[i]=true;if not transpose then value=value+v*self.current[i] end end end local text=table.concat(terms,' + ')
    if transpose then local path=self:realize(c);print('  '..text..': '..(path and 'realizable '..table.concat(self:names(path),' ') or 'not realizable'))
    else print('  '..text..' = '..value);for p,v in ipairs(c) do if v>0 then local b=value//v;bounds[p]=bounds[p] and math.min(bounds[p],b) or b end end end
  end
  if not transpose then local b={} for p=1,#ns do b[p]=bounds[p] and tostring(bounds[p]) or '-' end print('bounds: ('..table.concat(b,',')..')') end print((transpose and 'consistent: ' or 'conservative: ')..yes(all(covered,#ns)))
end
function Net:classify()
  local ordinary,pure,sm,mg,fc,efc=true,true,true,true,true,true;local inputs,outputs={},{};for t=1,#self.t do inputs[t]={} end for p=1,#self.p do outputs[p]={};for t=1,#self.t do ordinary=ordinary and self.pre[p][t]<=1 and self.post[p][t]<=1;pure=pure and not(self.pre[p][t]>0 and self.post[p][t]>0);if self.pre[p][t]>0 then inputs[t][#inputs[t]+1]=p;outputs[p][#outputs[p]+1]=t end end end
  for t=1,#self.t do local count=0;for p=1,#self.p do if self.post[p][t]>0 then count=count+1 end end sm=sm and #inputs[t]==1 and count==1 end
  for p,a in ipairs(outputs) do local count=0;for t=1,#self.t do if self.post[p][t]>0 then count=count+1 end end mg=mg and #a==1 and count==1;for _,t in ipairs(a) do if #a~=1 and #inputs[t]~=1 then fc=false end end for q,b in ipairs(outputs) do for _,t in ipairs(a) do if self.pre[q][t]>0 and key(a)~=key(b) then efc=false end end end end
  sm=sm and ordinary;mg=mg and ordinary;fc=fc and ordinary;efc=efc and ordinary
  for _,v in ipairs({{'ordinary',ordinary},{'pure',pure},{'state machine',sm},{'marked graph',mg},{'free choice',fc},{'extended free choice',efc}}) do print(v[1]..': '..yes(v[2])) end
  local verdict=not fc and 'not applicable' or #self.p>12 and 'too many places' or 'holds'
  if fc and #self.p<=12 then local traps=self:sets(true);for _,s in ipairs(self:sets(false)) do local holds=false;for _,q in ipairs(traps) do if s&q==q then for p,v in ipairs(self.current) do if v>0 and q&(1<<(p-1))~=0 then holds=true end end end end if not holds then verdict='fails at '..self:setText(s);break end end end print('commoner: '..verdict)
end
function Net:workflow(limit)
  local sources,sinks={},{};for p=1,#self.p do local input,output=false,false;for t=1,#self.t do input=input or self.post[p][t]>0;output=output or self.pre[p][t]>0 end if not input then sources[#sources+1]=p end if not output then sinks[#sinks+1]=p end end
  if #sources~=1 then print('workflow: no ('..#sources..' source places)');return end if #sinks~=1 then print('workflow: no ('..#sinks..' sink places)');return end
  local i,o,P=sources[1],sinks[1],#self.p;local ns,adj,rev=copy(self.p),{},{};for _,name in ipairs(self.t) do ns[#ns+1]=name end for v=1,#ns do adj[v]={};rev[v]={} end
  for p=1,P do for t=1,#self.t do if self.pre[p][t]>0 then adj[p][#adj[p]+1]=P+t;rev[P+t][#rev[P+t]+1]=p end if self.post[p][t]>0 then adj[P+t][#adj[P+t]+1]=p;rev[p][#rev[p]+1]=P+t end end end
  local f,b=visit(adj,i),visit(rev,o);for v,name in ipairs(ns) do if not f[v] or not b[v] then print('workflow: no ('..name..' is not on a path from '..self.p[i]..' to '..self.p[o]..')');return end end print('workflow: source '..self.p[i]..' sink '..self.p[o])
  local start,goal={},{};for p=1,P do start[p]=p==i and 1 or 0;goal[p]=p==o and 1 or 0 end local g=self:graph(start,limit);if g.aborted then print('reachability graph limit '..limit..' exceeded');return end
  local finish,used,proper=nil,{},true;rev={};for u=1,#g.states do rev[u]={} end for u,m in ipairs(g.states) do if key(m)==key(goal) then finish=u end if m[o]>=1 and key(m)~=key(goal) then proper=false end for _,e in ipairs(g.edges[u]) do rev[e[2]][#rev[e[2]]+1]=u;used[e[1]]=true end end
  local option=finish~=nil and all(visit(rev,finish),#g.states);local live=all(used,#self.t);print('option to complete: '..yes(option));print('proper completion: '..yes(proper));print('no dead transitions: '..yes(live));print('sound: '..yes(option and proper and live))
end
local arity={MARKING=0,RESET=0,SET=2,ENABLED=0,FIRE=-1,UNDO=1,SIMULATE=3,CONFLICTS=0,REACH=1,GRAPH=1,COVER=1,PATH=2,INCIDENCE=0,PINV=0,TINV=0,SIPHONS=0,TRAPS=0,CLASSIFY=0,WORKFLOW=1,SHOW=0}
function Net:execute(w)
  local cmd=w[1];if arity[cmd]==nil then bad('unknown command '..cmd) end if arity[cmd]<0 and #w<2 or arity[cmd]>=0 and #w~=arity[cmd]+1 then bad('wrong number of arguments') end
  local limit;if cmd=='REACH' or cmd=='GRAPH' or cmd=='COVER' or cmd=='PATH' or cmd=='WORKFLOW' then limit=number(w[2],1,2000);if not limit then bad('invalid limit '..w[2]) end end
  if cmd=='MARKING' or cmd=='RESET' then if cmd=='RESET' then self.current=copy(self.initial);self.history={} end print('marking '..mark(self.current))
  elseif cmd=='SET' then local p=locate(self.p,w[2]);if not p then bad('unknown place '..w[2]) end local v=number(w[3],0,999);if not v then bad('invalid tokens '..w[3]) end if self.cap[p]>0 and v>self.cap[p] then bad('tokens exceed capacity of '..w[2]) end self.current=copy(self.current);self.current[p]=v;self.history={};print('marking '..mark(self.current))
  elseif cmd=='ENABLED' then print('enabled: '..listed(self:names(self:enabled(self.current))))
  elseif cmd=='FIRE' then local ts={} for i=2,#w do local t=locate(self.t,w[i]);if not t then bad('unknown transition '..w[i]) end ts[#ts+1]=t end for i,t in ipairs(ts) do local reason=self:reason(self.current,t);if reason then print('step '..i..': '..self.t[t]..' not enabled ('..reason..') at '..mark(self.current));return end self:commit(t) end print('fired '..#ts..' -> '..mark(self.current))
  elseif cmd=='UNDO' then local k=number(w[2],1,1000);if not k then bad('invalid count '..w[2]) end local h=#self.history;if k>h then bad('cannot undo '..k..': history size '..h) end self.current=self.history[h-k+1];for _=1,k do table.remove(self.history) end print('marking '..mark(self.current))
  elseif cmd=='SIMULATE' then local steps,x=number(w[2],1,1000),number(w[3],1,2147483646);if not steps then bad('invalid steps '..w[2]) end if not x then bad('invalid seed '..w[3]) end if w[4]~='PRIORITY' and w[4]~='RANDOM' then bad('invalid mode '..w[4]) end local counts={} for t=1,#self.t do counts[t]=0 end local done=0
    while done<steps do local e=self:enabled(self.current);if #e==0 then print('dead (steps='..done..')');break end local t=e[1];if w[4]=='RANDOM' then x=x*48271%2147483647;t=e[x%#e+1] else for _,u in ipairs(e) do if self.priority[u]>self.priority[t] then t=u end end end self:commit(t);counts[t]=counts[t]+1;done=done+1;print('step '..done..': '..self.t[t]..' -> '..mark(self.current)) end if done==steps then print('completed (steps='..steps..')') end local a={} for t,name in ipairs(self.t) do a[t]=name..'='..counts[t] end print('counts: '..table.concat(a,' '))
  elseif cmd=='CONFLICTS' then local s,e={},{};for u=1,#self.t do for v=u+1,#self.t do local pair=self.t[u]..'/'..self.t[v];local conflict=false;for p=1,#self.p do if self.pre[p][u]>0 and self.pre[p][v]>0 then conflict=true end end if conflict then s[#s+1]=pair end if not self:reason(self.current,u) and not self:reason(self.current,v) and (self:reason(self:fire(self.current,u),v) or self:reason(self:fire(self.current,v),u)) then e[#e+1]=pair end end end print('structural: '..listed(s));print('effective: '..listed(e))
  elseif cmd=='REACH' or cmd=='GRAPH' then self:reach(limit,cmd=='GRAPH') elseif cmd=='COVER' then self:cover(limit)
  elseif cmd=='PATH' then local entries=words(w[3],'[^,]+');if #entries~=#self.p then bad('target needs '..#self.p..' entries') end local target={} for _,s in ipairs(entries) do if s=='*' then target[#target+1]={0,-1} else local plus=s:sub(-1)=='+';local v=number(plus and s:sub(1,-2) or s,0,9999999999);if not v then bad('invalid target entry '..s) end target[#target+1]={v,plus and -1 or v} end end local g=self:graph(self.current,limit,target);if g.found>0 then local a=self:names(self:path(g,g.found));print('reached '..mark(g.states[g.found])..' length='..#a..(#a>0 and ': '..table.concat(a,' ') or '')) elseif g.aborted then print('search limit '..limit..' exceeded') else print('unreachable (markings explored: '..#g.states..')') end
  elseif cmd=='INCIDENCE' then local rows={{''}};for _,name in ipairs(self.t) do rows[1][#rows[1]+1]=name end for p,name in ipairs(self.p) do local r={name};for t=1,#self.t do r[#r+1]=tostring(self.post[p][t]-self.pre[p][t]) end rows[#rows+1]=r end local width={} for _,r in ipairs(rows) do for i,s in ipairs(r) do width[i]=math.max(width[i] or 0,#s) end end for _,r in ipairs(rows) do local a={} for i,s in ipairs(r) do local pad=string.rep(' ',width[i]-#s);a[i]=i==1 and s..pad or pad..s end print((table.concat(a,'  '):gsub(' +$',''))) end
  elseif cmd=='PINV' or cmd=='TINV' then self:invariants(cmd=='TINV') elseif cmd=='SIPHONS' or cmd=='TRAPS' then if #self.p>12 then bad('more than 12 places') end local ss=self:sets(cmd=='TRAPS');print('minimal '..(cmd=='TRAPS' and 'traps' or 'siphons')..': '..#ss);for _,s in ipairs(ss) do local tokens=0;for p,v in ipairs(self.current) do if s&(1<<(p-1))~=0 then tokens=tokens+v end end print('  '..self:setText(s)..' tokens='..tokens) end
  elseif cmd=='CLASSIFY' then self:classify() elseif cmd=='WORKFLOW' then self:workflow(limit)
  elseif cmd=='SHOW' then for p,name in ipairs(self.p) do print('place '..name..' tokens='..self.initial[p]..' capacity='..(self.cap[p]>0 and self.cap[p] or 'none')) end for t,name in ipairs(self.t) do local lists={} for _,mat in ipairs({self.pre,self.post,self.inh}) do local a={} for p,pn in ipairs(self.p) do if mat[p][t]>0 then a[#a+1]=pn..':'..mat[p][t] end end lists[#lists+1]=#a>0 and table.concat(a,',') or '-' end print('transition '..name..' priority='..self.priority[t]..' pre='..lists[1]..' post='..lists[2]..' inhibit='..lists[3]) end end
end
local blocks=tonumber(io.read())
for _=1,blocks do local net=Net.new(words(io.read())[2]);while true do local line=io.read();if line=='END NET' then break end local ok,err=pcall(function()net:define(words(line))end);if not ok then print('error: '..err) end end net.current=copy(net.initial);print('net '..net.name..': places='..#net.p..' transitions='..#net.t..' arcs='..net.arcs..' inhibitors='..net.inhibitors);local n=tonumber(io.read());for _=1,n do local line=io.read();local ok,err=pcall(function()net:execute(words(line))end);if not ok then print('error: '..err) end end end
