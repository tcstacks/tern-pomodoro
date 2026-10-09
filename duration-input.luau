--!strict
local Input = {}

export type State = {
    text: string,
    cursor: number,
    anchor: number?,
    error: string?,
}

function Input.new(minutes: number): State
    local text = tostring(minutes)
    return { text = text, cursor = #text, anchor = 0 }
end

-- Digits only: byte and native UTF-16 offsets are identical in this field.
function Input.replace(state: State, first: number, last: number, text: string)
    local nextText = state.text:sub(1, first) .. text .. state.text:sub(last + 1)
    if not nextText:match("^%d*$") or #nextText > 3 then
        state.error = "Use whole minutes from 1 to 180"
        return
    end
    state.text = nextText
    state.cursor = first + #text
    state.anchor = nil
    state.error = nil
end

-- Native editing handles selection when enabled. Keep ordinary typing and
-- selection usable when Settings > Native composer editing is disabled.
function Input.key(state: State, key: Key): boolean
    local anchor = state.anchor or state.cursor
    local first, last = math.min(anchor, state.cursor), math.max(anchor, state.cursor)
    if (key.ctrl or key.meta) and key.name == "a" then
        state.anchor, state.cursor = 0, #state.text
    elseif key.alt or key.ctrl or key.meta then
        return false
    elseif key.name == "left" or key.name == "right" or key.name == "home" or key.name == "end" then
        local cursor = state.cursor
        if key.name == "home" then
            cursor = 0
        elseif key.name == "end" then
            cursor = #state.text
        elseif key.name == "left" then
            cursor = if not key.shift and first ~= last then first else math.max(0, cursor - 1)
        else
            cursor = if not key.shift and first ~= last then last else math.min(#state.text, cursor + 1)
        end
        state.anchor = if key.shift then anchor else nil
        state.cursor = cursor
    elseif key.name == "backspace" or key.name == "delete" then
        if first == last then
            if key.name == "backspace" then
                first = math.max(0, first - 1)
            else
                last = math.min(#state.text, last + 1)
            end
        end
        Input.replace(state, first, last, "")
    elseif key.text and key.text ~= "" then
        Input.replace(state, first, last, key.text)
    else
        return false
    end
    return true
end

return Input
