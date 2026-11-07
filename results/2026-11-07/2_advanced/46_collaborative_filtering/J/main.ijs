load 'ratings.ijs'
load 'neighborhood.ijs'
load 'factorization.ijs'
load 'evaluation.ijs'
load 'report.ijs'
Methods =: ;:'GLOBAL BASELINE USER_KNN ITEM_KNN SLOPE_ONE SVD ALS'
RankNames =: ;:'POPULAR BASELINE USER_KNN ITEM_KNN SLOPE_ONE SVD ALS'
integer =: 3 : 0
    text =. ":<.y
    '-'(I.text='_')}text
)
join =: 4 : 0
    result =. ''
    for_index. i.#y do.
        if. index do.
            result =. result,x
        end.
        result =. result,index{::y
    end.
    result
)
integers =: 3 : ''' ''join integer&.>y'
intdiv =: 4 : '<.(x: x)%x: y'
reals =: 3 : ''' ''join real_text&.>y'
title =: 3 : '(y{ItemCatalog){::Titles'
item_genres =: 3 : '(y{ItemCatalog){::Genres'
all_genres =: 3 : 0
    result =. 0$a:
    for_item. y do.
        result =. result,item_genres item
    end.
    /:~~.result
)
baseline_rmse =: 3 : 0
    'users items' =. y
    total =. 0.0
    for_row. Training do.
        'u i rating timestamp' =. row
        difference =. rating-((GlobalMean+u{users)+i{items)
        total =. total+difference*difference
    end.
    %:total%#Training
)
train_baseline =: 3 : 0
    users =. (#Users)$0.0
    items =. (#Items)$0.0
    log =. i.0
    for_sweep. i.10 do.
        for_i. i.#Items do.
            total =. 0.0
            for_u. i{::ItemRatings do.
                total =. total+(((<u,i){RatingValues)-GlobalMean)-u{users
            end.
            items =. (total%(ItemReg+i{ItemCounts))i}items
        end.
        for_u. i.#Users do.
            total =. 0.0
            for_i. u{::UserRatings do.
                total =. total+(((<u,i){RatingValues)-GlobalMean)-i{items
            end.
            users =. (total%(UserReg+u{UserCounts))u}users
        end.
        log =. log,baseline_rmse (<users),<items
    end.
    (<users),(<items),<log
)
p_value =: 0&{::
p_fallback =: 1&{::
p_count =: 2&{::
p_similarity =: 3&{::
p_top =: 4&{::
predict =: 3 : 0
    'method u i count' =. y
    value =. (GlobalMean+u{BaselineUsers)+i{BaselineItems
    fallback =. 0
    used =. 0
    average_similarity =. 0.0
    top =. _1
    select. method
    case. 0 do.
        value =. GlobalMean
    case. 2;3 do.
        candidates =. 0 3$0.0
        if. method=2 do.
            for_v. i{::ItemRatings do.
                similarity =. (<u,v){UserSimilarity
                if. (similarity~:2.0)*.similarity>MinSimilarity do.
                    candidates =. candidates,v,similarity,(<v,i){RatingValues
                end.
            end.
        else.
            for_j. u{::UserRatings do.
                similarity =. (<i,j){ItemSimilarity
                if. (similarity~:2.0)*.similarity>MinSimilarity do.
                    candidates =. candidates,j,similarity,(<u,j){RatingValues
                end.
            end.
        end.
        selected =. candidates select_neighbors count
        if. 0=#selected do.
            fallback =. 1
        else.
            numerator =. 0.0
            denominator =. 0.0
            for_candidate. selected do.
                index =. <.0{candidate
                similarity =. 1{candidate
                rating =. 2{candidate
                if. method=2 do.
                    mean =. index{UserMeans
                else.
                    mean =. index{ItemMeans
                end.
                numerator =. numerator+similarity*(rating-mean)
                denominator =. denominator+similarity
            end.
            if. method=2 do.
                mean =. u{UserMeans
            else.
                mean =. i{ItemMeans
            end.
            value =. mean+numerator%denominator
            used =. #selected
            average_similarity =. denominator%used
            top =. <.(<0,0){selected
        end.
    case. 4 do.
        numerator =. 0.0
        denominator =. 0
        for_j. u{::UserRatings do.
            common =. (<i,j){Common
            if. common>:1 do.
                deviation =. (0.0+(<i,j){Difference)%(common+Shrinkage)
                numerator =. numerator+(deviation+(<u,j){RatingValues)*common
                denominator =. denominator+common
            end.
        end.
        if. denominator=0 do.
            fallback =. 1
        else.
            value =. numerator%denominator
        end.
    case. 5 do.
        users =. 0{::SVD
        items =. 1{::SVD
        user_bias =. 2{::SVD
        item_bias =. 3{::SVD
        value =. ((GlobalMean+u{user_bias)+i{item_bias)+(u{users)factor_dot i{items
    case. 6 do.
        users =. 0{::ALS
        items =. 1{::ALS
        value =. value+(u{users)factor_dot i{items
    end.
    (<value),(<fallback),(<used),(<average_similarity),<top
)
ranked_list =: 3 : 0
    'method u' =. y
    if. (<u,method){ListCached do.
        (<u,method){::RankedLists return.
    end.
    if. method=0 do.
        items =. Popularity#~0=Popularity{u{RatingValues
    else.
        items =. I.0=u{RatingValues
        predictions =. i.0
        for_item. items do.
            prediction =. predict method,u,item,Neighbors
            predictions =. predictions,p_value prediction
        end.
        order =. /:(-predictions),.items
        items =. order{items
    end.
    RankedLists =: (<items)(<u,method)}RankedLists
    ListCached =: 1 (<u,method)}ListCached
    items
)
test_predictions =: 3 : 0
    Predicted =: (7,#Testing)$a:
    Clipped =: (7,#Testing)$0.0
    Errors =: (7,#Testing)$0.0
    lines =. <'user,item,actual,GLOBAL,BASELINE,USER_KNN,ITEM_KNN,SLOPE_ONE,SVD,ALS'
    for_t. i.#Testing do.
        'u i rating' =. t{Testing
        fields =. (<integer u{Users),(<integer i{Items),<integer rating
        for_method. i.7 do.
            prediction =. predict method,u,i,Neighbors
            value =. clip p_value prediction
            Predicted =: (<prediction)(<method,t)}Predicted
            Clipped =: value (<method,t)}Clipped
            Errors =: (value-rating)(<method,t)}Errors
            fields =. fields,<real_text value
        end.
        lines =. lines,<','join fields
    end.
    Relevant =: ((#Users),#Items)$0
    RelevantCounts =: (#Users)$0
    for_row. Testing do.
        'u i rating' =. row
        if. rating>:4 do.
            Relevant =: 1 (<u,i)}Relevant
            RelevantCounts =: (1+u{RelevantCounts)u}RelevantCounts
        end.
    end.
    Evaluated =: I.RelevantCounts>0
    lines
)
group_number =: 4 : '+/x>:y'
error_fields =: 4 : 0
    fields =. 0$a:
    for_method. i.7 do.
        selected =. x{method{Errors
        value =. 0.0
        if. #selected do.
            if. y do.
                value =. mae selected
            else.
                value =. rmse selected
            end.
        end.
        fields =. fields,<(method{::Methods),' ',value optional_real 0<#selected
    end.
    ' 'join fields
)
median =: 3 : 0
    ordered =. /:~y
    count =. #ordered
    if. 2|count do.
        (<.count%2){ordered
    else.
        left =. (<.count%2)-1
        right =. <.count%2
        ((left{ordered)+right{ordered)%2.0
    end.
)
ranked_metrics =: 3 : 0
    'u method count' =. y
    list =. (<u,method){::RankedLists
    ranking_metric (<list),(<u{Relevant),(<u{RelevantCounts),<count
)
bias_order =: 4 : 0
    if. y do.
        /:(-x),.i.#x
    else.
        /:x,.i.#x
    end.
)
evaluation_report =: 3 : 0
    sections =. 0$a:
    histogram =. 5$0
    first_time =. <./3{"1 Training
    last_time =. >./3{"1 Training
    for_row. Training do.
        value =. (2{row)-1
        histogram =. (1+value{histogram)value}histogram
    end.
    user_counts =. /:~UserCounts
    item_counts =. /:~ItemCounts
    user_pairs =. 0
    usable_users =. 0
    item_pairs =. 0
    usable_items =. 0
    slope_pairs =. 0
    for_u. i.(#Users)-1 do.
        for_v. (u+1)+i.(#Users)-u+1 do.
            value =. (<u,v){UserSimilarity
            if. value~:2.0 do.
                user_pairs =. user_pairs+1
                usable_users =. usable_users+value>MinSimilarity
            end.
        end.
    end.
    for_i. i.(#Items)-1 do.
        for_j. (i+1)+i.(#Items)-i+1 do.
            value =. (<i,j){ItemSimilarity
            if. value~:2.0 do.
                item_pairs =. item_pairs+1
                usable_items =. usable_items+value>MinSimilarity
            end.
            slope_pairs =. slope_pairs+0<(<i,j){Common
        end.
    end.
    lines =. <'data users ',(integer #Users),' items ',(integer #Items),' catalog ',(integer #CatalogIDs),' ratings ',(integer #Training),' test ',integer #Testing
    lines =. lines,<'density ',(real_text (#Training)%((#Users)*#Items)),' global_mean ',real_text GlobalMean
    lines =. lines,<'histogram ',integers histogram
    lines =. lines,<'user_ratings min ',(integer {.user_counts),' median ',(real_text median user_counts),' max ',integer {:user_counts
    lines =. lines,<'item_ratings min ',(integer {.item_counts),' median ',(real_text median item_counts),' max ',integer {:item_counts
    lines =. lines,<'timestamps first ',(integer first_time),' last ',integer last_time
    lines =. lines,<'cold_items ',integer (#CatalogIDs)-#Items
    lines =. lines,<'similarities user_pairs ',(integer user_pairs),' usable ',(integer usable_users),' item_pairs ',(integer item_pairs),' usable ',(integer usable_items),' slope_pairs ',integer slope_pairs
    sections =. sections,<lines
    training_genres =. all_genres i.#Items
    lines =. <'genre_stats'
    for_box. training_genres do.
        genre =. >box
        items =. 0
        ratings =. 0
        high =. 0
        for_i. i.#Items do.
            if. -.(<genre)e.item_genres i do.
                continue.
            end.
            items =. items+1
            ratings =. ratings+i{ItemCounts
            for_u. i{::ItemRatings do.
                high =. high+4<:(<u,i){RatingValues
            end.
        end.
        lines =. lines,<'genre ',genre,' items ',(integer items),' ratings ',(integer ratings),' high ',integer high
    end.
    sections =. sections,<lines
    lines =. <'time_buckets ',integer TimeBuckets
    for_bucket. 1+i.TimeBuckets do.
        count =. 0
        total =. 0
        users =. (#Users)$0
        for_row. Training do.
            'u i rating timestamp' =. row
            span =. (last_time-first_time)+1
            assigned =. 1+((timestamp-first_time)*TimeBuckets)intdiv span
            if. assigned=bucket do.
                count =. count+1
                total =. total+rating
                users =. 1 u}users
            end.
        end.
        mean =. 0.0
        if. count>0 do.
            mean =. (0.0+total)%count
        end.
        lines =. lines,<'bucket ',(integer bucket),' ratings ',(integer count),' users ',(integer +/users),' mean ',mean optional_real count>0
    end.
    sections =. sections,<lines
    lines =. <'rating_metrics'
    test_rmse =. i.0
    for_method. i.7 do.
        clipped_count =. 0
        fallback =. 0
        for_t. i.#Testing do.
            prediction =. (<method,t){::Predicted
            value =. p_value prediction
            clipped_count =. clipped_count+(value<1.0)+.value>5.0
            fallback =. fallback+p_fallback prediction
        end.
        value =. rmse method{Errors
        test_rmse =. test_rmse,value
        lines =. lines,<(method{::Methods),' rmse ',(real_text value),' mae ',(real_text mae method{Errors),' clipped ',(integer clipped_count),' fallback ',integer fallback
    end.
    sections =. sections,<lines
    global_total =. 0.0
    for_row. Training do.
        difference =. (2{row)-GlobalMean
        global_total =. global_total+difference*difference
    end.
    train =. (%:global_total%#Training),({:BaselineLog),0.0,0.0,0.0,({:4{::SVD),{:4{::ALS
    lines =. <'generalization'
    for_method. 0 1 5 6 do.
        lines =. lines,<(method{::Methods),' train ',(real_text method{train),' test ',(real_text method{test_rmse),' gap ',real_text (method{test_rmse)-method{train
    end.
    sections =. sections,<lines
    lines =. <'neighborhoods k ',integer Neighbors
    for_method. 2 3 do.
        with_neighbors =. 0
        count_sum =. 0
        similarity_sum =. 0.0
        for_t. i.#Testing do.
            prediction =. (<method,t){::Predicted
            if. -.p_fallback prediction do.
                with_neighbors =. with_neighbors+1
                count_sum =. count_sum+p_count prediction
                similarity_sum =. similarity_sum+p_similarity prediction
            end.
        end.
        mean_count =. 0.0
        mean_similarity =. 0.0
        if. with_neighbors>0 do.
            mean_count =. (0.0+count_sum)%with_neighbors
            mean_similarity =. similarity_sum%with_neighbors
        end.
        lines =. lines,<(method{::Methods),' predictions ',(integer #Testing),' with_neighbors ',(integer with_neighbors),' mean_neighbors ',(mean_count optional_real with_neighbors>0),' mean_similarity ',mean_similarity optional_real with_neighbors>0
    end.
    sections =. sections,<lines
    actual =. 2{"1 Testing
    actual_mean =. (0.0++/actual)%#Testing
    actual_squares =. 0.0
    for_value. actual do.
        actual_squares =. actual_squares+(value-actual_mean)*(value-actual_mean)
    end.
    actual_same =. *./actual={.actual
    lines =. <'prediction_stats actual mean ',(real_text actual_mean),' std ',real_text %:actual_squares%#Testing
    for_method. i.7 do.
        values =. method{Clipped
        total =. 0.0
        for_value. values do.
            total =. total+value
        end.
        mean =. total%#Testing
        squares =. 0.0
        cross =. 0.0
        for_t. i.#Testing do.
            value =. t{values
            squares =. squares+(value-mean)*(value-mean)
            cross =. cross+(value-mean)*((t{actual)-actual_mean)
        end.
        all_same =. *./values={.values
        defined =. (-.all_same)*.-.actual_same
        correlation =. 0.0
        if. defined do.
            correlation =. cross%%:squares*actual_squares
        end.
        lines =. lines,<(method{::Methods),' mean ',(real_text mean),' std ',(real_text %:squares%#Testing),' correlation ',correlation optional_real defined
    end.
    sections =. sections,<lines
    lines =. <'error_bins edges 0.5 1.0 1.5 2.0'
    for_method. i.7 do.
        bins =. 5$0
        for_error. method{Errors do.
            bin =. 4<.<.2.0*|error
            bins =. (1+bin{bins)bin}bins
        end.
        lines =. lines,<(method{::Methods),' ',integers bins
    end.
    sections =. sections,<lines
    lines =. <'comparison'
    for_a. i.6 do.
        for_b. (a+1)+i.7-a+1 do.
            wins =. 0
            ties =. 0
            losses =. 0
            for_t. i.#Testing do.
                first =. |(<a,t){Errors
                second =. |(<b,t){Errors
                if. first<second do.
                    wins =. wins+1
                elseif. first=second do.
                    ties =. ties+1
                else.
                    losses =. losses+1
                end.
            end.
            lines =. lines,<(a{::Methods),' ',(b{::Methods),' wins ',(integer wins),' ties ',(integer ties),' losses ',integer losses
        end.
    end.
    sections =. sections,<lines
    for_variable. i.2 do.
        if. variable=0 do.
            bounds =. UserGroups
            counts =. UserCounts
            label =. 'user'
        else.
            bounds =. ItemGroups
            counts =. ItemCounts
            label =. 'item'
        end.
        lines =. <label,'_groups bounds ',integers bounds
        for_group. i.(#bounds)+1 do.
            indices =. i.0
            for_t. i.#Testing do.
                index =. (<t,variable){Testing
                if. group=(index{counts)group_number bounds do.
                    indices =. indices,t
                end.
            end.
            if. group=0 do.
                first =. 1
            else.
                first =. (group-1){bounds
            end.
            if. group=#bounds do.
                last =. '-'
            else.
                last =. integer (group{bounds)-1
            end.
            lines =. lines,<'group ',(integer group+1),' from ',(integer first),' to ',last,' pairs ',(integer #indices),' ',indices error_fields 0
        end.
        sections =. sections,<lines
    end.
    lines =. <'by_rating'
    for_value. 1+i.5 do.
        indices =. I.value=2{"1 Testing
        lines =. lines,<'rating ',(integer value),' pairs ',(integer #indices),' ',indices error_fields 1
    end.
    sections =. sections,<lines
    test_genres =. all_genres 1{"1 Testing
    lines =. <'genres'
    for_box. test_genres do.
        genre =. >box
        indices =. i.0
        for_t. i.#Testing do.
            item =. (<t,1){Testing
            if. (<genre)e.item_genres item do.
                indices =. indices,t
            end.
        end.
        lines =. lines,<'genre ',genre,' pairs ',(integer #indices),' ',indices error_fields 0
    end.
    sections =. sections,<lines
    relevant_total =. +/Evaluated{RelevantCounts
    lines =. <'ranking users ',(integer #Evaluated),' relevant ',integer relevant_total
    for_count. Cutoffs do.
        lines =. lines,<'cutoff ',integer count
        for_method. i.7 do.
            hits =. 0
            recall =. 0.0
            ndcg =. 0.0
            ap =. 0.0
            rr =. 0.0
            hit_users =. 0
            for_u. Evaluated do.
                'h rec nd av reciprocal' =. ranked_metrics u,method,count
                hits =. hits+h
                recall =. recall+rec
                ndcg =. ndcg+nd
                ap =. ap+av
                rr =. rr+reciprocal
                hit_users =. hit_users+h>0
            end.
            users =. #Evaluated
            lines =. lines,<'  ',(method{::RankNames),' precision ',(real_text (0.0+hits)%(count*users)),' recall ',(real_text recall%users),' ndcg ',(real_text ndcg%users),' map ',(real_text ap%users),' mrr ',(real_text rr%users),' hit_rate ',real_text (0.0+hit_users)%users
        end.
    end.
    sections =. sections,<lines
    head =. <.(#Items)%5
    popular =. head{.Popularity
    lines =. <'beyond_accuracy top_n ',(integer TopN),' head ',integer head
    for_method. i.7 do.
        coverage =. (#Items)$0
        diversity =. 0
        novelty =. 0.0
        popularity =. 0
        long_tail =. 0
        similarity =. 0.0
        for_u. Evaluated do.
            list =. (<u,method){::RankedLists
            listed =. TopN{.list
            coverage =. 1 listed}coverage
            distinct_genres =. all_genres listed
            nov =. 0.0
            pair_sum =. 0.0
            for_i. listed do.
                proportion =. (0.0+#Users)%i{ItemCounts
                nov =. nov+2^.proportion
                popularity =. popularity+i{ItemCounts
                long_tail =. long_tail+-.i e.popular
            end.
            diversity =. diversity+#distinct_genres
            novelty =. novelty+nov%TopN
            for_a. i.TopN-1 do.
                for_b. (a+1)+i.TopN-a+1 do.
                    value =. (<(a{list),(b{list)){ItemSimilarity
                    if. value=2.0 do.
                        value =. 0.0
                    end.
                    pair_sum =. pair_sum+value
                end.
            end.
            pair_count =. <.(TopN*(TopN-1))%2
            similarity =. similarity+pair_sum%pair_count
        end.
        users =. #Evaluated
        lines =. lines,<(method{::RankNames),' coverage ',(real_text (0.0++/coverage)%#Items),' diversity ',(real_text (0.0+diversity)%users),' novelty ',(real_text novelty%users),' popularity ',(real_text (0.0+popularity)%(TopN*users)),' long_tail ',(real_text (0.0+long_tail)%(TopN*users)),' similarity ',real_text similarity%users
    end.
    sections =. sections,<lines
    lines =. <'ranking_groups top_n ',(integer TopN),' bounds ',integers UserGroups
    for_group. i.(#UserGroups)+1 do.
        users =. i.0
        for_u. Evaluated do.
            if. group=(u{UserCounts)group_number UserGroups do.
                users =. users,u
            end.
        end.
        fields =. <'group ',(integer group+1),' users ',integer #users
        for_method. i.7 do.
            total =. 0.0
            for_u. users do.
                metric =. ranked_metrics u,method,TopN
                total =. total+2{::metric
            end.
            mean =. 0.0
            if. #users do.
                mean =. total%#users
            end.
            fields =. fields,<(method{::RankNames),' ',mean optional_real 0<#users
        end.
        lines =. lines,<' 'join fields
    end.
    sections =. sections,<lines
    lines =. <'agreement top_n ',integer TopN
    for_a. i.6 do.
        for_b. (a+1)+i.7-a+1 do.
            total =. 0.0
            for_u. Evaluated do.
                first =. TopN{.(<u,a){::RankedLists
                second =. TopN{.(<u,b){::RankedLists
                intersection =. +/first e.second
                total =. total+(0.0+intersection)%((2*TopN)-intersection)
            end.
            lines =. lines,<(a{::RankNames),' ',(b{::RankNames),' jaccard ',real_text total%#Evaluated
        end.
    end.
    sections =. sections,<lines
    lines =. <'neighbor_grid'
    best_k =. 2$_1
    best_error =. 2$0.0
    for_count. NeighborGrid do.
        fields =. <'k ',integer count
        for_index. i.2 do.
            method =. index+2
            errors =. i.0
            for_row. Testing do.
                'u i rating' =. row
                prediction =. predict method,u,i,count
                errors =. errors,(clip p_value prediction)-rating
            end.
            value =. rmse errors
            fields =. fields,<(method{::Methods),' ',real_text value
            if. ((index{best_k)<0)+.value<index{best_error do.
                best_k =. count index}best_k
                best_error =. value index}best_error
            end.
        end.
        lines =. lines,<' 'join fields
    end.
    lines =. lines,<'best USER_KNN ',(integer 0{best_k),' ITEM_KNN ',integer 1{best_k
    sections =. sections,<lines
    lines =. <'biases'
    kinds =. ;:'item_high item_low user_high user_low'
    for_kind. i.4 do.
        if. kind<2 do.
            ids =. Items
            biases =. BaselineItems
            counts =. ItemCounts
            means =. ItemMeans
        else.
            ids =. Users
            biases =. BaselineUsers
            counts =. UserCounts
            means =. UserMeans
        end.
        order =. biases bias_order 0=2|kind
        for_index. ListSize{.order do.
            line =. (kind{::kinds),' ',(integer index{ids),' bias ',(real_text index{biases),' count ',(integer index{counts),' mean ',real_text index{means
            if. kind<2 do.
                line =. line,' ',title index
            end.
            lines =. lines,<line
        end.
    end.
    sections =. sections,<lines
    output =. 0$a:
    for_index. i.#sections do.
        if. index do.
            output =. output,<''
        end.
        output =. output,index{::sections
    end.
    output
)
preferred_genres =: 3 : 0
    'u liked' =. y
    all =. all_genres u{::UserRatings
    counts =. (#all)$0
    for_index. i.#all do.
        genre =. index{all
        count =. 0
        for_item. u{::UserRatings do.
            rating =. (<u,item){RatingValues
            qualifies =. (liked*.rating>:4)+.(-.liked)*.rating<:2
            if. qualifies*.genre e.item_genres item do.
                count =. count+1
            end.
        end.
        counts =. count index}counts
    end.
    present =. I.counts>0
    order =. /:(-present{counts),.present
    selected =. (3<.#present){.order{present
    names =. selected{all
    fields =. 0$a:
    for_index. selected do.
        fields =. fields,<(index{::all),' ',integer index{counts
    end.
    if. #fields do.
        text =. ' 'join fields
    else.
        text =. '-'
    end.
    (<names),<text
)
popular_line =: 3 : 0
    'rank item' =. y
    '  ',(integer rank),' ',(integer item{Items),' count ',(integer item{ItemCounts),' mean ',(real_text item{ItemMeans),' ',title item
)
recommendations_report =: 3 : 0
    output =. 0$a:
    for_request. i.#RecommendUsers do.
        id =. request{RecommendUsers
        u =. Users i.id
        if. request do.
            output =. output,<''
        end.
        if. u=#Users do.
            output =. output,(<'user ',(integer id),' unknown'),<'list POPULAR'
            for_rank. i.TopN do.
                output =. output,<popular_line (rank+1),rank{Popularity
            end.
            continue.
        end.
        output =. output,<'user ',(integer id),' ratings ',(integer u{UserCounts),' mean ',(real_text u{UserMeans),' bias ',real_text u{BaselineUsers
        'liked liked_text' =. preferred_genres u,1
        'disliked disliked_text' =. preferred_genres u,0
        output =. output,(<'liked_genres ',liked_text),<'disliked_genres ',disliked_text
        recent =. Training#~u=0{"1 Training
        order =. /:(-3{"1 recent),.1{"1 recent
        fields =. <'recent'
        for_index. (3<.#order){.order do.
            row =. index{recent
            fields =. fields,<(integer (1{row){Items),' ',integer 2{row
        end.
        output =. output,<' 'join fields
        candidates =. 0 3$0.0
        for_v. i.#Users do.
            value =. (<u,v){UserSimilarity
            if. (value~:2.0)*.value>MinSimilarity do.
                candidates =. candidates,v,value,0
            end.
        end.
        for_neighbor. candidates select_neighbors ListSize do.
            v =. <.0{neighbor
            output =. output,<'neighbor ',(integer v{Users),' similarity ',(real_text 1{neighbor),' common ',integer (<u,v){UserCommon
        end.
        for_t. i.#Testing do.
            row =. t{Testing
            if. u~:0{row do.
                continue.
            end.
            fields =. <'heldout ',(integer (1{row){Items),' actual ',integer 2{row
            for_method. i.7 do.
                fields =. fields,<real_text (<method,t){Clipped
            end.
            output =. output,<' 'join fields
        end.
        for_method. i.7 do.
            list =. (<u,method){::RankedLists
            genre_match =. 0
            for_item. TopN{.list do.
                genre_match =. genre_match+1 e.(item_genres item)e.liked
            end.
            output =. output,<'list ',(method{::RankNames),' genre_match ',integer genre_match
            for_rank. i.TopN do.
                item =. rank{list
                if. method=0 do.
                    line =. popular_line (rank+1),item
                else.
                    prediction =. predict method,u,item,Neighbors
                    line =. '  ',(integer rank+1),' ',(integer item{Items),' ',real_text p_value prediction
                    if. method e.2 3 do.
                        top =. p_top prediction
                        if. top<0 do.
                            top_text =. '-'
                        elseif. method=2 do.
                            top_text =. integer top{Users
                        else.
                            top_text =. integer top{Items
                        end.
                        line =. line,' via ',top_text
                    end.
                    line =. line,' ',title item
                end.
                output =. output,<line
            end.
        end.
    end.
    output
)
similar_items_report =: 3 : 0
    output =. 0$a:
    factors =. 1{::SVD
    for_request. i.#SimilarItems do.
        id =. request{SimilarItems
        i =. Items i.id
        if. request do.
            output =. output,<''
        end.
        output =. output,<'item ',(integer id),' ratings ',(integer i{ItemCounts),' mean ',(real_text i{ItemMeans),' bias ',(real_text i{BaselineItems),' genres ',((i{ItemCatalog){::GenreTexts),' title ',title i
        similarity_rows =. 0 3$0.0
        factor_rows =. 0 2$0.0
        common_rows =. 0 2$0
        slope_rows =. 0 4$0.0
        for_j. i.#Items do.
            if. j=i do.
                continue.
            end.
            value =. (<i,j){ItemSimilarity
            count =. (<i,j){Common
            if. value~:2.0 do.
                similarity_rows =. similarity_rows,j,value,count
            end.
            first =. i{factors
            second =. j{factors
            cosine =. (first factor_dot second)%%:((first factor_dot first)*(second factor_dot second))
            factor_rows =. factor_rows,j,cosine
            if. count>:1 do.
                common_rows =. common_rows,j,count
                difference =. (<j,i){Difference
                deviation =. (0.0+difference)%(count+Shrinkage)
                slope_rows =. slope_rows,j,deviation,count,difference
            end.
        end.
        similarity_order =. /:(-1{"1 similarity_rows),.0{"1 similarity_rows
        factor_order =. /:(-1{"1 factor_rows),.0{"1 factor_rows
        common_order =. /:(-1{"1 common_rows),.0{"1 common_rows
        slope_order =. /:(-1{"1 slope_rows),.(-2{"1 slope_rows),.0{"1 slope_rows
        output =. output,<'cosine'
        for_rank. i.ListSize<.#similarity_order do.
            row =. (rank{similarity_order){similarity_rows
            j =. <.0{row
            output =. output,<'  ',(integer rank+1),' ',(integer j{Items),' similarity ',(real_text 1{row),' common ',(integer 2{row),' ',title j
        end.
        output =. output,<'factors'
        for_rank. i.ListSize<.#factor_order do.
            row =. (rank{factor_order){factor_rows
            j =. <.0{row
            output =. output,<'  ',(integer rank+1),' ',(integer j{Items),' similarity ',(real_text 1{row),' ',title j
        end.
        output =. output,<'co_rated'
        for_rank. i.ListSize<.#common_order do.
            row =. (rank{common_order){common_rows
            j =. <.0{row
            output =. output,<'  ',(integer rank+1),' ',(integer j{Items),' common ',(integer 1{row),' ',title j
        end.
        output =. output,<'slope_one'
        for_rank. i.ListSize<.#slope_order do.
            row =. (rank{slope_order){slope_rows
            j =. <.0{row
            output =. output,<'  ',(integer rank+1),' ',(integer j{Items),' difference ',(integer 3{row),' common ',(integer 2{row),' ',title j
        end.
    end.
    output
)
training_log =: 3 : 0
    names =. ;:'BASELINE SVD ALS'
    logs =. (<BaselineLog),(<4{::SVD),<4{::ALS
    lines =. <'method,epoch,train_rmse'
    for_method. i.3 do.
        log =. method{::logs
        for_epoch. i.#log do.
            lines =. lines,<(method{::names),',',(integer epoch+1),',',real_text epoch{log
        end.
    end.
    lines
)
run =: 3 : 0
    read_inputs 0
    'BaselineUsers BaselineItems BaselineLog' =: train_baseline 0
    SVD =: train_svd 0
    ALS =: train_als (<BaselineUsers),<BaselineItems
    'UserSimilarity UserCommon ItemSimilarity Common Difference' =: build_neighborhood 0
    Popularity =: /:(-ItemCounts),.(-ItemMeans),.i.#Items
    RankedLists =: ((#Users),7)$a:
    ListCached =: ((#Users),7)$0
    prediction_csv =. test_predictions 0
    users =. Evaluated
    for_id. RecommendUsers do.
        u =. Users i.id
        if. (u<#Users)*.-.u e.users do.
            users =. users,u
        end.
    end.
    for_u. users do.
        for_method. i.7 do.
            ranked_list method,u
        end.
    end.
    try.
        1!:5 <'output'
    catch.
    end.
    'predictions.csv' save_lines prediction_csv
    'evaluation.txt' save_lines evaluation_report 0
    'recommendations.txt' save_lines recommendations_report 0
    'similar_items.txt' save_lines similar_items_report 0
    'training_log.csv' save_lines training_log 0
)
run 0
