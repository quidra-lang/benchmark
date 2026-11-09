using Printf

function real_text(value)
    text = @sprintf("%.4f", value)
    text == "-0.0000" ? "0.0000" : text
end

function p_value(numerator, denominator)
    numerator, denominator = reduced_fraction(numerator, denominator)
    "$numerator/$denominator $(real_text(numerator / denominator))"
end

number_list(numbers) = isempty(numbers) ? "none" : join(sort(numbers), " ")
bin_number(value, low, high, bins) = min(floor(Int, bins * (value - low) / (high - low)), bins - 1) + 1
bar(count, top) = "#"^div(40 * count + top - 1, top)

function write_lines(path, lines)
    open(path, "w") do file
        for line in lines
            println(file, line)
        end
    end
end
