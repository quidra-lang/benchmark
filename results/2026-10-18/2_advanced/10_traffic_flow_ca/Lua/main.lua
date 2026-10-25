local Minstd=require('minstd')
local Road=require('road')
local Vehicles=require('vehicles')
local Signals=require('signals')
local Stats=require('stats')
local fmt=string.format
local min,max=math.min,math.max
local dec,frac=Stats.dec,Stats.frac
local function extend(destination,source) for _,value in ipairs(source) do destination[#destination+1]=value end end
local function tokens(line) local result={}; for token in line:gmatch('[^ ]+') do result[#result+1]=token end; return result end
local function ratio(n,d) local g=Stats.gcd(n,d); return {n//g,d//g} end
local function multiply(r,n,d) local a,b=Stats.gcd(r[1],d),Stats.gcd(n,r[2]); return ratio((r[1]//a)*(n//b),(r[2]//b)*(d//a)) end
local function add(r,s) local g=Stats.gcd(r[2],s[2]); return ratio(r[1]*(s[2]//g)+s[1]*(r[2]//g),r[2]*(s[2]//g)) end
local function enumerate(segment)
    if not segment.junction then return {{segments={segment},share={1,1},sink=segment.to}} end
    local total=0; for _,turn in ipairs(segment.turns) do total=total+turn.weight end
    local routes={}
    for _,turn in ipairs(segment.turns) do
        for _,route in ipairs(enumerate(turn.target)) do
            local path={segment}; extend(path,route.segments)
            routes[#routes+1]={segments=path,share=multiply(route.share,turn.weight,total),sink=route.sink}
        end
    end
    return routes
end
local function read_simulation()
    local m={segments={},segment_by_id={},junctions={},incidents={},stops={},classes={},sources={},sinks={},detectors={},diagrams={},tracks={},tracked={},rings={},vehicles={},totals={},events={}}
    for line in io.lines('input/network.txt') do
        local p=tokens(line); local kind=p[1]
        if kind=='SEGMENT' then local s=Road.segment(p[2],p[3],p[4],tonumber(p[5]),tonumber(p[6]),tonumber(p[7])); m.segments[#m.segments+1]=s; m.segment_by_id[s.id]=s
        elseif kind=='JUNCTION' then local phases={}; for i=4,#p do phases[#phases+1]=p[i] end; m.junctions[#m.junctions+1]=Signals.new(p[2],tonumber(p[3]),phases)
        elseif kind=='INCIDENT' then m.incidents[#m.incidents+1]=Road.incident(m.segment_by_id[p[2]],tonumber(p[3]),tonumber(p[4]),tonumber(p[5]),tonumber(p[6]))
        elseif kind=='STOP' then local stop={segment=m.segment_by_id[p[2]],cell=tonumber(p[3]),dwell=tonumber(p[4]),buses=0}; stop.segment.stop=stop; m.stops[#m.stops+1]=stop end
    end
    for _,s in ipairs(m.segments) do for _,j in ipairs(m.junctions) do if s.to==j.node then s.junction=j end end end
    for line in io.lines('input/demand.txt') do
        local p=tokens(line); local kind=p[1]
        if kind=='CLASS' then m.classes[#m.classes+1]=Vehicles.class(p[2],tonumber(p[3]),tonumber(p[4]),p[5]=='Y',p[6]=='Y')
        elseif kind=='SOURCE' then
            local source={node=p[2],rates={},queue={},head=1,wait=0,maximum=0}
            for _,s in ipairs(m.segments) do if s.from==source.node then source.entry=s end end
            for i=3,#p do local rate,finish=p[i]:match('^(%d+):(%d+)$'); source.rates[#source.rates+1]={tonumber(rate),tonumber(finish)} end
            m.sources[#m.sources+1]=source
        elseif kind=='SINK' then m.sinks[#m.sinks+1]=p[2]
        elseif kind=='TURN' then local s=m.segment_by_id[p[2]]; s.turns[#s.turns+1]={target=m.segment_by_id[p[3]],weight=tonumber(p[4]),vehicles=0} end
    end
    for line in io.lines('input/params.txt') do
        local p=tokens(line); local kind=p[1]
        if kind=='seed' then m.random=Minstd.new(tonumber(p[2]))
        elseif kind=='steps' then m.steps=tonumber(p[2])
        elseif kind=='dawdle' then m.p=tonumber(p[2]); m.p0=tonumber(p[3])
        elseif kind=='interval' then m.interval=tonumber(p[2])
        elseif kind=='bin' then m.bin=tonumber(p[2])
        elseif kind=='detector' then m.detectors[#m.detectors+1]={name=p[2],segment=m.segment_by_id[p[3]],cell=tonumber(p[4]),width=tonumber(p[5]),totals={}}
        elseif kind=='diagram' then m.diagrams[#m.diagrams+1]={segment=m.segment_by_id[p[2]],lane=tonumber(p[3]),start=tonumber(p[4]),finish=tonumber(p[5]),lines={}}
        elseif kind=='track' then for i=2,#p do local id=tonumber(p[i]); m.tracks[#m.tracks+1]=id; m.tracked[id]=true end
        elseif kind=='ring' then local r={length=tonumber(p[2]),vmax=tonumber(p[3]),warm=tonumber(p[4]),measure=tonumber(p[5]),seed=tonumber(p[6]),counts={}}; for i=7,#p do r.counts[#r.counts+1]=tonumber(p[i]) end; m.rings[#m.rings+1]=r end
    end
    for i=1,m.steps//m.interval do m.totals[i]={arrived=0,inserted=0,exited=0,steps=0,speed=0}; for _,d in ipairs(m.detectors) do d.totals[i]={passing=0,occupancy=0,speed=0} end end
    for _,source in ipairs(m.sources) do source.routes=enumerate(source.entry) end
    return m
end
local function enter(m,v,s)
    v.route[#v.route+1]=s; s.entered=s.entered+1; v.turn=nil
    if s.junction then local weights={}; for _,turn in ipairs(s.turns) do weights[#weights+1]=turn.weight end; v.turn=s.turns[Minstd.select(weights,m.random:draw())] end
end
local function desired_lane(v)
    local s,l,x=v.segment,v.lane,v.cell; local maximum=v:maximum(); local here=s:free(l,x,maximum+1); local want=min(v.speed+1,maximum)
    if here<maximum+1 and x+here+1<s.length and s.cells[l][x+here+2]<0 then
        for _,next_lane in ipairs({l+1,l-1}) do if next_lane>=1 and next_lane<=s.lanes and s:free(next_lane,x,maximum+1)>here and s:safe(next_lane,x) then return next_lane,3 end end
    end
    if v:heading() then if l>=2 and s:safe(l-1,x) then return l-1,2 end; return l end
    if v.class.overtake and l+1<=s.lanes and here<want and s:free(l+1,x,maximum+1)>here and s:safe(l+1,x) then return l+1,1 end
    if l>=2 and s:free(l-1,x,maximum+1)>want and s:safe(l-1,x) then return l-1,2 end
    return l
end
local function run(m)
    local weights={}; for _,class in ipairs(m.classes) do weights[#weights+1]=class.weight end
    for t=1,m.steps do
        for _,incident in ipairs(m.incidents) do local event=Road.update(incident,t); if event then m.events[#m.events+1]=event end end
        local index=(t-1)//m.interval+1; local interval=m.totals[index]
        for _,source in ipairs(m.sources) do
            local rate=0; for _,period in ipairs(source.rates) do if t<=period[2] then rate=period[1]; break end end
            if m.random:draw()%1000<rate then local class=m.classes[Minstd.select(weights,m.random:draw())]; local v=Vehicles.new(#m.vehicles+1,class,source,t); m.vehicles[#m.vehicles+1]=v; source.queue[#source.queue+1]=v; interval.arrived=interval.arrived+1 end
        end
        for _,source in ipairs(m.sources) do
            local s=source.entry
            while source.head<=#source.queue do
                local lane,first=nil,-1
                for l=1,s.lanes do if s.cells[l][1]==0 and s:first(l)>first then lane=l; first=s:first(l) end end
                if not lane then break end
                local v=source.queue[source.head]; source.head=source.head+1; v:place(s,lane,0); v.inserted=t; enter(m,v,s); interval.inserted=interval.inserted+1
            end
            local waiting=#source.queue-source.head+1
            if waiting>0 and source.wait==0 then source.wait=t; source.maximum=0 end
            if source.wait~=0 then
                source.maximum=max(source.maximum,waiting)
                if waiting==0 then m.events[#m.events+1]=fmt('%04d QUEUE %s from %d max %d',t,source.node,source.wait,source.maximum); source.wait=0 end
            end
        end
        local changes={}
        for _,s in ipairs(m.segments) do
            if s.lanes>=2 then
                local reserved={}; for l=1,s.lanes do reserved[l]={} end
                for l=1,s.lanes do for _,id in ipairs(s.cells[l]) do
                    if id>0 then local v=m.vehicles[id]; if v.dwell==0 then local next_lane,kind=desired_lane(v); if next_lane~=l and not reserved[next_lane][v.cell] then reserved[next_lane][v.cell]=true; changes[#changes+1]={vehicle=v,lane=next_lane,kind=kind} end end end
                end end
            end
        end
        for _,change in ipairs(changes) do local v=change.vehicle; local s=v.segment; v:place(s,change.lane,v.cell); v.lane_changes=v.lane_changes+1; s.changes[change.kind]=s.changes[change.kind]+1 end
        local moves={}
        for _,s in ipairs(m.segments) do for l=1,s.lanes do for x=s.length-1,0,-1 do
            local id=s.cells[l][x+1]
            if id>0 then
                local v=m.vehicles[id]; local a=min(v.speed+1,v:maximum()); local gap=s:free(l,x,a)
                if gap<a and x+gap==s.length-1 then if not s.junction then gap=a elseif s.junction:green(s.id,t) then local target=v.turn.target; gap=gap+target:free(min(l,target.lanes),-1,a-gap) end end
                if v:heading() then gap=min(gap,s.stop.cell-x) end
                local u=Vehicles.slowdown(min(a,gap),v.speed,m.random:draw(),m.p,m.p0)
                if v.dwell>0 then u=0; v.dwell=v.dwell-1 end
                moves[#moves+1]={vehicle=v,segment=s,cell=x,u=u}
            end
        end end end
        for _,move in ipairs(moves) do
            local v,s,x=move.vehicle,move.segment,move.cell
            if x+move.u<s.length then v:place(s,v.lane,x+move.u)
            elseif not s.junction then v:leave(); v.exited=t; v.sink=s.to; interval.exited=interval.exited+1 end
        end
        for _,move in ipairs(moves) do
            local v,s,x=move.vehicle,move.segment,move.cell
            if x+move.u>=s.length and s.junction then
                local turn=v.turn; local target=turn.target; local lane=min(v.lane,target.lanes); local want=x+move.u-s.length; local pos=min(want,target:first(lane)-1)
                if pos<want then s.blocked=s.blocked+1 end
                if pos>=0 then v:place(target,lane,pos); move.u=s.length-x+pos; s.passed=s.passed+1; turn.vehicles=turn.vehicles+1; enter(m,v,target)
                else v:place(s,v.lane,s.length-1); move.u=s.length-1-x end
            end
        end
        for _,move in ipairs(moves) do
            local v,u=move.vehicle,move.u
            v.steps=v.steps+1; v.distance=v.distance+u
            if u==0 then v.stopped_steps=v.stopped_steps+1; if v.speed>0 then v.stop_count=v.stop_count+1 end end
            v.speed=u; interval.steps=interval.steps+1; interval.speed=interval.speed+u
            if v:heading() and v.lane==1 and v.cell==v.segment.stop.cell then local s=v.segment; v.completed[s]=true; v.dwell=s.stop.dwell; s.stop.buses=s.stop.buses+1; m.events[#m.events+1]=fmt('%04d BUS_STOP %d %s cell %d',t,v.number,s.id,v.cell) end
            if m.tracked[v.number] then local line; if v.segment then line=fmt('%04d %s %d %d %d',t,v.segment.id,v.lane,v.cell,v.speed) else line=fmt('%04d EXIT %d',t,v.speed) end; v.trajectory[#v.trajectory+1]=line end
            for _,d in ipairs(m.detectors) do if move.segment==d.segment and move.cell<d.cell and (v.segment~=d.segment or v.cell>=d.cell) then d.totals[index].passing=d.totals[index].passing+1 end end
        end
        for _,d in ipairs(m.detectors) do
            local total=d.totals[index]
            for _,row in ipairs(d.segment.cells) do for x=d.cell,d.cell+d.width-1 do local id=row[x+1]; if id>0 then total.occupancy=total.occupancy+1; total.speed=total.speed+m.vehicles[id].speed end end end
        end
        for _,s in ipairs(m.segments) do
            local count,queued,speed=0,0,0
            for _,row in ipairs(s.cells) do for _,id in ipairs(row) do if id>0 then count=count+1; local v=m.vehicles[id]; speed=speed+v.speed; if v.speed==0 then queued=queued+1 end end end end
            s.vehicle_sum=s.vehicle_sum+count; s.speed_sum=s.speed_sum+speed; s.max_vehicles=max(s.max_vehicles,count)
            if s.junction then local green=s.junction:green(s.id,t); if green then s.green_count=s.green_count+1 end; s.queue_sum=s.queue_sum+queued; s.max_queue=max(s.max_queue,queued); if t<m.steps and queued>0 and green and not s.junction:green(s.id,t+1) then s.failures=s.failures+1 end end
        end
        for _,d in ipairs(m.diagrams) do
            if d.start<=t and t<=d.finish then local signal='E'; if d.segment.junction then signal=d.segment.junction:green(d.segment.id,t) and 'G' or 'R' end; d.lines[#d.lines+1]=fmt('%04d %s %s',t,d.segment:cells_text(d.lane,m.vehicles),signal) end
        end
    end
    for _,source in ipairs(m.sources) do if source.wait~=0 then m.events[#m.events+1]=fmt('%04d QUEUE %s from %d max %d open',m.steps,source.node,source.wait,source.maximum) end end
end
local function route_text(path,separator) local ids={}; for _,s in ipairs(path) do ids[#ids+1]=s.id end; return table.concat(ids,separator) end
local function equal_route(a,b) if #a~=#b then return false end; for i,s in ipairs(a) do if s~=b[i] then return false end end; return true end
local function travel_block(heading,vehicles,bin)
    local times,total={},0
    for _,v in ipairs(vehicles) do if v.exited>0 then local time=v:travel(); times[#times+1]=time; total=total+time end end
    if #times==0 then return {heading..' exited 0'} end
    table.sort(times)
    local lines={fmt('%s exited %d min %d p50 %d p90 %d max %d mean %s',heading,#times,times[1],Stats.percentile(times,50),Stats.percentile(times,90),times[#times],dec(total,#times,2))}; extend(lines,Stats.histogram(times,bin)); return lines
end
local function class_block(heading,vehicles)
    local inserted,exited,steps,distance,travel,delay,stopped,stops,changes=0,0,0,0,0,0,0,0,0
    for _,v in ipairs(vehicles) do
        if v.inserted>0 then inserted=inserted+1 end
        steps=steps+v.steps; distance=distance+v.distance
        if v.exited>0 then exited=exited+1; travel=travel+v:travel(); delay=delay+v.inserted-v.arrival; stopped=stopped+v.stopped_steps; stops=stops+v.stop_count; changes=changes+v.lane_changes end
    end
    return {heading,fmt('  generated %d inserted %d exited %d in_network %d queued %d',#vehicles,inserted,exited,inserted-exited,#vehicles-inserted),fmt('  vehicle_steps %d distance %d mean_speed %s = %s',steps,distance,frac(distance,steps),dec(distance,steps,3)),fmt('  travel %s entry_delay %s stopped %s stops %s lane_changes %s',dec(travel,exited,2),dec(delay,exited,2),dec(stopped,exited,2),dec(stops,exited,2),dec(changes,exited,2))}
end
local function ring_experiment(m,r,count)
    local cars={}; for i=0,count-1 do cars[#cars+1]={position=i*r.length//count,speed=0} end
    local random=Minstd.new(r.seed); local total=0
    for t=1,r.warm+r.measure do
        table.sort(cars,function(a,b) return a.position>b.position end)
        local speeds={}
        for i,car in ipairs(cars) do local ahead=cars[(i-2)%count+1].position; local gap=(ahead-car.position-1)%r.length; speeds[i]=Vehicles.slowdown(min(car.speed+1,r.vmax,gap),car.speed,random:draw(),m.p,m.p0) end
        for i,car in ipairs(cars) do car.position=(car.position+speeds[i])%r.length; car.speed=speeds[i]; if t>r.warm then total=total+speeds[i] end end
    end
    return total
end
local function output(m)
    local files={['spacetime.txt']={},['detectors.csv']={'detector,interval,flow,density,speed'},['travel_times.txt']={},['class_stats.txt']={},['network_stats.txt']={},['timeline.csv']={'interval,arrived,inserted,exited,in_network,queued,mean_speed'},['tracks.txt']={},['fundamental.csv']={'ring,vehicles,density,flow,speed'},['events.txt']=m.events}
    local spacetime,detectors,travel,classes,network,timeline,tracks,fundamental=files['spacetime.txt'],files['detectors.csv'],files['travel_times.txt'],files['class_stats.txt'],files['network_stats.txt'],files['timeline.csv'],files['tracks.txt'],files['fundamental.csv']
    for _,d in ipairs(m.diagrams) do spacetime[#spacetime+1]=fmt('DIAGRAM %s lane %d steps %d-%d',d.segment.id,d.lane,d.start,d.finish); extend(spacetime,d.lines) end
    for _,d in ipairs(m.detectors) do for k,total in ipairs(d.totals) do detectors[#detectors+1]=fmt('%s,%d,%d,%s,%s',d.name,k,total.passing,dec(total.occupancy,m.interval*d.width*d.segment.lanes,4),dec(total.speed,total.occupancy,2)) end end
    for _,class in ipairs(m.classes) do local vehicles={}; for _,v in ipairs(m.vehicles) do if v.class==class then vehicles[#vehicles+1]=v end end; local heading='CLASS '..class.name; extend(travel,travel_block(heading,vehicles,m.bin)); extend(classes,class_block(fmt('%s vmax %d weight %d overtake %s stops %s',heading,class.vmax,class.weight,class.overtake and 'Y' or 'N',class.stops and 'Y' or 'N'),vehicles)) end
    extend(travel,travel_block('ALL',m.vehicles,m.bin)); extend(classes,class_block('ALL',m.vehicles))
    for _,source in ipairs(m.sources) do
        local exited={}; for _,v in ipairs(m.vehicles) do if v.source==source and v.exited>0 then exited[#exited+1]=v end end
        travel[#travel+1]=fmt('SOURCE %s exited %d',source.node,#exited)
        for _,route in ipairs(source.routes) do local count,total=0,0; for _,v in ipairs(exited) do if equal_route(v.route,route.segments) then count=count+1; total=total+v:travel() end end; travel[#travel+1]=fmt('  ROUTE %s expected %s vehicles %d share %s mean %s',route_text(route.segments,','),frac(route.share[1],route.share[2]),count,frac(count,#exited),dec(total,count,2)) end
        for _,sink in ipairs(m.sinks) do
            local share,found={0,1},false; for _,route in ipairs(source.routes) do if route.sink==sink then share=add(share,route.share); found=true end end
            if found then local count,total=0,0; for _,v in ipairs(exited) do if v.sink==sink then count=count+1; total=total+v:travel() end end; travel[#travel+1]=fmt('  SINK %s expected %s vehicles %d share %s mean %s',sink,frac(share[1],share[2]),count,frac(count,#exited),dec(total,count,2)) end
        end
    end
    for _,s in ipairs(m.segments) do network[#network+1]=fmt('SEGMENT %s %s %s length %d lanes %d limit %d entered %d mean_vehicles %s density %s mean_speed %s max_vehicles %d changes %d/%d/%d',s.id,s.from,s.to,s.length,s.lanes,s.limit,s.entered,dec(s.vehicle_sum,m.steps,3),dec(s.vehicle_sum,m.steps*s.length*s.lanes,4),dec(s.speed_sum,s.vehicle_sum,2),s.max_vehicles,s.changes[1],s.changes[2],s.changes[3]) end
    for _,j in ipairs(m.junctions) do
        extend(network,j:lines())
        for _,s in ipairs(m.segments) do if s.junction==j then network[#network+1]=fmt('  IN %s green %d passed %d blocked %d max_queue %d mean_queue %s failures %d',s.id,s.green_count,s.passed,s.blocked,s.max_queue,dec(s.queue_sum,m.steps,3),s.failures); for _,turn in ipairs(s.turns) do network[#network+1]=fmt('    TURN %s weight %d vehicles %d',turn.target.id,turn.weight,turn.vehicles) end end end
    end
    for _,s in ipairs(m.stops) do network[#network+1]=fmt('STOP %s cell %d dwell %d buses %d',s.segment.id,s.cell,s.dwell,s.buses) end
    for _,i in ipairs(m.incidents) do local active=i.active_start>0 and fmt('%d-%d',i.active_start,i.active_end) or 'none'; network[#network+1]=fmt('INCIDENT %s lane %d cell %d planned %d-%d active %s',i.segment.id,i.lane,i.cell,i.start,i.finish,active) end
    local on_road,queued=0,0
    for k,total in ipairs(m.totals) do on_road=on_road+total.inserted-total.exited; queued=queued+total.arrived-total.inserted; timeline[#timeline+1]=fmt('%d,%d,%d,%d,%d,%d,%s',k,total.arrived,total.inserted,total.exited,on_road,queued,dec(total.speed,total.steps,2)) end
    for _,number in ipairs(m.tracks) do
        local v=m.vehicles[number]
        if not v then tracks[#tracks+1]=fmt('VEHICLE %d none',number)
        else local path=#v.route>0 and route_text(v.route,' ') or '-'; tracks[#tracks+1]=fmt('VEHICLE %d class %s source %s arrival %d inserted %s exited %s sink %s',number,v.class.name,v.source.node,v.arrival,v.inserted>0 and tostring(v.inserted) or '-',v.exited>0 and tostring(v.exited) or '-',v.sink or '-'); tracks[#tracks+1]='ROUTE '..path; extend(tracks,v.trajectory) end
    end
    for k,r in ipairs(m.rings) do for _,count in ipairs(r.counts) do local total=ring_experiment(m,r,count); fundamental[#fundamental+1]=fmt('%d,%d,%s,%s,%s',k,count,dec(count,r.length,4),dec(total,r.length*r.measure,4),dec(total,count*r.measure,3)) end end
    os.execute('mkdir -p output')
    for name,lines in pairs(files) do local file=assert(io.open('output/'..name,'w')); if #lines>0 then file:write(table.concat(lines,'\n'),'\n') end; file:close() end
end
local simulation=read_simulation()
run(simulation)
output(simulation)
