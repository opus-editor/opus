-- Each line's words, every one capitalized and run together.
local function pascal (line)
  local words = {}
  for i, word in ipairs (opus.words (line)) do
    words[i] = opus.capitalize (word)
  end
  return table.concat (words)
end

function transform (input)
  local out = {}
  for i, segment in ipairs (input.segments) do
    out[i] = segment.text:gsub ("[^\n]+", pascal)
  end
  return out
end
