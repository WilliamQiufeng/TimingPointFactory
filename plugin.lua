function draw()
    creationPanel()
end

logs = ""

function get(identifier, defaultValue)
    return state.GetValue(identifier) or defaultValue
end

function round(num, numDecimalPlaces)
    local mult = 10 ^ (numDecimalPlaces or 0)
    return math.floor(num * mult + 0.5) / mult
end

function splitNums(inputstr)
    local t = {}
    for str in string.gmatch(inputstr, "([^,]+)") do
        table.insert(t, tonumber(str) or 0)
    end
    return t
end

function creationPanel()
    imgui.Begin("Timing Point Factory")

    startTime = get("startTime", 0)
    _, startTime = imgui.InputInt("Start Time", startTime)
    local currentTimeAsStartTime = imgui.Button("Use current time as start time")
    if currentTimeAsStartTime then
        startTime = state.SongTime
    end
    state.SetValue("startTime", startTime)

    endTime = get("endTime", 0)
    _, endTime = imgui.InputInt("End Time", endTime)
    local currentTimeAsEndTime = imgui.Button("Use current time as end time")
    if currentTimeAsEndTime then
        endTime = state.SongTime
    end
    state.SetValue("endTime", endTime)

    imgui.Dummy({ 10, 20 })

    imgui.BeginTabBar("##Actions")
    if imgui.BeginTabItem("Place Timing Points") then
        bpm = get("bpm", 0)
        _, bpm = imgui.InputInt("BPM", bpm)
        state.SetValue("bpm", bpm)

        pattern = get("pattern", "4")
        imgui.Text("Pattern is a list of numbers separated by ','")
        imgui.Text("For example: 5.2,3.2")
        imgui.Text("The plugin will generate the pattern repeatedly")


        _, pattern = imgui.InputText("Pattern", pattern, 1024)
        state.SetValue("pattern", pattern)

        patternNums = splitNums(pattern)

        if imgui.Button("Create##TimingPoints") then
            createTimingPoints()
        end
        for i, sig in pairs(patternNums) do
            imgui.Text("Signature #" .. i .. ": " .. sig .. "/4")
        end
        imgui.EndTabItem()
    end
    if imgui.BeginTabItem("Place Tuplets") then
        imgui.TextWrapped(
            "Adds timing point between the selected times such that the 1/4th note has the length of (end - start) / tupletNumber.")
        imgui.TextWrapped(
            "Additional timing points will be added after the end time to preserve the supposed measure starting beat.")
        imgui.Dummy({ 10, 10 })
        local tupletNum = get("tupletNum", 4)
        _, tupletNum = imgui.InputFloat("Tuplet Number", tupletNum)
        state.SetValue("tupletNum", tupletNum)

        if imgui.Button("Create##Tuplets") then
            local endTp = map.GetTimingPointAt(endTime)
            local startTp = map.GetTimingPointAt(startTime)
            local msPerBeat = (endTime - startTime) / tupletNum

            -- endTp -> endTime
            local beatEndTpToEndBeat = (endTime - endTp.StartTime) / endTp.MillisecondsPerBeat
            local endTpSignature = 4 -- TODO: endTp.Signature convert to int
            if endTp.Signature == time_signature.Triple then
                endTpSignature = 3
            end

            local recoverBeat = 1 - beatEndTpToEndBeat % 1
            local recoverBeatTpTime = endTime + recoverBeat * endTp.MillisecondsPerBeat

            local recoverMeasure = (endTpSignature - beatEndTpToEndBeat % endTpSignature) % endTpSignature
            local recoverMeasureTpTime = endTime + recoverMeasure * endTp.MillisecondsPerBeat

            local recoverBeatSignature = math.ceil(
                (recoverMeasureTpTime - recoverBeatTpTime) / endTp.MillisecondsPerBeat)

            local signature = math.ceil(tupletNum)

            local tupletTp = utils.CreateTimingPoint(startTime, 60000 / msPerBeat, signature, true)
            local endReturnTp = utils.CreateTimingPoint(endTime, endTp.Bpm, recoverBeatSignature + 1, true)
            local recoverBeatTp = utils.CreateTimingPoint(recoverBeatTpTime, endTp.Bpm, recoverBeatSignature, true)
            local recoverMeasureTp = utils.CreateTimingPoint(recoverMeasureTpTime, endTp.Bpm, endTp.Signature, false)

            tpBatch = { tupletTp, endReturnTp }
            if endTime ~= recoverBeatTpTime and recoverBeatTpTime ~= recoverMeasureTpTime then
                table.insert(tpBatch, recoverBeatTp)
            end
            if endTime ~= recoverMeasureTpTime then
                table.insert(tpBatch, recoverMeasureTp)
            end
            actions.PlaceTimingPointBatch(tpBatch)
        end
        imgui.EndTabItem()
    end
    imgui.EndTabBar()
    imgui.Text(logs)
    imgui.End()
end

function createTimingPoints()
    local patternIdx = 1
    local curTime = startTime
    local batch = {}
    -- Include start and end currently
    while curTime <= endTime do
        local realSig = patternNums[patternIdx]
        local sig = math.max(math.ceil(realSig), 1)
        local tp = utils.CreateTimingPoint(curTime, bpm, sig)
        table.insert(batch, tp)
        local timePassed = 60000 / bpm * realSig
        patternIdx = patternIdx + 1
        if patternIdx > #patternNums then
            patternIdx = 1
        end
        curTime = curTime + timePassed
    end
    actions.PlaceTimingPointBatch(batch)
end

function log(text)
    logs = logs .. "\n" .. text
end
