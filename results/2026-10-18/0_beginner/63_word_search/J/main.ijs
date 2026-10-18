search =: 4 : 0
  word =. x
  board =. y
  steps =. 8 2$0 1 1 1 1 0 1 _1 0 _1 _1 _1 _1 0 _1 1
  names =. ;:'E SE S SW W NW N NE'
  for_r. i.10 do.
    for_c. i.10 do.
      for_d. i.8 do.
        'dr dc' =. d{steps
        matched =. 1
        for_k. i.#word do.
          row =. r+k*dr
          column =. c+k*dc
          if. (row<0)+.(row>:10)+.(column<0)+.column>:10 do.
            matched =. 0 break.
          end.
          if. ((<row,column){board)~:k{word do. matched =. 0 break. end.
        end.
        if. matched do. ('(',(":r),', ',(":c),') ',>d{names) return. end.
      end.
    end.
  end.
  'not found'
)
board =: >'MMONKENBIR';'PMTIGERJPL';'TGREJEDUZI';'SPYUTEJDEC';'WKAPSIDLBN';'KUVNGSBPRO';'RIBSDACBAM';'YWVAUAPKAH';'KYCGTHHESR';'OCCALAOKKR'
main =: 3 : 0
  for_box. ;:'TIGER ZEBRA MONKEY PANDA KOALA RABBIT' do.
    word =. >box
    smoutput word,': ',word search board
  end.
)
main ''
