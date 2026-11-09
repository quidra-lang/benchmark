main =: 3 : 0
  commands =. 'undo';'type hello world';'delete 5';'type there';'undo';'undo';'redo';'type friend';'redo';'delete 20';'undo';'redo';'redo';'type see you'
  buffer =. ''
  undo =. redo =. 0$<''
  for_box. commands do.
    command =. >box
    result =. ''
    if. command-:'undo' do.
      if. 0=#undo do. result =. 'nothing to undo'
      else.
        redo =. redo,<buffer
        buffer =. >{:undo
        undo =. }:undo
      end.
    elseif. command-:'redo' do.
      if. 0=#redo do. result =. 'nothing to redo'
      else.
        undo =. undo,<buffer
        buffer =. >{:redo
        redo =. }:redo
      end.
    else.
      undo =. undo,<buffer
      redo =. 0$<''
      if. 'type '-:5{.command do. buffer =. buffer,5}.command
      else.
        count =. 0".7}.command
        buffer =. (0>. (#buffer)-count){.buffer
      end.
    end.
    if. 0=#result do. result =. '"',buffer,'"' end.
    smoutput command,' => ',result
  end.
)
main ''
