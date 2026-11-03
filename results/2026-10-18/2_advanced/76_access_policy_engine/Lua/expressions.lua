local Parser = {}
Parser.__index = Parser

function Parser.new(text)
    local tokens, position = {}, 1
    while position <= #text do
        local character, start = text:sub(position, position), position
        if character == ' ' then
            position = position + 1
        else
            if character == '"' then
                position = assert(text:find('"', position + 1, true)) + 1
            elseif character:match('[0-9]') then
                repeat position = position + 1 until position > #text or not text:sub(position, position):match('[0-9]')
            elseif character:match('[A-Za-z]') then
                repeat position = position + 1 until position > #text or not text:sub(position, position):match('[A-Za-z0-9_.]')
            else
                local pair = text:sub(position, position + 1)
                position = position + ((pair == '==' or pair == '!=' or pair == '<=' or pair == '>=') and 2 or 1)
            end
            tokens[#tokens + 1] = text:sub(start, position - 1)
        end
    end
    return setmetatable({tokens = tokens, position = 1}, Parser)
end
function Parser:peek() return self.tokens[self.position] end
function Parser:take() local token = self:peek(); self.position = self.position + 1; return token end
function Parser:joined(next_level, operators)
    local tree = next_level(self)
    while operators[self:peek()] do
        local operation = self:take()
        local right = next_level(self)
        tree = {operation = operation, arguments = {tree, right}}
    end
    return tree
end
function Parser:disjunction() return self:joined(Parser.conjunction, {['or'] = true}) end
function Parser:conjunction() return self:joined(Parser.negation, {['and'] = true}) end
function Parser:negation()
    if self:peek() == 'not' then self:take(); return {operation = 'not', arguments = {self:negation()}} end
    return self:comparison()
end
function Parser:comparison()
    local tree = self:sum()
    local operators = {['=='] = true, ['!='] = true, ['<'] = true, ['<='] = true, ['>'] = true, ['>='] = true, ['in'] = true}
    if operators[self:peek()] then
        local operation = self:take()
        local right = self:sum()
        return {operation = operation, arguments = {tree, right}}
    end
    return tree
end
function Parser:sum() return self:joined(Parser.product, {['+'] = true, ['-'] = true}) end
function Parser:product() return self:joined(Parser.unary, {['*'] = true}) end
function Parser:unary()
    if self:peek() == '-' then self:take(); return {operation = '-', arguments = {self:unary()}} end
    return self:primary()
end
function Parser:primary()
    local token = self:take()
    if token:match('^%d+$') then return {operation = 'literal', value = tonumber(token)} end
    if token:sub(1, 1) == '"' then return {operation = 'literal', value = token:sub(2, -2)} end
    if token == 'true' or token == 'false' then return {operation = 'literal', value = token == 'true'} end
    if token == 'it' then return {operation = 'it'} end
    if token:find('.', 1, true) then return {operation = 'attribute', reference = token} end
    if token == '(' then local tree = self:disjunction(); self:take(); return tree end
    if token == '[' then
        local values = {}
        while self:peek() ~= ']' do
            values[#values + 1] = self:take():sub(2, -2)
            if self:peek() ~= ']' then self:take() end
        end
        self:take(); return {operation = 'literal', value = values}
    end
    self:take()
    local arguments = {}
    while self:peek() ~= ')' do
        arguments[#arguments + 1] = self:disjunction()
        if self:peek() ~= ')' then self:take() end
    end
    self:take(); return {operation = token, arguments = arguments}
end

return {parse = function(text) return Parser.new(text):disjunction() end}
