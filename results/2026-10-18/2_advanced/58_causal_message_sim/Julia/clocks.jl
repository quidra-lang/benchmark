function nonreceive_event!(process,index)
    process.lamport += 1
    process.vector[index] += 1
end
function receive_event!(process,index,sender)
    process.lamport = max(process.lamport,sender.lamport)+1
    process.vector = max.(process.vector,sender.vector)
    process.vector[index] += 1
end
less_equal(a,b) = all(pair->pair[1]<=pair[2],zip(a,b))
happens_before(a,b) = a!=b && less_equal(a,b)
relation(a,b) = happens_before(a,b) ? "->" : happens_before(b,a) ? "<-" : "||"
broadcast_deliverable(stamp,received,source) = all(
    k->k==source ? stamp[k]==received[k]+1 : stamp[k]<=received[k],
    eachindex(stamp)
)
missing_indices(stamp,received,source) = [k for k in eachindex(stamp) if stamp[k]>received[k]+(k==source)]
vector_text(vector) = join(vector,",")
