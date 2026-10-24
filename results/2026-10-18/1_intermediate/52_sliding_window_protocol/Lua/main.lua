local function emit(s) io.write(s,"\n") end
local function words(line)
    local t={}
    for v in line:gmatch("%S+") do t[#t+1]=v end
    return t
end
local order={"PROTOCOL","FRAMES","WINDOW","SEQBITS","TIMEOUT","DELAY","INTERVAL","MAXTICKS",
    "DUPACK","NAK","BACKOFF","CONGESTION","UNSAFE","TRACE","RANDOM","LOSEDATA","LOSECTRL",
    "CORRUPTDATA","CORRUPTCTRL","DELAYDATA","DELAYCTRL","SNAPSHOT"}
local known={}
for i,k in ipairs(order) do known[k]=i end
local ranges={FRAMES={1,60},WINDOW={1,32},SEQBITS={1,6},TIMEOUT={1,50},DELAY={1,10},
    INTERVAL={0,10},MAXTICKS={1,2000},DUPACK={1,10}}
local allowed={PROTOCOL={SW=true,GBN=true,SR=true},NAK={ON=true,OFF=true},BACKOFF={ON=true,OFF=true},
    CONGESTION={ON=true,OFF=true},UNSAFE={ON=true,OFF=true},TRACE={ALL=true,SENDER=true,RECEIVER=true,NONE=true}}
local function inrange(n,lo,hi) return n and n>=lo and n<=hi end
local function validate(lines)
    local raw={}
    for _,line in ipairs(lines) do
        local w=words(line)
        local k=w[1]
        if not known[k] then return nil,"unknown key "..k end
        if raw[k] then return nil,"duplicate key "..k end
        local n=#w-1
        if (k=="RANDOM" and n~=3) or (known[k]>=16 and n<1) or (k~="RANDOM" and known[k]<16 and n~=1) then
            return nil,"wrong number of values for "..k
        end
        table.remove(w,1)
        raw[k]=w
    end
    for i=1,6 do if not raw[order[i]] then return nil,"missing key "..order[i] end end
    local c={INTERVAL=0,MAXTICKS=1000,NAK="OFF",BACKOFF="OFF",CONGESTION="OFF",UNSAFE="OFF",TRACE="ALL",
        LOSEDATA={},LOSECTRL={},CORRUPTDATA={},CORRUPTCTRL={},DELAYDATA={},DELAYCTRL={},SNAPSHOT={}}
    for _,k in ipairs(order) do
        local v=raw[k]
        if v then
            local valid=true
            if ranges[k] then
                c[k]=tonumber(v[1])
                valid=inrange(c[k],ranges[k][1],ranges[k][2])
            elseif allowed[k] then c[k]=v[1]; valid=allowed[k][v[1]]==true
            elseif k=="RANDOM" then
                local seed,p,corrupt=tonumber(v[1]),tonumber(v[2]),tonumber(v[3])
                valid=inrange(seed,1,2147483646) and p>=0 and corrupt>=0 and p+corrupt<=100
                c[k]={seed,p,corrupt}
            else
                local values={}
                for _,s in ipairs(v) do
                    local number,extra
                    if k=="DELAYDATA" or k=="DELAYCTRL" then
                        local a,b=s:match("^([^:]+):([^:]+)$")
                        number,extra=tonumber(a),tonumber(b)
                        if not inrange(number,1,9999) or not inrange(extra,1,50) then valid=false end
                    else
                        number=tonumber(s)
                        local lo,hi=1,9999
                        if k=="SNAPSHOT" then lo,hi=0,2000 end
                        if not inrange(number,lo,hi) then valid=false end
                    end
                    if values[number] then valid=false end
                    values[number]=extra or true
                end
                c[k]=values
            end
            if not valid then return nil,"bad value for "..k end
        end
    end
    if c.PROTOCOL=="SR" and c.DUPACK then return nil,"DUPACK not supported for SR" end
    local m=1<<c.SEQBITS
    local limit=c.PROTOCOL=="SW" and 1 or (c.PROTOCOL=="GBN" and m-1 or m//2)
    if c.WINDOW>limit and not (c.UNSAFE=="ON" and c.PROTOCOL~="SW") then
        return nil,"window "..c.WINDOW.." exceeds limit "..limit.." for "..c.PROTOCOL
    end
    local first
    for i in pairs(c.LOSEDATA) do if c.CORRUPTDATA[i] and (not first or i<first) then first=i end end
    if first then return nil,"data #"..first.." both lost and corrupted" end
    for i in pairs(c.LOSECTRL) do if c.CORRUPTCTRL[i] and (not first or i<first) then first=i end end
    if first then return nil,"control #"..first.." both lost and corrupted" end
    return c
end
local function decimal(x,y,digits,multiplier)
    local scale=10^digits
    local v=x*(multiplier or 1)*scale//y
    return string.format("%d.%0"..digits.."d",v//scale,v%scale)
end
local function simulate(c)
    local n,w,m,T,d=c.FRAMES,c.WINDOW,1<<c.SEQBITS,c.TIMEOUT,c.DELAY
    local sr=c.PROTOCOL=="SR"
    local trace=c.TRACE
    local base,H,nextframe,C,D=0,0,0,T,0
    local r,naksent=0,false
    local timer,timers,acked,queue,queued,buffer=nil,{},{},{},{},{}
    local cwnd,threshold,A=1,w,0
    local dataEvents,ctrlEvents={},{}
    local x=c.RANDOM and c.RANDOM[1]
    local stats={data=0,resent=0,control=0,nak=0,timeouts=0,fastretx=0,
        lost_data=0,lost_ctrl=0,corrupt_data=0,corrupt_ctrl=0,delivered=0,errors=0,discarded=0,max_buffer=0}
    local records={}
    for f=0,n-1 do records[f]={tx=0} end
    local function line(t,kind,s)
        if kind=="always" or trace=="ALL" or trace==kind then emit(t.." "..s) end
    end
    local function effective() return c.CONGESTION=="ON" and math.min(w,cwnd) or w end
    local function outcome(kind,number)
        local result="normal"
        if c.RANDOM then
            x=48271*x%2147483647
            local v=x%100
            if v<c.RANDOM[2] then result="lost"
            elseif v<c.RANDOM[2]+c.RANDOM[3] then result="corrupt" end
        end
        local suffix=kind=="data" and "DATA" or "CTRL"
        if c["LOSE"..suffix][number] then result="lost" end
        if c["CORRUPT"..suffix][number] then result="corrupt" end
        return result
    end
    local function transmit(t,kind,value)
        local number,events,delays
        if kind=="data" then number=stats.data; events=dataEvents; delays=c.DELAYDATA
        else number=stats.control; events=ctrlEvents; delays=c.DELAYCTRL end
        local arrival=t+d+(delays[number] or 0)
        events[arrival]=events[arrival] or {}
        events[arrival][#events[arrival]+1]={kind=kind,value=value,number=number,outcome=outcome(kind,number)}
    end
    local function control(t,kind,a)
        stats.control=stats.control+1
        if kind=="nak" then stats.nak=stats.nak+1 end
        line(t,"RECEIVER",kind:upper().." a="..a.." #"..stats.control)
        transmit(t,kind,a)
    end
    local function deliver(t,payload)
        if payload==r then
            line(t,"RECEIVER","DELIVER f="..r)
            records[r].delivered=t
            stats.delivered=stats.delivered+1
        else
            line(t,"RECEIVER","DELIVER f="..r.." wrong="..payload)
            stats.errors=stats.errors+1
        end
        r=r+1
        naksent=false
    end
    local function discard(t,s)
        stats.discarded=stats.discarded+1
        line(t,"RECEIVER","DISCARD seq="..s)
    end
    local function enqueue(f)
        if not queued[f] then queue[#queue+1]=f; queued[f]=true end
    end
    local function removequeue(f)
        if queued[f] then
            for i,v in ipairs(queue) do if v==f then table.remove(queue,i); break end end
            queued[f]=nil
        end
    end
    local function goback() nextframe,timer,D=base,nil,0 end
    local function increase(count)
        if c.CONGESTION~="ON" then return end
        for _=1,count do
            if cwnd<w then
                if cwnd<threshold then cwnd=cwnd+1
                else
                    A=A+1
                    if A==cwnd then cwnd,A=cwnd+1,0 end
                end
            end
        end
    end
    local function decrease(timeout)
        if c.CONGESTION=="ON" then
            threshold=math.max(cwnd//2,1)
            cwnd=timeout and 1 or threshold
            A=0
        end
    end
    local function showwindow(t,oldc,olds)
        if c.CONGESTION=="ON" and (oldc~=cwnd or olds~=threshold) then
            line(t,"SENDER","CWND "..cwnd.." ssthresh="..threshold)
        end
    end
    local function receive(t,e)
        local payload=e.value
        local s=payload%m
        line(t,"RECEIVER","RECV seq="..s.." #"..e.number)
        if not sr then
            if s==r%m then deliver(t,payload); control(t,"ack",s)
            else
                discard(t,s)
                if c.NAK=="ON" and not naksent then control(t,"nak",r%m); naksent=true
                elseif r>0 then control(t,"ack",(r-1)%m) end
            end
        else
            local offset=(s-r)%m
            if offset<w then
                local position=r+offset
                if buffer[position]~=nil then discard(t,s); control(t,"ack",s)
                elseif offset==0 then
                    deliver(t,payload)
                    while buffer[r]~=nil do
                        local value=buffer[r]
                        buffer[r]=nil
                        deliver(t,value)
                    end
                    control(t,"ack",s)
                else
                    buffer[position]=payload
                    local count=0
                    for _ in pairs(buffer) do count=count+1 end
                    stats.max_buffer=math.max(stats.max_buffer,count)
                    line(t,"RECEIVER","BUFFER f="..position)
                    control(t,"ack",s)
                    if c.NAK=="ON" and not naksent then control(t,"nak",r%m); naksent=true end
                end
            else
                discard(t,s)
                if (r-s)%m<=w then control(t,"ack",s) end
            end
        end
    end
    local function receivecontrol(t,e)
        local oldc,olds,oldbase=cwnd,threshold,base
        local a=e.value
        local f=base+(a-base)%m
        local accept=false
        if e.kind=="ack" then
            if sr then
                if f<H and not acked[f] then
                    accept=true
                    acked[f],timers[f]=true,nil
                    records[f].acked=records[f].acked or t
                    removequeue(f)
                    while base<H and acked[base] do base=base+1 end
                    increase(1)
                end
            elseif f<H then
                accept=true
                base=f+1
                if nextframe<base then nextframe=base end
                increase(base-oldbase)
            end
        else
            if sr then
                if f<H and not acked[f] then
                    accept=true
                    timers[f]=nil
                    enqueue(f)
                end
            elseif f<=H then
                accept=true
                base=f
                increase(base-oldbase)
                goback()
            end
            if accept then decrease(false) end
        end
        if base>oldbase then
            C=T
            if not sr then
                D=0
                for j=oldbase,base-1 do records[j].acked=records[j].acked or t end
            end
        end
        if accept then
            if not sr and e.kind=="ack" then timer=base~=nextframe and t+C or nil end
            line(t,"SENDER","GOT"..e.kind:upper().." a="..a.." #"..e.number.." base="..base)
        else
            line(t,"SENDER","OLD"..e.kind:upper().." a="..a.." #"..e.number)
            if not sr and e.kind=="ack" and c.DUPACK and base>=1 and a==(base-1)%m then
                D=D+1
                if D==c.DUPACK then
                    stats.fastretx=stats.fastretx+1
                    line(t,"SENDER","FASTRETX f="..base)
                    goback()
                    decrease(false)
                end
            end
        end
        showwindow(t,oldc,olds)
    end
    local function arrival(t,e,isdata)
        if e.outcome=="normal" then
            if isdata then receive(t,e) else receivecontrol(t,e) end
        else
            local suffix=isdata and "data" or "ctrl"
            local key=e.outcome.."_"..suffix
            stats[key]=stats[key]+1
            line(t,isdata and "RECEIVER" or "SENDER",(e.outcome=="lost" and "LOST " or "CORRUPT ")..e.kind.." #"..e.number)
        end
    end
    local function timeout(t,f)
        local oldc,olds=cwnd,threshold
        stats.timeouts=stats.timeouts+1
        line(t,"SENDER","TIMEOUT f="..f)
        if sr then timers[f]=nil; enqueue(f) else goback() end
        if c.BACKOFF=="ON" then C=math.min(2*C,8*T) end
        decrease(true)
        showwindow(t,oldc,olds)
    end
    local function send(t,f)
        local record=records[f]
        stats.data=stats.data+1
        local kind="SEND"
        if record.tx>0 then stats.resent=stats.resent+1; kind="RESEND" end
        record.tx=record.tx+1
        if record.first==nil then record.first=t end
        line(t,"SENDER",kind.." f="..f.." seq="..f%m.." #"..stats.data)
        transmit(t,"data",f)
    end
    local completion,finish
    for t=0,c.MAXTICKS do
        local arrivals=dataEvents[t] or {}
        table.sort(arrivals,function(a,b) return a.number<b.number end)
        for _,e in ipairs(arrivals) do arrival(t,e,true) end
        arrivals=ctrlEvents[t] or {}
        table.sort(arrivals,function(a,b) return a.number<b.number end)
        for _,e in ipairs(arrivals) do arrival(t,e,false) end
        if base==n then completion=t
        else
            if sr then
                for f=base,H-1 do if timers[f]==t then timeout(t,f) end end
            elseif timer==t then timeout(t,base) end
            local f
            if sr then
                if #queue>0 then f=table.remove(queue,1); queued[f]=nil
                elseif H<n and H<base+effective() and H*c.INTERVAL<=t then f=H; H=H+1 end
                if f~=nil then send(t,f); timers[f]=t+C end
            elseif nextframe<n and nextframe<base+effective() and (nextframe<H or nextframe*c.INTERVAL<=t) then
                f=nextframe
                send(t,f)
                H=math.max(H,f+1)
                nextframe=nextframe+1
                if timer==nil then timer=t+C end
            end
        end
        if c.SNAPSHOT[t] then
            local sender,receiver={},{}
            for f=0,n-1 do
                local state
                if (sr and acked[f]) or (not sr and f<base) then state="A"
                elseif (sr and queued[f]) or (not sr and nextframe<=f and f<H) then state="R"
                elseif (sr and f<H) or (not sr and f<nextframe) then state="O"
                elseif f<base+effective() then state="W" else state="." end
                sender[#sender+1]=state
                if f<r then state="D"
                elseif sr and buffer[f]~=nil then state="B"
                elseif (sr and f<r+w) or (not sr and f==r) then state="W" else state="." end
                receiver[#receiver+1]=state
            end
            line(t,"always","SNAPSHOT sender="..table.concat(sender).." receiver="..table.concat(receiver))
        end
        if completion or t==c.MAXTICKS then
            finish=t
            line(t,"always",completion and "DONE" or "ABORT")
            break
        end
    end
    local latency=0
    for f=0,n-1 do
        local rec=records[f]
        local function stamp(v) return v==nil and "-" or tostring(v) end
        emit("frame "..f..": seq="..f%m.." tx="..rec.tx.." first="..stamp(rec.first).." delivered="..stamp(rec.delivered).." acked="..stamp(rec.acked))
        if rec.delivered then latency=latency+rec.delivered-rec.first end
    end
    emit("totals: data="..stats.data.." resent="..stats.resent.." control="..stats.control.." nak="..stats.nak.." timeouts="..stats.timeouts.." fastretx="..stats.fastretx)
    emit("channel: lost_data="..stats.lost_data.." lost_ctrl="..stats.lost_ctrl.." corrupt_data="..stats.corrupt_data.." corrupt_ctrl="..stats.corrupt_ctrl)
    emit("receiver: delivered="..stats.delivered.." errors="..stats.errors.." discarded="..stats.discarded.." max_buffer="..stats.max_buffer)
    local goodput=completion and decimal(stats.delivered,completion,2) or "-"
    local efficiency=decimal(stats.delivered,stats.data,1,100)
    emit("result: completion="..(completion or "-").." goodput="..goodput.." efficiency="..efficiency.."% utilization="..decimal(stats.data,finish+1,1,100).."% latency="..(stats.delivered>0 and decimal(latency,stats.delivered,2) or "-"))
    return {completion=completion,delivered=stats.delivered,data=stats.data,goodput=goodput,efficiency=efficiency}
end
local results={}
local q=tonumber(io.read())
for i=1,q do
    local name=words(io.read())[2]
    local lines={}
    while true do
        local line=io.read()
        if line=="END" then break end
        lines[#lines+1]=line
    end
    emit("== "..name.." ==")
    local c,err=validate(lines)
    local result
    if err then emit("error: "..err); result={invalid=true}
    else
        emit("config: "..c.PROTOCOL.." n="..c.FRAMES.." w="..c.WINDOW.." k="..c.SEQBITS.." T="..c.TIMEOUT.." d="..c.DELAY)
        emit("options: interval="..c.INTERVAL.." limit="..c.MAXTICKS.." dupack="..(c.DUPACK or "off").." nak="..c.NAK:lower().." backoff="..c.BACKOFF:lower().." congestion="..c.CONGESTION:lower().." unsafe="..c.UNSAFE:lower().." trace="..c.TRACE:lower().." random="..(c.RANDOM and table.concat(c.RANDOM,"/") or "off"))
        result=simulate(c)
        result.protocol=c.PROTOCOL
    end
    result.name,result.order=name,i
    results[#results+1]=result
end
emit("== ranking ==")
local completed={}
for _,r in ipairs(results) do if r.completion then completed[#completed+1]=r end end
 table.sort(completed,function(a,b)
    local left,right=a.delivered*b.completion,b.delivered*a.completion
    if left~=right then return left>right end
    left,right=a.delivered*b.data,b.delivered*a.data
    if left~=right then return left>right end
    return a.order<b.order
end)
for rank,r in ipairs(completed) do emit(rank..". "..r.name.." "..r.protocol.." goodput="..r.goodput.." efficiency="..r.efficiency.."%") end
for _,r in ipairs(results) do if not r.completion then emit("- "..r.name.." "..(r.invalid and "invalid" or "aborted")) end end
emit("== protocols ==")
for _,protocol in ipairs({"SW","GBN","SR"}) do
    local count,delivered,ticks,data=0,0,0,0
    for _,r in ipairs(completed) do
        if r.protocol==protocol then count=count+1; delivered=delivered+r.delivered; ticks=ticks+r.completion; data=data+r.data end
    end
    if count>0 then emit(protocol..": runs="..count.." goodput="..decimal(delivered,ticks,2).." efficiency="..decimal(delivered,data,1,100).."%") end
end
