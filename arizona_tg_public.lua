--[[
  Arizona TG Public — публичная версия (свой бот, свои файлы)

  ========== УСТАНОВКА ==========
  1) Скопируй этот файл в moonloader\
  2) Скопируй рядом:
       lib\arizona_tg_public_ui.lua
       lib\arizona_ipc_public.lua
  3) Перезапусти игру / reload scripts
  4) Меню: Numpad Del или /tgpub
  5) Настройки → впиши Bot Token и Chat ID → Сохранить
  6) Проверка: /tgptest
  7) Обновление: /tgpubupdate или кнопка в меню (не на старте — иначе краш)

  Токен: @BotFather → /newbot
  Chat id: напиши боту /start, затем
    https://api.telegram.org/bot<ТОКЕН>/getUpdates → "chat":{"id": …}

  Полная инструкция: ИНСТРУКЦИЯ.txt
  ================================
]]

script_name('Arizona TG Public')
script_author('community')
script_version('1.0.15-public')
script_properties('work-in-pause')

local SCRIPT_VERSION = '1.0.15-public'

-- Автообновление: один раз создай публичный GitHub-репо и впиши owner/repo ниже.
-- Пока YOUR_GITHUB_USER — проверка пропускается.
local UPDATE_OWNER = 'prostochka0'
local UPDATE_REPO = 'arizona-tg-public-updates'
local UPDATE_BRANCH = 'main'
local UPDATE_BASE = string.format(
  'https://raw.githubusercontent.com/%s/%s/%s/',
  UPDATE_OWNER, UPDATE_REPO, UPDATE_BRANCH
)
local UPDATE_MANIFEST = UPDATE_BASE .. 'version.json'

-- Система помощи: support-бот (заявки → админ). Плейсхолдеры — пока не настроены.
local HELP_BOT_TOKEN = '9294611001:AAGJZXwHb12SFaLBs7KB6L_3rmnNh_JcTxE'
local HELP_ADMIN_CHAT_ID = '821562814'
local HELP_REPLIES_URL = UPDATE_BASE .. 'help_replies.json'

-- Ранний выход ДО sampev/mimgui: иначе public+notify / reload роняют lua51.dll
do
  local wd = getWorkingDirectory()
  local function exists(p)
    local f = io.open(p, 'rb')
    if f then f:close() return true end
    return false
  end
  local function read_all(p)
    local f = io.open(p, 'rb')
    if not f then return nil end
    local d = f:read('*a')
    f:close()
    return d
  end
  local function write_all(p, d)
    local f = io.open(p, 'wb')
    if not f then return false end
    f:write(d)
    f:close()
    return true
  end
  -- На ПК автора лежит arizona_tg_notify.lua — public только для друзей
  if exists(wd .. '\\arizona_tg_notify.lua') then
    print('[Arizona TG Public] SKIP: найден arizona_tg_notify.lua. Удали arizona_tg_public.lua — оба сразу крашат GTA.')
    function main() wait(-1) end
    return
  end
  -- Стадийное обновление: копируем на диск, БЕЗ reload (reload = краш). Нужен полный перезаход.
  local next_dir = wd .. '\\_tgpub_next'
  local next_main = next_dir .. '\\arizona_tg_public.lua'
  if exists(next_main) then
    local pairs_ = {
      { next_dir .. '\\arizona_tg_public.lua', wd .. '\\arizona_tg_public.lua' },
      { next_dir .. '\\lib\\arizona_tg_public_ui.lua', wd .. '\\lib\\arizona_tg_public_ui.lua' },
      { next_dir .. '\\lib\\arizona_ipc_public.lua', wd .. '\\lib\\arizona_ipc_public.lua' },
    }
    for i = 1, #pairs_ do
      local src, dst = pairs_[i][1], pairs_[i][2]
      local data = read_all(src)
      if data then
        write_all(dst, data)
        pcall(os.remove, src)
      end
    end
    pcall(os.remove, next_dir .. '\\version.json')
    print('[Arizona TG Public] Обновление записано на диск. ПОЛНОСТЬЮ закрой GTA и зайди снова.')
    _G.__TGPUB_NEED_RESTART = true
    -- не return / не reload — доигрываем текущую сессию, новая версия со следующего входа
  end

  -- проверка lib до require (частая ошибка установки)
  local miss = {}
  if not exists(wd .. '\\lib\\arizona_ipc_public.lua') then miss[#miss + 1] = 'lib/arizona_ipc_public.lua' end
  if not exists(wd .. '\\lib\\arizona_tg_public_ui.lua') then miss[#miss + 1] = 'lib/arizona_tg_public_ui.lua' end
  if #miss > 0 then
    print('[Arizona TG Public] НЕТ ФАЙЛОВ: ' .. table.concat(miss, ', '))
    print('[Arizona TG Public] Скопируй из РАЗДАТЬ_arizona_tg_public целиком (lua + lib\\).')
    function main()
      while not isSampAvailable() do wait(100) end
      wait(1500)
      pcall(sampAddChatMessage, '{FF5555}[TG Public] Нет lib-файлов. Скопируй lib\\ из раздачи.', -1)
      wait(-1)
    end
    return
  end
end

local encoding = require 'encoding'
encoding.default = 'CP1251'
local u8 = encoding.UTF8
local function cp(s)
  return u8:decode(s)
end

local sampev = require 'lib.samp.events'
local _requests_mod = require 'requests'
local http_inflight = 0
local script_alive = true
local samp_ready_at = 0
local BOOT_NET_GRACE = 20 -- сек после входа: авто/ранний HTTP откладываем (lua51 + Helper)
local requests = setmetatable({}, {
  __index = function(_, k)
    local v = _requests_mod[k]
    if type(v) == 'function'
        and (k == 'get' or k == 'post' or k == 'put' or k == 'delete' or k == 'head' or k == 'request') then
      return function(...)
        if not script_alive then return nil end
        http_inflight = http_inflight + 1
        local ok, a, b, c = pcall(v, ...)
        http_inflight = http_inflight - 1
        if http_inflight < 0 then http_inflight = 0 end
        if not ok then return nil end
        return a, b, c
      end
    end
    return v
  end,
})
local json = require 'cjson.safe'
local ok_ipc, ipc = pcall(require, 'arizona_ipc_public')
if not ok_ipc then
  print('[Arizona TG Public] require arizona_ipc_public FAIL: ' .. tostring(ipc))
  function main()
    while not isSampAvailable() do wait(100) end
    wait(1500)
    pcall(sampAddChatMessage, '{FF5555}[TG Public] Не загрузился arizona_ipc_public (см. moonloader.log)', -1)
    wait(-1)
  end
  return
end
local bit = require 'bit'
-- mimgui + UI подключаются ЛЕНИВО (ensure_imgui): при старте вместе с MCR/AdminMP
-- require mimgui часто роняет весь клиент GTA без Lua-ошибки в логе
local imgui = nil
local menu_ui = nil
local imgui_ready = false

local ffi = require 'ffi'
local _get_tick = nil
do
  local ok_cdef = pcall(ffi.cdef, [[unsigned long GetTickCount(void);]])
  local ok_k32, k32 = pcall(ffi.load, 'kernel32')
  if ok_cdef and ok_k32 and k32 and k32.GetTickCount then
    _get_tick = function()
      local ok, v = pcall(k32.GetTickCount)
      if ok then return tonumber(v) or 0 end
      return math.floor(os.clock() * 1000)
    end
  else
    _get_tick = function()
      return math.floor(os.clock() * 1000)
    end
  end
end
local function ticks()
  return _get_tick()
end

local ROOT = getWorkingDirectory()
-- полностью отдельные пути — не трогают arizona_tg_notify*
local CONFIG_PATH = ROOT .. '\\config\\arizona_tg_public.ini'
local OUTBOX_DIR = ROOT .. '\\arizona_tg_public'
local OUTBOX_PATH = OUTBOX_DIR .. '\\events.jsonl'
local STATE_PATH = OUTBOX_DIR .. '\\state.json'
local HELP_TICKETS_PATH = OUTBOX_DIR .. '\\help_tickets.json'
local STATS_PATH = ROOT .. '\\Arizona Tools\\statistics.json'
local FORMS_JSON = ROOT .. '\\Arizona Tools\\files\\json\\forms.json'
local THEME_BG_DIR = ROOT .. '\\resource\\themes_public\\'

local function trim_cfg(s)
  return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', ''))
end

local cfg = {
  token = '',
  chat_id = '',
  help_client_id = '',
  reports = true,
  forms = true,
  mentions = true,
  watch_queue = true,
  quiet_mode = false,
  cooldown = 3,
  queue_from = 10,
  queue_afk_from = 5,
  afk_sec = 90,
  clips = false, -- клипы выкл по умолчанию (нужен отдельный helper)
  theme = 'dark',
  win_w = 1000,
  win_h = 640,
}

local last_sent_at = 0
local last_queue = nil
local last_form_sig = ''
local last_activity = ticks()
local last_outgoing_cmd = ''
local form_cmds = {}
local form_cmds_count = 0
local last_mention_sig = ''
local last_push_kind = '-'
local last_push_at = 0
local last_report_push = { queue = nil, reason = nil, at = 0 }

-- plain table до инициализации mimgui (доступ [0] как у imgui.new.bool)
local showMenu = { [0] = false }
local styleReady = false
local menuTab = 1
local P -- forward decl
local utils_sel_id = -1
local utils_favs = { '/admins', '/re', '/time', '/leaders' }
local utils_hist = {}
local utils_notes = {}
local HIST_MAX = 16
local FAV_MAX = 12
local ui = {} -- заполняется в ensure_imgui()

local function c4(r, g, b, a)
  -- plain color (x,y,z,w) — без imgui на старте; UI сам читает поля
  return { x = r, y = g, z = b, w = a or 1 }
end

-- простые цветовые темы (без фоновых картинок)
local THEMES = {
  {
    id = 'dark', title = 'Тёмная', desc = 'Серый фон, синий акцент',
    ok = c4(0.40, 0.85, 0.55), bad = c4(0.92, 0.38, 0.42),
    accent = c4(0.35, 0.60, 0.95), accent2 = c4(0.25, 0.45, 0.75),
    muted = c4(0.55, 0.58, 0.62), warn = c4(0.95, 0.80, 0.40),
    soft = c4(0.92, 0.93, 0.95), line = c4(0.40, 0.55, 0.80, 0.25),
    gold = c4(0.75, 0.82, 0.95), side = c4(0.10, 0.11, 0.13),
    panel = c4(0.12, 0.13, 0.15, 0.98), card = c4(0.16, 0.17, 0.20),
    btn = c4(0.20, 0.22, 0.26), btn_h = c4(0.28, 0.40, 0.60),
    light = false, nav_dark_text = false,
  },
  {
    id = 'blue', title = 'Синяя', desc = 'Холодный синий',
    ok = c4(0.45, 0.88, 0.70), bad = c4(0.95, 0.40, 0.45),
    accent = c4(0.25, 0.55, 0.95), accent2 = c4(0.15, 0.35, 0.70),
    muted = c4(0.50, 0.58, 0.68), warn = c4(0.95, 0.85, 0.45),
    soft = c4(0.90, 0.94, 1.00), line = c4(0.30, 0.50, 0.90, 0.22),
    gold = c4(0.70, 0.82, 1.00), side = c4(0.06, 0.09, 0.16),
    panel = c4(0.08, 0.11, 0.18, 0.98), card = c4(0.12, 0.16, 0.24),
    btn = c4(0.14, 0.20, 0.32), btn_h = c4(0.22, 0.38, 0.65),
    light = false, nav_dark_text = false,
  },
  {
    id = 'green', title = 'Зелёная', desc = 'Тёмный лес',
    ok = c4(0.45, 0.90, 0.55), bad = c4(0.90, 0.40, 0.40),
    accent = c4(0.30, 0.78, 0.45), accent2 = c4(0.18, 0.55, 0.30),
    muted = c4(0.50, 0.58, 0.52), warn = c4(0.92, 0.82, 0.40),
    soft = c4(0.90, 0.95, 0.90), line = c4(0.30, 0.70, 0.40, 0.22),
    gold = c4(0.70, 0.90, 0.70), side = c4(0.06, 0.10, 0.08),
    panel = c4(0.08, 0.12, 0.10, 0.98), card = c4(0.12, 0.18, 0.14),
    btn = c4(0.14, 0.22, 0.16), btn_h = c4(0.22, 0.45, 0.28),
    light = false, nav_dark_text = false,
  },
  {
    id = 'orange', title = 'Оранжевая', desc = 'Тёплый акцент',
    ok = c4(0.45, 0.85, 0.50), bad = c4(0.95, 0.35, 0.35),
    accent = c4(0.95, 0.55, 0.20), accent2 = c4(0.75, 0.35, 0.10),
    muted = c4(0.60, 0.55, 0.50), warn = c4(1.00, 0.85, 0.40),
    soft = c4(0.96, 0.93, 0.90), line = c4(0.90, 0.50, 0.20, 0.22),
    gold = c4(1.00, 0.75, 0.45), side = c4(0.12, 0.09, 0.07),
    panel = c4(0.14, 0.11, 0.09, 0.98), card = c4(0.20, 0.15, 0.12),
    btn = c4(0.24, 0.18, 0.14), btn_h = c4(0.55, 0.32, 0.14),
    light = false, nav_dark_text = false,
  },
  {
    id = 'light', title = 'Светлая', desc = 'Светлый фон',
    ok = c4(0.15, 0.55, 0.30), bad = c4(0.75, 0.15, 0.18),
    accent = c4(0.15, 0.40, 0.85), accent2 = c4(0.10, 0.28, 0.60),
    muted = c4(0.45, 0.45, 0.48), warn = c4(0.70, 0.50, 0.10),
    soft = c4(0.12, 0.12, 0.14), line = c4(0.20, 0.35, 0.70, 0.20),
    gold = c4(0.20, 0.35, 0.70), side = c4(0.90, 0.91, 0.93),
    panel = c4(0.96, 0.96, 0.97, 0.98), card = c4(1.00, 1.00, 1.00),
    btn = c4(0.88, 0.89, 0.92), btn_h = c4(0.70, 0.78, 0.92),
    light = true, nav_dark_text = false,
  },
}

local C = {
  ok = nil, bad = nil, accent = nil, accent2 = nil, muted = nil, warn = nil,
  soft = nil, line = nil, gold = nil, side = nil, panel = nil, card = nil,
  btn = nil, btn_h = nil, light = false, nav_dark = false, dirty = true,
}

local WIN_W, WIN_H = 1000, 640
local SIDE_W = 190

-- Space Event sheet
local EVENTS_SHEET_ID = '1tL4khKreipDJrhtdWPaXe_HVdv6ZcihGpzHnI2FWVSg'
local EVENTS_GID = '169840119' -- Space
local EVENTS_CACHE = OUTBOX_DIR .. '\\events_space.csv'
local events_state = {
  status = 'idle', -- idle|loading|ok|err
  err = '',
  updated = 0,
  fetched_at = 0, -- только после сети; кэш не блокирует «Обновить»
  today = '',
  done = {}, -- norm -> { name, time, org, raw }
  today_list = {}, -- chronological rows for today
  rows = {}, -- все строки таблицы: { org, prize, ts, date, time, name }
  loading = false,
}

local ORG_PAY_CAP = 50000000 -- макс. выплата с одного МП
local ORG_AZP_PER = 50
local mp_hidden = {} -- norm name -> true (убрано из рекомендаций)
local mp_renames = {} -- norm key -> отображаемое имя
local mp_extra = {} -- доп. МП, добавленные вручную (display names)
local org_hidden = {} -- norm org -> true (убран из следящих)
local org_extra = {} -- следящие, добавленные вручную
local helper_hidden = {} -- norm helper -> true
local helper_extra = {} -- (legacy) ручные помощники — активность только из 2-го ника
local events_rename_key = nil -- какой МП сейчас переименовываем

-- рекомендованные МП (канон) + алиасы написания из таблицы
local MP_RECOMMENDED = {
  'Дерби',
  'Обстрел с крыши',
  'Король Узи',
  'Паркур на пляже',
  'Русская рулетка',
  'Прятки',
  'Гонки в пустыне',
  'Догони меня калаш',
  'Саймон говорит',
  'Третий Лишний',
  'Особо опасный',
  'Главный жнец',
  'Вышибалы',
  'Неоновый заезд',
  'Король ЦГ',
  'Король Дигла',
  'Король Обрезов',
  'Король Калашей',
  'Перестрелка в казино',
  'Перестрелка в пустыне',
  'Дамба',
  'Добраться до чиллиада',
  'Добрый выстрел',
  'Заморозка',
  'Тоннель смерти',
  'Царь горы',
  'Воздушные гонки',
  'Военные сражения',
  'Прятки в казино',
  'Поливалки',
  'Гонки ЛВ-ЛС',
  'Паркур',
  'Игра в кальмара',
  'Гонки на чиллиад',
  'Гонки',
}

-- ключи/значения — уже в «словарной» форме (после mp_norm)
local MP_ALIASES = {
  ['король uzi'] = 'король узи',
  ['король узичек'] = 'король узи',
  ['вышибала'] = 'вышибалы',
  ['добраться до чилиада'] = 'добраться до чиллиада',
  ['добраться до чилиада на болиде'] = 'добраться до чиллиада',
  ['добраться до чиллиада на болиде'] = 'добраться до чиллиада',
  ['король центра гетто'] = 'король цг',
  ['король цетра гетто'] = 'король цг',
  ['король диглов'] = 'король дигла',
  ['перестрелки в пустынке'] = 'перестрелка в пустыне',
  ['перестрелка в пустынном городе'] = 'перестрелка в пустыне',
  ['перестрелки в пустыне'] = 'перестрелка в пустыне',
  ['гонка в пустыне'] = 'гонки в пустыне',
  ['гонки лв - лс'] = 'гонки лв-лс',
  ['гонки лс - лв'] = 'гонки лв-лс',
  ['гонки лс-лв'] = 'гонки лв-лс',
  ['гонки к лса'] = 'гонки лв-лс',
  ['гонки на чиллиаде'] = 'гонки на чиллиад',
  ['гонки на чилиад'] = 'гонки на чиллиад',
  ['неоновые гонки'] = 'неоновый заезд',
  ['неоновый заезд'] = 'неоновый заезд',
  ['неон заезд'] = 'неоновый заезд',
  ['поливалка'] = 'поливалки',
  ['воздушная гонка'] = 'воздушные гонки',
  ['военное сражение'] = 'военные сражения',
}
local ROUND = 16
local theme_textures = {}
local theme_tex_tried = false

local WM_KEYDOWN = 0x0100
local WM_SYSKEYDOWN = 0x0104
local WM_LBUTTONDOWN = 0x0201
local WM_RBUTTONDOWN = 0x0204
local WM_MBUTTONDOWN = 0x0207
local WM_MOUSEWHEEL = 0x020A
local WM_XBUTTONDOWN = 0x020B
local VK_DELETE = 0x2E   -- Del / Numpad Del (NumLock off)
local VK_DECIMAL = 0x6E  -- Numpad . / Del (NumLock on)
local VK_ESCAPE = 0x1B

local function chat(msg)
  if isSampAvailable() then
    sampAddChatMessage(cp('{00E5FF}[TG Notify] {FFFFFF}') .. cp(tostring(msg)), -1)
  end
end

local function strip_colors(text)
  if not text then return '' end
  text = text:gsub('{%x%x%x%x%x%x}', '')
  text = text:gsub('{%w+}', '')
  return text
end

local function trim(s)
  return (tostring(s):gsub('^%s+', ''):gsub('%s+$', ''))
end

-- string.lower не трогает кириллицу → «Неоновый Заезд» ≠ «Неоновый заезд»
local function mp_casefold(s)
  s = tostring(s or '')
  local utf = s:find('\208') or s:find('\209')
  local out, i, n = {}, 1, #s
  while i <= n do
    local b = s:byte(i)
    if utf and b == 0xD0 and i < n then
      local b2 = s:byte(i + 1)
      if b2 == 0x81 then
        out[#out + 1] = '\208\181' -- Ё → е
      elseif b2 >= 0x90 and b2 <= 0x9F then
        out[#out + 1] = string.char(0xD0, b2 + 0x20)
      elseif b2 >= 0xA0 and b2 <= 0xAF then
        out[#out + 1] = string.char(0xD1, b2 - 0x20)
      else
        out[#out + 1] = string.char(b, b2)
      end
      i = i + 2
    elseif utf and b == 0xD1 and i < n then
      local b2 = s:byte(i + 1)
      if b2 == 0x91 then
        out[#out + 1] = '\208\181' -- ё → е
      else
        out[#out + 1] = string.char(b, b2)
      end
      i = i + 2
    elseif (not utf) and b == 0xA8 then
      out[#out + 1] = string.char(0xE5)
      i = i + 1
    elseif (not utf) and b == 0xB8 then
      out[#out + 1] = string.char(0xE5)
      i = i + 1
    elseif (not utf) and b >= 0xC0 and b <= 0xDF then
      out[#out + 1] = string.char(b + 0x20)
      i = i + 1
    elseif b < 128 then
      if b >= 65 and b <= 90 then b = b + 32 end
      out[#out + 1] = string.char(b)
      i = i + 1
    else
      out[#out + 1] = string.char(b)
      i = i + 1
    end
  end
  return table.concat(out)
end

local function mp_norm(name)
  name = tostring(name or '')
  name = name:gsub('\194\160', ' ')
  name = name:gsub('\160', ' ')
  name = name:gsub('\226\128\148', '-'):gsub('\226\128\149', '-'):gsub('\226\128\150', '-')
  name = name:gsub('%-+', '-')
  name = name:gsub('%s*%-%s*', '-')
  name = name:gsub('%s+', ' ')
  name = trim(name)
  name = mp_casefold(name)
  if MP_ALIASES[name] then return MP_ALIASES[name] end
  return name
end

-- «Nick1, Nick2, Nick3» — первый следящий, остальные кандидаты в помощники
local function org_split_nicks(s)
  local out = {}
  s = trim(tostring(s or ''))
  if s == '' then return out end
  for part in (s .. ','):gmatch('([^,;/]+)') do
    local n = trim(part)
    if n ~= '' then out[#out + 1] = n end
  end
  return out
end

local function org_primary(s)
  local nicks = org_split_nicks(s)
  return nicks[1] or ''
end

-- все ники после первого (ещё без фильтра «уже проводил МП»)
local function org_helpers_raw(s)
  local nicks = org_split_nicks(s)
  local out = {}
  for i = 2, #nicks do
    out[#out + 1] = nicks[i]
  end
  return out
end

-- кто хотя бы раз был первым в таблице (реально проводил МП) — не помощник.
-- ручное добавление в «следящие» сюда не входит: иначе помощник пропадает из подсчёта.
local function events_org_leaders_set()
  local set = {}
  local rows = events_state.rows or {}
  for i = 1, #rows do
    local key = mp_norm(org_primary(rows[i].org))
    if key ~= '' then set[key] = true end
  end
  return set
end

local function touch_activity()
  last_activity = ticks()
end

local function inactive_sec()
  local dt = ticks() - last_activity
  if dt < 0 then last_activity = ticks(); return 0 end
  return math.floor(dt / 1000)
end

local function is_afk()
  return inactive_sec() >= cfg.afk_sec
end

local function ensure_dirs()
  local lfs_ok, lfs = pcall(require, 'lfs')
  if lfs_ok and lfs.mkdir then
    pcall(lfs.mkdir, OUTBOX_DIR)
    pcall(lfs.mkdir, ROOT .. '\\config')
    pcall(lfs.mkdir, ROOT .. '\\resource')
    pcall(lfs.mkdir, THEME_BG_DIR)
  end
  ipc.ensure()
end

local function read_file(path)
  local f = io.open(path, 'rb')
  if not f then return nil end
  local data = f:read('*a')
  f:close()
  return data
end

local function write_file(path, data)
  local f = io.open(path, 'wb')
  if not f then return false end
  f:write(data)
  f:close()
  return true
end

-- update+help in one closure (Lua 5.1 200-local limit)
local extras = (function()
local function ensure_parent_dir(path)
  local dir = tostring(path or ''):match('^(.*)[/\\][^/\\]+$')
  if not dir or dir == '' then return end
  if type(createDirectory) == 'function' then
    pcall(createDirectory, dir)
  end
  local lfs_ok, lfs = pcall(require, 'lfs')
  if lfs_ok and lfs.mkdir then
    local acc = ''
    for part in (dir:gsub('/', '\\')):gmatch('[^\\]+') do
      acc = acc == '' and part or (acc .. '\\' .. part)
      if not (acc:match('^%a:$')) then
        pcall(lfs.mkdir, acc)
      end
    end
  end
end

-- ===================== AUTO-UPDATE =====================
local update_state = {
  status = 'idle', -- idle|checking|ready|updating|ok|error|disabled
  msg = '',
  remote = '',
  checked_at = 0,
  busy = false,
}

local function update_configured()
  return UPDATE_OWNER ~= '' and UPDATE_OWNER ~= 'YOUR_GITHUB_USER'
end

local function parse_semver(s)
  local a, b, c = tostring(s or ''):match('(%d+)%.(%d+)%.(%d+)')
  return tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0
end

local function version_is_newer(remote, local_v)
  local ra, rb, rc = parse_semver(remote)
  local la, lb, lc = parse_semver(local_v)
  if ra ~= la then return ra > la end
  if rb ~= lb then return rb > lb end
  return rc > lc
end

local function http_get_raw(url)
  local last = nil
  for _ = 1, 6 do
    local ok, resp = pcall(function()
      return requests.get(url, {
        timeout = 25,
        allow_redirects = false,
        headers = {
          ['User-Agent'] = 'Mozilla/5.0 ArizonaTGPublic/' .. SCRIPT_VERSION,
          ['Accept'] = '*/*',
        },
      })
    end)
    if not ok or type(resp) ~= 'table' then
      return nil, tostring(resp)
    end
    last = resp
    local code = tonumber(resp.status_code) or 0
    if code == 200 then
      return resp, nil
    end
    if code == 301 or code == 302 or code == 303 or code == 307 or code == 308 then
      local loc = nil
      if type(resp.headers) == 'table' then
        for k, v in pairs(resp.headers) do
          if tostring(k):lower() == 'location' then loc = v break end
        end
      end
      if type(loc) ~= 'string' or loc == '' then break end
      if loc:match('^https?://') then
        url = loc
      else
        local host = url:match('^(https?://[^/]+)') or ''
        url = host .. ((loc:sub(1, 1) == '/') and loc or ('/' .. loc))
      end
    else
      break
    end
  end
  local code = last and tonumber(last.status_code) or 0
  return last, 'HTTP ' .. tostring(code)
end

local function update_resolve_url(rel)
  rel = tostring(rel or ''):gsub('\\', '/')
  if rel:match('^https?://') then return rel end
  return UPDATE_BASE .. rel:gsub('^/+', '')
end

local function update_apply_manifest(manifest, silent)
  local ver = tostring(manifest.version or '')
  local files = manifest.files
  if ver == '' or type(files) ~= 'table' or #files == 0 then
    update_state.status = 'error'
    update_state.msg = 'битый version.json'
    if not silent then chat('Обновление: битый манифест') end
    return false
  end
  if not version_is_newer(ver, SCRIPT_VERSION) then
    update_state.status = 'ok'
    update_state.remote = ver
    update_state.msg = 'актуально (' .. SCRIPT_VERSION .. ')'
    if not silent then chat('Обновлений нет · ' .. SCRIPT_VERSION) end
    return false
  end
  update_state.status = 'updating'
  update_state.remote = ver
  update_state.msg = 'скачиваю ' .. ver
  if not silent then chat('Обновление до ' .. ver .. '…') end

  -- Пишем во _tgpub_next (не в живые .lua): overwrite + reload/AutoReboot = C0000005 в lua51
  local stage = ROOT .. '\\_tgpub_next'
  for i = 1, #files do
    local item = files[i]
    if type(item) == 'table' then
      local rel = tostring(item.path or item.url or '')
      local src = update_resolve_url(item.url or item.path or '')
      if rel == '' or src == '' then
        update_state.status = 'error'
        update_state.msg = 'плохой список файлов'
        if not silent then chat('Обновление: ошибка списка файлов') end
        return false
      end
      local low = rel:lower():gsub('\\', '/')
      if low:find('%.ini$') or low:find('config/') then
        -- skip
      else
        local resp, err = http_get_raw(src)
        local body = resp and resp.text or resp and resp.content
        if type(body) ~= 'string' or body == '' then
          update_state.status = 'error'
          update_state.msg = 'не скачался ' .. rel
          if not silent then chat('Обновление: не скачался ' .. rel) end
          return false
        end
        local dest = stage .. '\\' .. rel:gsub('/', '\\')
        ensure_parent_dir(dest)
        if not write_file(dest, body) then
          update_state.status = 'error'
          update_state.msg = 'не записал ' .. rel
          if not silent then chat('Обновление: не записал ' .. rel) end
          return false
        end
      end
    end
  end
  write_file(stage .. '\\version.json', '{"version":"' .. ver .. '"}\n')

  update_state.status = 'ready'
  update_state.msg = 'скачано ' .. ver .. ' · перезайди в игру'
  chat('TG Public ' .. ver .. ' скачан. Полностью закрой GTA и зайди снова (без reload).')
  return true
end

local function update_check(force, silent)
  if update_state.busy then return end
  if not script_alive then return end
  if not update_configured() then
    update_state.status = 'disabled'
    update_state.msg = 'укажи UPDATE_OWNER в скрипте'
    if not silent then chat('Автообновление не настроено (UPDATE_OWNER)') end
    return
  end
  if samp_ready_at > 0 then
    local age = os.time() - samp_ready_at
    if age < BOOT_NET_GRACE then
      if update_state._net_deferred then return end
      update_state._net_deferred = true
      local delay_ms = (BOOT_NET_GRACE - age) * 1000
      if delay_ms < 500 then delay_ms = 500 end
      update_state.status = 'checking'
      update_state.msg = 'подожди ' .. tostring(BOOT_NET_GRACE - age) .. 'с…'
      lua_thread.create(function()
        wait(delay_ms)
        update_state._net_deferred = false
        if script_alive then update_check(force, silent) end
      end)
      return
    end
  end
  if not force and update_state.checked_at > 0 and (os.time() - update_state.checked_at) < 120 then
    return
  end
  update_state.busy = true
  update_state.status = 'checking'
  update_state.msg = 'проверка…'
  lua_thread.create(function()
    local ok_run, err_run = pcall(function()
      local resp, err = http_get_raw(UPDATE_MANIFEST)
      update_state.checked_at = os.time()
      if not resp or (tonumber(resp.status_code) or 0) ~= 200 then
        update_state.status = 'error'
        update_state.msg = err or 'нет манифеста'
        if not silent then chat('Обновление: ' .. (update_state.msg or 'ошибка')) end
        return
      end
      local body = resp.text or resp.content or ''
      local manifest = json.decode(body)
      if type(manifest) ~= 'table' then
        update_state.status = 'error'
        update_state.msg = 'version.json не JSON'
        if not silent then chat('Обновление: битый JSON') end
        return
      end
      update_apply_manifest(manifest, silent)
    end)
    if not ok_run then
      update_state.status = 'error'
      update_state.msg = tostring(err_run)
      if not silent then chat('Обновление: сбой') end
    end
    update_state.busy = false
  end)
end

local function get_update_state()
  return update_state
end


  return {

    update_check = update_check,

    get_update_state = get_update_state,

    update_configured = update_configured,

    http_get_raw = http_get_raw,

    ensure_parent_dir = ensure_parent_dir,

  }

end)()
local function append_event(ev)
  ensure_dirs()
  local line = json.encode(ev) or '{}'
  local f = io.open(OUTBOX_PATH, 'ab')
  if f then f:write(line .. '\n'); f:close() end
end

local function apply_theme(id)
  local th = THEMES[1]
  for _, t in ipairs(THEMES) do
    if t.id == id then th = t break end
  end
  cfg.theme = th.id
  C.ok, C.bad = th.ok, th.bad
  C.accent, C.accent2 = th.accent, th.accent2
  C.muted, C.warn = th.muted, th.warn
  C.soft, C.line, C.gold = th.soft, th.line, th.gold
  C.side, C.panel, C.card = th.side, th.panel, th.card
  C.btn, C.btn_h = th.btn, th.btn_h
  C.light = th.light and true or false
  C.nav_dark = th.nav_dark_text and true or false
  C.dirty = true
end

apply_theme('dark')

-- публичная версия: только цвет, без jpg-фонов
local function ensure_theme_textures()
  theme_tex_tried = true
end

local function draw_theme_background()
  -- solid UI через C.panel / стиль меню
end

local function clamp_win_w(v)
  v = tonumber(v) or 1000
  if v < 820 then return 820 end
  if v > 1400 then return 1400 end
  return math.floor(v)
end

local function clamp_win_h(v)
  v = tonumber(v) or 640
  if v < 520 then return 520 end
  if v > 900 then return 900 end
  return math.floor(v)
end

local function write_char_buf(buf, size, s)
  s = tostring(s or '')
  pcall(function()
    local ffi = require 'ffi'
    ffi.fill(buf, size)
    ffi.copy(buf, s, math.min(#s, size - 1))
  end)
end

local function read_char_buf(buf)
  local ffi = require 'ffi'
  local raw = ''
  pcall(function() raw = ffi.string(buf) end)
  return trim_cfg((raw or ''):gsub('%z', ''))
end

local function sync_ui_from_cfg()
  if not imgui_ready or not ui.reports then return end
  ui.reports[0] = cfg.reports
  ui.forms[0] = cfg.forms
  ui.mentions[0] = cfg.mentions
  ui.watch_queue[0] = cfg.watch_queue
  ui.quiet_mode[0] = cfg.quiet_mode
  ui.queue_from[0] = cfg.queue_from
  ui.queue_afk_from[0] = cfg.queue_afk_from
  ui.afk_sec[0] = cfg.afk_sec
  ui.cooldown[0] = cfg.cooldown
  ui.send_clips[0] = cfg.clips
  ui.win_w[0] = clamp_win_w(cfg.win_w)
  ui.win_h[0] = clamp_win_h(cfg.win_h)
  write_char_buf(ui.bot_token, 192, cfg.token or '')
  write_char_buf(ui.chat_id, 64, cfg.chat_id or '')
  WIN_W = ui.win_w[0]
  WIN_H = ui.win_h[0]
end

local function apply_ui_to_cfg()
  if not imgui_ready or not ui.reports then return end
  cfg.reports = ui.reports[0]
  cfg.forms = ui.forms[0]
  cfg.mentions = ui.mentions[0]
  cfg.watch_queue = ui.watch_queue[0]
  cfg.quiet_mode = ui.quiet_mode[0]
  cfg.queue_from = math.max(1, ui.queue_from[0])
  cfg.queue_afk_from = math.max(1, ui.queue_afk_from[0])
  cfg.afk_sec = math.max(10, ui.afk_sec[0])
  cfg.cooldown = math.max(0, ui.cooldown[0])
  cfg.clips = ui.send_clips[0]
  cfg.win_w = clamp_win_w(ui.win_w[0])
  cfg.win_h = clamp_win_h(ui.win_h[0])
  cfg.token = read_char_buf(ui.bot_token)
  cfg.chat_id = read_char_buf(ui.chat_id)
  ui.win_w[0] = cfg.win_w
  ui.win_h[0] = cfg.win_h
  WIN_W = cfg.win_w
  WIN_H = cfg.win_h
end

local function load_ini()
  local raw = read_file(CONFIG_PATH)
  if not raw then
    ensure_dirs()
    write_file(CONFIG_PATH, table.concat({
      '; Токен и Chat ID задаются в меню → Настройки',
      '[Telegram]', 'BotToken=', 'ChatId=', '',
      '[Notify]', 'Reports=1', 'Forms=1', 'Mentions=1', 'WatchToolsQueue=1',
      'QuietMode=0', 'CooldownSec=3', 'QueueNotifyFrom=10', 'QueueNotifyAfkFrom=5', 'AfkSec=90', '',
      '[Clips]', 'Enabled=0', '',
      '[UI]', 'Theme=dark', '',
    }, '\n'))
    apply_theme('dark')
    return false
  end
  local section = ''
  for line in raw:gmatch('[^\r\n]+') do
    line = trim(line)
    if line ~= '' and not line:match('^;') and not line:match('^#') then
      local sec = line:match('^%[(.-)%]$')
      if sec then
        section = sec:lower()
      else
        local k, v = line:match('^([^=]+)=(.*)$')
        if k then
          k = trim(k):lower(); v = trim(v)
          if section == 'telegram' then
            if k == 'bottoken' then cfg.token = v end
            if k == 'chatid' then cfg.chat_id = v end
            if k == 'helpclientid' then cfg.help_client_id = v end
          elseif section == 'notify' then
            if k == 'reports' then cfg.reports = (v == '1' or v:lower() == 'true') end
            if k == 'forms' then cfg.forms = (v == '1' or v:lower() == 'true') end
            if k == 'mentions' then cfg.mentions = (v == '1' or v:lower() == 'true') end
            if k == 'watchtoolsqueue' then cfg.watch_queue = (v == '1' or v:lower() == 'true') end
            if k == 'quietmode' then cfg.quiet_mode = (v == '1' or v:lower() == 'true') end
            if k == 'cooldownsec' then cfg.cooldown = tonumber(v) or 3 end
            if k == 'queuenotifyfrom' then cfg.queue_from = tonumber(v) or 10 end
            if k == 'queuenotifyafkfrom' then cfg.queue_afk_from = tonumber(v) or 5 end
            if k == 'afksec' then cfg.afk_sec = tonumber(v) or 90 end
          elseif section == 'clips' then
            if k == 'enabled' then cfg.clips = (v == '1' or v:lower() == 'true') end
          elseif section == 'ui' then
            if k == 'theme' and v ~= '' then cfg.theme = v:lower() end
            if k == 'winw' then cfg.win_w = clamp_win_w(v) end
            if k == 'winh' then cfg.win_h = clamp_win_h(v) end
          elseif section == 'utils' then
            if k == 'favorites' and v ~= '' then
              utils_favs = {}
              for part in (v .. '|'):gmatch('([^|]*)|') do
                part = trim(part)
                if part ~= '' then
                  if not part:match('^/') then part = '/' .. part end
                  utils_favs[#utils_favs + 1] = part
                  if #utils_favs >= FAV_MAX then break end
                end
              end
              if #utils_favs == 0 then
                utils_favs = { '/admins', '/re', '/time', '/leaders' }
              end
            end
          end
        end
      end
    end
  end
  -- старые id тем из приватной версии
  if cfg.theme == 'void' or cfg.theme == 'ascend' or cfg.theme == 'ronin'
    or cfg.theme == 'ink' or cfg.theme == 'citadel' or cfg.theme == 'ash' then
    cfg.theme = 'dark'
  end
  apply_theme(cfg.theme or 'dark')
  if not cfg.help_client_id or cfg.help_client_id == '' then
    cfg.help_client_id = string.format(
      '%08x-%04x-%04x-%04x-%08x%04x',
      os.time() % 0xffffffff,
      math.random(0, 0xffff),
      math.random(0, 0xffff),
      math.random(0, 0xffff),
      math.random(0, 0xffffffff),
      math.random(0, 0xffff)
    )
  end
  return cfg.token ~= '' and cfg.chat_id ~= ''
end

local function save_ini()
  ensure_dirs()
  apply_ui_to_cfg()
  if not cfg.help_client_id or cfg.help_client_id == '' then
    cfg.help_client_id = string.format(
      '%08x-%04x-%04x-%04x-%08x%04x',
      os.time() % 0xffffffff,
      math.random(0, 0xffff),
      math.random(0, 0xffff),
      math.random(0, 0xffff),
      math.random(0, 0xffffffff),
      math.random(0, 0xffff)
    )
  end
  local bool = function(v) return v and '1' or '0' end
  write_file(CONFIG_PATH, table.concat({
    '; Telegram задаётся в меню → Настройки',
    '[Telegram]',
    'BotToken=' .. tostring(cfg.token or ''),
    'ChatId=' .. tostring(cfg.chat_id or ''),
    'HelpClientId=' .. tostring(cfg.help_client_id or ''),
    '',
    '[Notify]',
    'Reports=' .. bool(cfg.reports),
    'Forms=' .. bool(cfg.forms),
    'Mentions=' .. bool(cfg.mentions),
    'WatchToolsQueue=' .. bool(cfg.watch_queue),
    'QuietMode=' .. bool(cfg.quiet_mode),
    'CooldownSec=' .. tostring(cfg.cooldown),
    'QueueNotifyFrom=' .. tostring(cfg.queue_from),
    'QueueNotifyAfkFrom=' .. tostring(cfg.queue_afk_from),
    'AfkSec=' .. tostring(cfg.afk_sec),
    '',
    '[Clips]',
    'Enabled=' .. bool(cfg.clips),
    '',
    '[UI]',
    'Theme=' .. tostring(cfg.theme or 'dark'),
    'WinW=' .. tostring(clamp_win_w(cfg.win_w)),
    'WinH=' .. tostring(clamp_win_h(cfg.win_h)),
    '',
    '[Utils]',
    'Favorites=' .. table.concat(utils_favs, '|'),
    '',
  }, '\n'))
end

local function save_state()
  local hidden_arr = {}
  for k, v in pairs(mp_hidden) do
    if v then hidden_arr[#hidden_arr + 1] = k end
  end
  table.sort(hidden_arr)
  local org_arr = {}
  for k, v in pairs(org_hidden) do
    if v then org_arr[#org_arr + 1] = k end
  end
  table.sort(org_arr)
  local help_hid = {}
  for k, v in pairs(helper_hidden) do
    if v then help_hid[#help_hid + 1] = k end
  end
  table.sort(help_hid)
  write_file(STATE_PATH, json.encode({
    last_queue = last_queue,
    last_report_push = last_report_push,
    utils_hist = utils_hist,
    utils_notes = utils_notes,
    events_hidden = hidden_arr,
    events_renames = mp_renames,
    events_extra = mp_extra,
    events_org_hidden = org_arr,
    events_org_extra = org_extra,
    events_helper_hidden = help_hid,
    events_helper_extra = helper_extra,
    updated = os.time(),
  }) or '{}')
end

local function load_state()
  local raw = read_file(STATE_PATH)
  if not raw then return end
  local st = json.decode(raw)
  if type(st) ~= 'table' then return end
  if st.last_queue ~= nil then last_queue = tonumber(st.last_queue) end
  if type(st.last_report_push) == 'table' then
    last_report_push.queue = tonumber(st.last_report_push.queue)
    last_report_push.reason = st.last_report_push.reason
    last_report_push.at = tonumber(st.last_report_push.at) or 0
  end
  if type(st.utils_hist) == 'table' then
    utils_hist = {}
    for i = 1, math.min(#st.utils_hist, HIST_MAX) do
      local c = trim(tostring(st.utils_hist[i] or ''))
      if c ~= '' then utils_hist[#utils_hist + 1] = c end
    end
  end
  if type(st.utils_notes) == 'table' then
    utils_notes = {}
    for k, v in pairs(st.utils_notes) do
      local id = tostring(k)
      local note = trim(tostring(v or ''))
      if id ~= '' and note ~= '' then utils_notes[id] = note end
    end
  end
  mp_hidden = {}
  if type(st.events_hidden) == 'table' then
    for i = 1, #st.events_hidden do
      local k = mp_norm(st.events_hidden[i])
      if k ~= '' then mp_hidden[k] = true end
    end
  end
  mp_renames = {}
  if type(st.events_renames) == 'table' then
    for k, v in pairs(st.events_renames) do
      local key = mp_norm(k)
      local label = trim(tostring(v or ''))
      if key ~= '' and label ~= '' then mp_renames[key] = label end
    end
  end
  mp_extra = {}
  if type(st.events_extra) == 'table' then
    local seen = {}
    for i = 1, #MP_RECOMMENDED do
      seen[mp_norm(MP_RECOMMENDED[i])] = true
    end
    for i = 1, #st.events_extra do
      local name = trim(tostring(st.events_extra[i] or ''))
      local key = mp_norm(name)
      if key ~= '' and not seen[key] then
        seen[key] = true
        mp_extra[#mp_extra + 1] = name
      end
    end
  end
  org_hidden = {}
  if type(st.events_org_hidden) == 'table' then
    for i = 1, #st.events_org_hidden do
      local k = mp_norm(st.events_org_hidden[i])
      if k ~= '' then org_hidden[k] = true end
    end
  end
  org_extra = {}
  if type(st.events_org_extra) == 'table' then
    local seen = {}
    for i = 1, #st.events_org_extra do
      local name = trim(tostring(st.events_org_extra[i] or ''))
      local key = mp_norm(name)
      if key ~= '' and not seen[key] then
        seen[key] = true
        org_extra[#org_extra + 1] = name
      end
    end
  end
  helper_hidden = {}
  if type(st.events_helper_hidden) == 'table' then
    for i = 1, #st.events_helper_hidden do
      local k = mp_norm(st.events_helper_hidden[i])
      if k ~= '' then helper_hidden[k] = true end
    end
  end
  helper_extra = {}
  if type(st.events_helper_extra) == 'table' then
    local seen = {}
    for i = 1, #st.events_helper_extra do
      local name = trim(tostring(st.events_helper_extra[i] or ''))
      local key = mp_norm(name)
      if key ~= '' and not seen[key] then
        seen[key] = true
        helper_extra[#helper_extra + 1] = name
      end
    end
  end
end

local function url_encode(s)
  s = tostring(s or '')
  s = s:gsub('\n', '\r\n')
  s = s:gsub('([^%w%-%.%_%~ ])', function(c)
    return string.format('%%%02X', string.byte(c))
  end)
  return s:gsub(' ', '+')
end

local function tg_send(text, opts)
  opts = opts or {}
  if cfg.token == '' or cfg.chat_id == '' then
    if not opts.silent then chat('Нет токена: Настройки → Bot Token и Chat ID → Сохранить') end
    return false, 'no config'
  end
  local now = os.clock()
  if not opts.skip_cooldown and now - last_sent_at < cfg.cooldown then
    return false, 'cooldown'
  end
  last_sent_at = now
  local body = table.concat({
    'chat_id=' .. url_encode(cfg.chat_id),
    'text=' .. url_encode(text),
    'disable_web_page_preview=true',
  }, '&')
  local ok, resp = pcall(function()
    return requests.post('https://api.telegram.org/bot' .. cfg.token .. '/sendMessage', {
      data = body,
      headers = { ['Content-Type'] = 'application/x-www-form-urlencoded' },
      timeout = 15,
    })
  end)
  if not ok then
    if not opts.silent then chat('Ошибка Telegram: ' .. tostring(resp)) end
    return false, tostring(resp)
  end
  local parsed = nil
  if resp and resp.json then
    local jok, j = pcall(resp.json)
    if jok then parsed = j end
  elseif resp and resp.text then
    parsed = json.decode(resp.text)
  end
  if not parsed or not parsed.ok then
    local err = (parsed and parsed.description) or (resp and resp.text) or 'unknown'
    if not opts.silent then chat('Telegram отклонил: ' .. tostring(err):sub(1, 80)) end
    return false, tostring(err)
  end
  return true
end

local function notify(kind, text_cp, extra)
  if cfg.quiet_mode and kind ~= 'test' and not is_afk() then
    return
  end
  last_push_kind = tostring(kind)
  last_push_at = os.time()
  local utf = u8:encode(text_cp or '')
  append_event({ t = os.date('!%Y-%m-%dT%H:%M:%SZ'), kind = kind, text = utf, extra = extra or {} })
  lua_thread.create(function()
    local ok, err = tg_send(utf, { silent = kind ~= 'test', skip_cooldown = kind == 'test' })
    if kind == 'test' then
      chat(ok and 'Доставлено в Telegram' or ('Не доставлено: ' .. tostring(err)))
    end
  end)
end

local function queue_reason(q)
  if not q then return nil end
  if q >= cfg.queue_from then return 'high' end
  if q >= cfg.queue_afk_from and is_afk() then return 'afk' end
  return nil
end

local function consider_queue(q)
  if not cfg.reports or q == nil then return end
  local reason = queue_reason(q)
  if not reason then
    if last_report_push.queue and q < cfg.queue_afk_from then
      last_report_push.queue, last_report_push.reason = nil, nil
      save_state()
    elseif last_report_push.reason == 'afk' and not is_afk() then
      last_report_push.reason = nil; save_state()
    elseif last_report_push.reason == 'high' and q < cfg.queue_from then
      last_report_push.queue, last_report_push.reason = nil, nil
      save_state()
    end
    return
  end
  local prev_q, prev_reason = last_report_push.queue, last_report_push.reason
  local should = prev_q == nil or q > prev_q
    or (reason == 'afk' and prev_reason ~= 'afk')
    or (reason == 'high' and prev_reason ~= 'high')
  if not should then return end
  local hint = (reason == 'high')
    and (cp('\nПорог: ≥') .. tostring(cfg.queue_from))
    or (cp('\nПорог: ≥') .. tostring(cfg.queue_afk_from) .. cp(' и AFK ~') .. tostring(cfg.afk_sec) .. cp(' сек'))
  notify('queue', cp('Arizona · Репорты в очереди: ') .. tostring(q) .. hint,
    { queue = q, reason = reason, afk_sec = inactive_sec() })
  last_report_push.queue, last_report_push.reason, last_report_push.at = q, reason, os.time()
  save_state()
end

local function load_form_cmds()
  form_cmds, form_cmds_count = {}, 0
  local raw = read_file(FORMS_JSON)
  if not raw then return 0 end
  local data = json.decode(raw)
  if type(data) ~= 'table' then return 0 end
  local n = 0
  for _, item in ipairs(data) do
    if type(item) == 'table' and item.accept and type(item.name) == 'string' and item.name ~= '' then
      local cmd = item.name:match('^(%S+)')
      if cmd then
        form_cmds[cmd:lower()] = true
        n = n + 1
      end
    end
  end
  form_cmds_count = n
  return n
end

local function get_my_nick()
  if not isSampAvailable() then return nil end
  local ok, result = pcall(function()
    local _, id = sampGetPlayerIdByCharHandle(PLAYER_PED)
    if id ~= nil then
      return sampGetPlayerNickname(id)
    end
  end)
  if ok and result and result ~= '' then return result end
  return nil
end

local function to_ui(s)
  s = tostring(s or '')
  local ok, r = pcall(function() return u8(s) end)
  if ok and r and r ~= '' then return r end
  return s
end

local function get_my_id()
  if not isSampAvailable() then return nil end
  local ok, id = pcall(function()
    local _, pid = sampGetPlayerIdByCharHandle(PLAYER_PED)
    return pid
  end)
  if ok then return id end
  return nil
end

local function get_self_info()
  local info = {
    id = get_my_id(),
    nick = get_my_nick() or '-',
    x = 0, y = 0, z = 0,
    hp = 0, armor = 0, ping = 0,
    interior = 0, vw = 0,
  }
  if not isSampAvailable() then return info end
  pcall(function()
    info.x, info.y, info.z = getCharCoordinates(PLAYER_PED)
  end)
  pcall(function()
    if info.id ~= nil then
      info.hp = sampGetPlayerHealth(info.id) or 0
      info.armor = sampGetPlayerArmor(info.id) or 0
      info.ping = sampGetPlayerPing(info.id) or 0
    end
  end)
  pcall(function() info.interior = getActiveInterior() end)
  pcall(function()
    if getCharVirtualWorld then
      info.vw = getCharVirtualWorld(PLAYER_PED) or 0
    end
  end)
  return info
end

-- ===================== HELP (public → admin) =====================

local helpmod = (function()

local help_tickets = {}
local help_state = {
  busy = false,
  poll_at = 0,
  status = '',
}
local help_sel = { idx = 1 }

local function help_configured()
  return HELP_BOT_TOKEN ~= '' and HELP_BOT_TOKEN ~= 'YOUR_HELP_BOT_TOKEN'
    and HELP_ADMIN_CHAT_ID ~= '' and HELP_ADMIN_CHAT_ID ~= 'YOUR_HELP_ADMIN_CHAT_ID'
end

local function help_load_tickets()
  local raw = read_file(HELP_TICKETS_PATH)
  if not raw or raw == '' then
    help_tickets = {}
    return
  end
  local data = json.decode(raw)
  if type(data) == 'table' and type(data.tickets) == 'table' then
    help_tickets = data.tickets
  elseif type(data) == 'table' and data[1] then
    help_tickets = data
  else
    help_tickets = {}
  end
end

local function help_save_tickets()
  ensure_dirs()
  while #help_tickets > 80 do table.remove(help_tickets, 1) end
  write_file(HELP_TICKETS_PATH, json.encode({ tickets = help_tickets }) or '{"tickets":[]}')
end

local function help_get_tickets()
  return help_tickets
end

local function help_get_state()
  return help_state
end

local function help_get_sel()
  return help_sel
end

local function help_set_sel(i)
  help_sel.idx = math.max(1, tonumber(i) or 1)
end

local function help_ensure_client_id()
  if cfg.help_client_id and cfg.help_client_id ~= '' then return cfg.help_client_id end
  cfg.help_client_id = string.format(
    '%08x-%04x-%04x-%04x-%08x%04x',
    os.time() % 0xffffffff,
    math.random(0, 0xffff),
    math.random(0, 0xffff),
    math.random(0, 0xffff),
    math.random(0, 0xffffffff),
    math.random(0, 0xffff)
  )
  local raw = read_file(CONFIG_PATH) or ''
  if raw:find('HelpClientId=') then
    raw = raw:gsub('HelpClientId=[^\r\n]*', 'HelpClientId=' .. cfg.help_client_id)
  elseif raw:find('%[Telegram%]') then
    raw = raw:gsub('(%[Telegram%][^\r\n]*)', '%1\nHelpClientId=' .. cfg.help_client_id)
  else
    raw = raw .. '\n[Telegram]\nHelpClientId=' .. cfg.help_client_id .. '\n'
  end
  write_file(CONFIG_PATH, raw)
  return cfg.help_client_id
end

local function help_make_ticket_id()
  return string.format('t%08x%04x', os.time() % 0xffffffff, math.random(0, 0xffff))
end

local function help_send(text)
  text = trim(tostring(text or ''))
  if text == '' then
    chat('Помощь: опиши проблему')
    return false
  end
  if not help_configured() then
    chat('Помощь: support-бот ещё не настроен автором')
    help_state.status = 'не настроено'
    return false
  end
  if cfg.chat_id == '' then
    chat('Помощь: сначала укажи Chat ID в Настройках')
    return false
  end
  if help_state.busy then return false end
  help_state.busy = true
  help_state.status = 'отправка…'
  local client_id = help_ensure_client_id()
  local me = get_self_info()
  local nick = tostring(me.nick or '-')
  local server = ''
  pcall(function()
    if sampGetCurrentServerName then server = tostring(sampGetCurrentServerName() or '') end
  end)
  local ticket = {
    id = help_make_ticket_id(),
    client_id = client_id,
    nick = nick,
    server = server,
    text = text,
    user_chat_id = tostring(cfg.chat_id),
    ts = os.time(),
    status = 'pending',
    answer = '',
  }
  local payload = 'TGHELP_TICKET|' .. (json.encode(ticket) or '{}')
  lua_thread.create(function()
    local ok, err = pcall(function()
      local body = table.concat({
        'chat_id=' .. url_encode(HELP_ADMIN_CHAT_ID),
        'text=' .. url_encode(payload),
        'disable_web_page_preview=true',
      }, '&')
      local resp = requests.post('https://api.telegram.org/bot' .. HELP_BOT_TOKEN .. '/sendMessage', {
        data = body,
        headers = { ['Content-Type'] = 'application/x-www-form-urlencoded' },
        timeout = 20,
      })
      local parsed = nil
      if resp and resp.json then
        local jok, j = pcall(resp.json)
        if jok then parsed = j end
      elseif resp and resp.text then
        parsed = json.decode(resp.text)
      end
      if not parsed or not parsed.ok then
        error((parsed and parsed.description) or 'Telegram reject')
      end
    end)
    if ok then
      help_tickets[#help_tickets + 1] = ticket
      help_save_tickets()
      help_state.status = 'отправлено'
      help_sel.idx = #help_tickets
      if ui.help_text then write_char_buf(ui.help_text, 1024, '') end
      chat('Заявка отправлена · ' .. ticket.id)
    else
      help_state.status = 'ошибка'
      chat('Помощь: не удалось отправить (' .. tostring(err) .. ')')
    end
    help_state.busy = false
  end)
  return true
end

local function help_apply_replies(replies)
  if type(replies) ~= 'table' then return 0 end
  local cid = tostring(cfg.help_client_id or '')
  if cid == '' then return 0 end
  local by_id = {}
  for i = 1, #help_tickets do
    local t = help_tickets[i]
    if t and t.id then by_id[tostring(t.id)] = t end
  end
  local n = 0
  for i = 1, #replies do
    local r = replies[i]
    if type(r) == 'table' and tostring(r.client_id or '') == cid then
      local tid = tostring(r.id or '')
      local ans = tostring(r.answer or '')
      if tid ~= '' and ans ~= '' then
        local t = by_id[tid]
        if t then
          if t.answer ~= ans or t.status ~= 'answered' then
            t.answer = ans
            t.status = 'answered'
            t.answered_at = tonumber(r.ts) or os.time()
            n = n + 1
          end
        else
          help_tickets[#help_tickets + 1] = {
            id = tid,
            client_id = cid,
            nick = '-',
            text = tostring(r.question or ''),
            status = 'answered',
            answer = ans,
            ts = tonumber(r.ts) or os.time(),
            answered_at = tonumber(r.ts) or os.time(),
          }
          n = n + 1
        end
      end
    end
  end
  if n > 0 then help_save_tickets() end
  return n
end

local function help_poll_replies(force)
  if help_state.busy then return end
  if UPDATE_OWNER == 'YOUR_GITHUB_USER' then
    if force then help_state.status = 'укажи UPDATE_OWNER для ответов' end
    return
  end
  if not force and help_state.poll_at > 0 and (os.time() - help_state.poll_at) < 25 then
    return
  end
  help_state.busy = true
  if force then help_state.status = 'проверка ответов…' end
  lua_thread.create(function()
    local ok = pcall(function()
      local resp, herr = extras.http_get_raw(HELP_REPLIES_URL)
      help_state.poll_at = os.time()
      if not resp or (tonumber(resp.status_code) or 0) ~= 200 then
        if force then help_state.status = herr or 'нет help_replies.json' end
        return
      end
      local body = resp.text or resp.content or ''
      local data = json.decode(body)
      local replies = type(data) == 'table' and (data.replies or data) or nil
      local n = help_apply_replies(replies)
      if force then
        help_state.status = n > 0 and ('новых ответов: ' .. n) or 'новых ответов нет'
      elseif n > 0 then
        help_state.status = 'ответ получен'
        chat('Помощь: пришёл ответ (' .. n .. ')')
      end
    end)
    if not ok and force then help_state.status = 'ошибка опроса' end
    help_state.busy = false
  end)
end


  return {

    help_configured = help_configured,

    help_send = help_send,

    help_poll_replies = help_poll_replies,

    help_get_tickets = help_get_tickets,

    help_get_state = help_get_state,

    help_get_sel = help_get_sel,

    help_set_sel = help_set_sel,

    help_load_tickets = help_load_tickets,

    help_ensure_client_id = help_ensure_client_id,

  }

end)()

local function get_nearby_players(radius, limit)
  radius = tonumber(radius) or 50
  limit = tonumber(limit) or 28
  local list = {}
  if not isSampAvailable() then return list end
  local okc, mx, my, mz = pcall(getCharCoordinates, PLAYER_PED)
  if not okc then return list end
  local myId = get_my_id()
  for id = 0, 999 do
    if id ~= myId then
      local connected = false
      pcall(function() connected = sampIsPlayerConnected(id) end)
      if connected then
        local okp, ped = sampGetCharHandleBySampPlayerId(id)
        if okp and ped and doesCharExist(ped) then
          local ox, oy, oz = getCharCoordinates(ped)
          local dist = getDistanceBetweenCoords3d(mx, my, mz, ox, oy, oz)
          if dist <= radius then
            local nick, hp, armor = ('#' .. id), 0, 0
            pcall(function() nick = sampGetPlayerNickname(id) or nick end)
            pcall(function() hp = sampGetPlayerHealth(id) or 0 end)
            pcall(function() armor = sampGetPlayerArmor(id) or 0 end)
            list[#list + 1] = {
              id = id,
              nick = to_ui(nick),
              dist = dist,
              hp = hp,
              armor = armor,
            }
          end
        end
      end
    end
  end
  table.sort(list, function(a, b) return a.dist < b.dist end)
  if #list > limit then
    for i = #list, limit + 1, -1 do list[i] = nil end
  end
  return list
end

local function to_game_text(text)
  text = tostring(text or '')
  -- ASCII-команды (/admins и т.п.) не гоняем через encoding
  if text:match('^[\32-\126]+$') then
    return text
  end
  local ok, dec = pcall(cp, text)
  if ok and dec and dec ~= '' then return dec end
  return text
end

local function send_game_chat(text)
  text = trim(tostring(text or ''))
  if text == '' then return false end
  local payload = to_game_text(text)

  local function do_send()
    -- на Arizona надёжнее ProcessChatInput (как будто ввёл в чат сам)
    if type(sampProcessChatInput) == 'function' then
      local ok = pcall(sampProcessChatInput, payload)
      if ok then return true end
    end
    if type(sampSendChat) == 'function' then
      local ok = pcall(sampSendChat, payload)
      if ok then return true end
    end
    return false
  end

  -- из imgui-кадра sendCMD часто глотается — шлём на следующем тике
  if type(lua_thread) == 'table' and lua_thread.create then
    lua_thread.create(function()
      wait(80)
      if not do_send() then
        chat('Не удалось отправить: ' .. text)
      end
    end)
    return true
  end
  return do_send()
end

local function copy_text(text)
  text = tostring(text or '')
  if not imgui then return false end
  local ok = pcall(function() imgui.SetClipboardText(text) end)
  return ok
end

local function read_clipboard()
  local text = ''
  if not imgui then return '' end
  pcall(function() text = imgui.GetClipboardText() or '' end)
  return tostring(text or '')
end

local function read_cmd_buf()
  local ffi = require 'ffi'
  local raw = ''
  pcall(function() raw = ffi.string(ui.utils_cmd) end)
  return trim((raw or ''):gsub('%z', ''))
end

local function write_cmd_buf(s)
  s = tostring(s or '')
  pcall(function()
    local ffi = require 'ffi'
    ffi.fill(ui.utils_cmd, 96)
    ffi.copy(ui.utils_cmd, s, math.min(#s, 95))
  end)
end

local function read_pm_buf()
  local ffi = require 'ffi'
  local raw = ''
  pcall(function() raw = ffi.string(ui.utils_pm) end)
  return trim((raw or ''):gsub('%z', ''))
end

local function write_pm_buf(s)
  s = tostring(s or '')
  pcall(function()
    local ffi = require 'ffi'
    ffi.fill(ui.utils_pm, 128)
    ffi.copy(ui.utils_pm, s, math.min(#s, 127))
  end)
end

local function read_note_buf()
  local ffi = require 'ffi'
  local raw = ''
  pcall(function() raw = ffi.string(ui.utils_note) end)
  return trim((raw or ''):gsub('%z', ''))
end

local function write_note_buf(s)
  s = tostring(s or '')
  pcall(function()
    local ffi = require 'ffi'
    ffi.fill(ui.utils_note, 128)
    ffi.copy(ui.utils_note, s, math.min(#s, 127))
  end)
end

local function hist_push(cmd)
  cmd = trim(tostring(cmd or ''))
  if cmd == '' then return end
  for i = #utils_hist, 1, -1 do
    if utils_hist[i] == cmd then table.remove(utils_hist, i) end
  end
  table.insert(utils_hist, 1, cmd)
  while #utils_hist > HIST_MAX do utils_hist[#utils_hist] = nil end
  save_state()
end

local function fav_add(cmd)
  cmd = trim(tostring(cmd or ''))
  if cmd == '' then return false, 'пусто' end
  if not cmd:match('^/') then cmd = '/' .. cmd end
  for i = 1, #utils_favs do
    if utils_favs[i] == cmd then return false, 'уже есть' end
  end
  if #utils_favs >= FAV_MAX then return false, 'лимит ' .. FAV_MAX end
  utils_favs[#utils_favs + 1] = cmd
  save_ini()
  return true
end

local function fav_remove(idx)
  idx = tonumber(idx)
  if not idx or idx < 1 or idx > #utils_favs then return false end
  table.remove(utils_favs, idx)
  save_ini()
  return true
end

local function paste_id_from_clip()
  local raw = read_clipboard()
  local id = raw:match('(%d+)')
  if not id then
    chat('В буфере нет ID')
    return false
  end
  utils_sel_id = tonumber(id)
  chat('Выбран ID ' .. tostring(utils_sel_id) .. ' из буфера')
  return true
end

local function sync_note_buf_for_sel()
  local key = tostring(utils_sel_id)
  if utils_sel_id < 0 then
    write_note_buf('')
    return
  end
  write_note_buf(utils_notes[key] or '')
end

local function save_note_for_sel()
  if utils_sel_id < 0 then
    chat('Сначала выбери игрока')
    return
  end
  local key = tostring(utils_sel_id)
  local note = read_note_buf()
  if note == '' then
    utils_notes[key] = nil
  else
    utils_notes[key] = note
  end
  save_state()
  chat(note == '' and ('Заметка удалена для ' .. key) or ('Заметка сохранена для ' .. key))
end

local _utils_sel_prev = -2

local function utils_run_cmd(tpl)
  tpl = trim(tostring(tpl or ''))
  if tpl == '' then return false end
  if not tpl:match('^/') then
    tpl = '/' .. tpl
  end
  local id = utils_sel_id
  if tpl:find('{id}', 1, true) then
    if not id or id < 0 then
      chat('Сначала выбери игрока в списке')
      return false
    end
    tpl = tpl:gsub('{id}', tostring(id))
  end
  if send_game_chat(tpl) then
    hist_push(tpl)
    chat('CMD: ' .. tpl)
    return true
  end
  chat('Не удалось отправить: ' .. tpl)
  return false
end

local function send_pm_to_sel()
  if not utils_sel_id or utils_sel_id < 0 then
    chat('Сначала выбери игрока')
    return false
  end
  local msg = read_pm_buf()
  if msg == '' then
    chat('Введи текст личного сообщения')
    return false
  end
  if utils_run_cmd('/pm {id} ' .. msg) then
    write_pm_buf('')
    return true
  end
  return false
end

local RE_REPORT_FULL = cp('%[Жалоба%] от (%S+)%[(%d+)%]: (.+)%. Всего (%d+) жалоб')
local RE_REPORT_SHORT = cp('%[Жалоба%] от (%S+)%[(%d+)%]: (.+)')
local RE_TOTAL = cp('Всего (%d+) жалоб')

local function handle_chat(raw_text)
  local text = strip_colors(raw_text or '')
  if text == '' then return end

  if cfg.reports then
    local nick, id, body, total = text:match(RE_REPORT_FULL)
    if nick then
      last_queue = tonumber(total); save_state(); consider_queue(last_queue); return
    end
    nick, id, body = text:match(RE_REPORT_SHORT)
    if nick then
      local q = text:match(RE_TOTAL)
      if q then last_queue = tonumber(q); save_state(); consider_queue(last_queue) end
      return
    end
    local only_total = text:match(RE_TOTAL)
    if only_total then
      last_queue = tonumber(only_total); save_state(); consider_queue(last_queue); return
    end
  end

  if cfg.mentions then
    local me = get_my_nick()
    if me and me ~= '' then
      local pat = '@' .. me:lower()
      if text:lower():find(pat, 1, true) then
        local sig = text:sub(1, 80)
        if sig ~= last_mention_sig then
          last_mention_sig = sig
          notify('mention', cp('Arizona · Упоминание\n') .. text:sub(1, 400), {})
        end
      end
    end
  end
end

local function notify_admin_form(cmd, tag)
  local sig = tostring(cmd) .. ':' .. tostring(tag) .. ':' .. tostring(os.time())
  if sig == last_form_sig then return end
  last_form_sig = sig
  notify('form',
    cp('Arizona · Админ-форма\n') .. tostring(cmd) .. (tag ~= '' and (' // ' .. tag) or ''),
    { cmd = cmd, tag = tag })
end

function sampev.onServerMessage(color, text)
  pcall(handle_chat, text)
end

function sampev.onSendChat(message)
  pcall(touch_activity)
end

function sampev.onSendCommand(command)
  pcall(function()
    touch_activity()
    last_outgoing_cmd = tostring(command or '')
    if not cfg.forms then return end
    local cmd = last_outgoing_cmd:match('^/(%S+)') or last_outgoing_cmd:match('^(%S+)')
    if not cmd then return end
    cmd = cmd:lower()
    if form_cmds[cmd] then
      local tag = last_outgoing_cmd:match('//%s*(.+)$') or ''
      notify_admin_form('/' .. cmd, trim(tag))
    end
  end)
end

local function read_tools_info()
  local raw = read_file(STATS_PATH)
  if not raw then return nil end
  local data = json.decode(raw)
  if type(data) ~= 'table' or type(data.info) ~= 'table' then return nil end
  return data.info
end

local function read_tools_queue()
  local info = read_tools_info()
  if not info then return nil end
  local q = info.queue
  if type(q) == 'table' and q.count ~= nil then return tonumber(q.count) end
  return nil
end

-- Arizona Tools → info.online (сессия, иначе день) — не путать с active
local function read_tools_online()
  local info = read_tools_info()
  if not info then return nil end
  local o = info.online
  if type(o) == 'number' then return o end
  if type(o) ~= 'table' then return nil end
  if type(o.ses) == 'table' and o.ses.count ~= nil then
    return tonumber(o.ses.count)
  end
  if type(o.day) == 'table' and o.day.count ~= nil then
    return tonumber(o.day.count)
  end
  if o.count ~= nil then return tonumber(o.count) end
  return nil
end

local function read_tools_afk()
  local info = read_tools_info()
  if not info then return nil end
  local a = info.afk
  if type(a) == 'number' then return a end
  if type(a) ~= 'table' then return nil end
  if type(a.ses) == 'table' and a.ses.count ~= nil then
    return tonumber(a.ses.count)
  end
  if type(a.day) == 'table' and a.day.count ~= nil then
    return tonumber(a.day.count)
  end
  if a.count ~= nil then return tonumber(a.count) end
  return nil
end

local function format_active_sec(sec)
  sec = math.floor(tonumber(sec) or 0)
  if sec < 0 then sec = 0 end
  if sec < 60 then return tostring(sec) .. 's' end
  local m = math.floor(sec / 60)
  local s = sec % 60
  if m < 60 then return string.format('%dm %02ds', m, s) end
  local h = math.floor(m / 60)
  m = m % 60
  return string.format('%dh %02dm', h, m)
end

local function sync_clips_ui()
  local st = ipc.read_status()
  if st and st.send_clips ~= nil then
    ui.send_clips[0] = not not st.send_clips
  else
    ui.send_clips[0] = cfg.clips
  end
end

local function clips_set_enabled(on)
  ui.send_clips[0] = not not on
  cfg.clips = not not on
  ipc.write_cmd('set_clips=' .. (on and '1' or '0'))
end

local function format_clip_dur(sec)
  sec = math.floor(tonumber(sec) or 0)
  if sec < 0 then sec = 0 end
  return string.format('%02d:%02d', math.floor(sec / 60), sec % 60)
end

local ui_frame_ready = false

local function ensure_imgui()
  if imgui_ready and imgui and menu_ui and ui.bot_token then return true end
  local ok, err = pcall(function()
    if not imgui then
      imgui = require 'mimgui'
    end
    if not menu_ui then
      package.loaded['arizona_tg_public_ui'] = nil
      menu_ui = require 'arizona_tg_public_ui'
    end
    local was_open = showMenu and showMenu[0] or false
    showMenu = imgui.new.bool(was_open and true or false)
    ui.reports = imgui.new.bool(cfg.reports and true or false)
    ui.forms = imgui.new.bool(cfg.forms and true or false)
    ui.mentions = imgui.new.bool(cfg.mentions and true or false)
    ui.watch_queue = imgui.new.bool(cfg.watch_queue and true or false)
    ui.quiet_mode = imgui.new.bool(cfg.quiet_mode and true or false)
    ui.queue_from = imgui.new.int(tonumber(cfg.queue_from) or 10)
    ui.queue_afk_from = imgui.new.int(tonumber(cfg.queue_afk_from) or 5)
    ui.afk_sec = imgui.new.int(tonumber(cfg.afk_sec) or 90)
    ui.cooldown = imgui.new.int(tonumber(cfg.cooldown) or 3)
    ui.send_clips = imgui.new.bool(cfg.clips and true or false)
    ui.utils_radius = imgui.new.int(50)
    ui.utils_cmd = imgui.new.char[96]()
    ui.utils_note = imgui.new.char[128]()
    ui.utils_pm = imgui.new.char[128]()
    ui.events_rename = imgui.new.char[96]()
    ui.events_add = imgui.new.char[96]()
    ui.org_add = imgui.new.char[96]()
    ui.bot_token = imgui.new.char[192]()
    ui.chat_id = imgui.new.char[64]()
    ui.help_text = imgui.new.char[1024]()
    ui.win_w = imgui.new.int(tonumber(cfg.win_w) or 1000)
    ui.win_h = imgui.new.int(tonumber(cfg.win_h) or 640)
    if P then
      P.imgui = imgui
      P.ui = ui
      P.showMenu = showMenu
    end
  end)
  if not ok then
    imgui_ready = false
    chat('Меню не загрузилось (mimgui). Отключи MCR.luac и похожие. ' .. tostring(err))
    return false
  end
  imgui_ready = true
  return true
end

local function ensure_ui_frame()
  if ui_frame_ready then return true end
  if not ensure_imgui() then return false end
  local ok = pcall(function()
    imgui.OnFrame(
      function()
        if not script_alive then return false end
        local vok, vis = pcall(function()
          return P.showMenu[0] or (menu_ui.is_visible and menu_ui.is_visible())
        end)
        return vok and vis
      end,
      function(player)
        pcall(function() menu_ui.draw(P, player) end)
      end
    )
  end)
  ui_frame_ready = ok and true or false
  if not ok then
    chat('Меню: конфликт mimgui (отключи MCR/другие imgui-скрипты)')
  end
  return ui_frame_ready
end

do
  local path = thisScript().path
  _G.__ML_RELOAD_GUARD = _G.__ML_RELOAD_GUARD or {}
  _G.__ML_RELOAD_GUARD[path] = function()
    return http_inflight > 0
  end
end

addEventHandler('onScriptTerminate', function(scr)
  if scr ~= thisScript() then return end
  script_alive = false
  if _G.__ML_RELOAD_GUARD then
    _G.__ML_RELOAD_GUARD[scr.path] = nil
  end
  pcall(function()
    if showMenu then showMenu[0] = false end
  end)
end)

local function open_menu(tab)
  if not ensure_ui_frame() then return end
  showMenu[0] = true
  sync_ui_from_cfg()
  if tab ~= nil then
    menuTab = tonumber(tab) or menuTab or 1
  end
  if menuTab < 1 or menuTab > 8 then menuTab = 1 end
  if menuTab == 3 then sync_clips_ui() end
  if menu_ui and menu_ui.on_open then menu_ui.on_open() end
end

local function toggle_menu()
  local open = showMenu[0] or (menu_ui and menu_ui.is_visible and menu_ui.is_visible())
  if open then
    if imgui_ready then
      apply_ui_to_cfg()
      if ui.send_clips then clips_set_enabled(ui.send_clips[0]) end
      if menu_ui and menu_ui.request_close then menu_ui.request_close() end
    end
    showMenu[0] = false
  else
    open_menu()
  end
end

local function apply_menu_style()
  if not imgui then return end
  local function im4(col, a)
    return imgui.ImVec4(col.x, col.y, col.z, a or col.w or 1)
  end
  local s = imgui.GetStyle()
  s.WindowRounding = ROUND
  s.ChildRounding = 10
  s.FrameRounding = 8
  s.GrabRounding = 8
  s.ScrollbarRounding = 8
  s.WindowPadding = imgui.ImVec2(0, 0)
  s.FramePadding = imgui.ImVec2(12, 8)
  s.ItemSpacing = imgui.ImVec2(10, 9)
  s.ItemInnerSpacing = imgui.ImVec2(8, 6)
  s.WindowBorderSize = 0
  s.ChildBorderSize = 0
  s.FrameBorderSize = 0
  local c = s.Colors
  c[imgui.Col.WindowBg] = im4(C.panel, 0.02)
  c[imgui.Col.ChildBg] = imgui.ImVec4(0, 0, 0, 0)
  c[imgui.Col.Border] = im4(C.line, 0.12)
  c[imgui.Col.Button] = im4(C.btn)
  c[imgui.Col.ButtonHovered] = im4(C.btn_h)
  c[imgui.Col.ButtonActive] = im4(C.accent2)
  c[imgui.Col.CheckMark] = im4(C.accent)
  c[imgui.Col.SliderGrab] = im4(C.accent)
  c[imgui.Col.SliderGrabActive] = im4(C.accent2)
  if C.light then
    c[imgui.Col.FrameBg] = imgui.ImVec4(0.90, 0.90, 0.88, 0.40)
    c[imgui.Col.FrameBgHovered] = imgui.ImVec4(0.84, 0.84, 0.82, 0.55)
    c[imgui.Col.FrameBgActive] = imgui.ImVec4(0.78, 0.78, 0.76, 0.65)
  else
    c[imgui.Col.FrameBg] = im4(C.btn, 0.32)
    c[imgui.Col.FrameBgHovered] = im4(C.btn_h, 0.45)
    c[imgui.Col.FrameBgActive] = im4(C.accent2, 0.55)
  end
  c[imgui.Col.Text] = im4(C.soft)
  c[imgui.Col.TextDisabled] = im4(C.muted)
  c[imgui.Col.Separator] = im4(C.line)
end

local function send_queue_now()
  apply_ui_to_cfg()
  local qq = read_tools_queue() or last_queue
  if qq == nil then chat('Очередь неизвестна'); return end
  local prev = cfg.quiet_mode
  cfg.quiet_mode = false
  notify('queue', cp('Arizona · Репорты в очереди: ') .. tostring(qq) .. cp(' (меню)'), { queue = qq })
  cfg.quiet_mode = prev
end

local function parse_csv_line(line)
  local fields, i, len = {}, 1, #line
  while i <= len do
    if line:sub(i, i) == '"' then
      local j, buf = i + 1, {}
      while j <= len do
        local c = line:sub(j, j)
        if c == '"' then
          if line:sub(j + 1, j + 1) == '"' then
            buf[#buf + 1] = '"'
            j = j + 2
          else
            j = j + 1
            break
          end
        else
          buf[#buf + 1] = c
          j = j + 1
        end
      end
      fields[#fields + 1] = table.concat(buf)
      if line:sub(j, j) == ',' then j = j + 1 end
      i = j
    else
      local j = line:find(',', i, true) or (len + 1)
      fields[#fields + 1] = line:sub(i, j - 1)
      i = j + 1
    end
  end
  return fields
end

local Ev = (function()

local function events_today_str()
  return os.date('%d.%m.%Y')
end

local function parse_prize(s)
  s = tostring(s or '')
  -- убрать NBSP/пробелы/точки-разделители тысяч
  s = s:gsub('\194\160', ''):gsub('%s+', ''):gsub('%.', ''):gsub(',', '')
  local n = tonumber((s:match('(%d+)')))
  return n or 0
end

local function org_pay_for_prize(prize)
  local n = tonumber(prize) or 0
  if n < 0 then n = 0 end
  if n > ORG_PAY_CAP then n = ORG_PAY_CAP end
  return n
end

local function parse_date_ts(date_part)
  local d, m, y = tostring(date_part or ''):match('^(%d%d)%.(%d%d)%.(%d%d%d%d)$')
  if not d then return nil end
  return os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
end

-- понедельник 00:00 недели, в которой лежит ts
local function week_monday_ts(ts)
  ts = tonumber(ts) or os.time()
  local t = os.date('*t', ts)
  local since_mon = (t.wday + 5) % 7 -- Mon=0 … Sun=6
  local mid = os.time({ year = t.year, month = t.month, day = t.day, hour = 0, min = 0, sec = 0 })
  return mid - since_mon * 86400
end

local function fmt_org_money(n)
  n = tonumber(n) or 0
  if n <= 0 then return '0' end
  if n >= 1000000 then
    local m = n / 1000000
    if math.abs(m - math.floor(m + 1e-6)) < 0.05 then
      return string.format('%d млн', math.floor(m + 1e-6))
    end
    return string.format('%.1f млн', m)
  end
  if n >= 1000 then
    return string.format('%d тыс', math.floor(n / 1000 + 0.5))
  end
  return tostring(math.floor(n))
end

local function events_apply_csv(raw, yieldable, from_net)
  raw = tostring(raw or '')
  local today = events_today_str()
  local done, today_list, rows = {}, {}, {}
  local nline = 0
  for line in raw:gmatch('[^\r\n]+') do
    nline = nline + 1
    if yieldable and (nline % 100 == 0) then wait(0) end
    if not line:match('^Дата') and trim(line) ~= '' and not line:match('^,+') then
      local f = parse_csv_line(line)
      local dt = trim(f[1] or '')
      local title = trim(f[2] or '')
      local prize = parse_prize(f[4])
      local org = trim(f[5] or '')
      local date_part = dt:match('^(%d%d%.%d%d%.%d%d%d%d)')
      local time_part = dt:match('%s+(%d%d:%d%d)') or ''
      local ts = date_part and parse_date_ts(date_part) or nil
      if date_part and title ~= '' then
        rows[#rows + 1] = {
          name = title,
          org = org,
          prize = prize,
          pay = org_pay_for_prize(prize),
          date = date_part,
          time = time_part,
          ts = ts,
          raw = dt,
        }
        if date_part == today then
          local key = mp_norm(title)
          local row = {
            name = title,
            time = time_part,
            org = org,
            prize = prize,
            raw = dt,
            key = key,
          }
          today_list[#today_list + 1] = row
          done[key] = row
        end
      end
    end
  end
  table.sort(today_list, function(a, b)
    return tostring(a.time) > tostring(b.time)
  end)
  events_state.today = today
  events_state.done = done
  events_state.today_list = today_list
  events_state.rows = rows
  events_state.updated = os.time()
  if from_net then
    events_state.fetched_at = os.time()
  end
  events_state.status = 'ok'
  events_state.err = from_net and '' or 'кэш'
end

local function events_hdr(headers, key)
  if type(headers) ~= 'table' then return nil end
  local want = key:lower()
  for k, v in pairs(headers) do
    if tostring(k):lower() == want then return v end
  end
  return nil
end

local function events_abs_url(base, loc)
  loc = tostring(loc or '')
  if loc == '' then return nil end
  if loc:match('^https?://') then return loc end
  local host = base:match('^(https?://[^/]+)') or ''
  if loc:sub(1, 1) == '/' then return host .. loc end
  local dir = base:match('(.*/)') or (host .. '/')
  return dir .. loc
end

-- Google Sheets отдаёт 307 на другой хост — luasocket сам часто не переходит
local function events_http_get(url)
  local last = nil
  for _ = 1, 6 do
    local ok, resp = pcall(function()
      return requests.get(url, {
        timeout = 25,
        allow_redirects = false,
        headers = {
          ['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) TGNotify/2.4',
          ['Accept'] = 'text/csv,text/plain,*/*',
        },
      })
    end)
    if not ok or type(resp) ~= 'table' then
      return nil, tostring(resp)
    end
    last = resp
    local code = tonumber(resp.status_code) or 0
    if code == 200 then
      return resp, nil
    end
    if code == 301 or code == 302 or code == 303 or code == 307 or code == 308 then
      local loc = events_hdr(resp.headers, 'location')
      local next_url = events_abs_url(url, loc)
      if not next_url then break end
      url = next_url
    else
      break
    end
  end
  return last, nil
end

local function events_fetch(force)
  if events_state.loading then return end
  if not script_alive then return end
  -- первые секунды после входа HTTP часто роняет lua51 вместе с Helper/Tools
  if samp_ready_at > 0 then
    local age = os.time() - samp_ready_at
    if age < BOOT_NET_GRACE then
      if events_state._net_deferred then return end
      events_state._net_deferred = true
      local delay_ms = (BOOT_NET_GRACE - age) * 1000
      if delay_ms < 500 then delay_ms = 500 end
      events_state.status = 'loading'
      lua_thread.create(function()
        wait(delay_ms)
        events_state._net_deferred = false
        if script_alive then events_fetch(force) end
      end)
      return
    end
  end
  local today_empty = #(events_state.today_list or {}) == 0
  if not force and not today_empty and events_state.fetched_at > 0
      and (os.time() - events_state.fetched_at) < 90 then
    return
  end
  events_state.loading = true
  events_state.status = 'loading'
  lua_thread.create(function()
    local urls = {
      string.format(
        'https://docs.google.com/spreadsheets/d/%s/export?format=csv&gid=%s',
        EVENTS_SHEET_ID, EVENTS_GID
      ),
      string.format(
        'https://docs.google.com/spreadsheets/d/%s/gviz/tq?tqx=out:csv&gid=%s',
        EVENTS_SHEET_ID, EVENTS_GID
      ),
    }
    local body, last_code = nil, 0
    for i = 1, #urls do
      if not script_alive then break end
      local resp = select(1, events_http_get(urls[i]))
      if type(resp) == 'table' then
        last_code = tonumber(resp.status_code) or 0
        local text = tostring(resp.text or '')
        if last_code == 200 and text ~= '' and not text:match('<html') and text:find('Дата') then
          body = text
          break
        end
        if last_code == 200 and text ~= '' and not text:match('<html') and #text > 40 then
          body = text
          break
        end
      end
    end
    events_state.loading = false
    if not script_alive then return end
    if not body then
      local cached = read_file(EVENTS_CACHE)
      if cached and cached ~= '' then
        events_apply_csv(cached, true, false)
        events_state.status = 'ok'
        events_state.err = 'кэш (HTTP ' .. tostring(last_code) .. ')'
        chat('МП: не обновилось, показан кэш')
      else
        events_state.status = 'err'
        events_state.err = 'HTTP ' .. tostring(last_code)
        chat('МП: ошибка загрузки таблицы (' .. tostring(last_code) .. ')')
      end
      return
    end
    ensure_dirs()
    write_file(EVENTS_CACHE, body)
    events_apply_csv(body, true, true)
    local n = 0
    for _ in pairs(events_state.done) do n = n + 1 end
    chat(string.format('МП Space: сегодня %d уникальных / %d записей', n, #events_state.today_list))
  end)
end

local function events_is_in_canon(key)
  for i = 1, #MP_RECOMMENDED do
    if mp_norm(MP_RECOMMENDED[i]) == key then return true end
  end
  return false
end

local function events_is_in_extra(key)
  for i = 1, #mp_extra do
    if mp_norm(mp_extra[i]) == key then return true end
  end
  return false
end

-- уже в левом списке (канон/extra и не скрыто)
local function events_has_rec(key_or_name)
  local key = mp_norm(key_or_name)
  if key == '' or mp_hidden[key] then return false end
  return events_is_in_canon(key) or events_is_in_extra(key)
end

local function events_get_list()
  local out = {}
  local seen = {}
  local done = events_state.done or {}
  local function push(name, custom)
    local key = mp_norm(name)
    if key == '' or seen[key] or mp_hidden[key] then return end
    seen[key] = true
    local hit = done[key]
    out[#out + 1] = {
      name = mp_renames[key] or name,
      orig = name,
      key = key,
      done = hit ~= nil,
      time = hit and hit.time or '',
      org = hit and hit.org or '',
      custom = custom and true or false,
    }
  end
  for i = 1, #MP_RECOMMENDED do
    push(MP_RECOMMENDED[i], false)
  end
  for i = 1, #mp_extra do
    push(mp_extra[i], true)
  end
  table.sort(out, function(a, b)
    if a.done ~= b.done then return not a.done end -- сначала не проведённые
    return a.name < b.name
  end)
  return out
end

local function write_add_buf(s)
  s = tostring(s or '')
  pcall(function()
    local ffi = require 'ffi'
    ffi.fill(ui.events_add, 96)
    ffi.copy(ui.events_add, s, math.min(#s, 95))
  end)
end

local function read_add_buf()
  local ffi = require 'ffi'
  local raw = ''
  pcall(function() raw = ffi.string(ui.events_add) end)
  return trim((raw or ''):gsub('%z', ''))
end

local function events_add_rec(name)
  name = trim(tostring(name or ''))
  local key = mp_norm(name)
  if key == '' then return false, 'empty' end
  -- уже в каноне/extra (в т.ч. скрытое канон — вернём)
  if events_is_in_extra(key) and not mp_hidden[key] then
    return false, 'exists'
  end
  if events_is_in_canon(key) then
    if not mp_hidden[key] then return false, 'exists' end
    mp_hidden[key] = nil
    save_state()
    return true
  end
  mp_hidden[key] = nil
  if not events_is_in_extra(key) then
    mp_extra[#mp_extra + 1] = name
  end
  save_state()
  return true
end

local function events_add_from_buf()
  local name = read_add_buf()
  local ok, err = events_add_rec(name)
  if ok then write_add_buf('') end
  return ok, err, name
end

local function events_hide_rec(key_or_name)
  local key = mp_norm(key_or_name)
  if key == '' then return false end
  local kept = {}
  for i = 1, #mp_extra do
    if mp_norm(mp_extra[i]) ~= key then
      kept[#kept + 1] = mp_extra[i]
    end
  end
  mp_extra = kept
  -- всегда hidden: иначе имя из канона/таблицы снова всплывёт
  mp_hidden[key] = true
  if events_rename_key == key then events_rename_key = nil end
  save_state()
  return true
end

local function events_reset_hidden()
  mp_hidden = {}
  mp_renames = {}
  events_rename_key = nil
  save_state()
  return true
end

local function write_rename_buf(s)
  s = tostring(s or '')
  pcall(function()
    local ffi = require 'ffi'
    ffi.fill(ui.events_rename, 96)
    ffi.copy(ui.events_rename, s, math.min(#s, 95))
  end)
end

local function read_rename_buf()
  local ffi = require 'ffi'
  local raw = ''
  pcall(function() raw = ffi.string(ui.events_rename) end)
  return trim((raw or ''):gsub('%z', ''))
end

local function events_begin_rename(key, current_name)
  key = mp_norm(key)
  if key == '' then return false end
  events_rename_key = key
  write_rename_buf(current_name or '')
  return true
end

local function events_apply_rename()
  if not events_rename_key then return false end
  local label = read_rename_buf()
  if label == '' then
    mp_renames[events_rename_key] = nil
  else
    mp_renames[events_rename_key] = label
  end
  events_rename_key = nil
  save_state()
  return true
end

local function events_cancel_rename()
  events_rename_key = nil
  return true
end

local function events_get_rename_key()
  return events_rename_key
end

local function events_get_state()
  return events_state
end

local function events_date_str_ago(days_ago)
  days_ago = tonumber(days_ago) or 0
  if days_ago < 0 then days_ago = 0 end
  return os.date('%d.%m.%Y', os.time() - days_ago * 86400)
end

-- days_ago: 0 = сегодня, 1 = вчера
-- returns list, total_mp, date_str
local function events_get_orgs(days_ago)
  days_ago = tonumber(days_ago) or 0
  local want = events_date_str_ago(days_ago)
  local map = {}
  local total = 0
  local rows = events_state.rows or {}
  for i = 1, #rows do
    local r = rows[i]
    if r.date == want then
      total = total + 1
      local org = org_primary(r.org)
      if org ~= '' then
        local key = mp_norm(org)
        if key ~= '' and not org_hidden[key] then
          local e = map[key]
          if not e then
            e = { name = org, key = key, count = 0, last = '' }
            map[key] = e
          end
          e.count = e.count + 1
          local t = tostring(r.time or '')
          if t ~= '' and t > tostring(e.last or '') then e.last = t end
        end
      end
    end
  end
  local out = {}
  for _, v in pairs(map) do out[#out + 1] = v end
  table.sort(out, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return tostring(a.name) < tostring(b.name)
  end)
  return out, total, want
end

-- помощники за день (все ники после первого, кроме тех кто уже вёл МП)
local function events_get_helpers(days_ago)
  days_ago = tonumber(days_ago) or 0
  local want = events_date_str_ago(days_ago)
  local leaders = events_org_leaders_set()
  local map = {}
  local total = 0

  local function ensure(name)
    local key = mp_norm(name)
    if key == '' or helper_hidden[key] or leaders[key] then return nil end
    local e = map[key]
    if not e then
      e = { name = name, key = key, count = 0, last = '', manual = false }
      map[key] = e
    end
    return e
  end

  for i = 1, #helper_extra do
    local e = ensure(helper_extra[i])
    if e then e.manual = true end
  end

  local rows = events_state.rows or {}
  for i = 1, #rows do
    local r = rows[i]
    if r.date == want then
      local helps = org_helpers_raw(r.org)
      for hi = 1, #helps do
        local e = ensure(helps[hi])
        if e then
          total = total + 1
          e.count = e.count + 1
          local t = tostring(r.time or '')
          if t ~= '' and t > tostring(e.last or '') then e.last = t end
        end
      end
    end
  end

  local out = {}
  for _, v in pairs(map) do
    if (v.count or 0) > 0 or v.manual then
      out[#out + 1] = v
    end
  end
  table.sort(out, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return tostring(a.name) < tostring(b.name)
  end)
  return out, total, want
end

local function events_hide_helper(key_or_name)
  local key = mp_norm(key_or_name)
  if key == '' then return false end
  local kept = {}
  for i = 1, #helper_extra do
    if mp_norm(helper_extra[i]) ~= key then
      kept[#kept + 1] = helper_extra[i]
    end
  end
  helper_extra = kept
  helper_hidden[key] = true
  save_state()
  return true
end

local function events_reset_helpers()
  helper_hidden = {}
  helper_extra = {}
  save_state()
  return true
end

-- помощники: неделя / прошлая / за всё время (все после первого, кроме ведущих)
local function events_get_helpers_stats()
  local now = os.time()
  local week0 = week_monday_ts(now)
  local week1 = week0 + 7 * 86400
  local prev0 = week0 - 7 * 86400
  local leaders = events_org_leaders_set()
  local map = {}

  local function ensure(name)
    local key = mp_norm(name)
    if key == '' or helper_hidden[key] or leaders[key] then return nil end
    local e = map[key]
    if not e then
      e = {
        name = name,
        key = key,
        week_n = 0, week_pay = 0,
        prev_n = 0, prev_pay = 0,
        all_n = 0,
      }
      map[key] = e
    end
    return e
  end

  local rows = events_state.rows or {}
  for i = 1, #rows do
    local r = rows[i]
    local helps = org_helpers_raw(r.org)
    for hi = 1, #helps do
      local e = ensure(helps[hi])
      if e then
        e.all_n = e.all_n + 1
        local ts = tonumber(r.ts)
        local pay = tonumber(r.pay) or org_pay_for_prize(r.prize)
        if ts and ts >= week0 and ts < week1 then
          e.week_n = e.week_n + 1
          e.week_pay = e.week_pay + pay
        elseif ts and ts >= prev0 and ts < week0 then
          e.prev_n = e.prev_n + 1
          e.prev_pay = e.prev_pay + pay
        end
      end
    end
  end

  local out = {}
  for _, v in pairs(map) do
    v.week_azp = (v.week_n or 0) * ORG_AZP_PER
    v.prev_azp = (v.prev_n or 0) * ORG_AZP_PER
    v.week_pay_s = fmt_org_money(v.week_pay)
    v.prev_pay_s = fmt_org_money(v.prev_pay)
    out[#out + 1] = v
  end
  table.sort(out, function(a, b)
    if a.week_n ~= b.week_n then return a.week_n > b.week_n end
    if a.all_n ~= b.all_n then return a.all_n > b.all_n end
    return tostring(a.name) < tostring(b.name)
  end)

  local meta = {
    week_from = os.date('%d.%m', week0),
    week_to = os.date('%d.%m', week1 - 86400),
    prev_from = os.date('%d.%m', prev0),
    prev_to = os.date('%d.%m', week0 - 86400),
  }
  return out, meta
end

local function write_org_buf(s)
  s = tostring(s or '')
  pcall(function()
    local ffi = require 'ffi'
    ffi.fill(ui.org_add, 96)
    ffi.copy(ui.org_add, s, math.min(#s, 95))
  end)
end

local function read_org_buf()
  local ffi = require 'ffi'
  local raw = ''
  pcall(function() raw = ffi.string(ui.org_add) end)
  return trim((raw or ''):gsub('%z', ''))
end

local function events_add_org(name)
  name = trim(tostring(name or ''))
  name = trim((name:match('^([^,;/]+)') or name))
  local key = mp_norm(name)
  if key == '' then return false, 'empty' end
  local was_hidden = org_hidden[key] and true or false
  org_hidden[key] = nil
  for i = 1, #org_extra do
    if mp_norm(org_extra[i]) == key then
      return false, 'exists'
    end
  end
  local in_csv = false
  local rows = events_state.rows or {}
  for i = 1, #rows do
    if mp_norm(org_primary(rows[i].org)) == key then
      in_csv = true
      break
    end
  end
  if in_csv then
    save_state()
    if was_hidden then return true end
    return false, 'exists'
  end
  org_extra[#org_extra + 1] = name
  save_state()
  return true
end

local function events_add_org_from_buf()
  local name = read_org_buf()
  local ok, err = events_add_org(name)
  if ok then write_org_buf('') end
  return ok, err, name
end

-- все следящие: неделя / прошлая / за всё время
local function events_get_orgs_stats()
  local now = os.time()
  local week0 = week_monday_ts(now)
  local week1 = week0 + 7 * 86400
  local prev0 = week0 - 7 * 86400
  local map = {}

  local function ensure(org)
    local key = mp_norm(org)
    if key == '' or org_hidden[key] then return nil end
    local e = map[key]
    if not e then
      e = {
        name = org,
        key = key,
        week_n = 0, week_pay = 0,
        prev_n = 0, prev_pay = 0,
        all_n = 0,
        manual = false,
      }
      map[key] = e
    end
    return e
  end

  for i = 1, #org_extra do
    local e = ensure(org_extra[i])
    if e then e.manual = true end
  end

  local rows = events_state.rows or {}
  for i = 1, #rows do
    local r = rows[i]
    local org = org_primary(r.org)
    if org ~= '' then
      local e = ensure(org)
      if e then
        e.all_n = e.all_n + 1
        local ts = tonumber(r.ts)
        local pay = tonumber(r.pay) or org_pay_for_prize(r.prize)
        if ts and ts >= week0 and ts < week1 then
          e.week_n = e.week_n + 1
          e.week_pay = e.week_pay + pay
        elseif ts and ts >= prev0 and ts < week0 then
          e.prev_n = e.prev_n + 1
          e.prev_pay = e.prev_pay + pay
        end
      end
    end
  end

  local out = {}
  for _, v in pairs(map) do
    v.week_azp = (v.week_n or 0) * ORG_AZP_PER
    v.prev_azp = (v.prev_n or 0) * ORG_AZP_PER
    v.week_pay_s = fmt_org_money(v.week_pay)
    v.prev_pay_s = fmt_org_money(v.prev_pay)
    out[#out + 1] = v
  end
  table.sort(out, function(a, b)
    if a.week_n ~= b.week_n then return a.week_n > b.week_n end
    if a.all_n ~= b.all_n then return a.all_n > b.all_n end
    return tostring(a.name) < tostring(b.name)
  end)

  local meta = {
    week_from = os.date('%d.%m', week0),
    week_to = os.date('%d.%m', week1 - 86400),
    prev_from = os.date('%d.%m', prev0),
    prev_to = os.date('%d.%m', week0 - 86400),
  }
  return out, meta
end

local function events_hide_org(key_or_name)
  local key = mp_norm(key_or_name)
  if key == '' then return false end
  local kept = {}
  for i = 1, #org_extra do
    if mp_norm(org_extra[i]) ~= key then
      kept[#kept + 1] = org_extra[i]
    end
  end
  org_extra = kept
  -- всегда hidden: иначе ник из таблицы Space снова в «Все следящие»
  org_hidden[key] = true
  save_state()
  return true
end

local function events_reset_orgs()
  org_hidden = {}
  save_state()
  return true
end

  return {

    events_today_str = events_today_str,
    fmt_org_money = fmt_org_money,
    events_apply_csv = events_apply_csv,
    events_fetch = events_fetch,
    events_has_rec = events_has_rec,
    events_get_list = events_get_list,
    events_add_rec = events_add_rec,
    events_add_from_buf = events_add_from_buf,
    events_hide_rec = events_hide_rec,
    events_reset_hidden = events_reset_hidden,
    events_begin_rename = events_begin_rename,
    events_apply_rename = events_apply_rename,
    events_cancel_rename = events_cancel_rename,
    events_get_rename_key = events_get_rename_key,
    events_get_state = events_get_state,
    events_get_orgs = events_get_orgs,
    events_get_helpers = events_get_helpers,
    events_hide_helper = events_hide_helper,
    events_reset_helpers = events_reset_helpers,
    events_get_helpers_stats = events_get_helpers_stats,
    events_add_org = events_add_org,
    events_add_org_from_buf = events_add_org_from_buf,
    events_get_orgs_stats = events_get_orgs_stats,
    events_hide_org = events_hide_org,
    events_reset_orgs = events_reset_orgs,

  }

end)()



P = {
  imgui = imgui, bit = bit, cfg = cfg, ui = ui, C = C, c4 = c4,
  showMenu = showMenu, THEMES = THEMES, ipc = ipc,
  WIN_W = WIN_W, WIN_H = WIN_H, SIDE_W = SIDE_W, ROUND = ROUND,
  theme_textures = theme_textures,
  apply_menu_style = apply_menu_style,
  draw_theme_background = draw_theme_background,
  read_tools_queue = read_tools_queue,
  read_tools_online = read_tools_online,
  read_tools_afk = read_tools_afk,
  format_active_sec = format_active_sec,
  is_afk = is_afk,
  inactive_sec = inactive_sec,
  get_my_nick = get_my_nick,
  apply_ui_to_cfg = apply_ui_to_cfg,
  notify = notify,
  cp = cp,
  chat = chat,
  send_queue_now = send_queue_now,
  format_clip_dur = format_clip_dur,
  clips_set_enabled = clips_set_enabled,
  ensure_theme_textures = ensure_theme_textures,
  apply_theme = apply_theme,
  save_ini = save_ini,
  load_ini = load_ini,
  load_form_cmds = load_form_cmds,
  sync_ui_from_cfg = sync_ui_from_cfg,
  sync_clips_ui = sync_clips_ui,
}
P.get_tab = function() return menuTab end
P.set_tab = function(t) menuTab = t end
P.get_style_ready = function() return styleReady end
P.set_style_ready = function(v) styleReady = v end
P.get_queue = function() return last_queue end
P.get_form_cmds = function() return form_cmds_count end
P.get_last_push = function() return last_push_at, last_push_kind end
P.get_nearby_players = get_nearby_players
P.get_self_info = get_self_info
P.send_game_chat = send_game_chat
P.copy_text = copy_text
P.utils_run_cmd = utils_run_cmd
P.get_utils_sel = function() return utils_sel_id end
P.set_utils_sel = function(id)
  utils_sel_id = tonumber(id) or -1
  if utils_sel_id ~= _utils_sel_prev then
    _utils_sel_prev = utils_sel_id
    sync_note_buf_for_sel()
  end
end
P.to_ui = to_ui
P.get_utils_favs = function() return utils_favs end
P.get_utils_hist = function() return utils_hist end
P.fav_add = fav_add
P.fav_remove = fav_remove
P.paste_id_from_clip = paste_id_from_clip
P.read_cmd_buf = read_cmd_buf
P.write_cmd_buf = write_cmd_buf
P.read_pm_buf = read_pm_buf
P.write_pm_buf = write_pm_buf
P.send_pm_to_sel = send_pm_to_sel
P.save_note_for_sel = save_note_for_sel
P.get_note_for = function(id)
  return utils_notes[tostring(id)] or ''
end
P.events_fetch = Ev.events_fetch
P.events_get_list = Ev.events_get_list
P.events_get_state = Ev.events_get_state
P.events_hide_rec = Ev.events_hide_rec
P.events_reset_hidden = Ev.events_reset_hidden
P.events_add_rec = Ev.events_add_rec
P.events_add_from_buf = Ev.events_add_from_buf
P.events_has_rec = Ev.events_has_rec
P.events_get_orgs = Ev.events_get_orgs
P.events_get_orgs_stats = Ev.events_get_orgs_stats
P.events_hide_org = Ev.events_hide_org
P.events_reset_orgs = Ev.events_reset_orgs
P.events_get_helpers = Ev.events_get_helpers
P.events_get_helpers_stats = Ev.events_get_helpers_stats
P.events_hide_helper = Ev.events_hide_helper
P.events_reset_helpers = Ev.events_reset_helpers
P.events_add_org = Ev.events_add_org
P.events_add_org_from_buf = Ev.events_add_org_from_buf
P.fmt_org_money = Ev.fmt_org_money
P.events_begin_rename = Ev.events_begin_rename
P.events_apply_rename = Ev.events_apply_rename
P.events_cancel_rename = Ev.events_cancel_rename
P.events_get_rename_key = Ev.events_get_rename_key
P.SCRIPT_VERSION = SCRIPT_VERSION
P.update_check = extras.update_check
P.get_update_state = extras.get_update_state
P.update_configured = extras.update_configured
P.help_configured = helpmod.help_configured
P.help_send = helpmod.help_send
P.help_poll_replies = helpmod.help_poll_replies
P.help_get_tickets = helpmod.help_get_tickets
P.help_get_state = helpmod.help_get_state
P.help_get_sel = helpmod.help_get_sel
P.help_set_sel = helpmod.help_set_sel
P.help_load_tickets = helpmod.help_load_tickets
P.read_char_buf = read_char_buf
-- imgui.OnFrame регистрируется лениво в ensure_ui_frame() — иначе конфликт с MCR/другими
-- mimgui-скриптами роняет GTA сразу после post-load hooks

addEventHandler('onWindowMessage', function(msg, wparam, lparam)
  -- клики/клавиши в открытом меню не сбрасывают AFK/online
  local menu_open = showMenu and showMenu[0]
  if not menu_open then
    if msg == WM_KEYDOWN or msg == WM_SYSKEYDOWN
      or msg == WM_LBUTTONDOWN or msg == WM_RBUTTONDOWN
      or msg == WM_MBUTTONDOWN or msg == WM_MOUSEWHEEL
      or msg == WM_XBUTTONDOWN then
      touch_activity()
    end
  end
  if msg == WM_KEYDOWN or msg == WM_SYSKEYDOWN then
    if isSampAvailable() and sampIsChatInputActive() then return end
    if wparam == VK_DELETE or wparam == VK_DECIMAL then
      local open = showMenu[0] or (menu_ui and menu_ui.is_visible and menu_ui.is_visible())
      if open then toggle_menu() else open_menu() end
      return
    end
    -- Esc закрывает сразу, без паузы игры
    if wparam == VK_ESCAPE and (showMenu[0] or (menu_ui and menu_ui.is_visible and menu_ui.is_visible())) then
      apply_ui_to_cfg()
      if ui.send_clips then clips_set_enabled(ui.send_clips[0]) end
      if menu_ui and menu_ui.request_close then menu_ui.request_close() end
      showMenu[0] = false
      pcall(consumeWindowMessage, true, true)
      return
    end
  end
end)

function main()
  local ok_main, err_main = pcall(function()
    ensure_dirs()
    if not load_ini() then
      while not isSampAvailable() do wait(100) end
      chat('Public: открой /tgpub → Настройки → впиши Bot Token и Chat ID')
    end
    -- sync_ui_from_cfg только после ensure_imgui (открытие меню)
    pcall(load_state)
    pcall(function() helpmod.help_load_tickets() end)
    pcall(function() helpmod.help_ensure_client_id() end)
    local nforms = 0
    pcall(function() nforms = load_form_cmds() or 0 end)
    -- CSV кэш — в фоне с yield, не на старте main (иначе микрофриз/краш с другими скриптами)
    lua_thread.create(function()
      wait(3000)
      local cached = read_file(EVENTS_CACHE)
      if cached and cached ~= '' then
        pcall(function()
          Ev.events_apply_csv(cached, true)
          events_state.err = 'кэш'
        end)
      end
    end)
    touch_activity()
    while not isSampAvailable() do wait(100) end
    wait(2000)
    samp_ready_at = os.time()
    pcall(function()
      chat(string.format(
        'TG Public %s | Del /tgpub | /tgpubstatus | /tgptest',
        SCRIPT_VERSION
      ))
    end)
    if _G.__TGPUB_NEED_RESTART then
      pcall(function()
        chat('Обновление на диске — полностью закрой GTA и зайди снова')
      end)
      _G.__TGPUB_NEED_RESTART = nil
    end

    -- БЕЗ авто HTTP при старте (requests блокирует весь клиент → краш с Helper/ArzMarket).
    -- МП/update/help только вручную: Обновить в меню, /tgpubupdate, вкладка Помощь.

    pcall(sampRegisterChatCommand, 'tgpub', function()
      pcall(toggle_menu)
    end)
    pcall(sampRegisterChatCommand, 'tgpubstatus', function()
      local wd = getWorkingDirectory()
      local function ex(p)
        local f = io.open(p, 'rb'); if f then f:close(); return true end; return false
      end
      chat(string.format(
        'Public %s | token:%s chat:%s | lib ipc:%s ui:%s | menu:%s | forms:%d',
        SCRIPT_VERSION,
        (cfg.token ~= '' and 'ok' or 'нет'),
        (cfg.chat_id ~= '' and 'ok' or 'нет'),
        ex(wd .. '\\lib\\arizona_ipc_public.lua') and 'ok' or 'НЕТ',
        ex(wd .. '\\lib\\arizona_tg_public_ui.lua') and 'ok' or 'НЕТ',
        imgui_ready and 'ok' or 'закрыто',
        nforms
      ))
    end)
    pcall(sampRegisterChatCommand, 'tgpubupdate', function()
      pcall(function() extras.update_check(true, false) end)
    end)
    pcall(sampRegisterChatCommand, 'tgptest', function()
      notify('test', cp('Arizona Public · Тест\nЕсли видите это — ваш бот работает.'), {})
      chat('Тест отправлен в ваш Telegram')
    end)
    pcall(sampRegisterChatCommand, 'tgpubqueue', function()
      local q = read_tools_queue() or last_queue
      if q == nil then chat('Очередь пока неизвестна'); return end
      chat(string.format('Очередь: %s | AFK: %s (%dс)', tostring(q), is_afk() and 'да' or 'нет', inactive_sec()))
      local prev = cfg.quiet_mode; cfg.quiet_mode = false
      notify('queue', cp('Arizona Public · Репорты в очереди: ') .. tostring(q), { queue = q })
      cfg.quiet_mode = prev
    end)
    pcall(sampRegisterChatCommand, 'tgpubreload', function()
      local ok = load_ini()
      local n = load_form_cmds()
      sync_ui_from_cfg()
      chat(ok and ('Конфиг перечитан, форм: ' .. n) or ('Нет токена в Настройках, форм: ' .. n))
    end)

    while script_alive do
      wait(2000)
      if not script_alive then break end
      pcall(function()
        if cfg.watch_queue or cfg.reports then
          local q = read_tools_queue()
          if q ~= nil then
            if q ~= last_queue then last_queue = q; save_state() end
            consider_queue(q)
          elseif last_queue ~= nil then
            consider_queue(last_queue)
          end
        end
      end)
    end
  end)
  if not ok_main then
    pcall(function()
      if isSampAvailable() then
        sampAddChatMessage('{FF5555}[TG Public] crash: {FFFFFF}' .. tostring(err_main), -1)
      end
    end)
    while true do wait(10000) end
  end
end
