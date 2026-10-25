log_prefix =: 3 : 'SessionName,'' '',number Turns'
memory_store =: 4 : 0
    prefix =. log_prefix ''
    if. (<y)e.Memory do.
        MemoryLog =: MemoryLog,<prefix,' SKIP ',x,' ',y
        i.0 return.
    end.
    if. (#Memory)=Capacity do.
        MemoryLog =: MemoryLog,<prefix,' DROP ',0{::Memory
        Memory =: }.Memory
    end.
    Memory =: Memory,<y
    MemoryLog =: MemoryLog,<prefix,' STORE ',x,' ',y
    StoreCount =: StoreCount+1
    i.0
)
memory_recall =: 3 : 0
    text =. 0{::Memory
    Memory =: }.Memory
    MemoryLog =: MemoryLog,<(log_prefix ''),' RECALL ',text
    RecallCount =: RecallCount+1
    text
)
memory_clear =: 3 : 0
    if. #Memory do.
        MemoryLog =: MemoryLog,<y,' CLEAR ',number #Memory
        Memory =: 0$a:
    end.
    i.0
)
