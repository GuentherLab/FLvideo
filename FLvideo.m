% MATLAB Script for video control with audio visualization and controls
% Must first convert the real-time MRI files from Gottingen to AVI files
% using the same codec as in the MP4 files ("copy" the codec when
% translating, e.g. using https://cloudconvert.com/mp4-to-avi
%
% To save mp4 files ffmpeg (https://www.ffmpeg.org) must be installed
% (see https://phoenixnap.com/kb/ffmpeg-windows for instructions on Windows)
% or VLC (https://www.videolan.org/vlc/)
%

function FLvideo(videoFile)

    if nargin<1, videoFile = ''; end % Video file path
    
    data = initialize(videoFile); % initializes GUI (and data if videoFile is specified)

    % Callback Functions (NOTE: they all have access to the shared variable "data")

    % function handling real-time update of audio&video display
    function mainLoop(varargin)
        countidle=0;
        while ishandle(data.handles_hFig)&&countidle<32
            % Retrieve the latest state
            if isfield(data,'isPlaying')&&data.isPlaying
                % Update frame index
                currentFrame = ceil(max(1,data.audioPlayer.CurrentSample-data.SampleQueue)/data.SampleRate*data.FrameRate);
                if data.currentFrame~=currentFrame,
                    if (currentFrame==1&&data.currentFrame>1) || currentFrame >= data.endFrame % if audio is stopped (but not paused)
                        currentFrame = data.endFrame; 
                        set(data.handles_play, 'cdata', data.handles_icons{1});
                        data.isPlaying = false; % Stop playback
                    end

                    % Update video and lines
                    % Update video frame
                    data.currentFrame=currentFrame ;
                    frame = getframeCache(currentFrame);
                    set(data.hVideo, 'CData', frame); % Update video frame

                    timeAtCurrentFrame = (currentFrame+[-1 -1 0 0]) / data.FrameRate; % note: displays time at midpoint of frame
                    set(data.handles_audioFrameLine, 'XData', timeAtCurrentFrame, 'YData', data.audioYLim([1 2 2 1]));
                    set(data.handles_otherFrameLine1, 'XData', timeAtCurrentFrame, 'YData', data.otherYLim([1 2 2 1]));
                    set(data.handles_otherFrameLine2, 'XData', timeAtCurrentFrame, 'YData', data.otherYLim([1 2 2 1]));
                    set(data.handles_audioFrameText, 'string', sprintf(' t = %.3f s',mean(timeAtCurrentFrame)), 'position', [timeAtCurrentFrame(end), data.audioYLim*[0;1]]);
                    data.handles_audioFrameText_extent=[];
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


    % function handling initialization of audio&video display
    function varargout = initialize(videoFile, hFig)
        isready='off';
        NewData=false;
        ComputeDerivedMeasures=false;
        selectspeed=5;
        layout=1;
        motionHighlight=1;
        audioFrameText={'',[0,0]};
        audioShadingText1={'',[0,0]};
        audioShadingText2={'',[0,0]};
        audioShadingText3={'',[0,0]};
        audioSignalSelect=1;
        nplots=1;
        plotMeasure=[];
        cmapselect=1;
        zoomWindow=[];
        zoomin=false;
        isselected='off';
        % Create the main figure for video, audio, and controls
        if nargin<2, 
            hFig = figure('units','norm','Position', [.25, .1, .5, .8], 'MenuBar', 'none', 'NumberTitle', 'off', 'Name', 'Video Player','color','w', 'WindowButtonDownFcn', @(varargin)flvideo_buttonfcn('down',varargin{:}),'WindowButtonUpFcn',@(varargin)flvideo_buttonfcn('up',varargin{:}),'WindowButtonMotionFcn',@(varargin)flvideo_buttonfcn('motion',varargin{:}));
        else
            try selectspeed=get(data.handles_playbackspeed,'value'); end
            try, layout=get(data.handles_layout,'value'); end
            try, motionHighlight=get(data.handles_motionhighlight,'value'); end
            try, audioSignalSelect=get(data.handles_audiosignal,'value'); end
            try, nplots=numel(data.plotMeasure); end
            try, plotMeasure=get(data.handles_plotmeasure,'value'); end
            try, cmapselect=get(data.handles_colormap,'value'); end
        end
        if iscell(plotMeasure), plotMeasure=[plotMeasure{:}]; end
        if isequal(videoFile,0) % note: keep current file data
            audioSignal=data.audioSignalRaw;
            audioSignalDenoised=data.audioSignalDen;
            audioFs=data.SampleRate;
            frameCache=data.frameCache;
            FrameRate=data.FrameRate;
            numFrames=data.numFrames;
            totalDuration=data.totalDuration;
            NewData=true;
            ComputeDerivedMeasures=false;
            zoomWindow=data.zoomWindow;
            zoomin=data.zoomin;
            if ~isempty(zoomWindow), isselected='on'; end
            audioFrameText=get(data.handles_audioFrameText,{'string','position'});
            audioShadingText1=get(data.handles_audioShadingText1,{'string','position'});
            audioShadingText2=get(data.handles_audioShadingText2,{'string','position'});
            audioShadingText3=get(data.handles_audioShadingText3,{'string','position'});
            isready='on';
            videoFile='';
        else         
            data=[];
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
                        audioSignal=audioSignal(:,1); % mono audio track
                        % Create a VideoReader object
                        v = VideoReader(videoFile);

                        % Check video properties
                        disp(['Duration: ', num2str(v.Duration), ' seconds (',num2str(v.numFrames), ' frames)']);
                        disp(['Video Frame Rate: ', num2str(v.FrameRate), ' fps']);
                        disp(['Video Resolution: ', num2str(v.Width), 'x', num2str(v.Height)]);
                        disp(['Audio Sample Rate: ', num2str(audioFs)]);
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
                audioSignalDenoised = filterMRINoise(audioSignal, audioFs);
                NewData=true;
                ComputeDerivedMeasures=true;
                set(hFig, 'name', sprintf('Video Player : %s',videoFile));
            catch me
                errordlg([{'Problem reading video file:'} getReport(me,'basic','hyperlinks','off')], 'Video Player error');
                isready='off';
            end
        end
        if nargin>=2, 
            %set(hFig, 'name', 'Video Player');
            clf(hFig);
        end
        % Create a panel for the control buttons
        data.handles_hFig = hFig;
        data.handles_buttonPanel = uipanel('Position', [0, 0, 1, 0.15], 'Parent', hFig); % Slightly shorter panel for two rows of buttons

        % Top row: Playback buttons
        uicontrol('Style', 'pushbutton', 'String', 'Load New Video', 'Position', [20, 70, 210, 40], ...
            'Callback', @(src, event) loadNewVideo(hFig), 'Parent', data.handles_buttonPanel);
        
        temp=imread(fullfile(fileparts(which(mfilename)),'icons','icon_rest.png')); temp=repmat(squeeze(mean(mean(reshape(double(temp)/255,16,32,16,32),1),3)),[1,1,3]); temp(temp==1)=nan;
        uicontrol('Style', 'pushbutton', 'tooltip', 'Rewind', 'Position', [270, 70, 40, 40], 'cdata', temp, ...
            'Callback', @(src, event) rewindVideo(src, event, hFig), 'Parent', data.handles_buttonPanel);

        temp=imread(fullfile(fileparts(which(mfilename)),'icons','icon_back.png')); temp=repmat(squeeze(mean(mean(reshape(double(temp)/255,16,32,16,32),1),3)),[1,1,3]); temp(temp==1)=nan;
        uicontrol('Style', 'pushbutton', 'tooltip', 'Previous Frame', 'Position', [310, 70, 40, 40], 'cdata', temp, ...
            'Callback', @(src, event) previousFrame(src, event, hFig), 'Parent', data.handles_buttonPanel);

        temp=imread(fullfile(fileparts(which(mfilename)),'icons','icon_play.png')); temp=repmat(squeeze(mean(mean(reshape(double(temp)/255,16,32,16,32),1),3)),[1,1,3]); temp(temp==1)=nan; 
        data.handles_icons{1}=temp; 
        data.handles_play=uicontrol('Style', 'pushbutton', 'tooltip', 'Play/Pause', 'Position', [350, 70, 40, 40], 'cdata', temp, ...
            'Callback', @(src, event) togglePlayPause(src, event, hFig), 'Parent', data.handles_buttonPanel);
        temp=imread(fullfile(fileparts(which(mfilename)),'icons','icon_paus.png')); temp=repmat(squeeze(mean(mean(reshape(double(temp)/255,16,32,16,32),1),3)),[1,1,3]); temp(temp==1)=nan; 
        data.handles_icons{2}=temp;

        temp=imread(fullfile(fileparts(which(mfilename)),'icons','icon_forw.png')); temp=repmat(squeeze(mean(mean(reshape(double(temp)/255,16,32,16,32),1),3)),[1,1,3]); temp(temp==1)=nan;
        uicontrol('Style', 'pushbutton', 'tooltip', 'Next Frame', 'Position', [390, 70, 40, 40], 'cdata', temp, ...
            'Callback', @(src, event) nextFrame(src, event, hFig), 'Parent', data.handles_buttonPanel);

        uicontrol('Style', 'text', 'String', 'Playback Speed', 'Position', [490, 89, 100, 20], 'horizontalalignment','right', 'Parent', data.handles_buttonPanel);
        data.handles_playbackspeed=uicontrol('Style', 'popupmenu', 'Value', 5, 'string', {'0.1x', '0.25x', '0.5x', '0.75x', '1x', '1.25x', '1.5x', '2x', '5x'}, 'value', selectspeed, 'Position', [600, 89, 130, 20], ...
            'Callback', @(src, event) adjustPlaybackSpeed(src, event, hFig), 'Parent', data.handles_buttonPanel);

        uicontrol('Style', 'text', 'String', 'GUI layout', 'Position', [490, 66, 100, 20], 'horizontalalignment','right', 'Parent', data.handles_buttonPanel);
        data.handles_layout=uicontrol('Style', 'popupmenu', 'string', {'standard', 'maximized (horizontal layout)', 'maximized (vertical layout)'}, 'Value', layout, 'Position', [600, 66, 130, 20], ...
            'Callback', @(src, event) changeLayout, 'Parent', data.handles_buttonPanel);
        
        uicontrol('Style', 'text', 'String', 'Colormap', 'Position', [490, 43, 100, 20], 'horizontalalignment','right', 'Parent', data.handles_buttonPanel);
        data.handles_colormap=uicontrol('Style', 'popupmenu', 'string', {'gray', 'jet', 'parula','hot','sky','bone','copper'}, 'Value', cmapselect, 'Position', [600, 43, 130, 20], ...
            'Callback', @(src, event) changeColormap(src, event, hFig), 'Parent', data.handles_buttonPanel);
        
        uicontrol('Style', 'text', 'String', 'Highlight Motion', 'Position', [490, 20, 100, 20], 'horizontalalignment','right', 'Parent', data.handles_buttonPanel);
        data.handles_motionhighlight=uicontrol('Style', 'popupmenu', 'string', {'off', 'on'}, 'Value', motionHighlight, 'tooltip','Highlights in red areas in the video with high motion velocity (or acceleration when displaying motion acceleration)', 'Position', [600, 20, 130, 20], ...
            'Callback', @(src, event) changeMotionHighlight(src, event, hFig), 'Parent', data.handles_buttonPanel);
        
        % Bottom row: Selection and save controls
        uicontrol('Style', 'pushbutton', 'String', 'Select Window', 'tooltip','<HTML>Select a window between two timepoints<br/>Alternatively, click-and-drag in any of the plot displays to select a window</HTML>', 'Position', [20, 20, 210, 40], 'foregroundcolor','b', ...
            'Callback', @(src, event) selectPoints(hFig), 'Parent', data.handles_buttonPanel, 'enable',isready);

        temp=imread(fullfile(fileparts(which(mfilename)),'icons','icon_save.png')); temp=repmat(squeeze(mean(mean(reshape(double(temp)/255,20,32,20,32),1),3)),[1,1,3]); temp(temp==1)=nan; temp(:,:,3)=1;
        data.handles_saveclipButton = uicontrol('Style', 'pushbutton', 'tooltip', 'Save Clip with video within selected window', 'Position', [310, 20, 40, 40], 'cdata', temp, ...
            'Callback', @(src, event) saveClip(hFig), 'Parent', data.handles_buttonPanel, 'enable',isselected);

        temp=imread(fullfile(fileparts(which(mfilename)),'icons','icon_play.png')); temp=repmat(squeeze(mean(mean(reshape(double(temp)/255,16,32,16,32),1),3)),[1,1,3]); temp(temp==1)=nan; temp(:,:,3)=1;
        data.handles_playSelectionButton = uicontrol('Style', 'pushbutton', 'tooltip', 'Play/Pause video within selected window', 'cdata', temp, ...
            'Position', [350, 20, 40, 40], 'Enable', isselected, ...
            'Callback', @(src, event) playSelection(hFig), 'Parent', data.handles_buttonPanel);

        temp=imread(fullfile(fileparts(which(mfilename)),'icons','icon_zoom.png')); temp=repmat(squeeze(mean(mean(reshape(double(temp)/255,20,32,20,32),1),3)),[1,1,3]); temp(temp==1)=nan; temp(:,:,3)=1;
        data.handles_zoom=uicontrol('Style', 'pushbutton', 'tooltip', 'Zoom In/Out of selected window', 'Position', [390, 20, 40, 40], 'cdata', temp, ...
            'Callback', @(src, event) zoomIn, 'Parent', data.handles_buttonPanel, 'enable',isselected);
        
        if NewData, % Displays video and audio data
            if ComputeDerivedMeasures
                % Calculate global motion based on pixel differences
                globalMotionVel = zeros(1, numFrames - 1); % Preallocate for speed
                globalMotionAcc = globalMotionVel;
                frameMotionVel={};
                frameMotionAcc={};
                maxframeMotion=0;
                maxframeMotion2=0;
                for i = 1:numFrames - 1
                    frame1 = double(rgb2gray(frameCache{i})); % Convert frame to grayscale
                    frame2 = double(rgb2gray(frameCache{i + 1})); % Convert next frame to grayscale
                    frameMotionVel{i}=abs(frame1 - frame2).^2;
                    maxframeMotion=max(maxframeMotion,max(frameMotionVel{i}(:)));
                    globalMotionVel(i) = mean(frameMotionVel{i}(:)); % Compute mean of absolute values squared (MS)

                    if i>1, frame0 = double(rgb2gray(frameCache{i-1})); else frame0 = frame1; end
                    if i<numFrames-1, frame3 = double(rgb2gray(frameCache{i+2})); else frame3 = frame2; end
                    frameMotionAcc{i}=abs( (frame0 - frame1 - frame2 + frame3)/2 ).^2;
                    maxframeMotion2=max(maxframeMotion2,max(frameMotionAcc{i}(:)));
                    globalMotionAcc(i) = mean(frameMotionAcc{i}(:)); % Compute mean of absolute values squared (MS)
                end
                frameMotionVel=cellfun(@(x)x/maxframeMotion,frameMotionVel,'uni',0);
                frameMotionAcc=cellfun(@(x)x/maxframeMotion2,frameMotionAcc,'uni',0);
                globalMotionVel=interpft(globalMotionVel,length(audioSignal)); % resample to audio sampling rate (NOTE: sinc interpolation)
                globalMotionAcc=interpft(globalMotionAcc,length(audioSignal));
                dataspectrogram=[];
                dataharmonicRatio=[];
                %globalMotionVel = [globalMotionVel, globalMotionVel(end)]; % Match the length to numFrames
            else
                globalMotionVel=data.globalMotionVel;
                globalMotionAcc=data.globalMotionAcc;
                frameMotionVel=data.frameMotionVel;
                frameMotionAcc=data.frameMotionAcc;
                dataspectrogram=data.spectrogram;
                dataharmonicRatio=data.harmonicRatio;
            end
            audioYLim = [-1, 1]*1.1*max(max(abs(audioSignalDenoised(:))),max(abs(audioSignal(:)))); % Get the correct y-limits for the audio signal
            otherYLim = [0 1.1*max(globalMotionVel)]; % Calculate y-limits for the global motion velocity
            otherYLim2 = [0 1.1*max(globalMotionAcc)]; % Calculate y-limits for the global motion acceleration
            otherYLim3 = [0 8000];
            otherYLim = [min([otherYLim(1), otherYLim2(1), otherYLim3(1)]), max([otherYLim(2), otherYLim2(2), otherYLim3(2)])];

            % Create an axes for the video display
            data.handles_videoPanel = axes('Position', [0.1, 0.55, 0.8, 0.4], 'Parent', hFig); % Move video panel upward
            hVideo = imshow(frameCache{1}, 'Parent', data.handles_videoPanel); % Placeholder for video frame
            %disp(hVideo); % Display information about the hVideo object
            axis(data.handles_videoPanel, 'off'); % Hide axis lines and labels
            title(data.handles_videoPanel, 'Video Playback', 'Color', 'w');

            [data.handles_plotmeasure, data.handles_otherPanel1,data.handles_otherPlot1,data.handles_otherPointerLine1,data.handles_otherFrameLine1,data.handles_otherShading1,data.handles_otherPanel2,data.handles_otherPlot2,data.handles_otherPointerLine2,data.handles_otherFrameLine2,data.handles_otherShading2]=deal([]);
            for nplot=1:nplots
                if numel(plotMeasure)<nplot, 
                    newMeasure=1;
                    try, newMeasure=find(~ismember(1:numel(get(data.handles_plotmeasure(1),'string')), plotMeasure),1); end
                    plotMeasure(nplot)=max([1 newMeasure]);
                end
                % Create a dedicated axes for all other plots (for timeseries displays); related handles = data.handles_otherPanel1/2, data.handles_otherPlot1/2, data.handles_otherShading1/2, data.handles_plotmeasure
                data.handles_otherPanel1(nplot) = axes('Position', [1 nplot]*[0.1, 0.5-0.30/(1+nplots*1.5), 0.8, 0.30/(1+nplots*1.5); 0 -0.30*1.5/(1+nplots*1.5) 0 0], 'Parent', hFig);
                data.handles_otherPlot1(nplot) = plot((1:numFrames-1)/FrameRate, zeros(1,numFrames-1), 'g','parent',data.handles_otherPanel1(nplot));
                data.handles_otherPointerLine1(nplot) = patch([0 0 0 0], [0 0 0 0], 'k', 'edgecolor', 'k', 'facecolor', 'none','linestyle',':','parent',data.handles_otherPanel1(nplot)); % Black line for pointer position
                data.handles_otherFrameLine1(nplot) = patch([0 0 0 0], [0 0 0 0], 'r', 'edgecolor', 'none', 'facealpha', .5,'parent',data.handles_otherPanel1(nplot)); % Red line for current frame
                if isempty(zoomWindow), data.handles_otherShading1(nplot) = patch([0 0 0 0],[0 0 0 0],'blue', 'FaceAlpha', 0.2, 'EdgeColor', 'none','parent',data.handles_otherPanel1(nplot));
                else data.handles_otherShading1(nplot) = patch(zoomWindow([1 1 2 2]),otherYLim([1 2 2 1]),'blue', 'FaceAlpha', 0.2, 'EdgeColor', 'none','parent',data.handles_otherPanel1(nplot));        
                end
                xlim(data.handles_otherPanel1(nplot), [0 totalDuration]); % Set x-axis limits based on video duration
                if nplot==nplots, xlabel(data.handles_otherPanel1(nplot), 'Time (s)'); 
                else set(data.handles_otherPanel1(nplot),'xticklabel',[]);
                end
                set(data.handles_otherPanel1(nplot), 'xcolor', .5*[1 1 1], 'ycolor', .5*[1 1 1],'box','off');

                % Create a dedicated axes for all other plots (for image displays)
                data.handles_otherPanel2(nplot) = axes('Position', [1 nplot]*[0.1, 0.5-0.30/(1+nplots*1.5), 0.8, 0.30/(1+nplots*1.5); 0 -0.30*1.5/(1+nplots*1.5) 0 0], 'Parent', hFig);
                data.handles_otherPlot2(nplot) = image([],'parent',data.handles_otherPanel2(nplot));
                data.handles_otherPointerLine2(nplot) = patch([0 0 0 0], [0 0 0 0], 'k', 'edgecolor', 'k', 'facecolor', 'none','linestyle',':','parent',data.handles_otherPanel2(nplot)); % Black line for pointer position
                data.handles_otherFrameLine2(nplot) = patch([0 0 0 0], [0 0 0 0], 'r', 'edgecolor', 'none', 'facealpha', .5,'parent',data.handles_otherPanel2(nplot)); % Red line for current frame
                if isempty(zoomWindow), data.handles_otherShading2(nplot) = patch([0 0 0 0],[0 0 0 0],'blue', 'FaceAlpha', 0.2, 'EdgeColor', 'none','parent',data.handles_otherPanel2(nplot));
                else data.handles_otherShading2(nplot) = patch(zoomWindow([1 1 2 2]),otherYLim([1 2 2 1]),'blue', 'FaceAlpha', 0.2, 'EdgeColor', 'none','parent',data.handles_otherPanel2(nplot));        
                end
                xlim(data.handles_otherPanel2(nplot), [0 totalDuration]); % Set x-axis limits based on video duration
                if nplot==nplots, xlabel(data.handles_otherPanel2(nplot), 'Time (s)'); 
                else set(data.handles_otherPanel2(nplot),'xticklabel',[]);
                end
                %ylabel(data.handles_otherPanel2, 'Frequency (Hz)'); % note: change later when adding more plots
                set(data.handles_otherPanel2(nplot), 'xcolor', .5*[1 1 1], 'ycolor', .5*[1 1 1],'box','off');

                data.handles_plotmeasure(nplot)=uicontrol('Style', 'popupmenu', 'string', {'Velocity of Movements', 'Acceleration of Movements', 'Audio Spectrogram', 'Audio Harmonic to Noise Ratio', 'Acoustic Energy'}, 'Value', plotMeasure(nplot), 'units','norm','Position', [1 nplot]*[0.35, 0.5, 0.3, .03; 0  -0.30*1.5/(1+nplots*1.5) 0 0], 'Callback', @(src, event) changePlotMeasure(src, event, hFig), 'Parent', hFig);
            end
            data.handles_plotmeasure_add=uicontrol('Style', 'pushbutton', 'string', '+', 'tooltip','Add new plot to display', 'units','norm','Position', [0.91, 0.5-0.30, 0.02, 0.02], 'Callback', @(src, event) addPlotMeasure(src, event, hFig), 'Parent', hFig);
            data.handles_plotmeasure_del=uicontrol('Style', 'pushbutton', 'string', '-', 'tooltip','Remove this plot from display', 'units','norm','Position', [0.93, 0.5-0.30, 0.02, 0.02], 'Callback', @(src, event) delPlotMeasure(src, event, hFig), 'Parent', hFig);
            if nplots==0, set(data.handles_plotmeasure_del,'visible','off'); end
            if nplots>1&&nplots>=numel(get(data.handles_plotmeasure(1),'string')), set(data.handles_plotmeasure_add,'visible','off'); end

            % Create a dedicated axes for the audio signal
            data.handles_audioPanel = axes('Position', [1 0]*[0.1, 0.5-0.30/(1+nplots*1.5), 0.8, 0.30/(1+nplots*1.5); 0 -0.30*1.5/(1+nplots*1.5) 0 0], 'Parent', hFig); % Move audio panel upward
            data.handles_audioPlot = plot((0:length(audioSignal)-1)/audioFs, audioSignal(:,1), 'b', 'Parent', data.handles_audioPanel); % Plot full audio signal
            data.handles_audioPointerLine = patch(data.handles_audioPanel, [0 0 0 0], [0 0 0 0], 'k', 'edgecolor', 'k', 'facecolor', 'none','linestyle',':'); % Black line for mouse position
            data.handles_audioFrameLine = patch(data.handles_audioPanel, [0 0 0 0], [0 0 0 0], 'r', 'edgecolor', 'none', 'facealpha', .5); % Red line for current frame
            if isempty(zoomWindow), data.handles_audioShading = patch([0 0 0 0],[0 0 0 0],'blue', 'FaceAlpha', 0.2, 'EdgeColor', 'none'); 
            else data.handles_audioShading = patch(zoomWindow([1 1 2 2]),audioYLim([1 2 2 1]),'blue', 'FaceAlpha', 0.2, 'EdgeColor', 'none');        
            end
            data.handles_audioFrameText = text(0,0,'','color','r','horizontalalignment','left','verticalalignment','top'); set(data.handles_audioFrameText,{'string','position'},audioFrameText); 
            data.handles_audioShadingText1 = text(0,0,'','color','b','horizontalalignment','right','verticalalignment','bottom'); set(data.handles_audioShadingText1,{'string','position'},audioShadingText1); 
            data.handles_audioShadingText2 = text(0,0,'','color','b','horizontalalignment','left','verticalalignment','bottom'); set(data.handles_audioShadingText2,{'string','position'},audioShadingText2); 
            data.handles_audioShadingText3 = text(0,0,'','color','b','horizontalalignment','left','verticalalignment','top'); set(data.handles_audioShadingText3,{'string','position'},audioShadingText3); 
            xlim(data.handles_audioPanel, [0 totalDuration]); % Set x-axis limits based on audio duration
            ylim(data.handles_audioPanel, audioYLim); % Apply y-limits for the audio plot
            %xlabel(data.handles_audioPanel, 'Time (s)');
            %ylabel(data.handles_audioPanel, 'Audio Signal Intensity');
            %title(data.handles_audioPanel, 'Audio Signal with Current Frame');
            set(data.handles_audioPanel, 'xcolor', .5*[1 1 1], 'ycolor', .5*[1 1 1], 'box','off');
            if nplots==0, xlabel(data.handles_audioPanel, 'Time (s)');
            else set(data.handles_audioPanel,'xticklabel',[]);
            end
            data.handles_audiosignal=uicontrol('Style', 'popupmenu', 'string', {'raw Audio Signal','MRI denoised Audio Signal'}, 'Value', audioSignalSelect, 'units','norm','Position', [0.35, 0.5, 0.3, 0.03], 'Callback', @(src, event) changeAudioSignal(src, event, hFig), 'Parent', hFig);

            % Store information in shared "data" variable
            data.isPlaying = false;
            data.currentFrame = 1; % Start at the first frame
            data.endFrame = 0;
            data.numFrames = numFrames;
            data.FrameRate = FrameRate;
            data.audioSignal = audioSignal;
            data.audioSignalRaw = audioSignal;
            data.audioSignalDen = audioSignalDenoised;
            data.SampleRate = audioFs;
            data.totalDuration=totalDuration;
            data.zoomWindow=zoomWindow;
            data.zoomin = zoomin;
            data.SampleQueue = 0;
            data.hVideo = hVideo;
            data.frameCache = frameCache;
            data.frameMotionVel=frameMotionVel;
            data.frameMotionAcc=frameMotionAcc;
            data.globalMotionVel=globalMotionVel;
            data.globalMotionAcc=globalMotionAcc;
            data.spectrogram = dataspectrogram;
            data.harmonicRatio = dataharmonicRatio;
            data.motionHighlight = motionHighlight;
            data.plotMeasure = plotMeasure;
            data.audioSignalSelect = audioSignalSelect;
            data.layout = layout;
            data.colormap=1-gray(256);
            data.audioYLim = audioYLim;
            data.otherYLim = otherYLim;
            data.playbackSpeed = 1; % Default playback speed
            data.audioPlayer1 = audioplayer(audioSignal, audioFs); % Create audioplayer object
            data.audioPlayer2 = audioplayer(audioSignalDenoised, audioFs); % Create audioplayer object
            data.audioPlayer = data.audioPlayer1;
            data.videoFile = videoFile;

            % adds video name 
            adjustPlaybackSpeed();
            changeAudioSignal();
            changeColormap();
            zoomIn(zoomin);
            changeLayout();
        else
            data.handles_videoPanel=[];
            data.handles_audioPanel=[];
            data.handles_otherPanel1=[];
            data.handles_otherPanel2=[];
        end
        data.isPlaying=false;
        varargout={data};
    end

    function addPlotMeasure(varargin)
        if numel(data.plotMeasure)>1&&numel(data.plotMeasure)>=numel(get(data.handles_plotmeasure(1),'string')),return; end
        data.plotMeasure=[data.plotMeasure 1];
        initialize(0,data.handles_hFig);
    end

    function delPlotMeasure(varargin)
        data.plotMeasure=data.plotMeasure(1:end-1);
        initialize(0,data.handles_hFig);
    end

    function togglePlayPause(~, ~, hFig)
        if ~isfield(data,'audioPlayer'), return; end

        % Toggle playback state
        data.isPlaying = ~data.isPlaying;

        if data.isPlaying
            % Start audio playback from the current time
            if data.currentFrame==data.numFrames, data.currentFrame=1; end
            startSample = max(1, min(length(data.audioSignal)-1, 1+round((data.currentFrame-1)/data.FrameRate*data.SampleRate)));
            data.audioPlayer.SampleRate=data.SampleRate*data.playbackSpeed;
            data.endFrame=data.numFrames;
            set(data.handles_play, 'cdata', data.handles_icons{2}); 
            zoomIn(false);
            play(data.audioPlayer, [startSample, length(data.audioSignal)]);
            if data.SampleQueue==0, data.SampleQueue=data.audioPlayer.CurrentSample-startSample; disp(data.SampleQueue); end
            mainLoop();
        else
            % Pause audio playback
            set(data.handles_play, 'cdata', data.handles_icons{1}); 
            pause(data.audioPlayer);
        end

    end

    function nextFrame(~, ~, hFig)
        if ~isfield(data,'audioPlayer'), return; end
        if ~data.isPlaying,
            if data.currentFrame < data.numFrames
                data.currentFrame = data.currentFrame + 1;
                currentFrameIndex = round(data.currentFrame);
                frame = getframeCache(currentFrameIndex);
                set(data.hVideo, 'CData', frame);
                timeAtCurrentFrame = (currentFrameIndex+[-1 -1 0 0]) / data.FrameRate;
                set(data.handles_audioFrameLine, 'XData', timeAtCurrentFrame, 'YData', data.audioYLim([1 2 2 1]));
                set(data.handles_otherFrameLine1, 'XData', timeAtCurrentFrame, 'YData', data.otherYLim([1 2 2 1]));
                set(data.handles_otherFrameLine2, 'XData', timeAtCurrentFrame, 'YData', data.otherYLim([1 2 2 1]));
                set(data.handles_audioFrameText, 'string', sprintf(' t = %.3f s',mean(timeAtCurrentFrame)), 'position', [timeAtCurrentFrame(end), data.audioYLim*[0;1]]);
                data.handles_audioFrameText_extent=[];

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
        if ~isfield(data,'audioPlayer'), return; end
        if ~data.isPlaying,
            if data.currentFrame > 1
                data.currentFrame = data.currentFrame - 1;
                currentFrameIndex = round(data.currentFrame);
                frame = getframeCache(currentFrameIndex);
                set(data.hVideo, 'CData', frame);
                timeAtCurrentFrame = (currentFrameIndex+[-1 -1 0 0]) / data.FrameRate;
                set(data.handles_audioFrameLine, 'XData', timeAtCurrentFrame, 'YData', data.audioYLim([1 2 2 1]));
                set(data.handles_otherFrameLine1, 'XData', timeAtCurrentFrame, 'YData', data.otherYLim([1 2 2 1]));
                set(data.handles_otherFrameLine2, 'XData', timeAtCurrentFrame, 'YData', data.otherYLim([1 2 2 1]));
                set(data.handles_audioFrameText, 'string', sprintf(' t = %.3f s',mean(timeAtCurrentFrame)), 'position', [timeAtCurrentFrame(end), data.audioYLim*[0;1]]);
                data.handles_audioFrameText_extent=[];
                drawnow;
            end
        end
    end

    function thisFrame(thisTime)
        if ~isfield(data,'audioPlayer'), return; end
        if nargin<1||isempty(thisTime), thisTime=get(gca,'currentpoint'); end
        if ~data.isPlaying,
            data.currentFrame = max(1, min(data.numFrames, ceil(thisTime(1) * data.FrameRate)));
            currentFrameIndex = round(data.currentFrame);
            frame = getframeCache(currentFrameIndex);
            set(data.hVideo, 'CData', frame);
            timeAtCurrentFrame = (currentFrameIndex+[-1 -1 0 0]) / data.FrameRate;
            fprintf('t = %.3f s\n',thisTime(1));
            set(data.handles_audioFrameLine, 'XData', timeAtCurrentFrame, 'YData', data.audioYLim([1 2 2 1]));
            set(data.handles_otherFrameLine1, 'XData', timeAtCurrentFrame, 'YData', data.otherYLim([1 2 2 1]));
            set(data.handles_otherFrameLine2, 'XData', timeAtCurrentFrame, 'YData', data.otherYLim([1 2 2 1]));
            set(data.handles_audioFrameText, 'string', sprintf(' t = %.3f s',thisTime(1)), 'position', [timeAtCurrentFrame(end), data.audioYLim*[0;1]]);
            data.handles_audioFrameText_extent=[];
            drawnow;
        end
    end

    function rewindVideo(~, ~, hFig)
        if ~isfield(data,'audioPlayer'), return; end
        if ~data.isPlaying,
            data.currentFrame = 1;
            currentFrameIndex = round(data.currentFrame);
            frame = getframeCache(currentFrameIndex);
            set(data.hVideo, 'CData', frame);
            timeAtCurrentFrame = (currentFrameIndex+[-1 -1 0 0]) / data.FrameRate;
            set(data.handles_audioFrameLine, 'XData', timeAtCurrentFrame, 'YData', data.audioYLim([1 2 2 1]));
            set(data.handles_otherFrameLine1, 'XData', timeAtCurrentFrame, 'YData', data.otherYLim([1 2 2 1]));
            set(data.handles_otherFrameLine2, 'XData', timeAtCurrentFrame, 'YData', data.otherYLim([1 2 2 1]));
            set(data.handles_audioFrameText, 'string', sprintf(' t = %.3f s',mean(timeAtCurrentFrame)),  'position', [timeAtCurrentFrame(end), data.audioYLim*[0;1]]);
            data.handles_audioFrameText_extent=[];
            zoomIn(false);
            drawnow;
        end
    end

    function adjustPlaybackSpeed(~, ~, hFig)
        speeds=[0.1, 0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 5];
        if data.isPlaying, set(data.handles_playbackspeed,'value',find(speeds==data.playbackSpeed,1));
        else data.playbackSpeed = speeds(get(data.handles_playbackspeed,'value'));
        end
    end

    function zoomIn(state)
        if nargin<1, data.zoomin=~data.zoomin;
        else data.zoomin=state;
        end
        switch(data.zoomin)
            case 1, % zoom in
                startTime = data.zoomWindow(1);
                endTime = data.zoomWindow(2);
                xlim([data.handles_audioPanel,data.handles_otherPanel1,data.handles_otherPanel2], [max(0,startTime-.1*(endTime-startTime)) min(data.totalDuration,endTime+.1*(endTime-startTime))]); 
            case 0, % zoom out
                xlim([data.handles_audioPanel, data.handles_otherPanel1, data.handles_otherPanel2], [0 data.totalDuration]); 
        end
        data.handles_audioFrameText_extent=[];
        data.handles_audioShadingText1_extent=[];
        data.handles_audioShadingText2_extent=[];
        data.handles_audioShadingText3_extent=[];
    end

    function changeMotionHighlight(~, ~, hFig);
        data.motionHighlight=get(data.handles_motionhighlight,'value');
        if isfield(data,'hVideo'), set(data.hVideo, 'CData', getframeCache(data.currentFrame)); end
    end

    function changeColormap(~, ~, hFig);
        colormaps={1-gray(256),jet(256),parula(256),hot(256),sky(256),flipud(bone(256)),copper(256)};
        data.colormap=colormaps{get(data.handles_colormap,'value')};
        if isfield(data,'globalMotionVel'), changePlotMeasure(); end
    end


    function changePlotMeasure(~, ~, hFig);
        nplots=numel(data.handles_plotmeasure);
        data.plotMeasure=get(data.handles_plotmeasure,'value');
        if iscell(data.plotMeasure), data.plotMeasure=[data.plotMeasure{:}]; end
        if isfield(data,'globalMotionVel'), 
            for nplot=1:nplots
                if ismember(data.plotMeasure(nplot),[1,2,4,5]) % plots
                    switch(data.plotMeasure(nplot)),
                        case 1,
                            plotdataY = data.globalMotionVel; % Plot global velocity
                            %plotdataX = (1:numel(plotdataY))/data.FrameRate;
                            plotdataX = (0:numel(plotdataY)-1)/data.SampleRate; % note: use this when data has been interpolated to audio sampling rate
                        case 2,
                            plotdataY = data.globalMotionAcc; % Plot global acceleration
                            %plotdataX = (1:numel(plotdataY))/data.FrameRate;
                            plotdataX = (0:numel(plotdataY)-1)/data.SampleRate; % note: use this when data has been interpolated to audio sampling rate
                        case {4,5},
                            if ~isfield(data,'harmonicRatio')||isempty(data.harmonicRatio)
                                hwindowsize=3/75;
                                [data.harmonicRatio.P1,data.harmonicRatio.t,data.harmonicRatio.E1]=harmonicRatio(data.audioSignalRaw,data.SampleRate,round(hwindowsize*data.SampleRate),round((hwindowsize-.001)*data.SampleRate), 0.10);
                                [data.harmonicRatio.P2,data.harmonicRatio.t,data.harmonicRatio.E2]=harmonicRatio(data.audioSignalDen,data.SampleRate,round(hwindowsize*data.SampleRate),round((hwindowsize-.001)*data.SampleRate), 0.10);
                                data.harmonicRatio.E1 = sqrt(max(0,data.harmonicRatio.E1)); % MS to RMS
                                data.harmonicRatio.E2 = sqrt(max(0,data.harmonicRatio.E2)); % MS to RMS
                                data.harmonicRatio.P1 = -10*log10(1e-1)+10*log10(max(1e-1,data.harmonicRatio.P1./max(eps,1-data.harmonicRatio.P1))); % HR to HNR
                                data.harmonicRatio.P2 = -10*log10(1e-1)+10*log10(max(1e-1,data.harmonicRatio.P2./max(eps,1-data.harmonicRatio.P2))); % HR to HNR
                            end
                            if data.plotMeasure(nplot)==4 % Plot harmonic to noise ratio
                                if data.audioSignalSelect==1, plotdataY = data.harmonicRatio.P1;
                                else plotdataY = data.harmonicRatio.P2;
                                end
                            else % Plot acoustic energy
                                if data.audioSignalSelect==1, plotdataY = data.harmonicRatio.E1;
                                else plotdataY = data.harmonicRatio.E2;
                                end
                            end
                            plotdataX = data.harmonicRatio.t;
                    end
                    set(data.handles_otherPlot1(nplot),'xdata',plotdataX,'ydata',plotdataY,'visible','on');
                    set(data.handles_otherPanel1(nplot),'ylim',[0 1.1*max(plotdataY)],'visible','on');
                    set(data.handles_otherShading1(nplot),'visible','on');
                    set([data.handles_otherPanel2(nplot),data.handles_otherPlot2(nplot),data.handles_otherShading2(nplot)],'visible','off');
                else % images
                    switch(data.plotMeasure(nplot))
                        case 3, % spectrogram
                            if ~isfield(data,'spectrogram')||isempty(data.spectrogram),
                                hwindowsize=0.010;
                                [data.spectrogram.P1,data.spectrogram.t,data.spectrogram.f]=flvoice_spectrogram(data.audioSignalRaw,data.SampleRate,round(hwindowsize*data.SampleRate),round((hwindowsize-.001)*data.SampleRate),2048);
                                [data.spectrogram.P2,data.spectrogram.t,data.spectrogram.f]=flvoice_spectrogram(data.audioSignalDen,data.SampleRate,round(hwindowsize*data.SampleRate),round((hwindowsize-.001)*data.SampleRate),2048);
                            end
                            mask=data.spectrogram.f<=8000;
                            plotdataX=data.spectrogram.t;
                            plotdataY=data.spectrogram.f(mask);
                            if data.audioSignalSelect==1, plotdataC=data.spectrogram.P1(mask,:);
                            else plotdataC=data.spectrogram.P2(mask,:);
                            end
                    end
                    c1=prctile(mean(plotdataC,1),1);
                    c2=prctile(plotdataC(:),99.9);
                    set(data.handles_otherPlot2(nplot),'cdata',ind2rgb(1+floor((size(data.colormap,1)-1)*max(0,plotdataC-c1)/max(eps,c2-c1)),data.colormap),'xdata',plotdataX,'ydata',plotdataY,'visible','on');
                    %[nill,nill,idx]=unique(plotdataC);
                    %set(data.handles_otherPlot2(nplot),'cdata',ind2rgb(1+floor((size(data.colormap,1)-1)*max(0,reshape(idx,size(plotdataC))-1)/max(eps,max(idx)-1)),data.colormap),'xdata',plotdataX,'ydata',plotdataY,'visible','on');
                    set(data.handles_otherPanel2(nplot),'ydir','normal','ylim',[min(plotdataY) max(plotdataY)],'visible','on');
                    set(data.handles_otherShading2(nplot),'visible','on');
                    set([data.handles_otherPanel1(nplot),data.handles_otherPlot1(nplot),data.handles_otherShading1(nplot)],'visible','off');
                end
            end
        end
        if isfield(data,'hVideo'), set(data.hVideo, 'CData', getframeCache(data.currentFrame)); end
    end

    function changeAudioSignal(~, ~, hFig);
        data.audioSignalSelect =get(data.handles_audiosignal,'value');
        if isfield(data,'globalMotionVel'), 
            if data.audioSignalSelect==1, 
                data.audioSignal = data.audioSignalRaw; % raw audio
                data.audioPlayer = data.audioPlayer1;
            else,                   
                data.audioSignal = data.audioSignalDen; % denoised audio
                data.audioPlayer = data.audioPlayer2;
            end
            set(data.handles_audioPlot,'ydata',data.audioSignal(:,1));  
            set(data.handles_audioPanel,'ylim',data.audioYLim); 
            changePlotMeasure();
        end
    end

    function changeLayout(layout)
        if nargin<1, layout=get(data.handles_layout,'value'); end
        if ~isfield(data,'layout'), data.layout=1; end
        if ~isfield(data,'figureposition'), data.figureposition=[.25, .1, .5, .8]; end
        if data.layout==1, data.figureposition=get(data.handles_hFig,'Position'); end
        data.layout=layout; 
        set(data.handles_layout,'value',layout);
        nplots=numel(data.handles_plotmeasure);
        switch(data.layout)
            case 1, % standard layout
                set(data.handles_hFig,'Position',data.figureposition);
                set(data.handles_buttonPanel, 'Position', [0, 0, 1, 0.15]);
                set(data.handles_videoPanel,'Position', [0.0, 0.55, 1, 0.4]);
                set(data.handles_audioPanel,'Position', [1 0]*[0.1, 0.5-0.30/(1+nplots*1.5), 0.8, 0.30/(1+nplots*1.5); 0 -0.30*1.5/(1+nplots*1.5) 0 0]);
                set(data.handles_audiosignal,'Position',[0.35, 0.5, 0.3, 0.025]);
                for nplot=1:nplots, 
                    set(data.handles_otherPanel1(nplot), 'Position', [1 nplot]*[0.1, 0.5-0.30/(1+nplots*1.5), 0.8, 0.30/(1+nplots*1.5); 0 -0.30*1.5/(1+nplots*1.5) 0 0]);
                    set(data.handles_otherPanel2(nplot), 'Position', [1 nplot]*[0.1, 0.5-0.30/(1+nplots*1.5), 0.8, 0.30/(1+nplots*1.5); 0 -0.30*1.5/(1+nplots*1.5) 0 0]);
                    set(data.handles_plotmeasure(nplot),'Position',[1 nplot]*[0.35, 0.5, 0.3, .025; 0  -0.30*1.5/(1+nplots*1.5) 0 0]);
                end
                set(data.handles_plotmeasure_add,'Position', [0.91, 0.5-0.30, 0.04, 0.04]);
                set(data.handles_plotmeasure_del,'Position', [0.95, 0.5-0.30, 0.04, 0.04]);
                drawnow;
            case 2, % maximized (horizontal layout)
                set(data.handles_hFig,'Position',[0.01, 0, .98, .975]);
                set(data.handles_buttonPanel, 'Position', [0.575, 0.025, 0.4, 0.13]);
                set(data.handles_videoPanel,'Position', [0.0, 0.0, 0.54, 1]);
                set(data.handles_audioPanel,'Position', [1 0]*[0.575, 0.95-0.75/(1+nplots*1.25), 0.4, 0.75/(1+nplots*1.25); 0 -0.75*1.25/(1+nplots*1.25) 0 0]);
                set(data.handles_audiosignal,'Position',[0.575, 0.95, 0.4, 0.02]);
                for nplot=1:nplots, 
                    set(data.handles_otherPanel1(nplot), 'Position', [1 nplot]*[0.575, 0.95-0.75/(1+nplots*1.25), 0.4, 0.75/(1+nplots*1.25); 0 -0.75*1.25/(1+nplots*1.25) 0 0]);
                    set(data.handles_otherPanel2(nplot), 'Position', [1 nplot]*[0.575, 0.95-0.75/(1+nplots*1.25), 0.4, 0.75/(1+nplots*1.25); 0 -0.75*1.25/(1+nplots*1.25) 0 0]);
                    set(data.handles_plotmeasure(nplot),'Position',[1 nplot]*[0.575, 0.95, 0.4, .02; 0  -0.75*1.25/(1+nplots*1.25) 0 0]);
                end
                set(data.handles_plotmeasure_add,'Position', [0.978, 0.95-0.75, 0.02, 0.04]);
                set(data.handles_plotmeasure_del,'Position', [0.978, 0.95-0.75+0.04, 0.02, 0.04]);
                drawnow;
            case 3, % maximized (vertical layout)
                set(data.handles_hFig,'Position',[.01, 0, .98, .975]);
                set(data.handles_buttonPanel, 'Position', [.25, 0, .5, 0.13]);
                set(data.handles_videoPanel,'Position', [0.0, 0.4, 1, 0.6]);
                set(data.handles_audioPanel,'Position', [1 0]*[0.25, 0.35-0.175/(1+nplots*1.0), 0.5, 0.175/(1+nplots*1.0); 0 -0.175*1.0/(1+nplots*1.0) 0 0]);
                set(data.handles_audiosignal,'Position',[1 0]*[0.05, 0.35-.015-0.175/(1+nplots*1.0)/2, 0.15, 0.03; 0 -0.175*1.0/(1+nplots*1.0) 0 0]);
                for nplot=1:nplots, 
                    set(data.handles_otherPanel1(nplot), 'Position', [1 nplot]*[0.25, 0.35-0.175/(1+nplots*1.0), 0.5, 0.175/(1+nplots*1.0); 0 -0.175*1.0/(1+nplots*1.0) 0 0]);
                    set(data.handles_otherPanel2(nplot), 'Position', [1 nplot]*[0.25, 0.35-0.175/(1+nplots*1.0), 0.5, 0.175/(1+nplots*1.0); 0 -0.175*1.0/(1+nplots*1.0) 0 0]);
                    set(data.handles_plotmeasure(nplot),'Position',[1 nplot]*[0.05, 0.35-.015-0.175/(1+nplots*1.0)/2, 0.15, .03; 0  -0.175*1.0/(1+nplots*1.0) 0 0]);
                end
                set(data.handles_plotmeasure_add,'Position', [0.76, 0.35-0.175, 0.02, 0.04]);
                set(data.handles_plotmeasure_del,'Position', [0.78, 0.35-0.175, 0.02, 0.04]);
                drawnow;
        end
    end

    function selectPoints(hFig)
        % Display instructions
        fprintf('Select a point on the audio plot: ');
        [audioX1, ~] = ginput(1); 
        fprintf('t = %.3f s\n',mean(audioX1));

        % Add a temporary vertical line for the selected audio point
        handles_audioLine1 = line(data.handles_audioPanel, [audioX1, audioX1], data.audioYLim, 'Color', 'blue', 'LineStyle', ':');
        fprintf('Select a second point on the audio plot: ');
        [audioX2, ~] = ginput(1); 
        fprintf('t = %.3f s\n',mean(audioX2));

        % Determine the selected range
        startTime = min(audioX1, audioX2);
        endTime = max(audioX1, audioX2);
        data.zoomWindow = [startTime, endTime];

        % Add shading to indicate the selected range
        set(data.handles_audioShading, 'xdata', [startTime, endTime, endTime, startTime], 'ydata', [data.audioYLim(1), data.audioYLim(1), data.audioYLim(2), data.audioYLim(2)]); 
        set(data.handles_otherShading1, 'xdata', [startTime, endTime, endTime, startTime], 'ydata', [data.otherYLim(1), data.otherYLim(1), data.otherYLim(2), data.otherYLim(2)]); 
        set(data.handles_otherShading2, 'xdata', [startTime, endTime, endTime, startTime], 'ydata', [data.otherYLim(1), data.otherYLim(1), data.otherYLim(2), data.otherYLim(2)]); 
        set(data.handles_audioShadingText1, 'string', sprintf('t = %.3f s ',startTime), 'position', [startTime, data.audioYLim*[1;0]]);
        set(data.handles_audioShadingText2, 'string', sprintf(' t = %.3f s',endTime), 'position', [endTime, data.audioYLim*[1;0]]);
        set(data.handles_audioShadingText3, 'string', sprintf('∆t = %d ms',round(1000*(endTime-startTime))), 'position', [endTime, data.audioYLim*[1;0]]);
        data.handles_audioShadingText1_extent=[];
        data.handles_audioShadingText2_extent=[];
        data.handles_audioShadingText3_extent=[];
        delete(handles_audioLine1);

        % enable selection-related buttons
        if isfield(data, 'handles_playSelectionButton') && isvalid(data.handles_playSelectionButton), set(data.handles_playSelectionButton, 'Enable', 'on'); end
        if isfield(data, 'handles_saveclipButton') && isvalid(data.handles_saveclipButton), set(data.handles_saveclipButton, 'Enable', 'on'); end
        if isfield(data, 'handles_zoom') && isvalid(data.handles_zoom), set(data.handles_zoom, 'Enable', 'on'); end        

        % Display the time difference between the selected points
        disp(['Time difference between selected points: ', num2str(endTime - startTime), ' seconds.']);
        zoomIn(true);
    end

    function saveClip(hFig)
        % Check if audioLine and motionLine exist
        if isempty(data.zoomWindow)
            disp('Error: Select time points before saving a clip.');
            return;
        end

        % Calculate start and end times (in seconds)
        startTime = data.zoomWindow(1);
        endTime = data.zoomWindow(2);
        % Calculate frame range
        startFrame = max(1, min(data.numFrames, 1+floor(startTime * data.FrameRate)));
        endFrame = max(1, min(data.numFrames, 1+floor(endTime * data.FrameRate)));
        disp(['Saving clip from ', num2str(startTime), ' to ', num2str(endTime), ' seconds (', num2str(endFrame-startFrame+1),' frames)']);

        % Calculate audio sample range
        startSample = max(1, round((startFrame-1)/data.FrameRate * data.SampleRate));
        endSample = min(length(data.audioSignal), round((endFrame+1)/data.FrameRate* data.SampleRate-1));
        audioClip = data.audioSignal(startSample:endSample, :); % Extract audio segment

        % Prompt user for output file name
        if data.audioSignalSelect==1, suggestedfileName=regexprep(data.videoFile,'\.[^\.]*$','.mp4');
        else                          suggestedfileName=regexprep(data.videoFile,'(_denoised)?\.[^\.]*$','_denoised.mp4');
        end
        [fileName, filePath] = uiputfile({'*.mp4', 'MP4 Video File (*.mp4)'; '*.mat', 'Matlb Video File (*.mat)'; '*.avi', 'AVI Video File (*.avi)'; '*', 'All Files (*.*)'}, 'Save Video Clip As', suggestedfileName);
        if fileName == 0
            disp('Saving cancelled.');
            return;
        end
        outputFile = fullfile(filePath, fileName);
        if ~isempty(dir(outputFile)), 
            if ispc, [ok,nill]=system(sprintf('del "%s"',outputFile));
            else [ok,nill]=system(sprintf('rm -f ''%s''',outputFile));
            end
        end

        switch(regexprep(fileName,'^.*\.',''))
            case 'mp4'
                tempfile='VidTest_temporalfile_video.mp4';
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
                % Write separate audio track and merge
                SampleRate=data.SampleRate;
                if ~ismember(data.SampleRate,[44100,48000]) % resample audio to 44100 or 48000 for compatibility across platforms
                    if ismember(data.SampleRate,[11025, 22050]), SampleRate=44100;
                    else SampleRate=48000;
                    end
                    disp(['Clip audio resampled from ', num2str(data.SampleRate), 'Hz to ',num2str(SampleRate),'Hz']);
                    audioClip=interpft(audioClip,round(length(audioClip)*SampleRate/data.SampleRate));
                end
                audiowrite('VidTest_temporalfile_audio.mp4', audioClip, SampleRate);
                if ispc
                    args_ffmpeg=sprintf('-i "%s" -i "%s" -c:v copy -c:a copy "%s"', fullfile(pwd,'VidTest_temporalfile_video.mp4'),fullfile(pwd,'/VidTest_temporalfile_audio.mp4'), outputFile);
                    args_vlc=sprintf('-I dummy "%s" --input-slave="%s" --sout "#gather:std{access=file,mux=mp4,dst=%s}" vlc://quit', fullfile(pwd,'VidTest_temporalfile_video.mp4'),fullfile(pwd,'/VidTest_temporalfile_audio.mp4'), outputFile);
                    cmd='ffmpeg'; args=args_ffmpeg;
                    [ko,msg]=system('where ffmpeg');
                    if ko~=0
                        cmd='vlc'; args=args_vlc;
                        [ko,msg]=system('where vlc');
                    end                        
                    if ko==0 % try merging using ffmpeg or VLC
                        [ko,msg]=system(sprintf('%s %s', cmd, args))
                        if ko~=0, 
                            disp(sprintf('%s %s', cmd, args));
                            disp(msg); 
                        end
                        disp(['Clip saved to: ', outputFile]);
                    else
                        disp('Sorry, unable to find FFMPEG or VLC on your system. Please install FFMPEG and add its location to your system PATH');
                    end
                else
                    args_ffmpeg=sprintf('-i ''%s'' -i ''%s'' -c:v copy -c:a copy ''%s''', fullfile(pwd,'VidTest_temporalfile_video.mp4'),fullfile(pwd,'/VidTest_temporalfile_audio.mp4'), outputFile);
                    args_vlc=sprintf('-I dummy ''%s'' --input-slave=''%s'' --sout "#gather:std{access=file,mux=mp4,dst=%s}" vlc://quit', fullfile(pwd,'VidTest_temporalfile_video.mp4'),fullfile(pwd,'/VidTest_temporalfile_audio.mp4'), outputFile);
                    cmd='ffmpeg'; args=args_ffmpeg;
                    [ko,msg]=system('which ffmpeg');
                    if ko~=0 && ~isempty('/usr/local/bin/ffmpeg'), ko=0; cmd='/usr/local/bin/ffmpeg'; end
                    if ko~=0 && ~isempty('/Applications/ffmpeg'), ko=0; cmd='/Applications/ffmpeg'; end
                    if ko~=0
                        cmd='vlc'; args=args_vlc;
                        [ko,msg]=system('which vlc');
                        if ko~=0 && ~isempty('/usr/local/bin/vlc'), ko=0; cmd='/usr/local/bin/vlc'; end
                        if ko~=0 && ~isempty('/Applications/vlc'), ko=0; cmd='/Applications/vlc'; end
                        if ko~=0 && ~isempty('/Applications/VLC.app'), ko=0; cmd='/Applications/VLC.app/Contents/MacOS/VLC'; end
                    end                        
                    if ko==0 % try merging using ffmpeg
                        [ko,msg]=system(sprintf('%s %s', cmd, args));
                        if ko~=0, 
                            disp(sprintf('%s %s', cmd, args));
                            disp(msg); 
                        end
                        disp(['Clip saved to: ', outputFile]);
                    else
                        if ismac, disp('Sorry, unable to find FFMPEG or VLC on your system. Please install FFMPEG and add it to the Applications folder');
                        else disp('Sorry, unable to find FFMPEG or VLC on your system. Please install FFMPEG and add it to the /usr/local/bin/ folder');
                        end
                    end
                end

            case 'avi'
                if ~isempty(which('vision.VideoFileWriter')) % saves video and audio to avi using Vision Toolbox
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
                    disp(['Clip saved to: ', outputFile]);
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
                    disp(['Clip (without audio) saved to: ', outputFile]);
                end

            case 'mat'
                video = struct('data',{data.frameCache(startFrame:endFrame)},'fs',data.FrameRate);
                audio = struct('data',audioClip,'fs',data.SampleRate);
                save(outputFile, 'video','audio');
                disp(['Clip saved to: ', outputFile]);
        end
    end

    function playSelection(hFig)
        % Check if audioLine and motionLine exist
        if isempty(data.zoomWindow)
            disp('Error: No valid selection to play.');
            return;
        end

        % Toggle playback state for the selection
        if ~isfield(data, 'isPlaying') || ~data.isPlaying
            % Get selected time points
            startTime = data.zoomWindow(1);
            endTime = data.zoomWindow(2);

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
        if isfield(data,'videoFile')&&~isempty(data.videoFile), 
            [fileName, filePath] = uigetfile({ '*', 'All Files (*.*)'; '*.avi;*.mp4;*.mat', 'Video Files (*.avi, *.mp4; *.mat)'}, 'Select a Video File',fileparts(data.videoFile));
        else
            [fileName, filePath] = uigetfile({ '*', 'All Files (*.*)'; '*.avi;*.mp4;*.mat', 'Video Files (*.avi, *.mp4; *.mat)'}, 'Select a Video File');
        end
        if fileName == 0
            disp('No video file selected.');
            return;
        end
        newVideoFile = fullfile(filePath, fileName);
        disp(['Loading new video file: ', newVideoFile]);
        data=initialize(newVideoFile, hFig);

    end

    function frame = getframeCache(currentFrameIndex) % mixes video frame image with motion highlight
        frame = data.frameCache{currentFrameIndex};
        if data.motionHighlight>1, 
            colors=[0 0 0; 1 0 0; 1 1 0];
            color=colors(data.motionHighlight,:);
            if all(data.plotMeasure~=2) % by default shows velocity of motion (unless acceleration timecourse is being displayed)
                if currentFrameIndex==1, dframe=sqrt(data.frameMotionVel{currentFrameIndex});
                elseif currentFrameIndex==data.numFrames, dframe=sqrt(data.frameMotionVel{currentFrameIndex-1});
                else dframe=sqrt((data.frameMotionVel{currentFrameIndex}+data.frameMotionVel{currentFrameIndex-1})/2);
                end
            else
                if currentFrameIndex==1, dframe=sqrt(data.frameMotionAcc{currentFrameIndex});
                elseif currentFrameIndex==data.numFrames, dframe=sqrt(data.frameMotionAcc{currentFrameIndex-1});
                else dframe=sqrt((data.frameMotionAcc{currentFrameIndex}+data.frameMotionAcc{currentFrameIndex-1})/2);
                end
            end
            frame=uint8(cat(3, round((1-dframe).*double(frame(:,:,1))+255*dframe*color(1)), round((1-dframe).*double(frame(:,:,2))+255*dframe*color(2)), round((1-dframe).*double(frame(:,:,3))+255*dframe*color(3)) ));
        end
    end

    function copytoclipboard(handle)
        if nargin<1||isempty(handle), handle=gcbo; end
        str=regexprep(get(handle,'string'),'^\s+|\s+$','');
        clipboard('copy', str);
        fprintf('%s copied to clipboard\n',str);
    end

    function flvideo_buttonfcn(option,varargin)
        if ~isfield(data,'handles_audioPanel')||isempty(data.handles_audioPanel), return; end
        if ~isfield(data,'buttondown_pos'), data.buttondown_pos=0; end
        if ~isfield(data,'buttondown_time'), data.buttondown_time=0; end
        if ~isfield(data,'buttondown_ispressed'), data.buttondown_ispressed=0; end
        p1=get(0,'pointerlocation');
        set(gcbf,'units','pixels');
        p2=get(gcbf,'position');
        set(gcbf,'units','norm');
        p3=get(0,'screensize');
        p2(1:2)=p2(1:2)+p3(1:2)-1; % note: fix issue when connecting to external monitor/projector
        pos=(p1-p2(1:2))./p2(3:4);
        pos_ref=get(data.handles_audioPanel,'Position');
        pos_ref=(pos-pos_ref(1:2))./pos_ref(3:4);
        xlim_audio=get(data.handles_audioPanel,'xlim');
        pos_audio=[xlim_audio(1) data.audioYLim(1)]+pos_ref.*[xlim_audio(2)-xlim_audio(1),data.audioYLim(2)-data.audioYLim(1)];
        in_ref=all(pos_ref>=0 & pos_ref<=1);
        refTime=get(data.handles_audioPanel,'xlim')*[1-pos_ref(1);pos_ref(1)];
        nplots=numel(data.handles_plotmeasure);
        if ~in_ref, 
            for nplot=1:nplots,
                pos_ref=get(data.handles_otherPanel1(nplot),'Position');
                pos_ref=(pos-pos_ref(1:2))./pos_ref(3:4);
                in_ref=all(pos_ref>=0 & pos_ref<=1);
                if in_ref, break; end
            end
        end
        if strcmp(get(gcbf,'SelectionType'),'open'), set(gcbf,'selectiontype','normal'); if in_ref, zoomIn(false); end; return; end % double-click to zoom out
        in_text=[]; 
        if ~isfield(data,'handles_audioFrameText_extent')||isempty(data.handles_audioFrameText_extent), data.handles_audioFrameText_extent=get(data.handles_audioFrameText,'extent'); end % highlights text when hovering over it
        if ~isfield(data,'handles_audioShadingText1_extent')||isempty(data.handles_audioShadingText1_extent), data.handles_audioShadingText1_extent=get(data.handles_audioShadingText1,'extent'); end
        if ~isfield(data,'handles_audioShadingText2_extent')||isempty(data.handles_audioShadingText2_extent), data.handles_audioShadingText2_extent=get(data.handles_audioShadingText2,'extent'); end
        if ~isfield(data,'handles_audioShadingText3_extent')||isempty(data.handles_audioShadingText3_extent), data.handles_audioShadingText3_extent=get(data.handles_audioShadingText3,'extent'); end
        if all(pos_audio(1:2)>data.handles_audioFrameText_extent(1:2) & pos_audio(1:2)-data.handles_audioFrameText_extent(1:2)<data.handles_audioFrameText_extent(3:4)),            in_ref=false; in_text=data.handles_audioFrameText; set(data.handles_audioFrameText,'backgroundcolor',[.85 .85 .85]);     else set(data.handles_audioFrameText,'backgroundcolor','none'); end
        if all(pos_audio(1:2)>data.handles_audioShadingText1_extent(1:2) & pos_audio(1:2)-data.handles_audioShadingText1_extent(1:2)<data.handles_audioShadingText1_extent(3:4)),   in_ref=false; in_text=data.handles_audioShadingText1; set(data.handles_audioShadingText1,'backgroundcolor',[.85 .85 .85]);  else set(data.handles_audioShadingText1,'backgroundcolor','none'); end
        if all(pos_audio(1:2)>data.handles_audioShadingText2_extent(1:2) & pos_audio(1:2)-data.handles_audioShadingText2_extent(1:2)<data.handles_audioShadingText2_extent(3:4)),   in_ref=false; in_text=data.handles_audioShadingText2; set(data.handles_audioShadingText2,'backgroundcolor',[.85 .85 .85]);  else set(data.handles_audioShadingText2,'backgroundcolor','none'); end
        if all(pos_audio(1:2)>data.handles_audioShadingText3_extent(1:2) & pos_audio(1:2)-data.handles_audioShadingText3_extent(1:2)<data.handles_audioShadingText3_extent(3:4)),   in_ref=false; in_text=data.handles_audioShadingText3; set(data.handles_audioShadingText3,'backgroundcolor',[.85 .85 .85]);  else set(data.handles_audioShadingText3,'backgroundcolor','none'); end
        if data.buttondown_ispressed
        elseif in_ref, % show timepoint line
            set(data.handles_audioPointerLine, 'xdata', [refTime, refTime, refTime, refTime], 'ydata', [data.audioYLim(1), data.audioYLim(1), data.audioYLim(2), data.audioYLim(2)]);
            if nplots>0
                set(data.handles_otherPointerLine1, 'xdata', [refTime, refTime, refTime, refTime], 'ydata', [data.otherYLim(1), data.otherYLim(1), data.otherYLim(2), data.otherYLim(2)]);
                set(data.handles_otherPointerLine2, 'xdata', [refTime, refTime, refTime, refTime], 'ydata', [data.otherYLim(1), data.otherYLim(1), data.otherYLim(2), data.otherYLim(2)]);
            end
        else 
            set(data.handles_audioPointerLine, 'xdata', [], 'ydata', []);
            if nplots>0
                set(data.handles_otherPointerLine1, 'xdata', [], 'ydata', []);
                set(data.handles_otherPointerLine2, 'xdata', [], 'ydata', []);
            end
        end

        switch(option) % click-and-drag to select & zoom in
            case 'down',
                if in_ref % started selecting window or selecting timepoint
                    data.buttondown_pos=p1(1);
                    data.buttondown_time=refTime;
                    data.buttondown_ispressed=1;
                end
            case 'up',
                if data.buttondown_ispressed>1 % finished selecting window
                    data.buttondown_ispressed=0;
                    startTime = min(data.buttondown_time, refTime);
                    endTime = max(data.buttondown_time, refTime);
                    endTime = max(startTime + 0.001, endTime);
                    set(data.handles_audioShading, 'xdata', [startTime, endTime, endTime, startTime], 'ydata', [data.audioYLim(1), data.audioYLim(1), data.audioYLim(2), data.audioYLim(2)]);
                    set(data.handles_otherShading1, 'xdata', [startTime, endTime, endTime, startTime], 'ydata', [data.otherYLim(1), data.otherYLim(1), data.otherYLim(2), data.otherYLim(2)]);
                    set(data.handles_otherShading2, 'xdata', [startTime, endTime, endTime, startTime], 'ydata', [data.otherYLim(1), data.otherYLim(1), data.otherYLim(2), data.otherYLim(2)]);
                    set(data.handles_audioShadingText1, 'string', sprintf('t = %.3f s ',startTime), 'position', [startTime, data.audioYLim*[1;0]]);
                    set(data.handles_audioShadingText2, 'string', sprintf(' t = %.3f s',endTime), 'position', [endTime, data.audioYLim*[1;0]]);
                    set(data.handles_audioShadingText3, 'string', sprintf('∆t = %d ms',round(1000*(endTime-startTime))), 'position', [endTime, data.audioYLim*[1;0]]);
                    data.handles_audioShadingText1_extent=[];
                    data.handles_audioShadingText2_extent=[];
                    data.handles_audioShadingText3_extent=[];
                    data.zoomWindow = [startTime, endTime];
                    % enable selection-related buttons
                    if isfield(data, 'handles_playSelectionButton') && isvalid(data.handles_playSelectionButton), set(data.handles_playSelectionButton, 'Enable', 'on'); end
                    if isfield(data, 'handles_saveclipButton') && isvalid(data.handles_saveclipButton), set(data.handles_saveclipButton, 'Enable', 'on'); end
                    if isfield(data, 'handles_zoom') && isvalid(data.handles_zoom), set(data.handles_zoom, 'Enable', 'on'); end
                    zoomIn(true);
                elseif in_ref % selected timepoint
                    data.buttondown_ispressed=0;
                    thisFrame(refTime);
                elseif ~isempty(in_text) % clicked on text
                    data.buttondown_ispressed=0;
                    copytoclipboard(in_text);
                else % clicked elsewhere
                    data.buttondown_ispressed=0;
                end
            case 'motion'
                if in_ref && data.buttondown_ispressed && (data.buttondown_ispressed>1 || abs(p1(1)-data.buttondown_pos)>16), % in the process of selecting window (16pixels minimum displacement)
                    data.buttondown_ispressed=2;
                    startTime = min(data.buttondown_time, refTime);
                    endTime = max(data.buttondown_time, refTime);
                    set(data.handles_audioShading, 'xdata', [startTime, endTime, endTime, startTime], 'ydata', [data.audioYLim(1), data.audioYLim(1), data.audioYLim(2), data.audioYLim(2)]);
                    set(data.handles_otherShading1, 'xdata', [startTime, endTime, endTime, startTime], 'ydata', [data.otherYLim(1), data.otherYLim(1), data.otherYLim(2), data.otherYLim(2)]);
                    set(data.handles_otherShading2, 'xdata', [startTime, endTime, endTime, startTime], 'ydata', [data.otherYLim(1), data.otherYLim(1), data.otherYLim(2), data.otherYLim(2)]);
                    set(data.handles_audioShadingText1, 'string', sprintf('t = %.3f s ',startTime), 'position', [startTime, data.audioYLim*[1;0]]);
                    set(data.handles_audioShadingText2, 'string', sprintf(' t = %.3f s',endTime), 'position', [endTime, data.audioYLim*[1;0]]);
                    set(data.handles_audioShadingText3, 'string', sprintf('∆t = %d ms',round(1000*(endTime-startTime))), 'position', [endTime, data.audioYLim*[1;0]]);
                    data.handles_audioShadingText1_extent=[];
                    data.handles_audioShadingText2_extent=[];
                    data.handles_audioShadingText3_extent=[];
                    currentFrame = max(1, min(data.numFrames, ceil(refTime * data.FrameRate)));
                    currentFrameIndex = round(currentFrame);
                    frame = getframeCache(currentFrameIndex);
                    set(data.hVideo, 'CData', frame);
                end
        end
    end

end

function filteredAudio = filterMRINoise(audioSignal, audioFs, targetFreq)
% Comb filter: y(t) = x(t) - x(t-delay)
% optimized delay time to search between f0/2 and 2*f0
if nargin<3, targetFreq=55; end % target frequency (Hz) (range tested 22.5 to 110)
optimPeriod=nan;
optimValue=inf;
sample=(1:size(audioSignal,1))';
N=audioFs./targetFreq;
for nrepeat=1:4
    if nrepeat==1, tryperiods=linspace(N/2,2*N,64);
    elseif nrepeat==2, tryperiods=linspace(optimPeriod*(1-1.5/63),optimPeriod*(1+1.5/63),64);
    elseif nrepeat==3, tryperiods=linspace(optimPeriod*(1-2*1.5/63/63),optimPeriod*(1+2*1.5/63/63),64);
    else tryperiods=optimPeriod;
    end
    for PeriodInSamples=tryperiods,
        idx=PeriodInSamples;
        idx1=ceil(idx);
        idx2=idx1-idx;
        y=audioSignal;
        y(idx1+1:end)=y(idx1+1:end)-((1-idx2)*y(1:end-idx1)+idx2*y(2:end-idx1+1));
        Value=mean(mean(abs(y).^2,1));
        if Value<optimValue, optimPeriod=PeriodInSamples; optimValue=Value; end
    end
end
filteredAudio=y;
fprintf('Noise supression: noise fundamental frequency %sHz\n',mat2str(audioFs/optimPeriod,6));
end

% note: files from FLvoice (2025/02/01 version)
% consider integrating with FLvoice package in the future

function [P,t,f]=flvoice_spectrogram(s, fs, windowsize, windowoverlap, Nfft);
if nargin<5||isempty(Nfft), Nfft=pow2(nextpow2(fs/2)); end
S=flvoice_samplewindow(s(:), windowsize,windowoverlap,'none','same');
w=flvoice_hanning(size(S,1));
S=repmat(w,1,size(S,2)).*(S-repmat(mean(S,1),size(S,1),1));
S=abs(fft(S,max(Nfft,size(S,1)))).^2;
t=(0:size(S,2)-1)*(windowsize-windowoverlap)/fs;
f=(0:size(S,1)-1)*fs/size(S,1);
f=f(2:floor(size(S,1)/2));
S=S(2:floor(size(S,1)/2),:);
P=100+10*log10(2*S/fs/(w'*w)); % power spectrum in dB/Hz units
end

function [Y,idx_X,idxE]=flvoice_samplewindow(X, Wlength, Nlength, Type, Extent);
sX=[size(X),1];
if nargin<2 | isempty(Wlength), Wlength=sX(1); end 
if nargin<3 | isempty(Nlength), Nlength=floor(Wlength/2); end
if nargin<4 | isempty(Type), Type='none'; end
if nargin<5 | isempty(Extent), Extent='tight'; end
if lower(Type(1))=='c', docentering=1; Type=Type(2:end); else, docentering=0; end
prodsX=prod(sX(2:end));
switch(lower(Extent)),
case {'valid','tight'}, Base=0;
case 'same', Base=floor(Wlength/2);
otherwise, Base=Nlength;
end
X=cat(1,zeros([Base,sX(2:end)]),X,zeros([Wlength-Base-1,sX(2:end)]));
sY=1+floor((size(X,1)-Wlength)/(Wlength-Nlength));
idx_W=repmat((1:Wlength)',[1,sY]); 
idx_X=idx_W + repmat((Wlength-Nlength)*(0:sY-1),[Wlength,1]);
switch(lower(Type)),
case 'hamming',
    W=flvoice_hamming(Wlength);
case 'hanning',
    W=flvoice_hanning(Wlength);
case 'boxcar',
    W=ones(Wlength,1);
case 'triang',
    W=(1:Wlength)'/ceil(Wlength/2);
    W=min(W,2-W);
case 'none',
    W=ones(Wlength,1);
end
if docentering,
    k=Wlength-Nlength+1;
    h=flvoice_hamming(k); h=h/sum(h);
    e=convn(X.^2,h,'same');
    k2=Wlength;
    idx_k2=floor((Wlength-k2)/2)+(1:k2)';
    E=e(idx_X(idx_k2,:),:);%.*W(idx_W(:),ones(1,prod(sX(2:end))));
    E=reshape(E,[k2,sY,sX(2:end)]);
    [nill,idxE]=max(E,[],1);
    idx_X=max(1,min(size(X,1),idx_X+repmat(idxE-1+(idx_k2(1)-idx_k2(round(end/2))),[Wlength,1])));
end
if strcmp(lower(Type),'none'), Y=X(idx_X(:),:); else, Y=X(idx_X(:),:).*W(idx_W(:),ones(1,prod(sX(2:end)))); end
Y=reshape(Y,[Wlength,sY,sX(2:end)]);
idx_X=idx_X-Base;
idx_X(idx_X<=0 | idx_X>sX(1))=nan;
switch(lower(Extent)),
case {'valid','tight'},
    idx=~all(~isnan(idx_X),1);
    Y(:,idx,:)=[]; idx_X(:,idx)=[];
case 'same',
    idx=isnan(idx_X(1+floor(end/2),:));
    Y(:,idx,:)=[]; idx_X(:,idx)=[];
end
end

function w=flvoice_hanning(n)
if ~rem(n,2),%even
    w = .5*(1 - cos(2*pi*(1:n/2)'/(n+1))); 
    w=[w;flipud(w)];
else,%odd
   w = .5*(1 - cos(2*pi*(1:(n+1)/2)'/(n+1)));
   w = [w; flipud(w(1:end-1))];
end
end
function w=flvoice_hamming(n)
if ~rem(n,2),%even
    w = .54 - .46*cos(2*pi*(1:n/2)'/(n+1)); 
    w=[w;flipud(w)];
else,%odd
   w = .54 - .46*cos(2*pi*(1:(n+1)/2)'/(n+1));
   w = [w; flipud(w(1:end-1))];
end
end

function [w,t0,e]=harmonicRatio(s,fs,windowlength,overlaplength,ampthr)
if nargin<3||isempty(windowlength), windowlength=round(4.5/75*fs); end % from Praat: 4.5 times the minimum pitch (75Hz)
if nargin<4||isempty(overlaplength), overlaplength=windowlength-max(1,round(0.001*fs)); end
if nargin<5||isempty(ampthr), ampthr=0.1; end % from Praat: silence threshold
s2=flvoice_samplewindow(s(:),windowlength,overlaplength,'none','tight');
Nt=size(s2,2);
hwindow=flvoice_hanning(windowlength);
%valid=any(abs(s2)>ampthr*max(abs(s)),1);
%valid=mean(abs(s2)>ampthr*max(abs(s)),1)>.05;
s2=s2.*repmat(hwindow,[1,Nt]);
valid=any(abs(s2)>ampthr*max(abs(s)),1);
%valid=any(abs(s2)>ampthr,1);
t0=(windowlength/2+(windowlength-overlaplength)*(0:Nt-1)')/fs; % note: time of middle sample within window
f=min(2^nextpow2(2*windowlength-1):-1:1, 0:2^nextpow2(2*windowlength-1)-1);
%lowpass=0.03.^((f/800).^2);
%cc=real(ifft(abs(lowpass'.*fft(s2,2^nextpow2(2*windowlength-1))).^2));
cc=real(ifft(abs(fft(s2,2^nextpow2(2*windowlength-1))).^2));
cp=flipud(cumsum(s2.^2,1));
idx0=1:min(windowlength-1,ceil(.040*fs)); % remove delays above 40ms (<25Hz)
R=cc(idx0,:)./max(eps,sqrt(repmat(cc(1,:),numel(idx0),1).*cp(idx0,:))); % normalized cross-correlation
[w,idx]=max(R.*(cumsum(R<0,1)>0),[],1); % find maximum cross-correlation after removing first peak (up to first zero-crossing)
w3=R(max(1,min(size(R,1), repmat(idx,3,1)+repmat((-1:1)',1,numel(idx))))+(0:size(R,2)-1)*size(R,1)); % parabolic peak-height interpolation
w=((w>0).*max(0,min(1, w3(2,:)+(w3(1,:)-w3(3,:)).^2./(2*w3(2,:)-w3(3,:)-w3(1,:))/8)))';
e=cc(1,:)'/sum(hwindow);
w=w.*valid';
end