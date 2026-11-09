local Canvas=require('canvas')
local M={}
local function code(p,c)
    local value=0; if p.x<c.x0 then value=value|1 end; if p.x>c.x1 then value=value|2 end; if p.y<c.y0 then value=value|4 end; if p.y>c.y1 then value=value|8 end; return value
end
function M.segment(first,last,c)
    while true do
        local a,b=code(first,c),code(last,c)
        if a==0 and b==0 then return first,last end
        if (a&b)~=0 then return nil end
        local outside,other,region=first,last,a
        if a==0 then outside,other,region=last,first,b end
        local p
        if (region&4)~=0 then p={x=outside.x+Canvas.round((other.x-outside.x)*(c.y0-outside.y),other.y-outside.y),y=c.y0}
        elseif (region&8)~=0 then p={x=outside.x+Canvas.round((other.x-outside.x)*(c.y1-outside.y),other.y-outside.y),y=c.y1}
        elseif (region&2)~=0 then p={x=c.x1,y=outside.y+Canvas.round((other.y-outside.y)*(c.x1-outside.x),other.x-outside.x)}
        else p={x=c.x0,y=outside.y+Canvas.round((other.y-outside.y)*(c.x0-outside.x),other.x-outside.x)} end
        if a~=0 then first=p else last=p end
    end
end
function M.polygon(vertices,c)
    for boundary,limit in ipairs({c.x0,c.x1+1,c.y0,c.y1+1}) do
        local axis=boundary<=2 and 'x' or 'y'; local lower=boundary%2==1
        local function inside(p) if lower then return p[axis]>=limit else return p[axis]<=limit end end
        local function cross(s,e) if axis=='x' then return {x=limit,y=s.y+Canvas.round((limit-s.x)*(e.y-s.y),e.x-s.x)} else return {x=s.x+Canvas.round((limit-s.y)*(e.x-s.x),e.y-s.y),y=limit} end end
        local output={}
        for i,last in ipairs(vertices) do local first=vertices[(i-2)%#vertices+1]; if inside(last) then if not inside(first) then output[#output+1]=cross(first,last) end; output[#output+1]=last elseif inside(first) then output[#output+1]=cross(first,last) end end
        vertices=output
    end
    return vertices
end
return M
