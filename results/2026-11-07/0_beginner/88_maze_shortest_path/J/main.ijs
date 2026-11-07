main =: 3 : 0
  maze =. >'#############';'#S..#.......#';'#.#.#.###.#.#';'#.#...#...#.#';'#.###.#.###.#';'#...#...#...#';'###.#####.#.#';'#.......#..G#';'#############'
  flat =. ,maze
  start =. flat i.'S'
  goal =. flat i.'G'
  parent =. (#flat)$_1
  parent =. start start}parent
  queue =. ,start
  head =. 0
  steps =. 4 2$_1 0 1 0 0 _1 0 1
  while. (head<#queue)*._1=goal{parent do.
    current =. head{queue
    head =. >:head
    row =. <.current%13
    column =. 13|current
    for_step. steps do.
      'dr dc' =. step
      nr =. row+dr
      nc =. column+dc
      if. (nr>:0)*.(nr<9)*.(nc>:0)*.nc<13 do.
        neighbor =. (nr*13)+nc
        if. ('#'~:neighbor{flat)*._1=neighbor{parent do.
          parent =. current neighbor}parent
          queue =. queue,neighbor
        end.
      end.
    end.
  end.
  count =. 0
  current =. goal
  while. current~:start do.
    if. '.'=current{flat do. flat =. '*' current}flat end.
    current =. current{parent
    count =. >:count
  end.
  smoutput 'steps: ',":count
  smoutput 9 13$flat
)
main ''
