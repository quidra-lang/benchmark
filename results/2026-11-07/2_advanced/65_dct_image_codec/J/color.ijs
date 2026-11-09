clamp=:3 : '0>.255<.y'
rgb_to_planes=:3 :0
 'h w channels'=. $y
 flat=.((h*w),3)$,y
 r=.0{"1 flat
 g=.1{"1 flat
 b=.2{"1 flat
 yy=.<.(32768+(19595*r)+(38470*g)+7471*b)%65536
 cb=.<.(8421375+(_11059*r)+(_21709*g)+32768*b)%65536
 cr=.<.(8421375+(32768*r)+(_27439*g)-5329*b)%65536
 ((h,w)$yy);((h,w)$cb);(h,w)$cr
)
planes_to_rgb=:3 :0
 'yy cb cr'=.y
 cb=.cb-128
 cr=.cr-128
 r=.clamp yy+<.(32768+91881*cr)%65536
 g=.clamp yy+<.(32768+(_22554*cb)-46802*cr)%65536
 b=.clamp yy+<.(32768+116130*cb)%65536
 'h w'=. $yy
 (h,w,3)$,(,r),.(,g),.(,b)
)
build_planes=:4 :0
 codec=.x
 planes=.rgb_to_planes y
 result=.0$a:
 for_k. i.3 do.
  source=.k{::planes
  hk=.k{hs__codec
  vk=.k{vs__codec
  fx=.hmax__codec%hk
  fy=.vmax__codec%vk
  pw=.8*hk*mx__codec
  ph=.8*vk*my__codec
  plane=.(ph,pw)$0
  for_py. i.ph do.
   for_px. i.pw do.
    total=.0
    for_dy. i.fy do.
     sy=.(height__codec-1)<.(fy*py)+dy
     for_dx. i.fx do.
      sx=.(width__codec-1)<.(fx*px)+dx
      total=.total+(<sy,sx){source
     end.
    end.
    plane=.(<.total%(fx*fy))(<py,px)}plane
   end.
  end.
  result=.result,<plane
 end.
 result
)
upsample=:4 :0
 codec=.x
 result=.0$a:
 for_k. i.3 do.
  source=.k{::y
  xs=.<.((i.width__codec)*k{hs__codec)%hmax__codec
  ys=.<.((i.height__codec)*k{vs__codec)%vmax__codec
  result=.result,<xs{"1 ys{source
 end.
 result
)
