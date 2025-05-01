--- START OF FILE DatastoreService.lua ---

local DatastoreService = {}
DatastoreService.libs = {} -- libs table will be injected by require2

local rootPath -- Will be set during initialization
local DATA_DIR_NAME = "datastores" -- Base directory for all datastores

-- Initialize the service with the application root path
function DatastoreService:init(appRoot)
    local fs = self.libs['fs']
    local path = self.libs['path']
    if not fs or not path then
        print("DatastoreService: Missing required libs (fs or path) for initialization.")
        return false
    end
     if type(appRoot) ~= 'string' or appRoot == "" then
        print("DatastoreService: Invalid root path provided for initialization.")
        return false
     end

    -- Store rootPath internally for use by other services (like BadgeService fallback)
    self.rootPath = appRoot -- Store on the service instance
    rootPath = appRoot      -- Keep module-level for existing internal functions

    -- <<< Make DATA_DIR_NAME available on the instance >>>
    self.DATA_DIR_NAME = DATA_DIR_NAME

    local dataDirPath = path.join(rootPath, self.DATA_DIR_NAME) -- Use self.DATA_DIR_NAME
    -- Store dataDirPath internally for potential use by other services
    self.dataDirPath = dataDirPath

    -- Ensure the base data directory exists synchronously on startup
    local ok, err = pcall(fs.mkdirSync, dataDirPath, nil, { recursive = true })
    if not ok then
        if not (err and err.code == 'EEXIST') then
            print("DatastoreService: Failed to create base data directory '" .. dataDirPath .. "':", err)
            print("DatastoreService will be unable to save or load data.")
            self.rootPath = nil -- Invalidate paths
            rootPath = nil
            self.dataDirPath = nil
            self.DATA_DIR_NAME = nil -- Invalidate
            return false
        end
        print("DatastoreService: Base data directory already exists:", dataDirPath)
    end

    print("DatastoreService initialized for asynchronous raw file storage. Data will be stored in:", dataDirPath)
    return true
end


-- Internal helper to get the full path for a datastore key file
function DatastoreService:getFilePathInternal(datastoreName, key)
    local currentRootPath = self.rootPath -- Access instance path
    if not currentRootPath then return nil end
    local path = self.libs['path']
    if not path then return nil end
    if type(datastoreName) ~= 'string' or datastoreName == "" then return nil end
    if type(key) ~= 'string' or key == "" then return nil end

    local safeKey = key:gsub('[<>:"/\\|?*%c]', '_'):gsub('%.%.+', '_'):gsub('^%.+$', '_')
    if safeKey == "" or safeKey:match('^_*$') then safeKey = "default_key" end
    -- Use instance DATA_DIR_NAME if available
    local dataDir = self.DATA_DIR_NAME or DATA_DIR_NAME
    return path.join(currentRootPath, dataDir, datastoreName, safeKey)
end
-- Keep old local function wrapper if needed internally (though direct call is fine)
local function getFilePath(datastoreName, key)
    -- This local function doesn't have access to 'self', so it uses the module-level rootPath.
    -- It's better to call self:getFilePathInternal inside other methods of this service.
    if not rootPath then return nil end
    local path = DatastoreService.libs['path'] -- Access libs via module table
    if not path then return nil end
    if type(datastoreName) ~= 'string' or datastoreName == "" then return nil end
    if type(key) ~= 'string' or key == "" then return nil end
    local safeKey = key:gsub('[<>:"/\\|?*%c]', '_'):gsub('%.%.+', '_'):gsub('^%.+$', '_')
    if safeKey == "" or safeKey:match('^_*$') then safeKey = "default_key" end
    return path.join(rootPath, DATA_DIR_NAME, datastoreName, safeKey)
end

-- Internal helper to ensure a specific datastore's directory exists synchronously
local function ensureDatastoreDir(datastoreName)
     -- Use the module-level rootPath and DATA_DIR_NAME as this is a local helper
     if not rootPath then return false, "DatastoreService not initialized." end
     local fs = DatastoreService.libs['fs']
     local path = DatastoreService.libs['path']
     if not fs or not path then return false, "DatastoreService: Missing fs or path libs." end
      if type(datastoreName) ~= 'string' or datastoreName == "" then return false, "Invalid datastore name." end

     local dirPath = path.join(rootPath, DATA_DIR_NAME, datastoreName)
     local ok, err = pcall(fs.mkdirSync, dirPath, nil, { recursive = true })
     if not ok then
        if err and err.code == 'EEXIST' then return true, nil end
        local errMsg = (type(err) == 'table' and err.message) or tostring(err)
        print("DatastoreService: Failed to create directory '" .. dirPath .. "':", errMsg)
        return false, "Failed to create datastore directory '" .. dirPath .. "': " .. errMsg
     end
     return true, nil
end

-- Internal function to set/save data asynchronously
function DatastoreService:setAsyncInternal(datastoreName, key, value, callback)
    local fs = self.libs['fs']
    if not fs or not fs.writeFile then
        if callback then callback({message = "DatastoreService: Missing required lib (fs) or function (writeFile) for SetAsync."}) end; return
    end
    if not self.rootPath then -- Check instance path
        if callback then callback({message = "DatastoreService not initialized or failed setup."}) end; return
    end

    local dirOk, dirErr = ensureDatastoreDir(datastoreName) -- Use local helper
    if not dirOk then if callback then callback({message = dirErr}) end; return end

    local filePath = self:getFilePathInternal(datastoreName, key) -- Use instance method
    if not filePath then if callback then callback({message = "DatastoreService: Failed to get file path for key."}) end; return end

    local dataToWrite = tostring(value)
    fs.writeFile(filePath, dataToWrite, function(writeErr)
        if writeErr then
            print("DatastoreService: Error writing file '" .. filePath .. "':", writeErr.message or tostring(writeErr))
            if callback then callback(writeErr) end
        else
            if callback then callback(nil) end
        end
    end)
end

-- Internal function to get/load data asynchronously
function DatastoreService:getAsyncInternal(datastoreName, key, callback)
     local fs = self.libs['fs']
     if not fs or not fs.readFile then
         if callback then callback({message = "DatastoreService: Missing required lib (fs) or function (readFile) for GetAsync."}, nil) end; return
     end
     if not self.rootPath then -- Check instance path
        if callback then callback({message = "DatastoreService not initialized or failed setup."}, nil) end; return
    end

    local filePath = self:getFilePathInternal(datastoreName, key) -- Use instance method
    if not filePath then if callback then callback({message = "DatastoreService: Failed to get file path for key."}, nil) end; return end

    fs.readFile(filePath, function(readErr, data)
        if readErr then
            local isENOENT = (type(readErr) == 'table' and readErr.code == 'ENOENT') or (type(readErr) == 'string' and readErr:find('ENOENT', 1, true))
            local isEISDIR = (type(readErr) == 'table' and readErr.code == 'EISDIR') or (type(readErr) == 'string' and readErr:find('EISDIR', 1, true))
            if isENOENT then if callback then callback(nil, nil) end
            elseif isEISDIR then print("DatastoreService: Attempted read on directory: " .. filePath); if callback then callback(readErr, nil) end
            else print("DatastoreService: Error reading file '" .. filePath .. "':", readErr.message or tostring(readErr)); if callback then callback(readErr, nil) end end
            return
        end
        if callback then callback(nil, data) end
    end)
end

-- Internal function to delete data asynchronously
function DatastoreService:deleteAsyncInternal(datastoreName, key, callback)
    local fs = self.libs['fs']
    if not fs or not fs.unlink then
        if callback then callback({message = "DatastoreService: Missing required lib (fs) or function (unlink) for DeleteAsync."}) end; return
    end
    if not self.rootPath then -- Check instance path
        if callback then callback({message = "DatastoreService not initialized or failed setup."}) end; return
    end

    local filePath = self:getFilePathInternal(datastoreName, key) -- Use instance method
    if not filePath then if callback then callback({message = "DatastoreService: Failed to get file path for key."}) end; return end

    fs.unlink(filePath, function(unlinkErr)
        if unlinkErr then
            local isENOENT = (type(unlinkErr) == 'table' and unlinkErr.code == 'ENOENT') or (type(unlinkErr) == 'string' and unlinkErr:find('ENOENT', 1, true))
            if isENOENT then if callback then callback(nil) end
             else print("DatastoreService: Error deleting file '" .. filePath .. "':", unlinkErr.message or tostring(unlinkErr)); if callback then callback(unlinkErr) end end
        else
            if callback then callback(nil) end
        end
    end)
end


-- Internal function to update data asynchronously
function DatastoreService:updateAsyncInternal(datastoreName, key, updateFunc, callback)
     if type(updateFunc) ~= 'function' then if callback then callback({message = "UpdateAsync requires a function."}, nil) end; return end

    self:getAsyncInternal(datastoreName, key, function(getErr, currentValue) -- Uses instance method
        if getErr then print("DatastoreService.updateAsyncInternal: Error getAsyncInternal:", getErr); if callback then callback(getErr, nil) end; return end

        local ok, result = pcall(updateFunc, currentValue)
        if not ok then print("DatastoreService: Error executing updateFunc:", result); if callback then callback({message = "Error in update function: " .. tostring(result)}, nil) end; return end
        local newValue = result

        if newValue == nil then if callback then callback(nil, currentValue) end; return end -- No change

        local dataToSave = tostring(newValue)
        self:setAsyncInternal(datastoreName, key, dataToSave, function(setErr) -- Uses instance method
            if setErr then print("DatastoreService.updateAsyncInternal: Error setAsyncInternal:", setErr); if callback then callback(setErr, nil) end
            else if callback then callback(nil, dataToSave) end end
        end)
    end)
end


-- To access a data store
function DatastoreService:GetDataStore(name)
    local fs = self.libs['fs']
    local path = self.libs['path']
     if not fs or not path then print("DatastoreService: Missing libs for GetDataStore."); return nil end
    if not self.rootPath then print("DatastoreService: GetDataStore called before init."); return nil end

    local ds = {}
    local datastoreName = tostring(name):match("^%s*(.-)%s*$")
    if datastoreName == "" or datastoreName:match('[<>:"/\\|?*%c]') or datastoreName:match('^%.+$') then
        print("DatastoreService: GetDataStore called with invalid name:", name); return nil
    end

    local dirOk, dirErr = ensureDatastoreDir(datastoreName) -- Use local helper
    if not dirOk then print("DatastoreService: Failed directory prep for '" .. datastoreName .. "':", dirErr); return nil end

    local selfService = self -- Capture the DatastoreService instance

    function ds:SetAsync(key, value, callback)
         if type(key)~='string' or key=="" or key:match('[<>:"/\\|?*%c]') or key:match('^%.+$') then print("Datastore:SetAsync invalid key:", key); if callback then pcall(callback, {message="Invalid key."}) end; return end
        selfService:setAsyncInternal(datastoreName, key, value, callback)
    end
    function ds:GetAsync(key, callback)
         if type(key)~='string' or key=="" or key:match('[<>:"/\\|?*%c]') or key:match('^%.+$') then print("Datastore:GetAsync invalid key:", key); if callback then pcall(callback, {message="Invalid key."}, nil) end; return end
         selfService:getAsyncInternal(datastoreName, key, callback)
    end
    function ds:UpdateAsync(key, updateFunc, callback)
         if type(key)~='string' or key=="" or key:match('[<>:"/\\|?*%c]') or key:match('^%.+$') then print("Datastore:UpdateAsync invalid key:", key); if callback then pcall(callback, {message="Invalid key."}, nil) end; return end
          if type(updateFunc) ~= 'function' then print("Datastore:UpdateAsync non-function:", type(updateFunc)); if callback then pcall(callback, {message="Update function required."}, nil) end; return end
         selfService:updateAsyncInternal(datastoreName, key, updateFunc, callback)
    end
     function ds:DeleteAsync(key, callback)
         if type(key)~='string' or key=="" or key:match('[<>:"/\\|?*%c]') or key:match('^%.+$') then print("Datastore:DeleteAsync invalid key:", key); if callback then pcall(callback, {message="Invalid key."}) end; return end
         selfService:deleteAsyncInternal(datastoreName, key, callback)
     end

    return ds
end

return DatastoreService
--- END OF FILE DatastoreService.lua ---