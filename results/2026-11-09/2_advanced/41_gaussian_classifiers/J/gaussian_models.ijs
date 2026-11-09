argmax =: 3 : 0
    best =. 0
    for_index. 1+i.(#y)-1 do.
        if. (index{y)>best{y do.
            best =. index
        end.
    end.
    best
)
argmin =: 3 : 0
    best =. 0
    for_index. 1+i.(#y)-1 do.
        if. (index{y)<best{y do.
            best =. index
        end.
    end.
    best
)
s_row_count =: 0&{::
s_counts =: 1&{::
s_means =: 2&{::
s_scatter =: 3&{::
s_center =: 4&{::
s_variances =: 5&{::
s_pooled =: 6&{::
class_statistics =: 3 : 0
    'rows features count' =. y
    size =. #features
    groups =. count$<(0,size)$0.0
    vectors =. (0,size)$0.0
    for_box. rows do.
        row =. >box
        vector =. features{row_values row
        vectors =. vectors,vector
        category =. row_class row
        group =. category{::groups
        groups =. (<group,vector)category}groups
    end.
    counts =. i.0
    means =. (0,size)$0.0
    scatter =. (0,size,size)$0.0
    for_category. i.count do.
        group =. category{::groups
        counts =. counts,#group
        mean =. size$0.0
        for_feature. i.size do.
            total =. ordered_sum feature{"1 group
            mean =. (total%#group)feature}mean
        end.
        means =. means,mean
        matrix =. zeros size
        for_first. i.size do.
            for_second. i.size do.
                total =. 0.0
                for_vector. group do.
                    total =. total+((first{vector)-first{mean)*((second{vector)-second{mean)
                end.
                matrix =. total (<first,second)}matrix
            end.
        end.
        scatter =. scatter,,:(matrix)
    end.
    center =. size$0.0
    variances =. size$0.0
    for_feature. i.size do.
        average =. (ordered_sum feature{"1 vectors)%#rows
        center =. average feature}center
        total =. 0.0
        for_vector. vectors do.
            delta =. (feature{vector)-average
            total =. total+delta*delta
        end.
        variances =. (total%#rows)feature}variances
    end.
    pooled =. zeros size
    for_first. i.size do.
        for_second. i.size do.
            total =. 0.0
            for_category. i.count do.
                total =. total+(<category,first,second){scatter
            end.
            pooled =. (total%((#rows)-count))(<first,second)}pooled
        end.
    end.
    (<#rows),(<counts),(<means),(<scatter),(<center),(<variances),<pooled
)
g_name =: 0&{::
g_features =: 1&{::
g_statistics =: 2&{::
g_means =: 3&{::
g_priors =: 4&{::
g_covariances =: 5&{::
g_factors =: 6&{::
g_log_determinants =: 7&{::
g_log_priors =: 8&{::
g_normalizer =: 9&{::
g_epsilon =: 10&{::
g_gamma =: 11&{::
g_max_variance =: 12&{::
g_added =: 13&{::
train_model =: 3 : 0
    'name features rows count prior_mode epsilon gamma' =. y
    stats =. class_statistics (<rows),(<features),<count
    size =. #features
    means =. s_means stats
    counts =. s_counts stats
    scatter =. s_scatter stats
    maximum_variance =. >./s_variances stats
    added =. epsilon*maximum_variance
    priors =. count$0.0
    covariances =. (0,size,size)$0.0
    factors =. (0,size,size)$0.0
    determinants =. 0$0.0
    for_category. i.count do.
        prior =. 1.0%count
        if. prior_mode-:'empirical' do.
            prior =. (0.0+category{counts)%#rows
        end.
        priors =. prior category}priors
        covariance =. zeros size
        for_first. i.size do.
            for_second. i.size do.
                value =. 0.0
                if. name-:'LDA' do.
                    value =. (<first,second){s_pooled stats
                elseif. name-:'NB' do.
                    if. first=second do.
                        value =. (((<category,first,second){scatter)%category{counts)+added
                    end.
                else.
                    value =. ((<category,first,second){scatter)%(category{counts)-1
                    if. first~:second do.
                        value =. value*(1.0-gamma)
                    end.
                end.
                covariance =. value (<first,second)}covariance
            end.
        end.
        factor =. cholesky covariance
        covariances =. covariances,,:(covariance)
        factors =. factors,,:(factor)
        determinants =. determinants,log_determinant factor
    end.
    log_priors =. ^.priors
    normalizer =. (size*^.2.0*3.141592653589793)%2.0
    (<name),(<features),(<stats),(<means),(<priors),(<covariances),(<factors),(<determinants),(<log_priors),(<normalizer),(<epsilon),(<gamma),(<maximum_variance),<added
)
squared_distances =: 4 : 0
    means =. g_means x
    factors =. g_factors x
    result =. 0$0.0
    for_category. i.#means do.
        delta =. y-category{means
        result =. result,(category{factors)quadratic delta
    end.
    result
)
model_distances =: 4 : 'x squared_distances (g_features x){y'
model_scores =: 4 : 0
    distances =. x squared_distances y
    priors =. g_log_priors x
    determinants =. g_log_determinants x
    normalizer =. g_normalizer x
    result =. 0$0.0
    for_category. i.#distances do.
        score =. (((category{priors)-normalizer)-((category{determinants)%2.0))-((category{distances)%2.0)
        result =. result,score
    end.
    result
)
predict =: 4 : 'argmax x model_scores (g_features x){y'
pred_class =: 0&{::
pred_posterior =: 1&{::
pred_log_posterior =: 2&{::
pred_confidence =: 3&{::
pred_decision =: 4&{::
infer_vector =: 4 : 0
    'point costs' =. y
    scores =. x model_scores point
    predicted =. argmax scores
    maximum =. predicted{scores
    exponentials =. ^scores-maximum
    total =. ordered_sum exponentials
    posterior =. exponentials%total
    log_posterior =. (scores-maximum)-^.total
    decision =. predicted
    if. #costs do.
        risks =. 0$0.0
        for_decided. i.#scores do.
            risk =. 0.0
            for_category. i.#scores do.
                risk =. risk+(category{posterior)*(<category,decided){costs
            end.
            risks =. risks,risk
        end.
        decision =. argmin risks
    end.
    (<predicted),(<posterior),(<log_posterior),(< >./posterior),<decision
)
infer =: 4 : 0
    'values costs' =. y
    x infer_vector (<(g_features x){values),<costs
)
