local M = {}
local Segment = {}
Segment.__index = Segment
function M.segment(id, from, to, length, lanes, limit)
    local s = setmetatable({id=id, from=from, to=to, length=length, lanes=lanes, limit=limit, cells={}, turns={}, entered=0, vehicle_sum=0, speed_sum=0, max_vehicles=0, green_count=0, queue_sum=0, max_queue=0, failures=0, passed=0, blocked=0, changes={0,0,0}}, Segment)
    for lane=1,lanes do s.cells[lane]={}; for x=1,length do s.cells[lane][x]=0 end end
    return s
end
function Segment:free(lane, x, cap)
    local n=0
    while n<cap and x+n+1<self.length and self.cells[lane][x+n+2]==0 do n=n+1 end
    return n
end
function Segment:first(lane)
    for x,id in ipairs(self.cells[lane]) do if id~=0 then return x-1 end end
    return self.length
end
function Segment:safe(lane, x)
    for i=math.max(0,x-self.limit),x do if self.cells[lane][i+1]~=0 then return false end end
    return true
end
function Segment:cells_text(lane, vehicles)
    local row={}
    for _,id in ipairs(self.cells[lane]) do row[#row+1]=id==0 and '.' or id<0 and '#' or tostring(vehicles[id].speed) end
    return table.concat(row)
end
function M.incident(segment, lane, cell, start, finish)
    return {segment=segment,lane=lane,cell=cell,start=start,finish=finish,state='planned',active_start=0,active_end=0}
end
function M.update(incident, t)
    local i,s,event=incident,incident.segment,nil
    if i.state=='active' and t>i.finish then i.state='cleared'; s.cells[i.lane][i.cell+1]=0; event='INCIDENT_END'
    elseif i.state=='planned' and t>i.finish then i.state='cancelled'
    elseif i.state=='planned' and t>=i.start and s.cells[i.lane][i.cell+1]==0 then i.state='active'; s.cells[i.lane][i.cell+1]=-1; i.active_start=t; event='INCIDENT_START' end
    if i.state=='active' then i.active_end=t end
    if event then return string.format('%04d %s %s lane %d cell %d',t,event,s.id,i.lane,i.cell) end
end
return M
