using Printf
function fmt(value,places=4)
    text = Printf.format(Printf.Format("%.$(places)f"),value)
    startswith(text,"-") && parse(Float64,text)==0 ? text[2:end] : text
end
function curve_plot(observed,fitted)
    days,largest = length(observed),maximum(observed)
    width = length(string(largest))
    grid = fill('.',20,70)
    for column in 0:69
        day = column*(days-1)÷69+1
        observed_row = min(19,20observed[day]÷largest)
        fitted_row = min(19,floor(Int,20*fitted[day]/largest))
        grid[observed_row+1,column+1] = 'o'
        grid[fitted_row+1,column+1] = observed_row==fitted_row ? '#' : '*'
    end
    lines = ["plot observed o fitted * both # days 1 $days max $largest"]
    for row in 19:-1:0
        push!(lines,lpad(largest*row÷20,width)*" |"*join(grid[row+1,:]))
    end
    ticks = join(column%10==0 ? '+' : '-' for column in 0:69)
    push!(lines,repeat(" ",width+1)*"+"*ticks)
    labels = fill(' ',70)
    for column in 0:10:60
        text = string(1+column*(days-1)÷69)
        labels[column+1:column+length(text)] = collect(text)
    end
    push!(lines,rstrip(repeat(" ",width+2)*join(labels)))
    lines
end
