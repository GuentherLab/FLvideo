% MATLAB Script for video control with audio visualization and controls
% Must first convert the real-time MRI files from Gottingen to AVI files
% using the same codec as in the MP4 files ("copy" the codec when
% translating, e.g. using https://cloudconvert.com/mp4-to-avi
%
function VidTest22(videoFile)

    if nargin<1, videoFile = ''; end % Video file path
    
    [data,hFig] = initialize(videoFile);
    
    % Main loop for handling video playback
    while ishandle(hFig)
        % Retrieve the latest state
        if isfield(data,'isPlaying')&&data.isPlaying
            % Update frame index
            currentFrame = ceil(max(1,data.audioPlayer.CurrentSample-data.SampleQueue)/data.SampleRate*data.FrameRate);
            %disp([data.audioPlayer.CurrentSample currentFrame])
            if data.currentFrame~=currentFrame,
                if (currentFrame==1&&data.currentFrame>1) || currentFrame >= data.endFrame % if audio is stopped (but not paused)
                    currentFrame = data.endFrame; %min(data.numFrames,data.currentFrame);
                    data.isPlaying = false; % Stop playback
                end
    
                % Update video and lines
                % Update video frame
                data.currentFrame=currentFrame ;
                frame = data.frameCache{currentFrame};
                if isvalid(data.hVideo) % Ensure the hVideo object is valid
                    set(data.hVideo, 'CData', frame); % Update video frame
                else
                    disp('invalid video frame');
                end
    
                timeAtCurrentFrame = (currentFrame-1) / data.FrameRate;
                set(data.frameLine, 'XData', [timeAtCurrentFrame timeAtCurrentFrame], 'YData', data.audioYLim);
                set(data.motionFrameLine, 'XData', [timeAtCurrentFrame timeAtCurrentFrame], 'YData', data.motionYLim);
                drawnow;
            else pause(0.001);
            end
        else
            pause(0.01);
        end
    end


    % Callback Functions (NOTE: they all have access to the shared variable "data")
    function [data, hFig] = initialize(videoFile, hFig)
        v=[];
        isready='off';
        if ~isempty(videoFile), 
            % Create a VideoReader object
            try
                v = VideoReader(videoFile);
                isready='on';
            catch me
                errordlg([{'Problem reading video file:'} getReport(me,'basic','hyperlinks','off')], 'Video Player error');
                isready='off';
            end
        end
        % Create the main figure for video, audio, and controls
        if nargin<2, 
            hFig = figure('Position', [100, 50, 800, 900], 'MenuBar', 'none', 'NumberTitle', 'off', 'Name', 'Video Player','color','w');
        else 
            set(hFig, 'name', 'Video Player');
            clf(hFig);
        end

        % Create a panel for the control buttons
        buttonPanel = uipanel('Position', [0, 0, 1, 0.15], 'Parent', hFig); % Slightly shorter panel for two rows of buttons

        % Top row: Playback buttons
        uicontrol('Style', 'pushbutton', 'String', 'Play/Pause', 'Position', [20, 70, 100, 40], ...
            'Callback', @(src, event) togglePlayPause(src, event, hFig), 'Parent', buttonPanel, 'enable',isready);

        uicontrol('Style', 'pushbutton', 'String', 'Next Frame', 'Position', [130, 70, 100, 40], ...
            'Callback', @(src, event) nextFrame(src, event, hFig), 'Parent', buttonPanel, 'enable',isready);

        uicontrol('Style', 'pushbutton', 'String', 'Previous Frame', 'Position', [240, 70, 100, 40], ...
            'Callback', @(src, event) previousFrame(src, event, hFig), 'Parent', buttonPanel, 'enable',isready);

        uicontrol('Style', 'pushbutton', 'String', 'Rewind', 'Position', [350, 70, 100, 40], ...
            'Callback', @(src, event) rewindVideo(src, event, hFig), 'Parent', buttonPanel, 'enable',isready);

        uicontrol('Style', 'text', 'String', 'Playback Speed', 'Position', [470, 80, 100, 20], 'Parent', buttonPanel);
        uicontrol('Style', 'slider', 'Min', 0.1, 'Max', 2, 'Value', 1, 'Position', [580, 80, 100, 20], ...
            'Callback', @(src, event) adjustPlaybackSpeed(src, event, hFig), 'Parent', buttonPanel, 'enable',isready);

        % Bottom row: Selection and save controls
        uicontrol('Style', 'pushbutton', 'String', 'Select Points', 'Position', [20, 20, 100, 40], ...
            'Callback', @(src, event) selectPoints(hFig), 'Parent', buttonPanel, 'enable',isready);

        uicontrol('Style', 'pushbutton', 'String', 'Save Clip', 'Position', [130, 20, 100, 40], ...
            'Callback', @(src, event) saveClip(hFig), 'Parent', buttonPanel, 'enable',isready);

        playSelectionButton = uicontrol('Style', 'pushbutton', 'String', 'Play/Pause Selection', ...
            'Position', [240, 20, 120, 40], 'Enable', 'off', ...
            'Callback', @(src, event) playSelection(hFig), 'Parent', buttonPanel);

        uicontrol('Style', 'pushbutton', 'String', 'Load New Video', 'Position', [360, 20, 120, 40], ...
            'Callback', @(src, event) loadNewVideo(hFig), 'Parent', buttonPanel);
        
        data=[];
        if ~isempty(v) % Loads video and audio data
            % Check video properties
            disp(['Duration: ', num2str(v.Duration), ' seconds']);
            disp(['Video Frame Rate: ', num2str(v.FrameRate), ' fps']);
            disp(['Video Resolution: ', num2str(v.Width), 'x', num2str(v.Height)]);
            %disp(['Audio Format: ', v.AudioFormat]); % Audio information, if available
            % Extract audio signal
            [audioSignal, audioFs] = audioread(videoFile); % Read audio from the video

            % Get total frames of video
            numFrames = v.NumFrames; %floor(v.Duration * v.FrameRate); % NOTE: v.Duration is not an integer multiple of 1/FrameRate
            FrameRate = v.FrameRate; %numFrames/v.Duration;

            audioDuration = length(audioSignal) / audioFs; % Calculate audio duration
            audioTime = (0:length(audioSignal)-1)/audioFs; % linspace(0, audioDuration, length(audioSignal)); % Time points for audio signal (starts at t=0)
            totalDuration = max(audioDuration, v.Duration);

            % Preload frames into cache
            timeCache = [];
            frameCache = cell(1, numFrames);
            for i = 1:numFrames
                frameCache{i} = read(v, i);
                timeCache(i)=v.CurrentTime;
            end
            %disp(size(frameCache{1})); % Display dimensions of the first frame
            %disp(class(frameCache{1})); % Display data type of the first frame

            % Calculate global motion based on pixel differences
            globalMotion = zeros(1, numFrames - 1); % Preallocate for speed
            for i = 1:numFrames - 1
                frame1 = double(rgb2gray(frameCache{i})); % Convert frame to grayscale
                frame2 = double(rgb2gray(frameCache{i + 1})); % Convert next frame to grayscale
                globalMotion(i) = sum(abs(frame1(:) - frame2(:)).^2); % Compute sum of absolute differences (SAD)
            end
            globalMotion = [globalMotion, globalMotion(end)]; % Match the length to numFrames

            % Create an axes for the video display
            videoPanel = axes('Position', [0.1, 0.55, 0.8, 0.4], 'Parent', hFig); % Move video panel upward
            hVideo = imshow(frameCache{1}, 'Parent', videoPanel); % Placeholder for video frame
            %disp(hVideo); % Display information about the hVideo object
            if isvalid(hVideo)
                disp('hvideo initialized'); % Verify if hVideo is valid after initialization
            end
            axis(videoPanel, 'off'); % Hide axis lines and labels
            title(videoPanel, 'Video Playback', 'Color', 'w');

            % Create a dedicated axes for the audio signal
            audioPanel = axes('Position', [0.1, 0.4, 0.8, 0.1], 'Parent', hFig); % Move audio panel upward
            audioPlot = plot(audioTime, audioSignal, 'b', 'Parent', audioPanel); % Plot full audio signal
            hold(audioPanel, 'on');
            frameLine = plot(audioPanel, 0, 0, 'r', 'LineWidth', 2); % Red line for current frame
            xlim(audioPanel, [0 totalDuration]); % Set x-axis limits based on audio duration
            audioYLim = [-1, 1]*1.1*max(abs(audioSignal(:))); % Get the correct y-limits for the audio signal
            ylim(audioPanel, audioYLim); % Apply y-limits for the audio plot
            xlabel(audioPanel, 'Time (s)');
            ylabel(audioPanel, 'Audio Signal Intensity');
            title(audioPanel, 'Audio Signal with Current Frame');
            hold(audioPanel, 'off');
            set([audioPanel; audioPlot(:)],'buttondownfcn',@(varargin)thisFrame(get(gca,'currentpoint')));

            % Create a dedicated axes for the global motion
            motionPanel = axes('Position', [0.1, 0.25, 0.8, 0.1], 'Parent', hFig); % Move motion panel upward
            motionPlot = plot(motionPanel, (1:numFrames)/FrameRate, globalMotion, 'g'); % Plot global motion
            hold(motionPanel, 'on');
            motionFrameLine = plot(motionPanel, 0, 0, 'r', 'LineWidth', 2); % Red line for current frame
            xlim(motionPanel, [0 totalDuration]); % Set x-axis limits based on video duration
            motionYLim = [0 1.1*max(globalMotion)]; % Calculate y-limits for the global motion
            ylim(motionPanel, motionYLim); % Apply y-limits for the motion plot
            xlabel(motionPanel, 'Time (s)');
            ylabel(motionPanel, 'Motion Intensity');
            title(motionPanel, 'Global Motion Across Frames');
            hold(motionPanel, 'off');
            set([motionPanel; motionPlot(:)],'buttondownfcn',@(varargin)thisFrame(get(gca,'currentpoint')));

            % Store information in shared "data" variable
            data.isPlaying = false;
            data.currentFrame = 1; % Start at the first frame
            data.endFrame = 0;
            data.numFrames = numFrames;
            data.FrameRate = FrameRate;
            data.v = v;
            data.audioSignal = audioSignal;
            data.SampleRate = audioFs;
            data.SampleQueue = 0;
            data.hVideo = hVideo;
            data.frameCache = frameCache;
            data.audioPanel = audioPanel;
            data.motionPanel = motionPanel;
            data.frameLine = frameLine;
            data.motionFrameLine = motionFrameLine;
            data.audioYLim = audioYLim;
            data.motionYLim = motionYLim;
            data.playbackSpeed = 1; % Default playback speed
            data.audioPlayer = audioplayer(audioSignal, audioFs); % Create audioplayer object
            data.playSelectionButton = playSelectionButton;

            % adds video name 
            set(hFig, 'name', sprintf('Video Player : %s',videoFile));
            
        end


    end
    function togglePlayPause(~, ~, hFig)
        % Retrieve the current state

        % Toggle playback state
        data.isPlaying = ~data.isPlaying;

        if data.isPlaying
            % Start audio playback from the current time
            startSample = max(1, min(length(data.audioSignal)-1, 1+round((data.currentFrame-1)/data.FrameRate*data.SampleRate)));
            data.audioPlayer.SampleRate=data.SampleRate*data.playbackSpeed;
            data.endFrame=data.numFrames;
            play(data.audioPlayer, [startSample, length(data.audioSignal)]);
            if data.SampleQueue==0, data.SampleQueue=data.audioPlayer.CurrentSample-startSample; disp(data.SampleQueue); end
        else
            % Pause audio playback
            pause(data.audioPlayer);
        end

    end

    function nextFrame(~, ~, hFig)
        if ~data.isPlaying,
            if data.currentFrame < data.numFrames
                data.currentFrame = data.currentFrame + 1;
                currentFrameIndex = round(data.currentFrame);
                frame = data.frameCache{currentFrameIndex};
                set(data.hVideo, 'CData', frame);
                timeAtCurrentFrame = (currentFrameIndex-1) / data.FrameRate;
                set(data.frameLine, 'XData', [timeAtCurrentFrame timeAtCurrentFrame], 'YData', ylim(data.audioPanel));
                set(data.motionFrameLine, 'XData', [timeAtCurrentFrame timeAtCurrentFrame], ...
                    'YData', ylim(data.motionPanel));

                % Play the audio for the current frame
                startSample = max(1,min(length(data.audioSignal)-1, 1+round((data.currentFrame-1)/data.FrameRate*data.SampleRate) ));
                endSample = max(1,min(length(data.audioSignal), 1+round((data.currentFrame-0)/data.FrameRate*data.SampleRate) ));
                data.audioPlayer.SampleRate=data.SampleRate*data.playbackSpeed;
                data.endFrame=data.currentFrame;
                play(data.audioPlayer, [startSample, endSample]);
                drawnow;
            end
        end
    end

    function previousFrame(~, ~, hFig)
        if ~data.isPlaying,
            if data.currentFrame > 1
                data.currentFrame = data.currentFrame - 1;
                currentFrameIndex = round(data.currentFrame);
                frame = data.frameCache{currentFrameIndex};
                set(data.hVideo, 'CData', frame);
                timeAtCurrentFrame = (currentFrameIndex-1) / data.FrameRate;
                set(data.frameLine, 'XData', [timeAtCurrentFrame timeAtCurrentFrame], 'YData', ylim(data.audioPanel));
                set(data.motionFrameLine, 'XData', [timeAtCurrentFrame timeAtCurrentFrame], ...
                    'YData', ylim(data.motionPanel));
                drawnow;
            end
        end
    end

    function thisFrame(thisTime)
        if ~data.isPlaying,
            data.currentFrame = max(1, min(data.numFrames, ceil(thisTime(1) * data.FrameRate)));
            currentFrameIndex = round(data.currentFrame);
            frame = data.frameCache{currentFrameIndex};
            set(data.hVideo, 'CData', frame);
            timeAtCurrentFrame = (currentFrameIndex-1) / data.FrameRate;
            set(data.frameLine, 'XData', [timeAtCurrentFrame timeAtCurrentFrame], 'YData', ylim(data.audioPanel));
            set(data.motionFrameLine, 'XData', [timeAtCurrentFrame timeAtCurrentFrame], ...
                'YData', ylim(data.motionPanel));
            drawnow;
        end
    end

    function rewindVideo(~, ~, hFig)
        if ~data.isPlaying,
            data.currentFrame = 1;
            currentFrameIndex = round(data.currentFrame);
            frame = data.frameCache{currentFrameIndex};
            set(data.hVideo, 'CData', frame);
            timeAtCurrentFrame = (currentFrameIndex-1) / data.FrameRate;
            set(data.frameLine, 'XData', [timeAtCurrentFrame timeAtCurrentFrame], 'YData', ylim(data.audioPanel));
            set(data.motionFrameLine, 'XData', [timeAtCurrentFrame timeAtCurrentFrame], ...
                'YData', ylim(data.motionPanel));
            drawnow;
        end
    end

    function adjustPlaybackSpeed(slider, ~, hFig)
        if data.isPlaying, slider.Value=data.playbackSpeed;
        else data.playbackSpeed = slider.Value;
        end
    end

    function selectPoints(hFig)
        % Retrieve current state

        % Save the current axis limits
        currentAudioXLim = xlim(data.audioPanel);
        currentMotionXLim = xlim(data.motionPanel);
        currentAudioYLim = ylim(data.audioPanel);
        currentMotionYLim = ylim(data.motionPanel);

        % Hold the current plots to preserve existing data
        hold(data.audioPanel, 'on');
        hold(data.motionPanel, 'on');

        % Display instructions
        disp('Select a point on the audio plot');
        [audioX, ~] = ginput(1); % Select first point on the audio plot

        % Add a temporary vertical line for the selected audio point
        tempAudioLine = line(data.audioPanel, [audioX, audioX], currentAudioYLim, ...
            'Color', 'blue', 'LineStyle', '--');
        disp('Select a point on the motion plot');
        [motionX, ~] = ginput(1); % Select second point on the motion plot

        % Add a temporary vertical line for the selected motion point
        tempMotionLine = line(data.motionPanel, [motionX, motionX], currentMotionYLim, ...
            'Color', 'blue', 'LineStyle', '--');

        % Determine the selected range
        startTime = min(audioX, motionX);
        endTime = max(audioX, motionX);

        % Add shading to indicate the selected range
        tempAudioShading = fill(data.audioPanel, ...
            [startTime, endTime, endTime, startTime], ...
            [currentAudioYLim(1), currentAudioYLim(1), currentAudioYLim(2), currentAudioYLim(2)], ...
            'blue', 'FaceAlpha', 0.2, 'EdgeColor', 'none');
        tempMotionShading = fill(data.motionPanel, ...
            [startTime, endTime, endTime, startTime], ...
            [currentMotionYLim(1), currentMotionYLim(1), currentMotionYLim(2), currentMotionYLim(2)], ...
            'blue', 'FaceAlpha', 0.2, 'EdgeColor', 'none');
        set([tempAudioShading, tempMotionShading],'buttondownfcn',@(varargin)thisFrame(get(gca,'currentpoint')));

        % Remove previous lines and shading only after new points are selected
        if isfield(data, 'audioLine') && isvalid(data.audioLine)
            delete(data.audioLine); % Remove previous audio line
        end
        if isfield(data, 'motionLine') && isvalid(data.motionLine)
            delete(data.motionLine); % Remove previous motion line
        end
        if isfield(data, 'audioShading') && isvalid(data.audioShading)
            delete(data.audioShading); % Remove previous audio shading
        end
        if isfield(data, 'motionShading') && isvalid(data.motionShading)
            delete(data.motionShading); % Remove previous motion shading
        end

        % Save the new lines and shading to the data structure
        data.audioLine = tempAudioLine;
        data.motionLine = tempMotionLine;
        data.audioShading = tempAudioShading;
        data.motionShading = tempMotionShading;

        % Debugging: Check if playSelectionButton exists and is valid
        if isfield(data, 'playSelectionButton') && isvalid(data.playSelectionButton)
            disp('Got to here: playSelectionButton exists and is valid');
            set(data.playSelectionButton, 'Enable', 'on');
        else
            disp('playSelectionButton does not exist or is invalid');
        end

        % Restore the original axis limits
        xlim(data.audioPanel, currentAudioXLim);
        ylim(data.audioPanel, currentAudioYLim);
        xlim(data.motionPanel, currentMotionXLim);
        ylim(data.motionPanel, currentMotionYLim);

        % Release hold on the plots
        hold(data.audioPanel, 'off');
        hold(data.motionPanel, 'off');

        % Display the time difference between the selected points
        disp(['Time difference between selected points: ', num2str(endTime - startTime), ' seconds.']);
    end

    function saveClip(hFig)
        % Check if audioLine and motionLine exist
        if ~isfield(data, 'audioLine') || ~isvalid(data.audioLine) || ...
                ~isfield(data, 'motionLine') || ~isvalid(data.motionLine)
            disp('Error: Select time points before saving a clip.');
            return;
        end

        % Get selected time points from audioLine and motionLine
        audioX = data.audioLine.XData(1); % Time point from audio plot
        motionX = data.motionLine.XData(1); % Time point from motion plot

        % Calculate start and end times (in seconds)
        startTime = min(audioX, motionX);
        endTime = max(audioX, motionX);
        disp(['Saving clip from ', num2str(startTime), ' to ', num2str(endTime), ' seconds.']);

        % Prompt user for output file name
        [fileName, filePath] = uiputfile('*.avi', 'Save Video Clip As');
        if fileName == 0
            disp('Saving cancelled.');
            return;
        end
        outputFile = fullfile(filePath, fileName);

        % Calculate frame range
        startFrame = max(1, floor(startTime * data.FrameRate));
        endFrame = min(data.numFrames, ceil(endTime * data.FrameRate));

        % Calculate audio sample range
        startSample = max(1, round(startTime * data.SampleRate));
        endSample = min(length(data.audioSignal), round(endTime * data.SampleRate));
        audioClip = data.audioSignal(startSample:endSample, :); % Extract audio segment

        % Initialize vision.VideoFileWriter
        writer = vision.VideoFileWriter(outputFile, ...
            'FileFormat', 'AVI', ...
            'AudioInputPort', true, ...
            'FrameRate', data.FrameRate, ...
            'VideoCompressor', 'MJPEG Compressor');

        % Determine fixed audio size per frame
        numAudioSamplesPerFrame = ceil(data.SampleRate / data.FrameRate);
        fixedAudioFrameSize = [numAudioSamplesPerFrame, size(audioClip, 2)]; % [samples, channels]

        % Write video and audio frames
        for i = startFrame:endFrame
            frame = data.frameCache{i};

            % Extract corresponding audio samples for this frame
            audioStartIdx = (i - startFrame) * numAudioSamplesPerFrame + 1;
            audioEndIdx = audioStartIdx + numAudioSamplesPerFrame - 1;

            if audioEndIdx > size(audioClip, 1)
                % Pad with zeros if the audio segment is shorter
                audioFrame = zeros(fixedAudioFrameSize);
                audioFrame(1:(size(audioClip, 1) - audioStartIdx + 1), :) = ...
                    audioClip(audioStartIdx:end, :);
            else
                % Extract exact-sized audio segment
                audioFrame = audioClip(audioStartIdx:audioEndIdx, :);
            end

            % Write the video and audio frame
            step(writer, frame, audioFrame);
        end

        % Finalize the file
        release(writer);
        disp(['Clip saved with audio to: ', outputFile]);
    end

    function playSelection(hFig)
        % Check if audioLine and motionLine exist
        if ~isfield(data, 'audioLine') || ~isvalid(data.audioLine) || ...
                ~isfield(data, 'motionLine') || ~isvalid(data.motionLine)
            disp('Error: No valid selection to play.');
            return;
        end

        % Get selected time points
        audioX = data.audioLine.XData(1); % Time point from audio plot
        motionX = data.motionLine.XData(1); % Time point from motion plot
        startTime = min(audioX, motionX);
        endTime = max(audioX, motionX);

        % Calculate frame range
        startFrame = max(1, min(data.numFrames, floor(startTime * data.FrameRate)));
        endFrame = max(1, min(data.numFrames, ceil(endTime * data.FrameRate)));

        % Calculate audio sample range
        startSample = max(1, round(startTime * data.SampleRate));
        endSample = min(length(data.audioSignal), round(endTime * data.SampleRate));

        % Toggle playback state for the selection
        if ~isfield(data, 'isPlaying') || ~data.isPlaying
            % Adjust playback speed for audio
            data.audioPlayer.SampleRate=data.SampleRate*data.playbackSpeed;
            data.endFrame=endFrame;
            play(data.audioPlayer, [startSample, endSample]);
            data.isPlaying = true;
        else
            % Pause playback
            %data.isPlaying = false;
            pause(data.audioPlayer);
            data.isPlaying = false;
        end

    end


    function loadNewVideo(hFig)
        % Prompt user for a new video file
        [fileName, filePath] = uigetfile({'*.avi;*.mp4', 'Video Files (*.avi, *.mp4)'; '*.*', 'All Files (*.*)'}, ...
            'Select a Video File');
        if fileName == 0
            disp('No video file selected.');
            return;
        end
        newVideoFile = fullfile(filePath, fileName);
        disp(['Loading new video file: ', newVideoFile]);
        data=initialize(newVideoFile, hFig);

    end
end
