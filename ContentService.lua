local ContentService = {}
ContentService.libs = {} -- libs table will be injected by require2

local knowledgeService -- Reference to the KnowledgeService

-- --- QOTD Data ---
-- Now stores author as well, matching KnowledgeService data structure
local qotdData = {
  question = "Loading...",
  answer = "Selecting question...",
  author = ""
}
ContentService.qotdData = qotdData -- Make it accessible


-- --- Content for Other Pages ---
local aboutData = {
  title = "About SeaDrive",
  text = "SeaDrive is your friendly feline help buddy, built with the power of Luvit and Lua! I'm here to answer your questions based on my knowledge base, which you can contribute to! While I may not know everything (yet!), I'm always eager to help. Meow!"
}
ContentService.aboutData = aboutData -- Make it accessible


-- Initialize the service with dependencies
function ContentService:init(kbService)
    -- Validate KnowledgeService dependency
    if not kbService or type(kbService) ~= 'table' or type(kbService.getAllQuestions) ~= 'function' or type(kbService.getAnswer) ~= 'function' then
        print("ContentService: KnowledgeService dependency missing or invalid!")
        -- Allow init to succeed but functions relying on kbService will error or return defaults
        knowledgeService = nil 
        return true
    end
    knowledgeService = kbService
    print("ContentService initialized with KnowledgeService.")
    return true
end

-- Update QOTD using the knowledgeBase from KnowledgeService
function ContentService:updateQotd()
  -- Check if KnowledgeService dependency was successfully initialized
  if not knowledgeService or not knowledgeService.getAllQuestions or not knowledgeService.getAnswer then
      print("ContentService: Cannot update QOTD, KnowledgeService not initialized or methods missing.")
      qotdData.question = "Service Error"
      qotdData.answer = "Knowledge service not loaded."
      qotdData.author = ""
      return
  end

  local questions = knowledgeService:getAllQuestions() -- Use the service method
  if type(questions) ~= 'table' or #questions == 0 then -- Add type check for safety
    print("Warning: Knowledge base is empty or questions could not be retrieved. Cannot update QOTD.")
    qotdData.question = "No questions available"
    qotdData.answer = "Add some questions using the 'Add' page!"
     qotdData.author = ""
    return
  end
  local randomIndex = math.random(#questions)
  local selectedQuestion = questions[randomIndex]
  local selectedAnswerData = knowledgeService:getAnswer(selectedQuestion) -- Use the service method

  -- Update qotdData, including the author field
  qotdData.question = selectedQuestion
  qotdData.answer = (selectedAnswerData and selectedAnswerData.answer) or "Internal Error: Could not find answer for selected QOTD."
  qotdData.author = (selectedAnswerData and selectedAnswerData.author) or ""

  print(os.date("%Y-%m-%d %H:%M:%S") .. " - Updated QOTD to: [" .. qotdData.question .. "] by " .. (qotdData.author ~= "" and qotdData.author or "Anonymous"))
end


return ContentService