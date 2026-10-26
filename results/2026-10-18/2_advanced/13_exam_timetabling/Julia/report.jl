fixed_width_line(label, cells, label_width, cell_width) = rpad(label, label_width) * join(lpad(cell, cell_width) for cell in cells)
rounded_percent(part, whole) = div(200 * part + whole, 2 * whole)

function write_files(directory, files)
    mkpath(directory)
    for (name, lines) in files
        open(joinpath(directory, name), "w") do file
            for line in lines
                println(file, line)
            end
        end
    end
end
