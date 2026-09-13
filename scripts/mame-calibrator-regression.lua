-- MAME 0.289 regression harness for the MC-10 timing calibrator.
--
-- The cassette image is mounted by MAME before this script starts.  The
-- script controls only the emulated machine after startup: it enters CLOADM,
-- starts the cassette, waits for the complete image, enters EXEC, verifies
-- the manual band workflow, cycles alpha and the two advanced diagnostic
-- modes, exercises sweep-box height and vertical-position controls including
-- both off-screen directions, and analyzes the rendered screen pixels.
--
-- Run with:
--   mame.exe mc10 -ramsize 20K -cass build/timing-calibrator.c10 \
--     -autoboot_delay 2 \
--     -autoboot_script scripts/mame-calibrator-regression.lua \
--     -snapshot_directory build/mame-snapshots -seconds_to_run 120

local machine = manager.machine
local cassette = machine.cassettes[":cassette"]
local screen = machine.screens[":screen"]
local keyboard = machine.natkeyboard
local cpu = machine.devices[":maincpu"]
local program_space = cpu and cpu.spaces["program"]

local CAL_MODE = 0x00F1
local CAL_SWEEP_ACTIVE = 0x00F7
local CAL_PERIOD_H = 0x00E0
local CAL_PERIOD_L = 0x00E1
local CAL_PHASE_H = 0x00E2
local CAL_PHASE_L = 0x00E3
local CAL_EVENTS_H = 0x00E4
local CAL_EVENTS_L = 0x00E5
local CAL_RECT_Y = 0x00F3
local CAL_RECT_X = 0x00F2
local CAL_SWEEP_Y = 0x00FA
local CAL_SWEEP_HEIGHT_STATE = 0x00FB
local CAL_SWEEP_OFFSET = 0x00FC

local EXEC_MIN_FRAME = 2400
local EXEC_TIMEOUT_FRAME = 7200
local TAPE_SETTLE_FRAMES = 30
local ALPHA_FRAME = 4800
local KEY_TIMEOUT_FRAMES = 240
local SAMPLE_GAP_FRAMES = 120
local ACTIVE_WIDTH = 256
local ACTIVE_HEIGHT = 192
local ACTIVE_PIXELS = ACTIVE_WIDTH * ACTIVE_HEIGHT
local ACTIVE_LEFT = 58
local ACTIVE_TOP = 25

local PHASE_WAIT_MANUAL = 1
local PHASE_MANUAL_GAP = 2
local PHASE_WAIT_ALPHA = 3
local PHASE_WAIT_DRIFT = 4
local PHASE_DRIFT_GAP = 5
local PHASE_WAIT_SWEEP = 6
local PHASE_SWEEP_GAP = 7
local PHASE_WAIT_PAUSE = 8
local PHASE_PAUSED_GAP = 9
local PHASE_WAIT_RESIZE_DOWN = 10
local PHASE_WAIT_RESIZE_UP = 11
local PHASE_WAIT_MOVE_UP = 12
local PHASE_WAIT_MOVE_DOWN = 13
local PHASE_WAIT_OFFSCREEN_BOTTOM_START = 14
local PHASE_WAIT_OFFSCREEN_BOTTOM = 15
local PHASE_WAIT_OFFSCREEN_TOP_START = 16
local PHASE_WAIT_OFFSCREEN_TOP = 17
local PHASE_WAIT_RESUME = 18
local PHASE_WAIT_RETURN_MANUAL = 19
local PHASE_DONE = 20
local PHASE_WAIT_MANUAL_WRAP_TOP = 21
local PHASE_WAIT_MANUAL_WRAP_BOTTOM = 22
local PHASE_WAIT_MANUAL_WRAP_REAPPEAR = 23

assert(cassette, "MC-10 cassette device not found")
assert(screen, "MC-10 screen device not found")
assert(keyboard and keyboard.can_post, "MC-10 natural keyboard input is unavailable")
assert(program_space, "MC-10 CPU program address space not found")

keyboard.in_use = true
keyboard:post_coded("CLOADM{ENTER}")
print("MC-10 keyboard: CLOADM{ENTER}")

local frame = 0
local started = false
local exec_sent = false
local phase = PHASE_WAIT_MANUAL
local deadline = ALPHA_FRAME + KEY_TIMEOUT_FRAMES
local manual_first = nil
local drift_first = nil
local sweep_first = nil
local paused_first = nil
local paused_height = nil
local paused_offset = nil
local paused_sweep_y = nil
local offscreen_target = nil
local manual_wrap_expected = nil
local failed = false
local tape_end_frame = nil

local function fail(message)
    if failed then
        return
    end
    failed = true
    phase = PHASE_DONE
    print("MC-10 calibrator regression: FAIL: " .. message)
    machine:exit()
    error("MC-10 calibrator regression: " .. message)
end

local function read_byte(address)
    return program_space:read_u8(address)
end

local function read_word(address)
    return read_byte(address) * 0x100 + read_byte(address + 1)
end

local function signed_byte(value)
    if value >= 0x80 then
        return value - 0x100
    end
    return value
end

local function offset_byte(value)
    if value < 0 then
        return value + 0x100
    end
    return value
end

local function format_bbox(box)
    if not box then
        return "none"
    end
    return string.format("%d,%d-%d,%d", box.left, box.top, box.right, box.bottom)
end

local function rgb_from_pixel(value)
    -- screen:pixel() returns either a palette index or a packed RGB value.
    if value <= 0xFF and screen.palette then
        value = screen.palette:pen_color(value)
    end
    local red = math.floor(value / 0x10000) % 0x100
    local green = math.floor(value / 0x100) % 0x100
    local blue = value % 0x100
    return red, green, blue
end

local function color_class(value)
    local red, green, blue = rgb_from_pixel(value)
    if green >= red + 20 and green >= blue + 20 then
        return "green"
    end
    if red >= green + 40 and red >= blue + 40 then
        return "red"
    end
    if blue >= red + 30 and blue >= green + 30 then
        return "blue"
    end
    return "other"
end

local function analyze_pixels()
    local pixels, width, height = screen:pixels()
    assert(type(pixels) == "string", "screen:pixels() did not return a pixel buffer")
    assert(width and height and width > 0 and height > 0, "screen dimensions are invalid")

    local counts = { blue = 0, green = 0, red = 0, other = 0 }
    local boxes = {
        blue = nil,
        green = nil,
        red = nil,
    }

    for y = 0, height - 1 do
        for x = 0, width - 1 do
            local kind = color_class(screen:pixel(x, y))
            counts[kind] = counts[kind] + 1
            if boxes[kind] then
                local box = boxes[kind]
                if x < box.left then box.left = x end
                if y < box.top then box.top = y end
                if x + 1 > box.right then box.right = x + 1 end
                if y + 1 > box.bottom then box.bottom = y + 1 end
            elseif kind ~= "other" then
                boxes[kind] = { left = x, top = y, right = x + 1, bottom = y + 1 }
            end
        end
    end

    return {
        pixels = pixels,
        width = width,
        height = height,
        total = width * height,
        counts = counts,
        boxes = boxes,
    }
end

local function changed_pixels(first, second)
    if first.width ~= second.width or first.height ~= second.height then
        return first.total
    end

    -- MAME returns a 32-bit value for each visible pixel.  Comparing four
    -- bytes per pixel avoids depending on host endianness or pixel format.
    local changed = 0
    local length = math.min(#first.pixels, #second.pixels)
    for offset = 1, length, 4 do
        if string.byte(first.pixels, offset) ~= string.byte(second.pixels, offset)
            or string.byte(first.pixels, offset + 1) ~= string.byte(second.pixels, offset + 1)
            or string.byte(first.pixels, offset + 2) ~= string.byte(second.pixels, offset + 2)
            or string.byte(first.pixels, offset + 3) ~= string.byte(second.pixels, offset + 3) then
            changed = changed + 1
        end
    end
    return changed
end

local function print_metrics(label, metrics, delta)
    local suffix = delta and string.format(" changed=%d", delta) or ""
    print(string.format(
        "MC-10 pixels: %s size=%dx%d blue=%d green=%d red=%d other=%d green-box=%s red-box=%s%s",
        label,
        metrics.width,
        metrics.height,
        metrics.counts.blue,
        metrics.counts.green,
        metrics.counts.red,
        metrics.counts.other,
        format_bbox(metrics.boxes.green),
        format_bbox(metrics.boxes.red),
        suffix))
end

local function save_snapshot(name)
    local error_message = screen:snapshot(name .. ".png")
    if error_message then
        fail(string.format("snapshot %s failed: %s", name, tostring(error_message)))
    end
end

local function require_mode(expected, label)
    local actual = read_byte(CAL_MODE)
    if actual ~= expected then
        fail(string.format("%s expected CAL_MODE=%d, got %d", label, expected, actual))
    end
end

local function alpha_ready(metrics)
    local green = metrics.counts.green
    return green >= ACTIVE_PIXELS * 0.90
        and metrics.counts.blue == 0
        and metrics.counts.red == 0
end

local function sample_alpha(label)
    if read_byte(CAL_MODE) ~= 1 then
        return nil
    end
    save_snapshot("mame-calibrator-" .. label)
    local metrics = analyze_pixels()
    if not alpha_ready(metrics) then
        return nil
    end
    print_metrics(label, metrics)
    return metrics
end

local function count_region(metrics, expected_color, left, top, right, bottom)
    local count = 0
    for y = math.max(0, top), math.min(metrics.height, bottom) - 1 do
        for x = math.max(0, left), math.min(metrics.width, right) - 1 do
            if color_class(screen:pixel(x, y)) == expected_color then
                count = count + 1
            end
        end
    end
    return count
end

local function cg3_ready(metrics, expected_color)
    return metrics.counts.blue >= ACTIVE_PIXELS * 0.90
        and metrics.counts[expected_color] >= 256
end

local function sample_cg3(label, expected_color)
    save_snapshot("mame-calibrator-" .. label)
    local metrics = analyze_pixels()
    if not cg3_ready(metrics, expected_color) then
        return nil
    end
    print_metrics(label, metrics)
    return metrics
end

local function visible_red_bytes()
    local count = 0
    for address = 0x4000, 0x4BFF do
        if address < 0x4206 or address > 0x4208 then
            if read_byte(address) == 0xFF then
                count = count + 1
            end
        end
    end
    return count
end

local function sample_cg3_background(label)
    save_snapshot("mame-calibrator-" .. label)
    local metrics = analyze_pixels()
    local red_bytes = visible_red_bytes()
    if metrics.counts.blue < ACTIVE_PIXELS * 0.90 or red_bytes ~= 0 then
        return nil
    end
    print_metrics(label, metrics)
    print(string.format(
        "MC-10 pixels: %s red-video-bytes=%d",
        label,
        red_bytes))
    return metrics
end

local function sample_manual(label)
    if read_byte(CAL_MODE) ~= 0 then
        return nil
    end
    save_snapshot("mame-calibrator-" .. label)
    local metrics = analyze_pixels()
    local band = count_region(
        metrics,
        "green",
        ACTIVE_LEFT,
        ACTIVE_TOP,
        ACTIVE_LEFT + ACTIVE_WIDTH,
        ACTIVE_TOP + ACTIVE_HEIGHT)
    if metrics.counts.blue < ACTIVE_PIXELS * 0.90 or band < 512 then
        return nil
    end
    print_metrics(label, metrics)
    print(string.format(
        "MC-10 pixels: manual band y=%02X green-active=%d",
        read_byte(CAL_RECT_Y),
        band))
    return metrics
end

local function manual_band_memory_ready()
    local y = read_byte(CAL_RECT_Y)
    if y >= 0x60 then
        return false
    end
    local address = 0x4000 + y * 0x20
    for row = 0, 3 do
        for column = 0, 0x1F do
            if read_byte(address + row * 0x20 + column) ~= 0 then
                return false
            end
        end
    end
    return true
end

local function post_key(code, description, next_phase, next_deadline)
    keyboard:post_coded(code)
    phase = next_phase
    deadline = next_deadline or (frame + KEY_TIMEOUT_FRAMES)
    print(string.format("MC-10 keyboard: %s at frame %d", description, frame))
end

local function trace_state(label)
    local pc_entry = cpu.state["PC"] or cpu.state["CURPC"] or cpu.state["rPC"]
    local pc = pc_entry and pc_entry.value or -1
    print(string.format(
        "MC-10 trace: %s pc=%04X mode=%02X active=%02X rect=%02X/%02X sweep-y=%02X height=%02X offset=%02X red4138=%02X period=%04X phase=%04X events=%04X tape=%.2f/%.2f playing=%s posting=%s empty=%s",
        label,
        pc,
        read_byte(CAL_MODE),
        read_byte(CAL_SWEEP_ACTIVE),
        read_byte(CAL_RECT_X),
        read_byte(CAL_RECT_Y),
        read_byte(CAL_SWEEP_Y),
        read_byte(CAL_SWEEP_HEIGHT_STATE),
        read_byte(CAL_SWEEP_OFFSET),
        read_byte(0x4138),
        read_word(CAL_PERIOD_H),
        read_word(CAL_PHASE_H),
        read_word(CAL_EVENTS_H),
        cassette.position,
        cassette.length,
        tostring(cassette.is_playing),
        tostring(keyboard.is_posting),
        tostring(keyboard.empty)))
end

frame_subscription = emu.add_machine_frame_notifier(function()
    frame = frame + 1

    if not started and frame >= 240 then
        cassette:play()
        started = true
        print(string.format("MC-10 cassette: PLAY at frame %d", frame))
    end

    local tape_at_end = cassette.length > 0 and cassette.position >= cassette.length - 0.25
    if started and not exec_sent and tape_at_end and not tape_end_frame then
        tape_end_frame = frame
        print(string.format("MC-10 cassette: end detected at frame %d", frame))
    end
    local end_settled = tape_end_frame and frame >= tape_end_frame + TAPE_SETTLE_FRAMES
    if started and not exec_sent and frame >= EXEC_MIN_FRAME
        and (end_settled or frame >= EXEC_TIMEOUT_FRAME) then
        trace_state("before-exec")
        cassette:stop()
        keyboard:post_coded("EXEC{ENTER}")
        exec_sent = true
        deadline = ALPHA_FRAME + KEY_TIMEOUT_FRAMES
        print(string.format("MC-10 keyboard: EXEC{ENTER} at frame %d", frame))
    end

    if not exec_sent or phase == PHASE_DONE then
        return
    end

    if phase == PHASE_WAIT_MANUAL then
        if frame >= ALPHA_FRAME then
            manual_first = sample_manual("manual-first")
            if manual_first then
                post_key("S", "S move manual band", PHASE_MANUAL_GAP)
            elseif manual_band_memory_ready() then
                save_snapshot("mame-calibrator-manual-first-memory")
                print(string.format(
                    "MC-10 state: manual band screen RAM pass y=%02X",
                    read_byte(CAL_RECT_Y)))
                manual_first = analyze_pixels()
                post_key("S", "S move manual band", PHASE_MANUAL_GAP)
            elseif frame > deadline then
                local metrics = analyze_pixels()
                print_metrics("manual-timeout", metrics)
                trace_state("manual-timeout")
                fail("initial manual band render was not visible")
            end
        end
    elseif phase == PHASE_MANUAL_GAP then
        if frame >= deadline then
            local manual_second = sample_manual("manual-second")
            if not manual_second and not manual_band_memory_ready() then
                fail("manual band render disappeared before the second sample")
            end
            local delta = manual_second and changed_pixels(manual_first, manual_second) or 0
            if read_byte(CAL_RECT_Y) == 0x30 then
                fail(string.format(
                    "manual band did not move after S: changed=%d y=%02X",
                    delta,
                    read_byte(CAL_RECT_Y)))
            end
            print(string.format(
                "MC-10 pixels: manual band motion pass changed=%d y=%02X%s",
                delta,
                read_byte(CAL_RECT_Y),
                manual_second and "" or " screen-RAM-verified"))
            manual_wrap_expected = (read_byte(CAL_RECT_Y) - 4) % 0x100
            post_key("W", "W continue manual band toward top wrap", PHASE_WAIT_MANUAL_WRAP_TOP)
        end
    elseif phase == PHASE_WAIT_MANUAL_WRAP_TOP then
        if read_byte(CAL_RECT_Y) == manual_wrap_expected then
            if manual_wrap_expected == 0xFC then
                manual_wrap_expected = 0x60
                post_key("W", "W wrap manual band to bottom offscreen", PHASE_WAIT_MANUAL_WRAP_BOTTOM)
            else
                manual_wrap_expected = (manual_wrap_expected - 4) % 0x100
                post_key("W", "W continue manual band toward top wrap", PHASE_WAIT_MANUAL_WRAP_TOP)
            end
        elseif frame > deadline then
            fail(string.format(
                "W did not move manual band to %02X, got %02X",
                manual_wrap_expected,
                read_byte(CAL_RECT_Y)))
        end
    elseif phase == PHASE_WAIT_MANUAL_WRAP_BOTTOM then
        if read_byte(CAL_RECT_Y) == manual_wrap_expected then
            manual_wrap_expected = 0x5C
            post_key("W", "W re-enter manual band from bottom", PHASE_WAIT_MANUAL_WRAP_REAPPEAR)
        elseif frame > deadline then
            fail(string.format(
                "manual band did not wrap to bottom offscreen %02X, got %02X",
                manual_wrap_expected,
                read_byte(CAL_RECT_Y)))
        end
    elseif phase == PHASE_WAIT_MANUAL_WRAP_REAPPEAR then
        if read_byte(CAL_RECT_Y) == manual_wrap_expected then
            local wrapped = sample_manual("manual-wrap-reappear")
            if wrapped or manual_band_memory_ready() then
                print(string.format(
                    "MC-10 pixels: manual band wrap pass top=%02X bottom=%02X reappear=%02X",
                    0xFC,
                    0x60,
                    read_byte(CAL_RECT_Y)))
                post_key("M", "M to alpha values", PHASE_WAIT_ALPHA)
            elseif frame > deadline then
                fail("manual band did not reappear after bottom wrap")
            end
        elseif frame > deadline then
            fail(string.format(
                "manual band did not reappear at %02X, got %02X",
                manual_wrap_expected,
                read_byte(CAL_RECT_Y)))
        end
    elseif phase == PHASE_WAIT_ALPHA then
        if frame >= ALPHA_FRAME then
            local alpha = sample_alpha("alpha")
            if alpha then
                post_key("M", "M to raster drift", PHASE_WAIT_DRIFT)
            elseif frame > deadline then
                fail("initial alpha render was not visible")
            end
        end
    elseif phase == PHASE_WAIT_DRIFT then
        if read_byte(CAL_MODE) == 2 then
            drift_first = sample_cg3("drift-first", "green")
            if drift_first then
                phase = PHASE_DRIFT_GAP
                deadline = frame + SAMPLE_GAP_FRAMES
            elseif frame > deadline then
                fail("raster-drift mode did not render a blue CG3 surface")
            end
        elseif frame > deadline then
            fail("M did not select raster-drift mode")
        end
    elseif phase == PHASE_DRIFT_GAP then
        if frame >= deadline then
            local drift_second = sample_cg3("drift-second", "green")
            if not drift_second then
                fail("raster-drift render disappeared before the second sample")
            end
            local delta = changed_pixels(drift_first, drift_second)
            if delta < 64 then
                fail(string.format("raster-drift witness did not move enough: changed=%d", delta))
            end
            print(string.format("MC-10 pixels: raster-drift motion pass changed=%d", delta))
            post_key("M", "M to phase sweep", PHASE_WAIT_SWEEP)
        end
    elseif phase == PHASE_WAIT_SWEEP then
        if read_byte(CAL_MODE) == 3 then
            sweep_first = sample_cg3("sweep-first", "red")
            if sweep_first then
                phase = PHASE_SWEEP_GAP
                deadline = frame + SAMPLE_GAP_FRAMES
            elseif frame > deadline then
                fail("phase-sweep mode did not render a blue CG3 surface")
            end
        elseif frame > deadline then
            fail("M did not select phase-sweep mode")
        end
    elseif phase == PHASE_SWEEP_GAP then
        if frame >= deadline then
            local sweep_second = sample_cg3("sweep-second", "red")
            if not sweep_second then
                fail("phase-sweep render disappeared before the second sample")
            end
            local delta = changed_pixels(sweep_first, sweep_second)
            if delta < 64 then
                fail(string.format("phase-sweep witness did not move enough: changed=%d", delta))
            end
            print(string.format("MC-10 pixels: phase-sweep motion pass changed=%d", delta))
            post_key("{P}", "P pause sweep", PHASE_WAIT_PAUSE)
        end
    elseif phase == PHASE_WAIT_PAUSE then
        if read_byte(CAL_SWEEP_ACTIVE) == 0 then
            paused_first = sample_cg3("paused-first", "red")
            if paused_first then
                phase = PHASE_PAUSED_GAP
                deadline = frame + SAMPLE_GAP_FRAMES
            elseif frame > deadline then
                local metrics = analyze_pixels()
                print_metrics("paused-timeout", metrics)
                trace_state("paused-timeout")
                save_snapshot("mame-calibrator-paused-timeout")
                fail("paused phase-sweep render was not visible")
            end
        elseif frame > deadline then
            fail("P did not pause phase sweep")
        end
    elseif phase == PHASE_PAUSED_GAP then
        if frame >= deadline then
            local paused_second = sample_cg3("paused-second", "red")
            if not paused_second then
                fail("paused phase-sweep render disappeared before the second sample")
            end
            local delta = changed_pixels(paused_first, paused_second)
            if delta ~= 0 then
                fail(string.format("paused sweep changed rendered pixels: changed=%d", delta))
            end
            print("MC-10 pixels: paused-sweep stability pass changed=0")
            paused_height = read_byte(CAL_SWEEP_HEIGHT_STATE)
            paused_offset = read_byte(CAL_SWEEP_OFFSET)
            paused_sweep_y = read_byte(CAL_SWEEP_Y)
            local upper_boundary = -(paused_sweep_y + paused_height)
            local lower_boundary = 0x60 - paused_sweep_y
            print(string.format(
                "MC-10 geometry: sweep-base=%02X height=%02X upper-last-visible=%+d(%02X) upper-first-invisible=%+d(%02X top=%+d) lower-last-visible=%+d(%02X) lower-first-invisible=%+d(%02X top=%+d)",
                paused_sweep_y,
                paused_height,
                upper_boundary + 4,
                offset_byte(upper_boundary + 4),
                upper_boundary,
                offset_byte(upper_boundary),
                -paused_height,
                lower_boundary - 4,
                offset_byte(lower_boundary - 4),
                lower_boundary,
                offset_byte(lower_boundary),
                0x60))
            post_key("A", "A reduce paused sweep-box height", PHASE_WAIT_RESIZE_DOWN)
        end
    elseif phase == PHASE_WAIT_RESIZE_DOWN then
        local expected = paused_height - 4
        if read_byte(CAL_SWEEP_HEIGHT_STATE) == expected then
            local resized = sample_cg3("sweep-height-small", "red")
            if resized then
                print(string.format(
                    "MC-10 pixels: sweep height decrease pass height=%02X red=%d",
                    read_byte(CAL_SWEEP_HEIGHT_STATE),
                    resized.counts.red))
                post_key("D", "D increase paused sweep-box height", PHASE_WAIT_RESIZE_UP)
            elseif frame > deadline then
                fail("reduced phase-sweep box was not visible")
            end
        elseif frame > deadline then
            fail(string.format(
                "A did not reduce sweep height from %02X to %02X",
                paused_height,
                expected))
        end
    elseif phase == PHASE_WAIT_RESIZE_UP then
        if read_byte(CAL_SWEEP_HEIGHT_STATE) == paused_height then
            local resized = sample_cg3("sweep-height-large", "red")
            if resized then
                print(string.format(
                    "MC-10 pixels: sweep height increase pass height=%02X red=%d",
                    read_byte(CAL_SWEEP_HEIGHT_STATE),
                    resized.counts.red))
                post_key("W", "W move paused sweep box upward", PHASE_WAIT_MOVE_UP)
            elseif frame > deadline then
                fail("restored phase-sweep box was not visible")
            end
        elseif frame > deadline then
            fail(string.format(
                "D did not restore sweep height to %02X, got %02X",
                paused_height,
                read_byte(CAL_SWEEP_HEIGHT_STATE)))
        end
    elseif phase == PHASE_WAIT_MOVE_UP then
        local expected = (paused_offset - 4) % 0x100
        if read_byte(CAL_SWEEP_OFFSET) == expected then
            local moved = sample_cg3("sweep-move-up", "red")
            if moved then
                print(string.format(
                    "MC-10 pixels: sweep upward move pass offset=%02X y=%02X",
                    read_byte(CAL_SWEEP_OFFSET),
                    read_byte(CAL_RECT_Y)))
                post_key("S", "S move paused sweep box downward", PHASE_WAIT_MOVE_DOWN)
            elseif frame > deadline then
                fail("upward-moved phase-sweep box was not visible")
            end
        elseif frame > deadline then
            fail(string.format(
                "W did not reduce sweep offset from %02X, got %02X",
                paused_offset,
                read_byte(CAL_SWEEP_OFFSET)))
        end
    elseif phase == PHASE_WAIT_MOVE_DOWN then
        if read_byte(CAL_SWEEP_OFFSET) == paused_offset then
            local moved = sample_cg3("sweep-move-down", "red")
            if moved then
                print(string.format(
                    "MC-10 pixels: sweep downward move pass offset=%02X y=%02X",
                    read_byte(CAL_SWEEP_OFFSET),
                    read_byte(CAL_RECT_Y)))
                offscreen_target = (read_byte(CAL_SWEEP_OFFSET) + 4) % 0x100
                post_key(
                    "R",
                    "R release keyboard before lower sweep scan",
                    PHASE_WAIT_OFFSCREEN_BOTTOM_START,
                    frame + 12)
            elseif frame > deadline then
                fail("downward-moved phase-sweep box was not visible")
            end
        elseif frame > deadline then
            fail(string.format(
                "S did not restore sweep offset to %02X, got %02X",
                paused_offset,
                read_byte(CAL_SWEEP_OFFSET)))
        end
    elseif phase == PHASE_WAIT_OFFSCREEN_BOTTOM_START then
        if frame >= deadline then
            post_key("S", "S move sweep box toward lower boundary", PHASE_WAIT_OFFSCREEN_BOTTOM)
        end
    elseif phase == PHASE_WAIT_OFFSCREEN_BOTTOM then
        if read_byte(CAL_SWEEP_OFFSET) == offscreen_target then
            local lower_boundary = offset_byte(0x60 - paused_sweep_y)
            if offscreen_target == lower_boundary then
                local background = sample_cg3_background("sweep-offscreen-bottom")
                if background then
                    print(string.format(
                        "MC-10 pixels: sweep bottom disappearance pass offset=%+d(%02X) logical-top=+%d",
                        signed_byte(read_byte(CAL_SWEEP_OFFSET)),
                        read_byte(CAL_SWEEP_OFFSET),
                        0x60))
                    offscreen_target =
                        (read_byte(CAL_SWEEP_OFFSET) - 4) % 0x100
                    post_key(
                        "R",
                        "R release keyboard before upper sweep scan",
                        PHASE_WAIT_OFFSCREEN_TOP_START,
                        frame + 12)
                elseif frame > deadline then
                    fail("sweep box remained visible at the lower offscreen limit")
                end
            else
                offscreen_target = (read_byte(CAL_SWEEP_OFFSET) + 4) % 0x100
                post_key("S", "S continue moving sweep box below screen", PHASE_WAIT_OFFSCREEN_BOTTOM)
            end
        elseif frame > deadline then
            fail(string.format(
                "S did not move sweep offset to %02X, got %02X",
                offscreen_target,
                read_byte(CAL_SWEEP_OFFSET)))
        end
    elseif phase == PHASE_WAIT_OFFSCREEN_TOP_START then
        if frame >= deadline then
            post_key("W", "W move sweep box toward upper boundary", PHASE_WAIT_OFFSCREEN_TOP)
        end
    elseif phase == PHASE_WAIT_OFFSCREEN_TOP then
        if read_byte(CAL_SWEEP_OFFSET) == offscreen_target then
            local upper_boundary = offset_byte(-(paused_sweep_y + paused_height))
            if offscreen_target == upper_boundary then
                local background = sample_cg3_background("sweep-offscreen-top")
                if background then
                    print(string.format(
                        "MC-10 pixels: sweep top disappearance pass offset=%+d(%02X) logical-top=%+d",
                        signed_byte(read_byte(CAL_SWEEP_OFFSET)),
                        read_byte(CAL_SWEEP_OFFSET),
                        -paused_height))
                    post_key("{P}", "P resume sweep", PHASE_WAIT_RESUME)
                elseif frame > deadline then
                    fail("sweep box remained visible at the upper offscreen limit")
                end
            else
                offscreen_target = (read_byte(CAL_SWEEP_OFFSET) - 4) % 0x100
                post_key("W", "W continue moving sweep box above screen", PHASE_WAIT_OFFSCREEN_TOP)
            end
        elseif frame > deadline then
            fail(string.format(
                "W did not move sweep offset to %02X, got %02X",
                offscreen_target,
                read_byte(CAL_SWEEP_OFFSET)))
        end
    elseif phase == PHASE_WAIT_RESUME then
        if read_byte(CAL_SWEEP_ACTIVE) == 1 then
            post_key("M", "M return to manual band", PHASE_WAIT_RETURN_MANUAL)
        elseif frame > deadline then
            fail("P did not resume phase sweep")
        end
    elseif phase == PHASE_WAIT_RETURN_MANUAL then
        if read_byte(CAL_MODE) == 0 then
            local manual = sample_manual("return-manual")
            if manual then
                trace_state("complete")
                print("MC-10 calibrator regression: PASS")
                phase = PHASE_DONE
                machine:exit()
            elseif manual_band_memory_ready() then
                save_snapshot("mame-calibrator-return-manual")
                trace_state("complete-memory-verified")
                print("MC-10 pixels: return-manual screen RAM band pass")
                print("MC-10 calibrator regression: PASS")
                phase = PHASE_DONE
                machine:exit()
            elseif frame > deadline then
                trace_state("return-manual-timeout")
                fail("return to manual mode changed the mode byte but not the rendered band")
            end
        elseif frame > deadline then
            fail("M did not cycle from phase sweep back to manual band mode")
        end
    end
end)
