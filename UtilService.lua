local UtilService = {}
UtilService.libs = {} -- No specific libs actually needed for these functions, but follow the pattern


-- LAME JAVASCRIPT 
function UtilService:urlEncodeComponent(str)
  if not str then return "" end
  str = tostring(str)
  -- Encode characters that are *not* URL-safe according to RFC 3986
  -- Unreserved characters: A-Z a-z 0-9 - . _ ~
  str = string.gsub(str, "([^%w%.%-%_~])", function(c) -- Using %w for A-Za-z0-9_ and adding . - ~
    return string.format("%%%02X", string.byte(c))
  end)
  return str
end


-- LAME JAVASCRIPT2 (URL decode component)
function UtilService:urlDecodeComponent(str)
  if not str then return "" end
  str = tostring(str)
  -- Decode + back to space FIRST
  str = string.gsub(str, "+", " ")
  -- Decode %XX sequences
  str = string.gsub(str, "%%(%x%x)", function(h)
    -- Use pcall for safety in case of invalid hex sequence
    local ok, charCode = pcall(tonumber, h, 16)
    if ok and charCode then
        return string.char(charCode)
    else
        
        return "%%" .. h
    end
  end)
  return str 
end


return UtilService
