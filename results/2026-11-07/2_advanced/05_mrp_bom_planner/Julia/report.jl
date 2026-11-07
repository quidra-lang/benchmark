module Report

money(cents) = string(cents ÷ 100) * "." * lpad(string(cents % 100), 2, '0')
percent(part, whole) = (200 * part + whole) ÷ (2 * whole)
table(label, values, width) = rpad(label, 10) * join((lpad(string(value), width) for value in values))

function writefile(name, lines)
    mkpath("output")
    open(joinpath("output", name), "w") do file
        for line in lines
            println(file, line)
        end
    end
end

end
