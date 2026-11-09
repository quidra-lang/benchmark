Translate every flag access for integer k to physical k+1 while keeping loop variables as integer labels. Thus 0,1,7,49,200 map to positions 1,2,8,50,201. Preserve inclusive limit 200 and increasing prime retrieval; marking 49 must change position 50, not label 49.

The table already supports integer keys; initialize and access prime[n+1], prime[p+1] and prime[multiple+1]. primes remains a dense output array of integer labels, independent of flag keys.

The flag allocation, integer-labelled marking/retrieval accesses and inclusive limit are all affected by the representation shift. Prime output alone would hide the 49-to-position-50 error.
