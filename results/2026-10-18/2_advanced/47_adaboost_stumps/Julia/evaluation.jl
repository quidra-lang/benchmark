using Printf
function number(value,decimals=4)
    text = Printf.format(Printf.Format("%.$(decimals)f"),value)
    startswith(text,"-") && parse(Float64,text)==0 ? text[2:end] : text
end
ratio(a,b) = b>0 ? number(a/b) : "-"
prediction(score) = score>0 ? 1 : -1
function auc(rows,scores)
    positive = [scores[i] for i in eachindex(rows) if rows[i].label==1]
    negative = [scores[i] for i in eachindex(rows) if rows[i].label==-1]
    wins = ties = 0
    for a in positive,b in negative
        wins += a>b
        ties += a==b
    end
    (2wins+ties,2length(positive)*length(negative))
end
function confusion(rows,predictions,classes)
    matrix = zeros(Int,classes,classes)
    for (row,predicted) in zip(rows,predictions)
        matrix[row.label,predicted] += 1
    end
    matrix
end
count_at_most(margins,threshold) = count(<=(threshold),margins)
function write_lines(name,lines)
    open(joinpath("output",name),"w") do io
        for line in lines
            println(io,line)
        end
    end
end
