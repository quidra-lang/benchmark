PI =: 3.141592653589793
k_transition =: 3 : 0
    'model t' =. y
    size =. 4
    if. model-:'CA' do. size =. 6 end.
    matrix =. m_identity size
    matrix =. t(<0,2)}matrix
    matrix =. t(<1,3)}matrix
    if. size=6 do.
        matrix =. ((t*t)%2)(<0,4)}matrix
        matrix =. ((t*t)%2)(<1,5)}matrix
        matrix =. t(<2,4)}matrix
        matrix =. t(<3,5)}matrix
    end.
    matrix
)
k_noise =: 3 : 0
    'model t q' =. y
    qt =. q*t
    qt2 =. qt*t
    qt3 =. qt2*t
    size =. 4
    entries =. (0,0,qt3%3),(0,2,qt2%2),:2,2,qt
    if. model-:'CA' do.
        size =. 6
        qt4 =. qt3*t
        qt5 =. qt4*t
        entries =. (0,0,qt5%20),(0,2,qt4%8),(0,4,qt3%6),(2,2,qt3%3),(2,4,qt2%2),:4,4,qt
    end.
    matrix =. (size,size)$0.0
    for_axis. i.2 do.
        for_entry. entries do.
            'first second value' =. entry
            matrix =. value(<(first+axis),second+axis)}matrix
            matrix =. value(<(second+axis),first+axis)}matrix
        end.
    end.
    matrix
)
k_new =: 3 : 0
    'model q measurement' =. y
    size =. 4
    if. model-:'CA' do. size =. 6 end.
    state =. measurement,(size-2)$0.0
    variances =. (2$MeasurementSigma*MeasurementSigma),2$VelocityVariance
    if. size=6 do. variances =. variances,2$AccelerationVariance end.
    covariance =. m_diagonal variances
    h =. (2,size)$0.0
    h =. 1.0(<0,0)}h
    h =. 1.0(<1,1)}h
    r =. m_diagonal 2$MeasurementSigma*MeasurementSigma
    (<model),(<q),(<state),(<covariance),(<h),(<r),(<state),(<covariance),<m_identity size
)
k_predict =: 4 : 0
    model =. 0{::y
    q =. 1{::y
    transition =. k_transition (<model),<x
    noise =. k_noise (<model),(<x),<q
    state =. transition m_vector 2{::y
    covariance =. ((transition m_product 3{::y)m_product m_transpose transition)+noise
    result =. (<state)2}y
    result =. (<covariance)3}result
    result =. (<state)6}result
    result =. (<covariance)7}result
    (<transition)8}result
)
k_innovation =: 4 : 0
    h =. 4{::y
    covariance =. 3{::y
    residual =. x-h m_vector 2{::y
    s =. ((h m_product covariance)m_product m_transpose h)+5{::y
    precision =. m_inverse s
    d2 =. residual m_quadratic2 precision
    (<residual),(<s),(<precision),<d2
)
k_update =: 4 : 0
    'residual s precision d2' =. x k_innovation y
    h =. 4{::y
    r =. 5{::y
    covariance =. 3{::y
    gain =. (covariance m_product m_transpose h)m_product precision
    correction =. (m_identity #2{::y)-gain m_product h
    state =. (2{::y)+gain m_vector residual
    first =. (correction m_product covariance)m_product m_transpose correction
    second =. (gain m_product r)m_product m_transpose gain
    covariance =. first+second
    updated =. (<state)2}y
    updated =. (<covariance)3}updated
    likelihood =. ((-^.2*PI)-(^.m_determinant2 s)%2)-d2%2
    (<updated),(<d2),(<likelihood),<s
)
k_snapshot =: 3 : '2 3 6 7 8{y'
k_smooth =: 3 : 0
    states =. (#y)$<i.0
    last =. (#y)-1
    states =. (<0{::last{::y)last}states
    for_i. |.i.last do.
        current =. i{::y
        following =. (i+1){::y
        gain =. ((1{::current)m_product m_transpose 4{::following)m_product m_inverse 3{::following
        difference =. ((i+1){::states)-2{::following
        state =. (0{::current)+gain m_vector difference
        states =. (<state)i}states
    end.
    states
)
