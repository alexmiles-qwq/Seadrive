local JsonService = {}
JsonService.libs = {}


-- Encode
function JsonService:Encode(tbl)
    local jsn = self.libs['json']       -- Get lib
    if not jsn then return end          -- if no lib then you dumb lol

    return jsn.stringify(tbl)
end

-- Decode
function JsonService:Decode(str)
    local jsn = self.libs['json']   -- Get lib
    if not jsn then return end      -- if no lib then you dumb lol

    return jsn.decode(str)
end


return JsonService