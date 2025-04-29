--[[
       Made by _alexmiles_ (yes i talk to myself in my own code lol)
          Cuz i was bored xddd

          Version: 0.2.0-alpha.1c (Fixed POST body parsing)

          TODO:
            - Resolve module loading issue later
            - split into modules (maybe) -> HTML Generator, Router?
            - move to python or nodejs or idk lol
            - get rid of html generator (i dont think thats how the things works lol) -> Use templates?
            - figure out how to make favicon working (idk lol) (somehow SOLVED)
            - Add moderation/review for user submissions?
            - Improve error handling and user feedback?
]]

local http = require('http')
local fs = require('fs')
local path = require('path')
local url = require('url')
local timer = require('timer')
local json = require('json')
local querystring = require('querystring') 

local port = process.env.PORT or 8000
local root = process.cwd()
local KNOWLEDGE_FILE = "knowledge_base.json" -- File to store data

-- --- Knowledge Base 
local knowledgeBase = {} -- Will be loaded from file or start empty

-- --- QOTD Data ---
local qotdData = {
  question = "Loading...",
  answer = "Selecting question..."
}

-- --- Content for Other Pages ---
local aboutData = {
  title = "About SeaDrive",
  text = "SeaDrive is your friendly feline help buddy, built with the power of Luvit and Lua! I'm here to answer your questions based on my knowledge base, which you can contribute to! While I may not know everything (yet!), I'm always eager to help. Meow!"
}

-- --- Helper Functions for Knowledge Base ---

-- Normalize question (lowercase, trim whitespace)
local function normalizeQuestion(q)
  if type(q) ~= 'string' then return "" end
  return q:lower():match("^%s*(.-)%s*$")
end

-- Save the current knowledgeBase to the JSON file (asynchronously)
local function saveKnowledgeBase()
  local success, result_or_err = pcall(json.encode, knowledgeBase, { pretty = true })

  if not success then
      print("Error encoding knowledge base to JSON:", result_or_err) -- result_or_err holds the error msg
      return
  end

  local jsonData = result_or_err

  fs.writeFile(KNOWLEDGE_FILE, jsonData, function(writeErr) -- Pass the correct jsonData string
    if writeErr then
      print("Error writing knowledge base to " .. KNOWLEDGE_FILE .. ":", writeErr.message)
    else
    end
  end)
end

-- Load data from JSON file (synchronously)
local function loadKnowledgeBase()
  print("Attempting to load knowledge base from " .. KNOWLEDGE_FILE .. "...")
  local fileContent, readErr = fs.readFileSync(KNOWLEDGE_FILE)
  if not fileContent then
    if readErr and readErr.code == 'ENOENT' then
      print("Knowledge file not found. Starting with an empty base.")
      knowledgeBase = {}
    else
      print("Error reading knowledge file " .. KNOWLEDGE_FILE .. ":", readErr and readErr.message or "Unknown error")
      print("Starting with an empty knowledge base.")
      knowledgeBase = {}
    end
    return
  end
  local ok, decodedData = pcall(json.decode, fileContent)
  if ok and type(decodedData) == 'table' then
    knowledgeBase = decodedData
    local count = 0; for _ in pairs(knowledgeBase) do count = count + 1 end
    print("Knowledge base loaded successfully. Found", count, "entries.")
  else
    print("Error decoding JSON from " .. KNOWLEDGE_FILE .. ":", decodedData)
    print("Starting with an empty knowledge base due to load error.")
    knowledgeBase = {}
  end
end

-- Add a new Question and Answer directly to the knowledgeBase
local function addQA(question, answer)
  local normQ = normalizeQuestion(question)
  local ans = tostring(answer or ""):match("^%s*(.-)%s*$")
  if normQ == "" or ans == "" then
    return false, "Question and Answer cannot be empty."
  end
  if knowledgeBase[normQ] then
    return false, "This question already exists in the knowledge base."
  end
  knowledgeBase[normQ] = { answer = ans }
  print("Added QA: [" .. normQ .. "]")
  saveKnowledgeBase()
  return true, "Question added successfully!"
end

-- Get the answer for a specific question
local function getAnswer(question)
  local normQ = normalizeQuestion(question)
  return knowledgeBase[normQ]
end

-- Get all question strings
local function getAllQuestions()
  local questions = {}
  for q, _ in pairs(knowledgeBase) do table.insert(questions, q) end
  return questions
end

-- Get the count of entries
local function countKnowledgeEntries()
    local count = 0; for _ in pairs(knowledgeBase) do count = count + 1 end; return count
end

-- --- Other Helper Functions ---

-- Update QOTD using the local knowledgeBase
local function updateQotd()
  local questions = getAllQuestions()
  if #questions == 0 then
    print("Warning: Knowledge base is empty. Cannot update QOTD.")
    qotdData.question = "No questions available"
    qotdData.answer = "Add some questions using the 'Add' page!"
    return
  end
  local randomIndex = math.random(#questions)
  local selectedQuestion = questions[randomIndex]
  local selectedAnswerData = getAnswer(selectedQuestion)
  qotdData.question = selectedQuestion
  qotdData.answer = (selectedAnswerData and selectedAnswerData.answer) or "Internal Error: Could not find answer for selected QOTD."
  print(os.date("%Y-%m-%d %H:%M:%S") .. " - Updated QOTD to: [" .. qotdData.question .. "]")
end

-- LAME JAVASCRIPT
local function urlEncodeComponent(str)
  if not str then return "" end
  str = tostring(str)
  str = string.gsub(str, "([^%w%-%.!~%*'%_'(%)])", function(c)
    return string.format("%%%02X", string.byte(c))
  end)
  str = string.gsub(str, " ", "%%20")
  return str
end

-- LAME JAVASCRIPT2
local function urlDecodeComponent(str)
  if not str then return "" end
  str = tostring(str)
  str = string.gsub(str, "%%(%x%x)", function(h)
    return string.char(tonumber(h, 16))
  end)
  str = string.gsub(str, "+", " ")
  return str
end

-- SanitizePath function
local function sanitizePath(reqPath)
  local safePath = path.normalize(reqPath)
  if string.find(safePath, '^%.%.[/\\]') or string.find(safePath, '[/\\]%.%.[/\\]') or string.find(safePath, '[/\\]%.%.$') or safePath:sub(1,1) == '/' or safePath:sub(1,1) == '\\' then
    print("Warning: Potentially unsafe path blocked: " .. reqPath .. " -> " .. safePath); return nil
  end
  local fullPath = path.join(root, safePath)
  if not string.find(fullPath, root .. path.sep, 1, true) and fullPath ~= root then
     if fullPath:sub(1, #root) ~= root then
       print("Warning: Attempted access outside root directory blocked: " .. reqPath .. " -> " .. fullPath); return nil
     end
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
  }
  return mimeTypes[extension] or 'application/octet-stream'
end

-- Function to generate the HTML for the page dynamically 
local function generateHtml(pageType, currentQuestion, answerData, statusMsg)
  currentQuestion = currentQuestion or ""
  statusMsg = statusMsg or "" -- Message for add page feedback
  local mainContentHtml = ""
  local headerMascotBubble = "Welcome!"

  -- Add status message display logic 
  local statusHtml = ""
  if statusMsg ~= "" then
      local msgClass = "status-message"
      if string.find(statusMsg:lower(), "success") then msgClass = msgClass .. " success"
      elseif string.find(statusMsg:lower(), "error") or string.find(statusMsg:lower(), "fail") then msgClass = msgClass .. " error"
      end
      statusHtml = '<div class="' .. msgClass .. '">' .. statusMsg .. '</div>'
  end

  -- NavLinks Table 
  local navLinks = {
    {href = "/", text = "HOME"},
    {href = "/ask", text = "ASK"},
    {href = "/add", text = "ADD"},
    {href = "/qotd", text = "QOTD!"},
    {href = "/about", text = "ABOUT"}
  }
  local navHtml = "<nav>\n"
  for _, link in ipairs(navLinks) do
    local isActive = false
    if pageType ~= 'notfound' then
        if (pageType == 'home' and link.href == '/') or
           (pageType == 'ask' and link.href == '/ask') or
           (pageType == 'add' and link.href == '/add') or 
           (pageType == 'qotd' and link.href == '/qotd') or
           (pageType == 'about' and link.href == '/about') then
           isActive = true
        end
    end
    navHtml = navHtml .. string.format('    <a href="%s"%s>%s</a>\n',
                                       link.href,
                                       isActive and ' class="active"' or '',
                                       link.text)
  end
  navHtml = navHtml .. "</nav>"

  -- Generate main content based on pageType

  if pageType == 'home' then
    headerMascotBubble = "Welcome to SeaDrive!"
    mainContentHtml = [[
        <div class="content-section home-content">
            <h2>Welcome!</h2>
            <div class="answer-box" style="text-align: center;">
                <p>Hi there! I'm SeaDrive, your feline help buddy.</p>
                <p>Got a question? Head over to the Ask page!</p>
                 <p>Want to teach me something? Go to the Add page!</p>
                <p style="margin-top: 20px;">
                    <a href="/ask" style="padding: 8px 15px; background-color: #8bc37a; color: white; text-decoration: none; border-radius: 4px; margin-right: 10px;">
                        Go to Ask Page
                    </a>
                     <a href="/add" style="padding: 8px 15px; background-color: #7ab8c3; color: white; text-decoration: none; border-radius: 4px;">
                        Go to Add Page
                    </a>
                </p>
            </div>
            <div class="mascot-area main-mascot-area", style="">
                <img src="/images/mascot.png" alt="SeaDrive Mascot" class="mascot-img mascot-main-img">
            </div>
        </div>
    ]]

  elseif pageType == 'ask' then
    headerMascotBubble = "Ask me something!"
    local answerHtml = ""
    local bottomMascotHtml = [[<div class="mascot-area main-mascot-area"><img src="/images/mascot.png" alt="SeaDrive Mascot" class="mascot-img mascot-main-img"></div>]]

    if answerData then -- Answer found
      headerMascotBubble = "Here's what I know:"
      answerHtml = [[<div class="answer-section"><div class="answer-box"><p class="answer-title">Here's information for:<br>]] .. currentQuestion .. [[</p><p>]] .. answerData.answer .. [[</p></div><div class="mascot-area main-mascot-area"><div class="speech-bubble speech-bubble-bottom">Found it!</div><img src="/images/mascot.png" alt="SeaDrive Mascot" class="mascot-img mascot-main-img"></div></div>]]
      bottomMascotHtml = ""
    elseif currentQuestion ~= "" then -- Question asked, but no answer found
       headerMascotBubble = "Hmm, I'm not sure..."
       answerHtml = [[<div class="answer-section"><div class="answer-box not-found-box"><p class="answer-title">Sorry, I couldn't find an answer for:<br>]] .. currentQuestion .. [[</p><p>My knowledge is limited right now. Maybe you can <a href="/add">teach me</a>?</p></div><div class="mascot-area main-mascot-area"><div class="speech-bubble speech-bubble-bottom">Purrhaps try again?</div><img src="/images/mascot.png" alt="SeaDrive Mascot" class="mascot-img mascot-main-img"></div></div>]]
       bottomMascotHtml = ""
    end
    local escapedQuestion = currentQuestion:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'):gsub('"', '&quot;')
    mainContentHtml = [[<div class="ask-section"><h2>Ask SeaDrive:</h2><form method="GET" action="/ask" class="ask-input-group"><input type="text" name="question" placeholder="Type your question here..." value="]] .. escapedQuestion .. [["><button type="submit">ASK</button></form></div>]] .. answerHtml .. bottomMascotHtml

  elseif pageType == 'add' then
    headerMascotBubble = "Teach me something new!"
    mainContentHtml = [[
        <div class="content-section add-content">
            <h2>Add a New Question & Answer</h2>
            ]] .. statusHtml .. [[
            <form method="POST" action="/add" class="add-form">
                <div class="form-group">
                    <label for="new_question">Question:</label>
                    <input type="text" id="new_question" name="new_question" placeholder="Enter the question" required>
                </div>
                <div class="form-group">
                    <label for="new_answer">Answer:</label>
                    <textarea id="new_answer" name="new_answer" rows="4" placeholder="Enter the answer" required></textarea>
                </div>
                <button type="submit">Add to Knowledge Base</button>
            </form>

            <div class="bubble-mascot-wrapper" style="width: fit-content; margin-left: auto; margin-right: auto; margin-top: 20px; text-align: center;">

                <div class="speech-bubble speech-bubble-bottom" style="position: static !important; left: auto !important; right: auto !important; transform: none !important; margin-bottom: 5px; display: block;">
                    I'm ready to learn!
                </div>

                 <div class="mascot-area main-mascot-area">
                     <img src="/images/mascot.png" alt="SeaDrive Mascot - Eager" class="mascot-img mascot-main-img" style="display: inline-block;">
                </div>

            </div> 

        </div>
    ]]

  elseif pageType == 'qotd' then
    headerMascotBubble = "Question of the Day!"
    mainContentHtml = [[ <div class="content-section qotd-content"><h2>Question of the Day!</h2><div class="answer-box"><p class="answer-title"><strong>Q:</strong> ]] .. qotdData.question .. [[</p><p><strong>A:</strong> ]] .. qotdData.answer .. [[</p></div><div class="mascot-area main-mascot-area"><div class="speech-bubble speech-bubble-bottom">Today's tidbit!</div><img src="/images/mascot.png" alt="SeaDrive Mascot" class="mascot-img mascot-main-img"></div></div> ]]

  elseif pageType == 'about' then
    headerMascotBubble = "About Me!"
    mainContentHtml = [[ <div class="content-section about-content"><h2>]] .. aboutData.title .. [[</h2><div class="answer-box"><p>]] .. aboutData.text .. [[</p></div><div class="mascot-area main-mascot-area"><div class="speech-bubble speech-bubble-bottom">That's me!</div><img src="/images/mascot.png" alt="SeaDrive Mascot" class="mascot-img mascot-main-img"></div></div> ]]

  elseif pageType == 'notfound' then
    headerMascotBubble = "Uh oh... Lost?"
    mainContentHtml = [[
         <div class="content-section notfound-content">
            <h2 class="notfound-title">404 - Page Not Found</h2>
            <div class="answer-box notfound-box">
                <p>Mrow! Looks like the page you were looking for doesn't exist or has moved.</p>
                <p>Maybe try asking me something on the main page?</p>
                <p class="notfound-link-wrapper"><a href="/ask" class="notfound-link">Go to Ask Page</a></p>
            </div>
            <div class="mascot-area main-mascot-area">
                <div class="speech-bubble speech-bubble-bottom">Where did it go?</div>
                <img src="/images/mascot.png" alt="SeaDrive Mascot - Confused?" class="mascot-img mascot-main-img">
            </div>
        </div>
    ]]
  end

  -- Combine all parts into the full HTML
  local fullHtml = [[
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SeaDrive</title>
    <link rel="stylesheet" href="/style.css">
    <style>
      .status-message { padding: 10px; margin-bottom: 15px; border-radius: 4px; border: 1px solid transparent; }
      .status-message.success { background-color: #dff0d8; border-color: #d6e9c6; color: #3c763d; }
      .status-message.error { background-color: #f2dede; border-color: #ebccd1; color: #a94442; }
      .add-form .form-group { margin-bottom: 15px; }
      .add-form label { display: block; margin-bottom: 5px; font-weight: bold; }
      .add-form input[type="text"], .add-form textarea { width: 95%; padding: 8px; border: 1px solid #ccc; border-radius: 4px; }
      .add-form textarea { resize: vertical; }
      .add-form button { padding: 10px 15px; background-color: #5cb85c; color: white; border: none; border-radius: 4px; cursor: pointer; }
      .add-form button:hover { background-color: #4cae4c; }
    </style>
</head>
<body>
    <header>
        <div class="header-content">
            <div class="logo">
                <h1>SeaDrive</h1>
                <p>The feline help buddy</p>
            </div>
            <div class="mascot-area header-mascot-area">
                 <div class="speech-bubble speech-bubble-top">
                    ]] .. headerMascotBubble .. [[
                </div>
               <img src="/images/mascot.png" alt="SeaDrive Mascot" class="mascot-img mascot-header-img">
            </div>
        </div>
        <div class="sub-nav-text">
            <span>Your personal assistant</span>
            <span>The know it all cat!</span>
            <span>Ask them ANYTHING!</span>
        </div>
    </header>
    ]] .. navHtml .. [[
    <main>
        ]] .. mainContentHtml .. [[
    </main>
</body>
</html>
]]
  return fullHtml
end

-- A LOT OF HTML CODE INSIDE OF SERVER SCRIPT HUH ALEX WHAT ARE YOU DOING???

-- --- Initialization ---
loadKnowledgeBase() -- Load existing data first

print("Setting initial QOTD...")
updateQotd() 

local Mins = 5 -- Update QOTD
local InMillis = Mins * 60 * 1000
timer.setInterval(InMillis, updateQotd)
print("QOTD will update every " .. Mins .. " minutes.")

-- --- HTTP Server Logic ---
http.createServer(function (req, res)
  local parsedUrl = url.parse(req.url, true)
  local pathname = parsedUrl.pathname
  local query = parsedUrl.query or {}

  print("Request: " .. req.method .. " " .. pathname)

  -- --- Routing Logic ---

  -- Route 1: HOME page ('/') - GET only
  if pathname == '/' and req.method == 'GET' then
    local htmlContent = generateHtml('home')
    res:writeHead(200, {['Content-Type'] = 'text/html; charset=utf-8'})
    res:finish(htmlContent)
    print("  -> Responded with HTML page (Type: home)")

  -- Route 2: ASK page ('/ask') - GET only
  elseif pathname == '/ask' and req.method == 'GET' then
    local question = query.question or ""
    question = question:match("^%s*(.-)%s*$")
    local answerData
    if question ~= "" then
      answerData = getAnswer(question) 
    end
    local htmlContent = generateHtml('ask', question, answerData)
    res:writeHead(200, {['Content-Type'] = 'text/html; charset=utf-8'})
    res:finish(htmlContent)
    print("  -> Responded with HTML page (Type: ask)")

  -- Route 3: ADD page ('/add') - GET (Show form)
  elseif pathname == '/add' and req.method == 'GET' then
    local statusMsg = ""
    if query.status == 'success' then
        statusMsg = "Success! Your question was added to the knowledge base."
    elseif query.status == 'fail' then
        statusMsg = "Error: Could not add the question. " .. (query.reason and urlDecodeComponent(query.reason) or "Maybe it already exists?")
    elseif query.status == 'empty' then
        statusMsg = "Error: Question and Answer fields cannot be empty."
    end
    local htmlContent = generateHtml('add', nil, nil, statusMsg)
    res:writeHead(200, {['Content-Type'] = 'text/html; charset=utf-8'})
    res:finish(htmlContent)
    print("  -> Responded with HTML page (Type: add form)")

  -- Route 4: ADD page ('/add') - POST
  elseif pathname == '/add' and req.method == 'POST' then
      local body = ''
      req:on('data', function(chunk)
          body = body .. chunk
          
      end)

      req:on('end', function()
          local postData = {}
          local ok, parsed = pcall(querystring.parse, body) 
          if ok and type(parsed) == 'table' then
              postData = parsed
          else
              print("Error parsing POST body:", parsed) -- 'parsed' should contain the error message here
              res:writeHead(400, {['Content-Type'] = 'text/plain'})
              res:finish("Bad Request: Could not parse form data.")
              return
          end

          local new_q = postData.new_question or ""
          local new_a = postData.new_answer or ""

          if normalizeQuestion(new_q) == "" or new_a:match("^%s*(.-)%s*$") == "" then
              res:writeHead(303, {['Location'] = '/add?status=empty'})
              res:finish()
              print("  -> Add attempt failed (empty fields)")
              return
          end

          
          local success, msg = addQA(new_q, new_a)

          if success then
            res:writeHead(303, {['Location'] = '/add?status=success'})
            res:finish()
            print("  -> Add successful, redirecting.")
          else
            
            print("DEBUG: Type of querystring variable:", type(querystring))
            if type(querystring) == 'table' then
                print("DEBUG: Type of querystring.escape function:", type(querystring.escape))
            end

            local reason = urlEncodeComponent(msg or "Unknown reason")
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
    local htmlContent = generateHtml('qotd')
    res:writeHead(200, {['Content-Type'] = 'text/html; charset=utf-8'})
    res:finish(htmlContent)
    print("  -> Responded with HTML page (Type: qotd)")

  -- Route 6: About page ('/about') - GET only
  elseif pathname == '/about' and req.method == 'GET' then
    local htmlContent = generateHtml('about')
    res:writeHead(200, {['Content-Type'] = 'text/html; charset=utf-8'})
    res:finish(htmlContent)
    print("  -> Responded with HTML page (Type: about)")

  -- Route 7: Favicon 
  elseif pathname == '/favicon.ico' and req.method == 'GET' then
      local relativePath = "images/favicon.ico"
      local filePath = sanitizePath(relativePath)
      if not filePath then
        local htmlContent = generateHtml('notfound')
        res:writeHead(404, {['Content-Type'] = 'text/html; charset=utf-8'})
        res:finish(htmlContent); print("  -> Favicon request blocked (Sanitization failed)"); return
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
     -- 
      local relativePath = pathname:sub(2)
      local filePath = sanitizePath(relativePath)
      if not filePath then
        local htmlContent = generateHtml('notfound')
        res:writeHead(404, {['Content-Type'] = 'text/html; charset=utf-8'})
        res:finish(htmlContent); print("  -> Static file request blocked (Sanitization failed)"); return
      end
      local ok, stat = pcall(fs.statSync, filePath)
      if not ok or not stat or stat.type ~= 'file' then
        local htmlContent = generateHtml('notfound')
        res:writeHead(404, {['Content-Type'] = 'text/html; charset=utf-8'})
        res:finish(htmlContent); print("  -> Static file not found or not a file: " .. filePath); return
      end
      fs.readFile(filePath, function (err, data)
        if err then
          print("  -> Server Error reading static file: " .. err.message .. " for: " .. filePath)
          local htmlContent = generateHtml('notfound')
          res:writeHead(500, {['Content-Type'] = 'text/html; charset=utf-8'}); res:finish(htmlContent)
        else
          local contentType = getMimeType(filePath)
          res:writeHead(200, {['Content-Type'] = contentType}); res:finish(data)
          print("  -> Responded with static file: " .. pathname)
        end
      end)


  -- Route 9: GET 404'ED LMAO
  else
    local htmlContent = generateHtml('notfound')
    res:writeHead(404, {['Content-Type'] = 'text/html; charset=utf-8'})
    res:finish(htmlContent)
    print("  -> Responded with 404 page (Unhandled path/method: " .. req.method .. " " .. pathname .. ")")
  end

end):listen(port, function()
  print("------------------------------------------")
  print("SeaDrive Server")
  print("Version: 0.2.0-alpha.1c") 
  print("Knowledge Source: " .. KNOWLEDGE_FILE)
  print("Listening on http://localhost:" .. port)
  print("Root directory: " .. root)
  print("Available pages: / (Home), /ask, /add, /qotd, /about")
  print("Current knowledge base size:", countKnowledgeEntries(), "entries")
  print("------------------------------------------")
end)