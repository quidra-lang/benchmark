local Canvas=require('canvas')
local Primitives=require('primitives')
local M={}
function M.polygons(sequences,rule,c)
    local edges={}
    for _,vertices in ipairs(sequences) do for i,first in ipairs(vertices) do local last=vertices[i%#vertices+1]; if first.y~=last.y then edges[#edges+1]={first,last} end end end
    local pixels={}
    for y=c.y0,c.y1 do
        local crossings={}
        for _,edge in ipairs(edges) do
            local a,b=edge[1],edge[2]
            if math.min(a.y,b.y)<=y and y<math.max(a.y,b.y) then
                local d=b.y-a.y; local n=2*a.x*d+(2*y+1-2*a.y)*(b.x-a.x); local direction=1
                if d<0 then n,d=-n,-d; direction=-1 end
                crossings[#crossings+1]={x=(n-d)//(2*d)+1,direction=direction}
            end
        end
        table.sort(crossings,function(a,b) if a.x~=b.x then return a.x<b.x end; return a.direction<b.direction end)
        local count,winding,index=0,0,1
        for x=c.x0,c.x1 do while index<=#crossings and crossings[index].x<=x do count=count+1; winding=winding+crossings[index].direction; index=index+1 end; if rule=='evenodd' and count%2==1 or rule=='nonzero' and winding~=0 then Primitives.add(pixels,x,y) end end
    end
    return pixels
end
function M.shape(center,points,c)
    local extents={}; for _,p in pairs(points) do extents[p.y]=math.max(extents[p.y] or 0,math.abs(p.x)) end
    local pixels={}
    for dy,extent in pairs(extents) do local y=center.y+dy; if c.y0<=y and y<=c.y1 then for x=math.max(c.x0,center.x-extent),math.min(c.x1,center.x+extent) do Primitives.add(pixels,x,y) end end end
    return pixels
end
function M.flood(layer,seed,c)
    local target=layer:at(seed)
    local function same(p) local pixel=layer:at(p); if not target then return pixel==nil end; if not pixel then return false end; for k=1,4 do if pixel.color[k]~=target.color[k] then return false end end; return true end
    local pixels={}; Primitives.add(pixels,seed.x,seed.y); local pending={seed}; local head=1
    while head<=#pending do local p=pending[head]; head=head+1; for _,next_ in ipairs({{x=p.x+1,y=p.y},{x=p.x-1,y=p.y},{x=p.x,y=p.y+1},{x=p.x,y=p.y-1}}) do if Canvas.contains(c,next_) and not pixels[Primitives.key(next_)] and same(next_) then Primitives.add(pixels,next_.x,next_.y); pending[#pending+1]=next_ end end end
    return pixels
end
return M
