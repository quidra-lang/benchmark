clamped(image,x,y) = image[clamp(y+1,1,size(image,1)),clamp(x+1,1,size(image,2))]
function smoothing(image,params)
    height,width = size(image)
    ks,divisor = params["gauss_size"][1],params["gauss_divisor"][1]
    half,weights = ks÷2,params["gauss_kernel"]
    output = zeros(Int,height,width)
    for y in 0:height-1,x in 0:width-1
        total = 0
        for j in 0:ks-1,i in 0:ks-1
            total += weights[j*ks+i+1]*clamped(image,x+i-half,y+j-half)
        end
        output[y+1,x+1] = fld(total,divisor)
    end
    output
end
function gradient(image)
    height,width = size(image)
    gx,gy,magnitude = zeros(Int,height,width),zeros(Int,height,width),zeros(Int,height,width)
    for y in 0:height-1,x in 0:width-1
        q1,q2,q3 = clamped(image,x-1,y-1),clamped(image,x,y-1),clamped(image,x+1,y-1)
        q4,q6 = clamped(image,x-1,y),clamped(image,x+1,y)
        q7,q8,q9 = clamped(image,x-1,y+1),clamped(image,x,y+1),clamped(image,x+1,y+1)
        dx,dy = (q3+2q6+q9)-(q1+2q4+q7),(q7+2q8+q9)-(q1+2q2+q3)
        gx[y+1,x+1],gy[y+1,x+1],magnitude[y+1,x+1] = dx,dy,abs(dx)+abs(dy)
    end
    gx,gy,magnitude
end
