-- Every letter in capitals, accents included (opus.upper goes through GLib).
function transform (input)
  local out = {}
  for i, segment in ipairs (input.segments) do
    out[i] = opus.upper (segment.text)
  end
  return out
end
