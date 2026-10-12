-- Every letter in small letters, accents included (opus.lower goes through GLib).
function transform (input)
  local out = {}
  for i, segment in ipairs (input.segments) do
    out[i] = opus.lower (segment.text)
  end
  return out
end
