function fraction(numerator,denominator)
    denominator==0 && return "-"
    denominator<0 && ((numerator,denominator)=(-numerator,-denominator))
    common = gcd(abs(numerator),denominator)
    "$(numerator÷common)/$(denominator÷common)"
end
confusion_matrix(k) = zeros(Int,k,k)
function accumulate_confusion!(matrix,truth,prediction)
    for (actual,predicted) in zip(truth,prediction)
        matrix[actual,predicted] += 1
    end
end
correct_count(truth,prediction) = count(pair->pair[1]==pair[2],zip(truth,prediction))
function matrix_lines(states,matrix)
    width = maximum(length(string(value)) for value in matrix)
    lines = [" "*join((" "*lpad(state,width) for state in states))]
    for (i,state) in enumerate(states)
        push!(lines,string(state)*join((" "*lpad(value,width) for value in matrix[i,:])))
    end
    lines
end
function metric_lines(states,matrix)
    k = length(states)
    rows,columns = [sum(matrix[i,:]) for i in 1:k],[sum(matrix[:,i]) for i in 1:k]
    total,correct = sum(rows),sum(matrix[i,i] for i in 1:k)
    expected = sum(rows[i]*columns[i] for i in 1:k)
    lines = [
        "ACCURACY $(fraction(correct,total))",
        "KAPPA $(fraction(total*correct-expected,total*total-expected))"
    ]
    for (i,state) in enumerate(states)
        tp = matrix[i,i]
        push!(
            lines,
            "STATE $state precision $(fraction(tp,columns[i])) recall $(fraction(tp,rows[i])) f1 $(fraction(2tp,columns[i]+rows[i]))"
        )
    end
    lines
end
function runs(path)
    result = NTuple{3,Int}[]
    isempty(path) && return result
    start,state = 1,path[1]
    for t in 2:length(path)
        if path[t]!=state
            push!(result,(state,start,t-1))
            start,state = t,path[t]
        end
    end
    push!(result,(state,start,length(path)))
    result
end
regions_overlap(a,b) = a[1]<=b[2] && b[1]<=a[2]
function region_counts(predicted,truth)
    matched_predicted = count(region->any(other->regions_overlap(region,other),truth),predicted)
    matched_truth = count(region->any(other->regions_overlap(region,other),predicted),truth)
    [length(predicted),length(truth),matched_predicted,matched_truth]
end
boundaries(path) = [t for t in 2:length(path) if path[t-1]!=path[t]]
function boundary_counts(predicted_path,true_path,tolerance)
    predicted,truth = boundaries(predicted_path),boundaries(true_path)
    [
        length(predicted),
        length(truth),
        count(p->any(t->abs(p-t)<=tolerance,truth),predicted),
        count(t->any(p->abs(p-t)<=tolerance,predicted),truth)
    ]
end
