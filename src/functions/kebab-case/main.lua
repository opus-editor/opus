-- Each line's words, small letters joined by dashes. opus.words splits
-- identifiers (fooBar, HTTPServer) and sentences alike.
local function kebab (line)
  local words = {}
  for i, word in ipairs (opus.words (line)) do
    words[i] = opus.lower (word)
  end
  return table.concat (words, "-")
end

function transform (input)
  local out = {}
  for i, segment in ipairs (input.segments) do
    out[i] = segment.text:gsub ("[^\n]+", kebab)
  end
  return out
end
