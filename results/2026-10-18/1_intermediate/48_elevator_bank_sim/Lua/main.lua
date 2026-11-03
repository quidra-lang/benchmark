local POLICIES={'COST','NEAREST','ROUND','ETA'}
local CONFIG_KEYS={'FLOORS','CARS','CAPACITY','DOOR','START','POLICY','ZONES','PARK','PATIENCE','BYPASS','PERIOD','LIMIT','COMPARE'}
local ARG_COUNTS={CALL=3,CANCEL=1,OUT=1,IN=1,HOLD=2,FIRE=1,RESET=0,WHERE=1,STATUS=0}
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
local function sign(x)
    return x>0 and 1 or x<0 and -1 or 0
end
local function contains(a,x)
    for _,v in ipairs(a) do
        if v==x then
            return true
        end
    end
    return false
end
local function joined(a)
    return #a==0 and '-' or table.concat(a,',')
end
local function average(total,count)
    if count==0 then
        return '-'
    end
    local n=total*100//count
    return string.format('%d.%02d',n//100,n%100)
end
local function keys(t)
    local a={}
    for k in pairs(t) do
        a[#a+1]=k
    end
    table.sort(a)
    return a
end
local function remove(list,value)
    for i,v in ipairs(list) do
        if v==value then
            table.remove(list,i)
            return
        end
    end
end
local function parse_config(lines)
    local entries={}
    for _,words in ipairs(lines) do
        local k=words[1]
        check(not contains(CONFIG_KEYS,k),'unknown key '..k)
        check(entries[k]~=nil,'duplicate key '..k)
        local vs={}
        for i=2,#words do
            vs[#vs+1]=words[i]
        end
        entries[k]=vs
    end
    for i=1,5 do
        local k=CONFIG_KEYS[i]
        check(not entries[k],'missing key '..k)
    end
    local c={POLICY='COST',BYPASS=100,LIMIT=1000,COMPARE={}}
    local ranges={FLOORS={2,50},CARS={1,8},CAPACITY={1,20},DOOR={1,9},PATIENCE={1,1000},BYPASS={50,100},PERIOD={1,1000},LIMIT={1,5000}}
    for _,k in ipairs(CONFIG_KEYS) do
        if entries[k] then
            local vs=entries[k]
            local count=#vs
            local valid_count
            if k=='START' or k=='ZONES' then
                valid_count=count==c.CARS
            elseif k=='PARK' then
                valid_count=count==c.CARS+1
            elseif k=='COMPARE' then
                valid_count=count>=1 and count<=4
            else
                valid_count=count==1
            end
            check(not valid_count,'wrong number of values for '..k)
            local valid=true
            if ranges[k] then
                local v=tonumber(vs[1])
                valid=v>=ranges[k][1] and v<=ranges[k][2]
                c[k]=v
            elseif k=='POLICY' then
                valid=contains(POLICIES,vs[1])
                c[k]=vs[1]
            elseif k=='COMPARE' then
                local seen={}
                for _,v in ipairs(vs) do
                    if not contains(POLICIES,v) or seen[v] then
                        valid=false
                    end
                    seen[v]=true
                end
                c[k]=vs
            elseif k=='ZONES' then
                local zs={}
                for _,v in ipairs(vs) do
                    local a,b=v:match('^([^:]+):([^:]+)$')
                    a,b=tonumber(a),tonumber(b)
                    valid=valid and 1<=a and a<b and b<=c.FLOORS
                    zs[#zs+1]={a,b}
                end
                c[k]=zs
            else
                local ns={}
                for i,text in ipairs(vs) do
                    local n=tonumber(text)
                    ns[#ns+1]=n
                    if k=='PARK' and i==1 then
                        valid=valid and n>=0 and n<=100
                    else
                        valid=valid and n>=1 and n<=c.FLOORS
                    end
                end
                c[k]=ns
            end
            check(not valid,'bad value for '..k)
        end
    end
    if not c.ZONES then
        c.ZONES={}
        for _=1,c.CARS do
            c.ZONES[#c.ZONES+1]={1,c.FLOORS}
        end
    end
    for i=1,c.CARS do
        local a,b=c.ZONES[i][1],c.ZONES[i][2]
        check(c.START[i]<a or c.START[i]>b,'car '..i..' starts outside its zone')
        if c.PARK then
            check(c.PARK[i+1]<a or c.PARK[i+1]>b,'car '..i..' home outside its zone')
        end
    end
    return c
end
local function validate_events(c,lines)
    local accepted,last,groups,out,fire={},0,0,{},false
    for _,entry in ipairs(lines) do
        local line,words=entry[1],entry[2]
        local time,cmd=tonumber(words[1]),words[2]
        local v={}
        for i=3,#words do
            v[#v+1]=tonumber(words[i]) or words[i]
        end
        local message=nil
        if not ARG_COUNTS[cmd] then
            message='unknown command '..cmd
        elseif #v~=ARG_COUNTS[cmd] then
            message='wrong number of arguments for '..cmd
        elseif time<last then
            message='time goes backwards'
        elseif cmd=='CALL' then
            local a,b,n=v[1],v[2],v[3]
            local serves=false
            for _,z in ipairs(c.ZONES) do
                if z[1]<=a and a<=z[2] and z[1]<=b and b<=z[2] then
                    serves=true
                end
            end
            if a<1 or a>c.FLOORS or b<1 or b>c.FLOORS then
                message='bad floor'
            elseif a==b then
                message='same floor'
            elseif n<1 or n>99 then
                message='bad count'
            elseif not serves then
                message='no car serves '..a..'->'..b
            elseif fire then
                message='fire service active'
            end
        elseif cmd=='CANCEL' or cmd=='WHERE' then
            if v[1]<1 or v[1]>groups then
                message='unknown group'
            end
        elseif cmd=='OUT' or cmd=='IN' then
            local e=v[1]
            if e<1 or e>c.CARS then
                message='bad car'
            elseif cmd=='OUT' and out[e] then
                message='car '..e..' already out'
            elseif cmd=='IN' and not out[e] then
                message='car '..e..' already in'
            end
        elseif cmd=='HOLD' then
            if v[1]<1 or v[1]>c.CARS then
                message='bad car'
            elseif v[2]<1 or v[2]>9 then
                message='bad ticks'
            end
        elseif cmd=='FIRE' then
            if v[1]<1 or v[1]>c.FLOORS then
                message='bad floor'
            elseif fire then
                message='fire already active'
            end
        elseif cmd=='RESET' and not fire then
            message='fire not active'
        end
        if message then
            emit('line '..line..': '..message)
        else
            accepted[#accepted+1]={time,cmd,v}
            last=time
            if cmd=='CALL' then
                groups=groups+1
            elseif cmd=='OUT' then
                out[v[1]]=true
            elseif cmd=='IN' then
                out[v[1]]=nil
            elseif cmd=='FIRE' then
                fire=true
            elseif cmd=='RESET' then
                fire=false
            end
        end
    end
    return accepted
end
local function group_label(g)
    return 'G'..g.number
end
local function car_label(car)
    return 'E'..car.number
end
local function direction(g)
    return sign(g.b-g.a)
end
local function load(car)
    local n=0
    for _,p in ipairs(car.passengers) do
        n=n+p.count
    end
    return n
end
local function targets(car)
    local set={}
    for _,p in ipairs(car.passengers) do
        set[p.group.b]=true
    end
    for _,g in ipairs(car.calls) do
        set[g.a]=true
    end
    return keys(set)
end
local function serves(car,g)
    return car.zone[1]<=g.a and g.a<=car.zone[2] and car.zone[1]<=g.b and g.b<=car.zone[2]
end
local Sim={}
Sim.__index=Sim
function Sim:log(...)
    if self.logging then
        emit(self.time,...)
    end
end
function Sim:bypass(car)
    return load(car)*100>=self.c.CAPACITY*self.c.BYPASS
end
function Sim:cost(car,g)
    local f,d,x=car.floor,car.direction,g.a
    if self.policy=='NEAREST' or d==0 then
        return math.abs(f-x)
    end
    local ts=targets(car)
    local distance,via=0,0
    if direction(g)==d and (x-f)*d>=0 then
        distance=math.abs(x-f)
        for _,y in ipairs(ts) do
            if (y-f)*d>0 and (x-y)*d>0 then
                via=via+1
            end
        end
    else
        local m=f
        for _,y in ipairs(ts) do
            if d>0 then
                m=math.max(m,y)
            else
                m=math.min(m,y)
            end
            if (y-f)*d>0 then
                via=via+1
            end
        end
        distance=math.abs(f-m)+math.abs(m-x)
    end
    return distance+(self.policy=='ETA' and self.c.DOOR*via+car.door or 0)
end
function Sim:assign(g,excluded)
    local candidates={}
    for _,car in ipairs(self.cars) do
        if car.service and car~=excluded and serves(car,g) then
            candidates[#candidates+1]=car
        end
    end
    if #candidates==0 then
        return false
    end
    local chosen=candidates[1]
    if self.policy=='ROUND' then
        for _,car in ipairs(candidates) do
            if car.number>self.round then
                chosen=car
                break
            end
        end
        self.round=chosen.number
        self:log(car_label(chosen),'ASSIGN',group_label(g))
    else
        local cost=self:cost(chosen,g)
        for i=2,#candidates do
            local car=candidates[i]
            local v=self:cost(car,g)
            if v<cost then
                chosen,cost=car,v
            end
        end
        self:log(car_label(chosen),'ASSIGN',group_label(g),'cost='..cost)
    end
    if g.car then
        remove(g.car.calls,g)
    end
    chosen.calls[#chosen.calls+1]=g
    g.car=chosen
    return true
end
function Sim:dispatch(g)
    if not self:assign(g) then
        self.pending[#self.pending+1]=g
        self:log('PENDING',group_label(g))
    end
end
function Sim:walk(g,word)
    if g.car then
        remove(g.car.calls,g)
    else
        remove(self.pending,g)
    end
    g.car=nil
    self:log(word,group_label(g),'x'..g.waiting)
    g.lost=g.lost+g.waiting
    self.abandoned=self.abandoned+g.waiting
    g.waiting=0
end
function Sim:event(cmd,v)
    if cmd=='CALL' then
        local a,b,n=v[1],v[2],v[3]
        local g={number=#self.groups+1,a=a,b=b,count=n,time=self.time,waiting=n,boarded=0,delivered=0,lost=0,last_board=0,last_alight=0,cars={},wait_total=0,travel_total=0}
        self.groups[#self.groups+1]=g
        self:log(cmd,group_label(g),a..'->'..b,'x'..n)
        self:dispatch(g)
    elseif cmd=='CANCEL' then
        local g=self.groups[v[1]]
        if g.waiting>0 then
            self:walk(g,cmd)
        else
            self:log(cmd,group_label(g),'ignored')
        end
    elseif cmd=='OUT' then
        local car=self.cars[v[1]]
        car.service=false
        self:log(car_label(car),cmd)
        local calls=car.calls
        car.calls={}
        for _,g in ipairs(calls) do
            g.car=nil
            self:dispatch(g)
        end
    elseif cmd=='IN' then
        local car=self.cars[v[1]]
        car.service=true
        car.idle=self.time
        self:log(car_label(car),cmd)
        local pending=self.pending
        self.pending={}
        for _,g in ipairs(pending) do
            if not self:assign(g) then
                self.pending[#self.pending+1]=g
            end
        end
    elseif cmd=='HOLD' then
        local car=self.cars[v[1]]
        if car.door>0 then
            car.door=car.door+v[2]
            self:log(car_label(car),cmd,car.door)
        else
            self:log(car_label(car),cmd,'ignored')
        end
    elseif cmd=='FIRE' then
        self.fire=v[1]
        self:log(cmd,self.fire)
        for _,g in ipairs(self.groups) do
            if g.waiting>0 then
                self:walk(g,'ABANDON')
            end
        end
    elseif cmd=='RESET' then
        self.fire=nil
        self:log(cmd)
        for _,car in ipairs(self.cars) do
            car.idle=self.time
        end
    elseif cmd=='WHERE' then
        local g=self.groups[v[1]]
        local place=g.waiting==0 and '-' or g.car and car_label(g.car) or 'pending'
        local riding={}
        for _,car in ipairs(self.cars) do
            local n=0
            for _,p in ipairs(car.passengers) do
                if p.group==g then
                    n=n+p.count
                end
            end
            if n>0 then
                riding[#riding+1]=car_label(car)..'x'..n
            end
        end
        self:log(cmd,group_label(g),'waiting='..g.waiting,'car='..place,'riding='..joined(riding),'delivered='..g.delivered,'lost='..g.lost)
    elseif cmd=='STATUS' then
        for _,car in ipairs(self.cars) do
            local set,calls={},{}
            for _,p in ipairs(car.passengers) do
                set[p.group.b]=true
            end
            for _,g in ipairs(car.calls) do
                calls[#calls+1]=group_label(g)
            end
            local dir=({[-1]='down',[0]='idle',[1]='up'})[car.direction]
            self:log(cmd,car_label(car),'floor='..car.floor,'dir='..dir,'door='..car.door,'load='..load(car),'stops='..joined(keys(set)),'calls='..joined(calls),'service='..(car.service and 'in' or 'out'))
        end
        local pending={}
        for _,g in ipairs(self.pending) do
            pending[#pending+1]=group_label(g)
        end
        self:log(cmd,'pending='..joined(pending))
    end
end
function Sim:heading(car)
    local f,d=car.floor,car.direction
    local here={}
    if not self:bypass(car) then
        for _,g in ipairs(car.calls) do
            if g.a==f then
                here[#here+1]=g
            end
        end
    end
    local ts=targets(car)
    if d~=0 then
        for _,y in ipairs(ts) do
            if (y-f)*d>0 then
                return d
            end
        end
        for _,g in ipairs(here) do
            if direction(g)==d then
                return d
            end
        end
    end
    if #here>0 then
        return direction(here[1])
    end
    if d~=0 then
        for _,y in ipairs(ts) do
            if (y-f)*d<0 then
                return -d
            end
        end
    end
    if d==0 and #car.calls>0 then
        return sign(car.calls[1].a-f)
    end
    return 0
end
function Sim:move(car,n)
    car.energy=car.energy+(n>0 and 3+load(car) or 1)
    car.floor=car.floor+n
    car.distance=car.distance+1
end
function Sim:deliver(p)
    local g=p.group
    local w,r=p.board_time-g.time,self.time-g.time
    g.delivered=g.delivered+p.count
    g.last_alight=self.time
    g.wait_total=g.wait_total+w*p.count
    g.travel_total=g.travel_total+r*p.count
    self.delivered=self.delivered+p.count
    self.wait_total=self.wait_total+w*p.count
    self.travel_total=self.travel_total+r*p.count
    self.max_wait=math.max(self.max_wait,w)
end
function Sim:open(car)
    self:log(car_label(car),'OPEN',car.floor)
    car.door=self.c.DOOR
    car.stops=car.stops+1
    car.energy=car.energy+2
    local riding={}
    for _,p in ipairs(car.passengers) do
        if p.group.b==car.floor then
            self:log(car_label(car),'ALIGHT',group_label(p.group),'x'..p.count)
            self:deliver(p)
        elseif self.fire then
            self:log(car_label(car),'EVACUATE',group_label(p.group),'x'..p.count)
            p.group.lost=p.group.lost+p.count
            self.evacuated=self.evacuated+p.count
        else
            riding[#riding+1]=p
        end
    end
    car.passengers=riding
    if self.fire then
        return
    end
    local n=self:heading(car)
    if n~=0 then
        car.direction=n
    end
    local boarding={}
    for _,g in ipairs(car.calls) do
        if g.a==car.floor and direction(g)==n then
            boarding[#boarding+1]=g
        end
    end
    for _,g in ipairs(boarding) do
        local k=math.min(self.c.CAPACITY-load(car),g.waiting)
        if k>0 then
            car.passengers[#car.passengers+1]={group=g,count=k,board_time=self.time}
            car.boarded=car.boarded+k
            g.waiting=g.waiting-k
            g.boarded=g.boarded+k
            g.last_board=self.time
            g.cars[car.number]=true
            self:log(car_label(car),'BOARD',group_label(g),'x'..k)
        end
        if g.waiting==0 then
            remove(car.calls,g)
            g.car=nil
        else
            self:log(car_label(car),'LEFT',group_label(g),'x'..g.waiting)
            self:assign(g,car)
        end
    end
end
function Sim:advance(car)
    local old=car.floor
    if car.door>0 then
        car.door=car.door-1
    end
    if car.door==0 then
        local n,stop
        if self.fire then
            n=sign(self.fire-car.floor)
            stop=n==0 and #car.passengers>0
        else
            n=self:heading(car)
            stop=false
            for _,p in ipairs(car.passengers) do
                if p.group.b==car.floor then
                    stop=true
                end
            end
            if not self:bypass(car) then
                for _,g in ipairs(car.calls) do
                    if g.a==car.floor and direction(g)==n then
                        stop=true
                    end
                end
            end
        end
        if stop then
            self:open(car)
        elseif n~=0 then
            car.direction=n
            self:move(car,n)
        else
            if car.direction~=0 then
                self:log(car_label(car),'IDLE',car.floor)
                car.direction=0
                car.idle=self.time
            end
            if not self.fire and car.service and car.home and car.floor~=car.home and self.time-car.idle>=self.c.PARK[1] then
                self:move(car,sign(car.home-car.floor))
                if car.floor==car.home then
                    self:log(car_label(car),'PARK',car.home)
                end
            end
        end
    end
    if car.door>0 or old~=car.floor then
        car.busy=car.busy+1
    end
end
function Sim:settled(car)
    if car.door>0 or #car.passengers>0 or #car.calls>0 then
        return false
    end
    if self.fire then
        return car.floor==self.fire
    end
    return not car.service or not car.home or car.floor==car.home
end
function Sim:run()
    local index=1
    while true do
        if self.c.PATIENCE then
            for _,g in ipairs(self.groups) do
                if g.waiting>0 and self.time==g.time+self.c.PATIENCE then
                    self:walk(g,'ABANDON')
                end
            end
        end
        while index<=#self.events and self.events[index][1]==self.time do
            local e=self.events[index]
            self:event(e[2],e[3])
            index=index+1
        end
        for _,car in ipairs(self.cars) do
            self:advance(car)
        end
        local settled=true
        for _,car in ipairs(self.cars) do
            if not self:settled(car) then
                settled=false
            end
        end
        if index>#self.events and settled then
            self.status='end'
            self:log('END')
            return
        end
        if self.time==self.c.LIMIT then
            self.status='abort'
            self:log('ABORT')
            return
        end
        self.time=self.time+1
    end
end
function Sim:averages()
    return 'avg_wait='..average(self.wait_total,self.delivered)..' avg_travel='..average(self.travel_total,self.delivered)..' max_wait='..(self.delivered>0 and self.max_wait or '-')
end
local function breakdown(label,gs)
    local n,d,w=0,0,0
    for _,g in ipairs(gs) do
        n=n+g.count
        d=d+g.delivered
        w=w+g.wait_total
    end
    emit(label..':','groups='..#gs,'passengers='..n,'delivered='..d,'avg_wait='..average(w,d))
end
function Sim:report()
    local passengers,floors,periods=0,{},{}
    for _,g in ipairs(self.groups) do
        passengers=passengers+g.count
        floors[g.a]=floors[g.a] or {}
        floors[g.a][#floors[g.a]+1]=g
        if self.c.PERIOD then
            local k=g.time//self.c.PERIOD
            periods[k]=periods[k] or {}
            periods[k][#periods[k]+1]=g
        end
        emit(group_label(g),'t='..g.time,g.a..'->'..g.b,'n='..g.count,'delivered='..g.delivered,'lost='..g.lost,'wait='..(g.boarded==g.count and g.last_board-g.time or '-'),'travel='..(g.delivered==g.count and g.last_alight-g.time or '-'),'cars='..joined(keys(g.cars)))
    end
    for _,car in ipairs(self.cars) do
        local n=car.busy*1000//(self.time+1)
        emit(car_label(car),'distance='..car.distance,'stops='..car.stops,'boarded='..car.boarded,'busy='..car.busy,'util='..(n//10)..'.'..(n%10)..'%','energy='..car.energy)
    end
    for _,f in ipairs(keys(floors)) do
        breakdown('F'..f,floors[f])
    end
    for _,k in ipairs(keys(periods)) do
        local w=self.c.PERIOD
        breakdown('P'..k..' '..(k*w)..'-'..(k*w+w-1),periods[k])
    end
    emit('summary:','groups='..#self.groups,'passengers='..passengers,'delivered='..self.delivered,'abandoned='..self.abandoned,'evacuated='..self.evacuated,self:averages(),'end='..self.time)
end
local function simulate(c,events,policy,logging)
    local s=setmetatable({c=c,events=events,policy=policy,logging=logging,cars={},groups={},pending={},round=0,time=0,delivered=0,wait_total=0,travel_total=0,max_wait=0,abandoned=0,evacuated=0},Sim)
    for i=1,c.CARS do
        s.cars[#s.cars+1]={number=i,floor=c.START[i],zone=c.ZONES[i],home=c.PARK and c.PARK[i+1] or nil,direction=0,door=0,passengers={},calls={},service=true,idle=0,distance=0,stops=0,boarded=0,busy=0,energy=0}
    end
    s:run()
    return s
end
local function words(line)
    local a={}
    for w in line:gmatch('%S+') do
        a[#a+1]=w
    end
    return a
end
local lines={}
for line in io.lines() do
    lines[#lines+1]=line
end
local index,scenarios=2,{}
for ordinal=1,tonumber(lines[1]) do
    local name=words(lines[index])[2]
    index=index+1
    local settings,events={},{}
    while lines[index]~='END' do
        local ws=words(lines[index])
        if ws[1]:match('^%d') then
            events[#events+1]={index,ws}
        else
            settings[#settings+1]=ws
        end
        index=index+1
    end
    index=index+1
    emit('== '..name..' ==')
    local ok,c=pcall(parse_config,settings)
    local scenario={name=name,ordinal=ordinal}
    scenarios[#scenarios+1]=scenario
    if not ok then
        emit('error:',c)
    else
        scenario.config=c
        emit('config:','floors='..c.FLOORS,'cars='..c.CARS,'capacity='..c.CAPACITY,'door='..c.DOOR,'policy='..c.POLICY,'park='..(c.PARK and c.PARK[1] or 'off'),'patience='..(c.PATIENCE or 'off'),'bypass='..c.BYPASS,'period='..(c.PERIOD or 'off'),'limit='..c.LIMIT,'compare='..joined(c.COMPARE))
        for i=1,c.CARS do
            emit('E'..i..':','start='..c.START[i],'zone='..c.ZONES[i][1]..'-'..c.ZONES[i][2],'home='..(c.PARK and c.PARK[i+1] or '-'))
        end
        local accepted=validate_events(c,events)
        local s=simulate(c,accepted,c.POLICY,true)
        s:report()
        scenario.sim=s
        for _,p in ipairs(c.COMPARE) do
            local o=simulate(c,accepted,p,false)
            emit('compare '..p..':','delivered='..o.delivered,o:averages(),'end='..o.time,'status='..o.status)
        end
    end
end
emit('== ranking ==')
local ranked={}
for _,s in ipairs(scenarios) do
    if s.sim and s.sim.status=='end' and s.sim.delivered>0 then
        ranked[#ranked+1]=s
    end
end
table.sort(ranked,function(x,y)
    local a,b=x.sim,y.sim
    local w1,w2=a.wait_total*b.delivered,b.wait_total*a.delivered
    if w1~=w2 then
        return w1<w2
    end
    local t1,t2=a.travel_total*b.delivered,b.travel_total*a.delivered
    if t1~=t2 then
        return t1<t2
    end
    return x.ordinal<y.ordinal
end)
for i,r in ipairs(ranked) do
    emit(i..'.',r.name,'policy='..r.config.POLICY,r.sim:averages())
end
for _,r in ipairs(scenarios) do
    local s=r.sim
    if not s or s.status~='end' or s.delivered==0 then
        emit('-',r.name,not s and 'invalid' or s.status=='abort' and 'aborted' or 'empty')
    end
end
emit('== policies ==')
for _,policy in ipairs(POLICIES) do
    local n,d,w,t=0,0,0,0
    for _,r in ipairs(ranked) do
        if r.config.POLICY==policy then
            local s=r.sim
            n=n+1
            d=d+s.delivered
            w=w+s.wait_total
            t=t+s.travel_total
        end
    end
    if n>0 then
        emit(policy..':','runs='..n,'avg_wait='..average(w,d),'avg_travel='..average(t,d))
    end
end
