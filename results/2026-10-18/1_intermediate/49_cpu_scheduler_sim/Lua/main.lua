local ALGOS={'FCFS','SJF','SRTF','RR','PRIORITY','HRRN','EDF','LOTTERY','MLFQ'}
local KEYS={'cs','q','k','s','seed'}
local RANGES={cs={0,5},q={1,20},k={1,50},s={0,500},seed={1,2147483646}}
local DEFAULTS={cs=0,q=4,k=5,s=0,seed=1}
local METRICS={'turnaround','waiting','response'}
local EVENT_KINDS={'PREEMPT','EXPIRE','DEMOTE','BOOST','AGE'}
local SYMBOLS={FUTURE='-',DONE='-',RUN='#',SWITCH='s',READY='.',IO='i'}
local function emit(...)
    local a={...}
    for i,v in ipairs(a) do
        a[i]=tostring(v)
    end
    io.write(table.concat(a,' '),'\n')
end
local function check(bad,message)
    if bad then
        error(message,0)
    end
end
local function contains(a,x)
    for _,v in ipairs(a) do
        if v==x then
            return true
        end
    end
    return false
end
local function allowed(a)
    local k={'cs'}
    for _,v in ipairs(({RR={'q'},LOTTERY={'q','seed'},PRIORITY={'k'},MLFQ={'s'}})[a] or {}) do
        k[#k+1]=v
    end
    return k
end
local function notation(p,a)
    local words={}
    for _,k in ipairs(a and allowed(a) or KEYS) do
        words[#words+1]=k..'='..p[k]
    end
    return table.concat(words,' ')
end
local function truncated(u,v)
    local n=u*100//v
    return string.format('%d.%02d',n//100,n%100)
end
local function parse_params(words,a,preset)
    local p,seen={},{}
    for k,v in pairs(DEFAULTS) do
        p[k]=v
    end
    for _,k in ipairs(preset or {}) do
        seen[k]=true
    end
    for _,word in ipairs(words) do
        local k,text=word:match('^(%a+)=(%d+)$')
        local v=tonumber(text)
        check(not RANGES[k],'unknown key '..k)
        check(a and not contains(allowed(a),k),'key '..k..' not allowed for '..(a or ''))
        check(seen[k],'duplicate key '..k)
        check(v<RANGES[k][1] or v>RANGES[k][2],'invalid '..k)
        seen[k]=true
        p[k]=v
    end
    return p
end
local function describe(d)
    local bs={}
    for i,n in ipairs(d.bursts) do
        bs[#bs+1]=(i%2==1 and 'C' or 'I')..n
    end
    return d.id..' arrival='..d.arrival..' priority='..d.priority..' deadline='..(d.deadline or 'none')..' bursts='..table.concat(bs,',')
end
local function deadline(j)
    return j.process.deadline and j.process.arrival+j.process.deadline or nil
end
local function metrics(j)
    local t,total=j.finish-j.process.arrival,0
    for _,n in ipairs(j.process.bursts) do
        total=total+n
    end
    return {t,t-total,j.start-j.process.arrival}
end
local function slices(j)
    local n=0
    for _,r in ipairs(j.records) do
        n=n+r.slices
    end
    return n
end
local function missed(j)
    return deadline(j) and j.finish>deadline(j)
end
local Sim={}
Sim.__index=Sim
function Sim:event(kind,...)
    local words={self.time,kind,...}
    for i,v in ipairs(words) do
        words[i]=tostring(v)
    end
    self.events[#self.events+1]=table.concat(words,' ')
    self.counts[kind]=(self.counts[kind] or 0)+1
end
function Sim:enqueue(j)
    j.state='READY'
    j.enqueued=self.time
    local q=self.queues[j.level+1]
    q[#q+1]=j
end
function Sim:advance(j)
    j.burst=j.burst+1
    j.left=j.process.bursts[j.burst]
end
function Sim:release()
    self.cpu='IDLE'
    self.current=nil
end
function Sim:start(j)
    self.cpu='RUN'
    self.current=j
    self.run=0
    j.state='RUN'
    j.start=j.start or self.time
    local r=j.records[#j.records]
    r.start=r.start or self.time
end
function Sim:preempts(j)
    if self.a=='MLFQ' then
        for i=1,j.level do
            if #self.queues[i]>0 then
                return true
            end
        end
    end
    for _,x in ipairs(self.queues[1]) do
        if self.a=='SRTF' and x.left<j.left then
            return true
        end
        if self.a=='PRIORITY' and x.effective<j.effective then
            return true
        end
        if self.a=='EDF' and deadline(x) and (not deadline(j) or deadline(x)<deadline(j)) then
            return true
        end
    end
    return false
end
function Sim:choose(q)
    if self.a=='LOTTERY' then
        self.random=48271*self.random%2147483647
        local total=0
        for _,j in ipairs(q) do
            total=total+10-j.process.priority
        end
        local target=self.random%total
        for _,j in ipairs(q) do
            target=target-10+j.process.priority
            if target<0 then
                return j
            end
        end
    end
    local best=q[1]
    for i=2,#q do
        local j=q[i]
        local better=false
        if self.a=='SJF' or self.a=='SRTF' then
            better=j.left<best.left
        elseif self.a=='PRIORITY' then
            better=j.effective<best.effective
        elseif self.a=='EDF' then
            better=deadline(j) and (not deadline(best) or deadline(j)<deadline(best))
        elseif self.a=='HRRN' then
            better=(self.time-j.enqueued+j.left)*best.left>(self.time-best.enqueued+best.left)*j.left
        end
        if better then
            best=j
        end
    end
    return best
end
function Sim:capture()
    self.snapshot={self.cpu=='IDLE' and 'CPU IDLE' or 'CPU '..self.cpu..' '..self.current.id}
    for i=1,(self.a=='MLFQ' and 3 or 1) do
        local ids={}
        for _,j in ipairs(self.queues[i]) do
            ids[#ids+1]=j.id
        end
        self.snapshot[#self.snapshot+1]='QUEUE'..(self.a=='MLFQ' and i-1 or '')..' '..(#ids==0 and 'none' or table.concat(ids,' '))
    end
    for _,j in ipairs(self.jobs) do
        local text
        if j.state=='FUTURE' then
            text=j.id..' FUTURE at='..j.process.arrival
        elseif j.state=='DONE' then
            text=j.id..' DONE at='..j.finish
        else
            text=j.id..' '..j.state..' burst='..j.burst..' left='..j.left
            if self.a=='PRIORITY' then
                text=text..' prio='..j.effective
            elseif self.a=='MLFQ' then
                text=text..' level='..j.level..' used='..j.used
            end
        end
        self.snapshot[#self.snapshot+1]=text
    end
end
function Sim:simulate()
    while true do
        if self.a=='PRIORITY' then
            for _,j in ipairs(self.queues[1]) do
                j.wait=j.wait+1
                if j.wait==self.p.k then
                    j.wait=0
                    if j.effective>0 then
                        j.effective=j.effective-1
                        self:event('AGE',j.id,j.effective)
                    end
                end
            end
        end
        for _,j in ipairs(self.jobs) do
            if j.state=='IO' and j.left==0 then
                self:advance(j)
                j.records[#j.records+1]={length=j.left,ready=self.time,slices=0}
                self:enqueue(j)
                self:event('IODONE',j.id)
            end
        end
        for _,j in ipairs(self.jobs) do
            if j.state=='FUTURE' and j.process.arrival==self.time then
                j.records[#j.records+1]={length=j.left,ready=self.time,slices=0}
                self:enqueue(j)
                self:event('ARRIVE',j.id)
            end
        end
        local j=self.current
        if self.cpu=='SWITCH' and self.switch_left==0 then
            self:start(j)
            self:event('START',j.id)
        elseif self.cpu=='RUN' then
            if j.left==0 and j.burst==#j.process.bursts then
                j.state='DONE'
                j.finish=self.time
                self:event('DONE',j.id)
                self:release()
            else
                local demoted=self.a=='MLFQ' and j.level<2 and j.used==({4,8})[j.level+1]
                if demoted then
                    j.level=j.level+1
                    j.used=0
                    self:event('DEMOTE',j.id,j.level)
                end
                if j.left==0 then
                    self:advance(j)
                    j.state='IO'
                    self:event('IO',j.id,j.left)
                    self:release()
                elseif demoted then
                    self:enqueue(j)
                    self:release()
                elseif (self.a=='RR' or self.a=='LOTTERY') and self.run==self.p.q then
                    self:enqueue(j)
                    self:event('EXPIRE',j.id)
                    self:release()
                elseif self:preempts(j) then
                    self:enqueue(j)
                    self:event('PREEMPT',j.id)
                    self:release()
                end
            end
        end
        local done=true
        for _,x in ipairs(self.jobs) do
            if x.state~='DONE' then
                done=false
                break
            end
        end
        if done then
            break
        end
        if self.a=='MLFQ' and self.p.s>0 and self.time>0 and self.time%self.p.s==0 then
            local merged={}
            for _,q in ipairs(self.queues) do
                for _,x in ipairs(q) do
                    merged[#merged+1]=x
                end
            end
            self.queues={merged,{},{}}
            for _,x in ipairs(self.jobs) do
                x.level=0
                x.used=0
            end
            self:event('BOOST')
        end
        if self.cpu=='IDLE' then
            for _,q in ipairs(self.queues) do
                if #q>0 then
                    j=self:choose(q)
                    for i,x in ipairs(q) do
                        if x==j then
                            table.remove(q,i)
                            break
                        end
                    end
                    j.effective=j.process.priority
                    j.wait=0
                    j.records[#j.records].slices=j.records[#j.records].slices+1
                    local switched=j~=self.previous
                    if switched then
                        self.switches=self.switches+1
                    end
                    if switched and self.p.cs>0 then
                        self.cpu='SWITCH'
                        self.current=j
                        self.switch_left=self.p.cs
                        j.state='SWITCH'
                        self:event('SWITCH',j.id)
                    else
                        self:start(j)
                        self:event('DISPATCH',j.id)
                    end
                    break
                end
            end
        end
        if self.time==self.snapshot_time then
            self:capture()
        end
        for _,x in ipairs(self.jobs) do
            x.timeline[#x.timeline+1]=SYMBOLS[x.state]
        end
        local length=0
        for _,q in ipairs(self.queues) do
            length=length+#q
        end
        self.lengths[#self.lengths+1]=length
        self.states[#self.states+1]=self.cpu
        if self.cpu=='RUN' then
            j=self.current
            j.left=j.left-1
            j.used=j.used+1
            self.run=self.run+1
            self.previous=j
            self.labels[#self.labels+1]=j.id
            if j.left==0 then
                j.records[#j.records].finish=self.time+1
            end
        elseif self.cpu=='SWITCH' then
            self.switch_left=self.switch_left-1
            self.labels[#self.labels+1]='CS'
        else
            self.labels[#self.labels+1]='IDLE'
        end
        for _,x in ipairs(self.jobs) do
            if x.state=='IO' then
                x.left=x.left-1
            end
        end
        self.time=self.time+1
    end
    if not self.snapshot then
        self:capture()
    end
end
function Sim:totals()
    local v={0,0,0}
    for _,j in ipairs(self.jobs) do
        for i,n in ipairs(metrics(j)) do
            v[i]=v[i]+n
        end
    end
    return v
end
function Sim:averages()
    local v=self:totals()
    for i,n in ipairs(v) do
        v[i]=truncated(n,#self.jobs)
    end
    return v
end
function Sim:ticks(a,b)
    local v={0,0,0}
    for t=a+1,b do
        local s=self.states[t]
        local i=s=='RUN' and 1 or s=='SWITCH' and 2 or 3
        v[i]=v[i]+1
    end
    return table.unpack(v)
end
function Sim:utilization()
    local b=self:ticks(0,self.time)
    return truncated(b*100,self.time)
end
function Sim:missed()
    local n=0
    for _,j in ipairs(self.jobs) do
        if missed(j) then
            n=n+1
        end
    end
    return n
end
function Sim:met()
    local n=0
    for _,j in ipairs(self.jobs) do
        if deadline(j) and not missed(j) then
            n=n+1
        end
    end
    return n
end
function Sim:segments()
    local result,start={},0
    for t=1,self.time do
        if t==self.time or self.labels[t+1]~=self.labels[start+1] then
            result[#result+1]='['..start..'-'..t..' '..self.labels[start+1]..']'
            start=t
        end
    end
    return result
end
local registry={}
local function sorted_processes()
    local ps={}
    for _,p in pairs(registry) do
        ps[#ps+1]=p
    end
    table.sort(ps,function(x,y)
        return x.id<y.id
    end)
    return ps
end
local function sim(a,p,t)
    local s=setmetatable({a=a,p=p,snapshot_time=t,jobs={},queues={{},{},{}},cpu='IDLE',switch_left=0,run=0,switches=0,random=p.seed,events={},counts={},labels={},states={},lengths={},time=0},Sim)
    for _,d in ipairs(sorted_processes()) do
        s.jobs[#s.jobs+1]={process=d,id=d.id,state='FUTURE',burst=1,left=d.bursts[1],effective=d.priority,wait=0,level=0,used=0,enqueued=0,records={},timeline={}}
    end
    s:simulate()
    return s
end
local function require_algorithm(a)
    check(not contains(ALGOS,a),'unknown algorithm '..a)
end
local function process(id)
    check(not registry[id],'unknown process '..id)
    return registry[id]
end
local function size()
    local n=0
    for _ in pairs(registry) do
        n=n+1
    end
    return n
end
local function prepare(words,a,preset)
    local p=parse_params(words,a,preset)
    check(size()==0,'no processes')
    return p
end
local function metric_parts(v)
    local a={}
    for i,m in ipairs(METRICS) do
        a[i]=m..'='..v[i]
    end
    return table.concat(a,' ')
end
local function table_row(cells)
    local a={string.format('%-8s',cells[1])}
    for i=2,#cells do
        a[#a+1]=string.format('%8s',tostring(cells[i]))
    end
    return table.concat(a,' ')
end
local function execute(c,a)
    if c=='PROC' then
        local id,at,pr=a[1],tonumber(a[2]),tonumber(a[3])
        check(registry[id]~=nil,'duplicate process '..id)
        check(size()>=10,'too many processes')
        check(at>200,'invalid arrival '..id)
        check(pr>9,'invalid priority '..id)
        local valid=(#a-3)%2==1
        local bs,cpu,io={},0,0
        for i=4,#a do
            local n=tonumber(a[i]:sub(2))
            local odd=(i-4)%2==0
            valid=valid and a[i]:sub(1,1)==(odd and 'C' or 'I') and n>=1 and n<=30
            bs[#bs+1]=n
            if odd then
                cpu=cpu+n
            else
                io=io+n
            end
        end
        check(not valid,'invalid bursts '..id)
        registry[id]={id=id,arrival=at,priority=pr,bursts=bs}
        emit(c,id,'cpu='..cpu,'io='..io)
        return
    elseif c=='GEN' then
        local prefix,count,x=a[1],tonumber(a[2]),tonumber(a[3])
        for i=1,count do
            check(registry[prefix..i]~=nil,'duplicate process '..prefix..i)
        end
        check(size()+count>10,'too many processes')
        emit(c,'count='..count)
        local function draw(m)
            x=48271*x%2147483647
            return x%m
        end
        for i=1,count do
            local id=prefix..i
            local at=draw(21)
            local pr=draw(10)
            local m=1+draw(3)
            local bs={}
            for j=1,m do
                if j>1 then
                    bs[#bs+1]=1+draw(8)
                end
                bs[#bs+1]=1+draw(9)
            end
            local d={id=id,arrival=at,priority=pr,bursts=bs}
            registry[id]=d
            emit(describe(d))
        end
        return
    elseif c=='SETPRIO' or c=='DEADLINE' then
        local d,n=process(a[1]),tonumber(a[2])
        check(n>(c=='SETPRIO' and 9 or 1000),'invalid '..(c=='SETPRIO' and 'priority' or 'deadline')..' '..d.id)
        if c=='SETPRIO' then
            d.priority=n
            emit(c,d.id,'priority='..n)
        else
            d.deadline=n>0 and n or nil
            emit(c,d.id,d.deadline or 'none')
        end
        return
    elseif c=='DROP' then
        process(a[1])
        registry[a[1]]=nil
        emit(c,a[1])
        return
    elseif c=='CLEAR' then
        emit(c,'count='..size())
        registry={}
        return
    elseif c=='LIST' then
        emit(c,'count='..size())
        for _,d in ipairs(sorted_processes()) do
            emit(describe(d))
        end
        return
    end
    if c=='COMPARE' or c=='DIFF' or c=='RANK' then
        local first,second,metric,header
        if c=='DIFF' then
            first=table.remove(a,1)
            second=table.remove(a,1)
            require_algorithm(first)
            require_algorithm(second)
            header=first..' '..second
        elseif c=='RANK' then
            metric=table.remove(a,1)
            check(not contains({'turnaround','waiting','response','end','switches','missed'},metric),'unknown metric '..metric)
            header=metric
        end
        local p=prepare(a)
        if header then
            emit(c,header,notation(p))
        else
            emit(c,notation(p))
        end
        local algos=c=='DIFF' and {first,second} or ALGOS
        local sims={}
        for _,algo in ipairs(algos) do
            sims[#sims+1]=sim(algo,p)
        end
        if c=='COMPARE' then
            emit(table_row({'ALGO','TURN','WAIT','RESP','UTIL','END','SWITCH','MISS'}))
            for i,s in ipairs(sims) do
                local av=s:averages()
                emit(table_row({algos[i],av[1],av[2],av[3],s:utilization(),s.time,s.switches,s:missed()}))
            end
            local best={}
            for i,m in ipairs(METRICS) do
                local b=1
                for j,s in ipairs(sims) do
                    if s:totals()[i]<sims[b]:totals()[i] then
                        b=j
                    end
                end
                best[#best+1]=m..'='..algos[b]
            end
            emit('BEST',table.concat(best,' '))
        elseif c=='DIFF' then
            local wins={0,0,0}
            for i,j in ipairs(sims[1].jobs) do
                local x,y=metrics(j),metrics(sims[2].jobs[i])
                local parts={}
                for k,m in ipairs(METRICS) do
                    parts[k]=m..'='..x[k]..'/'..y[k]
                end
                emit(j.id,table.concat(parts,' '))
                local k=x[1]<y[1] and 1 or x[1]>y[1] and 2 or 3
                wins[k]=wins[k]+1
            end
            emit('WINS',first..'='..wins[1],second..'='..wins[2],'ties='..wins[3])
        else
            local idx=nil
            for i,m in ipairs(METRICS) do
                if m==metric then
                    idx=i
                end
            end
            local entries={}
            for i,s in ipairs(sims) do
                local v=idx and s:totals()[idx] or metric=='end' and s.time or metric=='switches' and s.switches or s:missed()
                entries[#entries+1]={value=v,index=i}
            end
            table.sort(entries,function(x,y)
                if x.value~=y.value then
                    return x.value<y.value
                end
                return x.index<y.index
            end)
            for _,e in ipairs(entries) do
                local rank=1
                for _,o in ipairs(entries) do
                    if o.value<e.value then
                        rank=rank+1
                    end
                end
                emit(rank,algos[e.index],idx and truncated(e.value,size()) or e.value)
            end
        end
        return
    end
    local algo=table.remove(a,1)
    require_algorithm(algo)
    local extra,key,lo,hi
    local preset={}
    if c=='WINDOW' then
        extra=tonumber(table.remove(a,1))
        check(extra<1 or extra>1000,'invalid window')
    elseif c=='SNAPSHOT' then
        extra=tonumber(table.remove(a,1))
    elseif c=='SWEEP' then
        key=table.remove(a,1)
        lo=tonumber(table.remove(a,1))
        hi=tonumber(table.remove(a,1))
        check(not RANGES[key],'unknown key '..key)
        check(not contains(allowed(algo),key),'key '..key..' not allowed for '..algo)
        local r=RANGES[key]
        check(lo>hi or lo<r[1] or hi>r[2] or hi-lo>20,'invalid range')
        preset={key}
    end
    local p=prepare(a,algo,preset)
    if c=='SWEEP' then
        emit(c,algo,key,lo,hi)
        local best,best_value=nil,lo
        for v=lo,hi do
            p[key]=v
            local s=sim(algo,p)
            emit(notation(p,algo),metric_parts(s:averages()),'util='..s:utilization(),'end='..s.time,'switches='..s.switches)
            local total=s:totals()[2]
            if not best or total<best then
                best,best_value=total,v
            end
        end
        emit('BEST',key..'='..best_value)
        return
    end
    local s=sim(algo,p,c=='SNAPSHOT' and extra or nil)
    check(c=='TIMELINE' and s.time>100,'too long '..s.time)
    if c=='TIMELINE' then
        emit(c,algo,notation(p,algo),'end='..s.time)
    elseif c=='SNAPSHOT' then
        emit(c,algo,notation(p,algo),'t='..extra)
    elseif c=='WINDOW' then
        emit(c,algo,notation(p,algo),'width='..extra)
    else
        emit(c,algo,notation(p,algo))
    end
    if c=='TRACE' then
        for _,v in ipairs(s.events) do
            emit(v)
        end
        emit('END',s.time)
    elseif c=='SNAPSHOT' then
        for _,v in ipairs(s.snapshot) do
            emit(v)
        end
    elseif c=='TIMELINE' then
        for _,j in ipairs(s.jobs) do
            emit(string.format('%-8s',j.id),table.concat(j.timeline))
        end
    elseif c=='BURSTS' then
        for _,j in ipairs(s.jobs) do
            for i,r in ipairs(j.records) do
                emit(j.id,'#'..i,'len='..r.length,'ready='..r.ready,'start='..r.start,'end='..r.finish,'wait='..(r.finish-r.ready-r.length),'slices='..r.slices)
            end
        end
    elseif c=='WINDOW' then
        for start=0,s.time-1,extra do
            local stop=math.min(start+extra,s.time)
            local b,cs,idle=s:ticks(start,stop)
            local counts={}
            for t=start+1,stop do
                if s.states[t]=='RUN' then
                    local id=s.labels[t]
                    counts[id]=(counts[id] or 0)+1
                end
            end
            local top=nil
            for id,n in pairs(counts) do
                if not top or n>counts[top] or (n==counts[top] and id<top) then
                    top=id
                end
            end
            emit(start..'-'..stop,'busy='..b,'switch='..cs,'idle='..idle,'util='..truncated(b*100,stop-start),'top='..(top or 'none'))
        end
    elseif c=='STATS' then
        for i,m in ipairs(METRICS) do
            local vs,total,low,high,low_id,high_id={},0
            for _,j in ipairs(s.jobs) do
                local v=metrics(j)[i]
                vs[#vs+1]=v
                total=total+v
                if not low or v<low then
                    low,low_id=v,j.id
                end
                if not high or v>high then
                    high,high_id=v,j.id
                end
            end
            table.sort(vs)
            local n=#vs
            local double=vs[(n+1)//2]+vs[n//2+1]
            emit(m,'min='..low,'('..low_id..')','max='..high,'('..high_id..')','median='..(double//2)..'.'..(double%2==1 and 5 or 0),'total='..total)
        end
    elseif c=='RUN' then
        local seg=s:segments()
        for i=1,#seg,8 do
            local group={}
            for j=i,math.min(i+7,#seg) do
                group[#group+1]=seg[j]
            end
            emit('GANTT',table.concat(group))
        end
        for _,j in ipairs(s.jobs) do
            local v=metrics(j)
            local text=j.id..' arrival='..j.process.arrival..' done='..j.finish..' '..metric_parts(v)..' slices='..slices(j)
            if deadline(j) then
                text=text..' deadline='..deadline(j)..' late='..math.max(0,j.finish-deadline(j))
            end
            emit(text)
        end
        emit('AVERAGE',metric_parts(s:averages()))
        local b,cs,idle=s:ticks(0,s.time)
        emit('CPU','end='..s.time,'busy='..b,'switch='..cs,'idle='..idle,'switches='..s.switches,'util='..s:utilization())
        local max,total=0,0
        for _,n in ipairs(s.lengths) do
            max=math.max(max,n)
            total=total+n
        end
        emit('QUEUE','max='..max,'avg='..truncated(total,s.time))
        local parts={}
        for _,k in ipairs(EVENT_KINDS) do
            parts[#parts+1]=k:lower()..'='..(s.counts[k] or 0)
        end
        emit('EVENTS',table.concat(parts,' '))
        emit('DEADLINE','met='..s:met(),'missed='..s:missed())
    end
end
local n=tonumber(io.read())
for _=1,n do
    local a={}
    for w in io.read():gmatch('%S+') do
        a[#a+1]=w
    end
    local c=table.remove(a,1)
    local ok,reason=pcall(execute,c,a)
    if not ok then
        emit('ERROR',reason)
    end
end
