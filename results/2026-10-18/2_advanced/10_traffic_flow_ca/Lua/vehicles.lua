local M = {}
local Vehicle = {}
Vehicle.__index = Vehicle
function M.class(name, vmax, weight, overtake, stops) return {name=name,vmax=vmax,weight=weight,overtake=overtake,stops=stops} end
function M.new(number, class, source, arrival)
    return setmetatable({number=number,class=class,source=source,arrival=arrival,inserted=0,exited=0,lane=0,cell=0,speed=0,route={},steps=0,distance=0,stopped_steps=0,stop_count=0,lane_changes=0,dwell=0,completed={},trajectory={}},Vehicle)
end
function Vehicle:maximum() return math.min(self.class.vmax,self.segment.limit) end
function Vehicle:place(segment, lane, cell)
    if self.segment then self.segment.cells[self.lane][self.cell+1]=0 end
    segment.cells[lane][cell+1]=self.number; self.segment=segment; self.lane=lane; self.cell=cell
end
function Vehicle:leave() self.segment.cells[self.lane][self.cell+1]=0; self.segment=nil end
function Vehicle:heading()
    local s=self.segment
    return s~=nil and self.class.stops and s.stop~=nil and not self.completed[s] and self.cell<=s.stop.cell
end
function Vehicle:travel() return self.exited-self.inserted+1 end
function M.slowdown(speed, previous, value, p, p0)
    local probability=previous==0 and p0 or p
    if speed>0 and value%1000<probability then speed=speed-1 end
    return speed
end
return M
