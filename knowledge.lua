-- knowledge.lua
local fs = require('fs')
local json = require('json') -- Luvit bundles a JSON library
local path = require('path')

local M = {} -- Our module table

local KNOWLEDGE_FILE = "knowledge_base.json" -- File to store data
local knowledgeData = {} -- This will hold the actual Q&A data

-- --- Private Helper Functions ---

-- Normalize question (lowercase, trim whitespace)
local function normalizeQuestion(q)
  if type(q) ~= 'string' then return "" end
  return q:lower():match("^%s*(.-)%s*$")
end

-- Save the current knowledgeData to the JSON file (asynchronously)
local function saveToFile()
  local jsonData, err = pcall(json.encode, knowledgeData, { pretty = true }) -- Make JSON readable
  if not jsonData then
      print("Error encoding knowledge base to JSON:", err)
      return
  end

  fs.writeFile(KNOWLEDGE_FILE, jsonData, function(writeErr)
    if writeErr then
      print("Error writing knowledge base to " .. KNOWLEDGE_FILE .. ":", writeErr.message)
    else
      -- Optional: print("Knowledge base saved successfully to " .. KNOWLEDGE_FILE)
    end
  end)
end

-- --- Public Module Functions ---

-- Load data from JSON file (synchronously - usually okay at startup)
function M.load()
  print("Attempting to load knowledge base from " .. KNOWLEDGE_FILE .. "...")
  local fileContent, readErr = fs.readFileSync(KNOWLEDGE_FILE) -- Use sync for startup simplicity

  if not fileContent then
    if readErr and readErr.code == 'ENOENT' then
      print("Knowledge file not found. Starting with an empty base (or defaults if added below).")
      -- Optionally, add default entries if the file doesn't exist
      -- M.add("Default Question?", "Default Answer.", true) -- Pass 'true' to skip save on initial load
      knowledgeData = {} -- Ensure it's an empty table
    else
      print("Error reading knowledge file " .. KNOWLEDGE_FILE .. ":", readErr and readErr.message or "Unknown error")
      print("Starting with an empty knowledge base.")
      knowledgeData = {}
    end
    return -- Don't try to decode if read failed
  end

  -- File content exists, try to decode
  local ok, decodedData = pcall(json.decode, fileContent)
  if ok and type(decodedData) == 'table' then
    knowledgeData = decodedData
    print("Knowledge base loaded successfully. Found", M.count(), "entries.")
  else
    print("Error decoding JSON from " .. KNOWLEDGE_FILE .. ":", decodedData) -- 'decodedData' holds error message on failure
    print("Starting with an empty knowledge base due to load error.")
    knowledgeData = {}
  end
end

-- Add a new Question and Answer
-- Returns: success (boolean), message (string)
-- skipSave is internal for initial loading without triggering immediate save
function M.add(question, answer, skipSave)
  local normQ = normalizeQuestion(question)
  local ans = tostring(answer or ""):match("^%s*(.-)%s*$") -- Trim answer too

  if normQ == "" or ans == "" then
    return false, "Question and Answer cannot be empty."
  end

  if knowledgeData[normQ] then
    return false, "This question already exists in the knowledge base."
  end

  knowledgeData[normQ] = { answer = ans }
  print("Added QA: [" .. normQ .. "]")

  if not skipSave then
    saveToFile() -- Save changes asynchronously
  end

  return true, "Question added successfully!"
end

-- Get the answer for a specific question
function M.get(question)
  local normQ = normalizeQuestion(question)
  return knowledgeData[normQ] -- Returns the {answer = ...} table or nil
end

-- Get all questions (returns a list of question strings)
function M.getAllQuestions()
  local questions = {}
  for q, _ in pairs(knowledgeData) do
    table.insert(questions, q)
  end
  return questions
end

-- Get the count of entries
function M.count()
    local count = 0
    for _ in pairs(knowledgeData) do
        count = count + 1
    end
    return count
end


return M