function doc_tree(document,depth=0)
    kind,prefix = document.kind,repeat("  ",depth)
    if kind == :concat
        return [line for child in document.children for line in doc_tree(child,depth)]
    elseif kind == :text
        return [prefix * "text \"" * document.value * "\""]
    elseif kind == :suffix
        return [prefix * "suffix \"" * document.value * "\""]
    elseif kind == :if_break
        return [prefix * "if_break \"" * document.broken * "\" \"" * document.flat * "\""]
    elseif kind in (:group,:nest,:align)
        label = kind == :group ? "group $(document.mode)" : kind == :nest ? "nest $(document.amount)" : "align"
        return [prefix * label;doc_tree(document.children[1],depth+1)]
    end
    [prefix * string(kind)]
end
function diff_lines(original,formatted)
    n,m = length(original),length(formatted)
    table = zeros(Int,n+1,m+1)
    for i in n:-1:1, j in m:-1:1
        table[i,j] = original[i] == formatted[j] ? table[i+1,j+1]+1 : max(table[i+1,j],table[i,j+1])
    end
    i,j,deleted,inserted = 1,1,0,0
    hunks = Any[]
    current = nothing
    while i <= n || j <= m
        if i <= n && j <= m && original[i] == formatted[j]
            current === nothing || push!(hunks,current)
            current = nothing
            i += 1
            j += 1
            continue
        end
        if current === nothing
            current = (start_old=i-1,start_new=j-1,deletes=Ref(0),inserts=Ref(0),lines=String[])
        end
        if j > m || (i <= n && table[i+1,j] >= table[i,j+1])
            current.deletes[] += 1
            deleted += 1
            push!(current.lines,"-" * original[i])
            i += 1
        else
            current.inserts[] += 1
            inserted += 1
            push!(current.lines,"+" * formatted[j])
            j += 1
        end
    end
    current === nothing || push!(hunks,current)
    result = ["hunks=$(length(hunks)) deleted=$deleted inserted=$inserted"]
    for hunk in hunks
        d,e = hunk.deletes[],hunk.inserts[]
        a,b = hunk.start_old+Int(d > 0),hunk.start_new+Int(e > 0)
        push!(result,"@@ -$a,$d +$b,$e @@")
        append!(result,hunk.lines)
    end
    result
end
function write_lines(name,lines)
    mkpath("output")
    write(joinpath("output",name),isempty(lines) ? "" : join(lines,"\n") * "\n")
end
