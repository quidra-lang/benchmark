After B,A,C the order is [C,A,B]. Fourth access B hits, removes its old slot and moves it to the front, yielding [B,C,A] with hits=1,misses=3. Following D misses, evicts least-recent A and yields [D,B,C] with hits=1,misses=4. The next access reads this same mutated cache; the access sequence is separately constructed and does not share ordering storage.

cache is a separate mutable List from the split string sequence. indexOf/removeAt/removeLast/insert update that list despite final preventing rebinding; out writes status before appending the resulting order.

The independent access list, mutable cache, hit removal/front insertion and miss eviction/counters establish the fourth/fifth accesses and retained state. Later accesses are unnecessary for that transition.
