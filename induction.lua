--------------------------------------------------------------------------
-- Induction Matrix Monitor -- CC:Tweaked + Mekanism v10.1+
--
-- Live progress-bar GUI for a Mekanism Induction Matrix: stored energy,
-- total capacity, charge %, input/output rates and a time-to-full/empty
-- estimate.  Units auto-scale (FE, kFE, MFE, GFE, TFE, PFE ...) and every
-- value -- including capacity -- is re-read each refresh, so adding more
-- Induction Cells or Providers shows up on screen immediately.
--
-- Setup:
--   * Place the computer against the matrix's Induction Port, or link
--     them with wired modems + network cable (right-click each modem).
--   * Optionally attach a monitor (any size; advanced looks best).
--     The program draws on the terminal and every attached monitor.
--   * Run:  induction  [monitor name]     e.g.  induction monitor_0
--   * Press Q (or hold Ctrl+T) to quit.
--
-- Note on units: Mekanism always reports energy to computers in Joules,
-- no matter which display unit its own GUI uses.  This program converts
-- to Forge Energy with Mekanism's default rate of 2.5 J per FE.  If your
-- pack changes "energyConversionRate" in mekanism/general.toml, mirror
-- that value below -- or set UNIT = "J" to show raw Joules.
--------------------------------------------------------------------------

-- ============================ configuration =============================
local REFRESH       = 1      -- seconds between screen updates
local UNIT          = "FE"   -- "FE" or "J"
local JOULES_PER_FE = 2.5    -- Mekanism's energyConversionRate config value
local MONITOR_NAME  = nil    -- e.g. "monitor_0" or "right"; nil = use all
local TITLE         = "Induction Matrix"
-- =========================================================================

local PERIPHERAL_TYPE = "inductionPort"
local PREFIXES = { "", "k", "M", "G", "T", "P", "E" }
local SPINNER  = { "|", "/", "-", "\\" }

local args = { ... }
if args[1] then MONITOR_NAME = args[1] end

-- ----------------------------- formatting -------------------------------

-- Joules in, human string out: 1234567890 J -> "493.83 MFE"
local function formatEnergy(joules, perTick)
  local value = joules
  if UNIT == "FE" then value = value / JOULES_PER_FE end
  local i = 1
  while math.abs(value) >= 1000 and i < #PREFIXES do
    value = value / 1000
    i = i + 1
  end
  local decimals = 2
  if i == 1 then
    decimals = 0
  elseif math.abs(value) >= 100 then
    decimals = 1
  end
  return string.format("%." .. decimals .. "f %s%s%s",
    value, PREFIXES[i], UNIT, perTick and "/t" or "")
end

local function formatEta(seconds)
  if seconds ~= seconds or seconds >= 365 * 86400 then return "over a year" end
  seconds = math.max(0, seconds)
  local s = math.floor(seconds + 0.5)
  local days = math.floor(s / 86400)
  local hrs  = math.floor(s % 86400 / 3600)
  local mins = math.floor(s % 3600 / 60)
  if days > 0 then return string.format("%dd %dh", days, hrs) end
  if hrs  > 0 then return string.format("%dh %dm", hrs, mins) end
  if mins > 0 then return string.format("%dm %ds", mins, s % 60) end
  return string.format("%ds", s % 60)
end

-- --------------------------- matrix reading -----------------------------

local function tryCall(fn)
  if not fn then return nil end
  local ok, value = pcall(fn)
  if ok then return value end
end

-- Returns a stats table, or nil + "unformed"/"error".
local function readStats(port)
  if port.isFormed then
    local ok, formed = pcall(port.isFormed)
    if ok and formed == false then return nil, "unformed" end
  end
  local ok, stats = pcall(function()
    return {
      energy   = port.getEnergy(),      -- Joules
      capacity = port.getMaxEnergy(),   -- Joules
      input    = port.getLastInput(),   -- Joules/tick
      output   = port.getLastOutput(),  -- Joules/tick
    }
  end)
  if not ok then
    if type(stats) == "string" and stats:lower():find("formed") then
      return nil, "unformed"
    end
    return nil, "error"
  end
  stats.cells     = tryCall(port.getInstalledCells)
  stats.providers = tryCall(port.getInstalledProviders)
  return stats
end

-- ------------------------------ displays --------------------------------

local displays = {}

-- Pick the largest text scale that still fits the full layout.
local function autoScale(mon)
  for scale = 5, 0.5, -0.5 do
    mon.setTextScale(scale)
    local w, h = mon.getSize()
    if w >= 30 and h >= 13 then return end
  end
end

-- `initial` controls whether a missing named monitor is a hard error (useful
-- at startup, to catch typos) or just skipped (so a later disconnect of that
-- monitor doesn't take the whole program down; it'll pick it back up once
-- reattached).
local function setupDisplays(initial)
  displays = { { dev = term.current(), isMonitor = false } }
  local monitors
  if MONITOR_NAME then
    local mon = peripheral.wrap(MONITOR_NAME)
    if not mon or not mon.setTextScale then
      if initial then
        error(("No monitor called %q is attached"):format(MONITOR_NAME), 0)
      end
      monitors = {}
    else
      monitors = { mon }
    end
  else
    monitors = { peripheral.find("monitor") }
  end
  for _, mon in ipairs(monitors) do
    autoScale(mon)
    displays[#displays + 1] = { dev = mon, isMonitor = true }
  end
  for _, d in ipairs(displays) do
    d.dev.setCursorBlink(false)
  end
end

-- ------------------------------ painting --------------------------------

local GRAYSCALE_OK = {
  [colors.white] = true, [colors.black] = true,
  [colors.gray] = true, [colors.lightGray] = true,
}

local function safeColor(d, c, fallback)
  c = c or fallback
  if c == fallback or d.isColor() or GRAYSCALE_OK[c] then return c end
  return fallback
end

-- Draw one full row from colored segments; pads to the screen edge so no
-- clear() is needed between frames (avoids flicker). `rowBg` is the
-- background for any part of the row a segment doesn't set explicitly
-- (e.g. the padding around a centered title), so a row can read as a
-- solid-colored banner instead of colored text floating on black.
local function paint(d, y, w, segs, center, rowBg)
  segs = segs or {}
  d.setCursorPos(1, y)
  local remaining = w
  local function put(text, fg, bg)
    if remaining <= 0 or #text == 0 then return end
    if #text > remaining then text = text:sub(1, remaining) end
    d.setTextColor(safeColor(d, fg, colors.white))
    d.setBackgroundColor(safeColor(d, bg or rowBg, colors.black))
    d.write(text)
    remaining = remaining - #text
  end
  if center then
    local total = 0
    for _, s in ipairs(segs) do total = total + #s[1] end
    if total < w then put((" "):rep(math.floor((w - total) / 2))) end
  end
  for _, s in ipairs(segs) do put(s[1], s.fg, s.bg) end
  put((" "):rep(remaining))
end

local function drawBar(d, y, w, frac, withLabel)
  frac = math.max(0, math.min(1, frac))
  local x0 = w >= 8 and 2 or 1          -- side margins on all but tiny screens
  local width = w - (x0 - 1) * 2
  local filled = math.floor(frac * width + 0.5)
  local label = ""
  if withLabel then
    label = string.format(" %.1f%% ", frac * 100)
    if #label > width then label = string.format("%.0f%%", frac * 100) end
  end
  local from = math.floor((width - #label) / 2) + 1
  local isC = d.isColor()
  local chars = {}
  for i = 1, width do
    local j = i - from + 1
    if j >= 1 and j <= #label then
      chars[i] = label:sub(j, j)
    elseif isC then
      chars[i] = " "
    else
      chars[i] = i <= filled and "=" or "-"
    end
  end
  d.setCursorPos(1, y)
  d.setTextColor(colors.white)
  d.setBackgroundColor(colors.black)
  d.write((" "):rep(x0 - 1))
  if isC then
    local fillC = frac < 0.15 and "e" or frac < 0.40 and "1" or "d"
    d.blit(table.concat(chars), ("0"):rep(width),
      fillC:rep(filled) .. ("7"):rep(width - filled))
    d.setBackgroundColor(colors.black)
  else
    d.write(table.concat(chars))
  end
  d.write((" "):rep(x0 - 1))
end

-- ------------------------------- layout ---------------------------------

local function kvRow(w, label, value, vcolor)
  local gap = w - 2 - #label - #value
  if gap >= 2 then
    return { segs = {
      { " " .. label, fg = colors.lightGray },
      { (" "):rep(gap - 1) },
      { value, fg = vcolor },
      { " " },
    } }
  end
  return { segs = { { " " }, { value, fg = vcolor } } }
end

-- Banner color reflects overall health at a glance: blue while everything
-- is fine, orange for an incomplete multiblock, red for anything wrong.
local STATUS_COLOR = {
  ok       = colors.blue,
  unformed = colors.orange,
  error    = colors.red,
  noport   = colors.red,
}

local function buildRows(view, w, h)
  local rows = {}
  local function add(r) rows[#rows + 1] = r end
  local function text(str, color, center, bg)
    add({ segs = { { str, fg = color, bg = bg } }, center = center, bg = bg })
  end
  local roomy = h >= 15
  local statusColor = STATUS_COLOR[view.state] or colors.blue

  text(TITLE, colors.white, true, statusColor)
  text(("\140"):rep(w), colors.gray)

  if view.state == "ok" then
    local s = view.stats
    local frac = s.capacity > 0 and s.energy / s.capacity or 0
    if roomy then add(false) end
    add(kvRow(w, "Stored", formatEnergy(s.energy)))
    add(kvRow(w, "Capacity", formatEnergy(s.capacity)))
    if roomy then add(false) end
    local thick = h >= 17
    if thick then add({ bar = frac }) end
    add({ bar = frac, label = true })
    if thick then add({ bar = frac }) end
    if roomy then add(false) end
    if h >= 11 then
      local net = s.input - s.output
      add(kvRow(w, "Input", formatEnergy(s.input, true),
        s.input > 0 and colors.lime or nil))
      add(kvRow(w, "Output", formatEnergy(s.output, true),
        s.output > 0 and colors.orange or nil))
      add(kvRow(w, "Net", (net > 0 and "+" or "") .. formatEnergy(net, true),
        net > 0 and colors.lime or net < 0 and colors.red or colors.lightGray))
      if h >= 13 then
        if math.abs(net) < 1e-9 then
          add(kvRow(w, "Trend", "steady", colors.cyan))
        elseif net > 0 then
          add(kvRow(w, "Full in", formatEta((s.capacity - s.energy) / net / 20), colors.lime))
        else
          add(kvRow(w, "Empty in", formatEta(s.energy / -net / 20), colors.orange))
        end
      end
    end
    if h >= 14 and s.cells then
      if roomy then add(false) end
      add({ segs = {
        { string.format("Cells: %d", s.cells), fg = colors.cyan },
        { "   " },
        { string.format("Providers: %d", s.providers or 0), fg = colors.purple },
      }, center = true })
    end
  elseif view.state == "unformed" then
    local wide = w >= 35
    add(false)
    text("Matrix is not formed!", colors.orange, true)
    add(false)
    text(wide and "Finish building the multiblock;" or "Finish the multiblock;",
      colors.lightGray, true)
    text(wide and "the display resumes automatically." or "display will resume.",
      colors.lightGray, true)
  elseif view.state == "error" then
    local wide = w >= 35
    add(false)
    text("Read error", colors.red, true)
    add(false)
    text(wide and "The Induction Port returned an" or "Unexpected error;",
      colors.lightGray, true)
    text(wide and "unexpected error; retrying." or "retrying...",
      colors.lightGray, true)
  else -- no port found
    local wide = w >= 35
    add(false)
    text(wide and "No Induction Port found" or "No Induction Port",
      colors.red, true)
    add(false)
    text(wide and "Attach this computer to your" or "Attach this computer",
      colors.lightGray, true)
    text(wide and "matrix's Induction Port, directly" or "to an Induction Port",
      colors.lightGray, true)
    text(wide and "or via wired modems." or "or use wired modems.",
      colors.lightGray, true)
    add(false)
    text("Searching...", colors.gray, true)
  end
  return rows
end

local function render(d, view, spin, isMonitor)
  local w, h = d.getSize()
  local rows = buildRows(view, w, h)
  local offset = math.floor(math.max(0, h - #rows) / 2)
  for y = 1, h do
    local row = rows[y - offset]
    if not row then
      paint(d, y, w, nil)
    elseif row.bar then
      drawBar(d, y, w, row.bar, row.label)
    else
      paint(d, y, w, row.segs, row.center, row.bg)
    end
  end
  if not isMonitor and h >= 8 then
    local hint = "Q = quit"
    paint(d, h, w, { { (" "):rep(w - #hint - 1) }, { hint, fg = colors.gray } })
  end
  d.setCursorPos(w, 1)
  d.setTextColor(safeColor(d, colors.gray, colors.white))
  d.setBackgroundColor(colors.black)
  d.write(SPINNER[spin])
end

-- ------------------------------ main loop -------------------------------

local function main()
  setupDisplays(true)
  local port, view
  local spin = 1
  local timer = os.startTimer(0)
  while true do
    local event, p1 = os.pullEventRaw()
    if event == "terminate" then
      return
    elseif event == "key" and p1 == keys.q then
      return
    elseif event == "timer" and p1 == timer then
      if not port then port = peripheral.find(PERIPHERAL_TYPE) end
      if not port then
        view = { state = "noport" }
      else
        local stats, why = readStats(port)
        if stats then
          view = { state = "ok", stats = stats }
        elseif why == "unformed" then
          view = { state = "unformed" }
        else
          port = nil                    -- peripheral may be stale; rescan next tick
          view = { state = "error" }
        end
      end
      for _, d in ipairs(displays) do
        render(d.dev, view, spin, d.isMonitor)
      end
      spin = spin % #SPINNER + 1
      timer = os.startTimer(REFRESH)
    elseif event == "monitor_resize" or event == "peripheral"
        or event == "peripheral_detach" or event == "term_resize" then
      setupDisplays()                   -- re-detect monitors and rescale
      port = nil
      timer = os.startTimer(0.05)
    end
  end
end

local ok, err = pcall(main)
for _, d in ipairs(displays) do
  pcall(function()
    d.dev.setTextColor(colors.white)
    d.dev.setBackgroundColor(colors.black)
    d.dev.clear()
    d.dev.setCursorPos(1, 1)
  end)
end
if not ok then error(err, 0) end
print("Induction Matrix monitor stopped.")
