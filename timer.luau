--!strict
local Timer = {}

export type State = {
    phase: string,
    remaining: number,
    deadline: number?,
    completed: number,
    focusDuration: number,
    breakDuration: number,
}

function Timer.duration(state: State): number
    return if state.phase == "break" then state.breakDuration else state.focusDuration
end

function Timer.restore(saved: any): State
    if saved == nil then
        return { phase = "focus", remaining = 25 * 60, completed = 0, focusDuration = 25 * 60, breakDuration = 5 * 60 }
    end
    return {
        phase = saved.phase,
        remaining = saved.remaining,
        deadline = saved.deadline,
        completed = saved.completed,
        -- Existing saved blocks predate adjustable durations.
        focusDuration = saved.focusDuration or 25 * 60,
        breakDuration = saved.breakDuration or 5 * 60,
    }
end

function Timer.remaining(state: State, now: number): number
    local deadline = state.deadline
    return if deadline then math.clamp(math.ceil(deadline - now), 0, Timer.duration(state)) else state.remaining
end

-- Settle the deadline before processing input, including input racing the last tick.
-- A completed interval clears its deadline, so it can only be counted once.
function Timer.settle(state: State, now: number): boolean
    if state.deadline == nil or now < state.deadline then
        return false
    end
    state.deadline = nil
    state.remaining = 0
    if state.phase == "focus" then
        state.completed += 1
    end
    return true
end

function Timer.select(state: State, phase: string)
    state.phase = phase
    state.remaining = Timer.duration(state)
    state.deadline = nil
end

-- Applying a duration prepares a fresh interval; it never starts or awards one.
function Timer.set_duration(state: State, minutes: number): boolean
    if minutes ~= minutes or minutes < 1 or minutes > 180 or minutes % 1 ~= 0 then
        return false
    end
    if state.phase == "break" then
        state.breakDuration = minutes * 60
    else
        state.focusDuration = minutes * 60
    end
    Timer.select(state, state.phase)
    return true
end

function Timer.next(state: State)
    Timer.select(state, if state.phase == "focus" then "break" else "focus")
end

function Timer.toggle(state: State, now: number)
    Timer.settle(state, now)
    if state.deadline then
        state.remaining = Timer.remaining(state, now)
        state.deadline = nil
    else
        if state.remaining == 0 then
            Timer.next(state)
        end
        state.deadline = now + state.remaining
    end
end

function Timer.save(state: State): State
    return {
        phase = state.phase,
        remaining = state.remaining,
        deadline = state.deadline,
        completed = state.completed,
        focusDuration = state.focusDuration,
        breakDuration = state.breakDuration,
    }
end

return Timer
