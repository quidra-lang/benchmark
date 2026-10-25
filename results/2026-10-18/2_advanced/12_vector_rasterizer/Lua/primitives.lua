local Canvas=require('canvas')
local M={}
function M.add(pixels,x,y) pixels[x..','..y]={x=x,y=y} end
function M.key(p) return p.x..','..p.y end
function M.count(pixels) local count=0; for _ in pairs(pixels) do count=count+1 end; return count end
function M.bresenham(first,last)
    local x,y=first.x,first.y; local dx,dy=math.abs(last.x-x),-math.abs(last.y-y); local sx,sy=x<last.x and 1 or -1,y<last.y and 1 or -1; local error_=dx+dy; local points={}
    while true do points[#points+1]={x=x,y=y}; if x==last.x and y==last.y then return points end; local doubled=2*error_; if doubled>=dy then error_=error_+dy; x=x+sx end; if doubled<=dx then error_=error_+dx; y=y+sy end end
end
function M.square(p,width)
    local low=-((width-1)//2); local points={}
    for j=low,low+width-1 do for i=low,low+width-1 do points[#points+1]={x=p.x+i,y=p.y+j} end end
    return points
end
function M.circle(radius)
    local points={}; local a,b,error_=radius,0,1-radius
    while a>=b do
        for _,p in ipairs({{a,b},{b,a},{-b,a},{-a,b},{-a,-b},{-b,-a},{b,-a},{a,-b}}) do M.add(points,p[1],p[2]) end
        b=b+1
        if error_<0 then error_=error_+2*b+1 else a=a-1; error_=error_+2*(b-a)+1 end
    end
    return points
end
function M.ellipse(rx,ry)
    local points={}; M.add(points,0,ry); M.add(points,0,-ry); local rx2,ry2=rx*rx,ry*ry; local x,y=0,ry
    local function quadrants() M.add(points,x,y); M.add(points,-x,y); M.add(points,x,-y); M.add(points,-x,-y) end
    while ry2*x<rx2*y do local decision=4*ry2*(x+1)*(x+1)+rx2*(2*y-1)*(2*y-1)-4*rx2*ry2; x=x+1; if decision>=0 then y=y-1 end; quadrants() end
    while y>0 do local decision=ry2*(2*x+1)*(2*x+1)+4*rx2*(y-1)*(y-1)-4*rx2*ry2; y=y-1; if decision<=0 then x=x+1 end; quadrants() end
    return points
end
function M.bezier(controls,segments)
    local degree=#controls-1; local scale=segments*segments; if degree==3 then scale=scale*segments end; local points={}
    for i=0,segments do
        local rest=segments-i; local weights={rest*rest,2*i*rest,i*i}; if degree==3 then weights={rest*rest*rest,3*i*rest*rest,3*i*i*rest,i*i*i} end
        local x,y=0,0; for k,p in ipairs(controls) do x=x+weights[k]*p.x; y=y+weights[k]*p.y end
        points[#points+1]={x=Canvas.round(x,scale),y=Canvas.round(y,scale)}
    end
    return points
end
return M
