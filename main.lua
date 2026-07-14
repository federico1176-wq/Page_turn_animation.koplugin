--[[--
Software page turn "erase/wipe" animation for e-ink devices — koplugin.

This is the koplugin version of the original 2-sw-page-turn-animation.lua
user patch. Same behavior, same tunables, same menu location, but now it's
a real plugin: it can be turned off from the Plugin Manager (Settings
(gear) -> More tools -> Plugin manager) and ALSO has its own "Plugin active"
switch in its own submenu that reverts the monkey-patches immediately,
without restarting KOReader.

IMPORTANT (migration from the old patch):
  - If 2-sw-page-turn-animation.lua is still installed in your patches/
    folder, DELETE or rename it before installing this plugin. Both would
    try to patch the same functions, and this file guards against that
    (it will refuse to patch and log a warning) but it's cleaner to only
    have one of the two installed.

IMPORTANT (compatibility with the other numbered patches):
  - 3-animation-style-picker.lua, 2-screen-transition-animations.lua, etc.
    hook into UIManager._repaint / Screen on top of this one, using
    userpatch.getUpValue() the same way this file fetches refresh_methods
    and update_dither from core. As long as this plugin loads BEFORE those
    patches (patches load after plugins during KOReader startup, so this
    should hold in practice), they'll keep working exactly as before,
    because upvalues live on the function object itself, not on whether
    the code that created it was a "patch" or a "plugin".
  - CAVEAT: if you use the in-menu "Plugin active" switch to turn this OFF
    *during* a running session (not a restart), and another patch has
    already wrapped UIManager._repaint on top of this one, that other
    patch's wrapper will be silently dropped until you restart KOReader
    (turning this back ON does not restore their wrapper, only ours).
    Full restarts don't have this problem. If you rely on the style
    picker / screen transitions patches, prefer restarting KOReader over
    toggling "Plugin active" mid-session.

Covers both fixed-layout documents (ReaderPaging: PDF, DjVu, comics...)
and reflowable documents in paginated mode (ReaderRolling: EPUB, FB2,
TXT...). Reflowable documents in "scroll" view mode are not affected,
since there's no discrete page turn to animate there.

Menu: Settings (gear) -> Tools -> More tools -> Software page turn
animation, with:
  - Plugin active (real enable/disable, reverts patches instantly)
  - Enable animation (mirrors the native toggle)
  - Number of steps (free spinner, 2 to 24)
  - Animation speed (ms per step, 5 to 100)
--]] --

local Device = require("device")
local Event = require("ui/event")
local ReaderPaging = require("apps/reader/modules/readerpaging")
local ReaderRolling = require("apps/reader/modules/readerrolling")
local Screen = Device.screen
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local dbg = require("dbg")
local userpatch = require("userpatch")
local _ = require("gettext")
local T = require("ffi/util").template

local DEBUG = false -- set to true for verbose per-step logging

-- ============ TUNABLES (defaults, overridden by the menu below) ==========
local DEFAULT_STEPS = 8
local DEFAULT_DELAY_MS = 20
local SETTING_KEY_STEPS = "page_turn_animation_steps"
local SETTING_KEY_DELAY = "page_turn_animation_delay_ms"
local SETTING_KEY_PLUGIN_ENABLED = "page_turn_animation_plugin_enabled"

-- Speed presets: each sets both step count and per-step delay together.
-- "Instant" still shows a (very short) wipe -- if you want no animation at
-- all, use the "Enable animation" toggle instead.
local SPEED_PRESETS = {
    { key = "slow",    text = _("Slow"),    steps = 16, delay_ms = 40 },
    { key = "medium",  text = _("Medium"),  steps = 8,  delay_ms = 20 },
    { key = "fast",    text = _("Fast"),    steps = 4,  delay_ms = 10 },
    { key = "instant", text = _("Instant"), steps = 2,  delay_ms = 5 },
}

local function getSteps()
    return G_reader_settings:readSetting(SETTING_KEY_STEPS, DEFAULT_STEPS)
end
local function getDelayUs()
    -- Stored in ms (friendlier in the UI), yieldToEPDC wants microseconds.
    return G_reader_settings:readSetting(SETTING_KEY_DELAY, DEFAULT_DELAY_MS) * 1000
end
local function isPluginEnabled()
    return G_reader_settings:nilOrTrue(SETTING_KEY_PLUGIN_ENABLED)
end
-- ===========================================================================

-- ---- State kept so we can cleanly revert everything on demand -----------
local patched = false

local orig_beforePaint, orig_afterPaint
local orig_setSwipeAnimations, orig_setSwipeDirection
local orig_canDoSwipeAnimation
local orig_repaint
local orig_paging_gotoPage
local orig_rolling_gotoPage
local refresh_methods, update_dither
local hardware_animate

local function applyPatch()
    if patched then return end
    if _G.__sw_page_turn_anim_patched then
        logger.warn("sw-page-turn-animation.koplugin: patch already applied elsewhere " ..
            "(old patch file still installed?) -- refusing to patch twice")
        return
    end

    orig_beforePaint = Screen.beforePaint
    orig_afterPaint = Screen.afterPaint
    orig_setSwipeAnimations = Screen.setSwipeAnimations
    orig_setSwipeDirection = Screen.setSwipeDirection
    orig_canDoSwipeAnimation = Device.canDoSwipeAnimation
    orig_repaint = UIManager._repaint
    orig_paging_gotoPage = ReaderPaging._gotoPage
    orig_rolling_gotoPage = ReaderRolling._gotoPage

    refresh_methods = userpatch.getUpValue(orig_repaint, "refresh_methods")
    update_dither = userpatch.getUpValue(orig_repaint, "update_dither")
    hardware_animate = Device.canDoSwipeAnimation()

    -- 1) Framebuffer: saved_bb snapshot + real setSwipeAnimations/setSwipeDirection
    Screen.beforePaint = function(self)
        if not self.painting then
            self.painting = true
            if self.swipe_animations then
                if self.saved_bb then self.saved_bb:free() end
                self.saved_bb = self.bb:copy()
            end
        end
    end

    Screen.afterPaint = function(self)
        self.painting = false
    end

    Screen.setSwipeAnimations = function(self, enabled)
        self.swipe_animations = enabled
    end

    Screen.setSwipeDirection = function(self, direction)
        self.swipe_forward = direction
    end

    -- 2) Report the device can do the (software) swipe animation, even if
    --    this model has it hardcoded to false.
    Device.canDoSwipeAnimation = function() return true end

    -- 3) UIManager:_repaint -- inject the software swipe animation right
    --    before the queued refreshes are executed.
    UIManager._repaint = function(self)
        local dirty = false
        local dithered = false

        local start_idx = 1
        for i = #self._window_stack, 1, -1 do
            if self._window_stack[i].widget.covers_fullscreen then
                start_idx = i
                break
            end
        end

        for i = start_idx, #self._window_stack do
            local window = self._window_stack[i]
            local widget = window.widget
            if dirty or self._dirty[widget] then
                Screen:beforePaint()
                widget:paintTo(Screen.bb, window.x, window.y, self._dirty[widget])
                self._dirty[widget] = nil
                dirty = true
                if widget.dithered then
                    dithered = true
                end
            end
        end

        for _, refreshfunc in ipairs(self._refresh_func_stack) do
            local refreshtype, region, dither = refreshfunc()
            dither = update_dither(dither, dithered)
            if refreshtype then
                self:_refresh(refreshtype, region, dither)
            end
        end
        self._refresh_func_stack = {}

        if dirty and not self._refresh_stack[1] then
            logger.dbg("no refresh got enqueued. Will do a partial full screen refresh, which might be inefficient")
            self:_refresh("partial")
        end

        local software_animate = not hardware_animate

        if software_animate then
            Screen.swipe_animations = false
            local saved_bb = Screen.saved_bb
            Screen.saved_bb = nil
            if saved_bb then
                local new_bb = Screen.bb:copy()
                local steps = getSteps()
                local screen_w = Screen.bb:getWidth()
                local screen_h = Screen.bb:getHeight()
                local swipe_forward = Screen.swipe_forward
                local prev_dx = 0

                for i = 1, steps do
                    local progress = i / steps
                    local dx = math.floor(screen_w * progress)
                    local strip_w = dx - prev_dx

                    if swipe_forward then
                        -- Right-to-left: new page reveals from the right
                        Screen.bb:blitFrom(saved_bb, 0, 0, 0, 0, screen_w - dx, screen_h)
                        Screen.bb:blitFrom(new_bb, screen_w - dx, 0, screen_w - dx, 0, dx, screen_h)

                        if i < steps then
                            if strip_w > 0 then
                                Screen:refreshUI(screen_w - dx, 0, strip_w, screen_h)
                                self:yieldToEPDC(getDelayUs())
                            end
                        else
                            Screen:refreshUI(0, 0, screen_w, screen_h)
                        end
                    else
                        -- Left-to-right: new page reveals from the left
                        Screen.bb:blitFrom(new_bb, 0, 0, 0, 0, dx, screen_h)
                        Screen.bb:blitFrom(saved_bb, dx, 0, dx, 0, screen_w - dx, screen_h)

                        if i < steps then
                            if strip_w > 0 then
                                Screen:refreshUI(prev_dx, 0, strip_w, screen_h)
                                self:yieldToEPDC(getDelayUs())
                            end
                        else
                            Screen:refreshUI(0, 0, screen_w, screen_h)
                        end
                    end

                    if DEBUG then
                        logger.dbg("sw-page-turn-animation:", i, "/", steps, "dx=", dx, "strip_w=", strip_w)
                    end

                    prev_dx = dx
                end

                -- Drop the now-redundant "page turn" refresh queued earlier
                -- this repaint, but keep any "full" mode ghosting-clear refresh.
                local kept_refreshes = {}
                for _, refresh in ipairs(self._refresh_stack) do
                    if refresh.mode == "full" then
                        table.insert(kept_refreshes, refresh)
                    end
                end
                self._refresh_stack = kept_refreshes

                new_bb:free()
                saved_bb:free()
            end
        end

        for _, refresh in ipairs(self._refresh_stack) do
            refresh.dither = update_dither(refresh.dither, dithered)
            if not Screen.hw_dithering then
                refresh.dither = nil
            end
            dbg:v("triggering refresh", refresh)
            refresh_methods[refresh.mode](Screen,
                refresh.region.x, refresh.region.y,
                refresh.region.w, refresh.region.h,
                refresh.dither)
        end

        if dirty then
            Screen:afterPaint()
        end

        self._refresh_stack = {}
        self.refresh_counted = false
    end

    -- Fixed-layout documents (PDF, DjVu, comics...)
    ReaderPaging._gotoPage = function(self, number, orig_mode)
        if number == self.current_page or not number then
            self.view.footer:onUpdateFooter(self.view.footer_visible)
            return true
        end
        if number > self.number_of_pages then
            logger.warn("page number too high: " .. number .. "!")
            number = self.number_of_pages
        elseif number < 1 then
            logger.warn("page number too low: " .. number .. "!")
            number = 1
        end
        if self.current_page then
            self.ui:handleEvent(Event:new("PageChangeAnimation", number > self.current_page))
        end
        self.ui:handleEvent(Event:new("PageUpdate", number, orig_mode))
        return true
    end

    -- Reflowable documents (EPUB, FB2, TXT...) in paginated "page" view mode.
    -- Core never fires PageChangeAnimation there, so we wrap _gotoPage to
    -- fire the same event ReaderPaging fires, before the real page change.
    ReaderRolling._gotoPage = function(self, new_page, ...)
        if self.view.view_mode == "page" and new_page and self.current_page
            and new_page ~= self.current_page then
            self.ui:handleEvent(Event:new("PageChangeAnimation", new_page > self.current_page))
        end
        return orig_rolling_gotoPage(self, new_page, ...)
    end

    patched = true
    _G.__sw_page_turn_anim_patched = true
    logger.info("sw-page-turn-animation.koplugin: patch applied (steps =", getSteps(), ")")
end

local function removePatch()
    if not patched then return end

    Screen.beforePaint = orig_beforePaint
    Screen.afterPaint = orig_afterPaint
    Screen.setSwipeAnimations = orig_setSwipeAnimations
    Screen.setSwipeDirection = orig_setSwipeDirection
    Device.canDoSwipeAnimation = orig_canDoSwipeAnimation
    UIManager._repaint = orig_repaint
    ReaderPaging._gotoPage = orig_paging_gotoPage
    ReaderRolling._gotoPage = orig_rolling_gotoPage

    patched = false
    _G.__sw_page_turn_anim_patched = false
    logger.info("sw-page-turn-animation.koplugin: patch reverted")
end

local SWPageTurnAnimation = WidgetContainer:extend{
    name = "swpageturnanimation",
    fullname = _("Software page turn animation"),
    description = _([[Adds a software-based page-turn wipe animation for e-ink devices, even on models where the native hardware animation is disabled. Configurable step count and speed. Can be enabled or disabled live from its own submenu, or globally from the Plugin Manager.]]),
    is_doc_only = true,
}

function SWPageTurnAnimation:init()
    -- Register through the standard plugin menu hook (addToMainMenu below)
    -- instead of splicing directly into ui/elements/page_turns.sub_item_table.
    -- That direct-splice approach depended on require/load order (it could
    -- silently no-op or error if page_turns hadn't built its table yet, or
    -- if another patch/plugin touched the same table first) and only worked
    -- while inside a ReaderUI instance. registerToMainMenu is the mechanism
    -- every core menu entry and well-behaved plugin uses, so it's called
    -- reliably every time the menu is built, in FileManager and Reader alike.
    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end

    if isPluginEnabled() then
        local ok, err = pcall(applyPatch)
        if not ok then
            logger.warn("sw-page-turn-animation.koplugin: applyPatch() failed:", err)
        end
    end
end

-- Called by the menu framework (via registerToMainMenu above) whenever the
-- main menu is built. We hang our submenu off "more_tools" (Settings/Tools
-- -> More tools), which is the standard, stable home for plugin settings.
-- Unlike Settings -> Gestures & Actions -> Page turning, whose sub_item_table
-- we used to mutate directly, "more_tools" is guaranteed to exist by the time
-- any plugin's addToMainMenu runs, so this entry always shows up.
function SWPageTurnAnimation:addToMainMenu(menu_items)
    menu_items.swpageturnanimation = {
        text = _("Software page turn animation"),
        sorting_hint = "more_tools",
        sub_item_table = {
            {
                text = _("Plugin active"),
                checked_func = isPluginEnabled,
                callback = function()
                    if isPluginEnabled() then
                        G_reader_settings:saveSetting(SETTING_KEY_PLUGIN_ENABLED, false)
                        removePatch()
                    else
                        G_reader_settings:saveSetting(SETTING_KEY_PLUGIN_ENABLED, true)
                        applyPatch()
                    end
                end,
                separator = true,
            },
            {
                text = _("Enable animation"),
                enabled_func = isPluginEnabled,
                checked_func = function()
                    return G_reader_settings:isTrue("swipe_animations")
                end,
                callback = function()
                    G_reader_settings:flipNilOrFalse("swipe_animations")
                end,
            },
            {
                text = _("Speed preset"),
                enabled_func = isPluginEnabled,
                sub_item_table_func = function()
                    local items = {}
                    for _, preset in ipairs(SPEED_PRESETS) do
                        table.insert(items, {
                            text = preset.text,
                            checked_func = function()
                                return getSteps() == preset.steps
                                    and G_reader_settings:readSetting(SETTING_KEY_DELAY, DEFAULT_DELAY_MS) == preset.delay_ms
                            end,
                            radio = true,
                            callback = function()
                                G_reader_settings:saveSetting(SETTING_KEY_STEPS, preset.steps)
                                G_reader_settings:saveSetting(SETTING_KEY_DELAY, preset.delay_ms)
                            end,
                        })
                    end
                    return items
                end,
                separator = true,
            },
            {
                keep_menu_open = true,
                enabled_func = isPluginEnabled,
                text_func = function()
                    return T(_("Number of steps: %1"), getSteps())
                end,
                callback = function(touchmenu_instance)
                    local SpinWidget = require("ui/widget/spinwidget")
                    UIManager:show(SpinWidget:new{
                        title_text = _("Animation steps"),
                        info_text = _([[
How many frames the page-turn wipe animation is split into.
More steps = smoother animation but slower.
Fewer steps = faster but choppier.]]),
                        value = getSteps(),
                        value_min = 2,
                        value_max = 24,
                        value_step = 1,
                        default_value = DEFAULT_STEPS,
                        precision = "%d",
                        callback = function(spin)
                            G_reader_settings:saveSetting(SETTING_KEY_STEPS, spin.value)
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end,
                    })
                end,
            },
            {
                keep_menu_open = true,
                enabled_func = isPluginEnabled,
                text_func = function()
                    return T(_("Animation speed: %1 ms/step"), G_reader_settings:readSetting(SETTING_KEY_DELAY, DEFAULT_DELAY_MS))
                end,
                callback = function(touchmenu_instance)
                    local SpinWidget = require("ui/widget/spinwidget")
                    UIManager:show(SpinWidget:new{
                        title_text = _("Animation speed"),
                        info_text = _([[
How long (in milliseconds) each intermediate frame stays on screen
before moving to the next one.
Lower = faster animation. Higher = slower, more deliberate.
Going too low may cause the e-ink panel to not fully refresh each
strip before the next one is drawn.]]),
                        value = G_reader_settings:readSetting(SETTING_KEY_DELAY, DEFAULT_DELAY_MS),
                        value_min = 5,
                        value_max = 100,
                        value_step = 5,
                        default_value = DEFAULT_DELAY_MS,
                        precision = "%d",
                        unit = "ms",
                        callback = function(spin)
                            G_reader_settings:saveSetting(SETTING_KEY_DELAY, spin.value)
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end,
                    })
                end,
            },
        },
    }
end

return SWPageTurnAnimation
