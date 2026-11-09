local M = {}
local Junction = {}
Junction.__index = Junction
function M.new(node, offset, tokens)
    local j=setmetatable({node=node,offset=offset,cycle=0,phases={}},Junction)
    for _,token in ipairs(tokens) do
        local duration,green=token:match('^(%d+):(.*)$'); local p={duration=tonumber(duration),token=green,greens={}}
        if green~='-' then for id in green:gmatch('[^,]+') do p.greens[id]=true end end
        j.phases[#j.phases+1]=p; j.cycle=j.cycle+p.duration
    end
    return j
end
function Junction:green(id, t)
    if #self.phases==0 then return true end
    local tau=(t-1+self.offset)%self.cycle
    for _,p in ipairs(self.phases) do if tau<p.duration then return p.greens[id]==true end; tau=tau-p.duration end
end
function Junction:lines()
    if #self.phases==0 then return {'JUNCTION '..self.node..' unsignalized'} end
    local lines={string.format('JUNCTION %s signal cycle %d offset %d',self.node,self.cycle,self.offset)}; local start=0
    for k,p in ipairs(self.phases) do lines[#lines+1]=string.format('  PHASE %d %d-%d %s',k,start,start+p.duration-1,p.token); start=start+p.duration end
    return lines
end
return M
