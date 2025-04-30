local KnowledgeService = {}
KnowledgeService.libs = {} 

local KNOWLEDGE_FILE = "knowledge_base.json" -- File to store data
local knowledgeBase = {} -- Will be loaded from file or start empty

-- Normalize question (lowercase, trim whitespace)
local function normalizeQuestion(q)
  if type(q) ~= 'string' then return "" end
  return q:lower():match("^%s*(.-)%s*$")
end
KnowledgeService.normalizeQuestion = normalizeQuestion


-- Save the current knowledgeBase to the JSON file (asynchronously)
function KnowledgeService:saveKnowledgeBase()
  local fs = self.libs['fs']
  local json = self.libs['json']
  if not fs or not json then
      print("KnowledgeService: Missing required libs (fs or json) for saveKnowledgeBase.")
      return
  end

  local success, result_or_err = pcall(json.encode, knowledgeBase, { pretty = true })

  if not success then
      print("Error encoding knowledge base to JSON:", result_or_err) -- result_or_err holds the error msg
      return
  end

  local jsonData = result_or_err

  fs.writeFile(KNOWLEDGE_FILE, jsonData, function(writeErr)
    if writeErr then
      print("Error writing knowledge base to " .. KNOWLEDGE_FILE .. ":", writeErr.message)
    else
      print("Knowledge base saved successfully.")
    end
  end)
end

-- Load data from JSON file (synchronously)
function KnowledgeService:loadKnowledgeBase()
  local fs = self.libs['fs']
  local json = self.libs['json']
  if not fs or not json then
       print("KnowledgeService: Missing required libs (fs or json) for loadKnowledgeBase.")
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
    local count = 0; for _ in pairs(knowledgeBase) do count = count + 1 end
    print("Knowledge base loaded successfully. Found", count, "entries.")
  else
    print("Error decoding JSON from " .. KNOWLEDGE_FILE .. ":", decodedData)
    print("Starting with an empty knowledge base due to load error.")
    knowledgeBase = {}
  end
end

-- Add a new Question and Answer directly to the knowledgeBase
function KnowledgeService:addQA(question, answer)
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
  self:saveKnowledgeBase() -- Use self: to call the method on the instance
  return true, "Question added successfully!"
end

-- Get the answer for a specific question
function KnowledgeService:getAnswer(question)
  local normQ = normalizeQuestion(question)
  return knowledgeBase[normQ]
end

-- Get all question strings
function KnowledgeService:getAllQuestions()
  local questions = {}
  for q, _ in pairs(knowledgeBase) do table.insert(questions, q) end
  return questions
end

-- Get the count of entries
function KnowledgeService:countKnowledgeEntries()
    local count = 0; for _ in pairs(knowledgeBase) do count = count + 1 end; return count
end


return KnowledgeService