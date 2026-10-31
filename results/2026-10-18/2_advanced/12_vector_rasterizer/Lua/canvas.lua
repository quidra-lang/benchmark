local M={}
function M.round(n,d) if d<0 then n,d=-n,-d end; return (2*n+d)//(2*d) end
function M.empty(r) return r.x0>r.x1 or r.y0>r.y1 end
function M.contains(r,p) return r.x0<=p.x and p.x<=r.x1 and r.y0<=p.y and p.y<=r.y1 end
function M.intersection(a,b) return {x0=math.max(a.x0,b.x0),y0=math.max(a.y0,b.y0),x1=math.min(a.x1,b.x1),y1=math.min(a.y1,b.y1)} end
local Layer={}
Layer.__index=Layer
function M.layer(width,height,opacity,mode) return setmetatable({width=width,height=height,opacity=opacity,mode=mode,pixels={}},Layer) end
function Layer:at(p) return self.pixels[p.y*self.width+p.x+1] end
function Layer:paint(p,color,line) self.pixels[p.y*self.width+p.x+1]={color=color,line=line} end
function Layer:erase(p) self.pixels[p.y*self.width+p.x+1]=nil end
function Layer:alpha(p) local pixel=self:at(p); return pixel and M.round(pixel.color[4]*self.opacity,255) or 0 end
function M.composite(layers,background,width,height)
    local image={}
    for y=0,height-1 do for x=0,width-1 do
        local p={x=x,y=y}; local value={background[1],background[2],background[3]}
        for _,layer in ipairs(layers) do
            local pixel=layer:at(p)
            if pixel then
                local alpha=M.round(pixel.color[4]*layer.opacity,255)
                for k=1,3 do local source=pixel.color[k]; if layer.mode=='multiply' then source=M.round(source*value[k],255) elseif layer.mode=='screen' then source=255-M.round((255-source)*(255-value[k]),255) end; value[k]=M.round(alpha*source+(255-alpha)*value[k],255) end
            end
        end
        image[y*width+x+1]=value
    end end
    return image
end
return M
