
local HtmlService = {}
HtmlService.libs = {} -- libs table will be injected by require2

local utilService -- Reference to the UtilService
local contentService -- Reference to the ContentService

local DEFAULT_PFP_URL = "/images/default_pfp.png" -- Define path for default PFP


-- Initialize the service with dependencies
function HtmlService:init(utlService, contService)
    if not utlService or type(utlService) ~= 'table' or type(utlService.urlEncodeComponent) ~= 'function' or type(utlService.urlDecodeComponent) ~= 'function' then
        print("HtmlService: UtilService dependency missing or invalid!")
        return false
    end
     if not contService then
        print("HtmlService: ContentService dependency missing!")
        -- Allow init to succeed but warn, as some pages might not need ContentService
        print("HtmlService: Warning - ContentService dependency missing. QOTD/About may not work.")
        -- return false -- Don't exit if content is missing
    end
    utilService = utlService
    contentService = contService
    print("HtmlService initialized.")
    return true
end

-- Helper to escape HTML
local function escapeHtml(str)
    if type(str) ~= 'string' then return "" end
    return str:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'):gsub('"', '&quot;'):gsub("'", "&#39;")
end


-- Function to generate the HTML for the page dynamically
-- Pass pageData (e.g., { question, answerData }), statusMsg, and user object (from middleware)
function HtmlService:generateHtml(pageType, pageData, statusMsg, user) -- Added 'user' parameter
    -- Check if necessary services are available
    if not utilService then
        return "<html><body><h1>HTML Service Not Fully Initialized!</h1><p>UtilService dependency missing.</p></body></html>" -- Minimal fallback
    end
    pageData = pageData or {} -- Ensure pageData is always a table
    -- Access data from service references, check if services exist
    local currentQuestion = pageData.question or ""
    local answerData = pageData.answerData or nil
    local qotdData = contentService and contentService.qotdData or { question = "Loading...", answer = "Data unavailable.", author = "" }
    local aboutData = contentService and contentService.aboutData or { title = "About (Unavailable)", text = "Content service not loaded." }

    statusMsg = statusMsg or ""
    local mainContentHtml = ""
    local headerMascotBubble = "Welcome!"

    -- Add status message display logic
    local statusHtml = ""
    if statusMsg ~= "" then
        local msgClass = "status-message"
        -- Determine message class based on content
        if string.find(statusMsg:lower(), "success") then msgClass = msgClass .. " success"
        elseif string.find(statusMsg:lower(), "error") or string.find(statusMsg:lower(), "fail") or string.find(statusMsg:lower(), "invalid") or string.find(statusMsg:lower(), "unavailable") or string.find(statusMsg:lower(), "forbidden") then msgClass = msgClass .. " error"
        elseif string.find(statusMsg:lower(), "info") or string.find(statusMsg:lower(), "logged out") or string.find(statusMsg:lower(), "log in") or string.find(statusMsg:lower(), "register") then msgClass = msgClass .. " info"
        else msgClass = msgClass .. " info" -- Default to info if unsure
        end
        statusHtml = '<div class="' .. msgClass .. '">' .. escapeHtml(statusMsg) .. '</div>'
    end

    -- NavLinks Table (Updated based on login status)
    local navLinks = {
      {href = "/", text = "HOME"},
      {href = "/ask", text = "ASK"},
      {href = "/qotd", text = "QOTD!"},
      {href = "/about", text = "ABOUT"},
    }

    -- Check if user is admin for nav link visibility
    local isAdmin = false
    if user and user.badges and type(user.badges) == 'table' then
        for _, badgeId in ipairs(user.badges) do
            if badgeId == 'admin' or badgeId == "owner" then
                isAdmin = true
                break
            end
        end
    end

    -- Add/Remove links based on user status
    if user then
        table.insert(navLinks, {href = "/add", text = "ADD"}) -- Only logged in users can add via form
        if user.username then
             local encodedUsername = utilService:urlEncodeComponent(user.username)
             table.insert(navLinks, {href = "/profile/" .. encodedUsername, text = "PROFILE"})
        end
        -- Add Admin link if user has 'admin' badge
        if isAdmin then
            table.insert(navLinks, {href = "/admin/badges", text = "MANAGE BADGES"})
        end
        table.insert(navLinks, {href = "/logout", text = "LOGOUT"}) -- Logged in users see logout
    else
         table.insert(navLinks, {href = "/register", text = "REGISTER"}) -- Not logged in see register
         table.insert(navLinks, {href = "/login", text = "LOGIN"}) -- Not logged in see login
    end


    local navHtml = "<nav>"
    local currentBasePath = "" -- Used for base path matching
    local currentFullPath = pageData.currentPath or "/" -- Get current path from pageData

    -- Detect base path for admin section
    if string.find(currentFullPath, '^/admin/') then currentBasePath = '/admin' end -- More general admin base path
    if string.find(currentFullPath, '^/admin/badges') then currentBasePath = '/admin/badges' end -- Specific for badges

    for _, link in ipairs(navLinks) do
      local isActive = false
      -- Exact match first
      if currentFullPath == link.href then
          isActive = true
      -- Base path match for admin badge section
      elseif currentBasePath == '/admin/badges' and link.href == '/admin/badges' then
           isActive = true
      -- Profile link active state (your own profile)
      elseif string.find(currentFullPath, '^/profile/') and user and user.username and link.href == ('/profile/' .. utilService:urlEncodeComponent(user.username)) then
          isActive = true
      -- Edit profile link active state
      elseif currentFullPath == '/profile/edit' and link.href == '/profile/edit' then
           isActive = true
      end

      navHtml = navHtml .. string.format('<a href="%s"%s>%s</a>',
                                         escapeHtml(link.href),
                                         isActive and ' class="active"' or '',
                                         escapeHtml(link.text))
    end
    navHtml = navHtml .. "</nav>"

    -- Add user status display in the header or elsewhere
    local userStatusHtml = ""
    if user and user.username then -- Ensure user and username exist
        userStatusHtml = string.format('<div class="user-status">Logged in as: <strong>%s</strong></div>', escapeHtml(user.username))
    else
        userStatusHtml = '<div class="user-status">Not logged in</div>'
    end


    -- Generate main content based on pageType

    if pageType == 'home' then
      headerMascotBubble = "Welcome to SeaDrive!"
      mainContentHtml = [[
          <div class="content-section home-content">
              <h2>Welcome!</h2>
              <div class="answer-box" style="text-align: center;">
                  <p>Hi there! I'm SeaDrive, your feline help buddy.</p>
                  <p>Got a question? Head over to the Ask page!</p>
                   ]] .. (user and '<p>Want to teach me something? Go to the Add page!</p>' or '<p>Log in or register to teach me something!</p>') .. [[
                   ]] .. (user and '<p>Want to view or edit your profile? Click the Profile link!</p>' or '') .. [[
                   ]] .. (isAdmin and '<p>Want to manage badges? Click the Manage Badges link!</p>' or '') .. [[
                  <p style="margin-top: 20px;">
                      <a href="/ask" class="button button-ask">Go to Ask Page</a>
                       ]] .. (user and '<a href="/add" class="button button-add">Go to Add Page</a>' or '') .. [[
                       ]] .. (not user and '<a href="/register" class="button button-register">Register</a> <a href="/login" class="button button-login">Login</a>' or '') .. [[
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
        local escapedAnswer = escapeHtml(tostring(answerData.answer or ""))
        -- Display author if available in data structure and link to profile
        local authorHtml = ""
        if answerData.author and answerData.author ~= "" and answerData.author ~= "Anonymous" then
             local authorName = answerData.author
             local escapedAuthor = escapeHtml(authorName)
             local encodedAuthor = utilService:urlEncodeComponent(authorName)
             local profileLink = "/profile/" .. encodedAuthor
             authorHtml = '<p class="answer-author">Contributed by: <a href="' .. escapeHtml(profileLink) .. '">' .. escapedAuthor .. '</a></p>'
        end
        answerHtml = [[<div class="answer-section"><div class="answer-box"><p class="answer-title">Here's information for:<br>]] .. escapeHtml(currentQuestion) .. [[</p><p>]] .. escapedAnswer .. [[</p>]] .. authorHtml .. [[</div><div class="mascot-area main-mascot-area"><div class="speech-bubble speech-bubble-bottom">Found it!</div><img src="/images/mascot.png" alt="SeaDrive Mascot" class="mascot-img mascot-main-img"></div></div>]]
        bottomMascotHtml = ""
      elseif currentQuestion ~= "" then -- Question asked, but no answer found
         headerMascotBubble = "Hmm, I'm not sure..."
         answerHtml = [[<div class="answer-section"><div class="answer-box not-found-box"><p class="answer-title">Sorry, I couldn't find an answer for:<br>]] .. escapeHtml(currentQuestion) .. [[</p><p>My knowledge is limited right now. ]] .. (user and 'Maybe you can <a href="/add">teach me</a>?' or 'Perhaps someone needs to teach me (you can <a href="/register">register</a> and <a href="/login">login</a> to add knowledge)?') .. [[</p></div><div class="mascot-area main-mascot-area"><div class="speech-bubble speech-bubble-bottom">Purrhaps try again?</div><img src="/images/mascot.png" alt="SeaDrive Mascot" class="mascot-img mascot-main-img"></div></div>]]
         bottomMascotHtml = ""
      end
      local escapedQuestionInput = escapeHtml(currentQuestion) -- Escape for value attr
      mainContentHtml = [[<div class="ask-section"><h2>Ask SeaDrive:</h2><form method="GET" action="/ask" class="ask-input-group"><input type="text" name="question" placeholder="Type your question here..." value="]] .. escapedQuestionInput .. [["><button type="submit">ASK</button></form></div>]] .. answerHtml .. bottomMascotHtml


    elseif pageType == 'add' then
       headerMascotBubble = user and "Teach me something new!" or "Psst! Log in to add!"
       mainContentHtml = [[
           <div class="content-section add-content">
               <h2>Add a New Question & Answer</h2>
               ]] .. statusHtml .. [[
               ]] .. (user and [[
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
                    <div class="mascot-area main-mascot-area"> <img src="/images/mascot.png" alt="SeaDrive Mascot - Eager" class="mascot-img mascot-main-img" style="display: inline-block;"> </div>
               </div>
               ]] or [[
                   <div class="answer-box">
                       <p>You must be logged in to add new questions and answers.</p>
                       <p>Please <a href="/login">log in</a> or <a href="/register">register</a>.</p>
                   </div>
                     <div class="bubble-mascot-wrapper" style="width: fit-content; margin-left: auto; margin-right: auto; margin-top: 20px; text-align: center;">
                         <div class="speech-bubble speech-bubble-bottom" style="position: static !important; left: auto !important; right: auto !important; transform: none !important; margin-bottom: 5px; display: block;">
                             Waiting for you!
                         </div>
                          <div class="mascot-area main-mascot-area"> <img src="/images/mascot.png" alt="SeaDrive Mascot - Waiting" class="mascot-img mascot-main-img" style="display: inline-block;"> </div>
                     </div>
               ]]) .. [[
           </div>
       ]]


    elseif pageType == 'qotd' then
      headerMascotBubble = "Question of the Day!"
      local escapedQotdQuestion = escapeHtml(tostring(qotdData.question or "Loading..."))
      local escapedQotdAnswer = escapeHtml(tostring(qotdData.answer or "Loading..."))
        -- Display author for QOTD if available and link to profile
      local qotdAuthorHtml = ""
       if qotdData.author and qotdData.author ~= "" and qotdData.author ~= "Anonymous" then
           local authorName = qotdData.author
           local escapedAuthor = escapeHtml(authorName)
           local encodedAuthor = utilService:urlEncodeComponent(authorName)
           local profileLink = "/profile/" .. encodedAuthor
           qotdAuthorHtml = '<p class="answer-author">Contributed by: <a href="' .. escapeHtml(profileLink) .. '">' .. escapedAuthor .. '</a></p>'
       end

      mainContentHtml = [[ <div class="content-section qotd-content"><h2>Question of the Day!</h2><div class="answer-box"><p class="answer-title"><strong>Q:</strong> ]] .. escapedQotdQuestion .. [[</p><p><strong>A:</strong> ]] .. escapedQotdAnswer .. [[</p>]] .. qotdAuthorHtml .. [[</div><div class="mascot-area main-mascot-area"><div class="speech-bubble speech-bubble-bottom">Today's tidbit!</div><img src="/images/mascot.png" alt="SeaDrive Mascot" class="mascot-img mascot-main-img"></div></div> ]]

    elseif pageType == 'about' then
      headerMascotBubble = "About Me!"
      local escapedAboutTitle = escapeHtml(tostring(aboutData.title or "About"))
      local escapedAboutText = escapeHtml(tostring(aboutData.text or "No info available"))
      mainContentHtml = [[ <div class="content-section about-content"><h2>]] .. escapedAboutTitle .. [[</h2><div class="answer-box"><p>]] .. escapedAboutText .. [[</p></div><div class="mascot-area main-mascot-area"><div class="speech-bubble speech-bubble-bottom">That's me!</div><img src="/images/mascot.png" alt="SeaDrive Mascot" class="mascot-img mascot-main-img"></div></div> ]]


    -- Registration and Login pages
    elseif pageType == 'register' then
         headerMascotBubble = user and "Welcome back!" or "Join the fun!"
         mainContentHtml = [[
             <div class="content-section auth-content">
                 <h2>Register New Account</h2>
                 ]] .. statusHtml .. [[
                  ]] .. (user and '<p>You are already logged in as ' .. escapeHtml(user.username) .. '. <a href="/logout">Logout</a> if you want to register a new account.</p>' or '') .. [[
                 ]] .. (not user and [[
                 <form method="POST" action="/register" class="auth-form">
                     <div class="form-group">
                         <label for="username">Username:</label>
                         <input type="text" id="username" name="username" required autocomplete="username">
                     </div>
                     <div class="form-group">
                         <label for="password">Password:</label>
                         <input type="password" id="password" name="password" required autocomplete="new-password">
                     </div>
                     <button type="submit">Register</button>
                 </form>
                 <p>Already have an account? <a href="/login">Login here</a>.</p>
                 ]] or '') .. [[
                 <div class="bubble-mascot-wrapper" style="width: fit-content; margin-left: auto; margin-right: auto; margin-top: 20px; text-align: center;">
                     <div class="speech-bubble speech-bubble-bottom" style="position: static !important; left: auto !important; right: auto !important; transform: none !important; margin-bottom: 5px; display: block;"> Sign up meow! </div>
                      <div class="mascot-area main-mascot-area"> <img src="/images/mascot.png" alt="SeaDrive Mascot - Register" class="mascot-img mascot-main-img" style="display: inline-block;"> </div>
                 </div>
             </div>
         ]]

    elseif pageType == 'login' then
         headerMascotBubble = user and "Welcome back!" or "Ready to chat?"
         mainContentHtml = [[
             <div class="content-section auth-content">
                 <h2>Login to Your Account</h2>
                 ]] .. statusHtml .. [[
                 ]] .. (user and '<p>You are already logged in as ' .. escapeHtml(user.username) .. '.</p>' or '') .. [[
                 ]] .. (not user and [[
                 <form method="POST" action="/login" class="auth-form">
                     <div class="form-group">
                         <label for="username">Username:</label>
                         <input type="text" id="username" name="username" required autocomplete="username">
                     </div>
                     <div class="form-group">
                         <label for="password">Password:</label>
                         <input type="password" id="password" name="password" required autocomplete="current-password">
                     </div>
                     <button type="submit">Login</button>
                 </form>
                 <p>Don't have an account? <a href="/register">Register here</a>.</p>
                 ]] or '') .. [[
                 <div class="bubble-mascot-wrapper" style="width: fit-content; margin-left: auto; margin-right: auto; margin-top: 20px; text-align: center;">
                     <div class="speech-bubble speech-bubble-bottom" style="position: static !important; left: auto !important; right: auto !important; transform: none !important; margin-bottom: 5px; display: block;"> Come on in! </div>
                     <div class="mascot-area main-mascot-area"> <img src="/images/mascot.png" alt="SeaDrive Mascot - Login" class="mascot-img mascot-main-img" style="display: inline-block;"> </div>
                 </div>
             </div>
         ]]

    -- Profile View Page
    elseif pageType == 'profile_view' then
        local profileData = pageData.profileData or {}
        local userQuestions = pageData.userQuestions or {}
        local allBadgeDefs = pageData.allBadgeDefs or {} -- Get badge definitions map
        local isOwnProfile = user and profileData and user.username == user.username

        headerMascotBubble = profileData.username and ("Viewing " .. escapeHtml(profileData.username) .. "'s Profile") or "Profile Not Found"

        local escapedUsername = escapeHtml(profileData.username or "Unknown User")
        local pfpUrl = profileData.profilePfpUrl and profileData.profilePfpUrl ~= "" and profileData.profilePfpUrl or DEFAULT_PFP_URL
        if not pfpUrl:match('^https?://') and not pfpUrl:match('^/') then pfpUrl = DEFAULT_PFP_URL end
        local escapedPfpUrl = escapeHtml(pfpUrl)

        local escapedDescription = escapeHtml(profileData.profileDescription or "")
        if escapedDescription == "" then escapedDescription = "<i>No description provided.</i>" end

        local registeredDateStr = "Unknown"
        if profileData.registeredAt and tonumber(profileData.registeredAt) then
            registeredDateStr = os.date('%Y-%m-%d', tonumber(profileData.registeredAt))
        end

        -- Generate Badges HTML using dynamic definitions
        local badgesHtml = ""
        local userBadges = profileData.badges or {}
        if type(userBadges) == 'table' and #userBadges > 0 then
            badgesHtml = '<div class="profile-badges">'
            for _, badgeId in ipairs(userBadges) do
                 local badgeDef = allBadgeDefs[badgeId] -- Look up definition from passed data
                 if badgeDef then
                     local badgeName = escapeHtml(badgeDef.name or badgeId)
                     local badgeColor = escapeHtml(badgeDef.color or '#cccccc')
                     local badgeImageUrl = escapeHtml(badgeDef.imageUrl or '')
                     local badgeDescription = escapeHtml(badgeDef.description or badgeName)

                     badgesHtml = badgesHtml .. string.format(
                        '<span class="badge" style="background-color: %s;" title="%s">' ..
                        '<img src="%s" class="badge-icon" alt="%s icon" onerror="this.style.display=\'none\'"> %s' ..
                        '</span>',
                        badgeColor, badgeDescription, badgeImageUrl, badgeName, badgeName
                     )
                 end
            end
            badgesHtml = badgesHtml .. '</div>'
        end

        local questionsHtml = '<p>No questions added yet.</p>'
        if userQuestions and #userQuestions > 0 then
            questionsHtml = '<ul class="profile-questions-list">'
            for _, q in ipairs(userQuestions) do
                local escapedQ = escapeHtml(q)
                local askLink = '/ask?question=' .. utilService:urlEncodeComponent(q)
                questionsHtml = questionsHtml .. '<li><a href="' .. escapeHtml(askLink) .. '">' .. escapedQ .. '</a></li>'
            end
            questionsHtml = questionsHtml .. '</ul>'
        end

        mainContentHtml = [[
            <div class="content-section profile-container">
                <h2>User Profile: ]] .. escapedUsername .. [[</h2>
                 ]] .. statusHtml .. [[
                <div class="profile-header">
                    <img src="]] .. escapedPfpUrl .. [[" alt="Profile Picture for ]] .. escapedUsername .. [[" class="profile-pfp" onerror="this.onerror=null; this.src='']] .. DEFAULT_PFP_URL ..[[';">
                    <div class="profile-info">
                        <h3 class="profile-username">]] .. escapedUsername .. [[</h3>
                        ]] .. badgesHtml .. [[ <!-- Insert Badges HTML -->
                        <p class="profile-meta">Member Since: ]] .. registeredDateStr .. [[</p>
                        ]] .. (isOwnProfile and '<a href="/profile/edit" class="profile-edit-button button">Edit Profile</a>' or '') .. [[
                    </div>
                </div>
                <div class="profile-description answer-box">
                     <h4>Description:</h4>
                     <p>]] .. escapedDescription .. [[</p>
                 </div>
                 <div class="profile-questions">
                    <h4>Questions Added:</h4>
                    ]] .. questionsHtml .. [[
                </div>
             </div>
        ]]

    -- Profile Edit Page
    elseif pageType == 'profile_edit' then
         headerMascotBubble = "Update your profile!"
         local profileData = pageData.profileData or {}
         local currentPfpUrl = profileData.profilePfpUrl or ""
         local escapedPfpUrlAttr = escapeHtml(currentPfpUrl)
         local escapedDescriptionContent = (profileData.profileDescription or ""):gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;') -- No quote escape needed

         mainContentHtml = [[
             <div class="content-section profile-edit-container">
                 <h2>Edit Your Profile</h2>
                 ]] .. statusHtml .. [[
                 ]] .. (not user and '<p class="error">Error: You must be logged in to edit your profile.</p>' or [[
                 <form method="POST" action="/profile/edit" class="auth-form profile-edit-form">
                     <div class="form-group">
                         <label for="profilePfpUrl">Profile Picture URL:</label>
                         <input type="url" id="profilePfpUrl" name="profilePfpUrl" value="]] .. escapedPfpUrlAttr .. [[" placeholder="https://example.com/image.png or /images/icon.png">
                     </div>
                     <div class="form-group">
                         <label for="profileDescription">Description:</label>
                         <textarea id="profileDescription" name="profileDescription" rows="5" placeholder="Tell us about yourself!">]] .. escapedDescriptionContent .. [[</textarea>
                     </div>
                     <button type="submit">Save Changes</button>
                 </form>
                 ]]) .. [[
            </div>
        ]]

    -- START Admin Badge Management Pages
    elseif pageType == 'admin_badge_list' then
        headerMascotBubble = "Manage Badges"
        local badgesMap = pageData.badgesMap or {}
        local badgeRows = ""
        local sortedIds = {}
        for id, _ in pairs(badgesMap) do table.insert(sortedIds, id) end
        table.sort(sortedIds)

        if #sortedIds == 0 then
            badgeRows = '<tr><td colspan="6">No badges defined yet.</td></tr>' -- Adjusted colspan
        else
            for _, badgeId in ipairs(sortedIds) do
                local badge = badgesMap[badgeId]
                local editUrl = "/admin/badges/edit/" .. utilService:urlEncodeComponent(badgeId)
                local deleteUrl = "/admin/badges/delete/" .. utilService:urlEncodeComponent(badgeId)
                badgeRows = badgeRows .. string.format([[
                    <tr>
                        <td><img src="%s" class="badge-icon-table" alt="%s" onerror="this.style.display='none';"></td>
                        <td>%s</td>
                        <td>%s</td>
                        <td style="color: %s;">%s</td>
                        <td>%s</td>
                        <td>
                            <a href="%s" class="button button-edit">Edit</a>
                            <form method="POST" action="%s" style="display:inline;" onsubmit="return confirm('Are you sure you want to delete the badge \'%s\'? This cannot be undone.');">
                                <button type="submit" class="button button-delete">Delete</button>
                            </form>
                        </td>
                    </tr>
                ]], escapeHtml(badge.imageUrl), escapeHtml(badge.name),
                    escapeHtml(badgeId), escapeHtml(badge.name), escapeHtml(badge.color), escapeHtml(badge.color),
                    escapeHtml(badge.description or ""),
                    escapeHtml(editUrl), escapeHtml(deleteUrl), escapeHtml(badge.name)
                )
            end
        end

        mainContentHtml = [[
            <div class="content-section admin-content">
                <h2>Manage Badge Definitions</h2>
                ]] .. statusHtml .. [[
                <p><a href="/admin/badges/add" class="button button-add">Add New Badge</a></p>
                <table class="admin-table">
                    <thead>
                        <tr>
                            <th>Icon</th>
                            <th>ID</th>
                            <th>Name</th>
                            <th>Color</th>
                            <th>Description</th>
                            <th>Actions</th>
                        </tr>
                    </thead>
                    <tbody>
                        ]] .. badgeRows .. [[
                    </tbody>
                </table>
            </div>
        ]]

    elseif pageType == 'admin_badge_add' or pageType == 'admin_badge_edit' then
        local isEdit = (pageType == 'admin_badge_edit')
        local badgeData = pageData.badgeData or {}
        headerMascotBubble = isEdit and "Edit Badge" or "Add New Badge"
        local formAction = isEdit and ("/admin/badges/edit/" .. utilService:urlEncodeComponent(badgeData.id or "")) or "/admin/badges/add"
        local badgeId = badgeData.id or ""
        local badgeName = badgeData.name or ""
        local badgeDesc = badgeData.description or ""
        local badgeImgUrl = badgeData.imageUrl or ""
        local badgeColor = badgeData.color or "#cccccc"

        mainContentHtml = [[
            <div class="content-section admin-content">
                <h2>]] .. headerMascotBubble .. [[</h2>
                ]] .. statusHtml .. [[
                <form method="POST" action="]] .. escapeHtml(formAction) .. [[" class="auth-form admin-form">
                    <div class="form-group">
                        <label for="badgeId">Badge ID:</label>
                        <input type="text" id="badgeId" name="id" value="]] .. escapeHtml(badgeId) .. [[" placeholder="e.g., admin, supporter, event_2024" required pattern="[a-zA-Z0-9][a-zA-Z0-9_-]*" title="Must start with letter/number, can contain letters, numbers, _, -" ]] .. (isEdit and "readonly" or "") .. [[>
                        ]] .. (isEdit and "<small>ID cannot be changed after creation.</small>" or "<small>Unique identifier (letters, numbers, -, _ starting with letter/number). Cannot be changed later.</small>") .. [[
                    </div>
                     <div class="form-group">
                        <label for="badgeName">Display Name:</label>
                        <input type="text" id="badgeName" name="name" value="]] .. escapeHtml(badgeName) .. [[" placeholder="e.g., Administrator, Gold Supporter" required>
                    </div>
                    <div class="form-group">
                        <label for="badgeImageUrl">Image URL:</label>
                        <input type="url" id="badgeImageUrl" name="imageUrl" value="]] .. escapeHtml(badgeImgUrl) .. [[" placeholder="https://example.com/icon.png or /images/badge.png" required>
                    </div>
                     <div class="form-group">
                        <label for="badgeColor">Display Color:</label>
                        <input type="color" id="badgeColor" name="color" value="]] .. escapeHtml(badgeColor) .. [["> <!-- Use color input type -->
                        <input type="text" id="badgeColorText" name="color_text" value="]] .. escapeHtml(badgeColor) .. [[" placeholder="#RRGGBB or rgb(...) or name" style="margin-left: 10px; width: 60%;">
                         <script>
                             document.getElementById('badgeColor').addEventListener('input', function(e) { document.getElementById('badgeColorText').value = e.target.value; });
                             document.getElementById('badgeColorText').addEventListener('input', function(e) { /* Update color picker only if input seems valid */ var inputVal = e.target.value; if(inputVal.match(/^#([a-fA-F0-9]{6}|[a-fA-F0-9]{3})$/) || inputVal.match(/^(rgb|hsl)a?\(.*\)$/) || inputVal.match(/^\w+$/)){ document.getElementById('badgeColor').value = inputVal; } });
                         </script>
                         <small>Used for background (defaults to gray).</small>
                    </div>
                     <div class="form-group">
                        <label for="badgeDescription">Description (Optional):</label>
                        <textarea id="badgeDescription" name="description" rows="3" placeholder="Short description shown on hover">]] .. escapeHtml(badgeDesc):gsub('<','&lt;'):gsub('>','&gt;') .. [[</textarea>
                    </div>
                    <button type="submit">]] .. (isEdit and "Save Changes" or "Create Badge") .. [[</button>
                    <a href="/admin/badges" style="margin-left: 15px;">Cancel</a>
                </form>
            </div>
        ]]
    -- END Admin Badge Management Pages

    elseif pageType == 'notfound' then
      headerMascotBubble = "Uh oh... Lost?"
      mainContentHtml = [[
           <div class="content-section notfound-content">
              <h2 class="notfound-title">404 / Forbidden</h2>
              <div class="answer-box notfound-box">
                  <p>Mrow! Looks like the page you were looking for doesn't exist or you don't have permission to see it.</p>
                  <p>Maybe try asking me something on the main page?</p>
                  <p class="notfound-link-wrapper"><a href="/ask" class="button button-ask">Go to Ask Page</a></p>
                   <p class="notfound-link-wrapper" style="margin-top: 10px;"><small>Message: ]] .. escapeHtml(statusMsg or "Page not found.") .. [[</small></p>
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
    <meta property="og:title" content="Ask Seadrive">
    <meta property="og:description" content="Your feline help buddy!">
    <meta property="og:image" content="/images/mascot.png">
    <meta property="og:url" content="http://seadrive.online">
    <meta property="og:type" content="website">
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SeaDrive</title>
    <link rel="stylesheet" href="/style.css">
    <style>
      /* Status Message Styles */
      .status-message { padding: 10px; margin-bottom: 15px; border-radius: 4px; border: 1px solid transparent; }
      .status-message.success { background-color: #dff0d8; border-color: #d6e9c6; color: #3c763d; }
      .status-message.error { background-color: #f2dede; border-color: #ebccd1; color: #a94442; }
      .status-message.info { background-color: #d9edf7; border-color: #bce8f1; color: #31708f; }

      /* Form Group Styles */
      .form-group { margin-bottom: 15px; }
      label { display: block; margin-bottom: 5px; font-weight: bold; }
      input[type="text"], input[type="password"], input[type="url"], input[type="email"], textarea {
          width: 95%; padding: 8px; border: 1px solid #ccc; border-radius: 4px; box-sizing: border-box;
      }
      textarea { resize: vertical; }
      .form-group small { color: #666; font-size: 0.9em; display: block; margin-top: 3px;}
      input[readonly] { background-color: #eee; cursor: not-allowed; }

      /* Button Styles */
       .button { display: inline-block; padding: 8px 15px; margin: 5px 5px 5px 0; border: none; border-radius: 4px; color: white; text-decoration: none; cursor: pointer; text-align: center; font-size: 1em; }
       .button-ask { background-color: #8bc37a; } .button-ask:hover { background-color: #7ab96a; }
       .button-add { background-color: #7ab8c3; } .button-add:hover { background-color: #6aa7b3; }
       .button-register { background-color: #c3a37a; } .button-register:hover { background-color: #b3936a; }
       .button-login { background-color: #7ac3b8; } .button-login:hover { background-color: #6ab3a8; }
       .button-edit { background-color: #f0ad4e; font-size: 0.9em; padding: 4px 8px; } .button-edit:hover { background-color: #ec971f; }
       .button-delete { background-color: #d9534f; font-size: 0.9em; padding: 4px 8px; } .button-delete:hover { background-color: #c9302c; }
       form button[type="submit"] { /* General submit buttons */
            padding: 10px 15px; background-color: #5cb85c; color: white; border: none; border-radius: 4px; cursor: pointer; font-size: 1em;
       }
        form button[type="submit"]:hover { background-color: #4cae4c; }

      /* User Status Style */
      .user-status { font-size: 0.9em; color: #555; text-align: center; margin-bottom: 10px; }

      /* Author Info Style */
       .answer-author { font-size: 0.9em; color: #666; margin-top: 10px; text-align: right;}
       .answer-author a { color: #555; text-decoration: none;}
       .answer-author a:hover { text-decoration: underline; color: #333; }

       /* Basic Auth/Admin Form Specific Styling */
       .auth-form { max-width: 400px; margin: 20px auto; padding: 20px; border: 1px solid #ddd; border-radius: 8px; background-color: #fff; }
       .admin-form { max-width: 600px; } /* Wider admin form */
       .auth-form .form-group input:not([type=color]) { width: calc(100% - 18px); } /* Adjust width for padding/border */
       .auth-content p { text-align: center; margin-top: 15px; }

      /* Profile Page Styles */
      .profile-container { text-align: left; }
      .profile-header { display: flex; align-items: flex-start; margin-bottom: 20px; background-color: #f9f9f9; padding: 15px; border-radius: 8px; border: 1px solid #eee;}
      .profile-pfp { width: 100px; height: 100px; border-radius: 50%; margin-right: 20px; border: 3px solid #ddd; object-fit: cover; background-color: #eee; flex-shrink: 0; }
      .profile-info { flex-grow: 1; }
      .profile-username { margin: 0 0 5px 0; font-size: 1.8em; color: #333;}
      .profile-meta { font-size: 0.9em; color: #777; margin: 5px 0 0 0; }
      .profile-edit-button { display: inline-block; margin-top: 10px; font-size: 0.9em; } /* Use general button class */
      .profile-description { margin-bottom: 20px; background-color: #e4f0f4; border-color: #a4c4e0; padding: 15px; border: 1px solid #a4c4e0; border-radius: 4px;}
      .profile-description h4, .profile-questions h4 { margin-top: 0; margin-bottom: 10px; color: #385e7a;}
      .profile-questions { background-color: #f0f0f0; padding: 15px; border-radius: 8px; border: 1px solid #ddd;}
      .profile-questions-list { list-style: none; padding: 0; margin: 0; }
      .profile-questions-list li { margin-bottom: 8px; background-color: #fff; padding: 8px; border-radius: 4px; border: 1px solid #eee;}
      .profile-questions-list li a { text-decoration: none; color: #007bff; }
      .profile-questions-list li a:hover { text-decoration: underline; }

      /* Badge Styles (Profile & Admin) */
      .profile-badges { margin: 5px 0 8px 0; }
      .badge {
          display: inline-flex; align-items: center;
          padding: 3px 8px; margin-right: 5px; margin-bottom: 5px;
          font-size: 0.85em; font-weight: bold; color: #fff;
          border-radius: 4px; line-height: 1;
          text-shadow: 1px 1px 1px rgba(0,0,0,0.2);
          vertical-align: middle;
      }
       .badge-icon {
          width: 1em; height: 1em; margin-right: 4px;
          vertical-align: middle; object-fit: contain;
      }
       .badge-icon-table {
          width: 20px; height: 20px; vertical-align: middle;
          object-fit: contain; margin-right: 5px; background-color: #eee; border-radius: 2px;
       }

      /* Profile Edit Form Specifics */
      .profile-edit-form textarea { width: 95%; }
      .profile-edit-form input[type="url"] { width: 95%; }

      /* Admin Page Styles */
      .admin-content { padding: 20px; }
      .admin-table { width: 100%; border-collapse: collapse; margin-top: 20px; }
      .admin-table th, .admin-table td { border: 1px solid #ddd; padding: 8px; text-align: left; vertical-align: middle;}
      .admin-table th { background-color: #f2f2f2; }
      .admin-table tr:nth-child(even) { background-color: #f9f9f9; }
      .admin-table td form { margin: 0; padding: 0; }
      .admin-form input[type=color] { vertical-align: middle; height: 30px; padding: 2px; border: 1px solid #ccc; border-radius: 4px; }
      .admin-form input[name=color_text] { width: auto !important; display: inline-block; max-width: 150px; }

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
        ]] .. userStatusHtml .. [[  <!-- Display user status -->
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
