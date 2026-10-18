local ffi = require("ffi")
local chunkStorage = require("chunk_storage")

local Workers = {}
Workers.__index = Workers

local WINDOWS = ffi.os == "Windows"
local WAIT_OBJECT_0 = 0
local CREATE_NO_WINDOW = 0x08000000

if WINDOWS then
  ffi.cdef[[
    typedef void *HANDLE;
    typedef int BOOL;
    typedef unsigned long DWORD;
    typedef unsigned short WORD;
    typedef struct {
      DWORD cb; char *lpReserved; char *lpDesktop; char *lpTitle;
      DWORD dwX; DWORD dwY; DWORD dwXSize; DWORD dwYSize;
      DWORD dwXCountChars; DWORD dwYCountChars; DWORD dwFillAttribute;
      DWORD dwFlags; WORD wShowWindow; WORD cbReserved2; unsigned char *lpReserved2;
      HANDLE hStdInput; HANDLE hStdOutput; HANDLE hStdError;
    } STARTUPINFOA;
    typedef struct { HANDLE hProcess; HANDLE hThread; DWORD dwProcessId; DWORD dwThreadId; }
      PROCESS_INFORMATION;
    BOOL CreateProcessA(const char *applicationName, char *commandLine,
      void *processAttributes, void *threadAttributes, BOOL inheritHandles,
      DWORD creationFlags, void *environment, const char *currentDirectory,
      STARTUPINFOA *startupInfo, PROCESS_INFORMATION *processInformation);
    DWORD WaitForSingleObject(HANDLE handle, DWORD milliseconds);
    BOOL GetExitCodeProcess(HANDLE process, DWORD *exitCode);
    BOOL TerminateProcess(HANDLE process, unsigned int exitCode);
    BOOL CloseHandle(HANDLE object);
  ]]
end

local function fileExists(path)
  local file = io.open(path, "rb")
  if not file then return false end
  file:close()
  return true
end

local function workerCount(requested)
  local processors = tonumber(os.getenv("NUMBER_OF_PROCESSORS")) or 2
  requested = tonumber(requested) or 0
  if requested <= 0 then requested = math.max(1, processors - 1) end
  return math.max(1, math.min(16, math.floor(requested)))
end

function Workers.new(savePath, options)
  options = options or {}
  local enabled = WINDOWS and savePath ~= nil and fileExists("lib/luajit.exe") and
    fileExists("src/chunk_worker.lua")
  return setmetatable({
    savePath = savePath,
    options = options,
    maxWorkers = enabled and workerCount(options.workerCount) or 0,
    enabled = enabled,
    active = {},
    queued = {},
    serial = 0
  }, Workers)
end

function Workers:count()
  return self.maxWorkers
end

local function writeDescriptor(path, savePath, chunkX, chunkZ, options)
  local file, err = io.open(path, "wb")
  if not file then return false, err end
  file:write(table.concat({
    savePath, tostring(chunkX), tostring(chunkZ), tostring(options.maxHeight or 127),
    tostring(options.generatorType or "default"), tostring(options.worldId or "earth"),
    string.format("%.17g", tonumber(options.seed) or 1), ""
  }, "\n"))
  file:close()
  return true
end

function Workers:launch(job)
  local startup = ffi.new("STARTUPINFOA[1]")
  local process = ffi.new("PROCESS_INFORMATION[1]")
  startup[0].cb = ffi.sizeof(startup[0])
  local command = string.format('"lib\\luajit.exe" "src\\chunk_worker.lua" "%s"',
    job.descriptor:gsub("/", "\\"))
  local commandBuffer = ffi.new("char[?]", #command + 1, command)
  local ok = ffi.C.CreateProcessA("lib\\luajit.exe", commandBuffer, nil, nil, 0,
    CREATE_NO_WINDOW, nil, nil, startup, process) ~= 0
  if not ok then
    job.done, job.failed = true, true
    os.remove(job.descriptor)
    return false
  end
  ffi.C.CloseHandle(process[0].hThread)
  job.process = process[0].hProcess
  self.active[job] = true
  return true
end

function Workers:pump()
  local activeCount = 0
  for job in pairs(self.active) do
    if ffi.C.WaitForSingleObject(job.process, 0) == WAIT_OBJECT_0 then
      local code = ffi.new("DWORD[1]")
      ffi.C.GetExitCodeProcess(job.process, code)
      ffi.C.CloseHandle(job.process)
      job.process = nil
      job.done = true
      job.failed = tonumber(code[0]) ~= 0
      self.active[job] = nil
      os.remove(job.descriptor)
    else
      activeCount = activeCount + 1
    end
  end

  while activeCount < self.maxWorkers do
    local job = table.remove(self.queued, 1)
    if not job then break end
    if self:launch(job) then activeCount = activeCount + 1 end
  end
end

function Workers:submit(chunkX, chunkZ, options)
  if not self.enabled then return nil end
  chunkStorage.ensureDirectory(self.savePath, options)
  self.serial = self.serial + 1
  local descriptor = chunkStorage.path(self.savePath, chunkX, chunkZ, options) ..
    string.format(".job.%d.%d", os.time(), self.serial)
  local ok = writeDescriptor(descriptor, self.savePath, chunkX, chunkZ, options)
  if not ok then return nil end
  local job = {chunkX = chunkX, chunkZ = chunkZ, descriptor = descriptor}
  self.queued[#self.queued + 1] = job
  self:pump()
  return job
end

function Workers:poll(job)
  if not job then return true, true end
  self:pump()
  return job.done == true, job.failed == true
end

-- Pending process jobs normally remain FIFO. When the player changes direction
-- the old front of that queue can be behind them, so let the streamer move an
-- imminent collision chunk ahead without disturbing work already running.
function Workers:prioritize(job)
  if not job or job.done or job.process then return false end
  for index = 1, #self.queued do
    if self.queued[index] == job then
      table.remove(self.queued, index)
      table.insert(self.queued, 1, job)
      return true
    end
  end
  return false
end

function Workers:close()
  for job in pairs(self.active) do
    -- These handles belong exclusively to this pool. Stop unfinished work so a
    -- closed/deleted world cannot be recreated later by an orphan process.
    ffi.C.TerminateProcess(job.process, 1)
    ffi.C.WaitForSingleObject(job.process, 1000)
    ffi.C.CloseHandle(job.process)
    job.process = nil
    os.remove(job.descriptor)
  end
  for i = 1, #self.queued do os.remove(self.queued[i].descriptor) end
  self.active, self.queued = {}, {}
end

return Workers
