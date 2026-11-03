module Plot
export limitsband, cusumband, widthband, standardband
newband() = fill('.',61)
place!(band,position,symbol) = (band[Int(clamp(position,0,60))+1] = symbol)
function framed(center)
    band = newband()
    place!(band,0,':')
    place!(band,60,':')
    place!(band,center,'|')
    band
end
function limitsband(l,v,signalled)
    span = l.ucl-l.lcl
    band = framed(floor(60*((l.cl-l.lcl)/span)+0.5))
    place!(band,floor(60*((v-l.lcl)/span)+0.5),signalled ? '*' : 'o')
    join(band)
end
function cusumband(upper,lower,h,up,down)
    band = framed(30)
    lower > 0 && place!(band,30-min(30,floor(30*(lower/h)+0.5)),down ? '*' : '-')
    upper > 0 && place!(band,30+min(30,floor(30*(upper/h)+0.5)),up ? '*' : '+')
    join(band)
end
function widthband(scale,width,value,center,signalled)
    band = newband()
    edge = min(30,floor(30*(width/scale)+0.5))
    place!(band,30,'|')
    place!(band,30-edge,':')
    place!(band,30+edge,':')
    place!(band,30+floor(30*((value-center)/scale)+0.5),signalled ? '*' : 'o')
    join(band)
end
function standardband(z,ok)
    band = framed(30)
    place!(band,30+floor(10*z+0.5),ok ? 'o' : '*')
    join(band)
end
end
