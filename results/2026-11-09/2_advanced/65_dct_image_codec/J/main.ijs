ScriptPath=: >{:4!:3''
SourceDirectory=: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
load SourceDirectory,'image_io.ijs'
load SourceDirectory,'color.ijs'
load SourceDirectory,'dct.ijs'
load SourceDirectory,'entropy.ijs'
load SourceDirectory,'bitstream.ijs'
big2=:256 256&#:
new_codec=:3 :0
 'w h hs vs ri'=.y
 c=.cocreate''
 width__c=:w
 height__c=:h
 hs__c=:hs
 vs__c=:vs
 hmax__c=:>./hs
 vmax__c=:>./vs
 mx__c=:>.w%8*hmax__c
 my__c=:>.h%8*vmax__c
 restart__c=:ri
 intervals__c=:1
 if. ri>0 do. intervals__c=:>.(mx__c*my__c)%ri end.
 quantids__c=:dcids__c=:acids__c=:0 1 1
 identifiers__c=:1 2 3
 quants__c=:4$a:
 tables__c=:8$a:
 blocks__c=:0$a:
 for_m. i.mx__c*my__c do.
  for_k. i.3 do.
   for_v. i.k{vs do.
    for_h. i.k{hs do.
     b=.cocreate''
     component__b=:k
     mcu__b=:m
     bx__b=:((k{hs)*(mx__c|m))+h
     by__b=:((k{vs)*<.m%mx__c)+v
     z__b=:64$0
     symbols__b=:0 4$0
     diff__b=:bits__b=:sse__b=:0
     original__b=:8 8$128
     blocks__c=:blocks__c,b
    end.
   end.
  end.
 end.
 c
)
interval_mcus=:4 :0
 c=.x
 first=.0
 count=.mx__c*my__c
 if. restart__c>0 do. first=.y*restart__c [ count=.restart__c<.count-first end.
 first,count
)
build_symbols=:3 :0
 c=.y
 frequencies__c=:8 256$0
 predictor=.3$0
 lastm=._1
 for_b. blocks__c do.
  k=.component__b
  m=.mcu__b
  if. m~:lastm do.
   if. restart__c>0 do. if. 0=restart__c|m do. predictor=.3$0 end. end.
   lastm=.m
  end.
  id=.k~:0
  z=.z__b
  difference=.(0{z)-k{predictor
  diff__b=:difference
  predictor=:(0{z)k}predictor
  cat=.category difference
  syms=.1 4$id,cat,cat,extra_value difference
  run=.0
  for_i. 1+i.63 do.
   value=.i{z
   if. value=0 do. run=.run+1
   else.
    while. run>:16 do. syms=.syms,(id+4),240,0,0 [ run=.run-16 end.
    cat=.category value
    syms=.syms,(id+4),((16*run)+cat),cat,extra_value value
    run=.0
   end.
  end.
  if. run>0 do. syms=.syms,(id+4),0,0,0 end.
  symbols__b=:syms
  for_symbol. syms do.
   'table value cat extra'=.symbol
   frequencies__c=:(1+(<table,value){frequencies__c)(<table,value)}frequencies__c
  end.
 end.
)
segment=:4 : '255,x,(big2 2+#y),y'
make_header=:3 :0
 c=.y
 q0=.0{::quants__c
 q1=.1{::quants__c
 header=.255 216,(219 segment 0,q0,1,q1)
 sof=.8,(big2 height__c),(big2 width__c),3,1,((16*0{hs__c)+0{vs__c),0,2,17,1,3,17,1
 header=.header,192 segment sof
 dht=.i.0
 for_slot. 0 4 1 5 do.
  t=.slot{tables__c
  cls=.<.slot%4
  id=.4|slot
  dht=.dht,((16*cls)+id),counts__t,values__t
 end.
 header=.header,196 segment dht
 if. restart__c>0 do. header=.header,221 segment big2 restart__c end.
 header,255 218 0 12 3 1 0 2 17 3 17 0 63 0
)
encode_coefficients=:4 :0
 mode=.x
 c=.y
 build_symbols c
 tables__c=:StandardTables
 if. mode-:'optimized' do.
  for_slot. 0 4 1 5 do. tables__c=:(optimized_table slot{frequencies__c)slot}tables__c end.
 end.
 header=.make_header c
 headerbytes__c=:#header
 bit_writer''
 intervaldata__c=:0$a:
 for_j. i.intervals__c do.
  'first count'=.c interval_mcus j
  start=.#Written
  for_b. blocks__c do.
   if. (mcu__b<first)+.mcu__b>:first+count do. continue. end.
   bits__b=:0
   for_symbol. symbols__b do.
    'slot value cat extra'=.symbol
    t=.slot{tables__c
    length=.value{lengths__t
    length write_bits value{codes__t
    cat write_bits extra
    bits__b=:bits__b+length+cat
   end.
  end.
  pad_bits''
  intervaldata__c=:intervaldata__c,<j,first,count,(headerbytes__c+start),(#Written)-start
  if. j<intervals__c-1 do. append_marker 208+8|j end.
 end.
 padding__c=:PaddingBits
 stuffed__c=:StuffedBytes
 scanbytes__c=:#Written
 bytes__c=:header,Written,255 217
 c
)
encode=:4 :0
 image=.x
 'quality sampling mode ri'=.y
 'h w channels'=. $image
 hs=.1 1 1
 vs=.1 1 1
 if. -.sampling-:'444' do. hs=.2 1 1 end.
 if. sampling-:'420' do. vs=.2 1 1 end.
 c=.new_codec w;h;hs;vs;ri
 quants__c=:(quantization_tables quality),2$a:
 planes=.c build_planes image
 sourceplanes__c=:planes
 for_b. blocks__c do.
  k=.component__b
  pixels=.(bx__b,by__b)block_pixels k{::planes
  original__b=:pixels
  z__b=:((k~:0){::quants__c)quantize dct_forward pixels
 end.
 mode encode_coefficients c
)
materialize=:3 :0
 c=.y
 planes=.0$a:
 for_k. i.3 do.
  pw=.8*(k{hs__c)*mx__c
  ph=.8*(k{vs__c)*my__c
  planes=.planes,<(ph,pw)$128
 end.
 for_b. blocks__c do.
  k=.component__b
  quant=.(k{quantids__c){::quants__c
  pixels=.dct_inverse quant dequantize z__b
  sse__b=:+/, *:pixels-original__b
  plane=.k{::planes
  plane=.(plane;bx__b;by__b)put_block pixels
  planes=:(<plane)k}planes
 end.
 componentplanes__c=:planes
 decodedplanes__c=:c upsample planes
 image__c=:planes_to_rgb decodedplanes__c
 c
)
decode_block=:4 :0
 c=.x
 b=.y
 k=.component__b
 dctable=.(k{dcids__c){tables__c
 actable=.(4+k{acids__c){tables__c
 category=.read_symbol dctable
 diff=.category receive_extend read_bits category
 Predictors=:((k{Predictors)+diff)k}Predictors
 z=.64$0
 z=:(k{Predictors)0}z
 index=.1
 while. index<64 do.
  symbol=.read_symbol actable
  if. symbol=0 do. break. end.
  run=.<.symbol%16
  cat=.16|symbol
  index=.index+run
  if. index>63 do. read_error 'index' end.
  if. cat>0 do. z=:(cat receive_extend read_bits cat)index}z end.
  index=.index+1
 end.
 z
)
segment_name=:3 :0
 select. y
 case. 192 do. 'SOF0'
 case. 196 do. 'DHT'
 case. 219 do. 'DQT'
 case. 221 do. 'DRI'
 case. 218 do. 'SOS'
 case. 254 do. 'COM'
 case. do. 'APP',dec y-224
 end.
)
decode=:3 :0
 bytes=.y
 quants=.4$a:
 tables=.8$a:
 ri=.0
 p=.2
 segments=.,<0;'SOI';0
 while. 1 do.
  marker=.(p+1){bytes
  length=.256#.(p+2 3){bytes
  data=.(length-2){.(p+4)}.bytes
  segments=.segments,<p;(segment_name marker);length
  p=.p+length+2
  select. marker
  case. 219 do.
   for_i. 65*i.(#data)%65 do.
    id=.i{data
    quants=:(<64{.(i+1)}.data)id}quants
   end.
  case. 196 do.
   pos=.0
   while. pos<#data do.
    selector=.pos{data
    cls=.<.selector%16
    id=.16|selector
    counts=.16{.(pos+1)}.data
    values=.(+/counts){.(pos+17)}.data
    tables=:(huffman_table counts;values)((4*cls)+id)}tables
    pos=.pos+17+#values
   end.
  case. 192 do.
   height=.256#.1 2{data
   width=.256#.3 4{data
   hs=.vs=.qids=.identifiers=.i.0
   for_i. 6+3*i.3 do.
    identifiers=.identifiers,i{data
    factor=.(i+1){data
    hs=.hs,<.factor%16
    vs=.vs,16|factor
    qids=.qids,(i+2){data
   end.
  case. 221 do. ri=.256#.data
  case. 218 do.
   dcids=.acids=.i.0
   for_i. 1+2*i.3 do.
    selector=.(i+1){data
    dcids=.dcids,<.selector%16
    acids=.acids,16|selector
   end.
   break.
  end.
 end.
 c=.new_codec width;height;hs;vs;ri
 identifiers__c=:identifiers
 quantids__c=:qids
 dcids__c=:dcids
 acids__c=:acids
 quants__c=:quants
 tables__c=:tables
 segments__c=:segments,<((#bytes)-2);'EOI';0
 headerbytes__c=:p
 scanbytes__c=:(#bytes)-2+p
 ReadBytes=:bytes
 ReadPosition=:p
 ReadBuffer=:i.0
 states__c=:(intervals__c)$<'lost'
 j=.0
 while. j<intervals__c do.
  Predictors=:3$0
  'first count'=.c interval_mcus j
  trial=.0$a:
  currentm=.first
  try.
   for_b. blocks__c do.
    if. (mcu__b<first)+.mcu__b>:first+count do. continue. end.
    currentm=.mcu__b
    trial=.trial,<c decode_block b
   end.
   ReadBuffer=:i.0
   expected=.217
   if. j<intervals__c-1 do. expected=.208+8|j end.
   if. (255~:ReadPosition{bytes)+.expected~:(ReadPosition+1){bytes do. read_error 'sync' end.
   pidx=.0
   for_b. blocks__c do.
    if. (mcu__b>:first)*.mcu__b<first+count do.
     z__b=:pidx{::trial
     pidx=.pidx+1
    end.
   end.
   states__c=:(<'ok')j}states__c
   ReadPosition=:ReadPosition+2
   j=.j+1
  catch.
   offset=.ReadPosition
   q=.resynchronize offset
   text=.'damaged ',DecodeError,' mcu ',(dec currentm),' offset ',(dec offset),' resync ',dec q
   states__c=:(<text)j}states__c
   ReadBuffer=:i.0
   marker=.(q+1){bytes
   if. marker=217 do. break. end.
   next=.j+1+8|(marker-208)-j
   ReadPosition=:q+2
   j=.next
  end.
 end.
 bytes__c=:bytes
 materialize c
)
psnr=:4 :0
 error=.+/ *:,x-y
 if. error=0 do. 'inf' return. end.
 value=.10*(^.65025*(#,x)%error)%^.10
 cents=.<.0.5+100*value
 (dec <.cents%100),'.','0123456789'{~10 10#:100|cents
)
metrics=:4 :0
 original=.x
 decoded=.y
 originals=.rgb_to_planes original
 result=.0$a:
 for_k. i.3 do. result=.result,<(k{::originals)psnr k{::decodedplanes__decoded end.
 result=.result,<(original psnr image__decoded)
 result,<dec >./|,original-image__decoded
)
bpp=:4 :0
 numerator=.8*x
 denominator=.y
 divisor=.numerator+.denominator
 (dec numerator%divisor),'/',dec denominator%divisor
)
thumbnail=:3 :0
 c=.y
 tw=.>.width__c%8
 th=.>.height__c%8
 planes=.0$a:
 for_k. i.3 do.
  plane=.(th,tw)$0
  q=.(k{quantids__c){::quants__c
  for_y. i.th do.
   for_x. i.tw do.
    bx=.<.(x*k{hs__c)%hmax__c
    by=.<.(y*k{vs__c)%vmax__c
    dc=.0
    for_b. blocks__c do.
     if. (component__b=k)*.(bx__b=bx)*.by__b=by do. dc=.0{z__b [ break. end.
    end.
    value=.clamp 128+<.(4+dc*0{q)%8
    plane=.value(<y,x)}plane
   end.
  end.
  planes=.planes,<plane
 end.
 planes_to_rgb planes
)
truncated_y=:4 :0
 keep=.x
 c=.y
 plane=.((8*my__c*0{vs__c),(8*mx__c*0{hs__c))$128
 q=.(0{quantids__c){::quants__c
 for_b. blocks__c do.
  if. component__b~:0 do. continue. end.
  z=.(keep{.z__b),(64-keep)$0
  pixels=.dct_inverse q dequantize z
  plane=.(plane;bx__b;by__b)put_block pixels
 end.
 (i.width__c){"1 (i.height__c){plane
)
repair=:3 :0
 source=.y
 c=.new_codec width__source;height__source;hs__source;vs__source;restart__source
 q0=.(0{quantids__source){::quants__source
 q1=.(1{quantids__source){::quants__source
 quants__c=:q0;q1;a:;a:
 for_i. i.#blocks__c do.
  a=.i{blocks__c
  b=.i{blocks__source
  z__a=:z__b
 end.
 'optimized'encode_coefficients c
)
reference_reports=:4 :0
 encoding=.x
 decoded=.y
 c=.encoding
 w=.width__c
 h=.height__c
 blockcounts=.3$0
 symbolcounts=.+/"1 frequencies__c
 nonzero=.64$0
 zeroac=.0
 componentbits=.componentsse=.componentnz=.3$0
 blocks=.,<'blocks ',dec #blocks__c
 for_i. i.#blocks__c do.
  b=.i{blocks__c
  k=.component__b
  source=.i{blocks__decoded
  z=.z__b
  q=.(k~:0){::quants__c
  pixels=.dct_inverse q dequantize z
  sse=.+/ *:,pixels-original__b
  nonzero=.nonzero+z~:0
  nz=.+/0~:}.z
  if. nz=0 do. zeroac=.zeroac+1 end.
  last=.0
  if. +/z~:0 do. last=.{:I.z~:0 end.
  blockcounts=.(1+k{blockcounts)k}blockcounts
  componentbits=.(bits__b+k{componentbits)k}componentbits
  componentsse=.(sse+k{componentsse)k}componentsse
  componentnz=.((+/z~:0)+k{componentnz)k}componentnz
  blocks=.blocks,<'block ',(dec i),' ',(k{::'Y';'Cb';'Cr'),' ',(dec bx__b),' ',(dec by__b),' dc ',(dec 0{z),' diff ',(dec diff__b),' nonzero ',(dec nz),' last ',(dec last),' bits ',(dec bits__b),' sse ',dec sse
 end.
 'output/blocks.txt'write_lines blocks
 tablelines=.0$a:
 names=.'dc_luma';'ac_luma';'dc_chroma';'ac_chroma'
 for_i. i.4 do.
  slot=.i{0 4 1 5
  t=.slot{tables__c
  frequencies=.slot{frequencies__c
  codebits=.+/frequencies*lengths__t
  tablelines=.tablelines,<'table ',(i{::names),' class ',(dec <.slot%4),' id ',(dec 4|slot),' symbols ',(dec #values__t),' coded ',(dec +/frequencies),' bits ',dec codebits
  tablelines=.tablelines,<'counts ',numbers counts__t
  for_v. values__t do.
   length=.v{lengths__t
   bits=.'01'{~(length$2)#:v{codes__t
   hex=.'0123456789abcdef'{~16 16#:v
   tablelines=.tablelines,<'symbol ',hex,' length ',(dec length),' code ',bits,' count ',dec v{frequencies
  end.
 end.
 'output/huffman_tables.txt'write_lines tablelines
 result=.0$a:
 result=.result,<'image ',(dec w),' ',dec h
 result=.result,<'sampling ',Sampling,' mcu ',(dec 8*hmax__c),' ',(dec 8*vmax__c),' grid ',(dec mx__c),' ',dec my__c
 result=.result,<'padded ',(dec 8*hmax__c*mx__c),' ',dec 8*vmax__c*my__c
 result=.result,<'blocks ',numbers blockcounts
 result=.result,<'restart_interval ',(dec restart__c),' markers ',dec intervals__c-1
 result=.result,<'huffman ',HuffmanMode
 result=.result,<'quality ',dec {.Qualities
 result=.result,<'quant 0 ',numbers 0{::quants__c
 result=.result,<'quant 1 ',numbers 1{::quants__c
 result=.result,<'symbols ',numbers 0 4 1 5{symbolcounts
 eob=.+/0{"1 4 5{frequencies__c
 zrl=.+/240{"1 4 5{frequencies__c
 result=.result,<'eob ',(dec eob),' zrl ',dec zrl
 result=.result,<'zero_ac_blocks ',dec zeroac
 result=.result,<'nonzero ',numbers nonzero
 for_k. i.3 do.
  result=.result,<'component ',(k{::'Y';'Cb';'Cr'),' bits ',(dec k{componentbits),' nonzero ',(dec k{componentnz),' sse ',dec k{componentsse
 end.
 result=.result,<'padding_bits ',dec padding__c
 result=.result,<'stuffed_bytes ',dec stuffed__c
 result=.result,<'header_bytes ',dec headerbytes__c
 result=.result,<'scan_bytes ',dec scanbytes__c
 result=.result,<'total_bytes ',dec #bytes__c
 for_row. intervaldata__c do. result=.result,<'interval ',numbers >row end.
 errors=.|,Original-image__decoded
 histogram=.8$0
 for_v. errors do.
  bucket=.+/v>:1 2 4 8 16 32 64
  histogram=:(1+bucket{histogram)bucket}histogram
 end.
 result=.result,<'error_histogram ',numbers histogram
 originalplanes=.rgb_to_planes Original
 for_keep. Truncations do.
  truncated=.keep truncated_y decoded
  result=.result,<'truncate ',(dec keep),' ',(0{::originalplanes)psnr truncated
 end.
 result
)
stream_reports=:3 :0
 c=.y
 result=.0$a:
 for_record. segments__c do.
  'position name length'=.>record
  result=.result,<'stream_segment ',(dec position),' ',name,' ',dec length
 end.
 result=.result,<'stream_image ',(dec width__c),' ',dec height__c
 for_k. i.3 do.
  result=.result,<'stream_component ',numbers (k{identifiers__c),(k{hs__c),(k{vs__c),(k{quantids__c),(k{dcids__c),k{acids__c
 end.
 for_id. i.4 do.
  q=.id{quants__c
  if. q-:a: do. continue. end.
  result=.result,<'stream_quant ',(dec id),' ',numbers >q
 end.
 for_cls. i.2 do.
  for_id. i.4 do.
   t=.((4*cls)+id){tables__c
   if. t-:a: do. continue. end.
   longest=.1+{:I.counts__t>0
   result=.result,<'stream_huffman ',(dec cls),' ',(dec id),' symbols ',(dec #values__t),' longest ',dec longest
  end.
 end.
 ok=.+/states__c=<'ok'
 lost=.+/states__c=<'lost'
 damaged=.intervals__c-ok+lost
 result=.result,<'stream_restart ',(dec restart__c),' intervals ',(dec intervals__c),' ok ',(dec ok),' damaged ',(dec damaged),' lost ',dec lost
 for_j. i.intervals__c do.
  'first count'=.c interval_mcus j
  result=.result,<'stream_interval ',(dec j),' ',(dec first),' ',(dec count),' ',j{::states__c
 end.
 result=.result,<'stream_scan_bytes ',dec scanbytes__c
 result
)
main=:3 :0
 read_configuration''
 Original=:read_ppm 'input/image.ppm'
 'h w channels'=. $Original
 rate=.,<'quality,bytes_standard,bytes_optimized,bpp,psnr_y,psnr_cb,psnr_cr,psnr_rgb,max_error'
 reference=.a:
 for_quality. Qualities do.
  standard=.Original encode quality;Sampling;'standard';Restart
  optimized=.Original encode quality;Sampling;'optimized';Restart
  if. HuffmanMode-:'standard' do. encoded=.standard else. encoded=.optimized end.
  decoded=.decode bytes__encoded
  measurements=.Original metrics decoded
  row=.(dec quality);(dec #bytes__standard);(dec #bytes__optimized);((#bytes__encoded)bpp w*h)
  rate=.rate,<','join row,measurements
  if. reference-:a: do. reference=.encoded [ referencedecoded=.decoded end.
 end.
 'output/rate_distortion.csv'write_lines rate
 'output/decoded.ppm'write_ppm image__referencedecoded
 'output/bitstream.hex'write_hex bytes__reference
 'output/thumbnail.ppm'write_ppm thumbnail referencedecoded
 report=.reference reference_reports referencedecoded
 for_sampling. '444';'422';'420' do.
  sampling=.>sampling
  e=.Original encode ({.Qualities);sampling;HuffmanMode;Restart
  d=.decode bytes__e
  measurements=.Original metrics d
  report=.report,<'sampling_compare ',sampling,' ',(dec #bytes__e),' ',' 'join 1 2 3{measurements
 end.
 current=.Original
 for_generation. 1+i.Generations do.
  e=.current encode ({.Qualities);Sampling;HuffmanMode;Restart
  d=.decode bytes__e
  changed=.+/ +./"1 ( ((h*w),3)$,current)~:((h*w),3)$,image__d
  report=.report,<'generation ',(dec generation),' ',(dec #bytes__e),' ',(Original psnr image__d),' ',dec changed
  current=.image__d
 end.
 lo=.1
 hi=.100
 while. lo<hi do.
  mid=.<.(lo+hi+1)%2
  e=.Original encode mid;Sampling;HuffmanMode;Restart
  size=.#bytes__e
  report=.report,<'rate_control_step ',(dec mid),' ',dec size
  if. size<:TargetBytes do. lo=.mid else. hi=.mid-1 end.
 end.
 e=.Original encode lo;Sampling;HuffmanMode;Restart
 d=.decode bytes__e
 report=.report,<'rate_control ',(dec lo),' ',(dec #bytes__e),' ',(('no';'yes'){::~(#bytes__e)<:TargetBytes),' ',Original psnr image__d
 stream=.decode read_hex 'input/stream.hex'
 'output/stream_decoded.ppm'write_ppm image__stream
 repaired=.repair stream
 'output/repaired.hex'write_hex bytes__repaired
 repaireddec=.decode bytes__repaired
 identical=.image__stream-:image__repaireddec
 report=.report,stream_reports stream
 report=.report,<'repair ',(dec #bytes__repaired),' ',(dec headerbytes__repaired),' ',(dec scanbytes__repaired),' identical ',('no';'yes'){::~identical
 'output/report.txt'write_lines report
 0
)
main''
