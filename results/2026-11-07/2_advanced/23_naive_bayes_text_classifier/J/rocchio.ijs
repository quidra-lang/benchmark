vector_length =: 3 : 0
    total =. 0.0
    for_value. y do. total =. total+value*value end.
    %:total
)
tfidf_vector =: 4 : 0
    counts =. (#x)$0
    for_term. y do. counts =. (1+term{counts)term}counts end.
    counts*x
)
train_rocchio =: 4 : 0
    'sequences labels' =. y
    idf =. ^.(#sequences)%x
    size =. #x
    centroids =. (ClassCount,size)$0.0
    documents =. ClassCount$0
    for_index. i.#sequences do.
        label =. index{labels
        documents =. (1+label{documents)label}documents
        vector =. idf tfidf_vector index{::sequences
        length =. vector_length vector
        if. length>0 do.
            for_term. i.size do.
                centroids =. (((<label,term){centroids)+(term{vector)%length)(<label,term)}centroids
            end.
        end.
    end.
    lengths =. 0$0.0
    for_label. i.ClassCount do.
        row =. (label{centroids)%label{documents
        centroids =. row label}centroids
        lengths =. lengths,vector_length row
    end.
    (<idf),(<centroids),<lengths
)
predict_rocchio =: 4 : 0
    'idf centroids lengths' =. x
    vector =. idf tfidf_vector y
    length =. vector_length vector
    similarities =. 0$0.0
    for_label. i.ClassCount do.
        value =. 0.0
        if. (length>0)*.(label{lengths)>0 do.
            product =. 0.0
            for_term. i.#idf do. product =. product+(term{vector)*(<label,term){centroids end.
            value =. product%(length*label{lengths)
        end.
        similarities =. similarities,value
    end.
    ranking =. /:(-similarities),.i.ClassCount
    label =. {.ranking
    (<label),(<label{similarities),(<ranking),(<similarities),(<0$0.0),(<0.0),(<0.0),<1{ranking
)
