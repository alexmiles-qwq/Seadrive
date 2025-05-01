--- START OF FILE BadgeService.lua ---

local BadgeService = {}
BadgeService.libs = {} -- libs table will be injected by require2

local BADGES_DS_NAME = 'badges'

-- Initialize the service with dependencies
function BadgeService:init(dsService, libs_table)
    -- Check mandatory dependencies
    if not dsService or type(dsService) ~= 'table' or type(dsService.GetDataStore) ~= 'function' then
        print("BadgeService: Missing or invalid DatastoreService dependency.")
        return false
    end
    if not libs_table or type(libs_table) ~= 'table' then print("BadgeService: Missing or invalid libs table dependency."); return false end
    if not libs_table.json or type(libs_table.json.encode) ~= 'function' or type(libs_table.json.decode) ~= 'function' then print("BadgeService: Missing or invalid 'json' lib."); return false end
    if not libs_table.path then print("BadgeService: Missing or invalid 'path' lib."); return false end
    if not libs_table.fs then print("BadgeService: Missing or invalid 'fs' lib."); return false end

    -- Store dependencies on the instance table 'self'
    self.datastoreService = dsService
    self.json_lib = libs_table.json
    self.path_lib = libs_table.path
    self.fs_lib = libs_table.fs
    self.libs = libs_table -- Store the whole libs table

    -- Get datastore instance using the stored service
    self.badgesDS = self.datastoreService:GetDataStore(BADGES_DS_NAME)
    if not self.badgesDS then
        print("BadgeService: Failed to get '" .. BADGES_DS_NAME .. "' datastore instance.")
        self.datastoreService = nil
        self.badgesDS = nil
        return false
    end

    print("BadgeService initialized.")
    return true
end

-- Helper (local function, doesn't need self)
local function validateBadgeData(badgeData, isUpdating)
    if type(badgeData) ~= 'table' then return false, "Invalid badge data format (must be a table)." end
    local validated = {}
    -- Validate ID carefully, allow letters, numbers, hyphen, underscore, must start with letter/number
    local id_candidate = tostring(badgeData.id or ""):lower():match("^%s*([a-zA-Z0-9][a-zA-Z0-9_%-]*)%s*$")
    badgeData.id = id_candidate
    badgeData.name = tostring(badgeData.name or ""):match("^%s*(.-)%s*$")
    badgeData.imageUrl = tostring(badgeData.imageUrl or ""):match("^%s*(.-)%s*$")
    badgeData.color = tostring(badgeData.color or ""):match("^%s*(.-)%s*$")
    badgeData.description = tostring(badgeData.description or ""):match("^%s*(.-)%s*$")

    if not badgeData.id or badgeData.id == "" then return false, "Badge ID is required and must contain only letters, numbers, hyphens, or underscores (starting with letter/number)." end
    validated.id = badgeData.id
    if badgeData.name == "" then return false, "Badge Name is required." end
    validated.name = badgeData.name
    if badgeData.imageUrl == "" then return false, "Badge Image URL is required." end
    if not badgeData.imageUrl:match("^https?://") and not badgeData.imageUrl:match("^/") then return false, "Badge Image URL must start with http://, https://, or /." end
    validated.imageUrl = badgeData.imageUrl
    if badgeData.color == "" then
        validated.color = "#cccccc" -- Default gray color
    -- This is the regex performing the check:
    elseif not badgeData.color:match("^#([a-fA-F0-9]{6}|[a-fA-F0-9]{3})$") and not badgeData.color:match("^(rgb|hsl)a?%(.-%)$") and not badgeData.color:match("^[a-zA-Z]+$") then
        -- Allow hex, rgb, hsl, standard named colors
        return false, "Invalid CSS color format (use hex #RRGGBB/#RGB, rgb/hsl, or named colors)."
    else
        validated.color = badgeData.color
    end
    validated.color = badgeData.color 
    validated.description = badgeData.description
    return true, validated
end


-- Create a new badge definition (Asynchronous)
function BadgeService:createBadgeAsync(badgeData, callback)
    if not self.badgesDS or not self.json_lib then if callback then callback({message = "BadgeService not properly initialized."}, nil) end; return end

    local isValid, resultData = validateBadgeData(badgeData, false)
    if not isValid then if callback then callback({message = resultData}, nil) end; return end
    local badgeId = resultData.id

    self.badgesDS:GetAsync(badgeId, function(getErr, existingData)
        if getErr then if callback then callback({message = "DB error: " .. (getErr.message or getErr)}, nil) end; return end
        if existingData then if callback then callback({message = "Badge ID '" .. badgeId .. "' exists."}, nil) end; return end

        resultData.createdAt = os.time()
        resultData.updatedAt = os.time()

        local okEncode, jsonData = pcall(self.json_lib.encode, resultData)
        if not okEncode then if callback then callback({message = "Encode error: " .. jsonData}, nil) end; return end

        self.badgesDS:SetAsync(badgeId, jsonData, function(setErr)
            if setErr then if callback then callback({message = "Save error: " .. (setErr.message or setErr)}, nil) end
            else print("BadgeService: Created badge '" .. badgeId .. "'"); if callback then callback(nil, resultData) end end
        end)
    end)
end

-- Get a single badge definition (Asynchronous)
function BadgeService:getBadgeDefinitionAsync(badgeId, callback)
     if not self.badgesDS or not self.json_lib then if callback then callback({message = "BadgeService not properly initialized."}, nil) end; return end
    if type(badgeId) ~= 'string' or badgeId == "" then if callback then callback({message = "Invalid Badge ID."}, nil) end; return end

    self.badgesDS:GetAsync(badgeId, function(getErr, jsonData)
        if getErr then if callback then callback({message = "DB error: " .. (getErr.message or getErr)}, nil) end; return end
        if not jsonData then if callback then callback(nil, nil) end; return end -- Not found

        local ok, badgeData = pcall(self.json_lib.decode, jsonData)
        if not ok or type(badgeData) ~= 'table' then if callback then callback({message = "Decode error for ID '" .. badgeId .. "'." }, nil) end; return end
        if callback then callback(nil, badgeData) end
    end)
end

-- Update an existing badge definition (Asynchronous)
function BadgeService:updateBadgeAsync(badgeId, badgeData, callback)
    if not self.badgesDS or not self.json_lib then if callback then callback({message = "BadgeService not properly initialized."}, nil) end; return end
    if type(badgeId) ~= 'string' or badgeId == "" then if callback then callback({message = "Invalid Badge ID for update."}, nil) end; return end

    self:getBadgeDefinitionAsync(badgeId, function(getErr, existingData) -- Uses self:method
        if getErr then if callback then callback(getErr, nil) end; return end
        if not existingData then if callback then callback({message = "Badge ID '" .. badgeId .. "' not found."}, nil) end; return end

        local dataToValidate = { id = badgeId, name = badgeData.name, description = badgeData.description, imageUrl = badgeData.imageUrl, color = badgeData.color }
        local isValid, validatedUpdates = validateBadgeData(dataToValidate, true)
        if not isValid then if callback then callback({message = validatedUpdates}, nil) end; return end

        existingData.name = validatedUpdates.name or existingData.name
        existingData.description = validatedUpdates.description
        existingData.imageUrl = validatedUpdates.imageUrl or existingData.imageUrl
        existingData.color = validatedUpdates.color or existingData.color
        existingData.updatedAt = os.time()

        local okEncode, jsonData = pcall(self.json_lib.encode, existingData)
        if not okEncode then if callback then callback({message = "Encode error: " .. jsonData}, nil) end; return end

        self.badgesDS:SetAsync(badgeId, jsonData, function(setErr)
             if setErr then if callback then callback({message = "Save error: " .. (setErr.message or setErr)}, nil) end
             else print("BadgeService: Updated badge '" .. badgeId .. "'"); if callback then callback(nil, existingData) end end
         end)
    end)
end

-- Delete a badge definition (Asynchronous)
function BadgeService:deleteBadgeAsync(badgeId, callback)
     if not self.badgesDS then if callback then callback({message = "BadgeService not properly initialized."}) end; return end
    if type(badgeId) ~= 'string' or badgeId == "" then if callback then callback({message = "Invalid Badge ID for delete."}) end; return end

    self.badgesDS:DeleteAsync(badgeId, function(deleteErr)
        if deleteErr then if callback then callback({message = "Delete error: " .. (deleteErr.message or deleteErr)}) end
        else print("BadgeService: Deleted badge '" .. badgeId .. "'"); if callback then callback(nil) end end
    end)
end


-- Get all badge definitions (Asynchronous)
function BadgeService:getAllBadgeDefinitionsAsync(callback)
    -- Access dependencies via self
    if not self.datastoreService or not self.path_lib or not self.fs_lib or not self.json_lib or not self.badgesDS then
        if callback then callback({message = "BadgeService dependencies missing in getAll."}, nil) end
        return
    end

    local ds = self.datastoreService
    local path = self.path_lib
    local fs = self.fs_lib
    local json = self.json_lib
    local currentBadgesDS = self.badgesDS

    -- Construct the path reliably using the DatastoreService instance method
    local badgesDirPath
    local getPathOk, dummyFilePath = pcall(ds.getFilePathInternal, ds, BADGES_DS_NAME, "_dummy_key_") -- Use '.' syntax to call method on ds
    if getPathOk and dummyFilePath then
         badgesDirPath = path.dirname(dummyFilePath)
         print("BadgeService: Reading badges from directory:", badgesDirPath) -- Debug Log
    else
         print("BadgeService: FATAL - Could not determine badges directory path via helper. Error:", dummyFilePath)
         -- Fallback is unlikely to work if the above failed, error out
         if callback then callback({message = "Cannot determine badges directory path."}, nil); end
         return
    end

    fs.readdir(badgesDirPath, function(readDirErr, files)
        if readDirErr then
            if readDirErr.code == 'ENOENT' then if callback then callback(nil, {}) end; return end -- No badges dir yet
            if callback then callback({message = "Error reading badges directory: " .. (readDirErr.message or readDirErr)}, nil) end; return
        end

        local badgesMap = {}
        local filesToProcess = #files
        local errorsOccurred = false
        local firstError = nil

        if filesToProcess == 0 then if callback then callback(nil, badgesMap) end; return end -- Empty

        local function fileProcessedCallback(err)
            if errorsOccurred and firstError then return end
            if err then
                 print("BadgeService: Error processing a badge file:", (err.message or tostring(err)))
                 if not firstError then firstError = err end
                 -- Continue processing other files for now
            end
            filesToProcess = filesToProcess - 1
            if filesToProcess == 0 then
                 if firstError then if callback then callback(firstError, nil) end -- Report first error if any occurred
                 else if callback then callback(nil, badgesMap) end end -- Success
            end
        end

        for _, filename in ipairs(files) do
             if not filename:match("^[._]") then -- Ignore hidden files
                 local badgeId = filename
                 -- Use the stored badgesDS instance variable
                 currentBadgesDS:GetAsync(badgeId, function(getDefErr, badgeJsonString)
                      local processErr = nil
                      if getDefErr then processErr = getDefErr -- Real datastore read error
                      elseif badgeJsonString then
                          local ok, decoded = pcall(json.decode, badgeJsonString) -- Use local json ref
                          if ok and type(decoded) == 'table' then
                               badgesMap[badgeId] = decoded
                          else processErr = {message = "Failed to decode JSON for badge ID '" .. badgeId .. "'"} end
                      else print("BadgeService: Warning - File '" .. filename .. "' listed but no data retrieved.") end
                      fileProcessedCallback(processErr)
                 end)
             else
                 fileProcessedCallback(nil) -- Ignored file
             end
        end
    end)
end


return BadgeService
--- END OF FILE BadgeService.lua ---