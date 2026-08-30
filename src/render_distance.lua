local renderDistance = {}

renderDistance.MIN_CHUNKS = 4
renderDistance.MAX_CHUNKS = 128
renderDistance.CHUNK_SIZE = 16

function renderDistance.clamp(value, fallback)
  local numeric = tonumber(value)
  if numeric == nil then numeric = tonumber(fallback) or renderDistance.MIN_CHUNKS end
  return math.max(renderDistance.MIN_CHUNKS,
    math.min(renderDistance.MAX_CHUNKS, math.floor(numeric + 0.5)))
end

function renderDistance.fullDetailRadius(value, maximum)
  return math.min(math.max(1, math.floor(tonumber(maximum) or 1)),
    renderDistance.clamp(value))
end

-- End the aerial fade just inside the outermost chunk. Besides hiding the LOD
-- boundary, this makes the menu setting visibly affect the scene instead of
-- every value sharing the old fixed 360-block fog horizon.
function renderDistance.fogRange(value, authoredStart)
  local chunks = renderDistance.clamp(value)
  local fogEnd = math.max(56.0, chunks * renderDistance.CHUNK_SIZE - 24.0)
  local fogStart = math.min(tonumber(authoredStart) or 48.0, fogEnd - 16.0)
  return fogStart, fogEnd
end

return renderDistance
