vadd =: +
vsub =: -
vneg =: -
vdot =: 4 : '(+/x*y)floor_div S'
vscale =: 4 : '(x*y)floor_div S'
vlength =: 3 : 'isqrt +/*:x:y'
vnorm =: 3 : '(y*S)floor_div vlength y'
