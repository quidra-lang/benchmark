using Printf
svm_sign(value) = value>0 ? 1 : -1
folds(size,count) = [(
    [i for i in 1:size if (i-1)%count!=f],
    [i for i in 1:size if (i-1)%count==f]
) for f in 0:count-1]
correct_count(labels,values) = count(pair->svm_sign(pair[2])==pair[1],zip(labels,values))
function binary_counts(labels,values)
    tp,fp,tn,fn = 0,0,0,0
    for (label,value) in zip(labels,values)
        if label==1
            value>0 ? (tp+=1) : (fn+=1)
        else
            value>0 ? (fp+=1) : (tn+=1)
        end
    end
    tp,fp,tn,fn
end
function auc(labels,values)
    positives,negatives = findall(==(1),labels),findall(==(-1),labels)
    total = 0.0
    for positive in positives,negative in negatives
        values[positive]>values[negative] && (total+=1.0)
        values[positive]==values[negative] && (total+=0.5)
    end
    total/(length(positives)*length(negatives))
end
function confusion_matrix(classes,predictions)
    matrix = zeros(Int,3,3)
    for (actual,predicted) in zip(classes,predictions)
        matrix[actual,predicted] += 1
    end
    matrix
end
function confusion_lines(matrix)
    lines = [join(matrix[i,:]," ") for i in 1:3]
    for k in 1:3
        push!(
            lines,
            "class $k precision $(ratio(matrix[k,k],sum(matrix[:,k]))) recall $(ratio(matrix[k,k],sum(matrix[k,:])))"
        )
    end
    lines
end
function fixed_text(value,decimals=4)
    result = Printf.format(Printf.Format("%.$(decimals)f"),value)
    startswith(result,"-") && parse(Float64,result)==0 ? result[2:end] : result
end
ratio(numerator,denominator) = denominator>0 ? fixed_text(numerator/denominator) : "-"
function ordered_sum(values)
    total = 0.0
    for value in values
        total += value
    end
    total
end
function write_lines(name,lines)
    mkpath("output")
    open(joinpath("output",name),"w") do io
        for line in lines
            println(io,line)
        end
    end
end
