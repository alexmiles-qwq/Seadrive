--- START OF FILE AuthService.lua ---

local AuthService = {}
-- AuthService.libs = {} -- No longer needed if we get libs via init parameter

local datastoreService -- Reference to the DatastoreService
-- We will now use json_lib directly from the libs table passed during init
local json_lib -- Reference to the json library (e.g., libs.json)
local sha2Lib -- Reference to the sha2 library

local usersDS -- Datastore for user accounts
local sessionsDS -- Datastore for active sessions

AuthService.SESSION_DURATION_SECONDS = 7 * 24 * 60 * 60 -- 1 week session duration (Made public)

-- Initialize the service with dependencies
-- Now expects dsService, the full libs table, and sha2
function AuthService:init(dsService, libs_table, sha2_dep)
    -- Check mandatory dependencies
    if not dsService or type(dsService) ~= 'table' or type(dsService.GetDataStore) ~= 'function' then
        print("AuthService: Missing or invalid DatastoreService dependency.")
        return false
    end
    if not libs_table or type(libs_table) ~= 'table' then
         print("AuthService: Missing or invalid libs table dependency.")
         return false
    end
    -- Check specific libs needed from the table
    if not libs_table.json or type(libs_table.json.encode) ~= 'function' or type(libs_table.json.decode) ~= 'function' then
         print("AuthService: Missing or invalid 'json' lib in the provided libs table.")
         return false
    end
     if not sha2_dep or type(sha2_dep) ~= 'table' or type(sha2_dep.sha256) ~= 'function' then
        print("AuthService: Missing or invalid sha2 lib with .sha256 dependency.")
        return false
    end


    datastoreService = dsService
    json_lib = libs_table.json -- Store reference to the json lib directly
    sha2Lib = sha2_dep -- Store the sha2 library reference

    -- Get datastore instances (synchronous calls, should be fine in init)
    -- Check if datastoreService and its GetDataStore method are valid
    if type(datastoreService) ~= 'table' or type(datastoreService.GetDataStore) ~= 'function' then
         print("AuthService: Provided DatastoreService is not valid.")
         -- Invalidate module-level references if dependencies fail
         datastoreService = nil
         json_lib = nil
         sha2Lib = nil
         return false
    end

    usersDS = datastoreService:GetDataStore('users')
    sessionsDS = datastoreService:GetDataStore('sessions')

    if not usersDS or not sessionsDS then
        print("AuthService: Failed to get required datastore instances.")
         -- Invalidate module-level references if datastore instances fail
         datastoreService = nil
         json_lib = nil
         sha2Lib = nil
        return false
    end

    print("AuthService initialized (using SHA-256 hashing and direct libs.json).")
     print("WARNING: Salt and Session ID generation still use math.random which is NOT cryptographically secure. This is a security risk.")
    return true
end

-- Helper to normalize username (lowercase and trim)
local function normalizeUsername(username)
    if type(username) ~= 'string' then return "" end
    -- Add basic character filtering to prevent issues with filenames/keys
    local norm = username:lower():match("^%s*(.-)%s*$")
    -- Filter problematic chars for keys, and prevent empty/dot-only results
    local safe = norm:gsub('[<>:"/\\|?*%c]', '_'):gsub('%.%.', '_')
     if safe == "" or safe:match('^_*$') or safe:match('^%.+$') then return "" end -- Disallow empty or problematic usernames
     return safe
end
AuthService.normalizeUsername = normalizeUsername


-- !!! INSECURE RANDOMNESS FOR SALT AND SESSION ID GENERATION !!!
-- !!! Although SHA-256 is used for hashing, the predictability of math.random is a vulnerability !!!

-- Generate a random salt (insecure randomness)
local function generateSalt()
    -- Use a combination of time and math.random for seeding, still not a CSPRNG
    math.randomseed(os.time() * 1000000 + os.clock() * 1000 + math.random(1, 1000000))
    local salt = ""
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()"
    local saltLength = 32 -- Use a reasonable salt length
    for i = 1, saltLength do
        salt = salt .. chars:sub(math.random(1, #chars), math.random(1, #chars))
    end
    return salt
end

-- Hash a password with a given salt using SHA-256
-- Returns hex hash string or nil on failure
local function hashPassword(password, salt)
    -- Check if sha2Lib is available before using it
    if not sha2Lib or type(sha2Lib.sha256) ~= 'function' then
        print("ERROR: sha2Lib not available for hashing!")
        return nil
    end
    local combined = salt .. password
    -- Use the provided sha2.sha256 function
    local hash = sha2Lib.sha256(combined)
    return hash -- Assuming sha2.sha256 returns the hex digest string
end

-- Verify a password against a stored hash and salt
-- Returns true or false
local function verifyPassword(password, storedHash, storedSalt)
    if type(password) ~= 'string' or type(storedHash) ~= 'string' or type(storedSalt) ~= 'string' then
        return false -- Cannot verify invalid input types
    end
     -- Check if sha2Lib is available before using it
    if not sha2Lib or type(sha2Lib.sha256) ~= 'function' then
        print("ERROR: sha2Lib not available for verification!")
        return false
    end
    local inputHash = hashPassword(password, storedSalt)
    return inputHash == storedHash
end

-- !!! END OF HASHING USING SHA-256 WITH INSECURE RANDOMNESS !!!


-- Register a new user account (Asynchronous)
-- callback signature: function(err)
function AuthService:registerUser(username, password, callback)
    local normUsername = normalizeUsername(username)
    -- Basic validation - username cannot be empty/invalid after normalization
    if normUsername == "" then
         if callback then callback({message = "Invalid username."}) end
        return
    end
    -- Password validation
    if type(password) ~= 'string' or #password < 8 then -- Basic minimum length
        if callback then callback({message = "Invalid password (must be at least 8 chars)."}) end
        return
    end
    if #password > 256 then -- Prevent excessively long passwords
         if callback then callback({message = "Password is too long."}) end
        return
    end
     -- Check if necessary services/libs are available
    if not usersDS or not json_lib or type(json_lib.encode) ~= 'function' or not sha2Lib or type(sha2Lib.sha256) ~= 'function' then
         print("AuthService.registerUser: Required dependencies (usersDS, json_lib, sha2Lib) not available.")
         if callback then callback({message = "Internal service error. Registration unavailable."}) end
         return
    end


    -- 1. Check if user already exists (Async get)
    usersDS:GetAsync(normUsername, function(getErr, userDataString)
        -- Correct async error handling: Check if getErr exists first.
        if getErr then
             print("AuthService.registerUser: DB error checking user existence '" .. normUsername .. "':", getErr)
             local errorMessage = (type(getErr) == 'table' and getErr.message) or tostring(getErr) or "Unknown database error."
             if callback then callback({message = "Database error checking user existence: " .. errorMessage}) end
             return -- Stop processing on error
        end

        if userDataString then
            print("AuthService.registerUser: Registration failed - user '" .. normUsername .. "' already exists (data found).")
            if callback then callback({message = "Username '" .. normUsername .. "' is already taken."}) end
            return
        end

        print("AuthService.registerUser: User '" .. normUsername .. "' does not exist. Proceeding with registration.")

        local salt = generateSalt()
        local passwordHash = hashPassword(password, salt)

        if not passwordHash then
             print("AuthService.registerUser: Hashing failed for user '" .. normUsername .. "'")
             if callback then callback({message = "Internal error during password hashing."}) end
             return
        end

        -- Initialize user data including profile and badges
        local userAccountData = {
            username = normUsername,
            passwordHash = passwordHash,
            salt = salt,
            registeredAt = os.time(),
            profilePfpUrl = "",
            profileDescription = "",
            badges = {} -- Initialize badges as an empty table
        }

        local okEncode, userDataStringEncoded = pcall(json_lib.encode, userAccountData)
        if not okEncode then
             print("AuthService.registerUser: Failed to encode initial user data for '" .. normUsername .. "':", userDataStringEncoded)
             if callback then callback({message = "Internal error preparing user data."}) end
             return
        end

        -- 3. Store user data (Async set)
        usersDS:SetAsync(normUsername, userDataStringEncoded, function(setErr)
            if setErr then
                print("AuthService: Failed to save new user '" .. normUsername .. "':", setErr)
                 local errorMessage = (type(setErr) == 'table' and setErr.message) or tostring(setErr) or "Unknown database write error."
                if callback then callback({message = "Failed to save user account: " .. errorMessage}) end
            else
                print("AuthService: Successfully registered user '" .. normUsername .. "'.")
                if callback then callback(nil) end -- Success
            end
        end)
    end)
end


-- Authenticate user and create a session (Asynchronous)
-- callback signature: function(err, sessionId, userDetails)
function AuthService:loginUser(username, password, callback)
    local normUsername = normalizeUsername(username)
    if normUsername == "" or type(password) ~= 'string' then
         if callback then callback({message = "Invalid username or password."}, nil, nil) end
         return
    end
    if not usersDS or not json_lib or not sha2Lib or not sessionsDS then
         print("AuthService.loginUser: Required dependencies not available.")
         if callback then callback({message = "Internal service error. Login unavailable."}, nil, nil) end
         return
    end

    -- 1. Get user data
    usersDS:GetAsync(normUsername, function(getErr, userDataString)
         if getErr then
              print("AuthService.loginUser: DB error checking user '" .. normUsername .. "':", getErr)
              local errorMessage = (type(getErr) == 'table' and getErr.message) or tostring(getErr) or "Unknown database error."
              if callback then callback({message = "Database error checking user: " .. errorMessage}, nil, nil) end
              return
         end
         if not userDataString then
              print("AuthService.loginUser: Login attempt failed for '" .. normUsername .. "': User not found.")
              if callback then callback({message = "Invalid username or password."}, nil, nil) end
              return
         end

         print("AuthService.loginUser: User '" .. normUsername .. "' found.")
         local ok, userAccountData = pcall(json_lib.decode, userDataString)
         if not ok or type(userAccountData) ~= 'table' or not userAccountData.passwordHash or not userAccountData.salt then
             print("AuthService: Failed to decode/validate user data for '" .. normUsername .. "'.", userAccountData)
             if callback then callback({message = "Internal error loading user data."}, nil, nil) end
             return
         end

         -- 2. Verify password
         local passwordMatches = verifyPassword(password, userAccountData.passwordHash, userAccountData.salt)
         if not passwordMatches then
            print("AuthService.loginUser: Login attempt failed for '" .. normUsername .. "': Incorrect password.")
             if callback then callback({message = "Invalid username or password."}, nil, nil) end
             return
         end

         -- 3. Create session
         self:createSession(normUsername, function(sessionErr, sessionId)
            if sessionErr then
                print("AuthService: Failed to create session for '" .. normUsername .. "':", sessionErr)
                if callback then callback({message = "Failed to create user session."}, nil, nil) end
            else
                print("AuthService: User '" .. normUsername .. "' logged in. Session created:", sessionId)
                -- Return user details including profile and badges
                local userDetails = {
                    username = userAccountData.username,
                    registeredAt = userAccountData.registeredAt,
                    profilePfpUrl = userAccountData.profilePfpUrl or "",
                    profileDescription = userAccountData.profileDescription or "",
                    badges = userAccountData.badges or {} -- Ensure badges table exists
                }
                if callback then callback(nil, sessionId, userDetails) end -- Success
            end
         end)
    end)
end


-- Create a new session entry (Asynchronous)
-- callback signature: function(err, sessionId)
function AuthService:createSession(userId, callback)
     local userId = tostring(userId)
     if not sessionsDS or not json_lib or not sha2Lib then
          print("AuthService.createSession: Required dependencies not available.")
         if callback then callback({message = "Internal service error. Session creation unavailable."}) end
         return
     end

     -- INSECURE SESSION ID GENERATION (using math.random)
     math.randomseed(os.time() * 1000000 + os.clock() * 1000 + math.random(1, 1000000))
     local randomPart = ""
     local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
     for i = 1, 16 do randomPart = randomPart .. chars:sub(math.random(1, #chars), math.random(1, #chars)) end
     local combinedForId = os.time() .. ":" .. os.clock() .. ":" .. randomPart .. ":" .. userId .. ":" .. tostring(math.random())
     local sessionId = sha2Lib.sha256(combinedForId)

     local sessionData = {
        userId = userId,
        createdAt = os.time(),
        expiresAt = os.time() + AuthService.SESSION_DURATION_SECONDS
     }
     local okEncode, sessionDataString = pcall(json_lib.encode, sessionData)
     if not okEncode then
        print("AuthService.createSession: Failed to encode session data for '" .. userId .. "':", sessionDataString)
        if callback then callback({message = "Internal error preparing session data."}) end
        return
     end

     sessionsDS:SetAsync(sessionId, sessionDataString, function(setErr)
        if setErr then
             print("AuthService: Failed to save session '" .. sessionId .. "':", setErr)
            if callback then callback({message = "Failed to save session."}) end
        else
            if callback then callback(nil, sessionId) end -- Success
        end
     end)
end


-- Get user associated with a session ID (Asynchronous)
-- callback signature: function(err, userDetails)
function AuthService:getSessionUser(sessionId, callback)
    if type(sessionId) ~= 'string' or sessionId == "" then
        if callback then callback(nil, nil) end
        return
    end
    if not sessionsDS or not json_lib or not usersDS then
         print("AuthService.getSessionUser: Required dependencies not available.")
         if callback then callback({message = "Internal service error. Session check unavailable."}, nil) end
         return
     end

    -- 1. Get session data
    sessionsDS:GetAsync(sessionId, function(getErr, sessionDataString)
        if getErr then
             print("AuthService: Error getting session '" .. sessionId .. "':", getErr)
             local errorMessage = (type(getErr) == 'table' and getErr.message) or tostring(getErr) or "Unknown DB error."
             if callback then callback({message = "Database error checking session: " .. errorMessage}, nil) end
             return
        end
        if not sessionDataString then
            if callback then callback(nil, nil) end -- Session not found
            return
        end

        local ok, sessionData = pcall(json_lib.decode, sessionDataString)
         if not ok or type(sessionData) ~= 'table' or not sessionData.userId or not sessionData.expiresAt then
             print("AuthService: Failed to decode/validate session data for '" .. sessionId .. "'.")
             sessionsDS:DeleteAsync(sessionId, function(delErr) if delErr then print("AuthService: Error deleting invalid session:", delErr) end end)
             if callback then callback(nil, nil) end
             return
         end

        -- 2. Check expiry
        if os.time() > sessionData.expiresAt then
             print("AuthService: Session '" .. sessionId .. "' expired. Deleting.")
             sessionsDS:DeleteAsync(sessionId, function(delErr) if delErr then print("AuthService: Error deleting expired session:", delErr) end end)
             if callback then callback(nil, nil) end
             return
        end

        -- 3. Get user data
        usersDS:GetAsync(sessionData.userId, function(userGetErr, userDataString)
            if userGetErr then
                 print("AuthService: Error getting user '" .. sessionData.userId .. "' for session:", userGetErr)
                 local errorMessage = (type(userGetErr) == 'table' and userGetErr.message) or tostring(userGetErr) or "Unknown DB error."
                 if callback then callback({message = "Database error getting user for session: " .. errorMessage}, nil) end
                 return
            end
            if not userDataString then
                 print("AuthService: User '" .. sessionData.userId .. "' not found for valid session '" .. sessionId .. "'. Deleting.")
                 sessionsDS:DeleteAsync(sessionId, function(delErr) if delErr then print("AuthService: Error deleting orphaned session:", delErr) end end)
                 if callback then callback(nil, nil) end
                return
            end

            local okUser, userAccountData = pcall(json_lib.decode, userDataString)
             if not okUser or type(userAccountData) ~= 'table' then
                 print("AuthService: Failed to decode user data for '" .. sessionData.userId .. "' from session.")
                 sessionsDS:DeleteAsync(sessionId, function(delErr) if delErr then print("AuthService: Error deleting session with invalid user data:", delErr) end end)
                 if callback then callback(nil, nil) end
                 return
             end

            -- Success! Return user details including profile and badges
            local userDetails = {
                username = userAccountData.username,
                registeredAt = userAccountData.registeredAt,
                profilePfpUrl = userAccountData.profilePfpUrl or "",
                profileDescription = userAccountData.profileDescription or "",
                badges = userAccountData.badges or {} -- Ensure badges table exists
            }
            if callback then callback(nil, userDetails) end -- Success
        end)
    end)
end


-- Delete a user session (Asynchronous)
-- callback signature: function(err)
function AuthService:logout(sessionId, callback)
    if type(sessionId) ~= 'string' or sessionId == "" then
         if callback then callback(nil) end
         return
    end
     if not sessionsDS then
         print("AuthService.logout: Required service (sessionsDS) not available.")
         if callback then callback({message = "Internal service error. Logout unavailable."}) end
         return
     end

    sessionsDS:DeleteAsync(sessionId, function(deleteErr)
        if deleteErr then
            print("AuthService: Error deleting session '" .. sessionId .. "':", deleteErr)
            local errorMessage = (type(deleteErr) == 'table' and deleteErr.message) or tostring(deleteErr) or "Unknown DB delete error."
            if callback then callback({message = "Failed to delete session: " .. errorMessage}) end
        else
            print("AuthService: Session '" .. sessionId .. "' deleted (if it existed).")
            if callback then callback(nil) end -- Success
        end
    end)
end


-- Update user profile information (PFP URL, Description) - Asynchronous
-- callback signature: function(err)
function AuthService:updateUserProfile(username, pfpUrl, description, callback)
    local normUsername = normalizeUsername(username)
    if normUsername == "" then
        if callback then callback({message = "Invalid username provided."}) end
        return
    end
    if not usersDS or not json_lib then
        print("AuthService.updateUserProfile: Required dependencies (usersDS, json_lib) not available.")
        if callback then callback({message = "Internal service error. Update unavailable."}) end
        return
    end

    -- 1. Get current user data
    usersDS:GetAsync(normUsername, function(getErr, userDataString)
        if getErr then
            print("AuthService.updateUserProfile: DB error fetching user '" .. normUsername .. "':", getErr)
            local errorMessage = (type(getErr) == 'table' and getErr.message) or tostring(getErr) or "Unknown DB error."
            if callback then callback({message = "Database error fetching user data: " .. errorMessage}) end
            return
        end
        if not userDataString then
            print("AuthService.updateUserProfile: Cannot update non-existent user '" .. normUsername .. "'.")
            if callback then callback({message = "User not found, cannot update profile."}) end
            return
        end

        -- 2. Decode user data
        local ok, userAccountData = pcall(json_lib.decode, userDataString)
        if not ok or type(userAccountData) ~= 'table' then
            print("AuthService.updateUserProfile: Failed to decode user data for '" .. normUsername .. "'.")
            if callback then callback({message = "Internal error loading user data for update."}) end
            return
        end

        -- 3. Update relevant fields
        userAccountData.profilePfpUrl = tostring(pfpUrl or "")
        userAccountData.profileDescription = tostring(description or "")
        -- IMPORTANT: Do NOT modify badges here.

        -- 4. Encode updated data
        local okEncode, updatedUserDataString = pcall(json_lib.encode, userAccountData)
        if not okEncode then
            print("AuthService.updateUserProfile: Failed to encode updated user data for '" .. normUsername .. "':", updatedUserDataString)
            if callback then callback({message = "Internal error preparing user data for saving."}) end
            return
        end

        -- 5. Save updated data
        usersDS:SetAsync(normUsername, updatedUserDataString, function(setErr)
            if setErr then
                print("AuthService.updateUserProfile: Failed to save updated profile for '" .. normUsername .. "':", setErr)
                local errorMessage = (type(setErr) == 'table' and setErr.message) or tostring(setErr) or "Unknown DB write error."
                if callback then callback({message = "Failed to save profile update: " .. errorMessage}) end
            else
                print("AuthService.updateUserProfile: Successfully updated profile for user '" .. normUsername .. "'.")
                if callback then callback(nil) end -- Success!
            end
        end)
    end)
end

-- NOTE: Functions to grant/revoke badges would go here.
-- Example structure (needs implementation):
-- function AuthService:grantBadge(adminUser, targetUsername, badgeId, callback) ... end
-- function AuthService:revokeBadge(adminUser, targetUsername, badgeId, callback) ... end


return AuthService
--- END OF FILE AuthService.lua ---