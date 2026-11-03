clamped(image,width,height,x,y) = image[clamp(y,0,height-1)*width+clamp(x,0,width-1)+1]
function box_sum(image,width,height,window)
    radius = window÷2
    padded_width,padded_height = width+2radius,height+2radius
    integral = zeros(Int,padded_height+1,padded_width+1)
    for y in 0:padded_height-1
        row_sum = 0
        for x in 0:padded_width-1
            row_sum += clamped(image,width,height,x-radius,y-radius)
            integral[y+2,x+2] = integral[y+1,x+2]+row_sum
        end
    end
    [integral[
        y+window+1,
        x+window+1
    ]-integral[y+1,x+window+1]-integral[y+window+1,x+1]+integral[y+1,x+1] for y in 0:height-1 for x in 0:width-1]
end
function census(image,width,height)
    result = Int[]
    for y in 0:height-1,x in 0:width-1
        code,center = 0,image[y*width+x+1]
        for dy in -2:2,dx in -2:2
            dx==0 && dy==0 && continue
            code = 2code+Int(clamped(image,width,height,x+dx,y+dy)<center)
        end
        push!(result,code)
    end
    result
end
function texture(image,width,height,window)
    gradient = [abs(clamped(image,width,height,x+1,y)-clamped(
        image,
        width,
        height,
        x-1,
        y
    )) for y in 0:height-1 for x in 0:width-1]
    box_sum(gradient,width,height,window)
end
function cost_volume(left,right,cl,cr,width,height,kind,window,dmin,dmax)
    volume = zeros(Int,length(left),dmax-dmin+1)
    for d in dmin:dmax
        pixels = Int[]
        for y in 0:height-1,x in 0:width-1
            p,q = y*width+x+1,y*width+max(x-d,0)+1
            difference = left[p]-right[q]
            value = kind=="census" ? count_ones(xor(
                cl[p],
                cr[q]
            )) : kind=="sad" ? abs(difference) : difference*difference
            push!(pixels,value)
        end
        volume[:,d-dmin+1] = box_sum(pixels,width,height,window)
    end
    volume
end
