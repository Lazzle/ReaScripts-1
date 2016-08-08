-- @description js_Notation - Double displayed length of selected notes and add staccato articulation.lua
-- @about
--  # Double the displayed length of selected notes and add staccato articulation
--
--    This script is intended to help solve the problem of short notes (such as staccato or muted guitar notes) 
--      that are notated with extraneous rests in-between.
--    Simply increasing the displayed length of the notes (by using the built-in action "Nudge length display offset right", 
--      for example) will remove the rests, but then the displayed lengths will not accurately reflect the lengths of 
--      the underlying MIDI notes.
--    This script therefore adds a staccato articulation to indicate that the underlying MIDI notes are actually shorter.
--    (The standard interpretation of staccato articulations is to halve the length of a note.)
--
-- @author juliansader
-- @website
--   Forum Thread http://forum.cockos.com/showthread.php?t=172782&page=25
-- @screenshot
-- @version 1.0
-- @changelog
--   + Initial beta release


---------------------------------------------------------------
-- Returns the textsysex index of a given note's notation info.
-- If no notation info is found, returns -1.
function getTextIndexForNote(take, notePPQ, noteChannel, notePitch)

    reaper.MIDI_Sort(take)
    _, _, _, countTextSysex = reaper.MIDI_CountEvts(take)
    if countTextSysex > 0 then 
    
        -- Use binary search to find text event closest to the left of note's PPQ        
        local rightIndex = countTextSysex-1
        local leftIndex = 0
        local middleIndex
        while (rightIndex-leftIndex)>1 do
            middleIndex = math.ceil((rightIndex+leftIndex)/2)
            local textOK, _, _, textPPQ, _, _ = reaper.MIDI_GetTextSysexEvt(take, middleIndex, true, false, 0, 0, "")
            if textPPQ >= notePPQ then
                rightIndex = middleIndex
            else
                leftIndex = middleIndex
            end     
        end -- while (rightIndex-leftIndex)>1
        
        -- Now search through text events one by one
        for i = leftIndex, countTextSysex-1 do
            local textOK, _, _, textPPQ, type, msg = reaper.MIDI_GetTextSysexEvt(take, i, true, false, 0, 0, "")
            -- Assume that text events are order by PPQ position, so if beyond, no need to search further
            if textPPQ > notePPQ then 
                break
            elseif textPPQ == notePPQ and type == 15 then
                textChannel, textPitch = msg:match("NOTE ([%d]+) ([%d]+)")
                if noteChannel == tonumber(textChannel) and notePitch == tonumber(textPitch) then
                    return i, msg
                end
            end   
        end
    end
    
    -- Nothing was found
    return(-1)
end

--------------------------------------
-- Here the code execution starts
-- function main()
editor = reaper.MIDIEditor_GetActive()
if editor ~= nil then
    take = reaper.MIDIEditor_GetTake(editor)
    if reaper.ValidatePtr2(0, take, "MediaItem_Take*") then    
                        
        reaper.Undo_BeginBlock2(0)

        -- Weird, sometimes REAPER's PPQ is not 960.  So first get PPQ of take.
        local QNstart = reaper.MIDI_GetProjQNFromPPQPos(take, 0)
        PPQ = reaper.MIDI_GetPPQPosFromProjQN(take, QNstart + 1) - QNstart
        PP64 = PPQ/16
                    
        i = -1
        repeat
            i = reaper.MIDI_EnumSelNotes(take, i)
            if i ~= -1 then
                noteOK, _, _, noteStartPPQ, noteEndPPQ, channel, pitch, _ = reaper.MIDI_GetNote(take, i)
                -- Based on experimentation, it seems that in REAPER's "disp_len" field, a value of "0.064" 
                --    increases the displayed note length by one 1/64th note.
                textForField = string.format("%.4f", tostring(((noteEndPPQ - noteStartPPQ)/PP64) * 0.064))
                
                notationIndex, msg = getTextIndexForNote(take, noteStartPPQ, channel, pitch)
                if notationIndex == -1 then
                    -- If note does not yet have notation info, create new event
                    reaper.MIDI_InsertTextSysexEvt(take, true, false, noteStartPPQ, 15, "NOTE "
                                                                                        ..tostring(channel)
                                                                                        .." "
                                                                                        ..tostring(pitch)
                                                                                        .." "
                                                                                        .."articulation staccato disp_len "
                                                                                        ..textForField)
                else
                    -- Remove existing articulation and length tweaks 
                    msg = msg:gsub(" articulation [%a]+", "")
                    msg = msg:gsub(" disp_len [%-]*[%d]+.[%d]+", "")
                    msg = msg .." articulation staccato disp_len "..textForField
                    reaper.MIDI_SetTextSysexEvt(take, notationIndex, nil, nil, nil, nil, msg, false)
                end
            end
        until i == -1
        
        reaper.Undo_EndBlock2(0, "Notation - Double displayed length and add staccato articulation", -1)
    end
end