--[[
       Made by _alexmiles_ (yes i talk to myself in my own code lol)
          Cuz i was bored xddd

          Version: 0.3.0-alpha.1a (Split into Modules!)

          TODO:
            - split into modules (maybe) -> HTML Generator, Router? (PARTIALLY DONE)
            - move to python or nodejs or idk lol
            - get rid of html generator (i dont think thats how the things works lol) -> Use templates?
            - figure out how to make favicon working (idk lol) (somehow SOLVED)
            - Add moderation/review for user submissions?
            - Improve error handling and user feedback?
            - Further refactor static file serving?
]]

local http = require('http')
local fs = require('fs')
local path = require('path')
local url = require('url')
local timer = require('timer')
local json = require('json') -- json needed for querystring.parse error check
local querystring = require('querystring') -- Needed for POST body parsing

--[[

    !! No module named [built-in luvit library] found FIX !!

  Apparently, luvit somehow for unknown for me reason loads modules
  without its built-in library. So we have to provide them lol.

  Check JsonService for an example how to make modules work

]]
local libs = {}
libs['http'] = http
libs['fs'] = fs
libs["path"] = path
libs['url'] = url
libs['json'] = json
libs['querystring'] = querystring
libs['timer'] = timer -- Added timer


-- New require - injects the libs table into required modules
local function require2(modulename)
  local mod = require(modulename) -- first require it
  mod['libs'] = libs  -- Provide the libraries

  return mod  -- just return
end

-- --- Load Services ---
local Services = {}

-- Load core services first
Services['JsonService'] = require2('JsonService') 
Services['KnowledgeService'] = require2('KnowledgeService')
Services['ContentService'] = require2('ContentService')
Services['UtilService'] = require2('UtilService')

Services['HtmlService'] = require2('HtmlService')


-- --- Service Initialization ---
-- Initialize services that have dependencies
if not Services['ContentService']:init(Services['KnowledgeService']) then
    print("FATAL ERROR: ContentService failed to initialize.")
end

if not Services['HtmlService']:init(Services['UtilService'], Services['ContentService']) then
     print("FATAL ERROR: HtmlService failed to initialize.")
end


-- --- Configuration ---
local port = process.env.PORT or 8000
local root = process.cwd()


-- --- Helper Functions  ---

-- SanitizePath function 
local function sanitizePath(reqPath)
  local safePath = path.normalize(reqPath)
  if string.find(safePath, '^%.%.[/\\]') or string.find(safePath, '[/\\]%.%.[/\\]') or string.find(safePath, '[/\\]%.%.$') then
    print("Warning: Potential path traversal blocked: " .. reqPath .. " -> " .. safePath); return nil
  end
  if safePath:sub(1,1) == '/' or safePath:sub(1,1) == '\\' then
      safePath = safePath:sub(2)
  end

  local fullPath = path.join(root, safePath)

  -- Final check to ensure the normalized path is actually within the root directory
  -- by comparing the beginning of the full path string.
  -- This handles cases like `/../some/path` after normalization.
  local rootWithSep = root .. path.sep
  if not (fullPath == root or fullPath:sub(1, #rootWithSep) == rootWithSep) then
      print("Warning: Attempted access outside root directory blocked: " .. reqPath .. " -> " .. fullPath); return nil
  end

  return fullPath
end

-- Simple MIME Type Lookup
local function getMimeType(filePath)
  local extension = string.match(filePath, "%.([^.]+)$")
  if not extension then return 'application/octet-stream' end
  extension = string.lower(extension)
  local mimeTypes = {
    txt = 'text/plain', html = 'text/html', htm = 'text/html', css = 'text/css',
    js = 'application/javascript', json = 'application/json', xml = 'application/xml',
    jpg = 'image/jpeg', jpeg = 'image/jpeg', png = 'image/png', gif = 'image/gif',
    svg = 'image/svg+xml', ico = 'image/x-icon',
    -- Add more mime types as needed
  }
  return mimeTypes[extension] or 'application/octet-stream'
end


-- --- Initialization ---
Services['KnowledgeService']:loadKnowledgeBase() -- Load existing data first

print("Setting initial QOTD...")
Services['ContentService']:updateQotd() -- Set the initial QOTD using the service

local Mins = 5 -- Update QOTD
local InMillis = Mins * 60 * 1000
timer.setInterval(InMillis, function() Services['ContentService']:updateQotd() end) -- Schedule QOTD updates
print("QOTD will update every " .. Mins .. " minutes.")

-- --- HTTP Server Logic ---
http.createServer(function (req, res)
  local parsedUrl = url.parse(req.url, true)
  local pathname = parsedUrl.pathname
  local query = parsedUrl.query or {}

  print("Request: " .. req.method .. " " .. pathname)

  -- Helper to send HTML response
  local function sendHtml(pageType, pageData, statusMsg)
      local htmlContent = Services['HtmlService']:generateHtml(pageType, pageData, statusMsg)
      res:writeHead(200, {['Content-Type'] = 'text/html; charset=utf-8'})
      res:finish(htmlContent)
      print("  -> Responded with HTML page (Type: " .. pageType .. ")")
  end

   -- Helper to send 404 HTML response
  local function sendNotFound()
      local htmlContent = Services['HtmlService']:generateHtml('notfound')
      res:writeHead(404, {['Content-Type'] = 'text/html; charset=utf-8'})
      res:finish(htmlContent)
      print("  -> Responded with 404 page")
  end

  -- --- Routing Logic ---

  -- Route 1: HOME page ('/') - GET only
  if pathname == '/' and req.method == 'GET' then
    sendHtml('home')

  -- Route 2: ASK page ('/ask') - GET only
  elseif pathname == '/ask' and req.method == 'GET' then
    local question = query.question or ""
    question = question:match("^%s*(.-)%s*$")
    local answerData
    if question ~= "" then
      answerData = Services['KnowledgeService']:getAnswer(question)
    end
    sendHtml('ask', { question = question, answerData = answerData }) -- Pass data for the page

  -- Route 3: ADD page ('/add') - GET 
  elseif pathname == '/add' and req.method == 'GET' then
    local statusMsg = ""
    if query.status == 'success' then
        statusMsg = "Success! Your question was added to the knowledge base."
    elseif query.status == 'fail' then
        statusMsg = "Error: Could not add the question. " .. (query.reason and Services['UtilService']:urlDecodeComponent(query.reason) or "Maybe it already exists?")
    elseif query.status == 'empty' then
        statusMsg = "Error: Question and Answer fields cannot be empty."
    end
    sendHtml('add', nil, statusMsg) 

  -- Route 4: ADD page ('/add') - POST
  elseif pathname == '/add' and req.method == 'POST' then
      local body = ''
      req:on('data', function(chunk)
          body = body .. chunk
      end)

      req:on('end', function()
          local postData = {}
          local ok, parsed = pcall(querystring.parse, body)
          if not ok then
              print("Error parsing POST body:", parsed) -- 'parsed' contains error message
              res:writeHead(400, {['Content-Type'] = 'text/plain'})
              res:finish("Bad Request: Could not parse form data.")
              return
          end
           if type(parsed) ~= 'table' then
               print("Error parsing POST body: Result is not a table.")
               res:writeHead(400, {['Content-Type'] = 'text/plain'})
               res:finish("Bad Request: Malformed form data.")
               return
           end

          postData = parsed -- Use the parsed table

          local new_q = postData.new_question or ""
          local new_a = postData.new_answer or ""

          if Services['KnowledgeService'].normalizeQuestion(new_q) == "" or new_a:match("^%s*(.-)%s*$") == "" then
              res:writeHead(303, {['Location'] = '/add?status=empty'})
              res:finish()
              print("  -> Add attempt failed (empty fields)")
              return
          end

          local success, msg = Services['KnowledgeService']:addQA(new_q, new_a)

          if success then
            res:writeHead(303, {['Location'] = '/add?status=success'})
            res:finish()
            print("  -> Add successful, redirecting.")
          else
            local reason = Services['UtilService']:urlEncodeComponent(msg or "Unknown reason")
            res:writeHead(303, {['Location'] = '/add?status=fail&reason=' .. reason})
            res:finish()
            print("  -> Add failed, redirecting. Reason:", msg)
        end
      end)

      req:on('error', function(err)
        print("Request stream error on POST /add:", err)
        res:writeHead(500, {['Content-Type'] = 'text/plain'})
        res:finish("Internal Server Error processing request.")
      end)

  -- Route 5: QOTD page ('/qotd') - GET only
  elseif pathname == '/qotd' and req.method == 'GET' then
    sendHtml('qotd') -- HtmlService will get QOTD data from ContentService

  -- Route 6: About page ('/about') - GET only
  elseif pathname == '/about' and req.method == 'GET' then
    sendHtml('about') -- HtmlService will get About data from ContentService

  -- Route 7: Favicon
  elseif pathname == '/favicon.ico' and req.method == 'GET' then
      local relativePath = "images/favicon.ico"
      local filePath = sanitizePath(relativePath) -- Use the local sanitizePath
      if not filePath then
        sendNotFound(); print("  -> Favicon request blocked (Sanitization failed)"); return
      end
      local ok, stat = pcall(fs.statSync, filePath)
      if not ok or not stat or stat.type ~= 'file' then
          res:writeHead(404, {['Content-Type'] = 'text/plain'})
          res:finish("404 Not Found - Favicon missing"); print("  -> Favicon file not found: " .. filePath); return
      end
      fs.readFile(filePath, function (err, data)
          if err then
            print("  -> Server Error reading favicon: " .. err.message)
            res:writeHead(500, {['Content-Type'] = 'text/plain'}); res:finish("500 Internal Server Error")
          else
            res:writeHead(200, {['Content-Type'] = 'image/x-icon'}); res:finish(data)
            print("  -> Responded with favicon.ico")
          end
      end)


  -- Route 8: Static files (CSS, Images)
  elseif (pathname == '/style.css' or string.match(pathname, '^/images/')) and req.method == 'GET' then
      local relativePath = pathname:sub(2)
      local filePath = sanitizePath(relativePath) -- Use the local sanitizePath
      if not filePath then
        sendNotFound(); print("  -> Static file request blocked (Sanitization failed)"); return
      end
      local ok, stat = pcall(fs.statSync, filePath)
      if not ok or not stat or stat.type ~= 'file' then
        sendNotFound(); print("  -> Static file not found or not a file: " .. filePath); return
      end
      fs.readFile(filePath, function (err, data)
        if err then
          print("  -> Server Error reading static file: " .. err.message .. " for: " .. filePath)
          sendNotFound(); -- Use 404 page
        else
          local contentType = getMimeType(filePath) -- Use the local getMimeType
          res:writeHead(200, {['Content-Type'] = contentType}); res:finish(data)
          print("  -> Responded with static file: " .. pathname)
        end
      end)


  -- Route 9: GET 404'ED LMAO
  else
    sendNotFound()
    print("  -> Unhandled path/method: " .. req.method .. " " .. pathname)
  end

end):listen(port, function()
  print("------------------------------------------")
  print("SeaDriveService Started.")
  print("Version: 0.3.0-alpha.1a")
  print("Listening on http://localhost:" .. port)
  print("Root directory: " .. root)
  print("Available pages: / (Home), /ask, /add, /qotd, /about")
  print("Current knowledge base size:", Services['KnowledgeService']:countKnowledgeEntries(), "entries") -- Use service method
  print("------------------------------------------")
end)