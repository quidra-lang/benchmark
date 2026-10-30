local protocol = {dirty = {M = true, O = true}}
function protocol.requester(name, old, operation, other_has_line)
    if name == 'VI' then
        if operation == 'R' then if old == 'I' then return 'BusRd', 'V' end; return nil, 'V' end
        return 'BusWr', old == 'I' and 'I' or 'V'
    end
    if old == 'I' then
        if operation == 'W' then return 'BusRdX', 'M' end
        return 'BusRd', (name == 'MSI' or other_has_line) and 'S' or 'E'
    end
    if operation == 'R' then return nil, old end
    if old == 'M' or old == 'E' then return nil, 'M' end
    return 'BusUpgr', 'M'
end
function protocol.snoop(name, old, transaction)
    if name == 'VI' then return transaction == 'BusRd' and 'V' or 'I', false, false end
    if transaction == 'BusRd' then
        if old == 'M' then if name == 'MOESI' then return 'O', true, false end; return 'S', true, true end
        if old == 'O' then return 'O', true, false end
        return 'S', false, false
    end
    return 'I', transaction == 'BusRdX' and protocol.dirty[old] == true, false
end
return protocol
