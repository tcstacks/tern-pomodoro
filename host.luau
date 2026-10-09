--!strict
local Timer = require("./timer")
local Input = require("./duration-input")
local ui = tern.ui
local DURATION_FIELD = "main.timer.clock.edit.duration"

type State = {
    clock: Timer.State,
    cx: BlockCx,
    timer: TimerHandle?,
    wave: boolean,
    waveTimer: TimerHandle?,
    input: Input.State,
    editing: boolean,
}

-- A pane ID can be reused by Restart. State identity distinguishes its runs.
-- Paused blocks have no producer; weak values let their state go on close.
local running: { [number]: State } = setmetatable({}, { __mode = "v" }) :: any

local function live(state: State): boolean
    if running[state.cx.pane] ~= state then
        return false
    end
    for _, pane in tern.pane.list() do
        if pane.pane == state.cx.pane then
            return true
        end
    end
    running[state.cx.pane] = nil
    return false
end

local function settle(state: State)
    if Timer.settle(state.clock, os.time()) then
        local focus = state.clock.phase == "focus"
        state.wave = true
        if state.waveTimer then
            state.waveTimer:cancel()
        end
        state.waveTimer = tern.timer(1300, function()
            state.waveTimer = nil
            if live(state) then
                state.wave = false
                state.cx:render()
            end
        end)
        state.cx:toast("success", if focus then "Focus complete" else "Break complete",
            if focus then "Well done. Take a break for yourself." else "Ready for one more good session?")
    end
end

local function arm(state: State)
    if state.timer then
        state.timer:cancel()
        state.timer = nil
    end
    if state.clock.deadline == nil then
        return
    end
    state.timer = tern.timer(1000, function()
        state.timer = nil
        if not live(state) then
            return
        end
        settle(state)
        state.cx:render()
        arm(state)
    end)
end

local function apply_duration(state: State)
    local input = state.input
    if not state.editing then
        return
    end
    local minutes = tonumber(input.text)
    if not minutes or not Timer.set_duration(state.clock, minutes) then
        input.error = "Use whole minutes from 1 to 180"
        return
    end
    state.editing = false
end

local function act(state: State, action: string)
    settle(state)
    if action == "edit-duration" then
        if state.clock.deadline then
            Timer.toggle(state.clock, os.time())
        end
        arm(state)
        state.input = Input.new(Timer.duration(state.clock) / 60)
        state.editing = true
        -- Remove readonly before focusing the persistent native field.
        state.cx:render()
        state.cx:frame({ { "focus", DURATION_FIELD } })
        return
    elseif action == "save-duration" then
        apply_duration(state)
        return
    elseif action == "cancel-duration" then
        state.editing = false
        return
    end
    state.editing = false
    if action == "start-pause" then
        Timer.toggle(state.clock, os.time())
    elseif action == "reset" then
        Timer.select(state.clock, state.clock.phase)
    elseif action == "skip" then
        Timer.next(state.clock)
    elseif action == "focus" or action == "break" then
        if state.clock.phase ~= action then
            Timer.select(state.clock, action)
        end
    end
    arm(state)
end

local function button(text: string, action: string, class: string): Node
    return ui.el("button", {
        key = action,
        text = text,
        class = class,
        actions = { click = action },
        aria = text,
    })
end

local function formatted(seconds: number): string
    return string.format("%02d:%02d", seconds // 60, seconds % 60)
end

local block: BlockDef<State> = {
    features = { "edit" },
    init = function(cx, _args, saved)
        local old = running[cx.pane]
        if old and old.timer then
            old.timer:cancel()
        end
        if old and old.waveTimer then
            old.waveTimer:cancel()
        end
        local clock = Timer.restore(saved)
        local state: State = {
            clock = clock, cx = cx, wave = false,
            input = Input.new(Timer.duration(clock) / 60), editing = false,
        }
        running[cx.pane] = state
        settle(state)
        arm(state)
        return state
    end,
    view = function(state, cx)
        local clock = state.clock
        local seconds = Timer.remaining(clock, os.time())
        local active = clock.deadline ~= nil
        local complete = not active and clock.remaining == 0
        local paused = not active and not complete and clock.remaining < Timer.duration(clock)
        local focus = clock.phase == "focus"
        local label = if active then "Pause" elseif complete then (if focus then "Start break" else "Start focus") elseif paused then "Resume" else "Start"
        local status = if complete then (if focus then "Focus complete" else "Break complete") elseif paused then "Paused" else ""
        local input = state.input
        local idleAttrs = { ["aria-hidden"] = if state.editing then "true" else "false" }
        local editAttrs = { ["aria-hidden"] = if state.editing then "false" else "true" }
        local progress = ui.node("progress", {
            key = "progress",
            value = 1 - seconds / Timer.duration(clock),
            tone = if focus then "accent" else "success",
        })
        local main = ui.col({
            ui.el("div", {
                key = "timer",
                class = "pomo" .. (if cx.cols < 42 then " pomo-compact" else "") .. (if state.editing then " pomo-editing" else ""),
            }, {
                ui.el("div", { class = "pomo-modes" }, {
                    button("Focus", "focus", "pomo-mode" .. (if focus then " selected" else "")),
                    button("Break", "break", "pomo-mode" .. (if not focus then " selected" else "")),
                }),
                ui.el("div", { key = "clock", class = "pomo-clock" }, {
                    ui.el("div", {
                        key = "countdown", class = "pomo-time pomo-layer pomo-idle",
                        text = formatted(seconds), actions = { click = "edit-duration" },
                        aria = formatted(seconds) .. " remaining. Click to change duration.",
                        attrs = idleAttrs,
                    }),
                    ui.el("div", { key = "edit", class = "pomo-layer pomo-edit", attrs = editAttrs }, {
                        ui.node("input", {
                            key = "duration", text = input.text, cursor = input.cursor, anchor = input.anchor,
                            readonly = not state.editing,
                            role = "pomodoro.duration", aria = "Duration in minutes, 1 to 180",
                        }),
                    }),
                }),
                ui.el("div", { key = "status", class = "pomo-status" }, {
                    ui.el("div", { class = "pomo-layer pomo-idle", text = status, attrs = idleAttrs }),
                    ui.el("div", {
                        class = "pomo-layer pomo-edit" .. (if input.error then " pomo-error" else ""),
                        attrs = editAttrs,
                        text = input.error or "Minutes · Enter to save · Esc to cancel",
                    }),
                }),
                ui.el("div", { class = "pomo-progress" }, { progress }),
                ui.el("div", { key = "controls", class = "pomo-controls" }, {
                    ui.el("div", { key = "playback", class = "pomo-control-row pomo-layer pomo-idle", attrs = idleAttrs }, {
                        button("Reset", "reset", "pomo-secondary"),
                        button(label, "start-pause", "pomo-primary"),
                        button("Skip", "skip", "pomo-secondary"),
                    }),
                    ui.el("div", { key = "edit", class = "pomo-control-row pomo-layer pomo-edit", attrs = editAttrs }, {
                        button("Cancel", "cancel-duration", "pomo-secondary"),
                        button("Save", "save-duration", "pomo-primary"),
                    }),
                }),
                ui.el("div", {
                    class = "pomo-footer",
                    hidden = clock.completed == 0,
                    text = tostring(clock.completed) .. (if clock.completed == 1 then " session" else " sessions"),
                }),
            }),
        })
        -- Region roles style the entire pane, not only the timer's content box.
        main.p = { role = if state.wave then "pomodoro.expiry" else "pomodoro.timer" }
        return { main = main }
    end,
    title = function(state)
        return "Pomodoro · " .. formatted(Timer.remaining(state.clock, os.time())) .. (if state.clock.phase == "focus" then " · Focus" else " · Break")
    end,
    key = function(state, key, _cx)
        if state.editing then
            if key.name == "enter" then
                apply_duration(state)
            elseif key.name == "escape" then
                state.editing = false
            else
                return Input.key(state.input, key)
            end
            return true
        end
        if key.ctrl or key.alt or key.meta then
            return false
        end
        if key.name == "space" or key.name == "enter" then
            act(state, "start-pause")
        elseif key.name == "r" then
            act(state, "reset")
        elseif key.name == "n" then
            act(state, "skip")
        else
            return false
        end
        return true
    end,
    event = function(state, ev, _cx)
        if ev.ev == "action" then
            act(state, ev.act)
        elseif state.editing and ev.id == DURATION_FIELD then
            if ev.ev == "focus" then
                state.cx:frame({ { "focus", ev.id } })
            elseif ev.ev == "edit" then
                -- A stale native edit must not splice a newer draft.
                if ev.len == #state.input.text then
                    Input.replace(state.input, ev.from, ev.to, ev.text)
                end
            end
        end
    end,
    save = function(state)
        return Timer.save(state.clock)
    end,
}

tern.block.define("timer", block)
