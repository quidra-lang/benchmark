local Parser = {}
Parser.__index = Parser
function Parser.new(text)
    local tokens, position = {}, 1
    while position <= #text do
        local character, start = text:sub(position, position), position
        if character == ' ' then position = position + 1
        else
            if character == "'" then position = assert(text:find("'", position + 1, true)) + 1
            elseif character:match('[A-Za-z_]') then
                repeat position = position + 1 until position > #text or not text:sub(position, position):match('[A-Za-z0-9_]')
            elseif character:match('[0-9%-]') then
                repeat position = position + 1 until position > #text or not text:sub(position, position):match('[0-9]')
            else
                local pair = text:sub(position, position + 1)
                position = position + ((pair == '<=' or pair == '>=' or pair == '<>') and 2 or 1)
            end
            tokens[#tokens + 1] = text:sub(start, position - 1)
        end
    end
    return setmetatable({tokens = tokens, position = 1}, Parser)
end
function Parser:peek() return self.tokens[self.position] end
function Parser:take() local token = self:peek(); self.position = self.position + 1; return token end
function Parser:accept(token) if self:peek() == token then self.position = self.position + 1; return true end; return false end
function Parser:item()
    local name = self:take()
    if name:match('^[a-z]') then return {operation = 'COLUMN', name = name} end
    self:take()
    local operation = self:accept('DISTINCT') and 'COUNT_DISTINCT' or name
    local column; if not self:accept('*') then column = self:take() end
    self:take(); return {operation = operation, name = column}
end
function Parser:literal()
    local token = self:take()
    if token:sub(1, 1) == "'" then return {kind = 'STRING', value = token:sub(2, -2)} end
    if token == 'TRUE' or token == 'FALSE' then return {kind = 'BOOL', value = token == 'TRUE'} end
    return {kind = 'INT', value = tonumber(token)}
end
function Parser:condition()
    local tree = self:conjunction()
    while self:accept('OR') do local right = self:conjunction(); tree = {operation = 'OR', left = tree, right = right} end
    return tree
end
function Parser:conjunction()
    local tree = self:negation()
    while self:accept('AND') do local right = self:negation(); tree = {operation = 'AND', left = tree, right = right} end
    return tree
end
function Parser:negation()
    if self:accept('NOT') then return {operation = 'NOT', child = self:negation()} end
    if self:accept('(') then local tree = self:condition(); self:take(); return tree end
    local column = self:take()
    local operation = self:take()
    local literals = {}
    if operation == 'IS' then operation = self:accept('NOT') and 'IS_NOT_NULL' or 'IS_NULL'; self:take()
    elseif operation == 'BETWEEN' then literals[1] = self:literal(); self:take(); literals[2] = self:literal()
    elseif operation == 'IN' then self:take(); literals[1] = self:literal(); while self:accept(',') do literals[#literals + 1] = self:literal() end; self:take()
    else literals[1] = self:literal() end
    return {operation = operation, column = column, literals = literals}
end
function Parser:parse()
    self:take()
    local items
    if not self:accept('*') then items = {self:item()}; while self:accept(',') do items[#items + 1] = self:item() end end
    local condition; if self:accept('WHERE') then condition = self:condition() end
    local group, order, descending, limit = nil, nil, false, nil
    if self:accept('GROUP') then self:take(); group = self:take() end
    if self:accept('ORDER') then self:take(); order = self:take(); descending = self:accept('DESC'); if not descending then self:accept('ASC') end end
    if self:accept('LIMIT') then limit = tonumber(self:take()) end
    return {items = items, condition = condition, group = group, order = order, descending = descending, limit = limit}
end
return Parser
