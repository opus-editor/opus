-- Each line's words, small letters joined by underscores.
local function snake (line)
  local words = {}
  for i, word in ipairs (opus.words (line)) do
    words[i] = opus.lower (word)
  end
  return table.concat (words, "_")
end

function transform (input)
  local out = {}
  for i, segment in ipairs (input.segments) do
    out[i] = segment.text:gsub ("[^\n]+", snake)
  end
  return out
end
