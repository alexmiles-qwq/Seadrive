local ContentService = {}
ContentService.libs = {} 

local knowledgeService -- Reference to the KnowledgeService

-- --- QOTD Data ---
local qotdData = {
  question = "Loading...",
  answer = "Selecting question..."
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
    if not kbService then
        print("ContentService: KnowledgeService dependency missing!")
        return false
    end
    knowledgeService = kbService
    print("ContentService initialized with KnowledgeService.")
    return true
end

-- Update QOTD using the local knowledgeBase
function ContentService:updateQotd()
  if not knowledgeService then
      print("ContentService: Cannot update QOTD, KnowledgeService not initialized.")
      qotdData.question = "Service Error"
      qotdData.answer = "Knowledge service not loaded."
      return
  end

  local questions = knowledgeService:getAllQuestions()
  if #questions == 0 then
    print("Warning: Knowledge base is empty. Cannot update QOTD.")
    qotdData.question = "No questions available"
    qotdData.answer = "Add some questions using the 'Add' page!"
    return
  end
  local randomIndex = math.random(#questions)
  local selectedQuestion = questions[randomIndex]
  local selectedAnswerData = knowledgeService:getAnswer(selectedQuestion) -- Use the service method
  qotdData.question = selectedQuestion
  qotdData.answer = (selectedAnswerData and selectedAnswerData.answer) or "Internal Error: Could not find answer for selected QOTD."
  print(os.date("%Y-%m-%d %H:%M:%S") .. " - Updated QOTD to: [" .. qotdData.question .. "]")
end


return ContentService