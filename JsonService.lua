local JsonService = {}
JsonService.libs = {}


-- Encode
function JsonService:Encode(tbl)
    local json = self.libs['json']       -- Get lib
    if not json or type(json.encode) ~= 'function' then
        print("JsonService: Libs check didnt passed for Encode")
        return nil -- Return nil or error string if json lib is invalid
    end

    -- Use pcall to handle potential errors during encoding
    local ok, result = pcall(json.encode, tbl)
    if not ok then
        print("JsonService: Error during encode:", result)
        return nil -- Return nil on error
    end
    return result -- Return the encoded string
end

-- Decode
function JsonService:Decode(str)
    local json = self.libs['json']   -- Get lib
    if not json or type(json.decode) ~= 'function' then
        print("JsonService: Libs check didnt passed for Decode")
        return nil -- Return nil or error string if json lib is invalid
    end

     -- Use pcall to handle potential errors during decoding
    local ok, result = pcall(json.decode, str)
    if not ok then
        print("JsonService: Error during decode:", result)
        return nil -- Return nil on error
    end
    return result -- Return the decoded Lua value
end


return JsonService