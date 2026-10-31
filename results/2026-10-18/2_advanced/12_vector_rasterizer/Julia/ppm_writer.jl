module PPMWriter
export write_ppm, write_preview
function write_lines(path, lines)
    open(path, "w") do io
        for line in lines
            println(io, line)
        end
    end
end
function write_ppm(path, image)
    h, w = size(image)
    lines = ["P3", "$w $h", "255"]
    for y in 1:h
        push!(lines, join((join(image[y,x], " ") for x in 1:w), " "))
    end
    write_lines(path, lines)
end
function write_preview(path, image)
    h, w = size(image)
    ramp = "@%#*+=-:,."
    lines = String[]
    for top in 1:4:h
        chars = Char[]
        for left in 1:2:w
            total = 0
            for y in top:top+3, x in left:left+1
                r, g, b = image[y,x]
                total += 299r+587g+114b
            end
            lum = fld(total,8000)
            push!(chars, ramp[fld(lum*10,256)+1])
        end
        push!(lines, join(chars))
    end
    write_lines(path, lines)
end
end
