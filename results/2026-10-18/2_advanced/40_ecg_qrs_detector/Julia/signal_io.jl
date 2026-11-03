function read_ecg()
    [parse(Int,split(line,',')[2]) for line in readlines("input/ecg.csv")[2:end]]
end
function read_annotations()
    [(sample=parse(Int,words[1]),label=String(words[2]))
     for words in split.(readlines("input/annotations.csv")[2:end],',')]
end
function read_params()
    Dict(String(words[1])=>parse(Int,words[2])
         for words in split.(readlines("input/params.txt")))
end
function write_lines(name,lines)
    mkpath("output")
    open(joinpath("output",name),"w") do io
        for line in lines
            println(io,line)
        end
    end
end
