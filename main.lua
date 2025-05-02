--[[
       Made by _alexmiles_ (yes i talk to myself in my own code lol)
          Cuz i was bored xddd

          Version: 0.5.3-alpha (Dynamic Badge Management + Debug Logs)

          TODO:
            - Implement Badge Assignment (Admin UI/Commands)
            - Use templates?
            - Add moderation/review for user submissions?
            - Improve error handling and user feedback?
            - Further refactor static file serving?
            - **Replace math.random with a CSPRNG for security!**
            - **Consider a slow password hash algorithm (like bcrypt) for security!**
            - **Add HTTPS for transport security.**
            - Handle actual PFP uploads instead of URLs.
]]

local http = require('http')
local fs = require('fs')
local path = require('path')
local url = require('url')
local timer = require('timer')
local json = require('json') -- Used directly and passed to libs
local querystring = require('querystring') -- Used directly and passed to libs
local sha2 = require('sha2') -- Required directly and passed to libs


-- Library injection setup
local libs = {}
libs['http'] = http
libs['fs'] = fs
libs["path"] = path
libs['url'] = url
libs['json'] = json
libs['querystring'] = querystring
libs['timer'] = timer
libs['sha2'] = sha2

local function require2(modulename)
  local m_status, m = pcall(require, modulename) -- Use pcall to safely require
  if not m_status or not m or type(m) ~= 'table' then
     print("ERROR: Failed to load module '" .. modulename .. "'. Error: " .. tostring(m))
     return nil -- Return nil on failure
  end
  m['libs'] = libs
  return m
end

local root = process.cwd()

-- --- Load Services ---
local Services = {}
local Start = os.clock()
Services['JsonService'] = require2('JsonService')
Services['UtilService'] = require2('UtilService')
Services['DatastoreService'] = require2('DatastoreService')
Services['AuthService'] = require2('AuthService')
Services['KnowledgeService'] = require2('KnowledgeService')
Services['ContentService'] = require2('ContentService')
Services['BadgeService'] = require2('BadgeService') -- <<< Load BadgeService
Services['HtmlService'] = require2('HtmlService')

-- --- Service Initialization ---
-- Ensure DatastoreService is loaded before others depend on it
if not Services['DatastoreService'] or not Services['DatastoreService']:init(root) then
  print("FATAL ERROR: DataStoreService failed to initialize. Exiting.")
  return
end
if not Services['AuthService'] or not Services['AuthService']:init(Services['DatastoreService'], libs, libs['sha2']) then
    print("FATAL ERROR: AuthService failed to initialize. Authentication features disabled.")
    Services['AuthService'] = nil
end
if not Services['KnowledgeService'] then
    print("FATAL ERROR: KnowledgeService failed to load.")
    -- No need to set to nil, require2 handles failed load check
elseif not Services['KnowledgeService'].loadKnowledgeBase then
     print("WARNING: KnowledgeService missing loadKnowledgeBase function.")
end
if not Services['ContentService'] or not Services['ContentService']:init(Services['KnowledgeService']) then
    print("FATAL ERROR: ContentService failed to initialize.")
    Services['ContentService'] = nil
end
-- Initialize BadgeService
if not Services['BadgeService'] or not Services['BadgeService']:init(Services['DatastoreService'], libs) then
     print("FATAL ERROR: BadgeService failed to initialize.")
     Services['BadgeService'] = nil
end
if not Services['HtmlService'] or not Services['HtmlService']:init(Services['UtilService'], Services['ContentService']) then
     print("FATAL ERROR: HtmlService failed to initialize.")
     Services['HtmlService'] = nil
end
local ServicesInitTime = os.clock() - Start
print('Services loaded. Took '..tostring(ServicesInitTime)..' seconds')

-- --- Helper Functions ---

local function sanitizePath(reqPath)
  if type(reqPath) ~= 'string' then return nil end
  local safePath = path.normalize(reqPath)
  if string.find(safePath, '^%.%.[/\\]') or string.find(safePath, '[/\\]%.%.[/\\]') or string.find(safePath, '[/\\]%.%.$') or safePath == ".." then
    print("Warning: Potential path traversal blocked: " .. reqPath .. " -> " .. safePath); return nil
  end
  if safePath:sub(1,1) == '/' or safePath:sub(1,1) == '\\' then safePath = safePath:sub(2) end
  local fullPath = path.join(root, safePath)
  local canonicalRoot = path.normalize(root)
  if not (fullPath:sub(1, #canonicalRoot + 1) == (canonicalRoot .. path.sep) or fullPath == canonicalRoot) then
       print("Warning: Attempted access outside root directory blocked: " .. reqPath .. " -> " .. fullPath); return nil
  end
  return fullPath
end


local function getMimeType(filePath)
  if type(filePath) ~= 'string' then return 'application/octet-stream' end
  local extension = string.match(filePath, "%.([^.]+)$")
  if not extension then return 'application/octet-stream' end
  extension = string.lower(extension)
  local mimeTypes = {
    txt = 'text/plain', html = 'text/html', htm = 'text/html', css = 'text/css',
    js = 'application/javascript', json = 'application/json', xml = 'application/xml',
    jpg = 'image/jpeg', jpeg = 'image/jpeg', png = 'image/png', gif = 'image/gif',
    svg = 'image/svg+xml', ico = 'image/x-icon', webp = 'image/webp',
  }
  return mimeTypes[extension] or 'application/octet-stream'
end

local function parseCookies(cookieHeader)
    local cookies = {}
    if type(cookieHeader) == 'string' and cookieHeader ~= '' then
        for cookie_pair in string.gmatch(cookieHeader, "[^;]+") do
            local name, value = string.match(cookie_pair, "^%s*(.-)=%s*(.*)$")
            if name then cookies[name] = value end
        end
    end
    return cookies
end

-- Authorization Helper
local function isAdmin(user)
    if not user or type(user.badges) ~= 'table' then
        return false  
    end
    for key, badgeId in ipairs(user.badges) do
        print(key, badgeId)
      
      if badgeId == 'admin' then
            return true
        elseif badgeId == "owner" then
          return true
        end
    end
    return false
end


-- --- Middleware to attach user data to request ---
local function attachUserMiddleware(req, res, next)
    local cookieHeader = req.headers['cookie']
    local cookies = parseCookies(cookieHeader)
    local sessionId = cookies['session_id']

    if not Services['AuthService'] or not sessionId then
         req.user = nil
         next(req, res)
         return
    end

    Services['AuthService']:getSessionUser(sessionId, function(err, userDetails)
        if err then
            print("Middleware Error getting session user:", (type(err)=='table' and err.message) or tostring(err))
            req.user = nil
        else
            req.user = userDetails -- includes profile info and badges
        end
        next(req, res)
    end)
end

-- --- Initialization (Data & Timers) ---
if Services['KnowledgeService'] and Services['KnowledgeService'].loadKnowledgeBase then
    Services['KnowledgeService']:loadKnowledgeBase()
else
    print("KnowledgeService not initialized or loadKnowledgeBase missing, skipping knowledge base load.")
end

print("Setting initial QOTD...")
if Services['ContentService'] and Services['ContentService'].updateQotd then
    Services['ContentService']:updateQotd()
else
    print("ContentService not initialized or updateQotd missing, cannot set QOTD.")
end

local Mins = 5 -- Update QOTD
local InMillis = Mins * 60 * 1000
if libs['timer'] and Services['ContentService'] and Services['ContentService'].updateQotd then
    timer.setInterval(InMillis, function()
        if Services['ContentService'] and Services['ContentService'].updateQotd then
            Services['ContentService']:updateQotd()
        end
    end)
    print("QOTD will update every " .. Mins .. " minutes.")
else
    print("Timer library or ContentService (with updateQotd) not available. QOTD will not auto-update.")
end


-- --- HTTP Server Logic ---
local port = process.env.PORT or 80

http.createServer(function (req, res)
    attachUserMiddleware(req, res, function(req, res) -- Apply middleware first

        local parsedUrl = url.parse(req.url, true)
        local pathname = parsedUrl.pathname
        local query = parsedUrl.query or {}

        -- Helper to get error message from error object/string
        local function getErrMsg(err)
             return (type(err) == 'table' and err.message) or tostring(err or "Unknown error")
        end

        local userStatus = req.user and ("Logged in as: " .. req.user.username .. (isAdmin(req.user) and " (Admin)" or "")) or "Not logged in"
        print(os.date("%Y-%m-%d %H:%M:%S") .." - Request: " .. req.method .. " " .. pathname .. " | " .. userStatus)

        -- Helper Functions for Responses
        local function sendHtml(pageType, pageData, statusMsg)
            if not Services['HtmlService'] or not Services['HtmlService'].generateHtml then
                 res:writeHead(500, {['Content-Type'] = 'text/plain'}); res:finish("Internal Server Error: HTML Service not initialized.")
                 print("  -> FATAL: HtmlService not initialized.")
                 return
            end
            pageData = pageData or {}
            pageData.currentPath = pathname -- Add current path for nav highlighting
            local htmlContent = Services['HtmlService']:generateHtml(pageType, pageData, statusMsg, req.user)
            res:writeHead(200, {['Content-Type'] = 'text/html; charset=utf-8'})
            res:finish(htmlContent)
        end

        local function sendNotFound(message)
            if not Services['HtmlService'] or not Services['HtmlService'].generateHtml then
                res:writeHead(404, {['Content-Type'] = 'text/plain'}); res:finish("404 Not Found: HTML Service unavailable.")
                print("  -> FATAL: HtmlService not initialized for 404.")
                return
            end
            local htmlContent = Services['HtmlService']:generateHtml('notfound', {currentPath = pathname}, message or "Page not found.", req.user)
            res:writeHead(404, {['Content-Type'] = 'text/html; charset=utf-8'})
            res:finish(htmlContent)
            print("  -> Responded with 404 page")
        end

        local function sendError(statusCode, message, logMessage)
            statusCode = statusCode or 500
            message = message or "Internal Server Error"
            logMessage = logMessage or message
            res:writeHead(statusCode, {['Content-Type'] = 'text/plain; charset=utf-8'})
            res:finish(message)
            print("  -> Responded with Error " .. statusCode .. ": " .. logMessage)
        end

         local function sendForbidden(logMessage)
             logMessage = logMessage or "Access denied"
             print("  -> Forbidden:", logMessage)
             if Services['HtmlService'] then
                 local htmlContent = Services['HtmlService']:generateHtml('notfound', {currentPath = pathname}, "403 - Forbidden: You do not have permission to access this page.", req.user)
                 res:writeHead(403, {['Content-Type'] = 'text/html; charset=utf-8'})
                 res:finish(htmlContent)
             else
                 sendError(403, "Forbidden")
             end
         end

        -- --- Routing Logic ---

        -- Route: / (Home) - GET
        if pathname == '/' and req.method == 'GET' then
            sendHtml('home')

        -- Route: /ask - GET
        elseif pathname == '/ask' and req.method == 'GET' then
            local question = query.question or ""
            question = question:match("^%s*(.-)%s*$")
            local answerData
            if question ~= "" and Services['KnowledgeService'] and Services['KnowledgeService'].getAnswer then
                 answerData = Services['KnowledgeService']:getAnswer(question)
            end
            sendHtml('ask', { question = question, answerData = answerData })

        -- Route: /add - GET (Show form)
        elseif pathname == '/add' and req.method == 'GET' then
            local statusMsg = ""
            if query.status == 'success' then statusMsg = "Success! Your question was added."
            elseif query.status == 'fail' then statusMsg = "Error: Could not add question. " .. (Services['UtilService'] and Services['UtilService'].urlDecodeComponent and query.reason and Services['UtilService']:urlDecodeComponent(query.reason) or "")
            elseif query.status == 'empty' then statusMsg = "Error: Question and Answer cannot be empty."
            elseif query.status == 'unauthorized' then statusMsg = "You must be logged in to add questions." end
            sendHtml('add', nil, statusMsg)

        -- Route: /add - POST (Handle submission)
        elseif pathname == '/add' and req.method == 'POST' then
            if not req.user then sendForbidden("Anonymous user cannot POST /add"); return end
            if not Services['KnowledgeService'] or not Services['UtilService'] then sendError(500, "Service Unavailable"); return end

            local body = ''
            req:on('data', function(chunk) body = body .. chunk end)
            req:on('end', function()
                local postData = nil
                local ok, parsed = pcall(libs.querystring.parse, body)
                if not ok or type(parsed) ~= 'table' then sendError(400, "Bad Request", "Failed parsing /add POST"); return end
                postData = parsed

                local new_q = postData.new_question or ""
                local new_a = postData.new_answer or ""

                if Services['KnowledgeService'].normalizeQuestion(new_q) == "" or new_a:match("^%s*(.-)%s*$") == "" then
                    res:writeHead(303, {['Location'] = '/add?status=empty'}); res:finish(); return
                end

                local username = req.user.username
                local success, msg = Services['KnowledgeService']:addQA(new_q, new_a, username)
                if success then
                  res:writeHead(303, {['Location'] = '/add?status=success'}); print("  -> Add successful by user '" .. username .. "'")
                else
                  local reason = Services['UtilService']:urlEncodeComponent(msg or "Unknown reason")
                  res:writeHead(303, {['Location'] = '/add?status=fail&reason=' .. reason}); print("  -> Add failed by user '" .. username .. "'. Reason:", msg)
                end
                res:finish()
            end)
            req:on('error', function(err) print("Request stream error on POST /add:", err); sendError(500, nil, "Stream error on POST /add") end)

        -- Route: /qotd - GET
        elseif pathname == '/qotd' and req.method == 'GET' then
             if not Services['ContentService'] then sendHtml('qotd', { question = "Service Unavailable", answer = "Content service is not initialized." })
             else sendHtml('qotd') end

        -- Route: /about - GET
        elseif pathname == '/about' and req.method == 'GET' then
             if not Services['ContentService'] then sendHtml('about', { title = "Service Unavailable", text = "Content service is not initialized." })
             else sendHtml('about') end

        -- Route: /register - GET (Show form)
        elseif pathname == '/register' and req.method == 'GET' then
             local statusMsg = ""
             if query.status == 'success' then statusMsg = "Registration successful! You can now log in."
             elseif query.status == 'fail' then statusMsg = "Registration failed. " .. (Services['UtilService'] and Services['UtilService'].urlDecodeComponent and query.reason and Services['UtilService']:urlDecodeComponent(query.reason) or "")
             elseif query.status == 'invalid' then statusMsg = "Invalid username or password." end
             sendHtml('register', nil, statusMsg)

        -- Route: /register - POST (Handle registration)
        elseif pathname == '/register' and req.method == 'POST' then
             if req.user then sendError(400, "Bad Request: Already logged in."); return end
             if not Services['AuthService'] or not Services['UtilService'] then sendError(500, "Service Unavailable"); return end

             local body = ''
             req:on('data', function(chunk) body = body .. chunk end)
             req:on('end', function()
                 local postData = nil
                 local ok, parsed = pcall(libs.querystring.parse, body)
                 if not ok or type(parsed) ~= 'table' then sendError(400, "Bad Request", "Failed parsing /register POST"); return end
                 postData = parsed

                 local username = postData.username or ""
                 local password = postData.password or ""

                 Services['AuthService']:registerUser(username, password, function(err)
                     if err then
                         local errMsg = getErrMsg(err)
                         print("  -> Registration failed for '" .. username .. "':", errMsg)
                         local reason = Services['UtilService']:urlEncodeComponent(errMsg)
                         res:writeHead(303, {['Location'] = '/register?status=fail&reason=' .. reason})
                     else
                         print("  -> Registration successful for '" .. username .. "'.")
                         res:writeHead(303, {['Location'] = '/register?status=success'})
                     end
                     res:finish()
                 end)
             end)
             req:on('error', function(err) print("Request stream error on POST /register:", err); sendError(500, nil, "Stream error on POST /register") end)

        -- Route: /profile/edit - GET (Show edit form for logged-in user)
        elseif pathname == '/profile/edit' and req.method == 'GET' then
            if not req.user then res:writeHead(303, {['Location'] = '/login?status=unauthorized'}); res:finish(); print("  -> Blocked GET /profile/edit: Not logged in"); return end
            -- Middleware ensures req.user exists if logged in

            local statusMsg = ""
            if query.status == 'success' then statusMsg = "Profile updated successfully!"
            elseif query.status == 'fail' then statusMsg = "Failed to update profile. " .. (Services['UtilService'] and Services['UtilService'].urlDecodeComponent and query.reason and Services['UtilService']:urlDecodeComponent(query.reason) or "") end

            sendHtml('profile_edit', { profileData = req.user }, statusMsg)
            print("  -> Sent profile edit page for " .. req.user.username)


        -- Route: /profile/edit - POST (Handle profile update)
        elseif pathname == '/profile/edit' and req.method == 'POST' then
            if not req.user then sendForbidden("Anonymous user cannot POST /profile/edit"); return end
            if not Services['AuthService'] or not Services['UtilService'] then sendError(500, "Service Unavailable"); return end

            local body = ''
            req:on('data', function(chunk) body = body .. chunk end)
            req:on('end', function()
                local postData = nil
                local ok, parsed = pcall(libs.querystring.parse, body)
                if not ok or type(parsed) ~= 'table' then sendError(400, "Bad Request", "Failed parsing /profile/edit POST"); return end
                postData = parsed
                local pfpUrl = postData.profilePfpUrl
                local description = postData.profileDescription

                Services['AuthService']:updateUserProfile(req.user.username, pfpUrl, description, function(updateErr)
                    if updateErr then
                         local errMsg = getErrMsg(updateErr)
                         print("  -> Error POST /profile/edit: Failed update for " .. req.user.username .. ":", errMsg)
                         local reason = Services['UtilService']:urlEncodeComponent(errMsg)
                         res:writeHead(303, {['Location'] = '/profile/edit?status=fail&reason=' .. reason})
                    else
                         print("  -> Success POST /profile/edit: Profile updated for " .. req.user.username)
                          local encodedUsername = Services['UtilService']:urlEncodeComponent(req.user.username)
                         res:writeHead(303, {['Location'] = '/profile/' .. encodedUsername .. '?status=editsuccess'})
                    end
                    res:finish()
                end)
            end)
            req:on('error', function(err) print("Request stream error on POST /profile/edit:", err); sendError(500, nil, "Stream error on POST /profile/edit") end)

         -- Route: /profile/:username - GET (View user profile)
        elseif string.match(pathname, '^/profile/([^/]+)$') and req.method == 'GET' then
            local encodedUsername = string.match(pathname, '^/profile/([^/]+)$')
             local targetUsername_raw = ""
             if Services['UtilService'] and Services['UtilService'].urlDecodeComponent then
                 local decode_ok, decoded_val = pcall(Services['UtilService'].urlDecodeComponent, Services['UtilService'], encodedUsername)
                 if decode_ok then targetUsername_raw = decoded_val or ""
                 else print("  -> WARNING GET /profile/: pcall decode failed:", tostring(decoded_val)); targetUsername_raw = encodedUsername end
             else print("  -> WARNING GET /profile/: UtilService missing."); targetUsername_raw = encodedUsername end

             local targetUsername = ""
             if Services['AuthService'] and Services['AuthService'].normalizeUsername then targetUsername = Services['AuthService'].normalizeUsername(targetUsername_raw)
             else print("  -> WARNING GET /profile/: AuthService missing.") end

             if targetUsername == "" then print("  -> GET /profile/: Invalid username:", targetUsername_raw); sendNotFound("Invalid profile URL."); return end
             print("  -> Requesting profile view for:", targetUsername)

             -- Check required services
             if not Services['AuthService'] or not Services['DatastoreService'] or not Services['JsonService'] or not Services['KnowledgeService'] or not Services['BadgeService'] then
                  print("  -> Error GET /profile/:username: Missing required services")
                  sendError(500, "Internal Server Error: Services unavailable.", "Missing services for /profile/:username")
                  return
             end

             local usersDS = Services['DatastoreService']:GetDataStore('users')
             if not usersDS then print("  -> Error GET /profile/:username: Could not get users datastore"); sendError(500, "Internal Server Error.", "Failed to get usersDS for /profile/:username"); return end

             -- 1. Get User Profile Data
             usersDS:GetAsync(targetUsername, function(getErr, userDataString)
                if getErr then local errMsg = getErrMsg(getErr); print("  -> Error GET /profile/:username: Fetching user " .. targetUsername .. ":", errMsg); sendError(500, "Error loading profile."); return end
                if not userDataString then print("  -> GET /profile/:username: User profile not found for " .. targetUsername); sendNotFound("User profile not found."); return end
                if userDataString == "" then print("  -> WARNING GET /profile/:username: User data is empty for " .. targetUsername); sendError(500, "Error loading profile data."); return end

                local profileData = {}
                local ok, decoded = pcall(Services['JsonService'].Decode, Services['JsonService'], userDataString)
                if not ok or type(decoded) ~= 'table' then print("  -> Error GET /profile/:username: Decoding data for " .. targetUsername .. ":", decoded); print("       String:", tostring(userDataString)); sendError(500, "Error loading profile data."); return end
                profileData = decoded

                print("  -> DEBUG /profile/: Decoded profileData:", tostring(profileData)) -- DEBUG LOG

                profileData.username = profileData.username or targetUsername
                profileData.registeredAt = profileData.registeredAt or nil
                profileData.profilePfpUrl = profileData.profilePfpUrl or ""
                profileData.profileDescription = profileData.profileDescription or ""
                profileData.badges = profileData.badges or {}

                -- 2. Get Questions by Author (Sync)
                local userQuestions = Services['KnowledgeService']:getQuestionsByAuthor(targetUsername)
                print("  -> Found", #userQuestions, "questions for author:", targetUsername)

                -- 3. Get ALL Badge Definitions (Async)
                Services['BadgeService']:getAllBadgeDefinitionsAsync(function(badgeErr, allBadgeDefs)
                     if badgeErr then
                          print("  -> Error GET /profile/:username: Fetching badge definitions:", getErrMsg(badgeErr))
                          allBadgeDefs = {}
                     end

                     print("  -> DEBUG /profile/: Fetched allBadgeDefs:", tostring(allBadgeDefs)) -- DEBUG LOG

                     local statusMsg = ""
                     if query.status == 'editsuccess' then statusMsg = "Profile updated successfully!" end

                     local pageDataForHtml = {
                        profileData = profileData,
                        userQuestions = userQuestions,
                        allBadgeDefs = allBadgeDefs
                     }
                     print("  -> DEBUG /profile/: Sending pageDataForHtml to HtmlService:", tostring(pageDataForHtml)) -- DEBUG LOG

                     -- 4. Render the page
                     sendHtml('profile_view', pageDataForHtml, statusMsg)
                     print("  -> Sent profile view page for " .. targetUsername)
                end)
             end)

        -- Route: /login - GET (Show form)
        elseif pathname == '/login' and req.method == 'GET' then
             if req.user then res:writeHead(303, {['Location'] = '/'}); res:finish(); return end
             local statusMsg = ""
             if query.status == 'fail' then statusMsg = "Login failed. Invalid username or password."
             elseif query.status == 'loggedout' then statusMsg = "You have been logged out."
             elseif query.status == 'unauthorized' then statusMsg = "Please log in to access that page." end
             sendHtml('login', nil, statusMsg)

        -- Route: /login - POST (Handle login)
        elseif pathname == '/login' and req.method == 'POST' then
             if req.user then sendError(400, "Bad Request: Already logged in."); return end
             if not Services['AuthService'] or not Services['UtilService'] then sendError(500, "Service Unavailable"); return end

             local body = ''
             req:on('data', function(chunk) body = body .. chunk end)
             req:on('end', function()
                local postData = nil
                if body == "" then sendError(400, "Bad Request", "Login POST empty body"); return end
                local ok, parsed = pcall(libs.querystring.parse, body)
                if not ok or type(parsed) ~= 'table' then sendError(400, "Bad Request", "Login POST parse failed"); return end
                postData = parsed
                if not postData.username or not postData.password then sendError(400, "Bad Request", "Login POST missing credentials"); return end
                local username = postData.username
                local password = postData.password

                Services['AuthService']:loginUser(username, password, function(err, sessionId, userDetails)
                    if err then local errMsg = getErrMsg(err); print("  -> Login failed for '" .. username .. "':", errMsg); res:writeHead(303, {['Location'] = '/login?status=fail'}); res:finish()
                    else
                        print("  -> Login successful for '" .. username .. "'.")
                        if not sessionId or not Services['AuthService'].SESSION_DURATION_SECONDS then print("ERROR: Missing sessionId/duration post-login!"); sendError(500); return end
                        local cookieValue = 'session_id=' .. sessionId .. '; HttpOnly; Path=/; Max-Age=' .. Services['AuthService'].SESSION_DURATION_SECONDS .. '; SameSite=Lax'
                        local responseHeaders = { ['Location'] = '/', ['Set-Cookie'] = cookieValue }
                        print("  -> Setting cookie and redirecting...")
                        res:writeHead(303, responseHeaders); res:finish()
                    end
                end)
            end)
            req:on('error', function(err) print("Request stream error on POST /login:", err); sendError(500, nil, "Stream error on POST /login") end)

        -- Route: /logout - GET
        elseif pathname == '/logout' and req.method == 'GET' then
             local cookieHeader = req.headers['cookie']
             local cookies = parseCookies(cookieHeader)
             local sessionId = cookies['session_id']
             res:setHeader('Set-Cookie', 'session_id=; HttpOnly; Path=/; Max-Age=0; SameSite=Lax')
             if not sessionId or not Services['AuthService'] or not Services['AuthService'].logout then
                 res:writeHead(303, {['Location'] = '/'}); res:finish(); print("  -> Logout: No session or AuthService unavailable."); return
             end
             Services['AuthService']:logout(sessionId, function(err)
                 if err then local errMsg = getErrMsg(err); print("  -> Logout failed:", errMsg); res:writeHead(303, {['Location'] = '/'})
                 else print("  -> Logout successful."); res:writeHead(303, {['Location'] = '/login?status=loggedout'}) end
                 res:finish()
             end)

        -- START Admin Badge Routes --
        elseif string.match(pathname, '^/admin/badges') then
             if not isAdmin(req.user) then sendForbidden("User not admin for admin section"); return end
             if not Services['BadgeService'] or not Services['UtilService'] then sendError(500, "Admin Service Unavailable"); return end

             -- Route: /admin/badges - GET (List badges)
             if pathname == '/admin/badges' and req.method == 'GET' then
                 local statusMsg = ""
                 if query.status == 'success_add' then statusMsg = "Success: Badge created."
                 elseif query.status == 'success_edit' then statusMsg = "Success: Badge updated."
                 elseif query.status == 'success_delete' then statusMsg = "Success: Badge deleted."
                 elseif query.status == 'fail' then statusMsg = "Error: " .. (Services['UtilService']:urlDecodeComponent(query.reason or "Unknown error")) end

                 Services['BadgeService']:getAllBadgeDefinitionsAsync(function(err, badgesMap)
                     if err then print("  -> Error getting all badges:", getErrMsg(err)); sendHtml('admin_badge_list', nil, "Error loading badges: " .. getErrMsg(err))
                     else sendHtml('admin_badge_list', { badgesMap = badgesMap }, statusMsg) end
                 end)

             -- Route: /admin/badges/add - GET (Show add form)
             elseif pathname == '/admin/badges/add' and req.method == 'GET' then
                 sendHtml('admin_badge_add')

             -- Route: /admin/badges/add - POST (Handle add submission)
             elseif pathname == '/admin/badges/add' and req.method == 'POST' then
                  local body = ''
                  req:on('data', function(chunk) body = body .. chunk end)
                  req:on('end', function()
                      local postData = nil
                      local ok, parsed = pcall(libs.querystring.parse, body)
                      if not ok or type(parsed) ~= 'table' then sendError(400, "Bad Request", "Failed parsing /admin/badges/add POST"); return end
                      postData = parsed
                      local badgeData = { id = postData.id, name = postData.name, description = postData.description, imageUrl = postData.imageUrl, color = postData.color_text or postData.color }

                      Services['BadgeService']:createBadgeAsync(badgeData, function(createErr, createdBadge)
                          if createErr then local reason = Services['UtilService']:urlEncodeComponent(getErrMsg(createErr)); res:writeHead(303, {['Location'] = '/admin/badges?status=fail&reason=' .. reason})
                          else res:writeHead(303, {['Location'] = '/admin/badges?status=success_add'}) end
                          res:finish()
                      end)
                  end)
                  req:on('error', function(err) print("Request stream error POST /admin/badges/add:", err); sendError(500) end)

             -- Route: /admin/badges/edit/:badgeId - GET (Show edit form)
             elseif string.match(pathname, '^/admin/badges/edit/([^/]+)$') and req.method == 'GET' then
                  local encodedBadgeId = string.match(pathname, '^/admin/badges/edit/([^/]+)$')
                  local badgeId = Services['UtilService']:urlDecodeComponent(encodedBadgeId)
                  if badgeId == "" then sendNotFound("Invalid badge ID."); return end

                  Services['BadgeService']:getBadgeDefinitionAsync(badgeId, function(getErr, badgeData)
                      if getErr then sendHtml('admin_badge_list', nil, "Error loading badge: " .. getErrMsg(getErr))
                      elseif not badgeData then sendHtml('admin_badge_list', nil, "Error: Badge '" .. badgeId .. "' not found.")
                      else sendHtml('admin_badge_edit', { badgeData = badgeData }) end
                  end)

             -- Route: /admin/badges/edit/:badgeId - POST (Handle edit submission)
             elseif string.match(pathname, '^/admin/badges/edit/([^/]+)$') and req.method == 'POST' then
                  local encodedBadgeId = string.match(pathname, '^/admin/badges/edit/([^/]+)$')
                  local badgeId = Services['UtilService']:urlDecodeComponent(encodedBadgeId)
                  if badgeId == "" then sendNotFound("Invalid badge ID."); return end

                  local body = ''
                  req:on('data', function(chunk) body = body .. chunk end)
                  req:on('end', function()
                      local postData = nil
                      local ok, parsed = pcall(libs.querystring.parse, body)
                      if not ok or type(parsed) ~= 'table' then sendError(400, "Bad Request", "Failed parsing /admin/badges/edit POST"); return end
                      postData = parsed
                      local badgeData = { name = postData.name, description = postData.description, imageUrl = postData.imageUrl, color = postData.color_text or postData.color }

                      Services['BadgeService']:updateBadgeAsync(badgeId, badgeData, function(updateErr, updatedBadge)
                          if updateErr then local reason = Services['UtilService']:urlEncodeComponent(getErrMsg(updateErr)); res:writeHead(303, {['Location'] = '/admin/badges?status=fail&reason=' .. reason})
                          else res:writeHead(303, {['Location'] = '/admin/badges?status=success_edit'}) end
                          res:finish()
                      end)
                  end)
                  req:on('error', function(err) print("Request stream error POST /admin/badges/edit:", err); sendError(500) end)

             -- Route: /admin/badges/delete/:badgeId - POST (Handle delete)
             elseif string.match(pathname, '^/admin/badges/delete/([^/]+)$') and req.method == 'POST' then
                  local encodedBadgeId = string.match(pathname, '^/admin/badges/delete/([^/]+)$')
                  local badgeId = Services['UtilService']:urlDecodeComponent(encodedBadgeId)
                  if badgeId == "" then sendNotFound("Invalid badge ID."); return end

                  Services['BadgeService']:deleteBadgeAsync(badgeId, function(deleteErr)
                       if deleteErr then local reason = Services['UtilService']:urlEncodeComponent(getErrMsg(deleteErr)); res:writeHead(303, {['Location'] = '/admin/badges?status=fail&reason=' .. reason})
                       else res:writeHead(303, {['Location'] = '/admin/badges?status=success_delete'}) end
                       res:finish()
                  end)

             -- Fallback for unknown /admin/badges routes
             else
                 sendNotFound("Admin badge page not found.")
             end
        -- END Admin Badge Routes --

        -- Route: /favicon.ico - GET
        elseif pathname == '/favicon.ico' and req.method == 'GET' then
             local filePath = sanitizePath("images/favicon.ico")
              if not filePath then sendNotFound(); return end
              local ok, stat = pcall(fs.statSync, filePath)
              if not ok or not stat or stat.type ~= 'file' then sendNotFound(); print("  -> Favicon file not found: " .. filePath); return end
              fs.readFile(filePath, function (err, data)
                  if err then print("  -> Server Error reading favicon: " .. err.message); sendError(500)
                  else res:writeHead(200, {['Content-Type'] = 'image/x-icon'}); res:finish(data) end
              end)

        -- Route: Static files (CSS, Images) - GET
        elseif (pathname == '/style.css' or string.match(pathname, '^/images/')) and req.method == 'GET' then
             local relativePath = pathname:sub(2)
             local filePath = sanitizePath(relativePath)
             if not filePath then sendNotFound(); return end
             local ok, stat = pcall(fs.statSync, filePath)
             if not ok or not stat or stat.type ~= 'file' then sendNotFound(); print("  -> Static file not found: " .. filePath); return end
             fs.readFile(filePath, function (err, data)
               if err then print("  -> Server Error reading static file: " .. err.message); sendNotFound()
               else local contentType = getMimeType(filePath); res:writeHead(200, {['Content-Type'] = contentType}); res:finish(data) end
             end)

        -- Route: 404 Not Found (Default)
        else
            sendNotFound()
             print("  -> Unhandled path/method: " .. req.method .. " " .. pathname)
        end

    end) -- End of middleware's next() call
end):listen(port, function()
    print("------------------------------------------")
    print("SeaDrive Server")
    print("Version: 0.5.3-alpha (Dynamic Badge Management + Debug Logs)")
    print("Knowledge Source: " .. (Services['KnowledgeService'] and "knowledge_base.json" or "Unavailable"))
    print("Listening on http://localhost:" .. port)
    print("Root directory: " .. root)
    print("Available pages: / (Home), /ask, /add, /qotd, /about, /register, /login, /logout, /profile/:user, /profile/edit")
    print("Admin pages: /admin/badges (List), /admin/badges/add (Add), /admin/badges/edit/:id (Edit)")
    local kbCount = (Services['KnowledgeService'] and Services['KnowledgeService'].countKnowledgeEntries and Services['KnowledgeService']:countKnowledgeEntries()) or "N/A"
    print("Current knowledge base size:", kbCount, "entries")
    print("------------------------------------------")
end)