
--[[
                                                  
     Licensed under GNU General Public License v2 
      * (c) 2013, Luke Bonham                     
      * (c) 2013, Rman                            
                                                  
--]]

local newtimer     = require("lain.helpers").newtimer
local read_pipe    = require("lain.helpers").read_pipe

local awful        = require("awful")
local beautiful    = require("beautiful")
local naughty      = require("naughty")

-- local math         = { modf   = math.modf }
local mouse        = mouse
local string       = { format = string.format,
                       match  = string.match,
                       rep    = string.rep }
local tonumber     = tonumber

local setmetatable = setmetatable


-- Pulse volume bar
-- lain.widgets.pulsebar
local pulsebar = {
    default_sink = "alsa_output.pci-0000_00_1b.0.analog-stereo",
    step         = "2%",

    colors = {
        background = beautiful.bg_normal,
        mute       = "#EB8F8F",
        unmute     = "#A4CE8A"
    },

    terminal = terminal or "xterm",
    mixer    = "pavucontrol",

    notifications = {
        font      = beautiful.font:sub(beautiful.font:find(""), beautiful.font:find(" ")),
        font_size = "11",
        color     = beautiful.fg_normal,
        bar_size  = 18,
        screen    = 1
    },

    _current_level = 0,
    _muted         = false
}

function pulsebar.notify()
    pulsebar.update()

    local preset = {
        title   = "",
        text    = "",
        timeout = 5,
        screen  = pulsebar.notifications.screen,
        font    = pulsebar.notifications.font .. " " ..
                  pulsebar.notifications.font_size,
        fg      = pulsebar.notifications.color
    }

    if pulsebar._muted
    then
        preset.title = pulsebar.channel .. " - Muted"
    else
        preset.title = pulsebar.channel .. " - " .. pulsebar._current_level .. "%"
    end

    int = math.modf((pulsebar._current_level / 100) * pulsebar.notifications.bar_size)
    preset.text = "["
                .. string.rep("|", int)
                .. string.rep(" ", pulsebar.notifications.bar_size - int)
                .. "]"

    if pulsebar.followmouse then
        preset.screen = mouse.screen
    end

    if pulsebar._notify ~= nil then
        pulsebar._notify = naughty.notify ({
            replaces_id = pulsebar._notify.id,
            preset      = preset,
        })
    else
        pulsebar._notify = naughty.notify ({
            preset = preset,
        })
    end
end

local function worker(args)
    local args       = args or {}
    local timeout    = args.timeout or 5
    local settings   = args.settings or function() end
    local width      = args.width or 63
    local height     = args.heigth or 1
    local ticks      = args.ticks or false
    local ticks_size = args.ticks_size or 7
    local vertical   = args.vertical or false

    pulsebar.cmd           = args.cmd or "pacmd"
    pulsebar.ctrl          = args.ctrl or "pactl"
    pulsebar.sink          = args.sink or pulsebar.default_sink
    pulsebar.level         = 0
    pulsebar.status        = "on"
    pulsebar.step          = args.step or pulsebar.step
    pulsebar.colors        = args.colors or pulsebar.colors
    pulsebar.notifications = args.notifications or pulsebar.notifications
    pulsebar.followmouse   = args.followmouse or false

    pulsebar.bar = awful.widget.progressbar()

    pulsebar.bar:set_background_color(pulsebar.colors.background)
    pulsebar.bar:set_color(pulsebar.colors.unmute)
    pulsebar.tooltip = awful.tooltip({ objects = { pulsebar.bar } })
    pulsebar.bar:set_width(width)
    pulsebar.bar:set_height(height)
    pulsebar.bar:set_ticks(ticks)
    pulsebar.bar:set_ticks_size(ticks_size)
    pulsebar.bar:set_vertical(vertical)

    function pulsebar.get_sink()
        local f = io.popen(pulsebar.cmd .. " dump | /bin/grep -v -e '^$' | /bin/grep -v load")
        local sink = nil

        while true  do
            line = f:read("*l")
            if line == nil then break end
            sink = string.match(line, "set%-default%-sink ([^\n]+)")
            if sink ~= nil then
                return sink
            end
        end
        f:close()
        return nil    
    end

    function pulsebar.update()
        -- Get default sink
        default_sink = pulsebar.get_sink()
        
        local f = io.popen(pulsebar.cmd .. " dump | /bin/grep -v -e '^$' | /bin/grep -v load")
        local self = {}
        volume_now = {}
              
        -- if the cmd can't be found
        if f == nil then
           return false
        end
        
        while true  do
           line = f:read("*l")
           if line == nil then break end
           
           sink, value = string.match(line, "set%-sink%-volume ([^%s]+) (0x%x+)")
           if sink == default_sink and value ~= 0  then
              volume_now.level = round((tonumber(value) / 0x10000) * 100)
           end
 
 
           sink, value = string.match(line, "set%-sink%-mute ([^%s]+) (%a+)")
           if sink == default_sink and value == "no" then
              volume_now.status = "on"
           elseif sink == default_sink and value == "yes" then
              volume_now.status = "off"
           end
        end
 
        f:close()
 
        if volume_now.level == nil
        then
           volume_now.level  = "0"
           volume_now.status = "off"
        end
        if volume_now.status == ""
        then
           volume_now.status = "off"
        end

        pulsebar._current_level = tonumber(volume_now.level)
        pulsebar.bar:set_value(pulsebar._current_level / 100)
        if not volume_now.status and tonumber(volume_now.level) == 0 or volume_now.status == "off"
        then
            pulsebar._muted = true
            pulsebar.tooltip:set_text (" [Muted] ")
            pulsebar.bar:set_color(pulsebar.colors.mute)
        else
            pulsebar._muted = false
            -- pulsebar.tooltip:set_text(string.format(" %s:%s ", pulsebar.channel, volu))
            pulsebar.tooltip:set_text(string.format(" %s ", volume_now.level))
            pulsebar.bar:set_color(pulsebar.colors.unmute)
        end

        settings()
    end

    pulsebar.bar:buttons (awful.util.table.join (
          awful.button ({}, 1, function()
            awful.util.spawn(pulsebar.mixer)
          end),
          awful.button ({}, 3, function()
            awful.util.spawn(string.format("%s set-sink-mute %s toggle", pulsebar.ctrl, pulsebar.sink))
            pulsebar.update()
          end),
          awful.button ({}, 4, function()
            awful.util.spawn(string.format("%s set-sink-volume %s +%s", pulsebar.ctrl, pulsebar.sink, pulsebar.step))
            pulsebar.update()
          end),
          awful.button ({}, 5, function()
            awful.util.spawn(string.format("%s set-sink-volume %s -%s", pulsebar.ctrl, pulsebar.sink, pulsebar.step))
            pulsebar.update()
          end)
    ))

    function round(num,idp)
        local mult = 10^(idp or 0)
        return math.floor(num*mult+0.5)/mult
    end

    timer_id = string.format("pulsebar-%s-%s", pulsebar.cmd, pulsebar.channel)

    newtimer(timer_id, timeout, pulsebar.update)

    return pulsebar
end

return setmetatable(pulsebar, { __call = function(_, ...) return worker(...) end })
