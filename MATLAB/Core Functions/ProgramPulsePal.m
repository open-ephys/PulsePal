%{
----------------------------------------------------------------------------

This file is part of the PulsePal Project
Copyright (C) 2014 Joshua I. Sanders, Cold Spring Harbor Laboratory, NY, USA

----------------------------------------------------------------------------

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, version 3.

This program is distributed  WITHOUT ANY WARRANTY and without even the 
implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  
See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
%}

function ConfirmBit = ProgramPulsePal(ProgramMatrix)

% Import virtual serial port object into this workspace from base
global PulsePalSystem;
   OriginalProgMatrix = ProgramMatrix;
    
    % Extract trigger address bytes
    Chan1TrigAddressBytes = uint8(cell2mat(ProgramMatrix(13,2:5)));
    Chan2TrigAddressBytes = uint8(cell2mat(ProgramMatrix(14,2:5)));
    
    % Extract custom override byte (0 if parameterized, 1 if this channel uses custom
    % stimulus train 1, 2 if this channel uses custom stimulus train 2)
    FollowsCustomStimID = uint8(cell2mat(ProgramMatrix(15,2:5)));
    
    % Extract custom stim target byte (0 if custom timestamps point to
    % pulse onsets ignoring inter-pulse interval, 1 if custom timestamps point to burst onsets, 
    % ignoring inter-burst interval)
    CustomStimTarget = uint8(cell2mat(ProgramMatrix(16,2:5)));
    
    % Extract custom stim loop byte (0 if the sequence is to be played only
    % once, 1 if it is to be looped until the end of
    % StimulusTrainDuration.)
    CustomStimLoop = uint8(cell2mat(ProgramMatrix(17,2:5)));
    
    % Extract biphasic settings for the four channels - 0 if monophasic pulses, 1 if biphasic
    IsBiphasic = cell2mat(ProgramMatrix(2,2:5)); IsBiphasic = uint8(IsBiphasic);
    
    % Extract pulse voltage for phase 1
    Phase1Voltages = cell2mat(ProgramMatrix(3,2:5));
    % Extract pulse voltage for phase 2
    Phase2Voltages = cell2mat(ProgramMatrix(4,2:5));
    % Extract resting voltages
    RestingVoltages = cell2mat(ProgramMatrix(18,2:5));
    
    % Check if pulse amplitude is in range
    AllVoltages = [Phase1Voltages Phase2Voltages RestingVoltages];
    if (sum(AllVoltages > 10) > 0) || (sum(AllVoltages < -10) > 0)
        error('Error: Voltages for Pulse Pal rev0.4 must be in the range -10V to 10V, and will be rounded to the nearest 78.125 mV.')
    end
    
    % Check if burst duration is defined when custom timestamps target
    % burst onsets
    for x = 1:4
        if CustomStimTarget(x) == 1
            BDuration = ProgramMatrix{9,1+x};
            if BDuration == 0
                error(['Error in output channel ' num2str(x) ': When custom stimuli target burst onsets, a non-zero burst duration must be defined.'])
            end
        end
    end

    % For parameterized mode, check whether partial pulses will be
    % generated, and adjust specified stimulus duration to exclude them.
    for x = 1:4
        BiphasicChannel = ProgramMatrix{2,1+x};
        if BiphasicChannel == 0
            PulseDuration = ProgramMatrix{5,1+x};
        else
            PulseDuration = ProgramMatrix{5,1+x} + ProgramMatrix{6,1+x} + ProgramMatrix{7,1+x};
        end
        PulseTrainDuration = ProgramMatrix{11,1+x};
        PulseOverlap = rem(PulseTrainDuration, PulseDuration);
        if PulseOverlap > 0
            PulseTrainDuration = PulseTrainDuration - PulseOverlap;
            ProgramMatrix{11,1+x} = PulseTrainDuration;
        end
    end
    
    
    % Extract voltages for phases 1 and 2
    Phase1Voltages = uint8(ceil(((Phase1Voltages+10)/20)*255));
    Phase2Voltages = uint8(ceil(((Phase2Voltages+10)/20)*255));
    RestingVoltages = uint8(ceil(((RestingVoltages+10)/20)*255));
    
    % Extract input channel settings
    
    InputChanMode = uint8(cell2mat(ProgramMatrix(2,8:9))); % if 0, "Normal mode", triggers on low to high transitions and ignores triggers until end of stimulus train. 
    % if 1, "Toggle mode", triggers on low to high and shuts off stimulus
    % train on next high to low. If 2, "Button mode", triggers on low to
    % high and shuts off on high to low.
    
    
    % Convert time data to microseconds
    TimeData = cell2mat(ProgramMatrix(5:12, 2:5));
    
    % Ensure time data is within range
    if sum(sum(rem(round(TimeData*1000000), PulsePalSystem.MinPulseDuration))) > 0
        errordlg(['Non-zero time values for Pulse Pal rev0.4 must be multiples of ' num2str(PulsePalSystem.MinPulseDuration) ' microseconds. Please check your program matrix.'], 'Invalid program');
    end
    
    TimeData = uint32(TimeData*PulsePalSystem.CycleFrequency); % Convert to multiple of cycle frequency
    
    
    
    % Arrange program into a single byte-string
    FormattedProgramTimestamps = TimeData(1:end); 
    SingleByteOutputParams = [IsBiphasic; Phase1Voltages; Phase2Voltages; FollowsCustomStimID; CustomStimTarget; CustomStimLoop; RestingVoltages];
    FormattedParams = [SingleByteOutputParams(1:end) Chan1TrigAddressBytes Chan2TrigAddressBytes InputChanMode];
    
    % Send program
%     fwrite(PulsePalSystem.SerialPort, 73, 'uint8'); % Instruct PulsePal to recieve a new program with byte 73
%     fwrite(PulsePalSystem.SerialPort, FormattedProgramTimestamps, 'uint32'); % Send 32 bit time data
%     fwrite(PulsePalSystem.SerialPort, FormattedParams, 'uint8'); % Send 8-bit params
    
    ByteString = [PulsePalSystem.OpMenuByte 73 typecast(FormattedProgramTimestamps, 'uint8') FormattedParams];
    fwrite(PulsePalSystem.SerialPort, ByteString, 'uint8');
    ConfirmBit = fread(PulsePalSystem.SerialPort, 1); % Get confirmation
    PulsePalSystem.CurrentProgram = OriginalProgMatrix; % Update Pulse Pal object