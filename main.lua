--[[
       Made by _alexmiles_ (yes i talk to myself in my own code lol)
          Cuz i was bored xddd

          TODO: 
            DONT FUCKING PUT ENTIRE CODE IN ONE SCRIPT DIDIOT!!!! DO MODULES YOU DUMB!! >:[]
            - split into modules (maybe)
            - move to python or nodejs or idk lol
            - get rid of html generator (i dont think thats how the things works lol)
            - figure out how to make favicon working (idk lol)
            - Let users add their own questions and anwsers
]]

local http = require('http')
local fs = require('fs')
local path = require('path')
local url = require('url')
local timer = require('timer')



local port = process.env.PORT or 8000
local root = process.cwd()

-- --- Basic Knowledge Base ---
local knowledgeBase = {                   -- Add own lol                      
  ["how deep is the average ocean?"] = {
    answer = "The average depth of the ocean is about <strong>3,682 meters (12,080 feet)</strong>. The deepest part of the ocean is called the Challenger Deep and is located beneath the western Pacific Ocean in the southern end of the Mariana Trench, which runs several hundred kilometers southwest of the U.S. territorial island of Guam."
  },
  ["what is luvit?"] = {
    answer = "Luvit is an asynchronous I/O library for Lua, inspired by Node.js. It combines the speed of LuaJIT with powerful libraries like libuv for event-driven, non-blocking applications like web servers!"
  },
  ["who are you?"] = {
    answer = "I'm SeaDrive, the feline help buddy! Ready to assist with your questions. Meow!"
  },
  ["what time is it?"] = {
    answer = "I'm not connected to a real-time clock, but it's definitely time to ask more questions!"
  }
}

-- --- Content for Other Pages ---
local qotdData = {
  question = "What is Luvit?",
  answer = knowledgeBase["what is luvit?"].answer
}

local aboutData = {
  title = "About SeaDrive",
  text = "SeaDrive is your friendly feline help buddy, built with the power of Luvit and Lua! I'm here to answer your questions based on my knowledge base. While I may not know everything (yet!), I'm always eager to help. Meow!"
}


-- --- Helper Functions ---


-- Quickly add new questions and anwsers (кто блять на свете будет использовать это в основном скрипте ты че генний ебать?  ?)
local function AddQA(Q, A)
  local Question = tostring(Q)
  local Anwser = tostring(A)
  
  local existing = knowledgeBase[Q]
  if existing then return end

  knowledgeBase[Q] = {answer = A}
end

-- Update to random question
local function updateQotd()
  local questions = {}
  for q, _ in pairs(knowledgeBase) do
    table.insert(questions, q)
  end

  -- Check if there are any questions to choose from
  if #questions == 0 then
    print("Warning: Knowledge base is empty or has no suitable questions. Cannot update QOTD.")
    qotdData.question = "No questions available"
    qotdData.answer = "Looks like the knowledge base needs more questions!"
    return 
  end

  -- Random
  local randomIndex = math.random(#questions)
  local selectedQuestion = questions[randomIndex]

  -- Get Answer
  local selectedAnswerData = knowledgeBase[selectedQuestion]

  -- Update
  qotdData.question = selectedQuestion
  qotdData.answer = (selectedAnswerData and selectedAnswerData.answer) or "Hmm, I selected a question but couldn't find its answer details."

  -- Log
  print(os.date("%Y-%m-%d %H:%M:%S") .. " - Updated QOTD to: [" .. qotdData.question .. "]")
end

-- SanitizePath function
local function sanitizePath(reqPath)
  local safePath = path.normalize(reqPath)
  if string.find(safePath, '^%.%.[/\\]') or string.find(safePath, '[/\\]%.%.[/\\]') or string.find(safePath, '[/\\]%.%.$') or safePath:sub(1,1) == '/' or safePath:sub(1,1) == '\\' then
    print("Warning: Potentially unsafe path blocked: " .. reqPath .. " -> " .. safePath)
    return nil
  end
  local fullPath = path.join(root, safePath)
  if not string.find(fullPath, root .. path.sep, 1, true) and fullPath ~= root then
     if fullPath:sub(1, #root) ~= root then
       print("Warning: Attempted access outside root directory blocked: " .. reqPath .. " -> " .. fullPath)
       return nil
     end
  end
  return fullPath
end

-- Simple MIME Type Lookup Ahh Function
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
-- Accepts pageType ('home', 'ask', 'qotd', 'about', 'notfound')
local function generateHtml(pageType, currentQuestion, answerData)
  currentQuestion = currentQuestion or ""
  local mainContentHtml = ""
  local headerMascotBubble = "Welcome!" -- Default bubble text for home

  -- NavLinks Table
  local navLinks = {
    {href = "/", text = "HOME"},
    {href = "/ask", text = "ASK"}, 
    {href = "/qotd", text = "QOTD!"},
    {href = "/about", text = "ABOUT"}
  }
  local navHtml = "<nav>\n"
  for _, link in ipairs(navLinks) do
    local isActive = false
    -- isActive Logic
    if pageType ~= 'notfound' then
        if (pageType == 'home' and link.href == '/') or
           (pageType == 'ask' and link.href == '/ask') or
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

  -- Logic for HOME page
  if pageType == 'home' then
    headerMascotBubble = "Welcome to SeaDrive!"
    mainContentHtml = [[
        <div class="content-section home-content">
            <h2>Welcome!</h2>
            <div class="answer-box" style="text-align: center;">
                <p>Hi there! I'm SeaDrive, your feline help buddy.</p>
                <p>Got a question? Head over to the Ask page!</p>
                <p style="margin-top: 20px;">
                    <a href="/ask" style="padding: 8px 15px; background-color: #8bc37a; color: white; text-decoration: none; border-radius: 4px;">
                        Go to Ask Page
                    </a>
                </p>
            </div>
            <div class="mascot-area main-mascot-area">
                <img src="/images/mascot.png" alt="SeaDrive Mascot" class="mascot-img mascot-main-img">
            </div>
        </div>
    ]]

  elseif pageType == 'ask' then
    -- Logic for ASK page (Shows form, and optionally answer)
    headerMascotBubble = "Ask me something!" -- Default for ask page
    local answerHtml = ""
    -- Default bottom mascot (shown only if no answer box is displayed)
    local bottomMascotHtml = [[<div class="mascot-area main-mascot-area"><img src="/images/mascot.png" alt="SeaDrive Mascot" class="mascot-img mascot-main-img"></div>]]

    if answerData then -- Answer found
      headerMascotBubble = "Here's information for:"
      answerHtml = [[<div class="answer-section"><div class="answer-box"><p class="answer-title">Here's information for:<br>]] .. currentQuestion .. [[</p><p>]] .. answerData.answer .. [[</p></div><div class="mascot-area main-mascot-area"><div class="speech-bubble speech-bubble-bottom"></div><img src="/images/mascot.png" alt="SeaDrive Mascot" class="mascot-img mascot-main-img"></div></div>]]
      bottomMascotHtml = "" -- Hide default mascot if answer is shown
    elseif currentQuestion ~= "" then -- Question asked, but no answer found
       headerMascotBubble = "Hmm, I'm not sure..."
       answerHtml = [[<div class="answer-section"><div class="answer-box not-found-box"><p class="answer-title">Sorry, I couldn't find an answer for:<br>]] .. currentQuestion .. [[</p><p>My knowledge is limited right now. Try asking something else!</p></div><div class="mascot-area main-mascot-area"><img src="/images/mascot.png" alt="SeaDrive Mascot" class="mascot-img mascot-main-img"></div></div>]]
       bottomMascotHtml = "" -- Hide default mascot if 'not found' answer is shown
    end
    -- The form is always part of the 'ask' page content
    local escapedQuestion = currentQuestion:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'):gsub('"', '&quot;')
    mainContentHtml = [[<div class="ask-section"><h2>Ask SeaDrive:</h2><form method="GET" action="/ask" class="ask-input-group"><input type="text" name="question" placeholder="Type your question here..." value="]] .. escapedQuestion .. [["><button type="submit">ASK</button></form></div>]] .. answerHtml .. bottomMascotHtml

  elseif pageType == 'qotd' then
    headerMascotBubble = "Question of the Day!"
    mainContentHtml = [[ <div class="content-section qotd-content"><h2>Question of the Day!</h2><div class="answer-box"><p class="answer-title"><strong>Q:</strong> ]] .. qotdData.question .. [[</p><p><strong>A:</strong> ]] .. qotdData.answer .. [[</p></div><div class="mascot-area main-mascot-area"><img src="/images/mascot.png" alt="SeaDrive Mascot" class="mascot-img mascot-main-img"></div></div> ]]

  elseif pageType == 'about' then
    headerMascotBubble = "About Me!"
    mainContentHtml = [[ <div class="content-section about-content"><h2>]] .. aboutData.title .. [[</h2><div class="answer-box"><p>]] .. aboutData.text .. [[</p></div><div class="mascot-area main-mascot-area"><img src="/images/mascot.png" alt="SeaDrive Mascot" class="mascot-img mascot-main-img"></div></div> ]]

  elseif pageType == 'notfound' then
    headerMascotBubble = "Uh oh... Lost?"
    mainContentHtml = [[ <div class="content-section notfound-content"><h2 class="notfound-title">404 - Page Not Found</h2><div class="answer-box notfound-box"><p>Mrow! Looks like the page you were looking for doesn't exist or has moved.</p><p>Maybe try asking me something on the main page?</p><p class="notfound-link-wrapper"><a href="/ask" class="notfound-link">Go to Ask Page</a></p></div><div class="mascot-area main-mascot-area"><img src="/images/mascot.png" alt="SeaDrive Mascot - Confused?" class="mascot-img mascot-main-img"></div></div> ]]
  end

  -- Combine all parts into the full HTM LAME
  local fullHtml = [[
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SeaDrive</title>
    <link rel="stylesheet" href="/style.css">
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

-- Add custom q/a

AddQA("test", "test2")

print("Setting initial QOTD...")
updateQotd()

local Mins = 1
local InMillis = Mins * 60 * 1000 -- X minutes * 60 seconds/min * 1000 ms/sec
timer.setInterval(InMillis, updateQotd)

-- --- HTTP Server Logic ---
http.createServer(function (req, res)
  local parsedUrl = url.parse(req.url, true)
  local pathname = parsedUrl.pathname
  local query = parsedUrl.query or {}

  print("Request: " .. req.method .. " " .. pathname)

  --  ROUTIN(E) G LOGIC 

  -- Route 1: HOME page ('/')
  if pathname == '/' then
    local htmlContent = generateHtml('home', nil, nil) -- Use 'home' type
    res:writeHead(200, {['Content-Type'] = 'text/html; charset=utf-8'})
    res:finish(htmlContent)
    print("  -> Responded with HTML page (Type: home)")

  -- Route 2: ASK page ('/ask') - Handles form display AND results
  elseif pathname == '/ask' then
    local question = query.question or "" -- Check for question parameter
    question = question:match("^%s*(.-)%s*$") -- Trim whitespace
    local answerData
    if question ~= "" then
      local lowerQuestion = string.lower(question)
      answerData = knowledgeBase[lowerQuestion] -- Look up only if question exists
    end
    -- Always generate 'ask' page type, passing question/answer if they exist
    local htmlContent = generateHtml('ask', question, answerData)
    res:writeHead(200, {['Content-Type'] = 'text/html; charset=utf-8'})
    res:finish(htmlContent)
    print("  -> Responded with HTML page (Type: ask)")

  -- Route 3: QOTD page
  elseif pathname == '/qotd' then
    local htmlContent = generateHtml('qotd', nil, nil)
    res:writeHead(200, {['Content-Type'] = 'text/html; charset=utf-8'})
    res:finish(htmlContent)
    print("  -> Responded with HTML page (Type: qotd)")

  -- Route 4: About page
  elseif pathname == '/about' then
    local htmlContent = generateHtml('about', nil, nil)
    res:writeHead(200, {['Content-Type'] = 'text/html; charset=utf-8'})
    res:finish(htmlContent)
    print("  -> Responded with HTML page (Type: about)")

  -- USELESS Route 5: useless favicon (alex beg you delete it bru)
  elseif pathname == '/favicon.ico' then
      local relativePath = "images/favicon.ico" -- Relative path within project
      local filePath = sanitizePath(relativePath)
      if not filePath then
        -- Sanitization failed, treat as not found
        local htmlContent = generateHtml('notfound', nil, nil)
        res:writeHead(404, {['Content-Type'] = 'text/html; charset=utf-8'})
        res:finish(htmlContent)
        print("  -> Favicon request blocked (Sanitization failed for: " .. relativePath .. ")")
        return
      end

      -- Check if file exists first (more robust than just trying readFile)
      local ok, stat = pcall(fs.statSync, filePath)
      if not ok or not stat or stat.type ~= 'file' then
          res:writeHead(404, {['Content-Type'] = 'text/plain'})
          res:finish("404 Not Found - Favicon missing")
          print("  -> Favicon file not found at: " .. filePath)
          return
      end

      -- File exists, now read and serve it
      fs.readFile(filePath, function (err, data)
          if err then
            print("  -> Server Error reading favicon: " .. err.message .. " for: " .. filePath)
            res:writeHead(500, {['Content-Type'] = 'text/plain'})
            res:finish("500 Internal Server Error")
          else
            local contentType = getMimeType(filePath) -- Should be 'image/x-icon'
            res:writeHead(200, {['Content-Type'] = contentType})
            res:finish(data)
            print("  -> Responded with favicon.ico")
          end
      end)

  -- Route 6: Static files (CSS, Images) - Now excludes favicon
  elseif pathname == '/style.css' or string.match(pathname, '^/images/') then
      local relativePath = pathname:sub(2)
      local filePath = sanitizePath(relativePath)
      if not filePath then
        local htmlContent = generateHtml('notfound', nil, nil)
        res:writeHead(404, {['Content-Type'] = 'text/html; charset=utf-8'})
        res:finish(htmlContent)
        print("  -> Responded with Custom 404 page (Sanitization failed for: " .. relativePath .. ")")
        return
      end
      local ok, stat = pcall(fs.statSync, filePath)
      if not ok or not stat or stat.type ~= 'file' then
        local htmlContent = generateHtml('notfound', nil, nil)
        res:writeHead(404, {['Content-Type'] = 'text/html; charset=utf-8'})
        res:finish(htmlContent)
        print("  -> Responded with Custom 404 page (Static file check failed for: " .. filePath .. ")")
        return
      end
      fs.readFile(filePath, function (err, data)
        if err then
          print("  -> Server Error reading file: " .. err.message .. " for: " .. filePath .. ")")
          local htmlContent = generateHtml('notfound', nil, nil)
          res:writeHead(500, {['Content-Type'] = 'text/html; charset=utf-8'})
          res:finish(htmlContent)
        else
          local contentType = getMimeType(filePath)
          res:writeHead(200, {['Content-Type'] = contentType})
          res:finish(data)
          print("  -> Responded with static file: " .. pathname .. " (Content-Type: " .. contentType .. ")")
        end
      end)

  -- Route 7: Handle all other unhandled paths as Custom 404
  else
    local htmlContent = generateHtml('notfound', nil, nil)
    res:writeHead(404, {['Content-Type'] = 'text/html; charset=utf-8'})
    res:finish(htmlContent)
    print("  -> Responded with Custom 404 page (Unhandled path: " .. pathname .. ")")
  end

end):listen(port, function()                                                                        
  print("Here is information for: Seadrive Search")
  print("SeaDrive server listening on http://localhost:" .. port)
  print("Root directory: " .. root)
  print("Available pages: / (Home), /ask, /qotd, /about") -- Updated available pages
  print("Known questions for Ask page:")
  for q, _ in pairs(knowledgeBase) do
    print("- " .. q)
  end
   print("------------------------------------------")

   
end)

