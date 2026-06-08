-- debugger.lua
-- Simple debugger and roadmap system for tracking game issues

local debugger = {}

debugger.issues = {}

debugger.issueIdCounter = 0

-- Add a new issue to the roadmap
function debugger.addIssue(description)
    debugger.issueIdCounter = debugger.issueIdCounter + 1
    local issue = {
        id = debugger.issueIdCounter,
        description = description,
        status = "open",
        createdAt = os.date("%Y-%m-%d %H:%M:%S"),
        updatedAt = os.date("%Y-%m-%d %H:%M:%S")
    }
    table.insert(debugger.issues, issue)
    return issue.id
end

-- Update the status of an issue
function debugger.updateIssueStatus(id, status)
    for _, issue in ipairs(debugger.issues) do
        if issue.id == id then
            issue.status = status
            issue.updatedAt = os.date("%Y-%m-%d %H:%M:%S")
            return true
        end
    end
    return false
end

-- Get all issues
function debugger.getIssues()
    return debugger.issues
end

-- Print all issues to console
function debugger.printIssues()
    print("--- Debugger Roadmap Issues ---")
    for _, issue in ipairs(debugger.issues) do
        print(string.format("ID: %d | Status: %s | Created: %s | Updated: %s", issue.id, issue.status, issue.createdAt, issue.updatedAt))
        print("Description: " .. issue.description)
        print("-----------------------------")
    end
end

return debugger
