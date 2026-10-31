one_smaller_subsets =: 3 : 0
    subsets =. 0$a:
    for_index. i.#y do. subsets =. subsets,<((i.#y)~:index)#y end.
    subsets
)
generate_candidates =: 3 : 0
    'previous size taxonomy' =. y
    previous =. (/:itemset_text&.>previous){previous
    known =. itemset_text&.>previous
    joined =. excluded =. pruned =. 0
    candidates =. 0$a:
    for_firstindex. i.#previous do.
        first =. firstindex{::previous
        for_secondindex. (firstindex+1)+i.(#previous)-(firstindex+1) do.
            second =. secondindex{::previous
            if. -. (}:first)-:}:second do. break. end.
            joined =. joined+1
            candidate =. first,{:second
            taxonomypair =. 0
            if. (size=2)*.#taxonomy do.
                'a b' =. candidate
                if. a has_key taxonomy do. taxonomypair =. b-:a get_key taxonomy end.
                if. b has_key taxonomy do. taxonomypair =. taxonomypair+.a-:b get_key taxonomy end.
            end.
            if. taxonomypair do. excluded =. excluded+1
            else.
                subsets =. itemset_text&.>one_smaller_subsets candidate
                if. *./subsets e.known do. candidates =. candidates,<candidate
                else. pruned =. pruned+1 end.
            end.
        end.
    end.
    'joined excluded pruned itemsets' record (<joined),(<excluded),(<pruned),<candidates
)
count_supports =: 4 : 0
    index =. empty_table ''
    for_number. i.#x do.
        for_itembox. number{::x do.
            item =. >itembox
            numbers =. 0$0
            if. item has_key index do. numbers =. item get_key index end.
            index =. ((<item),<numbers,number) put_key index
        end.
    end.
    counts =. empty_table ''
    for_candidatebox. y do.
        candidate =. >candidatebox
        numbers =. i.#x
        for_itembox. candidate do.
            item =. >itembox
            if. item has_key index do. found =. item get_key index else. found =. 0$0 end.
            numbers =. numbers#~numbers e.found
        end.
        counts =. ((<itemset_text candidate),<#numbers) put_key counts
    end.
    counts
)
