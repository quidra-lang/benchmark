base_color =: 4 : 0
    'material checker size' =. x
    if. size>0 do.
        parity =. +/y floor_div size
        if. 2|parity do.
            checker return.
        end.
    end.
    3{.material
)
phong =: 3 : 0
    'material normal light view ndl intensity factor' =. y
    effective =. intensity fixed_mul factor
    diffuse =. ((3{material)fixed_mul ndl)fixed_mul effective
    reflected_light =. (normal vscale 2*ndl)-light
    rv =. reflected_light vdot view
    specular =. 0x
    if. rv>0 do.
        power =. S
        for_j. i.5{material do.
            power =. power fixed_mul rv
        end.
        specular =. ((4{material)fixed_mul power)fixed_mul effective
    end.
    diffuse,specular
)
reflected =: 4 : 'vnorm x-y vscale 2*x vdot y'
refraction =: 3 : 0
    'material direction normal front' =. y
    wr =. 6{material
    wt =. 7{material
    if. wt=0 do.
        (<wr),(<wt),(<i.0x),<0 return.
    end.
    eta =. 8{material
    if. front do.
        eta =. (S*S)floor_div eta
    end.
    cosine =. -direction vdot normal
    discriminant =. (S*S)-((eta fixed_mul eta)*((S*S)-cosine*cosine))floor_div S
    if. discriminant<0 do.
        (<wr+wt),(<0x),(<i.0x),<1 return.
    end.
    transmitted =. vnorm (direction vscale eta)+normal vscale (eta fixed_mul cosine)-isqrt discriminant
    r0 =. (((8{material)-S)*S)floor_div (8{material)+S
    reflectance =. r0 fixed_mul r0
    x =. S-cosine<.S
    power =. S
    for_j. i.5 do.
        power =. power fixed_mul x
    end.
    fresnel =. reflectance+(S-reflectance)fixed_mul power
    transfer =. (7{material)fixed_mul fresnel
    (<wr+transfer),(<wt-transfer),(<transmitted),<0
)
mix =: 4 : 0
    result =. 3$0x
    for_j. i.#x do.
        result =. result+((j{::x)*j{y)floor_div S
    end.
    result
)
