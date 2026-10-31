using Printf

function real_text(value)
    text = @sprintf("%.4f", value)
    text == "-0.0000" ? "0.0000" : text
end

reals(values) = join(real_text.(values), " ")
four_decimal(value) = round(value; digits=4)
amount(cents) = (cents < 0 ? "-" : "") * string(div(abs(cents), 100)) * "." * lpad(string(mod(abs(cents), 100)), 2, '0')

function write_lines(path, lines)
    open(path, "w") do file
        for line in lines
            println(file, line)
        end
    end
end
