main =: 3 : 0
  cache =. ''
  hits =. misses =. 0
  for_key. 'BACBDABEADDCAEB' do.
    status =. 'hit'
    if. key e.cache do. hits =. >:hits
    else.
      misses =. >:misses
      status =. 'miss'
      if. 3=#cache do.
        status =. status,', evict ',{:cache
        cache =. }:cache
      end.
    end.
    cache =. key,cache-.key
    contents =. }. ; (<' ') ,&.> <"0 cache
    smoutput key,': ',status,' [',contents,']'
  end.
  smoutput 'hits: ',(":hits),' misses: ',":misses
)
main ''
