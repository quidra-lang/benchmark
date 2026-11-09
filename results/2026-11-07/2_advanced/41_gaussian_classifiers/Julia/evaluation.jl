function reduced_fraction(a,b)
    b==0 && return nothing
    divisor = gcd(abs(a),b)
    (a÷divisor,b÷divisor)
end
function sum_fractions(values)
    a,b = 0,1
    for (c,d) in values
        a,b = reduced_fraction(a*d+c*b,b*d)
    end
    (a,b)
end
function measures(actual,predictions,classes)
    matrix = zeros(Int,classes,classes)
    for (a,b) in zip(actual,predictions)
        matrix[a,b] += 1
    end
    support = vec(sum(matrix;dims=2))
    predicted = vec(sum(matrix;dims=1))
    diagonal = [matrix[k,k] for k in 1:classes]
    correct,n = sum(diagonal),length(actual)
    recall = [reduced_fraction(diagonal[k],support[k]) for k in 1:classes]
    precision = [reduced_fraction(diagonal[k],predicted[k]) for k in 1:classes]
    f1 = [reduced_fraction(2diagonal[k],support[k]+predicted[k]) for k in 1:classes]
    a,b = sum_fractions(recall)
    expected = sum(support.*predicted)
    (matrix=matrix,support=support,correct=correct,accuracy=reduced_fraction(correct,n),
     balanced_accuracy=reduced_fraction(a,b*classes),kappa=reduced_fraction(n*correct-expected,n*n-expected),
     recall=recall,precision=precision,f1=f1,
     macro_f1=ordered_sum(2diagonal[k]/(support[k]+predicted[k]) for k in 1:classes)/classes)
end
function mcnemar(actual,a,b)
    b01 = count(i->a[i]==actual[i] && b[i]!=actual[i],eachindex(actual))
    b10 = count(i->a[i]!=actual[i] && b[i]==actual[i],eachindex(actual))
    chi2 = b01==b10 ? 0.0 : (abs(b01-b10)-1)^2/(b01+b10)
    (b01=b01,b10=b10,chi2=chi2,significant=chi2>3.841)
end
mutable struct RandomGenerator
    state::Int
end
function draw!(generator)
    generator.state = (48271generator.state)%2147483647
end
