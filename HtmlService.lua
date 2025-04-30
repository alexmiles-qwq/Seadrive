local HtmlService = {}
HtmlService.libs = {}

local utilService -- Reference to the UtilService
local contentService -- Reference to the ContentService

-- Initialize the service with dependencies
function HtmlService:init(utlService, contService)
    if not utlService then
        print("HtmlService: UtilService dependency missing!")
        return false
    end
     if not contService then
        print("HtmlService: ContentService dependency missing!")
        return false
    end
    utilService = utlService
    contentService = contService
    print("HtmlService initialized with UtilService and ContentService.")
    return true
end


-- Function to generate the HTML for the page dynamically
function HtmlService:generateHtml(pageType, pageData, statusMsg)
  if not utilService or not contentService then
      return "<html><body><h1>HTML Service Not Initialized!</h1><p>Dependencies missing.</p></body></html>" -- Fallback error page
  end

  local currentQuestion = pageData and pageData.question or ""
  local answerData = pageData and pageData.answerData or nil
  -- QOTD and About data are accessed via the contentService reference
  local qotdData = contentService.qotdData
  local aboutData = contentService.aboutData

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

  -- NavLinks Table (Can remain here or be moved)
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
        -- Check if the current path matches the link's href for active class
        local currentPagePath = "/" -- Default for home
        if pageType == 'ask' then currentPagePath = '/ask'
        elseif pageType == 'add' then currentPagePath = '/add'
        elseif pageType == 'qotd' then currentPagePath = '/qotd'
        elseif pageType == 'about' then currentPagePath = '/about'
        end

        if currentPagePath == link.href then
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
      local escapedAnswer = tostring(answerData.answer or ""):gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'):gsub('"', '&quot;')
      answerHtml = [[<div class="answer-section"><div class="answer-box"><p class="answer-title">Here's information for:<br>]] .. currentQuestion .. [[</p><p>]] .. escapedAnswer .. [[</p></div><div class="mascot-area main-mascot-area"><div class="speech-bubble speech-bubble-bottom">Found it!</div><img src="/images/mascot.png" alt="SeaDrive Mascot" class="mascot-img mascot-main-img"></div></div>]]
      bottomMascotHtml = ""
    elseif currentQuestion ~= "" then -- Question asked, but no answer found
       headerMascotBubble = "Hmm, I'm not sure..."
       answerHtml = [[<div class="answer-section"><div class="answer-box not-found-box"><p class="answer-title">Sorry, I couldn't find an answer for:<br>]] .. currentQuestion .. [[</p><p>My knowledge is limited right now. Maybe you can <a href="/add">teach me</a>?</p></div><div class="mascot-area main-mascot-area"><div class="speech-bubble speech-bubble-bottom">Purrhaps try again?</div><img src="/images/mascot.png" alt="SeaDrive Mascot" class="mascot-img mascot-main-img"></div></div>]]
       bottomMascotHtml = ""
    end
    -- Use utilService for encoding the input value
    local escapedQuestion = utilService:urlEncodeComponent(currentQuestion):gsub('%%20', ' ') -- encode, but keep spaces as spaces for the value attr
    escapedQuestion = escapedQuestion:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'):gsub('"', '&quot;') -- Also escape HTML entities

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
    -- Access QOTD data via contentService
    local escapedQotdQuestion = tostring(qotdData.question or "Loading..."):gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'):gsub('"', '&quot;')
    local escapedQotdAnswer = tostring(qotdData.answer or "Loading..."):gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'):gsub('"', '&quot;')
    mainContentHtml = [[ <div class="content-section qotd-content"><h2>Question of the Day!</h2><div class="answer-box"><p class="answer-title"><strong>Q:</strong> ]] .. escapedQotdQuestion .. [[</p><p><strong>A:</strong> ]] .. escapedQotdAnswer .. [[</p></div><div class="mascot-area main-mascot-area"><div class="speech-bubble speech-bubble-bottom">Today's tidbit!</div><img src="/images/mascot.png" alt="SeaDrive Mascot" class="mascot-img mascot-main-img"></div></div> ]]

  elseif pageType == 'about' then
    headerMascotBubble = "About Me!"
    -- Access About data via contentService
    local escapedAboutTitle = tostring(aboutData.title or "About"):gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'):gsub('"', '&quot;')
    local escapedAboutText = tostring(aboutData.text or "No info available"):gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'):gsub('"', '&quot;')
    mainContentHtml = [[ <div class="content-section about-content"><h2>]] .. escapedAboutTitle .. [[</h2><div class="answer-box"><p>]] .. escapedAboutText .. [[</p></div><div class="mascot-area main-mascot-area"><div class="speech-bubble speech-bubble-bottom">That's me!</div><img src="/images/mascot.png" alt="SeaDrive Mascot" class="mascot-img mascot-main-img"></div></div> ]]

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
  -- Note: The inline styles specific to add page status messages and form groups
  -- could ideally go into style.css, but are kept here for simplicity as in original.
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


return HtmlService