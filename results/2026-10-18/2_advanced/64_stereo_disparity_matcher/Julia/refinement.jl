hundredths(value) = string(value÷100,".",lpad(value%100,2,'0'))
two_decimals(a,b=1) = hundredths((200a+b)÷(2b))
depth_hundredths(d,focal,baseline) = (200focal*baseline+d)÷(2d)
function subpixel(d,costs,dmin,dmax,focal,baseline)
    i,a,b = d-dmin+1,0,1
    if dmin<d<dmax && costs[i-1]>costs[i] && costs[i+1]>=costs[i]
        a = costs[i-1]-costs[i+1]
        b = 2*(costs[i-1]-2costs[i]+costs[i+1])
    end
    rounded = (200*(d*b+a)+b)÷(2b)
    hundredths(rounded),two_decimals(100focal*baseline,rounded)
end
