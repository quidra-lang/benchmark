function base_color(material,point)
    if !isnothing(material.checker)
        color,size = material.checker
        isodd(sum(fld(value,size) for value in point)) && return color
    end
    material.color
end
function phong(material,normal,light,view,ndl,intensity,factor)
    effective = mul(intensity,factor)
    diffuse = mul(mul(material.kd,ndl),effective)
    rv = dot(sub(sc(normal,2ndl),light),view)
    specular = 0
    if rv>0
        power = S
        for _ in 1:material.n
            power = mul(power,rv)
        end
        specular = mul(mul(material.ks,power),effective)
    end
    diffuse,specular
end
reflected(direction,normal) = norm(sub(direction,sc(normal,2dot(direction,normal))))
function refraction(material,direction,normal,front)
    wr,wt = material.kr,material.kt
    wt==0 && return (wr,wt,nothing,false)
    eta = front ? fld(S*S,material.ior) : material.ior
    cosine = -dot(direction,normal)
    discriminant = S*S-fld(mul(eta,eta)*(S*S-cosine*cosine),S)
    discriminant<0 && return (wr+wt,0,nothing,true)
    transmitted = norm(add(sc(direction,eta),sc(normal,mul(eta,cosine)-isqrt(discriminant))))
    r0 = fld((material.ior-S)*S,material.ior+S)
    reflectance = mul(r0,r0)
    x,power = S-min(cosine,S),S
    for _ in 1:5
        power = mul(power,x)
    end
    fresnel = reflectance+mul(S-reflectance,power)
    transfer = mul(material.kt,fresnel)
    wr+transfer,wt-transfer,transmitted,false
end
mix(weighted_colors...) = ntuple(a->sum(fld(color[a]*weight,S) for (color,weight) in weighted_colors),3)
