local UtilService = {}
UtilService.libs = {} 


-- LAME JAVASCRIPT
function UtilService:urlEncodeComponent(str)
  if not str then return "" end
  str = tostring(str)
  str = string.gsub(str, "([^%w%-%.!~%*'%_'(%)])", function(c)
    return string.format("%%%02X", string.byte(c))
  end)
  str = string.gsub(str, " ", "%%20")
  return str
end

-- LAME JAVASCRIPT2
function UtilService:urlDecodeComponent(str)
  if not str then return "" end
  str = tostring(str)
  str = string.gsub(str, "%%(%x%x)", function(h)
    return string.char(tonumber(h, 16))
  end)
  str = string.gsub(str, "+", " ")
  return str
end


return UtilService
