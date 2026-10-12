function transform (input)
  local out = {}
  for i, segment in ipairs (input.segments) do
    out[i] = opus.upper (segment.text) .. "!"
  end
  return out
end
