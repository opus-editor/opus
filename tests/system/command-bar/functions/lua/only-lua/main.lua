function transform (input)
  local out = {}
  for i, segment in ipairs (input.segments) do
    out[i] = segment.text
  end
  return out
end
