function read_dataset()
    subjects = [(id=parse(Int,r[1]),group=String(r[2]),time=parse(Int,r[3]),event=parse(Int,r[4]),
                 age=parse(Int,r[5]),sex=String(r[6]),stage=parse(Int,r[7]))
                for r in split.(readlines("input/subjects.csv")[2:end],',')]
    sort!(subjects;by=r->r.id)
    settings = Dict{String,Any}()
    for line in readlines("input/params.txt")
        words = split(line)
        key = String(words[1])
        settings[key] = key in (
            "GROUPS",
            "STRATA",
            "SUBGROUPS",
            "COX"
        ) ? String.(words[2:end]) : parse.(Int,words[2:end])
    end
    subjects,settings
end
