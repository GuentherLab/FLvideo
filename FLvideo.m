% MATLAB Script for video control with audio visualization and controls
% Must first convert the real-time MRI files from Gottingen to AVI files
% using the same codec as in the MP4 files ("copy" the codec when
% translating, e.g. using https://cloudconvert.com/mp4-to-avi
%
function FLvideo(videoFile)

    if nargin<1, videoFile = ''; end % Video file path
    
    data = initialize(videoFile); % initializes GUI (and data is videoFile is specified)

    mainLoop(); % Main loop for handling video playback

    function mainLoop(varargin)
        countidle=0;
        while ishandle(data.handles_hFig)&&countidle<32
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

                    timeAtCurrentFrame = (currentFrame+[-1 -1 0 0]) / data.FrameRate; % note: displays time at midpoint of frame
                    set(data.frameLine, 'XData', timeAtCurrentFrame, 'YData', data.audioYLim([1 2 2 1]));
                    set(data.motionFrameLine, 'XData', timeAtCurrentFrame, 'YData', data.motionYLim([1 2 2 1]));
                    countidle=0;
                    drawnow;
                else pause(0.001);
                end
            else
                pause(0.01);
                countidle=countidle+1;
            end
        end
    end


    % Callback Functions (NOTE: they all have access to the shared variable "data")
    function data = initialize(videoFile, hFig)
        data=[];
        frameCache={};
        isready='off';
        % Create the main figure for video, audio, and controls
        if nargin<2, 
            hFig = figure('units','norm','Position', [.25, .1, .5, .8], 'MenuBar', 'none', 'NumberTitle', 'off', 'Name', 'Video Player','color','w');
        end
        if ~isempty(videoFile), 
            try
                switch(regexprep(videoFile,'^.*\.',''))
                    case 'mat' % reads video file from .mat file
                        load(videoFile,'audio','video');
                        audioSignal=audio.data;
                        audioFs=audio.fs;
                        frameCache=video.data;
                        FrameRate=video.fs;
                        numFrames=numel(frameCache);
                        totalDuration=max(length(audioSignal)/audioFs, numFrames/FrameRate);

                    otherwise % reads video file
                        % Extract audio signal
                        [audioSignal, audioFs] = audioread(videoFile); % Read audio from the video
                        % Create a VideoReader object
                        v = VideoReader(videoFile);

                        % Check video properties
                        disp(['Duration: ', num2str(v.Duration), ' seconds (',num2str(v.numFrames), ' frames)']);
                        disp(['Video Frame Rate: ', num2str(v.FrameRate), ' fps']);
                        disp(['Video Resolution: ', num2str(v.Width), 'x', num2str(v.Height)]);
                        %disp(['Audio Format: ', v.AudioFormat]); % Audio information, if available

                        % Get total frames of video
                        numFrames = v.NumFrames; %floor(v.Duration * v.FrameRate); % NOTE: v.Duration is not an integer multiple of 1/FrameRate
                        FrameRate = v.FrameRate; %numFrames/v.Duration;

                        totalDuration = max(length(audioSignal)/audioFs, v.Duration);

                        % Preload frames into cache
                        %timeCache = [];
                        frameCache = cell(1, numFrames);
                        for i = 1:numFrames
                            frameCache{i} = read(v, i);
                            %timeCache(i)=v.CurrentTime;
                        end
                end
                isready='on';
            catch me
                errordlg([{'Problem reading video file:'} getReport(me,'basic','hyperlinks','off')], 'Video Player error');
                isready='off';
            end
        end
        if nargin>=2, 
            set(hFig, 'name', 'Video Player');
            clf(hFig);
        end
        % Create a panel for the control buttons
        data.handles_hFig = hFig;
        data.handles_buttonPanel = uipanel('Position', [0, 0, 1, 0.15], 'Parent', hFig); % Slightly shorter panel for two rows of buttons

        % Top row: Playback buttons
        uicontrol('Style', 'pushbutton', 'String', 'Play/Pause', 'Position', [20, 70, 100, 40], ...
            'Callback', @(src, event) togglePlayPause(src, event, hFig), 'Parent', data.handles_buttonPanel, 'enable',isready);

        uicontrol('Style', 'pushbutton', 'String', 'Next Frame', 'Position', [130, 70, 100, 40], ...
            'Callback', @(src, event) nextFrame(src, event, hFig), 'Parent', data.handles_buttonPanel, 'enable',isready);

        uicontrol('Style', 'pushbutton', 'String', 'Previous Frame', 'Position', [240, 70, 100, 40], ...
            'Callback', @(src, event) previousFrame(src, event, hFig), 'Parent', data.handles_buttonPanel, 'enable',isready);

        uicontrol('Style', 'pushbutton', 'String', 'Rewind', 'Position', [350, 70, 100, 40], ...
            'Callback', @(src, event) rewindVideo(src, event, hFig), 'Parent', data.handles_buttonPanel, 'enable',isready);

        uicontrol('Style', 'text', 'String', 'Playback Speed', 'Position', [470, 80, 100, 20], 'horizontalalignment','right', 'Parent', data.handles_buttonPanel);
        uicontrol('Style', 'slider', 'Min', 0.1, 'Max', 2, 'Value', 1, 'Position', [580, 80, 100, 20], ...
            'Callback', @(src, event) adjustPlaybackSpeed(src, event, hFig), 'Parent', data.handles_buttonPanel, 'enable',isready);

        uicontrol('Style', 'text', 'String', 'GUI layout', 'Position', [470, 50, 100, 20], 'horizontalalignment','right', 'Parent', data.handles_buttonPanel);
        data.handles_layout=uicontrol('Style', 'popupmenu', 'string', {'standard', 'maximized (horizontal layout)', 'maximized (vertical layout)'}, 'Value', 1, 'Position', [580, 50, 100, 20], ...
            'Callback', @(src, event) changeLayout(src, event, hFig), 'Parent', data.handles_buttonPanel, 'enable',isready);
        
        data.handles_zoom=uicontrol('Style', 'pushbutton', 'string', 'Zoom In/Out', 'value', 0, 'Position', [500, 20, 180, 20], ...
            'Callback', @(src, event) zoomIn, 'Parent', data.handles_buttonPanel, 'enable','off');
        
        % Bottom row: Selection and save controls
        uicontrol('Style', 'pushbutton', 'String', 'Select Points', 'Position', [20, 20, 100, 40], ...
            'Callback', @(src, event) selectPoints(hFig), 'Parent', data.handles_buttonPanel, 'enable',isready);

        data.handles_saveclipButton = uicontrol('Style', 'pushbutton', 'String', 'Save Clip', 'Position', [130, 20, 100, 40], ...
            'Callback', @(src, event) saveClip(hFig), 'Parent', data.handles_buttonPanel, 'enable','off');

        data.handles_playSelectionButton = uicontrol('Style', 'pushbutton', 'String', 'Play/Pause Selection', ...
            'Position', [240, 20, 120, 40], 'Enable', 'off', ...
            'Callback', @(src, event) playSelection(hFig), 'Parent', data.handles_buttonPanel);

        uicontrol('Style', 'pushbutton', 'String', 'Load New Video', 'Position', [360, 20, 120, 40], ...
            'Callback', @(src, event) loadNewVideo(hFig), 'Parent', data.handles_buttonPanel);
        
        if ~isempty(frameCache) % Displays video and audio data
            % Calculate global motion based on pixel differences
            globalMotion = zeros(1, numFrames - 1); % Preallocate for speed
            for i = 1:numFrames - 1
                frame1 = double(rgb2gray(frameCache{i})); % Convert frame to grayscale
                frame2 = double(rgb2gray(frameCache{i + 1})); % Convert next frame to grayscale
                globalMotion(i) = sum(abs(frame1(:) - frame2(:)).^2); % Compute sum of absolute differences (SAD)
            end
            %globalMotion = [globalMotion, globalMotion(end)]; % Match the length to numFrames

            % Create an axes for the video display
            data.handles_videoPanel = axes('Position', [0.1, 0.55, 0.8, 0.4], 'Parent', hFig); % Move video panel upward
            hVideo = imshow(frameCache{1}, 'Parent', data.handles_videoPanel); % Placeholder for video frame
            %disp(hVideo); % Display information about the hVideo object
            if isvalid(hVideo)
                disp('hvideo initialized'); % Verify if hVideo is valid after initialization
            end
            axis(data.handles_videoPanel, 'off'); % Hide axis lines and labels
            title(data.handles_videoPanel, 'Video Playback', 'Color', 'w');

            % Create a dedicated axes for the audio signal
            data.handles_audioPanel = axes('Position', [0.1, 0.4, 0.8, 0.1], 'Parent', hFig); % Move audio panel upward
            audioPlot = plot((0:length(audioSignal)-1)/audioFs, audioSignal, 'b', 'Parent', data.handles_audioPanel); % Plot full audio signal
            hold(data.handles_audioPanel, 'on');
            frameLine = patch(data.handles_audioPanel, [0 0 0 0], [0 0 0 0], 'r', 'edgecolor', 'none', 'facealpha', .5); % Red line for current frame
            xlim(data.handles_audioPanel, [0 totalDuration]); % Set x-axis limits based on audio duration
            audioYLim = [-1, 1]*1.1*max(abs(audioSignal(:))); % Get the correct y-limits for the audio signal
            ylim(data.handles_audioPanel, audioYLim); % Apply y-limits for the audio plot
            %xlabel(data.handles_audioPanel, 'Time (s)');
            ylabel(data.handles_audioPanel, 'Audio Signal Intensity');
            title(data.handles_audioPanel, 'Audio Signal with Current Frame');
            hold(data.handles_audioPanel, 'off');
            set(data.handles_audioPanel, 'xcolor', .5*[1 1 1], 'ycolor', .5*[1 1 1], 'xticklabel',[]);
            set([data.handles_audioPanel; audioPlot(:)],'buttondownfcn',@(varargin)thisFrame);

            % Create a dedicated axes for the global motion
            data.handles_motionPanel = axes('Position', [0.1, 0.25, 0.8, 0.1], 'Parent', hFig); % Move motion panel upward
            motionPlot = plot(data.handles_motionPanel, (1:numFrames-1)/FrameRate, globalMotion, 'g'); % Plot global motion
            hold(data.handles_motionPanel, 'on');
            motionFrameLine = patch(data.handles_motionPanel, [0 0 0 0], [0 0 0 0], 'r', 'edgecolor', 'none', 'facealpha', .5); % Red line for current frame
            xlim(data.handles_motionPanel, [0 totalDuration]); % Set x-axis limits based on video duration
            motionYLim = [0 1.1*max(globalMotion)]; % Calculate y-limits for the global motion
            ylim(data.handles_motionPanel, motionYLim); % Apply y-limits for the motion plot
            xlabel(data.handles_motionPanel, 'Time (s)');
            ylabel(data.handles_motionPanel, 'Motion Intensity');
            title(data.handles_motionPanel, 'Global Motion Across Frames');
            hold(data.handles_motionPanel, 'off');
            set(data.handles_motionPanel, 'xcolor', .5*[1 1 1], 'ycolor', .5*[1 1 1]);
            set([data.handles_motionPanel; motionPlot(:)],'buttondownfcn',@(varargin)thisFrame);

            % Store information in shared "data" variable
            data.isPlaying = false;
            data.currentFrame = 1; % Start at the first frame
            data.endFrame = 0;
            data.numFrames = numFrames;
            data.FrameRate = FrameRate;
            data.audioSignal = audioSignal;
            data.SampleRate = audioFs;
            data.totalDuration=totalDuration;
            data.SampleQueue = 0;
            data.hVideo = hVideo;
            data.frameCache = frameCache;
            data.frameLine = frameLine;
            data.motionFrameLine = motionFrameLine;
            data.audioYLim = audioYLim;
            data.motionYLim = motionYLim;
            data.zoomin = false;
            data.playbackSpeed = 1; % Default playback speed
            data.audioPlayer = audioplayer(audioSignal, audioFs); % Create audioplayer object

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
            zoomIn(false);
            play(data.audioPlayer, [startSample, length(data.audioSignal)]);
            if data.SampleQueue==0, data.SampleQueue=data.audioPlayer.CurrentSample-startSample; disp(data.SampleQueue); end
            mainLoop();
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
                timeAtCurrentFrame = (currentFrameIndex+[-1 -1 0 0]) / data.FrameRate;
                set(data.frameLine, 'XData', timeAtCurrentFrame, 'YData', data.audioYLim([1 2 2 1]));
                set(data.motionFrameLine, 'XData', timeAtCurrentFrame, ...
                    'YData', data.motionYLim([1 2 2 1]));

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
                timeAtCurrentFrame = (currentFrameIndex+[-1 -1 0 0]) / data.FrameRate;
                set(data.frameLine, 'XData', timeAtCurrentFrame, 'YData', data.audioYLim([1 2 2 1]));
                set(data.motionFrameLine, 'XData', timeAtCurrentFrame, ...
                    'YData', data.motionYLim([1 2 2 1]));
                drawnow;
            end
        end
    end

    function thisFrame(thisTime)
        if nargin<1||isempty(thisTime), thisTime=get(gca,'currentpoint'); end
        if ~data.isPlaying,
            data.currentFrame = max(1, min(data.numFrames, ceil(thisTime(1) * data.FrameRate)));
            currentFrameIndex = round(data.currentFrame);
            frame = data.frameCache{currentFrameIndex};
            set(data.hVideo, 'CData', frame);
            timeAtCurrentFrame = (currentFrameIndex+[-1 -1 0 0]) / data.FrameRate;
            set(data.frameLine, 'XData', timeAtCurrentFrame, 'YData', data.audioYLim([1 2 2 1]));
            set(data.motionFrameLine, 'XData', timeAtCurrentFrame, ...
                'YData', data.motionYLim([1 2 2 1]));
            drawnow;
        end
    end

    function rewindVideo(~, ~, hFig)
        if ~data.isPlaying,
            data.currentFrame = 1;
            currentFrameIndex = round(data.currentFrame);
            frame = data.frameCache{currentFrameIndex};
            set(data.hVideo, 'CData', frame);
            timeAtCurrentFrame = (currentFrameIndex+[-1 -1 0 0]) / data.FrameRate;
            set(data.frameLine, 'XData', timeAtCurrentFrame, 'YData', data.audioYLim([1 2 2 1]));
            set(data.motionFrameLine, 'XData', timeAtCurrentFrame, ...
                'YData', data.motionYLim([1 2 2 1]));
            zoomIn(false);
            drawnow;
        end
    end

    function adjustPlaybackSpeed(slider, ~, hFig)
        if data.isPlaying, slider.Value=data.playbackSpeed;
        else data.playbackSpeed = slider.Value;
        end
    end

    function zoomIn(state)
        if nargin<1, data.zoomin=~data.zoomin;
        else data.zoomin=state;
        end
        switch(data.zoomin)
            case 1, % zoom in
                startTime = min(data.audioLine.XData(1), data.motionLine.XData(1));
                endTime = max(data.audioLine.XData(1), data.motionLine.XData(1));
                xlim([data.handles_audioPanel,data.handles_motionPanel], [max(0,startTime-.1*(endTime-startTime)) min(data.totalDuration,endTime+.1*(endTime-startTime))]); 
            case 0, % zoom out
                xlim([data.handles_audioPanel, data.handles_motionPanel], [0 data.totalDuration]); 
        end
    end

    function changeLayout(~, ~, hFig)
        switch(get(data.handles_layout,'value'))
            case 1, % standard layout
                set(data.handles_hFig,'Position',[.25, .1, .5, .8]);
                set(data.handles_videoPanel,'Position', [0.0, 0.55, 1, 0.4]);
                set(data.handles_audioPanel,'Position', [0.1, 0.4, 0.8, 0.1]);
                set(data.handles_motionPanel, 'Position', [0.1, 0.25, 0.8, 0.1]);
                set(data.handles_buttonPanel, 'Position', [0, 0, 1, 0.15]);
                drawnow;
            case 2, % maximized (horizontal layout)
                set(data.handles_hFig,'Position',[0.01, 0, .98, .975]);
                set(data.handles_videoPanel,'Position', [0.0, 0.0, 0.55, 1]);
                set(data.handles_audioPanel,'Position', [0.575, 0.65, 0.4, 0.25]);
                set(data.handles_motionPanel, 'Position', [0.575, 0.275, 0.4, 0.25]);
                set(data.handles_buttonPanel, 'Position', [0.575, 0.025, 0.4, 0.15]);
                drawnow;
            case 3, % maximized (vertical layout)
                set(data.handles_hFig,'Position',[.01, 0, .98, .975]);
                set(data.handles_videoPanel,'Position', [0.0, 0.4, 1, 0.6]);
                set(data.handles_audioPanel,'Position', [0.1, 0.275, 0.8, 0.075]);
                set(data.handles_motionPanel, 'Position', [0.1, 0.175, 0.8, 0.075]);
                set(data.handles_buttonPanel, 'Position', [0, 0, 1, 0.15]);
                drawnow;
                % set(data.handles_videoPanel,'Position', [0.0, 0.15, 0.45, 0.85]);
                % set(data.handles_audioPanel,'Position', [0.50, 0.325, 0.20, 0.5]);
                % set(data.handles_motionPanel, 'Position', [0.75, 0.325, 0.20, 0.5]);
                % set(data.handles_buttonPanel, 'Position', [0, 0, 1, 0.15]);
                % set(data.handles_hFig,'Position',[0, 0, 1, 1]);
        end
    end

    function selectPoints(hFig)
        % Retrieve current state

        % Save the current axis limits
        currentAudioXLim = xlim(data.handles_audioPanel);
        currentMotionXLim = xlim(data.handles_motionPanel);
        currentAudioYLim = data.audioYLim;
        currentMotionYLim = data.motionYLim;

        % Hold the current plots to preserve existing data
        hold(data.handles_audioPanel, 'on');
        hold(data.handles_motionPanel, 'on');

        % Display instructions
        disp('Select a point on the audio plot');
        [audioX, ~] = ginput(1); % Select first point on the audio plot

        % Add a temporary vertical line for the selected audio point
        tempAudioLine = line(data.handles_audioPanel, [audioX, audioX], currentAudioYLim, ...
            'Color', 'blue', 'LineStyle', '--');
        disp('Select a point on the motion plot');
        [motionX, ~] = ginput(1); % Select second point on the motion plot

        % Add a temporary vertical line for the selected motion point
        tempMotionLine = line(data.handles_motionPanel, [motionX, motionX], currentMotionYLim, ...
            'Color', 'blue', 'LineStyle', '--');

        % Determine the selected range
        startTime = min(audioX, motionX);
        endTime = max(audioX, motionX);

        % Add shading to indicate the selected range
        tempAudioShading = fill(data.handles_audioPanel, ...
            [startTime, endTime, endTime, startTime], ...
            [currentAudioYLim(1), currentAudioYLim(1), currentAudioYLim(2), currentAudioYLim(2)], ...
            'blue', 'FaceAlpha', 0.2, 'EdgeColor', 'none');
        tempMotionShading = fill(data.handles_motionPanel, ...
            [startTime, endTime, endTime, startTime], ...
            [currentMotionYLim(1), currentMotionYLim(1), currentMotionYLim(2), currentMotionYLim(2)], ...
            'blue', 'FaceAlpha', 0.2, 'EdgeColor', 'none');
        set([tempAudioShading, tempMotionShading],'buttondownfcn',@(varargin)thisFrame);

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

        % enable selection-related buttons
        if isfield(data, 'handles_playSelectionButton') && isvalid(data.handles_playSelectionButton), set(data.handles_playSelectionButton, 'Enable', 'on'); end
        if isfield(data, 'handles_saveclipButton') && isvalid(data.handles_saveclipButton), set(data.handles_saveclipButton, 'Enable', 'on'); end
        if isfield(data, 'handles_zoom') && isvalid(data.handles_zoom), set(data.handles_zoom, 'Enable', 'on'); end        

        % Restore the original axis limits
        xlim(data.handles_audioPanel, currentAudioXLim);
        ylim(data.handles_audioPanel, currentAudioYLim);
        xlim(data.handles_motionPanel, currentMotionXLim);
        ylim(data.handles_motionPanel, currentMotionYLim);

        % Release hold on the plots
        hold(data.handles_audioPanel, 'off');
        hold(data.handles_motionPanel, 'off');

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
        % Calculate frame range
        startFrame = max(1, min(data.numFrames, 1+floor(startTime * data.FrameRate)));
        endFrame = max(1, min(data.numFrames, 1+floor(endTime * data.FrameRate)));
        disp(['Saving clip from ', num2str(startTime), ' to ', num2str(endTime), ' seconds (', num2str(endFrame-startFrame+1),' frames)']);

        % Calculate audio sample range
        startSample = max(1, round((startFrame-1)/data.FrameRate * data.SampleRate));
        endSample = min(length(data.audioSignal), round((endFrame+1)/data.FrameRate* data.SampleRate-1));
        audioClip = data.audioSignal(startSample:endSample, :); % Extract audio segment

        % Prompt user for output file name
        [fileName, filePath] = uiputfile({'*.mat', 'Matlb Video File (*.mat)'; '*.mp4', 'MP4 Video File (*.mp4)'; '*.avi', 'AVI Video File (*.avi)'; '*', 'All Files (*.*)'}, 'Save Video Clip As');
        if fileName == 0
            disp('Saving cancelled.');
            return;
        end
        outputFile = fullfile(filePath, fileName);

        switch(regexprep(fileName,'^.*\.',''))
            case 'mp4'
                if ismac&&~isempty(dir('/Applications/VLC.app')), 
                    saveaudio=true; 
                    tempfile='VidTest_temporalfile_video.mp4';
                else 
                    saveaudio=false; 
                    tempfile=outputFile;
                end
                % Write video
                writer = VideoWriter(tempfile,'MPEG-4');
                writer.FrameRate=data.FrameRate;
                open(writer);
                for i = startFrame:endFrame
                    frame = data.frameCache{i};
                    if rem(size(frame,1),8), frame=cat(1,frame,frame(end+zeros(1,8-rem(size(frame,1),8)),:,:)); end
                    if rem(size(frame,2),8), frame=cat(2,frame,frame(:,end+zeros(1,8-rem(size(frame,1),8)),:)); end
                    writeVideo(writer, frame);
                end
                close(writer);
                if saveaudio
                    % Write separate audio track and merge
                    audiowrite('VidTest_temporalfile_audio.mp4', audioClip, data.SampleRate);
                    [ok,msg]=system(sprintf('/Applications/VLC.app/Contents/MacOS/VLC -I dummy ''%s'' --input-slave=%s --sout "#gather:std{access=file,mux=mp4,dst=%s}" vlc://quit', fullfile(pwd,'VidTest_temporalfile_video.mp4'),fullfile(pwd,'/VidTest_temporalfile_audio.mp4'), outputFile))
                end

            case 'avi'
                if ~ismac&&~isempty(which('vision.VideoFileWriter')) % saves video and audio to avi using Vision Toolbox
                    % Initialize vision.VideoFileWriter
                    writer = vision.VideoFileWriter(outputFile, ...
                        'FileFormat', 'AVI', ...
                        'AudioInputPort', true, ...
                        'FrameRate', data.FrameRate, ...
                        'VideoCompressor', 'MJPEG Compressor');
                    numAudioSamplesPerFrame = ceil(data.SampleRate / data.FrameRate); % Determine fixed audio size per frame
                    fixedAudioFrameSize = [numAudioSamplesPerFrame, size(audioClip, 2)]; % [samples, channels]
                    for i = startFrame:endFrame % Write video and audio frames
                        frame = data.frameCache{i};
                        audioStartIdx = (i - startFrame) * numAudioSamplesPerFrame + 1; % Extract corresponding audio samples for this frame
                        audioEndIdx = audioStartIdx + numAudioSamplesPerFrame - 1;
                        if audioEndIdx > size(audioClip, 1) % Pad with zeros if the audio segment is shorter
                            audioFrame = zeros(fixedAudioFrameSize);
                            audioFrame(1:(size(audioClip, 1) - audioStartIdx + 1), :) = ...
                                audioClip(audioStartIdx:end, :);
                        else
                            audioFrame = audioClip(audioStartIdx:audioEndIdx, :); % Extract exact-sized audio segment
                        end
                        step(writer, frame, audioFrame); % Write the video and audio frame
                    end
                    release(writer);
                else % saves only video
                    writer = VideoWriter(outputFile,'MPEG-4');
                    writer.FrameRate=data.FrameRate;
                    open(writer);
                    for i = startFrame:endFrame
                        frame = data.frameCache{i};
                        if rem(size(frame,1),8), frame=cat(1,frame,frame(end+zeros(1,8-rem(size(frame,1),8)),:,:)); end
                        if rem(size(frame,2),8), frame=cat(2,frame,frame(:,end+zeros(1,8-rem(size(frame,1),8)),:)); end
                        writeVideo(writer, frame);
                    end
                    close(writer);
                end

            case 'mat'
                video = struct('data',{data.frameCache(startFrame:endFrame)},'fs',data.FrameRate);
                audio = struct('data',audioClip,'fs',data.SampleRate);
                save(outputFile, 'video','audio');
        end
        disp(['Clip saved to: ', outputFile]);
    end

    function playSelection(hFig)
        % Check if audioLine and motionLine exist
        if ~isfield(data, 'audioLine') || ~isvalid(data.audioLine) || ...
                ~isfield(data, 'motionLine') || ~isvalid(data.motionLine)
            disp('Error: No valid selection to play.');
            return;
        end

        % Toggle playback state for the selection
        if ~isfield(data, 'isPlaying') || ~data.isPlaying
            % Get selected time points
            audioX = data.audioLine.XData(1); % Time point from audio plot
            motionX = data.motionLine.XData(1); % Time point from motion plot
            startTime = min(audioX, motionX);
            endTime = max(audioX, motionX);

            % Calculate frame range
            startFrame = max(1, min(data.numFrames, 1+floor(startTime * data.FrameRate)));
            endFrame = max(1, min(data.numFrames, 1+floor(endTime * data.FrameRate)));

            % Calculate audio sample range
            startSample = max(1, round(startTime * data.SampleRate));
            endSample = min(length(data.audioSignal), round(endTime * data.SampleRate));

            % Adjust playback speed for audio
            data.audioPlayer.SampleRate=data.SampleRate*data.playbackSpeed;
            data.endFrame=endFrame;
            play(data.audioPlayer, [startSample, endSample]);
            data.isPlaying = true;
            mainLoop();
        else
            % Pause playback
            pause(data.audioPlayer);
            data.isPlaying = false;
        end

    end


    function loadNewVideo(hFig)
        % Prompt user for a new video file
        [fileName, filePath] = uigetfile({ '*', 'All Files (*.*)'; '*.avi;*.mp4;*.mat', 'Video Files (*.avi, *.mp4; *.mat)'}, ...
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
