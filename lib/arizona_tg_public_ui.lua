--[[
  Arizona TG Notify UI — premium glass admin (PB2 structure)
]]

local M = {}

-- mimgui_blur — лениво (при первом draw), иначе require вместе с MCR валит клиент
local blur = nil
local blur_tried = false
local function ensure_blur()
  if blur_tried then return blur end
  blur_tried = true
  local ok, mod = pcall(require, 'mimgui_blur')
  if ok then blur = mod end
  return blur
end

local anim = {
  toggles = {},
  hover = {},
  press = {},
  nav_slide = 0,
  nav_target = 0,
  tab_fade = 1,
  tab_was = nil,
  open = 0,
  closing = false,
  win_phase = 'idle', -- open | idle | close
  win_t = 0,
  tab_clock = 0,
  appear_i = 0,
  ev_was_loading = false,
  ev_show_done = false, -- false: только непроведённые (без повторов)
  org_day = 0, -- 0 сегодня, 1 вчера
  stagger = true,
  focus_pm = false,
}

-- зажал навигацию → водишь вверх/вниз и переключаешь вкладки
local nav_drag = {
  holding = false,
  slots = {},
}

-- ресайз окна за правый нижний угол
local win_resize = {
  active = false,
  start_mx = 0,
  start_my = 0,
  start_w = 0,
  start_h = 0,
  lock_x = 0,
  lock_y = 0,
}

local function u32(imgui, col)
  return imgui.ColorConvertFloat4ToU32(col)
end

local function clamp(x, a, b)
  if x < a then return a end
  if x > b then return b end
  return x
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function ease_out(t)
  t = clamp(t, 0, 1)
  return 1 - (1 - t) * (1 - t)
end

local function ease_out_back(t)
  t = clamp(t, 0, 1)
  local c = 1.2
  return 1 + (c + 1) * (t - 1) ^ 3 + c * (t - 1) ^ 2
end

-- staggered enter: плавный cascade, тени облегчены только на время входа
local function tab_appear(i)
  i = math.max(1, tonumber(i) or 1)
  if i > 10 then i = 10 end
  local delay = (i - 1) * 0.034
  local a = ease_out(clamp((anim.tab_clock - delay) / 0.34, 0, 1))
  -- только горизонтальный сдвиг: вертикальный dy давал визуальный «тык»
  return a, (1 - a) * 14, 0
end

local function next_appear()
  if anim.stagger == false then return 1, 0, 0 end
  anim.appear_i = (anim.appear_i or 0) + 1
  return tab_appear(anim.appear_i)
end

local function reset_tab_anim()
  anim.tab_clock = 0
  anim.appear_i = 0
end

local function toward(store, key, target, speed, dt)
  local v = store[key]
  if v == nil then store[key] = target; return target end
  v = lerp(v, target, clamp(speed * (dt or 0.016), 0, 1))
  if math.abs(v - target) < 0.003 then v = target end
  store[key] = v
  return v
end

local function with_a(imgui, c, a)
  return imgui.ImVec4(c.x, c.y, c.z, a)
end

local function fade_a(imgui, c, a)
  return with_a(imgui, c, (c.w or 1) * clamp(a, 0, 1))
end

local function mix(imgui, a, b, t)
  return imgui.ImVec4(
    lerp(a.x, b.x, t), lerp(a.y, b.y, t), lerp(a.z, b.z, t),
    lerp(a.w or 1, b.w or 1, t)
  )
end

local function lum(c)
  return 0.299 * c.x + 0.587 * c.y + 0.114 * c.z
end

-- soft stroke color that never looks like chalk-white outlines
local function stroke(imgui, C, a)
  local a = a or 0.14
  if lum(C.accent) > 0.72 then
    return with_a(imgui, C.soft, a * 0.55)
  end
  return with_a(imgui, C.accent, a)
end

local function nav_y_follow(my)
  local slots = nav_drag.slots
  if #slots == 0 then return nil end
  local first, last = slots[1], slots[#slots]
  if my <= first.cy then return first.y end
  if my >= last.cy then return last.y end
  for i = 1, #slots - 1 do
    local a, b = slots[i], slots[i + 1]
    if my >= a.cy and my <= b.cy then
      local t = (my - a.cy) / math.max(b.cy - a.cy, 1)
      return lerp(a.y, b.y, t)
    end
  end
  return first.y
end

local function draw_nav_pill(P, y)
  if not y or y <= 0 then return end
  local imgui, C = P.imgui, P.C
  local dl = imgui.GetWindowDrawList()
  local x = imgui.GetWindowPos().x + 10
  local w = P.SIDE_W - 20
  local h = 40
  local fill = lum(C.accent) > 0.72 and with_a(imgui, C.soft, 0.07) or with_a(imgui, C.accent, 0.14)
  dl:AddRectFilled(imgui.ImVec2(x, y), imgui.ImVec2(x + w, y + h), u32(imgui, fill), 12)
  dl:AddRect(imgui.ImVec2(x, y), imgui.ImVec2(x + w, y + h), u32(imgui, stroke(imgui, C, 0.22)), 12, imgui.DrawCornerFlags.All, 1)
  dl:AddRectFilled(
    imgui.ImVec2(x + 2, y + 11), imgui.ImVec2(x + 5, y + h - 11),
    u32(imgui, C.accent), 2
  )
end

-- ===================== ICONS =====================

local function icon_home(dl, imgui, cx, cy, col, s)
  s = s or 6.5
  dl:AddTriangleFilled(
    imgui.ImVec2(cx, cy - s * 0.95),
    imgui.ImVec2(cx - s, cy - 0.2),
    imgui.ImVec2(cx + s, cy - 0.2),
    col
  )
  dl:AddRectFilled(
    imgui.ImVec2(cx - s * 0.72, cy - 0.2),
    imgui.ImVec2(cx + s * 0.72, cy + s * 0.95),
    col, 1.5
  )
  dl:AddRectFilled(
    imgui.ImVec2(cx - s * 0.22, cy + s * 0.25),
    imgui.ImVec2(cx + s * 0.22, cy + s * 0.95),
    u32(imgui, imgui.ImVec4(0, 0, 0, 0.35)), 1
  )
end

local function icon_clips(dl, imgui, cx, cy, col, s)
  s = s or 6.5
  dl:AddRectFilled(
    imgui.ImVec2(cx - s, cy - s * 0.7),
    imgui.ImVec2(cx + s * 0.25, cy + s * 0.7),
    col, 2.2
  )
  dl:AddTriangleFilled(
    imgui.ImVec2(cx + s * 0.4, cy - s * 0.45),
    imgui.ImVec2(cx + s * 0.4, cy + s * 0.45),
    imgui.ImVec2(cx + s * 1.15, cy),
    col
  )
end

local function icon_themes(dl, imgui, cx, cy, col, s)
  s = s or 6.5
  dl:AddCircleFilled(imgui.ImVec2(cx, cy), s * 0.95, col, 18)
  local hole = u32(imgui, imgui.ImVec4(0, 0, 0, 0.45))
  dl:AddCircleFilled(imgui.ImVec2(cx + s * 0.15, cy - s * 0.1), s * 0.42, hole, 14)
end

local function icon_gear(dl, imgui, cx, cy, col, s)
  s = s or 6.5
  dl:AddCircleFilled(imgui.ImVec2(cx, cy), s * 0.72, col, 16)
  for i = 0, 5 do
    local a = i * (math.pi / 3) + 0.2
    local x = cx + math.cos(a) * s * 0.95
    local y = cy + math.sin(a) * s * 0.95
    dl:AddCircleFilled(imgui.ImVec2(x, y), s * 0.28, col, 8)
  end
  dl:AddCircleFilled(imgui.ImVec2(cx, cy), s * 0.32, u32(imgui, imgui.ImVec4(0, 0, 0, 0.45)), 12)
end

local function icon_x(dl, imgui, cx, cy, col, s)
  s = s or 4.5
  dl:AddLine(imgui.ImVec2(cx - s, cy - s), imgui.ImVec2(cx + s, cy + s), col, 2.1)
  dl:AddLine(imgui.ImVec2(cx + s, cy - s), imgui.ImVec2(cx - s, cy + s), col, 2.1)
end

local function icon_utils(dl, imgui, cx, cy, col, s)
  s = s or 6.5
  -- два «игрока»
  dl:AddCircleFilled(imgui.ImVec2(cx - s * 0.45, cy - s * 0.35), s * 0.38, col, 12)
  dl:AddCircleFilled(imgui.ImVec2(cx + s * 0.55, cy - s * 0.15), s * 0.32, col, 12)
  dl:AddCircleFilled(imgui.ImVec2(cx - s * 0.45, cy + s * 0.55), s * 0.55, col, 14)
  dl:AddCircleFilled(imgui.ImVec2(cx + s * 0.55, cy + s * 0.65), s * 0.48, col, 14)
end

local function icon_events(dl, imgui, cx, cy, col, s)
  s = s or 6.5
  dl:AddRectFilled(imgui.ImVec2(cx - s, cy - s * 0.75), imgui.ImVec2(cx + s, cy + s * 0.9), col, 2.2)
  dl:AddRectFilled(
    imgui.ImVec2(cx - s + 2, cy - s * 0.35),
    imgui.ImVec2(cx + s - 2, cy + s * 0.7),
    u32(imgui, imgui.ImVec4(0, 0, 0, 0.35)), 1.5
  )
  dl:AddRectFilled(imgui.ImVec2(cx - s * 0.55, cy - s * 1.05), imgui.ImVec2(cx - s * 0.25, cy - s * 0.55), col, 1)
  dl:AddRectFilled(imgui.ImVec2(cx + s * 0.25, cy - s * 1.05), imgui.ImVec2(cx + s * 0.55, cy - s * 0.55), col, 1)
end

local function icon_orgs(dl, imgui, cx, cy, col, s)
  s = s or 6.5
  -- следящий + мини-счётчик
  dl:AddCircleFilled(imgui.ImVec2(cx - s * 0.2, cy - s * 0.4), s * 0.4, col, 12)
  dl:AddCircleFilled(imgui.ImVec2(cx - s * 0.2, cy + s * 0.55), s * 0.6, col, 14)
  local bx, by, br = cx + s * 0.65, cy - s * 0.35, s * 0.42
  dl:AddCircleFilled(imgui.ImVec2(bx, by), br, col, 12)
  dl:AddLine(imgui.ImVec2(bx - br * 0.45, by), imgui.ImVec2(bx + br * 0.45, by), u32(imgui, imgui.ImVec4(0, 0, 0, 0.45)), 1.5)
  dl:AddLine(imgui.ImVec2(bx, by - br * 0.45), imgui.ImVec2(bx, by + br * 0.45), u32(imgui, imgui.ImVec4(0, 0, 0, 0.45)), 1.5)
end

local function icon_help(dl, imgui, cx, cy, col, s)
  s = s or 6.5
  dl:AddCircle(imgui.ImVec2(cx, cy), s * 0.95, col, 16, 1.6)
  dl:AddCircleFilled(imgui.ImVec2(cx, cy + s * 0.55), s * 0.14, col, 8)
  dl:AddLine(imgui.ImVec2(cx, cy - s * 0.05), imgui.ImVec2(cx, cy + s * 0.25), col, 1.7)
  dl:AddCircle(imgui.ImVec2(cx, cy - s * 0.38), s * 0.28, col, 12, 1.6)
end

local NAV = {
  { tab = 1, label = 'Главная', icon = icon_home },
  { tab = 5, label = 'Утилиты', icon = icon_utils },
  { tab = 6, label = 'Мероприят.', icon = icon_events },
  { tab = 7, label = 'Следящие', icon = icon_orgs },
  { tab = 8, label = 'Помощь', icon = icon_help },
  { tab = 3, label = 'Клипы', icon = icon_clips },
  { tab = 2, label = 'Настройки', icon = icon_gear },
}

local function switch_nav_tab(P, tab)
  if P.get_tab() == tab then return end
  P.set_tab(tab)
  anim.tab_fade = 0
  reset_tab_anim()
  if tab == 2 then P.sync_ui_from_cfg() end
  if tab == 3 then P.sync_clips_ui() end
  -- без HTTP на клике: requests блокирует весь клиент
end

local function nav_tab_at_y(my)
  local slots = nav_drag.slots
  if #slots == 0 then return nil end
  -- сначала точное попадание в слот
  for i = 1, #slots do
    local s = slots[i]
    if my >= s.y and my < s.y + s.h then
      return s.tab
    end
  end
  -- иначе ближайший по центру (удобно водить между пунктами)
  local best, bestd = slots[1].tab, math.abs(my - slots[1].cy)
  for i = 2, #slots do
    local d = math.abs(my - slots[i].cy)
    if d < bestd then
      bestd = d
      best = slots[i].tab
    end
  end
  -- не прыгать, если курсор далеко от полосы навигации
  if bestd > 56 then return nil end
  return best
end

-- мягкая тень (всегда 2 слоя — без скачка при смене режима)
local function soft_shadow(dl, imgui, min, max, r, strength)
  strength = strength or 1
  if strength < 0.03 then return end
  r = r or 8
  local layers = {
    { ox = 0, oy = 1, expand = 0, a = 0.16 * strength },
    { ox = 0, oy = 4, expand = 1, a = 0.07 * strength },
  }
  for i = 1, #layers do
    local L = layers[i]
    dl:AddRectFilled(
      imgui.ImVec2(min.x + L.ox - L.expand, min.y + L.oy),
      imgui.ImVec2(max.x + L.ox + L.expand, max.y + L.oy + L.expand),
      u32(imgui, imgui.ImVec4(0, 0, 0, clamp(L.a, 0, 0.35))),
      r + L.expand
    )
  end
end

local function draw_brand_mark(dl, imgui, C, cx, cy)
  local pulse = 0.55 + 0.2 * math.sin(imgui.GetTime() * 1.6)
  local r = 15
  soft_shadow(
    dl, imgui,
    imgui.ImVec2(cx - r, cy - r), imgui.ImVec2(cx + r, cy + r),
    9, 0.9
  )
  -- soft glow
  dl:AddCircleFilled(imgui.ImVec2(cx, cy), r + 4, u32(imgui, with_a(imgui, C.accent, 0.10 * pulse)), 24)
  -- plate
  dl:AddRectFilled(
    imgui.ImVec2(cx - r, cy - r), imgui.ImVec2(cx + r, cy + r),
    u32(imgui, with_a(imgui, C.card, 0.95)), 9
  )
  dl:AddRect(
    imgui.ImVec2(cx - r, cy - r), imgui.ImVec2(cx + r, cy + r),
    u32(imgui, with_a(imgui, C.accent, 0.55)), 9, imgui.DrawCornerFlags.All, 1.4
  )
  -- stylized A (peak)
  local col = u32(imgui, C.soft)
  local ac = u32(imgui, C.accent)
  dl:AddTriangleFilled(
    imgui.ImVec2(cx, cy - 8),
    imgui.ImVec2(cx - 8, cy + 7),
    imgui.ImVec2(cx + 8, cy + 7),
    ac
  )
  dl:AddTriangleFilled(
    imgui.ImVec2(cx, cy - 4),
    imgui.ImVec2(cx - 3.2, cy + 5),
    imgui.ImVec2(cx + 3.2, cy + 5),
    u32(imgui, with_a(imgui, C.card, 1))
  )
  dl:AddRectFilled(imgui.ImVec2(cx - 4.5, cy + 1.5), imgui.ImVec2(cx + 4.5, cy + 3.2), col, 1)
end

local function draw_card(dl, imgui, C, min, max, r, hot)
  r = r or 12
  -- glass как на вкладке МП: лёгкая заливка, фон темы читается
  soft_shadow(dl, imgui, min, max, r, 0.40 + (hot or 0) * 0.20)
  local fill = with_a(imgui, C.card, C.light and 0.36 or 0.26)
  if hot and hot > 0 then
    fill = mix(imgui, fill, with_a(imgui, C.accent, 0.12), hot * 0.30)
  end
  dl:AddRectFilled(min, max, u32(imgui, fill), r)
  local inset = 1.0
  dl:AddRect(
    imgui.ImVec2(min.x + inset, min.y + inset),
    imgui.ImVec2(max.x - inset, max.y - inset),
    u32(imgui, stroke(imgui, C, 0.10 + (hot or 0) * 0.16)),
    math.max(0, r - inset), imgui.DrawCornerFlags.All, 1.0
  )
  dl:AddRectFilledMultiColor(
    imgui.ImVec2(min.x + 2, min.y + 2),
    imgui.ImVec2(max.x - 2, min.y + 14),
    u32(imgui, with_a(imgui, C.soft, 0.03)),
    u32(imgui, with_a(imgui, C.soft, 0.03)),
    u32(imgui, imgui.ImVec4(0, 0, 0, 0)),
    u32(imgui, imgui.ImVec4(0, 0, 0, 0))
  )
end

-- PB2-style value stepper (step optional)
local function setting_row(P, id, label, bref, minv, maxv, step)
  local imgui, C = P.imgui, P.C
  step = tonumber(step) or 1
  if step < 1 then step = 1 end
  local w = imgui.GetContentRegionAvail().x
  local pad = 16
  local btn = 30
  local h = 86
  local appear, slide = next_appear()
  local base = imgui.GetCursorScreenPos()
  -- рисуем со сдвигом, хитбоксы на base (без перекрывающего InvisibleButton на всю карточку)
  local min = imgui.ImVec2(base.x + slide, base.y)
  local dl = imgui.GetWindowDrawList()
  local max = imgui.ImVec2(min.x + w, min.y + h)
  draw_card(dl, imgui, C, min, max, 12, 0)

  dl:AddText(imgui.ImVec2(min.x + pad, min.y + 14), u32(imgui, fade_a(imgui, C.muted, appear)), label)

  local yb = min.y + 40
  local xl = min.x + pad
  local xr = min.x + w - pad - btn

  imgui.SetCursorScreenPos(imgui.ImVec2(base.x + pad, base.y + 40))
  if imgui.InvisibleButton(id .. '_m', imgui.ImVec2(btn, btn)) then
    local v = tonumber(bref[0]) or minv
    bref[0] = math.max(minv, v - step)
  end
  local hm = imgui.IsItemHovered()
  dl:AddRectFilled(
    imgui.ImVec2(xl, yb), imgui.ImVec2(xl + btn, yb + btn),
    u32(imgui, with_a(imgui, C.soft, (hm and 0.14 or 0.07) * appear)), 9
  )
  dl:AddRect(imgui.ImVec2(xl, yb), imgui.ImVec2(xl + btn, yb + btn), u32(imgui, fade_a(imgui, stroke(imgui, C, 0.22), appear)), 9, imgui.DrawCornerFlags.All, 1)
  dl:AddLine(imgui.ImVec2(xl + 9, yb + btn * 0.5), imgui.ImVec2(xl + btn - 9, yb + btn * 0.5), u32(imgui, fade_a(imgui, C.soft, appear)), 2)

  imgui.SetCursorScreenPos(imgui.ImVec2(base.x + w - pad - btn, base.y + 40))
  if imgui.InvisibleButton(id .. '_p', imgui.ImVec2(btn, btn)) then
    local v = tonumber(bref[0]) or minv
    bref[0] = math.min(maxv, v + step)
  end
  local hp = imgui.IsItemHovered()
  dl:AddRectFilled(
    imgui.ImVec2(xr, yb), imgui.ImVec2(xr + btn, yb + btn),
    u32(imgui, with_a(imgui, C.soft, (hp and 0.14 or 0.07) * appear)), 9
  )
  dl:AddRect(imgui.ImVec2(xr, yb), imgui.ImVec2(xr + btn, yb + btn), u32(imgui, fade_a(imgui, stroke(imgui, C, 0.22), appear)), 9, imgui.DrawCornerFlags.All, 1)
  dl:AddLine(imgui.ImVec2(xr + 9, yb + btn * 0.5), imgui.ImVec2(xr + btn - 9, yb + btn * 0.5), u32(imgui, fade_a(imgui, C.soft, appear)), 2)
  dl:AddLine(imgui.ImVec2(xr + btn * 0.5, yb + 9), imgui.ImVec2(xr + btn * 0.5, yb + btn - 9), u32(imgui, fade_a(imgui, C.soft, appear)), 2)

  local val = tonumber(bref[0]) or minv
  local vs = tostring(val)
  local ts = imgui.CalcTextSize(vs)
  local pill_w = math.max(52, ts.x + 24)
  local pill_h = 28
  local px = min.x + (w - pill_w) * 0.5
  local py = yb + (btn - pill_h) * 0.5
  dl:AddRectFilled(
    imgui.ImVec2(px, py), imgui.ImVec2(px + pill_w, py + pill_h),
    u32(imgui, with_a(imgui, C.accent, 0.14 * appear)), 8
  )
  dl:AddRect(
    imgui.ImVec2(px, py), imgui.ImVec2(px + pill_w, py + pill_h),
    u32(imgui, fade_a(imgui, stroke(imgui, C, 0.35), appear)), 8, imgui.DrawCornerFlags.All, 1
  )
  dl:AddText(
    imgui.ImVec2(px + (pill_w - ts.x) * 0.5, py + (pill_h - ts.y) * 0.5),
    u32(imgui, fade_a(imgui, C.soft, appear)), vs
  )

  imgui.SetCursorScreenPos(imgui.ImVec2(base.x, base.y + h + 12))
  imgui.Dummy(imgui.ImVec2(w, 0))
end

-- ===================== PRIMITIVES =====================

local function soft_button(P, id, label, w, h, kind, fn)
  local imgui, C = P.imgui, P.C
  if not w or w < 0 then w = imgui.GetContentRegionAvail().x end
  local appear, slide, dy = next_appear()
  local base = imgui.GetCursorScreenPos()
  local min = imgui.ImVec2(base.x + slide, base.y + dy)
  local clicked = imgui.InvisibleButton(id, imgui.ImVec2(w, h))
  local hovered = imgui.IsItemHovered()
  local active = imgui.IsItemActive()
  local dt = imgui.GetIO().DeltaTime
  local hv = toward(anim.hover, id, hovered and 1 or 0, 14, dt)
  local pv = toward(anim.press, id, active and 1 or 0, 20, dt)
  local dl = imgui.GetWindowDrawList()
  local max = imgui.ImVec2(min.x + w, min.y + h)
  local r = 10
  local bright = lum(C.accent) > 0.72

  local fill, border, tcol
  if kind == 'primary' then
    if bright then
      fill = mix(imgui, with_a(imgui, C.soft, 0.08), with_a(imgui, C.soft, 0.14), hv)
      border = with_a(imgui, C.soft, 0.18 + 0.22 * hv)
      tcol = C.soft
    else
      local base_a = mix(imgui, C.accent, C.accent2, 0.15 + 0.25 * hv)
      fill = with_a(imgui, base_a, 0.55 + 0.20 * hv)
      border = with_a(imgui, C.soft, 0.10 + 0.18 * hv)
      tcol = C.nav_dark and P.c4(0.06, 0.05, 0.1) or P.c4(1, 1, 1)
    end
  else
    -- ghost: wash как строки МП
    fill = mix(imgui, with_a(imgui, C.soft, 0.045), with_a(imgui, C.soft, 0.10), hv)
    border = stroke(imgui, C, 0.10 + 0.22 * hv)
    tcol = C.soft
  end
  fill = fade_a(imgui, fill, appear)
  border = fade_a(imgui, border, appear)
  tcol = fade_a(imgui, tcol, appear)

  local inset = pv * 1.2
  local a = imgui.ImVec2(min.x + inset, min.y + inset)
  local b = imgui.ImVec2(max.x - inset, max.y - inset)

  soft_shadow(dl, imgui, a, b, r, ((kind == 'primary' and 0.55 or 0.35) + hv * 0.20) * appear)

  if hv > 0.05 and kind == 'primary' and not bright then
    dl:AddRectFilled(
      imgui.ImVec2(a.x - 2, a.y - 2), imgui.ImVec2(b.x + 2, b.y + 2),
      u32(imgui, with_a(imgui, C.accent, 0.18 * hv * appear)), r + 2
    )
  end

  dl:AddRectFilled(a, b, u32(imgui, fill), r)
  dl:AddRect(a, b, u32(imgui, border), r, imgui.DrawCornerFlags.All, 1.15)

  local ts = imgui.CalcTextSize(label)
  dl:AddText(
    imgui.ImVec2(min.x + (w - ts.x) * 0.5, min.y + (h - ts.y) * 0.5),
    u32(imgui, tcol), label
  )

  if clicked and fn then fn() end
  return clicked
end

local function toggle_row(P, id, label, bref)
  local imgui, C = P.imgui, P.C
  local w = imgui.GetContentRegionAvail().x
  local h = 40
  local appear, slide, dy = next_appear()
  local base = imgui.GetCursorScreenPos()
  local min = imgui.ImVec2(base.x + slide, base.y + dy)
  imgui.SetCursorScreenPos(base)
  if imgui.InvisibleButton(id, imgui.ImVec2(w, h)) then
    bref[0] = not bref[0]
  end
  local hovered = imgui.IsItemHovered()
  local dt = imgui.GetIO().DeltaTime
  local hv = toward(anim.hover, id, hovered and 1 or 0, 12, dt)
  local t = toward(anim.toggles, id, bref[0] and 1 or 0, 16, dt)
  local te = ease_out(t)
  local dl = imgui.GetWindowDrawList()
  local max = imgui.ImVec2(min.x + w, min.y + h)

  if hv > 0.01 then
    dl:AddRectFilled(min, max, u32(imgui, with_a(imgui, C.soft, 0.025 * hv * appear)), 8)
  end

  local tw, th = 40, 22
  local tx, ty = min.x + 8, min.y + (h - th) * 0.5
  local rr = th * 0.5
  local off = C.light and P.c4(0.70, 0.70, 0.72, 0.55) or P.c4(0.16, 0.16, 0.20, 0.95)
  local onc
  if lum(C.accent) > 0.72 then
    onc = with_a(imgui, C.soft, 0.50)
  else
    onc = with_a(imgui, C.accent, 0.80)
  end
  local track = fade_a(imgui, mix(imgui, off, onc, te), appear)
  dl:AddRectFilled(
    imgui.ImVec2(tx - 1, ty - 1), imgui.ImVec2(tx + tw + 1, ty + th + 1),
    u32(imgui, imgui.ImVec4(0, 0, 0, 0.35 * appear)), rr + 1
  )
  dl:AddRectFilled(imgui.ImVec2(tx, ty), imgui.ImVec2(tx + tw, ty + th), u32(imgui, track), rr)

  local kr = 7.5
  local kx = tx + 11 + te * (tw - 22)
  local ky = ty + th * 0.5
  dl:AddCircleFilled(imgui.ImVec2(kx + 0.8, ky + 1.2), kr, u32(imgui, imgui.ImVec4(0, 0, 0, 0.30 * appear)), 16)
  dl:AddCircleFilled(imgui.ImVec2(kx, ky), kr, u32(imgui, P.c4(1, 1, 1, 0.96 * appear)), 16)

  local tht = imgui.GetTextLineHeight()
  local lcol = fade_a(imgui, mix(imgui, C.muted, C.soft, 0.55 + 0.45 * hv), appear)
  dl:AddText(imgui.ImVec2(min.x + 58, min.y + (h - tht) * 0.5), u32(imgui, lcol), label)
  imgui.SetCursorScreenPos(imgui.ImVec2(base.x, base.y + h + 2))
end

local function value_box(P, label, value, vcol)
  local imgui, C = P.imgui, P.C
  local appear, slide, dy = next_appear()
  local base = imgui.GetCursorScreenPos()
  local min = imgui.ImVec2(base.x + slide, base.y + dy)
  local dl = imgui.GetWindowDrawList()
  dl:AddText(imgui.ImVec2(min.x, min.y), u32(imgui, fade_a(imgui, C.muted, appear)), label)
  imgui.Dummy(imgui.ImVec2(0, 6 + imgui.GetTextLineHeight()))
  local w = imgui.GetContentRegionAvail().x
  local h = 44
  base = imgui.GetCursorScreenPos()
  min = imgui.ImVec2(base.x + slide, base.y + dy)
  local max = imgui.ImVec2(min.x + w, min.y + h)
  draw_card(dl, imgui, C, min, max, 11, 0)

  local ts = imgui.CalcTextSize(tostring(value))
  dl:AddText(
    imgui.ImVec2(min.x + (w - ts.x) * 0.5, min.y + (h - ts.y) * 0.5),
    u32(imgui, fade_a(imgui, vcol or C.soft, appear)),
    tostring(value)
  )
  imgui.Dummy(imgui.ImVec2(0, h + 18))
end

local function panel_begin(P, id, w, h)
  local imgui, C = P.imgui, P.C
  -- панель без сдвига layout (иначе SameLine скачет); каскад — у детей внутри
  next_appear()
  local min = imgui.GetCursorScreenPos()
  local max = imgui.ImVec2(min.x + w, min.y + h)
  draw_card(imgui.GetWindowDrawList(), imgui, P.C, min, max, 14, 0)

  imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0, 0, 0, 0))
  imgui.PushStyleVarFloat(imgui.StyleVar.ChildRounding, 14)
  imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, imgui.ImVec2(0, 0))
  imgui.BeginChild(id, imgui.ImVec2(w, h), false)
  imgui.SetCursorPos(imgui.ImVec2(16, 16))
  imgui.BeginGroup()
  imgui.PushItemWidth(math.max(40, w - 32))
end

local function panel_end(P)
  P.imgui.PopItemWidth()
  P.imgui.EndGroup()
  P.imgui.EndChild()
  P.imgui.PopStyleVar(2)
  P.imgui.PopStyleColor()
end

local function nav_item_hit(P, entry)
  local imgui = P.imgui
  local tab = entry.tab
  local id = '##nav' .. tab
  local btn_w, btn_h = P.SIDE_W - 20, 40

  imgui.SetCursorPosX(10)
  local min = imgui.GetCursorScreenPos()
  imgui.InvisibleButton(id, imgui.ImVec2(btn_w, btn_h))
  local hovered = imgui.IsItemHovered()
  local pressed = imgui.IsItemActive()

  nav_drag.slots[#nav_drag.slots + 1] = {
    y = min.y,
    h = btn_h,
    cy = min.y + btn_h * 0.5,
    tab = tab,
    min = min,
    entry = entry,
    id = id,
    hovered = hovered,
  }
  if pressed then
    nav_drag.holding = true
  end
  if imgui.IsItemClicked() then
    switch_nav_tab(P, tab)
  end

  imgui.SetCursorScreenPos(imgui.ImVec2(min.x, min.y + btn_h + 6))
  imgui.Dummy(imgui.ImVec2(0, 0))
  return min.y, btn_h
end

local function nav_item_draw(P, slot)
  local imgui, C = P.imgui, P.C
  local entry = slot.entry
  local tab = entry.tab
  local active = (P.get_tab() == tab)
  local id = slot.id
  local min = slot.min
  local btn_w, btn_h = P.SIDE_W - 20, slot.h
  local dt = imgui.GetIO().DeltaTime
  -- при зажатии не подсвечиваем hover/press — только активная вкладка
  local want_hv = (not nav_drag.holding and slot.hovered and not active) and 1 or 0
  local hv = toward(anim.hover, id, want_hv, 18, dt)
  local dl = imgui.GetWindowDrawList()
  local max = imgui.ImVec2(min.x + btn_w, min.y + btn_h)

  if not active and hv > 0.01 then
    dl:AddRectFilled(min, max, u32(imgui, with_a(imgui, C.soft, 0.04 * hv)), 12)
  end

  local bx, by = min.x + 8, min.y + 8
  local bs = 28
  local badge_fill
  if active then
    if lum(C.accent) > 0.72 then
      badge_fill = with_a(imgui, C.soft, 0.14)
    else
      badge_fill = with_a(imgui, C.accent, 0.35)
    end
  else
    badge_fill = with_a(imgui, C.soft, 0.05 + 0.06 * hv)
  end
  dl:AddRectFilled(imgui.ImVec2(bx, by), imgui.ImVec2(bx + bs, by + bs), u32(imgui, badge_fill), 9)
  dl:AddRect(
    imgui.ImVec2(bx, by), imgui.ImVec2(bx + bs, by + bs),
    u32(imgui, stroke(imgui, C, active and 0.35 or (0.08 + 0.15 * hv))),
    9, imgui.DrawCornerFlags.All, 1
  )

  local icol = active and u32(imgui, C.soft) or u32(imgui, with_a(imgui, C.muted, 0.75 + 0.25 * hv))
  entry.icon(dl, imgui, bx + bs * 0.5, by + bs * 0.5, icol, 6.8)

  local tcol = active and C.soft or with_a(imgui, C.muted, 0.7 + 0.3 * hv)
  local th = imgui.GetTextLineHeight()
  dl:AddText(imgui.ImVec2(min.x + 46, min.y + (btn_h - th) * 0.5), u32(imgui, tcol), entry.label)
end

local function draw_chrome(P, alpha)
  local imgui, C, ROUND = P.imgui, P.C, P.ROUND
  local dl = imgui.GetWindowDrawList()
  local p, sz = imgui.GetWindowPos(), imgui.GetWindowSize()
  local a = imgui.ImVec2(p.x, p.y)
  local b = imgui.ImVec2(p.x + sz.x, p.y + sz.y)
  local corners = imgui.DrawCornerFlags.All
  local pulse = 0.55 + 0.2 * math.sin(imgui.GetTime() * 1.4)

  -- мягкая внешняя тень окна
  soft_shadow(dl, imgui, a, b, ROUND, 1.0 * alpha)

  local blur_mod = ensure_blur()
  if blur_mod then
    pcall(blur_mod.applyRect, dl, a, b, 2.4, u32(imgui, P.c4(1, 1, 1, 1)), ROUND, corners)
  end

  -- лёгкое стекло поверх фона темы (не закрашивать наглухо!)
  dl:AddRectFilled(a, b, u32(imgui, with_a(imgui, C.panel, (C.light and 0.28 or 0.18) * alpha)), ROUND, corners)
  dl:AddRect(a, b, u32(imgui, stroke(imgui, C, 0.32 * pulse * alpha)), ROUND, corners, 1.3)
  dl:AddRect(
    imgui.ImVec2(a.x + 1, a.y + 1), imgui.ImVec2(b.x - 1, b.y - 1),
    u32(imgui, with_a(imgui, C.soft, 0.05 * alpha)), ROUND - 1, corners, 1
  )
end

-- ===================== PAGES =====================

local function draw_home(P, q, afk_now, idle)
  local imgui, C, cfg, ui = P.imgui, P.C, P.cfg, P.ui
  local avail = imgui.GetContentRegionAvail().x
  local gap = 14
  local leftW = math.floor(avail * 0.42)
  local rightW = avail - leftW - gap
  local pageH = imgui.GetContentRegionAvail().y

  panel_begin(P, '##pb_left', leftW, pageH)
  toggle_row(P, '##t_rep', 'Репорты', ui.reports)
  toggle_row(P, '##t_frm', 'Админ-формы', ui.forms)
  toggle_row(P, '##t_men', 'Упоминания @ник', ui.mentions)
  toggle_row(P, '##t_que', 'Очередь Tools', ui.watch_queue)
  toggle_row(P, '##t_afk', 'Только когда AFK', ui.quiet_mode)
  toggle_row(P, '##t_clips', 'Клипы в Telegram', ui.send_clips)
  if ui.send_clips[0] ~= cfg.clips then P.clips_set_enabled(ui.send_clips[0]) end
  panel_end(P)

  imgui.SameLine(0, gap)
  imgui.BeginChild('##pb_right', imgui.ImVec2(rightW, pageH), false)

  local qtxt = (q ~= nil) and tostring(q) or '-'
  local qcol = (q ~= nil and q >= cfg.queue_from) and C.warn or C.ok
  value_box(P, 'Очередь репортов', qtxt, qcol)
  local fmt = P.format_active_sec or function(s) return tostring(s) .. 's' end
  local tools_on = P.read_tools_online and P.read_tools_online() or nil
  local tools_afk = P.read_tools_afk and P.read_tools_afk() or nil
  local atxt
  if afk_now then
    atxt = 'AFK ' .. fmt(tools_afk ~= nil and tools_afk or idle)
  elseif tools_on ~= nil then
    atxt = 'online ' .. fmt(tools_on)
  else
    atxt = 'online ' .. fmt(idle)
  end
  value_box(P, 'Онлайн (Tools)', atxt, afk_now and C.warn or C.ok)

  local gw = (imgui.GetContentRegionAvail().x - 12) / 3
  local gh = 40
  soft_button(P, '##b_test', 'Тест TG', gw, gh, 'ghost', function()
    P.apply_ui_to_cfg()
    P.notify('test', P.cp('Arizona · Тест из меню\nЕсли видите это — мост работает.'), {})
    P.chat('Тест отправлен')
  end)
  imgui.SameLine(0, 6)
  soft_button(P, '##b_q', 'Очередь', gw, gh, 'ghost', function() P.send_queue_now() end)
  imgui.SameLine(0, 6)
  soft_button(P, '##b_c', 'Клипы', gw, gh, 'ghost', function()
    P.set_tab(3); anim.tab_fade = 0; reset_tab_anim(); P.sync_clips_ui()
  end)

  imgui.Dummy(imgui.ImVec2(0, 8))
  soft_button(P, '##b_rec', 'REC', gw, gh, 'ghost', function() P.ipc.write_cmd('record') end)
  imgui.SameLine(0, 6)
  soft_button(P, '##b_rw', 'Replay', gw, gh, 'ghost', function() P.ipc.write_cmd('rewind') end)
  imgui.SameLine(0, 6)
  soft_button(P, '##b_th', 'Темы', gw, gh, 'ghost', function()
    P.set_tab(4); anim.tab_fade = 0; reset_tab_anim()
  end)

  imgui.Dummy(imgui.ImVec2(0, 10))
  soft_button(P, '##b_set', 'Настройки порогов', -1, 42, 'primary', function()
    P.set_tab(2); anim.tab_fade = 0; reset_tab_anim(); P.sync_ui_from_cfg()
  end)

  imgui.Dummy(imgui.ImVec2(0, 14))
  local lpa, lpk = P.get_last_push()
  if lpa > 0 then
    imgui.TextColored(C.muted, string.format('Последний пуш: %s  %s', lpk, os.date('%H:%M', lpa)))
  else
    imgui.TextColored(C.muted, 'Последний пуш: —')
  end
  imgui.EndChild()
end

local function draw_events(P)
  local imgui, C = P.imgui, P.C
  if anim.need_events_fetch and P.events_fetch then
    anim.need_events_fetch = false
    P.events_fetch(false)
  end
  local st = P.events_get_state and P.events_get_state() or {}
  local all_list = P.events_get_list and P.events_get_list() or {}
  local today_list = st.today_list or {}
  local avail = imgui.GetContentRegionAvail().x
  local rename_key = P.events_get_rename_key and P.events_get_rename_key() or nil
  local dt = imgui.GetIO().DeltaTime
  local tnow = imgui.GetTime()
  if st.status == 'loading' then
    anim.ev_was_loading = true
  elseif anim.ev_was_loading then
    anim.ev_was_loading = false
    reset_tab_anim()
  end

  -- фильтр: по умолчанию без уже проведённых (без повторов за день)
  local done_n = 0
  for i = 1, #all_list do
    if all_list[i].done then done_n = done_n + 1 end
  end
  local list = {}
  if anim.ev_show_done then
    list = all_list
  else
    for i = 1, #all_list do
      if not all_list[i].done then list[#list + 1] = all_list[i] end
    end
  end

  local function row_appear(i)
    -- после шапки/кнопок: смещение индекса, чтобы строки шли каскадом
    return tab_appear((anim.appear_i or 0) + i)
  end

  -- компактная шапка в одну строку
  do
    local row_h = 30
    local min = imgui.GetCursorScreenPos()
    local dl = imgui.GetWindowDrawList()
    local head_a = ease_out(clamp(anim.tab_clock / 0.28, 0, 1))
    local left = string.format('Space · %s', tostring(st.today or os.date('%d.%m.%Y')))
    local status = tostring(st.status or '')
    if st.err and st.err ~= '' then status = status .. ' · ' .. st.err end
    dl:AddText(imgui.ImVec2(min.x, min.y + 6), u32(imgui, with_a(imgui, C.soft, head_a)), left)
    local lx = min.x + imgui.CalcTextSize(left).x + 10
    dl:AddText(imgui.ImVec2(lx, min.y + 6), u32(imgui, with_a(imgui, C.muted, head_a)), status)

    local bw = 96
    imgui.SetCursorScreenPos(imgui.ImVec2(min.x + avail - bw, min.y))
    soft_button(P, '##ev_ref', 'Обновить', bw, row_h, 'ghost', function()
      reset_tab_anim()
      if P.events_fetch then P.events_fetch(true) end
    end)
    imgui.SetCursorScreenPos(imgui.ImVec2(min.x, min.y + row_h + 8))
    imgui.Dummy(imgui.ImVec2(0, 0))
  end

  if rename_key and P.ui.events_rename then
    imgui.PushItemWidth(avail - 180)
    imgui.InputText('##ev_ren_in', P.ui.events_rename, 96)
    imgui.PopItemWidth()
    imgui.SameLine(0, 6)
    soft_button(P, '##ev_ren_ok', 'OK', 50, 26, 'primary', function()
      if P.events_apply_rename then P.events_apply_rename(); P.chat('МП переименовано') end
    end)
    imgui.SameLine(0, 6)
    soft_button(P, '##ev_ren_cancel', '×', 28, 26, 'ghost', function()
      if P.events_cancel_rename then P.events_cancel_rename() end
    end)
    imgui.Dummy(imgui.ImVec2(0, 6))
  end

  local gap = 10
  local leftW = math.floor(avail * 0.50)
  local rightW = avail - leftW - gap
  local bodyH = math.max(120, imgui.GetContentRegionAvail().y - 4)

  -- ===== слева: рекомендованные =====
  imgui.BeginChild('##ev_rec', imgui.ImVec2(leftW, bodyH), false)
  do
    local title = anim.ev_show_done
      and string.format('Рекомендованные · %d', #list)
      or string.format('Осталось · %d', #list)
    imgui.TextColored(C.muted, title)
    imgui.SameLine(0, 8)
    local filt = anim.ev_show_done and 'без повторов' or 'все'
    local fw = imgui.CalcTextSize(filt).x + 8
    if imgui.InvisibleButton('##ev_filt', imgui.ImVec2(fw, 16)) then
      anim.ev_show_done = not anim.ev_show_done
      reset_tab_anim()
    end
    local fmin = imgui.GetItemRectMin()
    local fh = toward(anim.hover, '##ev_filt', imgui.IsItemHovered() and 1 or 0, 14, dt)
    imgui.GetWindowDrawList():AddText(fmin, u32(imgui, mix(imgui, C.muted, C.accent, fh)), filt)
    if done_n > 0 and not anim.ev_show_done then
      imgui.SameLine(0, 6)
      imgui.TextColored(C.muted, string.format('(%d сегодня)', done_n))
    end
    imgui.SameLine()
    local tw = imgui.CalcTextSize('сброс').x + 8
    imgui.SetCursorPosX(math.max(imgui.GetCursorPosX(), leftW - tw - 4))
    if imgui.InvisibleButton('##ev_reset', imgui.ImVec2(tw, 16)) then
      if P.events_reset_hidden then P.events_reset_hidden(); P.chat('Рекомендации восстановлены') end
    end
    local rmin = imgui.GetItemRectMin()
    local rh = toward(anim.hover, '##ev_reset', imgui.IsItemHovered() and 1 or 0, 14, dt)
    imgui.GetWindowDrawList():AddText(rmin, u32(imgui, mix(imgui, C.muted, C.accent, rh)), 'сброс')
  end
  if P.ui.events_add then
    local add_h = 26
    local add_bw = 78
    local flags = 0
    pcall(function() flags = imgui.InputTextFlags.EnterReturnsTrue end)
    local function do_add()
      if not P.events_add_from_buf then return end
      local ok, err, name = P.events_add_from_buf()
      if ok then
        P.chat('В рекомендации: ' .. tostring(name))
      elseif err == 'exists' then
        P.chat('Уже в списке')
      elseif err == 'empty' then
        P.chat('Введите название МП')
      end
    end
    imgui.PushItemWidth(math.max(40, leftW - add_bw - 10))
    local enter = imgui.InputText('##ev_add_in', P.ui.events_add, 96, flags)
    imgui.PopItemWidth()
    imgui.SameLine(0, 6)
    soft_button(P, '##ev_add_ok', 'Добавить', add_bw, add_h, 'primary', do_add)
    if enter then do_add() end
    imgui.Dummy(imgui.ImVec2(0, 2))
  else
    imgui.Dummy(imgui.ImVec2(0, 4))
  end
  imgui.BeginChild('##ev_rec_list', imgui.ImVec2(0, -1), false)
  if #list == 0 then
    if not anim.ev_show_done and done_n > 0 then
      imgui.TextColored(C.muted, 'Все рекомендованные уже сегодня')
      imgui.TextColored(C.muted, 'нажми «все», чтобы увидеть')
    else
      imgui.TextColored(C.muted, 'Список пуст — сброс')
    end
  else
    for i = 1, #list do
      local e = list[i]
      local row_h = 30
      local btn = 22
      local w = imgui.GetContentRegionAvail().x
      local text_w = math.max(40, w - btn * 2 - 10)
      local base = imgui.GetCursorScreenPos()
      local appear, slide, dy = row_appear(i)
      local min = imgui.ImVec2(base.x + slide, base.y + dy)
      local dl = imgui.GetWindowDrawList()
      local editing = (rename_key == e.key)
      local id = '##evr' .. i

      imgui.SetCursorScreenPos(base)
      imgui.InvisibleButton(id, imgui.ImVec2(text_w, row_h))
      local hovered = imgui.IsItemHovered()
      local hv = toward(anim.hover, id, hovered and 1 or 0, 14, dt)

      local fill = e.done and with_a(imgui, C.soft, 0.025) or with_a(imgui, C.soft, 0.045)
      if not e.done then fill = mix(imgui, fill, with_a(imgui, C.accent, 0.08), 0.4) end
      if editing then fill = with_a(imgui, C.accent, 0.16) end
      fill = mix(imgui, fill, with_a(imgui, C.soft, 0.10), hv * 0.55)
      fill = with_a(imgui, fill, (fill.w or 1) * appear)

      if hv > 0.08 then
        soft_shadow(dl, imgui, min, imgui.ImVec2(min.x + w, min.y + row_h), 6, 0.35 * hv * appear)
      end
      dl:AddRectFilled(min, imgui.ImVec2(min.x + w, min.y + row_h), u32(imgui, fill), 6)
      if hv > 0.05 and not e.done then
        dl:AddRect(
          min, imgui.ImVec2(min.x + w, min.y + row_h),
          u32(imgui, with_a(imgui, C.accent, 0.22 * hv * appear)), 6, imgui.DrawCornerFlags.All, 1
        )
      end

      local th = imgui.GetTextLineHeight()
      local ty = min.y + (row_h - th) * 0.5
      local tcol = e.done and with_a(imgui, C.muted, 0.75) or C.soft
      tcol = with_a(imgui, tcol, (tcol.w or 1) * appear)
      -- место справа под индикатор, чтобы клип его не срезал
      local clip2 = min.x + text_w - (e.done and 4 or 18)
      pcall(function()
        dl:PushClipRect(imgui.ImVec2(min.x + 8, min.y), imgui.ImVec2(clip2, min.y + row_h), true)
      end)
      dl:AddText(imgui.ImVec2(min.x + 8, ty), u32(imgui, tcol), e.name)
      if e.done then
        local ts = imgui.CalcTextSize(e.name)
        local mid = ty + th * 0.55
        dl:AddLine(
          imgui.ImVec2(min.x + 8, mid), imgui.ImVec2(math.min(min.x + 8 + ts.x, clip2), mid),
          u32(imgui, with_a(imgui, C.muted, 0.8 * appear)), 1.4
        )
        local meta = ''
        if e.time and e.time ~= '' then meta = e.time end
        if e.org and e.org ~= '' then meta = meta .. (meta ~= '' and ' · ' or '') .. e.org end
        if meta ~= '' then
          local mx = min.x + 8 + ts.x + 8
          if mx + imgui.CalcTextSize(meta).x < clip2 then
            dl:AddText(imgui.ImVec2(mx, ty), u32(imgui, with_a(imgui, C.muted, appear)), meta)
          end
        end
      end
      pcall(function() dl:PopClipRect() end)

      if not e.done then
        local pulse = 0.55 + 0.45 * math.sin(tnow * 2.2 + i * 0.4)
        local cx = min.x + text_w - 9
        local cy = min.y + row_h * 0.5
        local pr = 3.2 + 1.4 * pulse
        dl:AddCircle(imgui.ImVec2(cx, cy), pr + 2.2, u32(imgui, with_a(imgui, C.ok, 0.25 * pulse * appear)), 14, 1.3)
        dl:AddCircleFilled(imgui.ImVec2(cx, cy), 2.8, u32(imgui, with_a(imgui, C.ok, (0.55 + 0.45 * pulse) * appear)), 12)
      end

      imgui.SameLine(0, 4)
      local rmin = imgui.ImVec2(base.x + text_w + 2, base.y + 4 + dy)
      imgui.SetCursorScreenPos(imgui.ImVec2(base.x + text_w + 2, base.y + 4))
      if imgui.InvisibleButton('##evren' .. i, imgui.ImVec2(btn, row_h - 8)) then
        if P.events_begin_rename then P.events_begin_rename(e.key, e.name) end
      end
      local rhv = toward(anim.hover, '##evren' .. i, imgui.IsItemHovered() and 1 or 0, 16, dt)
      local inset = rhv * 0.8
      dl:AddRectFilled(
        imgui.ImVec2(rmin.x + inset, rmin.y + inset),
        imgui.ImVec2(rmin.x + btn - inset, rmin.y + row_h - 8 - inset),
        u32(imgui, mix(imgui, with_a(imgui, C.soft, 0.05 * appear), with_a(imgui, C.accent, 0.45 * appear), rhv)), 5
      )
      dl:AddText(imgui.ImVec2(rmin.x + 3, rmin.y + 2), u32(imgui, with_a(imgui, C.soft, appear)), 'Aa')

      imgui.SameLine(0, 4)
      local draw_xmin = imgui.ImVec2(base.x + text_w + 2 + btn + 4, base.y + 4 + dy)
      if imgui.InvisibleButton('##evx' .. i, imgui.ImVec2(btn, row_h - 8)) then
        if P.events_hide_rec and P.events_hide_rec(e.key) then P.chat('Убрано: ' .. tostring(e.name)) end
      end
      local xhv = toward(anim.hover, '##evx' .. i, imgui.IsItemHovered() and 1 or 0, 16, dt)
      local xi = xhv * 0.8
      dl:AddRectFilled(
        imgui.ImVec2(draw_xmin.x + xi, draw_xmin.y + xi),
        imgui.ImVec2(draw_xmin.x + btn - xi, draw_xmin.y + row_h - 8 - xi),
        u32(imgui, mix(imgui, with_a(imgui, C.soft, 0.05 * appear), with_a(imgui, C.bad, 0.5 * appear), xhv)), 5
      )
      icon_x(dl, imgui, draw_xmin.x + btn * 0.5, draw_xmin.y + (row_h - 8) * 0.5, u32(imgui, with_a(imgui, C.soft, appear)), 2.8)

      imgui.SetCursorScreenPos(imgui.ImVec2(base.x, base.y + row_h + 2))
      imgui.Dummy(imgui.ImVec2(0, 0))
    end
  end
  imgui.EndChild()
  imgui.EndChild()

  -- ===== справа: сегодня =====
  imgui.SameLine(0, gap)
  imgui.BeginChild('##ev_today', imgui.ImVec2(rightW, bodyH), false)
  imgui.TextColored(C.muted, string.format('Сегодня · %d', #today_list))
  imgui.Dummy(imgui.ImVec2(0, 4))
  imgui.BeginChild('##ev_today_list', imgui.ImVec2(0, -1), false)
  if #today_list == 0 then
    imgui.TextColored(C.muted, 'Пока пусто')
  else
    for i = 1, #today_list do
      local r = today_list[i]
      local has_org = r.org and r.org ~= ''
      local row_h = has_org and 40 or 28
      local btn = 22
      local in_rec = P.events_has_rec and P.events_has_rec(r.key or r.name)
      local w = imgui.GetContentRegionAvail().x
      local text_w = math.max(40, w - (in_rec and 0 or (btn + 6)))
      local base = imgui.GetCursorScreenPos()
      local appear, slide, dy = row_appear(i + math.max(#list, 1))
      local min = imgui.ImVec2(base.x + slide, base.y + dy)
      local dl = imgui.GetWindowDrawList()
      local pad = 8
      local right = min.x + text_w - 4
      local id = '##evt' .. i

      imgui.SetCursorScreenPos(base)
      imgui.InvisibleButton(id, imgui.ImVec2(text_w, row_h))
      local hv = toward(anim.hover, id, imgui.IsItemHovered() and 1 or 0, 14, dt)

      local fill = with_a(imgui, C.card, (0.32 + 0.18 * hv) * appear)
      if hv > 0.08 then
        soft_shadow(dl, imgui, min, imgui.ImVec2(min.x + w, min.y + row_h), 7, 0.4 * hv * appear)
      end
      dl:AddRectFilled(min, imgui.ImVec2(min.x + w, min.y + row_h), u32(imgui, fill), 6)
      dl:AddRect(
        min, imgui.ImVec2(min.x + w, min.y + row_h),
        u32(imgui, stroke(imgui, C, (0.10 + 0.18 * hv) * appear)), 6, imgui.DrawCornerFlags.All, 1
      )
      if hv > 0.02 then
        dl:AddRectFilled(
          imgui.ImVec2(min.x + 1, min.y + 6), imgui.ImVec2(min.x + 3, min.y + row_h - 6),
          u32(imgui, with_a(imgui, C.accent, 0.75 * hv * appear)), 2
        )
      end

      local th = imgui.GetTextLineHeight()
      local time_s = (r.time and r.time ~= '') and r.time or '--:--'
      local time_w = imgui.CalcTextSize(time_s).x
      local name = tostring(r.name or '')
      local acol = with_a(imgui, C.accent, appear)
      local scol = with_a(imgui, C.soft, appear)
      local mcol = with_a(imgui, C.muted, appear)

      if has_org then
        dl:AddText(imgui.ImVec2(min.x + pad, min.y + 4), u32(imgui, acol), time_s)
        local nx = min.x + pad + time_w + 8
        pcall(function()
          dl:PushClipRect(imgui.ImVec2(nx, min.y), imgui.ImVec2(right, min.y + th + 6), true)
        end)
        dl:AddText(imgui.ImVec2(nx, min.y + 4), u32(imgui, scol), name)
        pcall(function() dl:PopClipRect() end)
        pcall(function()
          dl:PushClipRect(imgui.ImVec2(min.x + pad, min.y + th + 4), imgui.ImVec2(right, min.y + row_h), true)
        end)
        dl:AddText(imgui.ImVec2(min.x + pad, min.y + 4 + th + 2), u32(imgui, mcol), tostring(r.org))
        pcall(function() dl:PopClipRect() end)
      else
        local ty = min.y + (row_h - th) * 0.5
        dl:AddText(imgui.ImVec2(min.x + pad, ty), u32(imgui, acol), time_s)
        local nx = min.x + pad + time_w + 8
        pcall(function()
          dl:PushClipRect(imgui.ImVec2(nx, min.y), imgui.ImVec2(right, min.y + row_h), true)
        end)
        dl:AddText(imgui.ImVec2(nx, ty), u32(imgui, scol), name)
        pcall(function() dl:PopClipRect() end)
      end

      if not in_rec then
        local by = base.y + (row_h - (btn)) * 0.5
        local draw_xmin = imgui.ImVec2(base.x + text_w + 2, by + dy)
        imgui.SetCursorScreenPos(imgui.ImVec2(base.x + text_w + 2, by))
        if imgui.InvisibleButton('##evta' .. i, imgui.ImVec2(btn, btn)) then
          if P.events_add_rec then
            local ok = P.events_add_rec(r.name)
            if ok then P.chat('В рекомендации: ' .. tostring(r.name))
            else P.chat('Уже в списке') end
          end
        end
        local ahv = toward(anim.hover, '##evta' .. i, imgui.IsItemHovered() and 1 or 0, 16, dt)
        local ai = ahv * 0.8
        dl:AddRectFilled(
          imgui.ImVec2(draw_xmin.x + ai, draw_xmin.y + ai),
          imgui.ImVec2(draw_xmin.x + btn - ai, draw_xmin.y + btn - ai),
          u32(imgui, mix(imgui, with_a(imgui, C.soft, 0.05 * appear), with_a(imgui, C.ok, 0.55 * appear), ahv)), 5
        )
        local cx = draw_xmin.x + btn * 0.5
        local cy = draw_xmin.y + btn * 0.5
        local col = u32(imgui, with_a(imgui, C.soft, appear))
        dl:AddLine(imgui.ImVec2(cx - 3.2, cy), imgui.ImVec2(cx + 3.2, cy), col, 1.6)
        dl:AddLine(imgui.ImVec2(cx, cy - 3.2), imgui.ImVec2(cx, cy + 3.2), col, 1.6)
      end

      imgui.SetCursorScreenPos(imgui.ImVec2(base.x, base.y + row_h + 3))
      imgui.Dummy(imgui.ImVec2(0, 0))
    end
  end
  imgui.EndChild()
  imgui.EndChild()
end

local function draw_orgs(P)
  local imgui, C = P.imgui, P.C
  if anim.need_events_fetch and P.events_fetch then
    anim.need_events_fetch = false
    P.events_fetch(false)
  end
  local st = P.events_get_state and P.events_get_state() or {}
  local day_ago = (anim.org_day == 1) and 1 or 0
  local list, day_mp, day_str = {}, 0, ''
  if P.events_get_orgs then
    list, day_mp, day_str = P.events_get_orgs(day_ago)
  end
  list = list or {}
  day_mp = tonumber(day_mp) or 0
  local help_stats, hmeta = {}, {}
  if P.events_get_helpers_stats then
    help_stats, hmeta = P.events_get_helpers_stats()
  end
  help_stats = help_stats or {}
  hmeta = hmeta or {}
  local stats, smeta = {}, {}
  if P.events_get_orgs_stats then
    stats, smeta = P.events_get_orgs_stats()
  end
  stats = stats or {}
  smeta = smeta or {}
  local avail = imgui.GetContentRegionAvail().x
  local dt = imgui.GetIO().DeltaTime
  if st.status == 'loading' then
    anim.ev_was_loading = true
  elseif anim.ev_was_loading then
    anim.ev_was_loading = false
    reset_tab_anim()
  end

  local function row_appear(i)
    return tab_appear((anim.appear_i or 0) + i)
  end

  local function draw_hide_x(id, key, name, base, x, y, btn, appear, dy, hide_fn)
    local draw_xmin = imgui.ImVec2(x, y + dy)
    imgui.SetCursorScreenPos(imgui.ImVec2(x, y))
    if imgui.InvisibleButton(id, imgui.ImVec2(btn, btn)) then
      local fn = hide_fn or P.events_hide_org
      if fn and fn(key or name) then
        P.chat('Убран: ' .. tostring(name))
      end
    end
    local dl = imgui.GetWindowDrawList()
    local xhv = toward(anim.hover, id, imgui.IsItemHovered() and 1 or 0, 16, dt)
    local xi = xhv * 0.8
    dl:AddRectFilled(
      imgui.ImVec2(draw_xmin.x + xi, draw_xmin.y + xi),
      imgui.ImVec2(draw_xmin.x + btn - xi, draw_xmin.y + btn - xi),
      u32(imgui, mix(imgui, with_a(imgui, C.soft, 0.05 * appear), with_a(imgui, C.bad, 0.5 * appear), xhv)), 5
    )
    icon_x(dl, imgui, draw_xmin.x + btn * 0.5, draw_xmin.y + btn * 0.5, u32(imgui, with_a(imgui, C.soft, appear)), 2.8)
  end

  local function draw_day_person_rows(rows, id_prefix, hide_fn, appear_off)
    if #rows == 0 then return end
    for i = 1, #rows do
      local e = rows[i]
      local row_h = 34
      local btn = 22
      local badge_w = 42
      local w = imgui.GetContentRegionAvail().x
      local text_w = math.max(40, w - btn - badge_w - 12)
      local base = imgui.GetCursorScreenPos()
      local appear, slide, dy = row_appear((appear_off or 0) + i)
      local min = imgui.ImVec2(base.x + slide, base.y + dy)
      local dl = imgui.GetWindowDrawList()
      local id = id_prefix .. i

      imgui.SetCursorScreenPos(base)
      imgui.InvisibleButton(id, imgui.ImVec2(text_w, row_h))
      local hv = toward(anim.hover, id, imgui.IsItemHovered() and 1 or 0, 14, dt)

      local fill = with_a(imgui, C.card, (0.32 + 0.18 * hv) * appear)
      if hv > 0.08 then
        soft_shadow(dl, imgui, min, imgui.ImVec2(min.x + w, min.y + row_h), 7, 0.4 * hv * appear)
      end
      dl:AddRectFilled(min, imgui.ImVec2(min.x + w, min.y + row_h), u32(imgui, fill), 7)
      dl:AddRect(
        min, imgui.ImVec2(min.x + w, min.y + row_h),
        u32(imgui, stroke(imgui, C, (0.10 + 0.18 * hv) * appear)), 7, imgui.DrawCornerFlags.All, 1
      )

      local th = imgui.GetTextLineHeight()
      local ty = min.y + (row_h - th) * 0.5
      local name = tostring(e.name or '')
      local clip_r = min.x + text_w - 4
      pcall(function()
        dl:PushClipRect(imgui.ImVec2(min.x + 10, min.y), imgui.ImVec2(clip_r, min.y + row_h), true)
      end)
      dl:AddText(imgui.ImVec2(min.x + 10, ty), u32(imgui, with_a(imgui, C.soft, appear)), name)
      if e.last and e.last ~= '' then
        local nx = min.x + 10 + imgui.CalcTextSize(name).x + 8
        if nx + imgui.CalcTextSize(e.last).x < clip_r then
          dl:AddText(imgui.ImVec2(nx, ty), u32(imgui, with_a(imgui, C.muted, appear)), e.last)
        end
      end
      pcall(function() dl:PopClipRect() end)

      local cnt = tostring(e.count or 0)
      local bx = min.x + text_w + 2
      local bw, bh = badge_w - 4, 22
      local by = min.y + (row_h - bh) * 0.5
      local bright = lum(C.accent) > 0.72
      local bfill = bright
        and with_a(imgui, C.soft, 0.92 * appear)
        or with_a(imgui, C.accent, 0.95 * appear)
      local btxt = bright
        and with_a(imgui, P.c4(0.08, 0.08, 0.1), appear)
        or with_a(imgui, P.c4(1, 1, 1), appear)
      dl:AddRectFilled(imgui.ImVec2(bx, by), imgui.ImVec2(bx + bw, by + bh), u32(imgui, bfill), 6)
      local cts = imgui.CalcTextSize(cnt)
      dl:AddText(
        imgui.ImVec2(bx + (bw - cts.x) * 0.5, by + (bh - cts.y) * 0.5),
        u32(imgui, btxt), cnt
      )

      draw_hide_x(
        id_prefix .. 'x' .. i, e.key, e.name, base,
        base.x + text_w + badge_w + 2, base.y + (row_h - btn) * 0.5,
        btn, appear, dy, hide_fn
      )

      imgui.SetCursorScreenPos(imgui.ImVec2(base.x, base.y + row_h + 3))
      imgui.Dummy(imgui.ImVec2(0, 0))
    end
  end

  local function draw_count_badge(dl, x, y, w, h, text, appear, primary)
    local bright = lum(C.accent) > 0.72
    local bfill, btxt
    if primary then
      bfill = bright and with_a(imgui, C.soft, 0.92 * appear) or with_a(imgui, C.accent, 0.95 * appear)
      btxt = bright and with_a(imgui, P.c4(0.08, 0.08, 0.1), appear) or with_a(imgui, P.c4(1, 1, 1), appear)
    else
      bfill = with_a(imgui, C.soft, (bright and 0.14 or 0.12) * appear)
      btxt = with_a(imgui, C.soft, appear)
    end
    dl:AddRectFilled(imgui.ImVec2(x, y), imgui.ImVec2(x + w, y + h), u32(imgui, bfill), 6)
    local ts = imgui.CalcTextSize(text)
    dl:AddText(
      imgui.ImVec2(x + (w - ts.x) * 0.5, y + (h - ts.y) * 0.5),
      u32(imgui, btxt), text
    )
  end

  -- помощники: как дневной счётчик, но неделя + всё время
  local function draw_helper_rows(rows, id_prefix, appear_off)
    if #rows == 0 then
      imgui.TextColored(C.muted, (st.status == 'loading') and 'Загрузка…' or 'Помощников пока нет')
      return
    end
    for i = 1, #rows do
      local e = rows[i]
      local row_h = 34
      local btn = 22
      local badge_w = 40
      local gap = 4
      local w = imgui.GetContentRegionAvail().x
      local text_w = math.max(40, w - btn - badge_w * 2 - gap - 14)
      local base = imgui.GetCursorScreenPos()
      local appear, slide, dy = row_appear((appear_off or 0) + i)
      local min = imgui.ImVec2(base.x + slide, base.y + dy)
      local dl = imgui.GetWindowDrawList()
      local id = id_prefix .. i

      imgui.SetCursorScreenPos(base)
      imgui.InvisibleButton(id, imgui.ImVec2(text_w, row_h))
      local hv = toward(anim.hover, id, imgui.IsItemHovered() and 1 or 0, 14, dt)

      local fill = with_a(imgui, C.card, (0.32 + 0.18 * hv) * appear)
      if hv > 0.08 then
        soft_shadow(dl, imgui, min, imgui.ImVec2(min.x + w, min.y + row_h), 7, 0.4 * hv * appear)
      end
      dl:AddRectFilled(min, imgui.ImVec2(min.x + w, min.y + row_h), u32(imgui, fill), 7)
      dl:AddRect(
        min, imgui.ImVec2(min.x + w, min.y + row_h),
        u32(imgui, stroke(imgui, C, (0.10 + 0.18 * hv) * appear)), 7, imgui.DrawCornerFlags.All, 1
      )

      local th = imgui.GetTextLineHeight()
      local ty = min.y + (row_h - th) * 0.5
      local name = tostring(e.name or '')
      local clip_r = min.x + text_w - 4
      pcall(function()
        dl:PushClipRect(imgui.ImVec2(min.x + 10, min.y), imgui.ImVec2(clip_r, min.y + row_h), true)
      end)
      dl:AddText(imgui.ImVec2(min.x + 10, ty), u32(imgui, with_a(imgui, C.soft, appear)), name)
      pcall(function() dl:PopClipRect() end)

      local bh = 22
      local by = min.y + (row_h - bh) * 0.5
      local bw = badge_w - 2
      local bx1 = min.x + text_w + 2
      local bx2 = bx1 + badge_w + gap
      draw_count_badge(dl, bx1, by, bw, bh, tostring(e.week_n or 0), appear, true)
      draw_count_badge(dl, bx2, by, bw, bh, tostring(e.all_n or 0), appear, false)

      draw_hide_x(
        id_prefix .. 'x' .. i, e.key, e.name, base,
        base.x + text_w + badge_w * 2 + gap + 6, base.y + (row_h - btn) * 0.5,
        btn, appear, dy, P.events_hide_helper
      )

      imgui.SetCursorScreenPos(imgui.ImVec2(base.x, base.y + row_h + 3))
      imgui.Dummy(imgui.ImVec2(0, 0))
    end
  end

  -- шапка
  do
    local row_h = 30
    local min = imgui.GetCursorScreenPos()
    local dl = imgui.GetWindowDrawList()
    local head_a = ease_out(clamp(anim.tab_clock / 0.28, 0, 1))
    local left = string.format('Space · %s', tostring(st.today or os.date('%d.%m.%Y')))
    local status = tostring(st.status or '')
    if st.err and st.err ~= '' then status = status .. ' · ' .. st.err end
    dl:AddText(imgui.ImVec2(min.x, min.y + 6), u32(imgui, with_a(imgui, C.soft, head_a)), left)
    local lx = min.x + imgui.CalcTextSize(left).x + 10
    dl:AddText(imgui.ImVec2(lx, min.y + 6), u32(imgui, with_a(imgui, C.muted, head_a)), status)

    local bw = 96
    imgui.SetCursorScreenPos(imgui.ImVec2(min.x + avail - bw, min.y))
    soft_button(P, '##org_ref', 'Обновить', bw, row_h, 'ghost', function()
      reset_tab_anim()
      if P.events_fetch then P.events_fetch(true) end
    end)
    imgui.SetCursorScreenPos(imgui.ImVec2(min.x, min.y + row_h + 8))
    imgui.Dummy(imgui.ImVec2(0, 0))
  end

  do
    local day_title = (day_ago == 1) and 'Вчера' or 'Сегодня'
    local switch_to = (day_ago == 1) and 'сегодня' or 'вчера'
    local label = string.format('%s · %d МП', day_title, day_mp)
    local lw = imgui.CalcTextSize(label).x + 4
    if imgui.InvisibleButton('##org_day', imgui.ImVec2(lw, 16)) then
      anim.org_day = (day_ago == 1) and 0 or 1
      reset_tab_anim()
    end
    local dmin = imgui.GetItemRectMin()
    local dh = toward(anim.hover, '##org_day', imgui.IsItemHovered() and 1 or 0, 14, dt)
    imgui.GetWindowDrawList():AddText(dmin, u32(imgui, mix(imgui, C.muted, C.accent, 0.35 + 0.65 * dh)), label)
    imgui.SameLine(0, 8)
    local sw = imgui.CalcTextSize(switch_to).x + 6
    if imgui.InvisibleButton('##org_day_sw', imgui.ImVec2(sw, 16)) then
      anim.org_day = (day_ago == 1) and 0 or 1
      reset_tab_anim()
    end
    local smin = imgui.GetItemRectMin()
    local sh = toward(anim.hover, '##org_day_sw', imgui.IsItemHovered() and 1 or 0, 14, dt)
    imgui.GetWindowDrawList():AddText(smin, u32(imgui, mix(imgui, C.muted, C.accent, sh)), switch_to)

    imgui.SameLine()
    local tw = imgui.CalcTextSize('сброс').x + 8
    imgui.SetCursorPosX(math.max(imgui.GetCursorPosX(), avail - tw - 4))
    if imgui.InvisibleButton('##org_reset', imgui.ImVec2(tw, 16)) then
      if P.events_reset_orgs then P.events_reset_orgs(); P.chat('Следящие восстановлены') end
    end
    local rmin = imgui.GetItemRectMin()
    local rh = toward(anim.hover, '##org_reset', imgui.IsItemHovered() and 1 or 0, 14, dt)
    imgui.GetWindowDrawList():AddText(rmin, u32(imgui, mix(imgui, C.muted, C.accent, rh)), 'сброс')
  end
  imgui.Dummy(imgui.ImVec2(0, 4))

  local bodyH = math.max(200, imgui.GetContentRegionAvail().y - 4)

  local function draw_week_cards(rows, id_prefix, hide_fn, appear_off, accent_ok)
    if #rows == 0 then
      imgui.TextColored(C.muted, (st.status == 'loading') and 'Загрузка…' or 'Нет данных')
      return
    end
    for i = 1, #rows do
      local e = rows[i]
      local row_h = 72
      local btn = 22
      local w = imgui.GetContentRegionAvail().x
      local text_w = math.max(40, w - btn - 8)
      local base = imgui.GetCursorScreenPos()
      local appear, slide, dy = row_appear((appear_off or 0) + i)
      local min = imgui.ImVec2(base.x + slide, base.y + dy)
      local dl = imgui.GetWindowDrawList()
      local id = id_prefix .. i

      imgui.SetCursorScreenPos(base)
      imgui.InvisibleButton(id, imgui.ImVec2(text_w, row_h))
      local hv = toward(anim.hover, id, imgui.IsItemHovered() and 1 or 0, 14, dt)

      local fill = with_a(imgui, C.card, (0.30 + 0.16 * hv) * appear)
      if hv > 0.08 then
        soft_shadow(dl, imgui, min, imgui.ImVec2(min.x + w, min.y + row_h), 8, 0.4 * hv * appear)
      end
      dl:AddRectFilled(min, imgui.ImVec2(min.x + w, min.y + row_h), u32(imgui, fill), 8)
      dl:AddRect(
        min, imgui.ImVec2(min.x + w, min.y + row_h),
        u32(imgui, stroke(imgui, C, (0.10 + 0.16 * hv) * appear)), 8, imgui.DrawCornerFlags.All, 1
      )
      if accent_ok and (e.week_n or 0) > 0 then
        dl:AddRectFilled(
          imgui.ImVec2(min.x + 1, min.y + 8), imgui.ImVec2(min.x + 3, min.y + row_h - 8),
          u32(imgui, with_a(imgui, C.ok, 0.7 * appear)), 2
        )
      end

      local th = imgui.GetTextLineHeight()
      local pad = 10
      local name = tostring(e.name or '')
      local clip_r = min.x + text_w - 4
      pcall(function()
        dl:PushClipRect(imgui.ImVec2(min.x + pad, min.y), imgui.ImVec2(clip_r, min.y + row_h), true)
      end)
      dl:AddText(imgui.ImVec2(min.x + pad, min.y + 6), u32(imgui, with_a(imgui, C.soft, appear)), name)
      local line1 = string.format(
        'Неделя · %d МП · %d азп · %s',
        e.week_n or 0, e.week_azp or 0, tostring(e.week_pay_s or '0')
      )
      local line2 = string.format(
        'Прошлая · %d МП · %d азп · %s',
        e.prev_n or 0, e.prev_azp or 0, tostring(e.prev_pay_s or '0')
      )
      local line3 = string.format('За всё время · %d МП', e.all_n or 0)
      dl:AddText(imgui.ImVec2(min.x + pad, min.y + 6 + th + 2), u32(imgui, with_a(imgui, C.accent, 0.9 * appear)), line1)
      dl:AddText(imgui.ImVec2(min.x + pad, min.y + 6 + th * 2 + 4), u32(imgui, with_a(imgui, C.muted, appear)), line2)
      dl:AddText(imgui.ImVec2(min.x + pad, min.y + 6 + th * 3 + 6), u32(imgui, with_a(imgui, C.muted, 0.85 * appear)), line3)
      pcall(function() dl:PopClipRect() end)

      draw_hide_x(
        id_prefix .. 'x' .. i, e.key, e.name, base,
        base.x + text_w + 2, base.y + (row_h - btn) * 0.5,
        btn, appear, dy, hide_fn
      )

      imgui.SetCursorScreenPos(imgui.ImVec2(base.x, base.y + row_h + 4))
      imgui.Dummy(imgui.ImVec2(0, 0))
    end
  end

  -- всё ниже в одном скролле, чтобы «Добавить» не уезжало за край
  imgui.BeginChild('##org_page', imgui.ImVec2(avail, bodyH), false)

  -- ===== день (сегодня / вчера) =====
  do
    local day_title = (day_ago == 1) and 'Вчера' or 'Сегодня'
    imgui.TextColored(C.muted, string.format('Следящие · %s', day_title))
  end
  if #list == 0 then
    local empty = (day_ago == 1) and 'Вчера никого' or 'Сегодня пока никого'
    imgui.TextColored(C.muted, (st.status == 'loading') and 'Загрузка…' or empty)
  else
    draw_day_person_rows(list, '##orgd', P.events_hide_org, 0)
  end

  imgui.Dummy(imgui.ImVec2(0, 8))

  -- ===== помощники: счётчики неделя / всё время =====
  do
    local range = ''
    if hmeta.week_from then
      range = string.format(' · %s–%s', tostring(hmeta.week_from), tostring(hmeta.week_to))
    end
    imgui.TextColored(C.muted, string.format('Помощники · %d%s', #help_stats, range))
    imgui.SameLine(0, 8)
    imgui.TextColored(C.muted, 'неделя')
    imgui.SameLine(0, 4)
    imgui.TextColored(C.accent, '·')
    imgui.SameLine(0, 4)
    imgui.TextColored(C.muted, 'всё время')
    imgui.SameLine()
    local tw = imgui.CalcTextSize('сброс').x + 8
    local cur = imgui.GetCursorPosX()
    imgui.SetCursorPosX(math.max(cur, avail - tw - 8))
    if imgui.InvisibleButton('##help_reset', imgui.ImVec2(tw, 16)) then
      if P.events_reset_helpers then P.events_reset_helpers(); P.chat('Помощники сброшены') end
    end
    local rmin = imgui.GetItemRectMin()
    local rh = toward(anim.hover, '##help_reset', imgui.IsItemHovered() and 1 or 0, 14, dt)
    imgui.GetWindowDrawList():AddText(rmin, u32(imgui, mix(imgui, C.muted, C.accent, rh)), 'сброс')
  end
  draw_helper_rows(help_stats, '##helps', math.max(#list, 1))

  imgui.Dummy(imgui.ImVec2(0, 10))

  -- ===== все следящие + добавление =====
  do
    imgui.TextColored(C.muted, string.format('Все следящие · %d', #stats))
    if smeta.week_from then
      imgui.SameLine(0, 10)
      imgui.TextColored(
        C.muted,
        string.format('%s–%s · прошл. %s–%s',
          tostring(smeta.week_from), tostring(smeta.week_to),
          tostring(smeta.prev_from), tostring(smeta.prev_to))
      )
    end
  end

  if P.ui.org_add then
    local add_h = 28
    local add_bw = 78
    local flags = 0
    pcall(function() flags = imgui.InputTextFlags.EnterReturnsTrue end)
    local function do_add_org()
      if not P.events_add_org_from_buf then return end
      local ok, err, name = P.events_add_org_from_buf()
      if ok then
        P.chat('В следящие: ' .. tostring(name))
      elseif err == 'exists' then
        P.chat('Уже в списке')
      elseif err == 'empty' then
        P.chat('Введите ник')
      end
    end
    local field_w = math.max(80, imgui.GetContentRegionAvail().x - add_bw - 10)
    imgui.PushItemWidth(field_w)
    local enter = imgui.InputText('##org_add_in', P.ui.org_add, 96, flags)
    imgui.PopItemWidth()
    imgui.SameLine(0, 6)
    soft_button(P, '##org_add_ok', 'Добавить', add_bw, add_h, 'primary', do_add_org)
    if enter then do_add_org() end
    imgui.Dummy(imgui.ImVec2(0, 4))
  end

  draw_week_cards(
    stats, '##orgs', P.events_hide_org,
    math.max(#list, 1) + math.max(#help_stats, 1),
    true
  )

  imgui.EndChild()
end

local function draw_utils(P)
  local imgui, C, ui = P.imgui, P.C, P.ui
  local avail = imgui.GetContentRegionAvail().x
  local gap = 8
  local leftW = math.floor(avail * 0.46)
  local rightW = avail - leftW - gap
  local radius = (ui.utils_radius and ui.utils_radius[0]) or 50
  local nearby = P.get_nearby_players(radius, 28) or {}
  local selfi = P.get_self_info and P.get_self_info() or {}
  local sel = P.get_utils_sel and P.get_utils_sel() or -1
  local sel_nick = nil
  for i = 1, #nearby do
    if nearby[i].id == sel then sel_nick = nearby[i].nick break end
  end

  imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing, imgui.ImVec2(8, 6))

  -- шапка
  do
    local appear, slide = next_appear()
    local w = avail
    local h = 52
    local base = imgui.GetCursorScreenPos()
    local min = imgui.ImVec2(base.x + slide, base.y)
    local max = imgui.ImVec2(min.x + w, min.y + h)
    local dl = imgui.GetWindowDrawList()
    soft_shadow(dl, imgui, min, max, 11, 0.30 * appear)
    dl:AddRectFilled(min, max, u32(imgui, with_a(imgui, C.card, 0.28 * appear)), 11)
    dl:AddRect(min, max, u32(imgui, fade_a(imgui, stroke(imgui, C, 0.12), appear)), 11, imgui.DrawCornerFlags.All, 1)
    local nick = P.to_ui and P.to_ui(selfi.nick or '-') or tostring(selfi.nick or '-')
    local line1 = string.format('Я · %s  [%s]', nick, tostring(selfi.id or '-'))
    local line2 = string.format(
      'XYZ %.0f %.0f %.0f · HP %.0f · ARM %.0f · ping %s',
      selfi.x or 0, selfi.y or 0, selfi.z or 0,
      selfi.hp or 0, selfi.armor or 0, tostring(selfi.ping or 0)
    )
    dl:AddText(imgui.ImVec2(min.x + 14, min.y + 9), u32(imgui, fade_a(imgui, C.soft, appear)), line1)
    dl:AddText(imgui.ImVec2(min.x + 14, min.y + 29), u32(imgui, fade_a(imgui, C.muted, appear)), line2)

    local bw = 88
    imgui.SetCursorScreenPos(imgui.ImVec2(base.x + w - bw - 10, base.y + 11))
    soft_button(P, '##u_copy_me', 'Копир. ID', bw, 30, 'ghost', function()
      if selfi.id ~= nil and P.copy_text(tostring(selfi.id)) then
        P.chat('ID скопирован: ' .. tostring(selfi.id))
      end
    end)
    imgui.SetCursorScreenPos(imgui.ImVec2(base.x, base.y + h + 8))
  end

  if ui.utils_radius then
    local rh = 30
    local base = imgui.GetCursorScreenPos()
    local dl = imgui.GetWindowDrawList()
    dl:AddText(imgui.ImVec2(base.x, base.y + 6), u32(imgui, C.muted), 'Радиус')
    imgui.SetCursorScreenPos(imgui.ImVec2(base.x + 62, base.y))
    local min = imgui.GetCursorScreenPos()
    if imgui.InvisibleButton('##u_rad_m', imgui.ImVec2(28, rh)) then
      ui.utils_radius[0] = math.max(10, ui.utils_radius[0] - 5)
    end
    dl:AddRectFilled(min, imgui.ImVec2(min.x + 28, min.y + rh), u32(imgui, with_a(imgui, C.soft, 0.07)), 7)
    dl:AddText(imgui.ImVec2(min.x + 9, min.y + 6), u32(imgui, C.soft), '-')
    imgui.SameLine(0, 5)
    min = imgui.GetCursorScreenPos()
    local vs = tostring(ui.utils_radius[0]) .. ' м'
    local tw = math.max(52, imgui.CalcTextSize(vs).x + 14)
    dl:AddRectFilled(min, imgui.ImVec2(min.x + tw, min.y + rh), u32(imgui, with_a(imgui, C.accent, 0.12)), 7)
    dl:AddText(imgui.ImVec2(min.x + 7, min.y + 6), u32(imgui, C.soft), vs)
    imgui.Dummy(imgui.ImVec2(tw, rh))
    imgui.SameLine(0, 5)
    min = imgui.GetCursorScreenPos()
    if imgui.InvisibleButton('##u_rad_p', imgui.ImVec2(28, rh)) then
      ui.utils_radius[0] = math.min(200, ui.utils_radius[0] + 5)
    end
    dl:AddRectFilled(min, imgui.ImVec2(min.x + 28, min.y + rh), u32(imgui, with_a(imgui, C.soft, 0.07)), 7)
    dl:AddText(imgui.ImVec2(min.x + 8, min.y + 6), u32(imgui, C.soft), '+')
    imgui.SetCursorScreenPos(imgui.ImVec2(base.x, base.y + rh + 8))
  end

  local bodyH = math.max(160, imgui.GetContentRegionAvail().y)
  panel_begin(P, '##u_near', leftW, bodyH)
  imgui.TextColored(C.muted, string.format('Рядом (%d)', #nearby))
  imgui.Dummy(imgui.ImVec2(0, 4))
  imgui.BeginChild('##u_near_list', imgui.ImVec2(leftW - 30, bodyH - 42), false)
  if #nearby == 0 then
    imgui.TextColored(C.muted, 'Никого в радиусе')
  else
    for i = 1, #nearby do
      local p = nearby[i]
      local row_h = 38
      local w = imgui.GetContentRegionAvail().x
      local appear, slide = next_appear()
      local base = imgui.GetCursorScreenPos()
      local min = imgui.ImVec2(base.x + slide, base.y)
      local id = '##up' .. tostring(p.id)
      imgui.SetCursorScreenPos(base)
      local clicked = imgui.InvisibleButton(id, imgui.ImVec2(w, row_h))
      local hv = toward(anim.hover, id, imgui.IsItemHovered() and 1 or 0, 14, imgui.GetIO().DeltaTime)
      local active = (sel == p.id)
      local dl = imgui.GetWindowDrawList()
      local max = imgui.ImVec2(min.x + w, min.y + row_h)
      local fill_a = (active and 0.16 or (0.04 + 0.08 * hv)) * appear
      local fill = active and with_a(imgui, C.accent, fill_a) or with_a(imgui, C.soft, fill_a)
      dl:AddRectFilled(min, max, u32(imgui, fill), 8)
      if active then
        dl:AddRectFilled(
          imgui.ImVec2(min.x + 2, min.y + 9), imgui.ImVec2(min.x + 5, min.y + row_h - 9),
          u32(imgui, fade_a(imgui, C.accent, appear)), 2
        )
      end
      local title = string.format('%s  [%d]', p.nick, p.id)
      local meta = string.format('%.0fm · HP %.0f', p.dist, p.hp)
      local th = imgui.GetTextLineHeight()
      dl:AddText(imgui.ImVec2(min.x + 12, min.y + 5), u32(imgui, fade_a(imgui, C.soft, appear)), title)
      dl:AddText(imgui.ImVec2(min.x + 12, min.y + 5 + th), u32(imgui, fade_a(imgui, C.muted, appear)), meta)
      if clicked then P.set_utils_sel(p.id) end
      imgui.SetCursorScreenPos(imgui.ImVec2(base.x, base.y + row_h + 3))
      imgui.Dummy(imgui.ImVec2(0, 0))
    end
  end
  imgui.EndChild()
  panel_end(P)

  imgui.SameLine(0, gap)
  imgui.BeginChild('##u_actions', imgui.ImVec2(rightW, bodyH), false)

  local who = (sel >= 0)
    and string.format('%s [%d]', sel_nick or ('id ' .. sel), sel)
    or 'игрок не выбран'
  imgui.TextColored(C.muted, 'Выбран · ')
  imgui.SameLine(0, 0)
  imgui.TextColored(C.soft, who)
  imgui.Dummy(imgui.ImVec2(0, 2))

  local cw = (imgui.GetContentRegionAvail().x - 6) / 2
  local ch = 34
  soft_button(P, '##u_goto', 'Goto', cw, ch, 'ghost', function() P.utils_run_cmd('/goto {id}') end)
  imgui.SameLine(0, 6)
  soft_button(P, '##u_get', 'GetHere', cw, ch, 'ghost', function() P.utils_run_cmd('/gethere {id}') end)
  soft_button(P, '##u_st', 'Stats', cw, ch, 'ghost', function() P.utils_run_cmd('/stats {id}') end)
  imgui.SameLine(0, 6)
  soft_button(P, '##u_fr', 'Freeze', cw, ch, 'ghost', function() P.utils_run_cmd('/freeze {id}') end)
  soft_button(P, '##u_cid', 'Копир. ID', cw, ch, 'ghost', function()
    if sel < 0 then P.chat('Сначала выбери игрока') return end
    if P.copy_text(tostring(sel)) then P.chat('ID скопирован: ' .. tostring(sel)) end
  end)
  imgui.SameLine(0, 6)
  soft_button(P, '##u_paste', 'ID из буфера', cw, ch, 'ghost', function()
    if P.paste_id_from_clip then P.paste_id_from_clip() end
  end)

  imgui.Dummy(imgui.ImVec2(0, 4))
  imgui.TextColored(C.muted, 'Личное сообщение (PM)')
  if ui.utils_pm then
    if anim.focus_pm then
      pcall(function() imgui.SetKeyboardFocusHere(0) end)
      anim.focus_pm = false
    end
    local flags = 0
    pcall(function() flags = imgui.InputTextFlags.EnterReturnsTrue end)
    imgui.PushItemWidth(-1)
    local enter = imgui.InputText('##u_pm', ui.utils_pm, 128, flags)
    imgui.PopItemWidth()
    soft_button(P, '##u_pm_send', 'Отправить PM', -1, 32, 'primary', function()
      if P.send_pm_to_sel then P.send_pm_to_sel() end
    end)
    if enter and P.send_pm_to_sel then P.send_pm_to_sel() end
    imgui.TextColored(C.muted, 'Выбери игрока → напиши текст → Enter')
  end

  imgui.Dummy(imgui.ImVec2(0, 4))
  imgui.TextColored(C.muted, 'Заметка')
  if ui.utils_note then
    imgui.PushItemWidth(-1)
    imgui.InputText('##u_note', ui.utils_note, 128)
    imgui.PopItemWidth()
    soft_button(P, '##u_note_save', 'Сохранить заметку', -1, 30, 'ghost', function()
      if P.save_note_for_sel then P.save_note_for_sel() end
    end)
  end

  imgui.Dummy(imgui.ImVec2(0, 4))
  imgui.TextColored(C.muted, 'Избранное')
  local favs = P.get_utils_favs and P.get_utils_favs() or {}
  if #favs == 0 then
    imgui.TextColored(C.muted, 'пусто — добавь команду ниже')
  else
    for i = 1, #favs do
      local cmd = favs[i]
      local label = cmd
      if #label > 18 then label = label:sub(1, 17) .. '…' end
      local bw = imgui.GetContentRegionAvail().x - 34
      soft_button(P, '##ufav' .. i, label, bw, 30, 'ghost', function()
        P.utils_run_cmd(cmd)
      end)
      imgui.SameLine(0, 4)
      soft_button(P, '##ufavx' .. i, '×', 30, 30, 'ghost', function()
        if P.fav_remove and P.fav_remove(i) then P.chat('Убрано из избранного') end
      end)
    end
  end

  imgui.Dummy(imgui.ImVec2(0, 4))
  imgui.TextColored(C.muted, 'Своя команда')
  if ui.utils_cmd then
    imgui.PushItemWidth(-1)
    imgui.InputText('##u_cmd', ui.utils_cmd, 96)
    imgui.PopItemWidth()
    local sw = (imgui.GetContentRegionAvail().x - 6) / 2
    soft_button(P, '##u_send', 'Отправить', sw, 34, 'primary', function()
      local raw = P.read_cmd_buf and P.read_cmd_buf() or ''
      if raw == '' then return end
      P.utils_run_cmd(raw)
    end)
    imgui.SameLine(0, 6)
    soft_button(P, '##u_favadd', '+ Избранное', sw, 34, 'ghost', function()
      local raw = P.read_cmd_buf and P.read_cmd_buf() or ''
      if raw == '' then P.chat('Введи команду') return end
      local ok, err = P.fav_add(raw)
      if ok then P.chat('В избранном') else P.chat(tostring(err or 'не добавлено')) end
    end)
    imgui.TextColored(C.muted, '{id} = выбранный игрок')
  end

  imgui.Dummy(imgui.ImVec2(0, 4))
  imgui.TextColored(C.muted, 'История')
  local hist = P.get_utils_hist and P.get_utils_hist() or {}
  if #hist == 0 then
    imgui.TextColored(C.muted, 'пока пусто')
  else
    for i = 1, math.min(#hist, 10) do
      local cmd = hist[i]
      local label = cmd
      if #label > 22 then label = label:sub(1, 21) .. '…' end
      soft_button(P, '##uhist' .. i, label, -1, 28, 'ghost', function()
        if P.write_cmd_buf then P.write_cmd_buf(cmd) end
        P.utils_run_cmd(cmd)
      end)
    end
  end

  imgui.EndChild()
  imgui.PopStyleVar()
end

local function status_chip(P, w, h, title, detail, col)
  local imgui, C = P.imgui, P.C
  local appear, slide, dy = next_appear()
  local base = imgui.GetCursorScreenPos()
  local min = imgui.ImVec2(base.x + slide, base.y + dy)
  local dl = imgui.GetWindowDrawList()
  local max = imgui.ImVec2(min.x + w, min.y + h)
  soft_shadow(dl, imgui, min, max, 12, 0.35 * appear)
  dl:AddRectFilled(min, max, u32(imgui, with_a(imgui, C.card, 0.30 * appear)), 12)
  dl:AddRect(min, max, u32(imgui, fade_a(imgui, stroke(imgui, C, 0.12), appear)), 12, imgui.DrawCornerFlags.All, 1)
  dl:AddCircleFilled(imgui.ImVec2(min.x + 18, min.y + 22), 5, u32(imgui, fade_a(imgui, col, appear)), 12)
  dl:AddCircle(imgui.ImVec2(min.x + 18, min.y + 22), 8, u32(imgui, with_a(imgui, col, 0.28 * appear)), 12, 1.2)
  dl:AddText(imgui.ImVec2(min.x + 34, min.y + 12), u32(imgui, fade_a(imgui, C.muted, appear)), title)
  dl:AddText(imgui.ImVec2(min.x + 34, min.y + 32), u32(imgui, fade_a(imgui, C.soft, appear)), detail)
  imgui.Dummy(imgui.ImVec2(w, h))
end

local function tip_card(P, line1, line2)
  local imgui, C = P.imgui, P.C
  local appear, slide, dy = next_appear()
  local w = imgui.GetContentRegionAvail().x
  local h = 54
  local base = imgui.GetCursorScreenPos()
  local min = imgui.ImVec2(base.x + slide, base.y + dy)
  local dl = imgui.GetWindowDrawList()
  local max = imgui.ImVec2(min.x + w, min.y + h)
  soft_shadow(dl, imgui, min, max, 11, 0.45 * appear)
  dl:AddRectFilled(min, max, u32(imgui, with_a(imgui, C.soft, 0.04 * appear)), 11)
  dl:AddRect(min, max, u32(imgui, fade_a(imgui, stroke(imgui, C, 0.12), appear)), 11, imgui.DrawCornerFlags.All, 1)
  dl:AddRectFilled(imgui.ImVec2(min.x, min.y + 10), imgui.ImVec2(min.x + 3, max.y - 10), u32(imgui, with_a(imgui, C.accent, 0.55 * appear)), 2)
  dl:AddText(imgui.ImVec2(min.x + 16, min.y + 12), u32(imgui, fade_a(imgui, C.muted, appear)), line1)
  dl:AddText(imgui.ImVec2(min.x + 16, min.y + 30), u32(imgui, fade_a(imgui, C.muted, appear)), line2)
  imgui.Dummy(imgui.ImVec2(0, h))
end

local function draw_clips(P)
  local imgui, C, ui, cfg = P.imgui, P.C, P.ui, P.cfg
  local st = P.ipc.read_status()
  local alive = P.ipc.helper_alive(5)
  local avail = imgui.GetContentRegionAvail().x
  local pageH = imgui.GetContentRegionAvail().y

  imgui.BeginChild('##cl_page', imgui.ImVec2(avail, pageH), false)

  -- статус-ряд: 3 чипа
  local gap = 10
  local chip_w = (avail - gap * 2) / 3
  local chip_h = 58
  local rec = alive and st and st.recording
  local tok = alive and st and st.tg_ok

  status_chip(P, chip_w, chip_h,
    'Хелпер',
    alive and 'онлайн' or 'не загружен',
    alive and C.ok or C.warn)
  imgui.SameLine(0, gap)
  status_chip(P, chip_w, chip_h,
    'Запись',
    rec and P.format_clip_dur(st.sec) or 'выкл',
    rec and C.bad or C.muted)
  imgui.SameLine(0, gap)
  status_chip(P, chip_w, chip_h,
    'Telegram',
    (not alive and '—') or (tok and 'готов' or 'нет связи'),
    (alive and tok) and C.ok or C.warn)

  imgui.Dummy(imgui.ImVec2(0, 14))

  -- управление + тоггл внутри одной карточки
  local box_h = 236
  panel_begin(P, '##cl_ctrl', avail, box_h)
  imgui.TextColored(C.muted, 'Управление ShadowPlay')
  imgui.Dummy(imgui.ImVec2(0, 10))

  local inner = imgui.GetContentRegionAvail().x
  local gw = (inner - 8) / 2
  soft_button(P, '##cl_rec', 'Старт / стоп', gw, 42, 'ghost', function() P.ipc.write_cmd('record') end)
  imgui.SameLine(0, 8)
  soft_button(P, '##cl_rw', 'Instant Replay', gw, 42, 'ghost', function() P.ipc.write_cmd('rewind') end)

  imgui.Dummy(imgui.ImVec2(0, 10))
  local dragOn = st and st.drag
  soft_button(P, '##cl_drag', dragOn and 'Закрепить REC' or 'Двигать REC', -1, 40, 'primary', function()
    P.ipc.write_cmd('drag')
  end)

  imgui.Dummy(imgui.ImVec2(0, 8))
  toggle_row(P, '##t_clips2', 'Спрашивать в TG перед отправкой', ui.send_clips)
  if ui.send_clips[0] ~= cfg.clips then P.clips_set_enabled(ui.send_clips[0]) end
  panel_end(P)

  imgui.Dummy(imgui.ImVec2(0, 12))
  tip_card(P, 'F12 — запись ShadowPlay', 'Клип >45 МБ автоматически сжимается под Telegram')

  imgui.EndChild()
end

local function draw_themes(P)
  local imgui, C, cfg = P.imgui, P.C, P.cfg
  P.ensure_theme_textures()
  local gap, cols = 12, 3
  local avail = imgui.GetContentRegionAvail().x
  local card_w = (avail - gap * (cols - 1)) / cols
  local card_h = 124
  local cur = nil
  local t = imgui.GetTime()
  local dt = imgui.GetIO().DeltaTime

  for i, th in ipairs(P.THEMES) do
    local selected = (cfg.theme == th.id)
    if selected then cur = th end
    local appear, slide, dy = next_appear()
    local base = imgui.GetCursorScreenPos()
    local min = imgui.ImVec2(base.x + slide, base.y + dy)
    imgui.SetCursorScreenPos(base)
    if imgui.InvisibleButton('##theme_' .. th.id, imgui.ImVec2(card_w, card_h)) then
      P.apply_theme(th.id)
      P.save_ini()
      P.chat('Тема: ' .. th.title)
    end
    local hovered = imgui.IsItemHovered()
    local hv = toward(anim.hover, 'th_' .. th.id, (hovered or selected) and 1 or 0, 12, dt)
    local max = imgui.ImVec2(min.x + card_w, min.y + card_h)
    local dl = imgui.GetWindowDrawList()
    local tex = P.theme_textures[th.id]

    draw_card(dl, imgui, C, min, max, 12, hv)
    local pad = 5
    local img_a = imgui.ImVec2(min.x + pad, min.y + pad)
    local img_b = imgui.ImVec2(max.x - pad, max.y - 32)
    if tex then
      dl:AddImageRounded(tex, img_a, img_b, imgui.ImVec2(0, 0), imgui.ImVec2(1, 1),
        u32(imgui, imgui.ImVec4(1, 1, 1, (0.70 + 0.30 * hv) * appear)), 10, imgui.DrawCornerFlags.All)
    else
      dl:AddRectFilled(img_a, img_b, u32(imgui, fade_a(imgui, C.card, appear)), 10)
    end

    if selected then
      local glow = (0.35 + 0.2 * math.sin(t * 2.5)) * appear
      dl:AddRect(min, max, u32(imgui, with_a(imgui, C.accent, glow)), 12, imgui.DrawCornerFlags.All, 2)
      dl:AddRect(
        imgui.ImVec2(min.x - 2, min.y - 2), imgui.ImVec2(max.x + 2, max.y + 2),
        u32(imgui, with_a(imgui, C.accent, 0.18 * appear)), 13, imgui.DrawCornerFlags.All, 1
      )
    end

    local label = th.title
    local ts = imgui.CalcTextSize(label)
    dl:AddText(imgui.ImVec2(min.x + (card_w - ts.x) * 0.5, max.y - 23),
      u32(imgui, fade_a(imgui, selected and C.accent or C.soft, appear)), label)

    if (i % cols) ~= 0 and i < #P.THEMES then
      imgui.SameLine(0, gap)
    else
      imgui.Dummy(imgui.ImVec2(0, gap))
    end
  end
  if cur then
    local ha = ease_out(clamp(anim.tab_clock / 0.35, 0, 1))
    imgui.TextColored(fade_a(imgui, C.accent, ha), cur.title)
    imgui.SameLine(0, 10)
    imgui.TextColored(fade_a(imgui, C.muted, ha), cur.desc)
  end
end

local function draw_settings(P)
  local imgui, C, ui = P.imgui, P.C, P.ui
  local avail = imgui.GetContentRegionAvail().x
  local gap = 12
  local leftW = math.floor((avail - gap) * 0.5)
  local rightW = avail - leftW - gap
  local ha = ease_out(clamp((anim.tab_clock or 0) / 0.4, 0, 1))

  -- Telegram credentials (публичная версия)
  if ui.bot_token and ui.chat_id then
    imgui.TextColored(fade_a(imgui, C.muted, ha), 'Telegram')
    imgui.Dummy(imgui.ImVec2(0, 2))
    imgui.TextColored(fade_a(imgui, C.soft, ha), 'Bot Token')
    local pw = 0
    pcall(function() pw = imgui.InputTextFlags.Password end)
    imgui.PushItemWidth(-1)
    imgui.InputText('##set_token', ui.bot_token, 192, pw)
    imgui.PopItemWidth()
    imgui.Dummy(imgui.ImVec2(0, 4))
    imgui.TextColored(fade_a(imgui, C.soft, ha), 'Chat ID')
    imgui.PushItemWidth(-1)
    imgui.InputText('##set_chat', ui.chat_id, 64)
    imgui.PopItemWidth()
    local tok_ok = (P.cfg.token or '') ~= '' and (P.cfg.chat_id or '') ~= ''
    -- live preview from buffers after apply is on save; hint only
    imgui.TextColored(
      fade_a(imgui, tok_ok and C.ok or C.warn, ha),
      tok_ok and 'Токен загружен из конфига' or 'Впиши токен и Chat ID, затем Сохранить'
    )
    imgui.Dummy(imgui.ImVec2(0, 8))
  end

  local pageH = math.max(140, imgui.GetContentRegionAvail().y - 58)

  imgui.BeginChild('##set_l', imgui.ImVec2(leftW, pageH), false)
  setting_row(P, '##qfrom', 'Пуш если очередь >=', ui.queue_from, 1, 50)
  setting_row(P, '##qafk', 'Пуш при AFK если очередь >=', ui.queue_afk_from, 1, 30)
  imgui.EndChild()

  imgui.SameLine(0, gap)
  imgui.BeginChild('##set_r', imgui.ImVec2(rightW, pageH), false)
  setting_row(P, '##afk', 'AFK через, сек', ui.afk_sec, 30, 300)
  setting_row(P, '##cd', 'Пауза между пушами, сек', ui.cooldown, 0, 30)
  imgui.Dummy(imgui.ImVec2(0, 6))
  imgui.TextColored(fade_a(imgui, C.muted, ha), string.format('Форм-команд Tools: %d', P.get_form_cmds()))
  imgui.TextColored(fade_a(imgui, C.muted, ha), string.format('Размер: %d×%d', tonumber(P.cfg.win_w) or 0, tonumber(P.cfg.win_h) or 0))
  imgui.TextColored(fade_a(imgui, C.muted, ha), 'Тяни угол справа снизу')
  imgui.EndChild()

  -- автообновление
  do
    local st = P.get_update_state and P.get_update_state() or nil
    local ver = tostring(P.SCRIPT_VERSION or '?')
    local status = st and st.status or 'idle'
    local msg = st and tostring(st.msg or '') or ''
    local remote = st and tostring(st.remote or '') or ''
    local line
    if status == 'disabled' then
      line = 'Автообновление: не настроено'
    elseif status == 'checking' then
      line = 'Проверка обновлений…'
    elseif status == 'updating' then
      line = msg ~= '' and msg or ('Скачиваю ' .. remote)
    elseif status == 'ok' then
      line = 'Актуально · ' .. ver
    elseif status == 'error' then
      line = 'Ошибка: ' .. (msg ~= '' and msg or 'сеть')
    elseif status == 'ready' then
      line = msg ~= '' and msg or ('Готово · ' .. remote)
    else
      line = 'Версия ' .. ver
    end
    imgui.Dummy(imgui.ImVec2(0, 6))
    imgui.TextColored(fade_a(imgui, C.muted, ha), 'Обновления')
    local col = C.soft
    if status == 'ok' then col = C.ok
    elseif status == 'error' then col = C.warn
    elseif status == 'updating' or status == 'checking' then col = C.accent
    end
    imgui.TextColored(fade_a(imgui, col, ha), line)
  end

  local bw = (imgui.GetContentRegionAvail().x - 10) / 3
  soft_button(P, '##save', 'Сохранить', bw, 44, 'primary', function()
    P.apply_ui_to_cfg()
    P.save_ini()
    P.clips_set_enabled(P.ui.send_clips[0])
    local ok = (P.cfg.token or '') ~= '' and (P.cfg.chat_id or '') ~= ''
    P.chat(ok and 'Настройки сохранены' or 'Сохранено, но токен/Chat ID пустые')
  end)
  imgui.SameLine(0, 10)
  soft_button(P, '##reset', 'Сбросить', bw, 44, 'ghost', function()
    P.load_ini(); P.load_form_cmds(); P.sync_ui_from_cfg(); P.sync_clips_ui()
    P.chat('Загружено из файла')
  end)
  imgui.SameLine(0, 10)
  soft_button(P, '##upd_chk', 'Проверить', bw, 44, 'ghost', function()
    if P.update_check then P.update_check(true, false) end
  end)
end

local function draw_help(P)
  local imgui, C, ui = P.imgui, P.C, P.ui
  local ha = ease_out(clamp((anim.tab_clock or 0) / 0.4, 0, 1))
  local tickets = (P.help_get_tickets and P.help_get_tickets()) or {}
  local st = (P.help_get_state and P.help_get_state()) or {}
  local sel = (P.help_get_sel and P.help_get_sel()) or { idx = 1 }
  local idx = tonumber(sel.idx) or 1
  if idx < 1 then idx = 1 end
  if #tickets > 0 and idx > #tickets then idx = #tickets end

  if not (P.help_configured and P.help_configured()) then
    imgui.TextColored(fade_a(imgui, C.warn, ha), 'Помощь пока не настроена автором скрипта')
    imgui.TextColored(fade_a(imgui, C.muted, ha), 'После настройки здесь можно отправить вопрос')
    return
  end

  if (P.cfg.chat_id or '') == '' then
    imgui.TextColored(fade_a(imgui, C.warn, ha), 'Укажи Chat ID в Настройках — нужен для ответа')
    imgui.Dummy(imgui.ImVec2(0, 6))
  end

  imgui.TextColored(fade_a(imgui, C.muted, ha), 'Опиши проблему')
  imgui.PushItemWidth(-1)
  local ok_ml = pcall(function()
    imgui.InputTextMultiline('##help_txt', ui.help_text, 1024, imgui.ImVec2(-1, 88))
  end)
  if not ok_ml then
    imgui.InputText('##help_txt', ui.help_text, 1024)
  end
  imgui.PopItemWidth()
  imgui.Dummy(imgui.ImVec2(0, 6))

  local bw = (imgui.GetContentRegionAvail().x - 10) / 2
  soft_button(P, '##help_send', 'Отправить', bw, 40, 'primary', function()
    local text = ''
    if P.read_char_buf then text = P.read_char_buf(ui.help_text) end
    if P.help_send then P.help_send(text) end
  end)
  imgui.SameLine(0, 10)
  soft_button(P, '##help_refresh', 'Обновить', bw, 40, 'ghost', function()
    if P.help_poll_replies then P.help_poll_replies(true) end
  end)

  local status = tostring(st.status or '')
  if status ~= '' then
    imgui.Dummy(imgui.ImVec2(0, 4))
    imgui.TextColored(fade_a(imgui, C.muted, ha), status)
  end

  imgui.Dummy(imgui.ImVec2(0, 10))
  imgui.TextColored(fade_a(imgui, C.soft, ha), string.format('Мои заявки · %d', #tickets))
  imgui.Dummy(imgui.ImVec2(0, 4))

  local listH = math.max(120, imgui.GetContentRegionAvail().y - 8)
  local leftW = math.floor(imgui.GetContentRegionAvail().x * 0.42)
  local rightW = imgui.GetContentRegionAvail().x - leftW - 12

  imgui.BeginChild('##help_list', imgui.ImVec2(leftW, listH), false)
  if #tickets == 0 then
    imgui.TextColored(fade_a(imgui, C.muted, ha), 'Пока пусто')
  else
    for i = #tickets, 1, -1 do
      local t = tickets[i]
      local answered = tostring(t.status or '') == 'answered'
      local title = answered and 'Ответ' or 'Ожидает'
      local preview = tostring(t.text or ''):gsub('\n', ' ')
      if #preview > 36 then preview = preview:sub(1, 35) .. '…' end
      local id = '##ht_' .. tostring(i)
      local active = (i == idx)
      local base = imgui.GetCursorScreenPos()
      local w = imgui.GetContentRegionAvail().x
      local h = 44
      if imgui.InvisibleButton(id, imgui.ImVec2(w, h)) then
        idx = i
        if P.help_set_sel then P.help_set_sel(i) end
      end
      local hv = toward(anim.hover, id, (imgui.IsItemHovered() or active) and 1 or 0, 14, imgui.GetIO().DeltaTime)
      local dl = imgui.GetWindowDrawList()
      local fill = active and with_a(imgui, C.accent, 0.22) or with_a(imgui, C.soft, 0.05 + 0.06 * hv)
      dl:AddRectFilled(base, imgui.ImVec2(base.x + w, base.y + h), u32(imgui, fill), 8)
      dl:AddRect(base, imgui.ImVec2(base.x + w, base.y + h), u32(imgui, stroke(imgui, C, 0.12 + 0.18 * hv)), 8, imgui.DrawCornerFlags.All, 1)
      dl:AddText(imgui.ImVec2(base.x + 10, base.y + 6), u32(imgui, answered and C.ok or C.warn), title)
      dl:AddText(imgui.ImVec2(base.x + 10, base.y + 22), u32(imgui, with_a(imgui, C.muted, 0.95)), preview)
      imgui.Dummy(imgui.ImVec2(0, 4))
    end
  end
  imgui.EndChild()

  imgui.SameLine(0, 12)
  imgui.BeginChild('##help_detail', imgui.ImVec2(rightW, listH), false)
  local cur = tickets[idx]
  if not cur then
    imgui.TextColored(fade_a(imgui, C.muted, ha), 'Выбери заявку слева')
  else
    imgui.TextColored(fade_a(imgui, C.muted, ha), tostring(cur.id or ''))
    imgui.Dummy(imgui.ImVec2(0, 4))
    imgui.TextColored(fade_a(imgui, C.soft, ha), 'Вопрос')
    imgui.TextWrapped(tostring(cur.text or ''))
    imgui.Dummy(imgui.ImVec2(0, 10))
    if tostring(cur.status or '') == 'answered' and tostring(cur.answer or '') ~= '' then
      imgui.TextColored(fade_a(imgui, C.ok, ha), 'Ответ')
      imgui.TextWrapped(tostring(cur.answer or ''))
    else
      imgui.TextColored(fade_a(imgui, C.warn, ha), 'Ожидаем ответ…')
    end
  end
  imgui.EndChild()
end

-- ===================== ROOT =====================

local WIN_OPEN_DUR = 0.42
local WIN_CLOSE_DUR = 0.28

function M.is_visible()
  if anim.win_phase == 'open' then return true end
  return (anim.open or 0) > 0.05
end

function M.request_close(P)
  if P and P.apply_ui_to_cfg then
    pcall(function()
      P.apply_ui_to_cfg()
      if P.clips_set_enabled and P.ui and P.ui.send_clips then
        P.clips_set_enabled(P.ui.send_clips[0])
      end
    end)
  end
  -- закрытие без анимации
  anim.win_phase = 'idle'
  anim.win_t = 0
  anim.closing = false
  anim.open = 0
  if P and P.showMenu then P.showMenu[0] = false end
end

function M.draw(P, player)
  local imgui, bit, C, cfg = P.imgui, P.bit, P.C, P.cfg
  local showMenu = P.showMenu
  -- размер меню из cfg (редактор в Настройках)
  local WIN_W = tonumber(cfg.win_w) or P.WIN_W or 1000
  local WIN_H = tonumber(cfg.win_h) or P.WIN_H or 640
  if WIN_W < 820 then WIN_W = 820 elseif WIN_W > 1400 then WIN_W = 1400 end
  if WIN_H < 520 then WIN_H = 520 elseif WIN_H > 900 then WIN_H = 900 end
  P.WIN_W, P.WIN_H = WIN_W, WIN_H
  local SIDE_W, ROUND = P.SIDE_W, P.ROUND
  local menuTab = P.get_tab()
  local dt = math.min(imgui.GetIO().DeltaTime or 0.016, 0.05)

  if C.dirty or not P.get_style_ready() then
    P.apply_menu_style()
    P.set_style_ready(true)
    C.dirty = false
  end
  player.HideCursor = false

  if anim.tab_was ~= menuTab then
    anim.tab_fade = 0
    anim.tab_was = menuTab
    reset_tab_anim()
  end
  anim.tab_fade = clamp(anim.tab_fade + dt * 6.5, 0, 1)
  anim.tab_clock = (anim.tab_clock or 0) + dt
  anim.appear_i = 0

  -- если открыли меню, а фазу не выставили — стартуем разворот
  if showMenu[0] and anim.win_phase == 'idle' and (anim.open or 0) < 0.99 and not anim.closing then
    anim.win_phase = 'open'
    anim.win_t = 0
  end

  if anim.win_phase == 'open' or anim.win_phase == 'close' then
    anim.win_t = (anim.win_t or 0) + dt
  end

  local open_e, win_alpha, win_h, y_off = 1, 1, WIN_H, 0
  local animating = false

  if anim.win_phase == 'open' then
    local t = clamp(anim.win_t / WIN_OPEN_DUR, 0, 1)
    open_e = ease_out(t)
    win_alpha = clamp(0.20 + 0.80 * open_e, 0, 1)
    win_h = WIN_H * (0.08 + 0.92 * open_e)
    if win_h < 64 then win_h = 64 end
    y_off = (1 - open_e) * 20
    animating = true
    anim.open = open_e
    if t >= 1 then
      anim.win_phase = 'idle'
      anim.open = 1
      open_e, win_alpha, win_h, y_off = 1, 1, WIN_H, 0
      animating = false
    end
  else
    anim.open = showMenu[0] and 1 or 0
    open_e, win_alpha, win_h, y_off = 1, 1, WIN_H, 0
  end

  local io = imgui.GetIO()
  local cx = io.DisplaySize.x * 0.5
  local cy = io.DisplaySize.y * 0.48

  if animating or anim.win_phase ~= 'idle' then
    imgui.SetNextWindowPos(imgui.ImVec2(cx, cy + y_off), imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))
    imgui.SetNextWindowSize(imgui.ImVec2(WIN_W, win_h), imgui.Cond.Always)
  else
    imgui.SetNextWindowPos(imgui.ImVec2(cx, cy), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
    imgui.SetNextWindowSize(imgui.ImVec2(WIN_W, WIN_H), imgui.Cond.Always)
  end
  imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, ROUND)
  imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, win_alpha)

  local winFlags = bit.bor(
    imgui.WindowFlags.NoTitleBar,
    imgui.WindowFlags.NoResize,
    imgui.WindowFlags.NoCollapse,
    imgui.WindowFlags.NoScrollbar
  )
  if win_resize.active or animating then
    winFlags = bit.bor(winFlags, imgui.WindowFlags.NoMove)
  end
  if not imgui.Begin('##arizona_tg_public_menu', showMenu, winFlags) then
    imgui.PopStyleVar(2)
    imgui.End()
    return
  end

  -- жёстко фиксируем size/pos после Begin (SetNext* иногда игнорит уже созданное окно)
  if animating then
    pcall(function()
      imgui.SetWindowSizeVec2(imgui.ImVec2(WIN_W, win_h), imgui.Cond.Always)
      imgui.SetWindowPosVec2(
        imgui.ImVec2(cx - WIN_W * 0.5, cy + y_off - win_h * 0.5),
        imgui.Cond.Always
      )
    end)
  end
  if win_resize.active then
    imgui.SetWindowPosVec2(imgui.ImVec2(win_resize.lock_x, win_resize.lock_y), imgui.Cond.Always)
  end
  if anim.win_phase == 'idle' then
    local wp = imgui.GetWindowPos()
    anim.settled_x, anim.settled_y = wp.x, wp.y
  end

  P.draw_theme_background()
  draw_chrome(P, open_e)

  local q = P.get_queue()
  if q == nil then q = P.read_tools_queue() end
  local afk_now = P.is_afk()
  local idle = P.inactive_sec()
  local me = P.get_my_nick() or '-'
  local token_ok = (cfg.token ~= '' and cfg.chat_id ~= '')

  -- SIDEBAR glass
  do
    local dl = imgui.GetWindowDrawList()
    local wp = imgui.GetWindowPos()
    local side_a = imgui.ImVec2(wp.x, wp.y)
    local side_b = imgui.ImVec2(wp.x + SIDE_W, wp.y + WIN_H)
    dl:AddRectFilled(side_a, side_b, u32(imgui, with_a(imgui, C.side, 0.55)), ROUND,
      bit.bor(imgui.DrawCornerFlags.TopLeft, imgui.DrawCornerFlags.BotLeft))
    dl:AddRectFilledMultiColor(
      side_a, imgui.ImVec2(wp.x + SIDE_W, wp.y + 90),
      u32(imgui, with_a(imgui, C.accent, 0.10)),
      u32(imgui, with_a(imgui, C.accent, 0.10)),
      u32(imgui, imgui.ImVec4(0, 0, 0, 0)),
      u32(imgui, imgui.ImVec4(0, 0, 0, 0))
    )
  end

  imgui.BeginChild('##sidebar', imgui.ImVec2(SIDE_W, WIN_H), false)
  imgui.Dummy(imgui.ImVec2(0, 18))

  -- brand mark (peak A)
  do
    local dl = imgui.GetWindowDrawList()
    local p = imgui.GetCursorScreenPos()
    local cx = p.x + SIDE_W * 0.5 - 10
    local cy = p.y + 14
    draw_brand_mark(dl, imgui, C, cx, cy)
  end
  imgui.Dummy(imgui.ImVec2(0, 42))

  local tab_in_nav = false
  for _, entry in ipairs(NAV) do
    if entry.tab == menuTab then tab_in_nav = true break end
  end

  nav_drag.slots = {}
  for _, entry in ipairs(NAV) do
    nav_item_hit(P, entry)
  end

  -- зажал → водишь вверх/вниз: pill едет за курсором, вкладка меняется без hover-подсветки
  if nav_drag.holding then
    if imgui.IsMouseDown(0) then
      pcall(function() imgui.CaptureMouseFromApp(true) end)
      local my = imgui.GetIO().MousePos.y
      local follow = nav_y_follow(my)
      if follow then anim.nav_target = follow end
      local tab = nav_tab_at_y(my)
      if tab then switch_nav_tab(P, tab) end
    else
      nav_drag.holding = false
      -- отпустили — доснапить pill к активной вкладке
      for i = 1, #nav_drag.slots do
        local s = nav_drag.slots[i]
        if s.tab == P.get_tab() then
          anim.nav_target = s.y
          break
        end
      end
    end
  elseif tab_in_nav then
    for i = 1, #nav_drag.slots do
      local s = nav_drag.slots[i]
      if s.tab == P.get_tab() then
        anim.nav_target = s.y
        break
      end
    end
  end

  if tab_in_nav then
    local speed = nav_drag.holding and 26 or 16
    anim.nav_slide = lerp(
      (anim.nav_slide == 0 and anim.nav_target ~= 0) and anim.nav_target or anim.nav_slide,
      anim.nav_target, clamp(speed * dt, 0, 1)
    )
    draw_nav_pill(P, anim.nav_slide)
  end

  for i = 1, #nav_drag.slots do
    nav_item_draw(P, nav_drag.slots[i])
  end

  -- footer: Themes chip → Telegram → nick
  do
    local chip_w, chip_h = 52, 22
    imgui.SetCursorPosY(WIN_H - 98)
    imgui.SetCursorPosX(14)
    local min = imgui.GetCursorScreenPos()
    local active = (menuTab == 4)
    if imgui.InvisibleButton('##side_themes', imgui.ImVec2(chip_w, chip_h)) then
      P.set_tab(4)
      anim.tab_fade = 0
      reset_tab_anim()
    end
    local hv = toward(anim.hover, '##side_themes', (imgui.IsItemHovered() or active) and 1 or 0, 14, dt)
    local dl = imgui.GetWindowDrawList()
    local max = imgui.ImVec2(min.x + chip_w, min.y + chip_h)
    local fill = active and with_a(imgui, C.accent, 0.28) or with_a(imgui, C.soft, 0.06 + 0.08 * hv)
    dl:AddRectFilled(min, max, u32(imgui, fill), 7)
    dl:AddRect(min, max, u32(imgui, stroke(imgui, C, 0.18 + 0.25 * hv)), 7, imgui.DrawCornerFlags.All, 1)
    icon_themes(dl, imgui, min.x + 11, min.y + chip_h * 0.5, u32(imgui, active and C.soft or C.muted), 5)
    local lab = 'Темы'
    local lts = imgui.CalcTextSize(lab)
    dl:AddText(
      imgui.ImVec2(min.x + 20, min.y + (chip_h - lts.y) * 0.5),
      u32(imgui, active and C.soft or with_a(imgui, C.muted, 0.85)),
      lab
    )
  end

  imgui.SetCursorPosY(WIN_H - 68)
  imgui.SetCursorPosX(14)
  do
    local dl = imgui.GetWindowDrawList()
    local p = imgui.GetCursorScreenPos()
    local okcol = token_ok and C.ok or C.bad
    local pulse = token_ok and (0.65 + 0.35 * math.sin(imgui.GetTime() * 2.2)) or 1
    dl:AddCircleFilled(imgui.ImVec2(p.x + 5, p.y + 7), 4.5, u32(imgui, with_a(imgui, okcol, pulse)), 10)
    if token_ok then
      dl:AddCircle(imgui.ImVec2(p.x + 5, p.y + 7), 7, u32(imgui, with_a(imgui, okcol, 0.25 * pulse)), 10, 1.2)
    end
  end
  imgui.SetCursorPosX(28)
  imgui.TextColored(token_ok and C.ok or C.bad, token_ok and 'Telegram' or 'нет TG')

  imgui.SetCursorPosY(WIN_H - 44)
  imgui.SetCursorPosX(14)
  do
    local nick = tostring(me or '-')
    if #nick > 16 then nick = nick:sub(1, 15) .. '…' end
    imgui.TextColored(C.muted, nick)
  end
  imgui.EndChild()

  -- divider
  do
    local dl = imgui.GetWindowDrawList()
    local wp = imgui.GetWindowPos()
    local x = wp.x + SIDE_W
    dl:AddLine(
      imgui.ImVec2(x, wp.y + 16), imgui.ImVec2(x, wp.y + WIN_H - 16),
      u32(imgui, stroke(imgui, C, 0.16)), 1
    )
  end

  imgui.SameLine(0, 0)
  local contentW = WIN_W - SIDE_W
  local titles = {
    [1] = 'Основное меню', [2] = 'Настройки', [3] = 'Клипы',
    [4] = 'Темы', [5] = 'Утилиты', [6] = 'Мероприятия · Space',
    [7] = 'Следящие · Space', [8] = 'Помощь',
  }

  imgui.BeginChild('##content', imgui.ImVec2(contentW, WIN_H), false)
  imgui.Dummy(imgui.ImVec2(0, 16))
  imgui.SetCursorPosX(22)
  imgui.TextColored(C.soft, titles[menuTab] or 'Меню')

  do
    local dl = imgui.GetWindowDrawList()
    local rmin, rmax = imgui.GetItemRectMin(), imgui.GetItemRectMax()
    local tw = (rmax.x - rmin.x) * ease_out(anim.tab_fade)
    dl:AddRectFilled(
      imgui.ImVec2(rmin.x, rmax.y + 5),
      imgui.ImVec2(rmin.x + math.max(tw, 8), rmax.y + 7),
      u32(imgui, with_a(imgui, C.accent, 0.7)), 2
    )
  end

  -- close (компактный, как чип «Темы»)
  imgui.SameLine(contentW - 40)
  do
    local sz = 22
    local min = imgui.GetCursorScreenPos()
    -- чуть поднять к линии заголовка
    min = imgui.ImVec2(min.x, min.y + 1)
    imgui.SetCursorScreenPos(min)
    if imgui.InvisibleButton('##close', imgui.ImVec2(sz, sz)) then
      M.request_close(P)
    end
    local hovered = imgui.IsItemHovered()
    local hv = toward(anim.hover, '##close', hovered and 1 or 0, 14, dt)
    local dl = imgui.GetWindowDrawList()
    local max = imgui.ImVec2(min.x + sz, min.y + sz)
    local bg = mix(imgui, with_a(imgui, C.soft, 0.05), with_a(imgui, C.bad, 0.50), hv)
    dl:AddRectFilled(min, max, u32(imgui, bg), 6)
    dl:AddRect(min, max, u32(imgui, stroke(imgui, C, 0.14 + 0.22 * hv)), 6, imgui.DrawCornerFlags.All, 1)
    icon_x(dl, imgui, min.x + sz * 0.5, min.y + sz * 0.5, u32(imgui, C.soft), 3.6)
  end

  -- page fade only (без Y-сдвига — он давал скачок вместе со stagger)
  local fade = ease_out(anim.tab_fade)
  imgui.SetCursorPosX(20)
  imgui.SetCursorPosY(52)
  imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, 0.42 + 0.58 * fade)
  imgui.BeginChild('##page', imgui.ImVec2(contentW - 36, WIN_H - 64), false)
  if menuTab == 1 then
    draw_home(P, q, afk_now, idle)
  elseif menuTab == 5 then
    draw_utils(P)
  elseif menuTab == 6 then
    draw_events(P)
  elseif menuTab == 7 then
    draw_orgs(P)
  elseif menuTab == 8 then
    draw_help(P)
  elseif menuTab == 3 then
    draw_clips(P)
  elseif menuTab == 4 then
    draw_themes(P)
  elseif menuTab == 2 then
    draw_settings(P)
  end
  imgui.EndChild()
  imgui.PopStyleVar()
  imgui.EndChild()

  -- ручка ресайза: правый нижний угол (по дельте мыши, без перетаскивания окна)
  do
    local grip = 28
    local wp = imgui.GetWindowPos()
    local wsz = imgui.GetWindowSize()
    local mx = imgui.GetIO().MousePos.x
    local my = imgui.GetIO().MousePos.y
    local gmin = imgui.ImVec2(wp.x + wsz.x - grip - 4, wp.y + wsz.y - grip - 4)
    local gmax = imgui.ImVec2(wp.x + wsz.x - 2, wp.y + wsz.y - 2)
    local in_grip = mx >= gmin.x and my >= gmin.y and mx <= wp.x + wsz.x + 4 and my <= wp.y + wsz.y + 4

    if (not win_resize.active) and in_grip and imgui.IsMouseClicked(0) then
      win_resize.active = true
      win_resize.start_mx = mx
      win_resize.start_my = my
      win_resize.start_w = wsz.x
      win_resize.start_h = wsz.y
      win_resize.lock_x = wp.x
      win_resize.lock_y = wp.y
    end

    if win_resize.active then
      if imgui.IsMouseDown(0) then
        pcall(function() imgui.CaptureMouseFromApp(true) end)
        -- жёстко держим позицию — иначе imgui двигает окно вместе с мышью
        imgui.SetWindowPosVec2(imgui.ImVec2(win_resize.lock_x, win_resize.lock_y), imgui.Cond.Always)
        local nw = math.floor(win_resize.start_w + (mx - win_resize.start_mx) + 0.5)
        local nh = math.floor(win_resize.start_h + (my - win_resize.start_my) + 0.5)
        if nw < 820 then nw = 820 elseif nw > 1400 then nw = 1400 end
        if nh < 520 then nh = 520 elseif nh > 900 then nh = 900 end
        cfg.win_w = nw
        cfg.win_h = nh
        if P.ui.win_w then P.ui.win_w[0] = nw end
        if P.ui.win_h then P.ui.win_h[0] = nh end
        P.WIN_W, P.WIN_H = nw, nh
        imgui.SetWindowSizeVec2(imgui.ImVec2(nw, nh), imgui.Cond.Always)
      else
        win_resize.active = false
        pcall(function() P.save_ini() end)
      end
    end

    local hot = in_grip or win_resize.active
    local dl = imgui.GetWindowDrawList()
    local col = u32(imgui, with_a(imgui, hot and C.accent or C.muted, hot and 0.95 or 0.5))
    local x2, y2 = gmax.x, gmax.y
    for i = 0, 2 do
      local o = i * 5
      dl:AddLine(imgui.ImVec2(x2 - 15 + o, y2), imgui.ImVec2(x2, y2 - 15 + o), col, 2.0)
    end
  end

  imgui.End()
  imgui.PopStyleVar(2)
  P.apply_ui_to_cfg()
end

function M.on_open()
  anim.open = 0
  anim.closing = false
  anim.win_phase = 'open'
  anim.win_t = 0
  anim.tab_fade = 0
  reset_tab_anim()
  -- сеть только после открытия меню / вкладки (не на старте GTA)
  anim.need_events_fetch = true
end

return M
