local math3d = {}

function math3d.perspective(fov, aspect, near, far)
  local f = 1.0 / math.tan(fov / 2)
  local nf = 1 / (near - far)

  return {
    f / aspect, 0, 0, 0,
    0, f, 0, 0,
    0, 0, (far + near) * nf, -1,
    0, 0, (2 * far * near) * nf, 0
  }
end

function math3d.lookAt(eye, center, up)
  local fx = center[1] - eye[1]
  local fy = center[2] - eye[2]
  local fz = center[3] - eye[3]
  local rlf = 1 / math.sqrt(fx * fx + fy * fy + fz * fz)
  fx, fy, fz = fx * rlf, fy * rlf, fz * rlf

  local sx = fy * up[3] - fz * up[2]
  local sy = fz * up[1] - fx * up[3]
  local sz = fx * up[2] - fy * up[1]
  local rls = 1 / math.sqrt(sx * sx + sy * sy + sz * sz)
  sx, sy, sz = sx * rls, sy * rls, sz * rls

  local ux = sy * fz - sz * fy
  local uy = sz * fx - sx * fz
  local uz = sx * fy - sy * fx

  return {
    sx, ux, -fx, 0,
    sy, uy, -fy, 0,
    sz, uz, -fz, 0,
    -(sx * eye[1] + sy * eye[2] + sz * eye[3]),
    -(ux * eye[1] + uy * eye[2] + uz * eye[3]),
    fx * eye[1] + fy * eye[2] + fz * eye[3],
    1
  }
end

function math3d.ortho(left, right, bottom, top, near, far)
  return {
    2 / (right - left), 0, 0, 0,
    0, 2 / (top - bottom), 0, 0,
    0, 0, -2 / (far - near), 0,
    -(right + left) / (right - left),
    -(top + bottom) / (top - bottom),
    -(far + near) / (far - near),
    1
  }
end

function math3d.multiplyMat4(a, b)
  local result = {}
  for col = 0, 3 do
    for row = 0, 3 do
      local value = 0
      for k = 0, 3 do
        value = value + a[k * 4 + row + 1] * b[col * 4 + k + 1]
      end
      result[col * 4 + row + 1] = value
    end
  end
  return result
end

function math3d.frustumPlanes(matrix)
  local function plane(a, b, c, d)
    local length = math.sqrt(a * a + b * b + c * c)
    if length == 0 then
      return {a = 0.0, b = 1.0, c = 0.0, d = 0.0}
    end
    return {a = a / length, b = b / length, c = c / length, d = d / length}
  end

  local r1 = {matrix[1], matrix[5], matrix[9], matrix[13]}
  local r2 = {matrix[2], matrix[6], matrix[10], matrix[14]}
  local r3 = {matrix[3], matrix[7], matrix[11], matrix[15]}
  local r4 = {matrix[4], matrix[8], matrix[12], matrix[16]}

  return {
    plane(r4[1] + r1[1], r4[2] + r1[2], r4[3] + r1[3], r4[4] + r1[4]),
    plane(r4[1] - r1[1], r4[2] - r1[2], r4[3] - r1[3], r4[4] - r1[4]),
    plane(r4[1] + r2[1], r4[2] + r2[2], r4[3] + r2[3], r4[4] + r2[4]),
    plane(r4[1] - r2[1], r4[2] - r2[2], r4[3] - r2[3], r4[4] - r2[4]),
    plane(r4[1] + r3[1], r4[2] + r3[2], r4[3] + r3[3], r4[4] + r3[4]),
    plane(r4[1] - r3[1], r4[2] - r3[2], r4[3] - r3[3], r4[4] - r3[4])
  }
end

function math3d.aabbInFrustum(planes, bounds)
  for i = 1, #planes do
    local p = planes[i]
    local x = p.a >= 0 and bounds.maxX or bounds.minX
    local y = p.b >= 0 and bounds.maxY or bounds.minY
    local z = p.c >= 0 and bounds.maxZ or bounds.minZ
    if p.a * x + p.b * y + p.c * z + p.d < 0 then
      return false
    end
  end
  return true
end

function math3d.cross(a, b)
  return {
    a[2] * b[3] - a[3] * b[2],
    a[3] * b[1] - a[1] * b[3],
    a[1] * b[2] - a[2] * b[1]
  }
end

function math3d.dot(a, b)
  return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
end

function math3d.length(v)
  return math.sqrt(math3d.dot(v, v))
end

function math3d.add(a, b)
  return {a[1] + b[1], a[2] + b[2], a[3] + b[3]}
end

function math3d.subtract(a, b)
  return {a[1] - b[1], a[2] - b[2], a[3] - b[3]}
end

function math3d.scale(v, amount)
  return {v[1] * amount, v[2] * amount, v[3] * amount}
end

function math3d.projectOnPlane(v, normal)
  local amount = math3d.dot(v, normal)
  return {v[1] - normal[1] * amount, v[2] - normal[2] * amount, v[3] - normal[3] * amount}
end

function math3d.normalize(v)
  local length = math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3])
  if length == 0 then
    return {0.0, 1.0, 0.0}
  end

  return {v[1] / length, v[2] / length, v[3] / length}
end

function math3d.clamp(value, minValue, maxValue)
  return math.max(minValue, math.min(maxValue, value))
end

function math3d.smoothstep(edge0, edge1, value)
  local t = math3d.clamp((value - edge0) / (edge1 - edge0), 0.0, 1.0)
  return t * t * (3.0 - 2.0 * t)
end

function math3d.mix(a, b, amount)
  return a + (b - a) * amount
end

function math3d.mixColor(a, b, amount)
  return {
    math3d.mix(a[1], b[1], amount),
    math3d.mix(a[2], b[2], amount),
    math3d.mix(a[3], b[3], amount)
  }
end

return math3d
