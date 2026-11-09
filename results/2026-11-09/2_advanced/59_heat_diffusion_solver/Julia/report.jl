using Printf
function real_text(value,places)
    text = Printf.format(Printf.Format("%.$(places)f"),value)
    startswith(text,"-") && parse(Float64,text)==0 ? text[2:end] : text
end
time_text(milliseconds) = "$(milliseconds÷1000).$(lpad(milliseconds%1000,3,'0'))"
temperature_lines(plate,field) = [join(
    (real_text(field[cell(plate,r,c)],2) for c in 0:plate.width-1),
    " "
) for r in 0:plate.height-1]
function isotherm_lines(plate,field,bands)
    hottest = argmax(field)
    counts = zeros(Int,length(bands)+1)
    characters = Char[]
    for (p,temperature) in enumerate(field)
        digit = count(boundary->boundary<=temperature,bands)
        counts[digit+1] += 1
        push!(characters,p==hottest ? '*' : Char(Int('0')+digit))
    end
    counts,[join(characters[r*plate.width+1:(r+1)*plate.width]) for r in 0:plate.height-1]
end
function write_lines(name,lines)
    mkpath("output")
    open(joinpath("output",name),"w") do io
        for line in lines
            println(io,line)
        end
    end
end
