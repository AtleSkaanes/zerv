local query_before = Smed.info.request.query_params
local headers_before = Smed.info.request.headers

if query_before == nil or headers_before == nil then
    return
end

type Value = string -- | { [number]: string }

local query_params: { [string]: Value } = {}
Smed.info.request.query_params = query_params
local headers: { [string]: Value } = {}
Smed.info.request.headers = headers

for _, value in ipairs(query_before) do
    Smed.info.request.query_params[value.key] = value.val
end

for _, value in ipairs(headers_before) do
    Smed.info.request.headers[value.key] = value.val
end


