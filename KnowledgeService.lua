--- START OF FILE KnowledgeService.lua ---

local KnowledgeService = {}
KnowledgeService.libs = {} -- libs table will be injected by require2

local KNOWLEDGE_FILE = "knowledge_base.json" -- File to store data
local knowledgeBase = {} -- Will be loaded from file or start empty

-- Normalize question (lowercase, trim whitespace)
local function normalizeQuestion(q)
  if type(q) ~= 'string' then return "" end
  return q:lower():match("^%s*(.-)%s*$")
end
KnowledgeService.normalizeQuestion = normalizeQuestion -- Make it public


-- Save the current knowledgeBase to the JSON file (asynchronously)
local function saveKnowledgeBase()
  local fs = KnowledgeService.libs['fs']
  local json = KnowledgeService.libs['json']
  if not fs or not json then
      print("KnowledgeService: Missing required libs (fs or json) for saveKnowledgeBase. Cannot save.")
      return
  end

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
      -- print("Knowledge base saved successfully.") -- Optional: uncomment for verbose saving logs
    end
  end)
end
-- KnowledgeService.saveKnowledgeBase = saveKnowledgeBase -- Keep internal


-- Load data from JSON file (synchronously)
-- This is typically done once at startup, so synchronous is acceptable
function KnowledgeService:loadKnowledgeBase()
  local fs = self.libs['fs']
  local json = self.libs['json']
  if not fs or not json then
       print("KnowledgeService: Missing required libs (fs or json) for loadKnowledgeBase. Cannot load.")
       knowledgeBase = {} -- Ensure base is empty if libs are missing
       return
  end

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
    -- Ensure all entries have an author field for consistency if loading old data
    for q, data in pairs(knowledgeBase) do
        -- If the loaded data is not a table (old format where value was just the answer string), convert it
        if type(data) ~= 'table' then
             knowledgeBase[q] = { answer = tostring(data or ""), author = "" } -- Use empty string for author
        else
            -- If it's a table but 'author' is missing or not a string, ensure it's a string
            data.author = tostring(data.author or ""):match("^%s*(.-)%s*$") -- Trim and default to empty string
             -- Ensure answer exists and is a string
             data.answer = tostring(data.answer or "")
        end
    end

    local count = 0; for _ in pairs(knowledgeBase) do count = count + 1 end
    print("Knowledge base loaded successfully. Found", count, "entries.")
  else
    print("Error decoding JSON from " .. KNOWLEDGE_FILE .. ":", decodedData)
    print("Starting with an empty knowledge base due to load error.")
    knowledgeBase = {}
  end
end


-- Add a new Question and Answer directly to the knowledgeBase
-- Added 'author' parameter
function KnowledgeService:addQA(question, answer, author) -- Added author parameter
  local normQ = normalizeQuestion(question)
  local ans = tostring(answer or ""):match("^%s*(.-)%s*$")
  -- Get author string, default to "Anonymous" if nil or empty/whitespace
  local auth = tostring(author or ""):match("^%s*(.-)%s*$")
   if auth == "" then auth = "Anonymous" end

  if normQ == "" or ans == "" then
    return false, "Question and Answer cannot be empty."
  end
  if knowledgeBase[normQ] then
    return false, "This question already exists in the knowledge base."
  end
  -- Store the author with the answer data
  knowledgeBase[normQ] = { answer = ans, author = auth }
  print("Added QA: [" .. normQ .. "] by " .. auth) -- Log author
  saveKnowledgeBase() -- Keep calling the internal save function
  return true, "Question added successfully!"
end

-- Get the answer for a specific question
function KnowledgeService:getAnswer(question)
  local normQ = normalizeQuestion(question)
  return knowledgeBase[normQ] -- Returns { answer = ..., author = ... } or nil
end

-- Get all questions added by a specific author
function KnowledgeService:getQuestionsByAuthor(authorName)
    local questions = {}
    local searchAuthor = tostring(authorName or ""):match("^%s*(.-)%s*$") -- Normalize search term
    if searchAuthor == "" then return questions end -- No author, no questions

    if type(knowledgeBase) == 'table' then
        for q, data in pairs(knowledgeBase) do
            -- Check if data is a table and has an author field matching the search term
            if type(data) == 'table' and data.author and data.author == searchAuthor then
                table.insert(questions, q) -- Add the question string
            end
        end
    end
    return questions
end

-- Get all question strings
function KnowledgeService:getAllQuestions()
  local questions = {}
  -- Check if knowledgeBase is valid before iterating
  if type(knowledgeBase) == 'table' then
      for q, _ in pairs(knowledgeBase) do table.insert(questions, q) end
  end
  return questions
end

-- Get the count of entries
function KnowledgeService:countKnowledgeEntries()
    local count = 0;
    -- Check if knowledgeBase is valid before iterating
    if type(knowledgeBase) == 'table' then
        for _ in pairs(knowledgeBase) do count = count + 1 end
    end
    return count
end


return KnowledgeService
--- END OF FILE KnowledgeService.lua ---