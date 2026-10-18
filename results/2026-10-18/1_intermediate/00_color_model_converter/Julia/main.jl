using Printf

const BUILTIN_NAMES = split("black maroon green olive navy purple teal silver gray red lime yellow blue magenta cyan white orange pink brown gold coral salmon violet indigo")
const BUILTIN_HEX = split("000000 800000 008000 808000 000080 800080 008080 C0C0C0 808080 FF0000 00FF00 FFFF00 0000FF FF00FF 00FFFF FFFFFF FFA500 FFC0CB A52A2A FFD700 FF7F50 FA8072 EE82EE 4B0082")
const BUILTIN_COLORS = [[parse(Int,text[i:i+1];base=16) for i in (1,3,5)] for text in BUILTIN_HEX]
const SIGNATURES = Dict(
    "PARSE"=>"c",
    "DEFINE"=>"name c",
    "UNDEFINE"=>"name",
    "LIST"=>"",
    "HSL"=>"c",
    "HSV"=>"c",
    "HWB"=>"c",
    "CMYK"=>"c",
    "YCBCR"=>"c",
    "YIQ"=>"c",
    "FROMHSL"=>"0:359 0:100 0:100",
    "FROMHSV"=>"0:359 0:100 0:100",
    "FROMHWB"=>"0:359 0:100 0:100",
    "FROMCMYK"=>"0:100 0:100 0:100 0:100",
    "FROMYCBCR"=>"0:255 0:255 0:255",
    "FROMYIQ"=>"0:255 -255:255 -255:255",
    "RGB565"=>"c",
    "FROM565"=>"code",
    "ANSI"=>"c",
    "FROMANSI"=>"0:255",
    "WEBSAFE"=>"c",
    "GRAY"=>"c gray",
    "INVERT"=>"c",
    "MIX"=>"c c 0:100",
    "MIXHSL"=>"c c 0:100",
    "GRADIENT"=>"c c 2:16",
    "TINTS"=>"c 1:10",
    "SHADES"=>"c 1:10",
    "TONES"=>"c 1:10",
    "BLEND"=>"blend c c",
    "ALPHA"=>"c 0:100 c 0:100",
    "SIMULATE"=>"c simulation",
    "ROTATE"=>"c -720:720",
    "COMPLEMENT"=>"c",
    "TRIADIC"=>"c",
    "TETRADIC"=>"c",
    "SPLITCOMP"=>"c",
    "ANALOGOUS"=>"c 1:6 1:60",
    "LIGHTEN"=>"c 0:100",
    "DARKEN"=>"c 0:100",
    "SATURATE"=>"c 0:100",
    "DESATURATE"=>"c 0:100",
    "NEAREST"=>"c",
    "DISTANCE"=>"c c",
    "CONTRAST"=>"c c",
    "ACCESSIBLE"=>"c c",
    "DESCRIBE"=>"c",
    "RANDOM"=>"1:999999999 1:16")
const KEYWORDS = Dict(
    "gray"=>split("LUMA AVERAGE LIGHTNESS HSP"),
    "blend"=>split("MULTIPLY SCREEN OVERLAY HARDLIGHT SOFTLIGHT DARKEN LIGHTEN DIFFERENCE EXCLUSION ADD SUBTRACT COLORDODGE COLORBURN HUE SATURATION COLOR LUMINOSITY"),
    "simulation"=>split("PROTANOPIA DEUTERANOPIA TRITANOPIA ACHROMATOPSIA"))

require_valid(condition) = condition || throw(ArgumentError("INVALID"))
round_ratio(n,d) = fld(2*n+d,2*d)
away_ratio(n,d) = n < 0 ? -round_ratio(-n,d) : round_ratio(n,d)
byte_clamp(x) = min(255,max(0,x))
hex_color(c) = @sprintf("#%02X%02X%02X",c[1],c[2],c[3])
color_sequence(colors) = join(hex_color.(colors)," ")
color_distance(a,b) = sum((a[i]-b[i])^2 for i in 1:3)

function integer_arg(text,low,high)
    require_valid(occursin(r"^-?[0-9]{1,9}$",text))
    value = parse(Int,text)
    require_valid(low <= value <= high)
    return value
end

function parse_color(text,registered)
    if occursin(r"^#[0-9A-Fa-f]{6}$",text)
        return [parse(Int,text[i:i+1];base=16) for i in (2,4,6)]
    elseif occursin(r"^#[0-9A-Fa-f]{3}$",text)
        return [17*parse(Int,string(text[i]);base=16) for i in 2:4]
    end
    matched = match(r"^rgb\(([0-9]{1,3}),([0-9]{1,3}),([0-9]{1,3})\)$",text)
    if matched !== nothing
        color = parse.(Int,matched.captures)
        require_valid(all(x <= 255 for x in color))
        return color
    end
    index = findfirst(==(text),BUILTIN_NAMES)
    index !== nothing && return copy(BUILTIN_COLORS[index])
    require_valid(haskey(registered,text))
    return copy(registered[text])
end

function typed_arg(text,kind,registered)
    kind == "c" && return parse_color(text,registered)
    if kind == "name"
        require_valid(occursin(r"^[a-z]{1,12}$",text))
        return String(text)
    elseif kind == "code"
        require_valid(occursin(r"^0x[0-9a-fA-F]{4}$",text))
        return parse(Int,text[3:end];base=16)
    elseif haskey(KEYWORDS,kind)
        require_valid(text in KEYWORDS[kind])
        return String(text)
    end
    low,high = parse.(Int,split(kind,':'))
    return integer_arg(text,low,high)
end

function hue(c)
    r,g,b = c
    high,low = maximum(c),minimum(c)
    delta = high-low
    delta == 0 && return 0
    if high == r
        numerator = 60*(g-b)
        numerator < 0 && (numerator += 360*delta)
    elseif high == g
        numerator = 60*(b-r)+120*delta
    else
        numerator = 60*(r-g)+240*delta
    end
    return mod(round_ratio(numerator,delta),360)
end

function hsl(c)
    high,low = maximum(c),minimum(c)
    delta = high-low
    saturation = delta == 0 ? 0 : round_ratio(100*delta,255-abs(high+low-255))
    return [hue(c),saturation,round_ratio(100*(high+low),510)]
end

function base60(h)
    sector,fraction = divrem(h,60)
    x = iseven(sector) ? fraction : 60-fraction
    return [[60,x,0],[x,60,0],[0,60,x],[0,x,60],[x,0,60],[60,0,x]][sector+1]
end

function from_hsl(h,s,l)
    chroma = (100-abs(2*l-100))*s
    offset = 6000*l-30*chroma
    return [round_ratio(255*(u*chroma+offset),600000) for u in base60(h)]
end

function model_values(model,c)
    r,g,b = c
    high,low = maximum(c),minimum(c)
    if model == "HSL"
        return hsl(c)
    elseif model == "HSV"
        return [hue(c),high == 0 ? 0 : round_ratio(100*(high-low),high),round_ratio(100*high,255)]
    elseif model == "HWB"
        return [hue(c),round_ratio(100*low,255),round_ratio(100*(255-high),255)]
    elseif model == "CMYK"
        high == 0 && return [0,0,0,100]
        return vcat([round_ratio(100*(high-x),high) for x in c],round_ratio(100*(255-high),255))
    elseif model == "YCBCR"
        return byte_clamp.([
            round_ratio(299*r+587*g+114*b,1000),
            round_ratio(128000-169*r-331*g+500*b,1000),
            round_ratio(128000+500*r-419*g-81*b,1000)])
    end
    return [
        round_ratio(299*r+587*g+114*b,1000),
        round_ratio(596*r-274*g-322*b,1000),
        round_ratio(211*r-523*g+312*b,1000)]
end

function model_text(model,c)
    values = model_values(model,c)
    if model in ("HSL","HSV","HWB")
        return string(lowercase(model),'(',values[1],',',values[2],"%,",values[3],"%)")
    elseif model == "CMYK"
        return string("cmyk(",join([string(value,'%') for value in values],","),')')
    end
    return string(lowercase(model),'(',join(values,","),')')
end

function ansi_color(number)
    number < 16 && return copy(BUILTIN_COLORS[number+1])
    if number >= 232
        return fill(8+10*(number-232),3)
    end
    value = number-16
    levels = [0,95,135,175,215,255]
    return levels[[div(value,36)+1,div(value,6)%6+1,value%6+1]]
end

function root_ratio(n,d)
    low,high = 0,1
    while d*high*high <= n
        high *= 2
    end
    while high-low > 1
        middle = div(low+high,2)
        if d*middle*middle <= n
            low = middle
        else
            high = middle
        end
    end
    return low
end

function nearest_index(color,colors)
    best = 1
    for i in 2:length(colors)
        if color_distance(color,colors[i]) < color_distance(color,colors[best])
            best = i
        end
    end
    return best
end

function contrast(a,b)
    luminance(c) = 2126*c[1]^2+7152*c[2]^2+722*c[3]^2
    y1,y2 = luminance(a),luminance(b)
    high,low = max(y1,y2)+32512500,min(y1,y2)+32512500
    if high >= 7*low
        verdict = "AAA"
    elseif 2*high >= 9*low
        verdict = "AA"
    else
        verdict = "FAIL"
    end
    return round_ratio(100*high,low),verdict
end

function contrast_text(a,b)
    ratio,verdict = contrast(a,b)
    return @sprintf("%d.%02d %s",div(ratio,100),ratio%100,verdict)
end

gradient(a,b,n) = [[a[j]+away_ratio((b[j]-a[j])*i,n-1) for j in 1:3] for i in 0:n-1]
mean_color(colors) = [round_ratio(sum(c[j] for c in colors),length(colors)) for j in 1:3]
widths(colors) = [maximum(c[j] for c in colors)-minimum(c[j] for c in colors) for j in 1:3]

function palette(colors,k)
    boxes = [copy(colors)]
    while length(boxes) < k
        selected,best_width = 0,-1
        for i in eachindex(boxes)
            if length(boxes[i]) >= 2
                width = maximum(widths(boxes[i]))
                if width > best_width
                    selected,best_width = i,width
                end
            end
        end
        box = boxes[selected]
        axis = argmax(widths(box))
        indices = sortperm(1:length(box);by=i -> (box[i][axis],i))
        ordered = box[indices]
        middle = div(length(box),2)
        splice!(boxes,selected:selected,[ordered[1:middle],ordered[middle+1:end]])
    end
    return boxes
end

function blend_component(mode,x,y)
    multiply = div(x*y,255)
    screen = 255-div((255-x)*(255-y),255)
    if mode == "MULTIPLY"
        return multiply
    elseif mode == "SCREEN"
        return screen
    elseif mode == "OVERLAY" || mode == "HARDLIGHT"
        lower = mode == "OVERLAY" ? x < 128 : y < 128
        return lower ? div(2*x*y,255) : 255-div(2*(255-x)*(255-y),255)
    elseif mode == "SOFTLIGHT"
        return div((255-x)*multiply+x*screen,255)
    elseif mode == "DARKEN"
        return min(x,y)
    elseif mode == "LIGHTEN"
        return max(x,y)
    elseif mode == "DIFFERENCE"
        return abs(x-y)
    elseif mode == "EXCLUSION"
        return x+y-div(2*x*y,255)
    elseif mode == "ADD"
        return min(255,x+y)
    elseif mode == "SUBTRACT"
        return max(0,x-y)
    elseif mode == "COLORDODGE"
        return y == 255 ? 255 : min(255,div(255*x,255-y))
    end
    return y == 0 ? 0 : max(0,255-div(255*(255-x),y))
end

function execute(command,raw,registered,registration_order)
    if command in ("PALETTE","KMEANS","BEST","SORT","DITHER")
        if command in ("PALETTE","KMEANS")
            require_valid(2 <= length(raw) <= 33)
            k = integer_arg(raw[1],1,length(raw)-1)
            args = Any[k,[parse_color(token,registered) for token in raw[2:end]]]
        else
            require_valid((command == "BEST" ? 2 : 1) <= length(raw) <= (command == "BEST" ? 33 : 32))
            args = Any[[parse_color(token,registered) for token in raw]]
        end
    else
        require_valid(haskey(SIGNATURES,command))
        kinds = split(SIGNATURES[command])
        require_valid(length(raw) == length(kinds))
        args = Any[typed_arg(raw[i],kinds[i],registered) for i in eachindex(raw)]
    end
    if command == "DEFINE"
        name,color = args
        require_valid(!(name in BUILTIN_NAMES))
        if !haskey(registered,name)
            push!(registration_order,name)
        end
        registered[name] = copy(color)
        return name*" "*hex_color(color)
    elseif command == "UNDEFINE"
        name = args[1]
        require_valid(haskey(registered,name))
        delete!(registered,name)
        filter!(!=(name),registration_order)
        return name*" removed"
    elseif command == "LIST"
        return isempty(registered) ? "NONE" : join([name*"="*hex_color(registered[name]) for name in sort(collect(keys(registered)))]," ")
    elseif command == "PARSE" || command == "NEAREST"
        color = args[1]
        names = vcat(String.(BUILTIN_NAMES),registration_order)
        colors = vcat(BUILTIN_COLORS,[registered[name] for name in registration_order])
        if command == "NEAREST"
            i = nearest_index(color,colors)
            return string(names[i],' ',hex_color(colors[i]),' ',color_distance(color,colors[i]))
        end
        i = findfirst(==(color),colors)
        parts = [hex_color(color),"rgb("*join(color,",")*")"]
        append!(parts,[model_text(model,color) for model in ("HSL","HSV","HWB","CMYK","YCBCR","YIQ")])
        push!(parts,i === nothing ? "-" : names[i])
        return join(parts," ")
    elseif command in ("HSL","HSV","HWB","CMYK","YCBCR","YIQ")
        return model_text(command,args[1])
    elseif command == "FROMHSL"
        result = from_hsl(args...)
    elseif command == "FROMHSV"
        h,s,v = args
        chroma = v*s
        result = [round_ratio(255*(u*chroma+6000*v-60*chroma),600000) for u in base60(h)]
    elseif command == "FROMHWB"
        h,w,k = args
        if w+k >= 100
            result = fill(round_ratio(255*w,w+k),3)
        else
            result = [round_ratio(255*(u*(100-w-k)+60*w),6000) for u in base60(h)]
        end
    elseif command == "FROMCMYK"
        result = [round_ratio(255*(100-args[i])*(100-args[4]),10000) for i in 1:3]
    elseif command == "FROMYCBCR"
        y,cb,cr = args
        result = byte_clamp.([
            round_ratio(1000*y+1402*(cr-128),1000),
            round_ratio(1000*y-344*(cb-128)-714*(cr-128),1000),
            round_ratio(1000*y+1772*(cb-128),1000)])
    elseif command == "FROMYIQ"
        y,i,q = args
        result = byte_clamp.([
            round_ratio(1000*y+956*i+619*q,1000),
            round_ratio(1000*y-272*i-647*q,1000),
            round_ratio(1000*y-1106*i+1703*q,1000)])
    elseif command == "RGB565"
        r,g,b = args[1]
        value = 2048*round_ratio(31*r,255)+32*round_ratio(63*g,255)+round_ratio(31*b,255)
        return @sprintf("0x%04X",value)
    elseif command == "FROM565"
        value = args[1]
        result = [round_ratio(255*div(value,2048),31),round_ratio(255*(div(value,32)%64),63),round_ratio(255*(value%32),31)]
    elseif command == "ANSI"
        colors = ansi_color.(16:255)
        i = nearest_index(args[1],colors)
        return string(i+15,' ',hex_color(colors[i]),' ',color_distance(args[1],colors[i]))
    elseif command == "FROMANSI"
        result = ansi_color(args[1])
    elseif command == "WEBSAFE"
        result = [51*round_ratio(x,51) for x in args[1]]
    elseif command == "GRAY"
        color,method = args
        r,g,b = color
        if method == "LUMA"
            value = round_ratio(299*r+587*g+114*b,1000)
        elseif method == "AVERAGE"
            value = round_ratio(r+g+b,3)
        elseif method == "LIGHTNESS"
            value = round_ratio(maximum(color)+minimum(color),2)
        else
            value = root_ratio(299*r*r+587*g*g+114*b*b,1000)
        end
        result = fill(value,3)
    elseif command == "INVERT"
        result = 255 .- args[1]
    elseif command == "MIX"
        a,b,p = args
        result = [round_ratio(a[i]*(100-p)+b[i]*p,100) for i in 1:3]
    elseif command == "MIXHSL"
        a,b,p = args
        h1,s1,l1 = hsl(a)
        h2,s2,l2 = hsl(b)
        delta = mod(h2-h1,360)
        delta > 180 && (delta -= 360)
        result = from_hsl(
            mod(h1+away_ratio(delta*p,100),360),
            s1+away_ratio((s2-s1)*p,100),
            l1+away_ratio((l2-l1)*p,100))
    elseif command == "GRADIENT"
        return color_sequence(gradient(args...))
    elseif command in ("TINTS","SHADES","TONES")
        color,n = args
        target_value = Dict("TINTS"=>255,"SHADES"=>0,"TONES"=>128)[command]
        target = fill(target_value,3)
        return color_sequence(gradient(color,target,n+2)[2:end-1])
    elseif command == "BLEND"
        mode,a,b = args
        if mode in ("HUE","SATURATION","COLOR","LUMINOSITY")
            h1,s1,l1 = hsl(a)
            h2,s2,l2 = hsl(b)
            if mode == "HUE"
                result = from_hsl(h2,s1,l1)
            elseif mode == "SATURATION"
                result = from_hsl(h1,s2,l1)
            elseif mode == "COLOR"
                result = from_hsl(h2,s2,l1)
            else
                result = from_hsl(h1,s1,l2)
            end
        else
            result = [blend_component(mode,a[i],b[i]) for i in 1:3]
        end
    elseif command == "ALPHA"
        a,p,b,q = args
        opacity = 100*p+q*(100-p)
        result = opacity == 0 ? [0,0,0] : [round_ratio(100*p*a[i]+q*(100-p)*b[i],opacity) for i in 1:3]
        return string(hex_color(result),' ',round_ratio(opacity,100),'%')
    elseif command == "SIMULATE"
        color,kind = args
        matrices = Dict(
            "PROTANOPIA"=>[[567,433,0],[558,442,0],[0,242,758]],
            "DEUTERANOPIA"=>[[625,375,0],[700,300,0],[0,300,700]],
            "TRITANOPIA"=>[[950,50,0],[0,433,567],[0,475,525]],
            "ACHROMATOPSIA"=>fill([299,587,114],3))
        result = [round_ratio(sum(row[i]*color[i] for i in 1:3),1000) for row in matrices[kind]]
    elseif command in ("ROTATE","COMPLEMENT","TRIADIC","TETRADIC","SPLITCOMP","ANALOGOUS")
        h,s,l = hsl(args[1])
        if command == "ROTATE"
            offsets = [args[2]]
        elseif command == "ANALOGOUS"
            offsets = [i*args[3] for i in -args[2]:args[2] if i != 0]
        else
            offsets = Dict("COMPLEMENT"=>[180],"TRIADIC"=>[120,240],"TETRADIC"=>[90,180,270],"SPLITCOMP"=>[150,210])[command]
        end
        return color_sequence([from_hsl(mod(h+d,360),s,l) for d in offsets])
    elseif command in ("LIGHTEN","DARKEN","SATURATE","DESATURATE")
        h,s,l = hsl(args[1])
        p = args[2]
        if command == "LIGHTEN"
            l = min(100,l+p)
        elseif command == "DARKEN"
            l = max(0,l-p)
        elseif command == "SATURATE"
            s = min(100,s+p)
        else
            s = max(0,s-p)
        end
        result = from_hsl(h,s,l)
    elseif command == "DISTANCE"
        a,b = args
        r1,g1,b1 = a
        r2,g2,b2 = b
        weighted = (1024+r1+r2)*(r1-r2)^2+2048*(g1-g2)^2+(1534-r1-r2)*(b1-b2)^2
        return string(color_distance(a,b),' ',root_ratio(weighted,512))
    elseif command == "CONTRAST"
        return contrast_text(args...)
    elseif command == "ACCESSIBLE"
        result,bg = args
        if contrast(result,bg)[2] == "FAIL"
            h,s,l = hsl(result)
            found = false
            for step in 1:100
                for lightness in (l-step,l+step)
                    if 0 <= lightness <= 100
                        candidate = from_hsl(h,s,lightness)
                        if contrast(candidate,bg)[2] != "FAIL"
                            result = candidate
                            found = true
                            break
                        end
                    end
                end
                found && break
            end
        end
        return hex_color(result)*" "*contrast_text(result,bg)
    elseif command == "BEST"
        colors = args[1]
        bg = colors[1]
        selected = 2
        for i in 3:length(colors)
            if contrast(colors[i],bg)[1] > contrast(colors[selected],bg)[1]
                selected = i
            end
        end
        return hex_color(colors[selected])*" "*contrast_text(colors[selected],bg)
    elseif command == "DESCRIBE"
        h,s,l = hsl(args[1])
        l <= 5 && return "black"
        l >= 95 && return "white"
        if l <= 20
            lightness = "very dark"
        elseif l <= 40
            lightness = "dark"
        elseif l <= 60
            lightness = "medium"
        elseif l <= 80
            lightness = "light"
        else
            lightness = "very light"
        end
        s < 10 && return lightness*" gray"
        if s < 40
            saturation = "muted"
        elseif s < 80
            saturation = "moderate"
        else
            saturation = "vivid"
        end
        names = split("red orange yellow chartreuse green spring-green cyan azure blue violet magenta rose")
        return join([lightness,saturation,names[div(mod(h+15,360),30)+1]]," ")
    elseif command in ("PALETTE","KMEANS")
        k,colors = args
        boxes = palette(colors,k)
        representatives = mean_color.(boxes)
        counts = length.(boxes)
        iterations = 0
        if command == "KMEANS"
            for iteration in 1:20
                assigned = [Vector{Int}[] for j in 1:k]
                for color in colors
                    push!(assigned[nearest_index(color,representatives)],color)
                end
                updated = [isempty(assigned[j]) ? representatives[j] : mean_color(assigned[j]) for j in 1:k]
                counts = length.(assigned)
                iterations = iteration
                unchanged = updated == representatives
                representatives = updated
                unchanged && break
            end
        end
        output = join([string(hex_color(representatives[j]),':',counts[j]) for j in 1:k]," ")
        return command == "PALETTE" ? output : string(iterations,' ',output)
    elseif command == "SORT"
        colors = args[1]
        order = sortperm(1:length(colors);by=i -> (Tuple(hsl(colors[i])),i))
        return color_sequence(colors[order])
    elseif command == "DITHER"
        error = [0,0,0]
        output = String[]
        for color in args[1]
            adjusted = byte_clamp.(color.+error)
            selected = nearest_index(adjusted,BUILTIN_COLORS[1:16])
            push!(output,BUILTIN_NAMES[selected])
            error = adjusted.-BUILTIN_COLORS[selected]
        end
        return join(output," ")
    elseif command == "RANDOM"
        state,n = args
        output = Vector{Int}[]
        for i in 1:n
            state = (48271*state)%2147483647
            u = state
            state = (48271*state)%2147483647
            v = state
            state = (48271*state)%2147483647
            push!(output,from_hsl(u%360,40+v%61,25+state%51))
        end
        return color_sequence(output)
    end
    return hex_color(result)
end

function main()
    count = parse(Int,readline())
    registered = Dict{String,Vector{Int}}()
    registration_order = String[]
    for i in 1:count
        parts = split(readline(),' ')
        try
            println(execute(String(parts[1]),parts[2:end],registered,registration_order))
        catch exception
            exception isa ArgumentError || rethrow()
            println("INVALID")
        end
    end
end
main()
