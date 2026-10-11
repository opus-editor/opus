-- Locale matching: pick the best locale for an Accept-Language header.
local Locale = {}
Locale.__index = Locale

local DEFAULT_CODE = "en"
local MAX_TAGS = 8

function Locale.new(code, name)
  local self = setmetatable({}, Locale)
  self.code = code
  self.name = name
  return self
end

function Locale:matches(tag)
  return self.code:lower() == tag:lower()
end

local function parse_tags(header)
  local tags = {}
  for raw in string.gmatch(header, "[^,]+") do
    local tag = raw:match("^%s*([^;]+)")
    if tag and #tags < MAX_TAGS then
      tags[#tags + 1] = tag
    end
  end
  return tags
end

--- Returns the first requested locale we know, or the default one.
-- @param locales table of Locale
-- @param header the raw Accept-Language value
function Locale.requested(locales, header)
  for _, tag in ipairs(parse_tags(header or "")) do
    for i = 1, #locales do
      if locales[i]:matches(tag) then
        return locales[i], true
      end
    end
  end
  repeat
    local fallback = locales[1]
    if fallback ~= nil and fallback.code == DEFAULT_CODE then
      return fallback, false
    end
  until true
  return nil, false
end

local locales = { Locale.new("en", "English"), Locale.new("pt-BR", "Português") }
local found, exact = Locale.requested(locales, "pt-BR,pt;q=0.9,en;q=0.8")
print(("%s (%s)"):format(found.name, exact and "exact" or "fallback"))
