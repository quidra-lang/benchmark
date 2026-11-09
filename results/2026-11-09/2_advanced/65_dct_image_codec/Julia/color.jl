clamp_byte(value) = clamp(value,0,255)
function to_ycbcr(pixel)
    r,g,b = pixel
    (
        fld(19595r+38470g+7471b+32768,65536),
        fld(-11059r-21709g+32768b+8421375,65536),
        fld(32768r-27439g-5329b+8421375,65536)
    )
end
function to_rgb(y,cb,cr)
    (
        clamp_byte(y+fld(91881*(cr-128)+32768,65536)),
        clamp_byte(y+fld(-22554*(cb-128)-46802*(cr-128)+32768,65536)),
        clamp_byte(y+fld(116130*(cb-128)+32768,65536))
    )
end
function split_planes(image)
    planes = [zeros(Int,size(image)) for _ in 1:3]
    for y in axes(image,1),x in axes(image,2)
        for (k,value) in enumerate(to_ycbcr(image[y,x]))
            planes[k][y,x] = value
        end
    end
    planes
end
function component_planes(planes,factors,mx,my)
    height,width = size(planes[1])
    hmax,vmax = maximum(first,factors),maximum(last,factors)
    result = Matrix{Int}[]
    for (plane,(h,v)) in zip(planes,factors)
        fx,fy = hmax÷h,vmax÷v
        component = zeros(Int,8v*my,8h*mx)
        for y in 0:size(component,1)-1,x in 0:size(component,2)-1
            total = 0
            for j in 0:fy-1,i in 0:fx-1
                total += plane[min(fy*y+j,height-1)+1,min(fx*x+i,width-1)+1]
            end
            component[y+1,x+1] = total÷(fx*fy)
        end
        push!(result,component)
    end
    result
end
function upsample(planes,factors,width,height)
    hmax,vmax = maximum(first,factors),maximum(last,factors)
    [[
        plane[y*v÷vmax+1,x*h÷hmax+1] for y in 0:height-1,
        x in 0:width-1
    ] for (plane,(h,v)) in zip(planes,factors)]
end
combine_rgb(planes) = [
    to_rgb(planes[1][y,x],planes[2][y,x],planes[3][y,x]) for y in axes(planes[1],1),
    x in axes(planes[1],2)
]
