build_neighborhood =: 3 : 0
    user_count =. #Users
    item_count =. #Items
    user_similarity =. (user_count,user_count)$2.0
    user_common =. (user_count,user_count)$0
    item_similarity =. (item_count,item_count)$2.0
    common =. (item_count,item_count)$0
    difference =. (item_count,item_count)$0
    for_u. i.user_count-1 do.
        for_v. (u+1)+i.user_count-u+1 do.
            n =. 0x
            sx =. 0x
            sy =. 0x
            sxx =. 0x
            syy =. 0x
            sxy =. 0x
            for_item. u{::UserRatings do.
                other =. (<v,item){RatingValues
                if. other=0 do.
                    continue.
                end.
                value =. (<u,item){RatingValues
                n =. n+1
                sx =. sx+value
                sy =. sy+other
                sxx =. sxx+value*value
                syy =. syy+other*other
                sxy =. sxy+value*other
            end.
            if. n<2 do.
                continue.
            end.
            numerator =. (n*sxy)-sx*sy
            dx =. (n*sxx)-sx*sx
            dy =. (n*syy)-sy*sy
            if. (dx=0)+.dy=0 do.
                continue.
            end.
            scaled =. numerator*n
            a =. scaled*scaled
            b =. ((dx*dy)*(n+Shrinkage))*(n+Shrinkage)
            similarity =. (*numerator)*%:(0.0+a)%(0.0+b)
            user_similarity =. similarity (<u,v)}user_similarity
            user_similarity =. similarity (<v,u)}user_similarity
            user_common =. n (<u,v)}user_common
            user_common =. n (<v,u)}user_common
        end.
    end.
    for_i. i.item_count-1 do.
        for_j. (i+1)+i.item_count-i+1 do.
            n =. 0
            delta =. 0
            numerator =. 0.0
            ni =. 0.0
            nj =. 0.0
            for_u. i{::ItemRatings do.
                other =. (<u,j){RatingValues
                if. other=0 do.
                    continue.
                end.
                value =. (<u,i){RatingValues
                n =. n+1
                delta =. delta+(value-other)
                di =. value-u{UserMeans
                dj =. other-u{UserMeans
                numerator =. numerator+di*dj
                ni =. ni+di*di
                nj =. nj+dj*dj
            end.
            if. n>:1 do.
                common =. n (<i,j)}common
                common =. n (<j,i)}common
                difference =. delta (<i,j)}difference
                difference =. (-delta)(<j,i)}difference
            end.
            if. (n>:2)*.(ni~:0)*.nj~:0 do.
                similarity =. (((numerator%%:ni*nj)*n)%(n+Shrinkage))
                item_similarity =. similarity (<i,j)}item_similarity
                item_similarity =. similarity (<j,i)}item_similarity
            end.
        end.
    end.
    (<user_similarity),(<user_common),(<item_similarity),(<common),<difference
)
select_neighbors =: 4 : 0
    order =. /:(-1{"1 x),.0{"1 x
    (y<.#order){.order{x
)
