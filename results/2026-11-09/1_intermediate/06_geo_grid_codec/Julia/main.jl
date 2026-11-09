using Printf
const PRECS = Dict("GEOHASH"=>collect(1:9),"MAIDENHEAD"=>[2,4,6,8],"PLUSCODE"=>[2,4,6,8,10,11],
    "GARS"=>[5,6,7],"GEOREF"=>[2,4,8,10,12],"MESH"=>[4,6,8,9,10,11])
const GH = "0123456789bcdefghjkmnpqrstuvwxyz"
const L24 = "ABCDEFGHJKLMNPQRSTUVWXYZ"
const PC = "23456789CFGHJMPQRVWX"
const MH = ["ABCDEFGHIJKLMNOPQR","0123456789","abcdefghijklmnopqrstuvwx","0123456789"]
const BANDS = "CDEFGHJKLMNPQRSTUVWX"
const OS = "ABCDEFGHJKLMNOPQRSTUVWXYZ"
const COLS = ["STUVWXYZ","ABCDEFGH","JKLMNPQR"]
const ROWS = "ABCDEFGHJKLMNPQRSTUV"
invalid() = throw(ArgumentError("INVALID"))
char_at(set,index) = string(set[index+1])
function index_char(set,char)
    length(char) == 1 || invalid()
    index = findfirst(==(only(char)),set)
    index === nothing && invalid()
    return index-1
end
function integer_arg(text,lo,hi)
    occursin(r"^-?[0-9]{1,9}$",text) || invalid()
    value = parse(Int,text)
    lo <= value <= hi || invalid()
    return value
end
function coordinate(text,latitude)
    parts = match(r"^(-?)([0-9]{1,3})(?:\.([0-9]{1,6}))?$",text)
    parts === nothing && invalid()
    fraction = parts[3] === nothing ? "" : parts[3]
    value = parse(Int,parts[2])*1000000+parse(Int,rpad(fraction,6,'0'))
    parts[1] == "-" && (value = -value)
    if latitude
        -90000000 <= value <= 90000000 || invalid()
    else
        -180000000 <= value < 180000000 || invalid()
    end
    return value
end
function system_name(sys)
    haskey(PRECS,sys) || invalid()
    return sys
end
function grid_precision(sys,text)
    p = integer_arg(text,1,12)
    p in PRECS[sys] || invalid()
    return p
end
function grid(sys,p)
    sys == "GEOHASH" && return (2^div(5p+1,2),2^div(5p,2))
    sizes = Dict(
        "MAIDENHEAD"=>[(18,18),(180,180),(4320,4320),(43200,43200)],
        "PLUSCODE"=>[(18,9),(360,180),(7200,3600),(144000,72000),(2880000,1440000),(11520000,7200000)],
        "GARS"=>[(720,360),(1440,720),(4320,2160)],
        "GEOREF"=>[(24,12),(360,180),(21600,10800),(216000,108000),(2160000,1080000)],
        "MESH"=>[(360,270),(2880,2160),(28800,21600),(57600,43200),(115200,86400),(230400,172800)])
    return sizes[sys][findfirst(==(p),PRECS[sys])]
end
function radix_digits(value,radices)
    out = zeros(Int,length(radices))
    for index in reverse(eachindex(radices))
        out[index] = mod(value,radices[index])
        value = div(value,radices[index])
    end
    return out
end
function encode(sys,p,x,y)
    if sys == "GEOHASH"
        a,b = div(5p+1,2),div(5p,2)
        value = 0
        out = ""
        for index in 0:5p-1
            if iseven(index)
                a -= 1
                bit = mod(div(x,2^a),2)
            else
                b -= 1
                bit = mod(div(y,2^b),2)
            end
            value = 2value+bit
            if mod(index,5) == 4
                out *= char_at(GH,value)
                value = 0
            end
        end
        return out
    elseif sys == "MAIDENHEAD"
        k = div(p,2)
        radices = [18,10,24,10][1:k]
        xs,ys = radix_digits(x,radices),radix_digits(y,radices)
        return join(char_at(MH[i],xs[i])*char_at(MH[i],ys[i]) for i in 1:k)
    elseif sys == "PLUSCODE"
        tail = ""
        if p == 11
            tail = char_at(PC,4mod(y,5)+mod(x,4))
            x,y = div(x,4),div(y,5)
        end
        k = div(min(p,10),2)
        radices = fill(20,k)
        radices[1] = 18
        xs = radix_digits(x,radices)
        radices[1] = 9
        ys = radix_digits(y,radices)
        out = join(char_at(PC,ys[i])*char_at(PC,xs[i]) for i in 1:k)*tail
        p < 8 && return out*repeat("0",8-p)*"+"
        return out[1:8]*"+"*out[9:end]
    elseif sys == "GARS"
        tail = ""
        if p == 7
            tail = string(1+mod(x,3)+3(2-mod(y,3)))
            x,y = div(x,3),div(y,3)
        end
        if p >= 6
            tail = string(1+mod(x,2)+2(1-mod(y,2)))*tail
            x,y = div(x,2),div(y,2)
        end
        return @sprintf("%03d",x+1)*char_at(L24,div(y,24))*char_at(L24,mod(y,24))*tail
    elseif sys == "GEOREF"
        tail = ""
        if p >= 8
            m = div(p-4,2)
            scale = 6*10^(m-1)
            tail = lpad(string(mod(x,scale)),m,'0')*lpad(string(mod(y,scale)),m,'0')
            x,y = div(x,scale),div(y,scale)
        end
        if p >= 4
            tail = char_at(L24,mod(x,15))*char_at(L24,mod(y,15))*tail
            x,y = div(x,15),div(y,15)
        end
        return char_at(L24,x)*char_at(L24,y)*tail
    end
    level = findfirst(==(p),PRECS["MESH"])
    scale = [1,8,80,160,320,640][level]
    u,v = x-280scale,y-135scale
    (u < 0 || u >= 80scale || v < 0 || v >= 100scale) && return "-"
    radices = [80,8,10,2,2,2][1:level]
    us = radix_digits(u,radices)
    radices[1] = 100
    vs = radix_digits(v,radices)
    out = @sprintf("%02d%02d",vs[1],us[1])
    for index in 2:level
        if index <= 3
            out *= string(vs[index],us[index])
        else
            out *= string(1+us[index]+2vs[index])
        end
    end
    return out
end
function decode(sys,code)
    p = length(code)
    x,y = 0,0
    sys != "PLUSCODE" && !(p in PRECS[sys]) && invalid()
    if sys == "GEOHASH"
        bitindex = 0
        for char in code
            value = index_char(GH,string(char))
            for i in 4:-1:0
                bit = mod(div(value,2^i),2)
                if iseven(bitindex)
                    x = 2x+bit
                else
                    y = 2y+bit
                end
                bitindex += 1
            end
        end
    elseif sys == "MAIDENHEAD"
        for index in 1:div(p,2)
            radix = length(MH[index])
            x = x*radix+index_char(MH[index],string(code[2index-1]))
            y = y*radix+index_char(MH[index],string(code[2index]))
        end
    elseif sys == "PLUSCODE"
        count(==('+'),code) == 1 && findfirst(==('+'),code) == 9 || invalid()
        before,after = code[1:8],code[10:end]
        zero = findfirst(==('0'),before)
        prefix = zero === nothing ? 8 : zero-1
        prefix in (2,4,6,8) || invalid()
        prefix < 8 && (before[prefix+1:end] != repeat("0",8-prefix) || !isempty(after)) && invalid()
        prefix == 8 && !(length(after) in (0,2,3)) && invalid()
        sequence = before[1:prefix]*after
        p = length(sequence)
        values = [index_char(PC,string(char)) for char in sequence]
        values[1] <= 8 && values[2] <= 17 || invalid()
        for index in 1:div(min(p,10),2)
            y = y*(index == 1 ? 9 : 20)+values[2index-1]
            x = x*(index == 1 ? 18 : 20)+values[2index]
        end
        if p == 11
            x = 4x+mod(values[11],4)
            y = 5y+div(values[11],4)
        end
    elseif sys == "GARS"
        occursin(r"^[0-9]{3}",code) || invalid()
        x = parse(Int,code[1:3])-1
        y = 24index_char(L24[1:15],string(code[4]))+index_char(L24,string(code[5]))
        if p >= 6
            q = index_char("1234",string(code[6]))
            x,y = 2x+mod(q,2),2y+1-div(q,2)
        end
        if p == 7
            q = index_char("123456789",string(code[7]))
            x,y = 3x+mod(q,3),3y+2-div(q,3)
        end
    elseif sys == "GEOREF"
        x = index_char(L24,string(code[1]))
        y = index_char(L24[1:12],string(code[2]))
        if p >= 4
            x = 15x+index_char(L24[1:15],string(code[3]))
            y = 15y+index_char(L24[1:15],string(code[4]))
        end
        if p >= 8
            m = div(p-4,2)
            tail = code[5:end]
            occursin(r"^[0-9]+$",tail) || invalid()
            scale = 6*10^(m-1)
            e,n = parse(Int,tail[1:m]),parse(Int,tail[m+1:end])
            e < scale && n < scale || invalid()
            x,y = x*scale+e,y*scale+n
        end
    else
        occursin(r"^[0-9]+$",code) || invalid()
        level = findfirst(==(p),PRECS["MESH"])
        u,v = parse(Int,code[3:4]),parse(Int,code[1:2])
        u <= 79 || invalid()
        for index in 2:level
            if index <= 3
                base = index == 2 ? 8 : 10
                a,b = parse(Int,string(code[2index+1])),parse(Int,string(code[2index+2]))
                a < base && b < base || invalid()
                v,u = v*base+a,u*base+b
            else
                q = index_char("1234",string(code[index+5]))
                u,v = 2u+mod(q,2),2v+div(q,2)
            end
        end
        scale = [1,8,80,160,320,640][level]
        x,y = u+280scale,v+135scale
    end
    w,h = grid(sys,p)
    0 <= x < w && 0 <= y < h && encode(sys,p,x,y) == code || invalid()
    return (p,x,y)
end
function point_cell(sys,p,lat,lon)
    w,h = grid(sys,p)
    return div((lon+180000000)*w,360000000),min(div((lat+90000000)*h,180000000),h-1)
end
function ancestor(sys,cell,q)
    p,x,y = cell
    w,h = grid(sys,p)
    v,u = grid(sys,q)
    return (q,div(x*v,w),div(y*u,h))
end
cell_code(sys,cell) = encode(sys,cell...)
coord_text(value) = (value < 0 ? "-" : "")*@sprintf("%d.%06d",div(abs(value),1000000),mod(abs(value),1000000))
function decimal_suffix(e,n,d)
    d == 0 && return ""
    return " "*@sprintf("%05d",mod(e,100000))[1:d]*" "*@sprintf("%05d",mod(n,100000))[1:d]
end
function square_digits(args,offset)
    length(args) == offset && return (0,0,100000)
    a,b = args[offset+1:offset+2]
    occursin(r"^[0-9]{1,5}$",a) && occursin(r"^[0-9]{1,5}$",b) && length(a) == length(b) || invalid()
    size = 10^(5-length(a))
    return parse(Int,a)*size,parse(Int,b)*size,size
end
function compact_cells(sys,cells)
    current = Set(cells)
    while true
        changed = false
        for cell in collect(current)
            index = findfirst(==(cell[1]),PRECS[sys])
            for i in 1:index-1
                if ancestor(sys,cell,PRECS[sys][i]) in current
                    delete!(current,cell)
                    changed = true
                    break
                end
            end
        end
        for index in length(PRECS[sys]):-1:2
            p,q = PRECS[sys][index],PRECS[sys][index-1]
            w,h = grid(sys,p)
            v,u = grid(sys,q)
            needed = div(w,v)*div(h,u)
            groups = Dict{NTuple{3,Int},Vector{NTuple{3,Int}}}()
            for cell in current
                if cell[1] == p
                    parentcell = ancestor(sys,cell,q)
                    push!(get!(groups,parentcell,NTuple{3,Int}[]),cell)
                end
            end
            for (parentcell,children) in groups
                if length(children) == needed
                    setdiff!(current,children)
                    push!(current,parentcell)
                    changed = true
                end
            end
        end
        changed || break
    end
    return sort!(collect(current);by=cell -> (cell[1],-cell[3],cell[2]))
end
function execute(line)
    words = String.(split(line,' '))
    command,t = words[1],words[2:end]
    counts = Dict("ENCODE"=>[4],"DECODE"=>[2],"NEIGHBORS"=>[2],"PARENT"=>[2],"CHILDREN"=>[2],"COMMON"=>[3],
        "CONTAINS"=>[4],"COVER"=>[6],"CONVERT"=>[5],"STEPS"=>[3],"PATH"=>[3],"RELATE"=>[4],"SIZE"=>[2],
        "SHORTEN"=>[3],"RECOVER"=>[3],"UTMZONE"=>[2],"OSGB"=>[3],"UNOSGB"=>[1,3],"MGRS"=>[5],"UNMGRS"=>[2,4],"QUADKEY"=>[3],"UNQUADKEY"=>[1])
    if command == "COMPACT"
        2 <= length(t) <= 101 || invalid()
    else
        haskey(counts,command) && length(t) in counts[command] || invalid()
    end
    if command == "UTMZONE"
        lat,lon = coordinate(t[1],true),coordinate(t[2],false)
        (lat < -80000000 || lat >= 84000000) && return "NONE"
        band = char_at(BANDS,min(div(lat+80000000,8000000),19))
        zone = div(lon+180000000,6000000)+1
        band == "V" && 3000000 <= lon < 12000000 && (zone = 32)
        if band == "X" && 0 <= lon < 42000000
            if lon < 9000000
                zone = 31
            elseif lon < 21000000
                zone = 33
            elseif lon < 33000000
                zone = 35
            else
                zone = 37
            end
        end
        return string(zone,band)
    elseif command == "OSGB"
        e,n,d = integer_arg(t[1],0,699999),integer_arg(t[2],0,1299999),integer_arg(t[3],0,5)
        letters = char_at(OS,5(3-div(n,500000))+2+div(e,500000))*char_at(OS,5(4-mod(div(n,100000),5))+mod(div(e,100000),5))
        return letters*decimal_suffix(e,n,d)
    elseif command == "UNOSGB"
        length(t[1]) == 2 || invalid()
        a,b = index_char(OS,t[1][1:1]),index_char(OS,t[1][2:2])
        e = 500000(mod(a,5)-2)+100000mod(b,5)
        n = 500000(3-div(a,5))+100000(4-div(b,5))
        0 <= e < 700000 && 0 <= n < 1300000 || invalid()
        de,dn,size = square_digits(t,1)
        return "sw=$(e+de),$(n+dn) size=$size"
    elseif command == "MGRS"
        zone = integer_arg(t[1],1,60)
        length(t[2]) == 1 || invalid()
        index_char(BANDS,t[2])
        e,n,d = integer_arg(t[3],100000,899999),integer_arg(t[4],0,9999999),integer_arg(t[5],0,5)
        offset = iseven(zone) ? 5 : 0
        letters = char_at(COLS[mod(zone,3)+1],div(e,100000)-1)*char_at(ROWS,mod(div(n,100000)+offset,20))
        return string(zone,t[2])*" "*letters*decimal_suffix(e,n,d)
    elseif command == "UNMGRS"
        parts = match(r"^([1-9][0-9]?)([CDEFGHJKLMNPQRSTUVWX])$",t[1])
        parts === nothing && invalid()
        zone = parse(Int,parts[1])
        zone <= 60 && length(t[2]) == 2 || invalid()
        c = index_char(COLS[mod(zone,3)+1],t[2][1:1])
        r = index_char(ROWS,t[2][2:2])
        offset = iseven(zone) ? 5 : 0
        e,n = 100000(c+1),100000mod(r-offset,20)
        de,dn,size = square_digits(t,2)
        return "$(t[1]) sw=$(e+de),$(n+dn) size=$size"
    elseif command == "QUADKEY"
        z = integer_arg(t[3],1,23)
        x,y = integer_arg(t[1],0,2^z-1),integer_arg(t[2],0,2^z-1)
        return join(string(mod(div(x,2^i),2)+2mod(div(y,2^i),2)) for i in z-1:-1:0)
    elseif command == "UNQUADKEY"
        occursin(r"^[0-3]{1,23}$",t[1]) || invalid()
        x,y = 0,0
        for char in t[1]
            value = parse(Int,string(char))
            x,y = 2x+mod(value,2),2y+div(value,2)
        end
        return "x=$x y=$y z=$(length(t[1]))"
    elseif command in ("SHORTEN","RECOVER")
        lat,lon = coordinate(t[2],true),coordinate(t[3],false)
        if command == "SHORTEN"
            p,x,y = decode("PLUSCODE",t[1])
            p >= 8 || invalid()
            w,h = grid("PLUSCODE",p)
            dy = abs((-90000000-lat)*2h+180000000(2y+1))
            dx = abs((-180000000-lon)*2w+360000000(2x+1))
            dy < 15000*2h && dx < 15000*2w && return t[1][7:end]
            dy < 300000*2h && dx < 300000*2w && return t[1][5:end]
            return t[1]
        end
        occursin(r"^([23456789CFGHJMPQRVWX]{2}|[23456789CFGHJMPQRVWX]{4})\+([23456789CFGHJMPQRVWX]{2,3})?$",t[1]) || invalid()
        r = 9-findfirst(==('+'),t[1])
        px,py = point_cell("PLUSCODE",10,lat,lon)
        full = encode("PLUSCODE",10,px,py)[1:r]*t[1]
        p,x,y = decode("PLUSCODE",full)
        w,h = grid("PLUSCODE",p)
        d = r == 4 ? 1000000 : 50000
        my,mx = div(d*h,180000000),div(d*w,360000000)
        cy,cx = 180000000(2y+1),360000000(2x+1)
        if (lat+div(d,2)+90000000)*2h < cy && cy >= d*2h
            y -= my
        elseif (lat-div(d,2)+90000000)*2h > cy && cy <= (180000000-d)*2h
            y += my
        end
        if (lon+div(d,2)+180000000)*2w < cx
            x = mod(x-mx,w)
        elseif (lon-div(d,2)+180000000)*2w > cx
            x = mod(x+mx,w)
        end
        return encode("PLUSCODE",p,x,y)
    end
    sys = system_name(t[1])
    if command in ("SIZE","ENCODE","COVER")
        p = grid_precision(sys,t[command == "ENCODE" ? 4 : 2])
        w,h = grid(sys,p)
        if command == "SIZE"
            cells = w*h
            if sys == "MESH"
                scale = [1,8,80,160,320,640][findfirst(==(p),PRECS[sys])]
                cells = 8000scale*scale
            end
            return "w=$(coord_text(div(360000000,w))) h=$(coord_text(div(180000000,h))) cells=$cells"
        elseif command == "ENCODE"
            x,y = point_cell(sys,p,coordinate(t[2],true),coordinate(t[3],false))
            code = encode(sys,p,x,y)
            return code == "-" ? "OUT OF AREA" : code
        end
        lat1,lon1 = coordinate(t[3],true),coordinate(t[4],false)
        lat2,lon2 = coordinate(t[5],true),coordinate(t[6],false)
        lat1 <= lat2 || invalid()
        x1,y1 = point_cell(sys,p,lat1,lon1)
        x2,y2 = point_cell(sys,p,lat2,lon2)
        columns = lon1 <= lon2 ? x2-x1+1 : min(w,x2-x1+1+w)
        (y2-y1+1)*columns > 100 && return "TOO MANY"
        return join((encode(sys,p,mod(x1+i,w),y) for y in y2:-1:y1 for i in 0:columns-1)," ")
    elseif command == "COMPACT"
        cells = [decode(sys,code) for code in t[2:end]]
        return join((cell_code(sys,cell) for cell in compact_cells(sys,cells))," ")
    end
    cell = decode(sys,t[2])
    p,x,y = cell
    w,h = grid(sys,p)
    index = findfirst(==(p),PRECS[sys])
    if command == "DECODE"
        south,west = -90000000+div(180000000y,h),-180000000+div(360000000x,w)
        north,east = -90000000+div(180000000(y+1),h),-180000000+div(360000000(x+1),w)
        cy,cx = -90000000+div(180000000(2y+1),2h),-180000000+div(360000000(2x+1),2w)
        return "sw=$(coord_text(south)),$(coord_text(west)) ne=$(coord_text(north)),$(coord_text(east)) c=$(coord_text(cy)),$(coord_text(cx))"
    elseif command == "CONTAINS"
        point = point_cell(sys,p,coordinate(t[3],true),coordinate(t[4],false))
        return point == (x,y) ? "YES" : "NO"
    elseif command == "NEIGHBORS"
        codes = String[]
        for (dx,dy) in ((0,1),(1,1),(1,0),(1,-1),(0,-1),(-1,-1),(-1,0),(-1,1))
            if y+dy < 0 || y+dy >= h
                push!(codes,"-")
            else
                push!(codes,encode(sys,p,mod(x+dx,w),y+dy))
            end
        end
        return join(codes," ")
    elseif command == "PARENT"
        index == 1 && return "NONE"
        return cell_code(sys,ancestor(sys,cell,PRECS[sys][index-1]))
    elseif command == "CHILDREN"
        index == length(PRECS[sys]) && return "NONE"
        q = PRECS[sys][index+1]
        v,u = grid(sys,q)
        rx,ry = div(v,w),div(u,h)
        rx*ry > 100 && return "TOO MANY"
        return join((encode(sys,q,rx*x+i,ry*y+j) for j in ry-1:-1:0 for i in 0:rx-1)," ")
    elseif command == "CONVERT"
        t[3] == "TO" || invalid()
        sys2 = system_name(t[4])
        q = grid_precision(sys2,t[5])
        v,u = grid(sys2,q)
        code = encode(sys2,q,div((2x+1)*v,2w),div((2y+1)*u,2h))
        return code == "-" ? "OUT OF AREA" : code
    elseif command == "RELATE"
        sys2 = system_name(t[3])
        q,a,b = decode(sys2,t[4])
        v,u = grid(sys2,q)
        l1,r1,l2,r2 = x*v,(x+1)*v,a*w,(a+1)*w
        s1,n1,s2,n2 = y*u,(y+1)*u,b*h,(b+1)*h
        l1 == l2 && r1 == r2 && s1 == s2 && n1 == n2 && return "EQUAL"
        l1 >= l2 && r1 <= r2 && s1 >= s2 && n1 <= n2 && return "INSIDE"
        l2 >= l1 && r2 <= r1 && s2 >= s1 && n2 <= n1 && return "CONTAINS"
        max(l1,l2) < min(r1,r2) && max(s1,s2) < min(n1,n2) && return "OVERLAP"
        latitude_touch = max(s1,s2) <= min(n1,n2)
        dateline = (x == 0 && a+1 == v) || (a == 0 && x+1 == w)
        latitude_touch && (max(l1,l2) <= min(r1,r2) || dateline) && return "TOUCH"
        return "DISJOINT"
    end
    second = decode(sys,t[3])
    if command == "COMMON"
        limit = min(index,findfirst(==(second[1]),PRECS[sys]))
        for i in limit:-1:1
            a = ancestor(sys,cell,PRECS[sys][i])
            a == ancestor(sys,second,PRECS[sys][i]) && return cell_code(sys,a)
        end
        return "NONE"
    end
    p == second[1] || return "MISMATCH"
    dx = mod(second[2]-x,w)
    2dx > w && (dx -= w)
    dy = second[3]-y
    command == "STEPS" && return "dx=$dx dy=$dy"
    n = max(abs(dx),abs(dy))
    n+1 > 100 && return "TOO MANY"
    n == 0 && return cell_code(sys,cell)
    return join((encode(sys,p,mod(x+fld(2i*dx+n,2n),w),y+fld(2i*dy+n,2n)) for i in 0:n)," ")
end
function main()
    total = parse(Int,readline())
    for index in 1:total
        line = readline()
        try
            println(execute(line))
        catch exception
            exception isa ArgumentError || rethrow()
            println("INVALID")
        end
    end
end
main()
