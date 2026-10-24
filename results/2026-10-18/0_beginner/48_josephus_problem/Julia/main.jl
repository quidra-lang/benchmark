for (n,k) in [(7,3),(10,2),(41,3)]
    people = collect(1:n)
    removed = Int[]
    index = 0
    while !isempty(people)
        index = mod(index+k-1,length(people))
        push!(removed,popat!(people,index+1))
    end
    println("n=",n," k=",k,": ",join(removed," "))
    println("survivor: ",removed[end])
end
