off_diagonal(matrix) = sequential_sum(matrix[p,q]*matrix[p,q] for p in 1:size(matrix,1)-1 for q in p+1:size(
    matrix,
    1
))
function jacobi(matrix)
    a = copy(matrix)
    n = size(matrix,1)
    v = identity_matrix(n)
    initial = off_diagonal(a)
    sweeps = 0
    if initial>0
        for number in 1:100
            for p in 1:n-1,q in p+1:n
                a[p,q]==0 && continue
                theta = (a[q,q]-a[p,p])/(2a[p,q])
                t = 1/(abs(theta)+sqrt(theta*theta+1))
                theta<0 && (t=-t)
                c = 1/sqrt(t*t+1)
                s = t*c
                for r in 1:n
                    r in (p,q) && continue
                    x,y = a[r,p],a[r,q]
                    a[r,p] = a[p,r] = c*x-s*y
                    a[r,q] = a[q,r] = s*x+c*y
                end
                value = a[p,q]
                a[p,p] -= t*value
                a[q,q] += t*value
                a[p,q] = a[q,p] = 0.0
                for r in 1:n
                    x,y = v[r,p],v[r,q]
                    v[r,p],v[r,q] = c*x-s*y,s*x+c*y
                end
            end
            remaining = off_diagonal(a)
            sweeps==0 && remaining<1e-16*initial && (sweeps=number)
            remaining<1e-22*initial && break
        end
    end
    order = sort(collect(1:n);by=k->(-a[k,k],k))
    (values=[a[k,k] for k in order],vectors=[orient(normalize(v[:,k])) for k in order],sweeps=sweeps)
end
function power_iteration(matrix,references)
    b = copy(matrix)
    components = NamedTuple[]
    for reference in references
        x = ones(length(reference))
        agreement = nothing
        for step in 1:1000
            x = normalize(multiply(b,x))
            difference = min(max_difference(x,reference),max_difference(x,-reference))
            isnothing(agreement) && difference<1e-6 && (agreement=step)
        end
        value = dot_product(x,multiply(b,x))
        vector = orient(normalize(x))
        deflate!(b,value,vector)
        push!(components,(value=value,vector=vector,agreement=agreement))
    end
    components
end
