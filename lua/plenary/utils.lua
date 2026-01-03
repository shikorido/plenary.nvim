local M = {}

M.is_win = vim.fn.has("win32") == 1

M.is_msys2 = (function()
  -- Run this once.
  -- UPD. Nope, requires &shell to be unix-ish from msys2.
  --local ok, result = pcall(vim.fn.system, "uname")
  --if ok and result then
  --  if result:find("MINGW64_NT") or
  --     result:find("MINGW32_NT") or
  --     result:find("MSYS_NT") then
  --     return true
  --  end
  --end
  -- Using vim.system (nvim's wrapper over libuv spawn) to call uname directly.
  local obj = vim.system({ "uname" }, { text = true }):wait()
  if obj.code == 0 then
    local stdout = obj.stdout
    if stdout:find("MINGW64_NT") or
       stdout:find("MINGW32_NT") or
       stdout:find("MSYS_NT") then
       return true
    end
  end
  return false
end)()

function M.is_windows_abs_path(s)
  return type(s) == 'string'
    and s:find('^[A-Za-z]:[\\/]')
end

function M.is_posix_abs_path(s)
  return type(s) == 'string'
    and s:find('^/')
end

-- How can we find msys2 installation
-- if it cannot be located from ENV vars?
-- Registry?
-- Or using vim.fn.expand("~") which expands to Windows style path
-- with an assumption that HOME points to msys' home and msys' folder is msys64.
M.msys2_root = M.is_msys2 and (function()
  -- msys2 path in windows style
  -- C:\\msys64 is a common location
  return vim.fn.expand("~"):gsub("/", "\\"):match("^.*msys64")
end)() or nil

-- Handles msys2 virtual (bind mounted) folders like "/bin" (the only one at the moment).
M.msys2_root_map = M.msys2_root and (function()
  -- Direct root mapping
  return {
    ["/bin"] = M.msys2_root .. "\\usr\\bin", -- bind mounted to /usr/bin
    ["/clang64"] = M.msys2_root .. "\\clang64",
    ["/clangarm64"] = M.msys2_root .. "\\clangarm64",
    ["/dev"] = M.msys2_root .. "\\dev",
    ["/etc"] = M.msys2_root .. "\\etc",
    ["/home"] = M.msys2_root .. "\\home",
    ["/installerResources"] = M.msys2_root .. "\\installerResources",
    ["/mingw32"] = M.msys2_root .. "\\mingw32",
    ["/mingw64"] = M.msys2_root .. "\\mingw64",
    ["/opt"] = M.msys2_root .. "\\opt",
    ["/proc"] = M.msys2_root .. "\\proc",
    ["/tmp"] = M.msys2_root .. "\\tmp",
    ["/ucrt64"] = M.msys2_root .. "\\ucrt64",
    ["/usr"] = M.msys2_root .. "\\usr",
    ["/var"] = M.msys2_root .. "\\var"
  }
end)() or nil

-- msys2 to windows actually.
function M.posix_to_windows(posix_path, sep)
  -- Sanity checks.
  if not posix_path or type(posix_path) ~= "string" or #posix_path == 0
    or not M.msys2_root or #M.msys2_root == 0 then
    return posix_path
  end

  if not sep or type(sep) ~= "string" or not sep:find("^[\\/]$") then
    sep = "\\"
  end

  local prefix_changed = false

  -- For a case when vim.fn.expand() eats posix-style path.
  -- In that case we get backslashes from libuv which uses WinAPI under the hood
  -- which we don't need in the conversion logic.
  -- E.g. vim.fn.expand("/home/User") gives "\home\User".
  posix_path = posix_path:gsub("\\", "/")

  -- If path does not begin with '/' - assume prefix should not be changed.
  -- Can potentially break something.
  if posix_path:find("/") ~= 1 then prefix_changed = true end

  -- If we have only "/".
  if not prefix_changed and #posix_path == 1 and posix_path:find("/") then
    --vim.notify("Only '/' case: " .. posix_path, vim.log.levels.WARN)
    ---@type string
    posix_path = M.msys2_root
    prefix_changed = true
  end

  -- Apply root folder mappings only if path starts with "/" and has at least 3 chars after
  if not prefix_changed and posix_path:find("^/[A-Za-z][A-Za-z][A-Za-z]") then
    for prefix, replacement in pairs(M.msys2_root_map) do
      if posix_path:find("^" .. prefix) then
        --vim.notify("msys2 root mapping case: " .. posix_path, vim.log.levels.WARN)
        posix_path = posix_path:gsub("^" .. prefix, replacement)
        prefix_changed = true
        break
      end
    end
  end

  -- Drive letter paths /c/Users -> C:\\Users (+edge case on fast pane split in WezTerm /C:/Users -> C:\\Users).
  -- It is possible to have only "/c" (w/o trailing "/") but not "/C:" (WezTerm internally trails it with "/").
  -- Idk if WezTerm paths behaviour leaks to msys2 actually cause even in regular cmd.exe/powershell.exe it uses
  -- "/<DRIVE>:/" notation internally for panes.
  if not prefix_changed then
    if #posix_path == 2 and posix_path:find("^/[A-Za-z]$") then
      --vim.notify("Only '^/[A-Za-z]$' case: " .. posix_path, vim.log.levels.WARN)
      posix_path = posix_path:gsub("^/([A-Za-z])", "%1:\\")
      prefix_changed = true
    elseif posix_path:find("^/[A-Za-z]:?/") then
      --vim.notify("'^/[A-Za-z]:?/' case: " .. posix_path, vim.log.levels.WARN)
      posix_path = posix_path:gsub("^/([A-Za-z]):?/", "%1:\\")
      prefix_changed = true
    else
      -- The code path can be taken only in specific cases
      -- like a custom folder under msys2 root (/abc).
      --vim.notify("General mapping case for given path: " .. posix_path, vim.log.levels.WARN)
      posix_path = posix_path:gsub("^/", M.msys2_root .. "\\")
      prefix_changed = true
    end
  end

  -- Lets try to use posix-style paths for testing.
  --posix_path = posix_path:gsub("^/([A-Za-z]):?([^0-9A-Za-z_-]?)", "/%1%2")

  if sep == "/" then
    -- Replace remaining backslashes with forward slashes.
    posix_path = posix_path:gsub("\\", "/")
  else
    -- Replace remaining forward slashes with backslashes.
    posix_path = posix_path:gsub("/", "\\")
  end

  -- For bash.exe (nvim shell) it is better to use forward slashes
  -- cause backslashes must to be escaped. Need to come up with something
  -- cause nvim for windows (even clang64 binary) prefers windows-style paths (but works with forward slashes as well?).
  -- UPD. "set shellslash" makes the trick by converting backslashes to forward slashes in shell invocations.
  --posix_path = posix_path:gsub("\\", "/")

  -- Drive letter to upper case
  if posix_path:find("^[a-z]:") then
    posix_path = posix_path:sub(1, 1):upper() .. posix_path:sub(2)
  end

  --vim.notify("posix_to_windows will return " .. posix_path, vim.log.levels.WARN)

  return posix_path
end

function M.windows_to_posix(windows_path)
  -- Sanity checks.
  if not windows_path or type(windows_path) ~= "string" or #windows_path == 0 or not windows_path:find("^[A-Za-z]:")
    or not M.msys2_root or #M.msys2_root == 0 then
    return windows_path
  end

  local prefix_changed = false

  windows_path = windows_path:gsub("/", "\\")

  if not prefix_changed and windows_path:find("^" .. M.msys2_root) then
    windows_path = windows_path:gsub("^" .. M.msys2_root, "")
    prefix_changed = true
  end

  if not prefix_changed and windows_path:find("^[A-Za-z]:") then
    windows_path = windows_path:gsub("^([A-Za-z]):", "/%1")
    prefix_changed = true
  end

  windows_path = windows_path:gsub("\\", "/")

  return windows_path
end

return M
