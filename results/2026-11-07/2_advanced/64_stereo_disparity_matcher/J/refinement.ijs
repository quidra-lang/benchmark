decimal =: 3 : 0
 (str <.y%100),'.',(_2{.'00',str 100|y)
)
two =: 4 : 'decimal <.((200x*x)+y)%(2x*y)'
signed_two =: 4 : 0
 t =. (|x)two y
 if. (x<0)*.-.t-:'0.00' do. '-',t else. t end.
)
lower_median =: 3 : '(<.((#y)-1)%2){/:~y'
subpixel =: 4 : 0
 'p d' =. y
 a =. 0x
 b =. 1x
 if. (d>Dmin)*.d<Dmax do.
  j =. d-Dmin
  'lo mid hi' =. (j+_1 0 1){p{x
  if. (lo>mid)*.hi>:mid do. a =. lo-hi
  b =. 2*((lo-(2*mid))+hi) end.
 end.
 q =. <.((200x*((d*b)+a))+b)%(2*b)
 (<decimal q),<(100x*(pn 'focal_length')*pn 'baseline')two q
)
