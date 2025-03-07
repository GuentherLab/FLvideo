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
                        set(data.handles_playButton, 'cdata', data.handles_icons{1});
                        set(data.handles_playSelectionButton,'cdata',data.handles_icons{3});
                        data.isPlaying = false; % Stop playback
                    end

                    % Update video and lines
                    % Update video frame
                    data.currentFrame=currentFrame ;
                    frame = getframeCache(currentFrame);
                    set(data.hVideo, 'CData', frame); % Update video frame

                    timeAtCurrentFrame = (currentFrame+[-1 -1 0 0]) / data.FrameRate; % note: displays time at midpoint of frame
                    set(data.handles_audioSelectedVideoframe, 'XData', timeAtCurrentFrame, 'YData', data.audioYLim([1 2 2 1]));
                    set(data.handles_otherSelecetedVideoframe1, 'XData', timeAtCurrentFrame, 'YData', data.otherYLim([1 2 2 1]));
                    set(data.handles_otherSelecetedVideoframe2, 'XData', timeAtCurrentFrame, 'YData', data.otherYLim([1 2 2 1]));
                    set([data.handles_audioCurrentPoint,data.handles_otherCurrentPoint1,data.handles_otherCurrentPoint2], 'XData', [], 'YData', []);
                    set(data.handles_audioCurrentPointText, 'string', sprintf(' t = %.3f s',mean(timeAtCurrentFrame)), 'position', [timeAtCurrentFrame(end), data.audioYLim*[1;0]]);
                    %set([data.handles_audioSelectedPoint,data.handles_otherSelectedPoint1,data.handles_otherSelectedPoint2], 'XData', [], 'YData', []);
                    %set(data.handles_audioSelectedPointText, 'string', sprintf(' t = %.3f s',mean(timeAtCurrentFrame)), 'position', [timeAtCurrentFrame(end), data.audioYLim*[1;0]]);
                    %data.handles_audioSelectedPointText_extent=[];
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
        selectspeed=5;      % default playback speed: 1x
        currentFrame=1;     % default videoframe displayed: 1
        layout=1;           % default layout: standard
        motionHighlight=1;  % default motion highlight: off
        cmapselect=3;       % default colormap: parula
        smoothing={0 0 0 0};  % default temporal smoothing: 0ms hanning window (note: in the same order as data.allPlotMeasures: velocity of motion, acoustic energy, acceleration, HNR)
        threshold={.20 .05 .20 .05};  % default height threshold (in percent of max units) (note: in the same order as data.allPlotMeasures: velocity of motion, acoustic energy, acceleration, HNR)
        videodisplay=2;     % default video-frame behavior: current frame follows mouse motion
        textgridTier=0;
        textgridTier_options={'none'};
        %audioSelectedPoint=[0 0 0 0];
        audioSelectedVideoframe=[0 0 0 0];
        %audioSelectedPointText={'',[0,0]};
        audioSelectedWindowText1={'',[0,0]};
        audioSelectedWindowText2={'',[0,0]};
        audioSelectedWindowText3={'',[0,0]};
        audioSignalSelect=1;% default audio: raw
        nplots=1;
        plotMeasure=[];
        zoomWindow=[];
        zoomin=false;
        isselected='off';
        % Create the main figure for video, audio, and controls
        if nargin<2, 
            hFig = figure('units','norm','Position', [.25, .1, .5, .8], 'MenuBar', 'none', 'NumberTitle', 'off', 'Name', 'Video Player','color','w', 'WindowButtonDownFcn', @(varargin)flvideo_buttonfcn('down',varargin{:}),'WindowButtonUpFcn',@(varargin)flvideo_buttonfcn('up',varargin{:}),'WindowButtonMotionFcn',@(varargin)flvideo_buttonfcn('motion',varargin{:}),'windowkeypressfcn',@(varargin)flvideo_keyfcn('press',varargin{:}),'windowkeyreleasefcn',@(varargin)flvideo_keyfcn('release',varargin{:}));
        else
            try selectspeed=get(data.handles_playbackspeed,'value'); end
            try, layout=get(data.handles_layout,'value'); end
            try, motionHighlight=get(data.handles_motionhighlight,'value'); end
            try, textgridTier=get(data.handles_textgridtier,'value')-1; end
            try, audioSignalSelect=get(data.handles_audiosignal,'value'); end
            try, nplots=numel(data.plotMeasure); end
            try, plotMeasure=get(data.handles_plotmeasure,'value'); end
            try, cmapselect=get(data.handles_colormap,'value'); end
            try, smoothing=get(data.handles_smoothing,'value'); end
            try, threshold=get(data.handles_threshold,'value'); end
            try, videodisplay=get(data.handles_videodisplay,'value'); end
        end
        if iscell(plotMeasure), plotMeasure=[plotMeasure{:}]; end
        if isequal(videoFile,0) % note: keep current file data
            audioSignal=data.audioSignalRaw;
            audioSignalDenoised=data.audioSignalDen;
            audioFs=data.SampleRate;
            frameCache=data.frameCache;
            FrameRate=data.FrameRate;
            numFrames=data.numFrames;
            currentFrame=data.currentFrame;
            totalDuration=data.totalDuration;
            XLim=data.XLim;
            textgridLabels=data.textgridLabels;
            textgridTier_options=data.textgridTier_options;
            NewData=true;
            ComputeDerivedMeasures=false;
            zoomWindow=data.zoomWindow;
            zoomin=data.zoomin;
            if ~isempty(zoomWindow), isselected='on'; end
            %audioSelectedPoint=get(data.handles_audioSelectedPoint,'xdata');
            %if isempty(audioSelectedPoint), audioSelectedPoint=[0 0 0 0]; end
            %audioSelectedPointText=get(data.handles_audioSelectedPointText,{'string','position'});
            audioSelectedWindowText1=get(data.handles_audioSelectedWindowText1,{'string','position'});
            audioSelectedWindowText2=get(data.handles_audioSelectedWindowText2,{'string','position'});
            audioSelectedWindowText3=get(data.handles_audioSelectedWindowText3,{'string','position'});
            audioSelectedVideoframe=get(data.handles_audioSelectedVideoframe,'xdata');
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
                        XLim = [0 totalDuration];

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
                        XLim = [0 totalDuration];

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
            textgridFile=[regexprep(videoFile,'\.[^\.]+$',''),'.TextGrid'];
            textgridLabels=[];
            textgridTier_options={'none'};
            textgridTier=0;
            if NewData&&~isempty(dir(textgridFile))
                try
                    fprintf('Reading TextGrid file %s\n',textgridFile);
                    out=flvoice_readTextGrid(textgridFile);
                    textgridTier_options=[{'none'}, out.label];
                    textgridTier=min(1,numel(out));
                    textgridLabels=struct('intervals',[],'labels',[]);
                    for n1=1:numel(out), 
                        textgridLabels(n1)=struct('intervals',[[out(n1).interval.t1]; [out(n1).interval.t2]],'labels',{regexprep({out(n1).interval.label},'.*','   $0   ')});
                    end
                catch me
                    errordlg([{'Problem reading TextGrid file:'} getReport(me,'basic','hyperlinks','off')], 'Video Player error');
                end
            end
        end
        if nargin>=2, 
            %set(hFig, 'name', 'Video Player');
            clf(hFig);
        end
        data.allPlotMeasures={'Velocity of Movements', 'Acoustic Energy', 'Acceleration of Movements', 'Audio HNR (Harmonic to Noise Ratio)', 'Audio Spectrogram'};
        
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
        data.handles_playButton=uicontrol('Style', 'pushbutton', 'tooltip', 'Play/Pause', 'Position', [350, 70, 40, 40], 'cdata', temp, ...
            'Callback', @(src, event) togglePlayPause(src, event, hFig), 'Parent', data.handles_buttonPanel);
        temp=imread(fullfile(fileparts(which(mfilename)),'icons','icon_paus.png')); temp=repmat(squeeze(mean(mean(reshape(double(temp)/255,16,32,16,32),1),3)),[1,1,3]); temp(temp==1)=nan; 
        data.handles_icons{2}=temp;

        temp=imread(fullfile(fileparts(which(mfilename)),'icons','icon_forw.png')); temp=repmat(squeeze(mean(mean(reshape(double(temp)/255,16,32,16,32),1),3)),[1,1,3]); temp(temp==1)=nan;
        uicontrol('Style', 'pushbutton', 'tooltip', 'Next Frame', 'Position', [390, 70, 40, 40], 'cdata', temp, ...
            'Callback', @(src, event) nextFrame(src, event, hFig), 'Parent', data.handles_buttonPanel);

        uicontrol('Style', 'text', 'String', 'Playback Speed', 'Position', [440, 80, 100, 20], 'horizontalalignment','right', 'Parent', data.handles_buttonPanel);
        data.handles_playbackspeed=uicontrol('Style', 'popupmenu', 'Value', 5, 'string', {'0.1x', '0.25x', '0.5x', '0.75x', '1x', '1.25x', '1.5x', '2x', '5x'}, 'value', selectspeed, 'Position', [550, 80, 180, 20], ...
            'Callback', @(src, event) adjustPlaybackSpeed(src, event, hFig), 'Parent', data.handles_buttonPanel);

        uicontrol('Style', 'text', 'String', 'Display Labels', 'Position', [440, 60, 100, 20], 'horizontalalignment','right', 'Parent', data.handles_buttonPanel);
        data.handles_textgridtier=uicontrol('Style', 'popupmenu', 'string', textgridTier_options, 'Value', textgridTier+1, 'tooltip','Selects tier to display from TextGrid labels file (if a .TextGrid file associated with the current .mp4 file exists)', 'Position', [550, 60, 180, 20], ...
            'Callback', @(src, event) changeTextgridTier(src, event, hFig), 'Parent', data.handles_buttonPanel);
        
        data.handles_layout=uicontrol('Style', 'popupmenu', 'string', {'standard', 'maximized (horizontal layout)', 'maximized (vertical layout)'}, 'Value', layout, 'tooltip', 'Select the desired GUI layout', 'Position', [550, 18, 180, 20], ...
            'Callback', @(src, event) changeLayout, 'Parent', data.handles_buttonPanel, 'visible','off');
        
        data.handles_colormap=uicontrol('Style', 'popupmenu', 'string', {'gray', 'jet', 'parula','hot','sky','bone','copper'}, 'Value', cmapselect, 'tooltip', 'Select colormap used when displaying the audio spectrogram', 'Position', [550, 18, 180, 20], ...
            'Callback', @(src, event) changeColormap(src, event, hFig), 'Parent', data.handles_buttonPanel, 'visible','off');
        
        smoothingnames={};
        for nsmoothing=1:numel(smoothing)
            data.handles_smoothing(nsmoothing)=uicontrol('Style', 'slider', 'Value', smoothing{nsmoothing}, 'tooltip','Smooths velocity/acceleration/energy/etc plots (minimum: no smoothing; maximum: 200ms hanning window)', 'Position', [550, 18, 180, 20], ...
            'Callback', @(src, event) changeSmoothing(nsmoothing), 'Parent', data.handles_buttonPanel, 'visible','off');
            try, addlistener(data.handles_smoothing(nsmoothing), 'ContinuousValueChange',@(varargin)changeSmoothing(nsmoothing)); end
            smoothingnames{nsmoothing}=['Smooth ',data.allPlotMeasures{nsmoothing}];
        end
        
        thresholdnames={};
        for nthreshold=1:numel(threshold)
            data.handles_threshold(nthreshold)=uicontrol('Style', 'slider', 'Value', threshold{nthreshold}, 'tooltip','Smooths velocity/acceleration/energy/etc plots (minimum: no threshold; maximum: 200ms hanning window)', 'Position', [550, 18, 180, 20], ...
            'Callback', @(src, event) changeThreshold(nthreshold), 'Parent', data.handles_buttonPanel, 'visible','off');
            try, addlistener(data.handles_threshold(nthreshold), 'ContinuousValueChange',@(varargin)changeThreshold(nthreshold)); end
            thresholdnames{nthreshold}=['Threshold ',data.allPlotMeasures{nthreshold}];
        end
        
        data.handles_motionhighlight=uicontrol('Style', 'popupmenu', 'string', {'off', 'on'}, 'Value', motionHighlight, 'tooltip','Highlights in red areas in the video with high motion velocity (or acceleration when displaying motion acceleration)', 'Position', [550, 18, 180, 20], ...
            'Callback', @(src, event) changeMotionHighlight(src, event, hFig), 'Parent', data.handles_buttonPanel, 'visible','off');
        
        data.handles_videodisplay=uicontrol('Style', 'popupmenu', 'string', {'follow mouse clicks', 'follow mouse position'}, 'Value', videodisplay, 'tooltip','<html>Select <i>mouse click</i> to have the displayed video frame change when clicking a timepoint in any of the plots<br/>Select <i>mouse position</i> to have the displayed video frame change when hovering over any of the plots</html>', 'Position', [550, 18, 180, 20], ...
            'Callback', @(src, event) changeFrameMotion(src, event, hFig), 'Parent', data.handles_buttonPanel, 'visible','off');
        
        uicontrol('Style', 'text', 'String', 'Settings', 'Position', [440, 40, 100, 20], 'horizontalalignment','right', 'Parent', data.handles_buttonPanel);
        data.handles_settings=uicontrol('Style', 'popupmenu', 'string', {'          ', 'GUI Layout', 'Video display', 'Spectrogram color', 'Highlight motion in video', smoothingnames{:}, thresholdnames{:}}, 'Value', 1, 'Position', [550, 40, 180, 20], ...
            'Callback', @changeGuiOptions, 'Parent', data.handles_buttonPanel, 'userdata',[data.handles_layout, data.handles_videodisplay, data.handles_colormap, data.handles_motionhighlight, data.handles_smoothing, data.handles_threshold]);
        
        % Bottom row: Selection and save controls
        uicontrol('Style', 'pushbutton', 'String', 'Select Window', 'tooltip','<HTML>Select a window between two timepoints<br/>Alternatively, click-and-drag in any of the plot displays to select a window</HTML>', 'Position', [20, 20, 210, 40], 'foregroundcolor','b', ...
            'Callback', @(src, event) selectPoints(hFig), 'Parent', data.handles_buttonPanel, 'enable',isready);

        temp=imread(fullfile(fileparts(which(mfilename)),'icons','icon_save.png')); temp=repmat(squeeze(mean(mean(reshape(double(temp)/255,20,32,20,32),1),3)),[1,1,3]); temp(temp==1)=nan; temp(:,:,3)=1;
        data.handles_saveclipButton = uicontrol('Style', 'pushbutton', 'tooltip', 'Save Clip with video within selected window', 'Position', [310, 20, 40, 40], 'cdata', temp, ...
            'Callback', @(src, event) saveClip(hFig), 'Parent', data.handles_buttonPanel, 'enable',isselected);

        temp=imread(fullfile(fileparts(which(mfilename)),'icons','icon_play.png')); temp=repmat(squeeze(mean(mean(reshape(double(temp)/255,16,32,16,32),1),3)),[1,1,3]); temp(temp==1)=nan; temp(:,:,3)=1;
        data.handles_icons{3}=temp;
        data.handles_playSelectionButton = uicontrol('Style', 'pushbutton', 'tooltip', 'Play/Pause video within selected window', 'cdata', temp, ...
            'Position', [350, 20, 40, 40], 'Enable', isselected, ...
            'Callback', @(src, event) playSelection(hFig), 'Parent', data.handles_buttonPanel);
        temp=imread(fullfile(fileparts(which(mfilename)),'icons','icon_paus.png')); temp=repmat(squeeze(mean(mean(reshape(double(temp)/255,16,32,16,32),1),3)),[1,1,3]); temp(temp==1)=nan; temp(:,:,3)=1;
        data.handles_icons{4}=temp;

        temp=imread(fullfile(fileparts(which(mfilename)),'icons','icon_zoomin.png')); temp=repmat(squeeze(mean(mean(reshape(double(temp)/255,20,32,20,32),1),3)),[1,1,3]); temp(temp==1)=nan; temp(:,:,3)=1;
        data.handles_icons{5}=temp;
        data.handles_zoomButton=uicontrol('Style', 'pushbutton', 'tooltip', 'Zoom In/Out of selected window', 'Position', [390, 20, 40, 40], 'cdata', temp, ...
            'Callback', @(src, event) zoomIn([],true), 'Parent', data.handles_buttonPanel, 'enable',isselected);
        temp=imread(fullfile(fileparts(which(mfilename)),'icons','icon_zoomout.png')); temp=repmat(squeeze(mean(mean(reshape(double(temp)/255,20,32,20,32),1),3)),[1,1,3]); temp(temp==1)=nan; temp(:,:,3)=1;
        data.handles_icons{6}=temp;
        
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
            hVideo = imshow(frameCache{currentFrame}, 'Parent', data.handles_videoPanel); % Placeholder for video frame
            %disp(hVideo); % Display information about the hVideo object
            axis(data.handles_videoPanel, 'off'); % Hide axis lines and labels
            title(data.handles_videoPanel, 'Video Playback', 'Color', 'w');

            [data.handles_plotmeasure, data.handles_otherPanel1,data.handles_otherPlot1,data.handles_otherCurrentPoint1,data.handles_otherSelecetedVideoframe1,data.handles_otherSelectedWindow1,data.handles_otherThreshold,data.handles_otherSegments,...
                                       data.handles_otherPanel2,data.handles_otherPlot2,data.handles_otherCurrentPoint2,data.handles_otherSelecetedVideoframe2,data.handles_otherSelectedWindow2]=deal([]);
            for nplot=1:nplots
                if numel(plotMeasure)<nplot, 
                    newMeasure=1;
                    try, newMeasure=find(~ismember(1:numel(data.allPlotMeasures), plotMeasure),1); end
                    plotMeasure(nplot)=max([1 newMeasure]);
                end
                % Create a dedicated axes for all other plots (for timeseries displays); related handles = data.handles_otherPanel1/2, data.handles_otherPlot1/2, data.handles_otherShading1/2, data.handles_plotmeasure
                data.handles_otherPanel1(nplot) = axes('Position', [1 nplot]*[0.1, 0.5-0.30/(1+nplots*1.5), 0.8, 0.30/(1+nplots*1.5); 0 -0.30*1.5/(1+nplots*1.5) 0 0], 'Parent', hFig);
                data.handles_otherPlot1(nplot) = plot((1:numFrames-1)/FrameRate, zeros(1,numFrames-1), 'g','parent',data.handles_otherPanel1(nplot));
                data.handles_otherThreshold(nplot) = line([0 totalDuration],[0 0]+threshold{nplot},'LineStyle','-','color',.75*[1 1 1],'visible','off','parent',data.handles_otherPanel1(nplot));
                data.handles_otherSegments(nplot) = patch([0 0 0 0], [0 0 0 0], 'k','edgecolor','none','facecolor','k','facealpha',0.1, 'parent',data.handles_otherPanel1(nplot));
                %data.handles_otherSelectedPoint1(nplot) = patch(audioSelectedPoint, otherYLim([1 2 2 1]), 'k', 'edgecolor', 'k', 'facecolor', 'none','linestyle',':','parent',data.handles_otherPanel1(nplot)); % Black line for last-clicked pointer position
                data.handles_otherCurrentPoint1(nplot) = patch([0 0 0 0], [0 0 0 0], 'k', 'edgecolor', 'k', 'facecolor', 'none','linestyle',':','parent',data.handles_otherPanel1(nplot)); % Black line for pointer position
                data.handles_otherSelecetedVideoframe1(nplot) = patch(audioSelectedVideoframe, otherYLim([1 2 2 1]), 'r', 'edgecolor', 'none', 'facealpha', .5,'parent',data.handles_otherPanel1(nplot)); % Red line for current frame
                if isempty(zoomWindow), data.handles_otherSelectedWindow1(nplot) = patch([0 0 0 0],[0 0 0 0],'blue', 'FaceAlpha', 0.05, 'EdgeColor', 'none','parent',data.handles_otherPanel1(nplot));
                else data.handles_otherSelectedWindow1(nplot) = patch(zoomWindow([1 1 2 2]),otherYLim([1 2 2 1]),'blue', 'FaceAlpha', 0.05, 'EdgeColor', 'none','parent',data.handles_otherPanel1(nplot));        
                end
                xlim(data.handles_otherPanel1(nplot), XLim); % Set x-axis limits based on video duration
                if nplot==nplots, xlabel(data.handles_otherPanel1(nplot), 'Time (s)'); 
                else set(data.handles_otherPanel1(nplot),'xticklabel',[]);
                end
                set(data.handles_otherPanel1(nplot), 'xcolor', .5*[1 1 1], 'ycolor', .5*[1 1 1],'box','off');

                % Create a dedicated axes for all other plots (for image displays)
                data.handles_otherPanel2(nplot) = axes('Position', [1 nplot]*[0.1, 0.5-0.30/(1+nplots*1.5), 0.8, 0.30/(1+nplots*1.5); 0 -0.30*1.5/(1+nplots*1.5) 0 0], 'Parent', hFig);
                data.handles_otherPlot2(nplot) = image([],'parent',data.handles_otherPanel2(nplot));
                %data.handles_otherSelectedPoint2(nplot) = patch(audioSelectedPoint, otherYLim([1 2 2 1]), 'k', 'edgecolor', 'k', 'facecolor', 'none','linestyle',':','parent',data.handles_otherPanel2(nplot)); % Black line for last-clicked pointer position
                data.handles_otherCurrentPoint2(nplot) = patch([0 0 0 0], [0 0 0 0], 'k', 'edgecolor', 'k', 'facecolor', 'none','linestyle',':','parent',data.handles_otherPanel2(nplot)); % Black line for pointer position
                data.handles_otherSelecetedVideoframe2(nplot) = patch(audioSelectedVideoframe, otherYLim([1 2 2 1]), 'r', 'edgecolor', 'none', 'facealpha', .5,'parent',data.handles_otherPanel2(nplot)); % Red line for current frame
                if isempty(zoomWindow), data.handles_otherSelectedWindow2(nplot) = patch([0 0 0 0],[0 0 0 0],'blue', 'FaceAlpha', 0.05, 'EdgeColor', 'none','parent',data.handles_otherPanel2(nplot));
                else data.handles_otherSelectedWindow2(nplot) = patch(zoomWindow([1 1 2 2]),otherYLim([1 2 2 1]),'blue', 'FaceAlpha', 0.05, 'EdgeColor', 'none','parent',data.handles_otherPanel2(nplot));        
                end
                xlim(data.handles_otherPanel2(nplot), XLim); % Set x-axis limits based on video duration
                if nplot==nplots, xlabel(data.handles_otherPanel2(nplot), 'Time (s)'); 
                else set(data.handles_otherPanel2(nplot),'xticklabel',[]);
                end
                %ylabel(data.handles_otherPanel2, 'Frequency (Hz)'); % note: change later when adding more plots
                set(data.handles_otherPanel2(nplot), 'xcolor', .5*[1 1 1], 'ycolor', .5*[1 1 1],'box','off');

                data.handles_plotmeasure(nplot)=uicontrol('Style', 'popupmenu', 'string', data.allPlotMeasures, 'Value', plotMeasure(nplot), 'units','norm','Position', [1 nplot]*[0.35, 0.5, 0.3, .03; 0  -0.30*1.5/(1+nplots*1.5) 0 0], 'Callback', @(src, event) changePlotMeasure(src, event, hFig), 'Parent', hFig);
            end
            data.handles_plotmeasure_add=uicontrol('Style', 'pushbutton', 'string', '+', 'tooltip','Add new plot to display', 'units','norm','Position', [0.91, 0.5-0.30, 0.02, 0.02], 'Callback', @(src, event) addPlotMeasure(src, event, hFig), 'Parent', hFig);
            data.handles_plotmeasure_del=uicontrol('Style', 'pushbutton', 'string', '-', 'tooltip','Remove this plot from display', 'units','norm','Position', [0.93, 0.5-0.30, 0.02, 0.02], 'Callback', @(src, event) delPlotMeasure(src, event, hFig), 'Parent', hFig);
            if nplots==0, set(data.handles_plotmeasure_del,'visible','off'); end
            if nplots>1&&nplots>=numel(data.allPlotMeasures), set(data.handles_plotmeasure_add,'visible','off'); end

            % Create a dedicated axes for the audio signal
            data.handles_audioPanel = axes('Position', [1 0]*[0.1, 0.5-0.30/(1+nplots*1.5), 0.8, 0.30/(1+nplots*1.5); 0 -0.30*1.5/(1+nplots*1.5) 0 0], 'Parent', hFig); % Move audio panel upward
            data.handles_audioPlot = plot((0:length(audioSignal)-1)/audioFs, audioSignal(:,1), 'b', 'Parent', data.handles_audioPanel); % Plot full audio signal
            %data.handles_audioSelectedPoint = patch(data.handles_audioPanel,audioSelectedPoint, audioYLim([1 2 2 1]), 'k', 'edgecolor', 'k', 'facecolor', 'none','linestyle',':'); % Black line for last-clicked mouse position
            data.handles_audioCurrentPoint = patch(data.handles_audioPanel, [0 0 0 0], [0 0 0 0], 'k', 'edgecolor', 'k', 'facecolor', 'none','linestyle',':'); % Black line for mouse position
            data.handles_audioCurrentPointText = text(0,0,'','color','k','horizontalalignment','left','verticalalignment','bottom','parent',data.handles_audioPanel);
            if isempty(textgridLabels)||textgridTier==0, 
                textgridTier=0;
                data.handles_audioLabelsInterval = [];
                data.handles_audioLabelsText=[];
                data.handles_audioLabelsText_extent = [];
            else 
                data.handles_audioLabelsInterval = patch(data.handles_audioPanel, ... % patch for TextGrid intervals
                    'vertices',[reshape([textgridLabels(textgridTier).intervals;flipud(textgridLabels(textgridTier).intervals)],[],1), reshape([1 0; 1 0; 0 1; 0 1]*audioYLim'*ones(1,size(textgridLabels(textgridTier).intervals,2)),[],1)], ...
                    'faces', reshape(1:4*size(textgridLabels(textgridTier).intervals,2),4,[])', ...
                    'facevertexalpha', [zeros(size(textgridLabels(textgridTier).intervals,2),1)], ...
                    'facecolor','y','edgecolor',[.85 .85 .85],'facealpha','flat','AlphaDataMapping','none'); 
                data.handles_audioLabelsText = text(mean(textgridLabels(textgridTier).intervals,1),[0 1]*audioYLim'*ones(1,size(textgridLabels(textgridTier).intervals,2)),textgridLabels(textgridTier).labels,'color',[.75 .75 .75], 'horizontalalignment','center','verticalalignment','top','parent',data.handles_audioPanel); % text for TextGrid intervals
                data.handles_audioLabelsText_extent = [];
                data.handles_audioLabelsText_fontsize = get(0,'DefaultAxesFontSize');
            end
            data.handles_audioSelectedVideoframe = patch(data.handles_audioPanel, audioSelectedVideoframe, audioYLim([1 2 2 1]), 'r', 'edgecolor', 'none', 'facealpha', .5); % Red line for current frame
            if isempty(zoomWindow), data.handles_audioSelectedWindow = patch([0 0 0 0],[0 0 0 0],'blue', 'FaceAlpha', 0.1, 'EdgeColor', 'none'); 
            else data.handles_audioSelectedWindow = patch(zoomWindow([1 1 2 2]),audioYLim([1 2 2 1]),'blue', 'FaceAlpha', 0.1, 'EdgeColor', 'none');        
            end
            %data.handles_audioSelectedPointText = text(0,0,'','color','k','horizontalalignment','left','verticalalignment','bottom','parent',data.handles_audioPanel); set(data.handles_audioSelectedPointText,{'string','position'},audioSelectedPointText); 
            data.handles_audioSelectedWindowText1 = text(0,0,'','color','b','horizontalalignment','right','verticalalignment','bottom','parent',data.handles_audioPanel); set(data.handles_audioSelectedWindowText1,{'string','position'},audioSelectedWindowText1); 
            data.handles_audioSelectedWindowText2 = text(0,0,'','color','b','horizontalalignment','left','verticalalignment','bottom','parent',data.handles_audioPanel); set(data.handles_audioSelectedWindowText2,{'string','position'},audioSelectedWindowText2); 
            data.handles_audioSelectedWindowText3 = text(0,0,'','color','b','horizontalalignment','left','verticalalignment','top','parent',data.handles_audioPanel); set(data.handles_audioSelectedWindowText3,{'string','position'},audioSelectedWindowText3); 
            xlim(data.handles_audioPanel, XLim); % Set x-axis limits based on audio duration
            ylim(data.handles_audioPanel, audioYLim); % Apply y-limits for the audio plot
            %xlabel(data.handles_audioPanel, 'Time (s)');
            %ylabel(data.handles_audioPanel, 'Audio Signal Intensity');
            %title(data.handles_audioPanel, 'Audio Signal with Current Frame');
            set(data.handles_audioPanel, 'xcolor', .5*[1 1 1], 'ycolor', .5*[1 1 1], 'box','off');
            if nplots==0, xlabel(data.handles_audioPanel, 'Time (s)');
            else set(data.handles_audioPanel,'xtick',[],'xticklabel',[]);
            end
            data.handles_audiosignal=uicontrol('Style', 'popupmenu', 'string', {'raw Audio Signal','MRI denoised Audio Signal'}, 'Value', audioSignalSelect, 'units','norm','Position', [0.35, 0.5, 0.3, 0.03], 'Callback', @(src, event) changeAudioSignal(src, event, hFig), 'Parent', hFig);

            % Store information in shared "data" variable
            data.isPlaying = false;
            data.currentFrame = currentFrame; % Start at the first frame
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
            data.textgridLabels = textgridLabels;
            data.motionHighlight = motionHighlight;
            data.textgridTier = textgridTier;
            data.textgridTier_options = textgridTier_options; 
            data.plotMeasure = plotMeasure;
            data.audioSignalSelect = audioSignalSelect;
            data.layout = layout;
            data.colormap=parula(256);
            data.videodisplay=videodisplay;
            data.smoothing=smoothing;
            data.threshold=threshold;
            data.maxsmoothing=0.200; % maximum smoothing (in seconds, hanning window length)
            data.XLim = XLim;
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
            zoomIn(data.XLim);
            changeLayout();
            set(data.handles_hFig,'windowstyle','modal'); drawnow nocallbacks; set(data.handles_hFig,'windowstyle','normal'); % note: fixes Matlab issue loosing focus on figure handle
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
        if numel(data.plotMeasure)>1&&numel(data.plotMeasure)>=numel(data.allPlotMeasures),return; end
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
            set(data.handles_playButton, 'cdata', data.handles_icons{2}); 
            zoomIn(false);
            play(data.audioPlayer, [startSample, length(data.audioSignal)]);
            if data.SampleQueue==0, data.SampleQueue=data.audioPlayer.CurrentSample-startSample; disp(data.SampleQueue); end
            mainLoop();
        else
            % Pause audio playback
            set(data.handles_playButton, 'cdata', data.handles_icons{1}); 
            pause(data.audioPlayer);
        end

    end

    function nextFrame(~, ~, hFig)
        if ~isfield(data,'audioPlayer'), return; end
        if ~data.isPlaying,
            if data.currentFrame < data.numFrames
                data.currentFrame = data.currentFrame + 1;
                frame = getframeCache(data.currentFrame);
                set(data.hVideo, 'CData', frame);
                timeAtCurrentFrame = (data.currentFrame+[-1 -1 0 0]) / data.FrameRate;
                set(data.handles_audioSelectedVideoframe, 'XData', timeAtCurrentFrame, 'YData', data.audioYLim([1 2 2 1]));
                set(data.handles_otherSelecetedVideoframe1, 'XData', timeAtCurrentFrame, 'YData', data.otherYLim([1 2 2 1]));
                set(data.handles_otherSelecetedVideoframe2, 'XData', timeAtCurrentFrame, 'YData', data.otherYLim([1 2 2 1]));
                %set([data.handles_audioSelectedPoint,data.handles_otherSelectedPoint1,data.handles_otherSelectedPoint2], 'XData', [], 'YData', []);
                %set(data.handles_audioSelectedPointText, 'string', sprintf(' t = %.3f s',mean(timeAtCurrentFrame)), 'position', [timeAtCurrentFrame(end), data.audioYLim*[1;0]]);
                %data.handles_audioSelectedPointText_extent=[];

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
                frame = getframeCache(data.currentFrame);
                set(data.hVideo, 'CData', frame);
                timeAtCurrentFrame = (data.currentFrame+[-1 -1 0 0]) / data.FrameRate;
                set(data.handles_audioSelectedVideoframe, 'XData', timeAtCurrentFrame, 'YData', data.audioYLim([1 2 2 1]));
                set(data.handles_otherSelecetedVideoframe1, 'XData', timeAtCurrentFrame, 'YData', data.otherYLim([1 2 2 1]));
                set(data.handles_otherSelecetedVideoframe2, 'XData', timeAtCurrentFrame, 'YData', data.otherYLim([1 2 2 1]));
                %set([data.handles_audioSelectedPoint,data.handles_otherSelectedPoint1,data.handles_otherSelectedPoint2], 'XData', [], 'YData', []);
                %set(data.handles_audioSelectedPointText, 'string', sprintf(' t = %.3f s',mean(timeAtCurrentFrame)), 'position', [timeAtCurrentFrame(end), data.audioYLim*[1;0]]);
                %data.handles_audioSelectedPointText_extent=[];
                drawnow;
            end
        end
    end

    function thisFrame(thisTime)
        if ~isfield(data,'audioPlayer'), return; end
        if nargin<1||isempty(thisTime), thisTime=get(gca,'currentpoint'); end
        if ~data.isPlaying,
            data.currentFrame = round(max(1, min(data.numFrames, ceil(thisTime(1) * data.FrameRate))));
            frame = getframeCache(data.currentFrame);
            set(data.hVideo, 'CData', frame);
            str=sprintf('t = %.3f s',thisTime(1));
            clipboard('copy', str);
            fprintf('%s copied to clipboard\n',str);
            timeAtCurrentFrame = (data.currentFrame+[-1 -1 0 0]) / data.FrameRate;
            set(data.handles_audioSelectedVideoframe, 'XData', timeAtCurrentFrame, 'YData', data.audioYLim([1 2 2 1]));
            set(data.handles_otherSelecetedVideoframe1, 'XData', timeAtCurrentFrame, 'YData', data.otherYLim([1 2 2 1]));
            set(data.handles_otherSelecetedVideoframe2, 'XData', timeAtCurrentFrame, 'YData', data.otherYLim([1 2 2 1]));
            %set(data.handles_audioSelectedPoint, 'XData', thisTime(1)+[0 0 0 0], 'YData', data.audioYLim([1 2 2 1]));
            %set(data.handles_otherSelectedPoint1, 'XData', thisTime(1)+[0 0 0 0], 'YData', data.otherYLim([1 2 2 1]));
            %set(data.handles_otherSelectedPoint2, 'XData', thisTime(1)+[0 0 0 0], 'YData', data.otherYLim([1 2 2 1]));
            %set(data.handles_audioSelectedPointText, 'string', sprintf(' t = %.3f s',thisTime(1)), 'position', [thisTime(1), data.audioYLim*[1;0]]);
            %data.handles_audioSelectedPointText_extent=[];
            drawnow;
        end
    end

    function rewindVideo(~, ~, hFig)
        if ~isfield(data,'audioPlayer'), return; end
        if ~data.isPlaying,
            data.currentFrame = 1;
            frame = getframeCache(data.currentFrame);
            set(data.hVideo, 'CData', frame);
            timeAtCurrentFrame = (data.currentFrame+[-1 -1 0 0]) / data.FrameRate;
            set(data.handles_audioSelectedVideoframe, 'XData', timeAtCurrentFrame, 'YData', data.audioYLim([1 2 2 1]));
            set(data.handles_otherSelecetedVideoframe1, 'XData', timeAtCurrentFrame, 'YData', data.otherYLim([1 2 2 1]));
            set(data.handles_otherSelecetedVideoframe2, 'XData', timeAtCurrentFrame, 'YData', data.otherYLim([1 2 2 1]));
            %set([data.handles_audioSelectedPoint,data.handles_otherSelectedPoint1,data.handles_otherSelectedPoint2], 'XData', [], 'YData', []);
            %set(data.handles_audioSelectedPointText, 'string', sprintf(' t = %.3f s',mean(timeAtCurrentFrame)),  'position', [timeAtCurrentFrame(end), data.audioYLim*[1;0]]);
            %data.handles_audioSelectedPointText_extent=[];
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

    function zoomIn(state,animation)
        if nargin<2||isempty(animation), animation=false; end
        bakxlim=data.XLim; %get(data.handles_audioPanel,'xlim');
        if nargin<1||isempty(state), state=[]; data.zoomin=~data.zoomin;
        elseif numel(state)==2 % explicit zoom
            state(1)=max(0,state(1));
            state(2)=min(data.totalDuration,state(2));
            data.zoomin=~isequal(state, [0 data.totalDuration]);
            if diff(state)<.001, return; end
        else data.zoomin=state;
        end
        if numel(state)==2
            if data.textgridTier>0, set(data.handles_audioLabelsText(mean(data.textgridLabels(data.textgridTier).intervals,1)>state(1)&mean(data.textgridLabels(data.textgridTier).intervals,1)<state(2)),'visible','on'); end
            data.XLim=state;
            xlim([data.handles_audioPanel,data.handles_otherPanel1,data.handles_otherPanel2], state);
            if data.zoomin, set(data.handles_zoomButton,'cdata',data.handles_icons{6});
            else set(data.handles_zoomButton,'cdata',data.handles_icons{5});
            end
        else
            switch(data.zoomin)
                case 1, % zoom in
                    startTime = data.zoomWindow(1);
                    endTime = data.zoomWindow(2);
                    set(data.handles_zoomButton,'cdata',data.handles_icons{6});
                    xfactor=.1;
                    if data.textgridTier>0, set(data.handles_audioLabelsText(mean(data.textgridLabels(data.textgridTier).intervals,1)<startTime|mean(data.textgridLabels(data.textgridTier).intervals,1)>endTime),'visible','off'); end
                    data.XLim=[max(0,startTime-xfactor*(endTime-startTime)) min(data.totalDuration,endTime+xfactor*(endTime-startTime))];
                    if animation,
                        for k=[1/2 1/4 1/8 0]
                            xlim([data.handles_audioPanel,data.handles_otherPanel1,data.handles_otherPanel2], k*bakxlim+(1-k)*[max(0,startTime-xfactor*(endTime-startTime)) min(data.totalDuration,endTime+xfactor*(endTime-startTime))]);
                            drawnow;
                        end
                    else
                        xlim([data.handles_audioPanel,data.handles_otherPanel1,data.handles_otherPanel2], data.XLim);
                    end
                case 0, % full zoom out
                    set(data.handles_zoomButton,'cdata',data.handles_icons{5});
                    set(data.handles_audioLabelsText,'visible','on');
                    data.XLim=[0 data.totalDuration];
                    if animation,
                        bakxlim=get(data.handles_audioPanel,'xlim');
                        for k=[1/2 1/4 1/8 0]
                            xlim([data.handles_audioPanel, data.handles_otherPanel1, data.handles_otherPanel2], k*bakxlim+(1-k)*[0 data.totalDuration]);
                            drawnow;
                        end
                    else
                        xlim([data.handles_audioPanel, data.handles_otherPanel1, data.handles_otherPanel2], data.XLim);
                    end
            end
        end
        %data.handles_audioSelectedPointText_extent=[];
        data.handles_audioSelectedWindowText1_extent=[];
        data.handles_audioSelectedWindowText2_extent=[];
        data.handles_audioSelectedWindowText3_extent=[];
        data.handles_audioLabelsText_extent=[];
    end

    function changeGuiOptions(~,~,hFig)
        i1=get(gcbo,'value')-1;         
        % makes associated menu visible
        val=get(gcbo,'userdata'); 
        set(val,'visible','off'); 
        if i1, 
            set(val(i1),'visible','on'); 
            % menu-specific options
            optionNames=get(gcbo,'string');
            switch(optionNames{i1+1}),
                case 'Highlight motion in video' % switches off/on Motion highlight value
                    set(val(i1),'value',1+mod(get(val(i1),'value'),numel(get(val(i1),'string'))));
                    changeMotionHighlight();
            end
        end
    end

    function changeMotionHighlight(~, ~, hFig);
        data.motionHighlight=get(data.handles_motionhighlight,'value');
        if data.motionHighlight==2, fprintf('Motion highlight on\n')
        else fprintf('Motion highlight off\n')
        end
        if isfield(data,'hVideo'), set(data.hVideo, 'CData', getframeCache(data.currentFrame)); end
    end

    function changeFrameMotion(~, ~, hFig);
        data.videodisplay=get(data.handles_videodisplay,'value');
        if data.videodisplay==2, fprintf('Video frame displayed follows mouse position\n')
        else fprintf('Video frame displayed follows mouse clicks\n')
        end
        if isfield(data,'hVideo'), set(data.hVideo, 'CData', getframeCache(data.currentFrame)); end
    end
    
    
    function changeTextgridTier(~, ~, hFig);
        data.textgridTier=get(data.handles_textgridtier,'value')-1;
        if isfield(data,'globalMotionVel'), initialize(0,data.handles_hFig); end
    end

    function changeColormap(~, ~, hFig);
        colormaps={1-gray(256),jet(256),parula(256),hot(256),sky(256),flipud(bone(256)),copper(256)};
        data.colormap=colormaps{get(data.handles_colormap,'value')};
        %set(data.handles_hFig,'colormap',data.colormap);
        if isfield(data,'globalMotionVel'), changePlotMeasure(); end
    end

    function changeSmoothing(nsmoothing)
        data.smoothing{nsmoothing}=get(data.handles_smoothing(nsmoothing),'value');
        switch(data.allPlotMeasures{nsmoothing})
            case 'Velocity of Movements'
                data.globalMotionVel_smoothed=[];
            case 'Acoustic Energy', 
                if isfield(data,'harmonicRatio')&&~isempty(data.harmonicRatio),
                    [data.harmonicRatio.E1_smoothed, data.harmonicRatio.E2_smoothed]=deal([]);
                end
            case 'Acceleration of Movements', 
                data.globalMotionAcc_smoothed=[];
            case 'Audio HNR (Harmonic to Noise Ratio)'
                if isfield(data,'harmonicRatio')&&~isempty(data.harmonicRatio),
                    [data.harmonicRatio.P1_smoothed, data.harmonicRatio.P2_smoothed]=deal([]);
                end
        end
        if isfield(data,'globalMotionVel'), 
            if data.smoothing{nsmoothing}>0, fprintf('Smooths %s with %dms hanning window (use SHIFT + left-click to select local maxima)\n', data.allPlotMeasures{nsmoothing},round(1000*data.maxsmoothing*data.smoothing{nsmoothing}));
            else fprintf('Displays raw/unsmoothed %s\n',data.allPlotMeasures{nsmoothing});
            end
            changePlotMeasure(); 
        end
    end

    function changeThreshold(nthreshold)
        data.threshold{nthreshold}=get(data.handles_threshold(nthreshold),'value');
        switch(data.allPlotMeasures{nthreshold})
            case 'Velocity of Movements'
                data.globalMotionVel_thresholded=[];
            case 'Acoustic Energy', 
                if isfield(data,'harmonicRatio')&&~isempty(data.harmonicRatio),
                    [data.harmonicRatio.E1_thresholded, data.harmonicRatio.E2_thresholded]=deal([]);
                end
            case 'Acceleration of Movements', 
                data.globalMotionAcc_thresholded=[];
            case 'Audio HNR (Harmonic to Noise Ratio)'
                if isfield(data,'harmonicRatio')&&~isempty(data.harmonicRatio),
                    [data.harmonicRatio.P1_thresholded, data.harmonicRatio.P2_thresholded]=deal([]);
                end
        end
        if isfield(data,'globalMotionVel'), 
            if ismac, ALT='OPTION'; else ALT='ALT'; end
            if data.threshold{nthreshold}>0, fprintf('Display timepoints when %s crosses %d%% of maximum value (use %s + left-click to select these boundary timepoints)\n', data.allPlotMeasures{nthreshold},round(100*data.threshold{nthreshold}),ALT);
            else fprintf('Displays raw/unthresholded %s\n',data.allPlotMeasures{nthreshold});
            end
            changePlotMeasure(); 
        end
    end

    function changePlotMeasure(~, ~, hFig);
        nplots=numel(data.handles_plotmeasure);
        data.plotMeasure=get(data.handles_plotmeasure,'value');
        if iscell(data.plotMeasure), data.plotMeasure=[data.plotMeasure{:}]; end
        if isfield(data,'globalMotionVel'), 
            for nplot=1:nplots
                if ismember(data.allPlotMeasures{data.plotMeasure(nplot)},{'Velocity of Movements', 'Acoustic Energy', 'Acceleration of Movements', 'Audio HNR (Harmonic to Noise Ratio)'}) % plots
                    if ismember(data.allPlotMeasures{data.plotMeasure(nplot)},{'Acoustic Energy', 'Audio HNR (Harmonic to Noise Ratio)'})&&(~isfield(data,'harmonicRatio')||isempty(data.harmonicRatio))
                        hwindowsize=3/75;
                        [data.harmonicRatio.P1,data.harmonicRatio.t,data.harmonicRatio.E1]=harmonicRatio(data.audioSignalRaw,data.SampleRate,round(hwindowsize*data.SampleRate),round((hwindowsize-.001)*data.SampleRate), 0.10);
                        [data.harmonicRatio.P2,data.harmonicRatio.t,data.harmonicRatio.E2]=harmonicRatio(data.audioSignalDen,data.SampleRate,round(hwindowsize*data.SampleRate),round((hwindowsize-.001)*data.SampleRate), 0.10);
                        data.harmonicRatio.E1 = sqrt(max(0,data.harmonicRatio.E1)); % MS to RMS
                        data.harmonicRatio.E2 = sqrt(max(0,data.harmonicRatio.E2)); % MS to RMS
                        data.harmonicRatio.P1 = -10*log10(1e-1)+10*log10(max(1e-1,data.harmonicRatio.P1./max(eps,1-data.harmonicRatio.P1))); % HR to HNR
                        data.harmonicRatio.P2 = -10*log10(1e-1)+10*log10(max(1e-1,data.harmonicRatio.P2./max(eps,1-data.harmonicRatio.P2))); % HR to HNR
                        data.harmonicRatio.SampleRate=1/median(diff(data.harmonicRatio.t));
                    end
                    [plotdataX, plotdataY, plotdataT,ischanged] = getMeasure(data.plotMeasure(nplot)); % gets measure timeseries (+optional smoothing & thresholding)
                    set(data.handles_otherPlot1(nplot),'xdata',plotdataX,'ydata',plotdataY,'visible','on');
                    if ischanged, set(data.handles_otherThreshold(nplot),'ydata',ischanged+[0 0],'visible','on'); end
                    if isempty(plotdataT)
                        set(data.handles_otherSegments(nplot),'visible','off');
                        data.handles_boundaries{nplot}=[];
                    else 
                        temp=repmat(plotdataX(plotdataT(1:numel(plotdataT)-rem(numel(plotdataT),2))),2,1);
                        temp(:,2:2:end)=flipud(temp(:,2:2:end));
                        set(data.handles_otherSegments(nplot),'vertices',[temp(:), reshape([0 1; 1 0; 1 0; 0 1]*data.otherYLim'*ones(1,size(temp,2)/2),[],1)], 'faces', reshape(1:2*size(temp,2),4,[])','visible','on');
                        data.handles_boundaries{nplot}=plotdataX(plotdataT);
                    end
                    set(data.handles_otherPanel1(nplot),'ylim',[0 1.1*max(plotdataY)],'visible','on');
                    set(data.handles_otherSelectedWindow1(nplot),'visible','on');
                    set([data.handles_otherPanel2(nplot),data.handles_otherPlot2(nplot),data.handles_otherSelectedWindow2(nplot),data.handles_otherSelecetedVideoframe2(nplot)],'visible','off');
                else % images
                    switch(data.allPlotMeasures{data.plotMeasure(nplot)})
                        case 'Audio Spectrogram', % spectrogram
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
                    set(data.handles_otherSelectedWindow2(nplot),'visible','on');
                    set([data.handles_otherPanel1(nplot),data.handles_otherPlot1(nplot),data.handles_otherSelectedWindow1(nplot),data.handles_otherSelecetedVideoframe1(nplot),data.handles_otherSegments(nplot)],'visible','off');
                end
            end
        end
        if isfield(data,'hVideo'), set(data.hVideo, 'CData', getframeCache(data.currentFrame)); end
    end

    function [plotdataX, plotdataY, plotdataT, ischanged] = getMeasure(nmeasure)
        ischanged=0;
        switch(data.allPlotMeasures{nmeasure})
            case 'Velocity of Movements', 
                fieldname='globalMotionVel'; 
                SampleRate=data.SampleRate;  % note: data.FrameRate was raw/original sample rate
                plotdataX = []; 
            case 'Acceleration of Movements', 
                fieldname='globalMotionAcc'; 
                SampleRate=data.SampleRate; 
                plotdataX = []; 
            case 'Acoustic Energy', 
                if data.audioSignalSelect==1, fieldname='harmonicRatio.E1'; 
                else fieldname='harmonicRatio.E2'; 
                end
                SampleRate=data.harmonicRatio.SampleRate; 
                plotdataX = data.harmonicRatio.t;
            case 'Audio HNR (Harmonic to Noise Ratio)', 
                if data.audioSignalSelect==1, fieldname='harmonicRatio.P1'; 
                else fieldname='harmonicRatio.P2'; 
                end
                SampleRate=data.harmonicRatio.SampleRate; 
                plotdataX = data.harmonicRatio.t;
        end
        fieldname_smoothed=[fieldname,'_smoothed'];
        fieldname_thresholded=[fieldname,'_thresholded'];
        if data.smoothing{nmeasure}>0&&(~isfieldx(data,fieldname_smoothed)||isempty(getfieldx(data,fieldname_smoothed))), % timeseries smoothed
            temp=getfieldx(data,fieldname);
            data=setfieldx(data,fieldname_smoothed, reshape(convn(reshape(temp,[],1),flvoice_hanning(2*ceil(data.smoothing{nmeasure}*data.maxsmoothing*SampleRate/2)+1, true),'same'),size(temp)));
            data=setfieldx(data,fieldname_thresholded,[]);
        end
        if data.threshold{nmeasure}>0&&(~isfieldx(data,fieldname_thresholded)||isempty(getfieldx(data,fieldname_thresholded))), % timeseries thresholded
            thr=data.threshold{nmeasure}*max(getfieldx(data,fieldname));
            if data.smoothing{nmeasure}>0, temp=getfieldx(data,fieldname_smoothed)>thr;
            else temp=getfieldx(data,fieldname)>thr;
            end
            data=setfieldx(data,fieldname_thresholded, min(numel(temp),find([temp(:);false]~=[false;temp(:)]))); % (find(temp(2:end)~=temp(1:end-1))-1)/SampleRate);
            ischanged=thr;
        end
        if data.smoothing{nmeasure}>0, plotdataY = getfieldx(data,fieldname_smoothed); 
        else plotdataY = getfieldx(data,fieldname);
        end
        if isempty(plotdataX), plotdataX = (0:numel(plotdataY)-1)/SampleRate; end
        if data.threshold{nmeasure}>0, plotdataT=getfieldx(data,fieldname_thresholded);
        else plotdataT=[];
        end
        plotdataX = reshape(plotdataX,1,[]);
        plotdataY = reshape(plotdataY,1,[]);
        plotdataT = reshape(plotdataT,1,[]);
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
        if ~isfield(data,'handles_plotmeasure'), return; end
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
        %data.handles_audioSelectedPointText_extent=[];
        data.handles_audioSelectedWindowText1_extent=[];
        data.handles_audioSelectedWindowText2_extent=[];
        data.handles_audioSelectedWindowText3_extent=[];
        data.handles_audioLabelsText_extent=[];
    end

    function selectPoints(hFig)
        fprintf('Select a point on the audio plot:\n');
        data.buttondown_selectingpoints=1;
        return
        % % Display instructions
        % [audioX1, ~] = ginput(1); 
        % fprintf('t = %.3f s\n',mean(audioX1));
        % 
        % % Add a temporary vertical line for the selected audio point
        % handles_audioLine1 = line(data.handles_audioPanel, [audioX1, audioX1], data.audioYLim, 'Color', 'blue', 'LineStyle', ':');
        % fprintf('Select a second point on the audio plot: ');
        % [audioX2, ~] = ginput(1); 
        % fprintf('t = %.3f s\n',mean(audioX2));
        % 
        % % Determine the selected range
        % startTime = min(audioX1, audioX2);
        % endTime = max(audioX1, audioX2);
        % data.zoomWindow = [startTime, endTime];
        % 
        % % Add shading to indicate the selected range
        % set(data.handles_audioSelectedWindow, 'xdata', [startTime, endTime, endTime, startTime], 'ydata', [data.audioYLim(1), data.audioYLim(1), data.audioYLim(2), data.audioYLim(2)]); 
        % set(data.handles_otherSelectedWindow1, 'xdata', [startTime, endTime, endTime, startTime], 'ydata', [data.otherYLim(1), data.otherYLim(1), data.otherYLim(2), data.otherYLim(2)]); 
        % set(data.handles_otherSelectedWindow2, 'xdata', [startTime, endTime, endTime, startTime], 'ydata', [data.otherYLim(1), data.otherYLim(1), data.otherYLim(2), data.otherYLim(2)]); 
        % set(data.handles_audioSelectedWindowText1, 'string', sprintf('t = %.3f s ',startTime), 'position', [startTime, data.audioYLim*[1;0]]);
        % set(data.handles_audioSelectedWindowText2, 'string', sprintf(' t = %.3f s',endTime), 'position', [endTime, data.audioYLim*[1;0]]);
        % set(data.handles_audioSelectedWindowText3, 'string', sprintf('∆t = %d ms',round(1000*(endTime-startTime))), 'position', [endTime, data.audioYLim*[1;0]]);
        % delete(handles_audioLine1);
        % 
        % % enable selection-related buttons
        % if isfield(data, 'handles_playSelectionButton') && isvalid(data.handles_playSelectionButton), set(data.handles_playSelectionButton, 'Enable', 'on'); end
        % if isfield(data, 'handles_saveclipButton') && isvalid(data.handles_saveclipButton), set(data.handles_saveclipButton, 'Enable', 'on'); end
        % if isfield(data, 'handles_zoomButton') && isvalid(data.handles_zoomButton), set(data.handles_zoomButton, 'Enable', 'on'); end        
        % 
        % % Display the time difference between the selected points
        % disp(['Time difference between selected points: ', num2str(endTime - startTime), ' seconds.']);
        % zoomIn(true,true);
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
            set(data.handles_playSelectionButton,'cdata',data.handles_icons{4});
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
            set(data.handles_playSelectionButton,'cdata',data.handles_icons{3});
            % Pause playback
            pause(data.audioPlayer);
            data.isPlaying = false;
        end
    end

    function loadNewVideo(hFig)
        % Prompt user for a new video file
        if isfield(data,'videoFile')&&~isempty(data.videoFile), 
            [fileName, filePath] = uigetfile({'*.avi;*.mp4;*.mat', 'Video Files (*.avi, *.mp4; *.mat)'; '*', 'All Files (*.*)'}, 'Select a Video File',fileparts(data.videoFile));
        else
            [fileName, filePath] = uigetfile({'*.avi;*.mp4;*.mat', 'Video Files (*.avi, *.mp4; *.mat)'; '*', 'All Files (*.*)'}, 'Select a Video File');
        end
        if fileName == 0
            disp('No video file selected.');
            return;
        end
        fileName = regexprep(fileName,'\.TextGrid$','.mp4'); % if selected TextGrid file select mp4 instead
        newVideoFile = fullfile(filePath, fileName);
        disp(['Loading new video file: ', newVideoFile]);
        data=initialize(newVideoFile, hFig);

    end

    function frame = getframeCache(currentFrameIndex) % mixes video frame image with motion highlight
        frame = data.frameCache{currentFrameIndex};
        if data.motionHighlight>1, 
            colors=[0 0 0; 1 0 0; 1 1 0];
            color=colors(data.motionHighlight,:);
            if 0, %~ismember({'Acceleration of Movements'},data.allPlotMeasures(data.plotMeasure)) % by default shows velocity of motion (unless acceleration timecourse is being displayed?)
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


    function refTime=flvideo_findlocalmaximum(in_ref,refTime)
        if in_ref==1, xdata=get(data.handles_audioPlot,{'xdata','ydata'});
        else xdata=get(data.handles_otherPlot1(in_ref-1),{'xdata','ydata'});
        end
        idx1=1+find(xdata{2}(2:end-1)>xdata{2}(1:end-2) & xdata{2}(2:end-1)>=xdata{2}(3:end));
        if ~isempty(idx1)
            [nill,idx2]=min(abs(xdata{1}(idx1)-refTime));
            refTime=xdata{1}(idx1(idx2));
        end
    end

    function flvideo_keyfcn(option,varargin)
        mdf=get(data.handles_hFig,'currentmodifier');
        data.keydown_isctrlpressed=ismember('control',mdf); % CTRL-click to zoom in/out
        data.keydown_isshiftpressed=ismember('shift',mdf); % SHIFT-click to snap-to-peak
        data.keydown_isaltpressed=ismember('alt',mdf); % ALT-click to snap-to-boundary
        if isfield(data,'handles_audioCurrentPointText')
            switch(option)
                case 'press'
                    if data.keydown_isctrlpressed,
                        set(data.handles_audioCurrentPointText, 'string', ' CLICK&DRAG TO ZOOM');
                    elseif data.keydown_isshiftpressed,
                        set(data.handles_audioCurrentPointText, 'string', ' CLICK TO SELECT CLOSEST PEAK');
                    elseif data.keydown_isaltpressed,
                        set(data.handles_audioCurrentPointText, 'string', ' CLICK TO SELECT CLOSEST BOUNDARY');
                    end
                case 'release'
                    set(data.handles_audioCurrentPointText, 'string', '')
            end
            flvideo_buttonfcn('motion');
        end
    end

    function flvideo_buttonfcn(option,varargin)
        if isfield(data, 'isPlaying') && data.isPlaying, return; end % note: disregards mouse movements when audio is playing
        if ~isfield(data,'handles_audioPanel')||isempty(data.handles_audioPanel), return; end
        if ~isfield(data,'buttondown_pos'), data.buttondown_pos=0; end
        if ~isfield(data,'buttondown_time'), data.buttondown_time=0; end
        if ~isfield(data,'buttondown_ispressed'), data.buttondown_ispressed=0; end
        if ~isfield(data,'buttondown_isctrlpressed'), data.buttondown_isctrlpressed=0; end
        if ~isfield(data,'buttondown_isshiftpressed'), data.buttondown_isshiftpressed=0; end
        if ~isfield(data,'buttondown_selectingpoints'), data.buttondown_selectingpoints=0; end
        if ~isfield(data,'keydown_isctrlpressed'), data.keydown_isctrlpressed=0; end
        if ~isfield(data,'keydown_isshiftpressed'), data.keydown_isshiftpressed=0; end
        if ~isfield(data,'keydown_isaltpressed'), data.keydown_isaltpressed=0; end
        p1=get(0,'pointerlocation');
        set(gcbf,'units','pixels');
        p2=get(gcbf,'position');
        set(gcbf,'units','norm');
        p3=get(0,'screensize');
        p2(1:2)=p2(1:2)+p3(1:2)-1; % note: fix issue when connecting to external monitor/projector
        pos=(p1-p2(1:2))./p2(3:4);
        pos_ref=get(data.handles_audioPanel,'Position');
        pos_ref=(pos-pos_ref(1:2))./pos_ref(3:4);
        xlim_audio=data.XLim; %get(data.handles_audioPanel,'xlim');
        pos_audio=[xlim_audio(1) data.audioYLim(1)]+pos_ref.*[xlim_audio(2)-xlim_audio(1),data.audioYLim(2)-data.audioYLim(1)];
        in_ref=all(pos_ref>=0 & pos_ref<=1);
        refTime=data.XLim*[1-pos_ref(1);pos_ref(1)];
        %refTime=get(data.handles_audioPanel,'xlim')*[1-pos_ref(1);pos_ref(1)];
        nplots=numel(data.handles_plotmeasure);
        if ~in_ref, 
            for nplot=1:nplots,
                pos_ref=get(data.handles_otherPanel1(nplot),'Position');
                pos_ref=(pos-pos_ref(1:2))./pos_ref(3:4);
                in_ref=all(pos_ref>=0 & pos_ref<=1);
                if in_ref, in_ref=1+nplot; break; end % note: in_ref indicates the axes the mouse is in (1 for audio plot, >1 for other plots)
            end
        end
        %if strcmp(get(gcbf,'SelectionType'),'open'), set(gcbf,'selectiontype','normal'); if in_ref, zoomIn(1/2,true); end; return; end % double-click to zoom out
        in_text=[]; % cursor on text
        in_label=[]; % cursor in TextGrid text
        in_interval=[]; % cursor in TextGrid interval
        if data.textgridTier>0,
            label_mask=(pos_audio(1)>=data.textgridLabels(data.textgridTier).intervals(1,:)&pos_audio(1)<=data.textgridLabels(data.textgridTier).intervals(2,:));
            in_interval=find(label_mask,1);
            %set(data.handles_audioLabelsInterval,'facevertexalpha',.05*label_mask');
            label_inplot=(data.textgridLabels(data.textgridTier).intervals(2,:)>=data.XLim(1)&data.textgridLabels(data.textgridTier).intervals(1,:)<=data.XLim(2));
            %if ~isempty(data.handles_audioLabelsText), set(data.handles_audioLabelsText(label_inplot),'color',[.75 .75 .75],'fontsize',data.handles_audioLabelsText_fontsize,'backgroundcolor','none'); end
            if ~isempty(data.handles_audioLabelsText), set(data.handles_audioLabelsText(label_inplot),'color',[.75 .75 .75],'backgroundcolor','none'); end
        end
        if ~isempty(in_interval) && (~isfield(data,'handles_audioLabelsText_extent')||numel(data.handles_audioLabelsText_extent)<in_interval||isempty(data.handles_audioLabelsText_extent{in_interval})), data.handles_audioLabelsText_extent{in_interval}=get(data.handles_audioLabelsText(in_interval),'extent'); end % highlights text when hovering over it
        %if ~isfield(data,'handles_audioSelectedPointText_extent')||isempty(data.handles_audioSelectedPointText_extent), data.handles_audioSelectedPointText_extent=get(data.handles_audioSelectedPointText,'extent'); end
        if ~isfield(data,'handles_audioSelectedWindowText1_extent')||isempty(data.handles_audioSelectedWindowText1_extent), data.handles_audioSelectedWindowText1_extent=get(data.handles_audioSelectedWindowText1,'extent'); end
        if ~isfield(data,'handles_audioSelectedWindowText2_extent')||isempty(data.handles_audioSelectedWindowText2_extent), data.handles_audioSelectedWindowText2_extent=get(data.handles_audioSelectedWindowText2,'extent'); end
        if ~isfield(data,'handles_audioSelectedWindowText3_extent')||isempty(data.handles_audioSelectedWindowText3_extent), data.handles_audioSelectedWindowText3_extent=get(data.handles_audioSelectedWindowText3,'extent'); end
        if ~isempty(in_interval)&&all(pos_audio(1:2)>data.handles_audioLabelsText_extent{in_interval}(1:2) & pos_audio(1:2)-data.handles_audioLabelsText_extent{in_interval}(1:2)<data.handles_audioLabelsText_extent{in_interval}(3:4)), in_label=in_interval; set(data.handles_audioLabelsText(in_interval),'backgroundcolor',[.85 .85 .85]); end
        %if all(pos_audio(1:2)>data.handles_audioSelectedPointText_extent(1:2) & pos_audio(1:2)-data.handles_audioSelectedPointText_extent(1:2)<data.handles_audioSelectedPointText_extent(3:4)),            in_text=data.handles_audioSelectedPointText; set(data.handles_audioSelectedPointText,'backgroundcolor',[.85 .85 .85]);     else set(data.handles_audioSelectedPointText,'backgroundcolor','none'); end
        if all(pos_audio(1:2)>data.handles_audioSelectedWindowText1_extent(1:2) & pos_audio(1:2)-data.handles_audioSelectedWindowText1_extent(1:2)<data.handles_audioSelectedWindowText1_extent(3:4)),   in_text=data.handles_audioSelectedWindowText1; set(data.handles_audioSelectedWindowText1,'backgroundcolor',[.85 .85 .85]);  else set(data.handles_audioSelectedWindowText1,'backgroundcolor','none'); end
        if all(pos_audio(1:2)>data.handles_audioSelectedWindowText2_extent(1:2) & pos_audio(1:2)-data.handles_audioSelectedWindowText2_extent(1:2)<data.handles_audioSelectedWindowText2_extent(3:4)),   in_text=data.handles_audioSelectedWindowText2; set(data.handles_audioSelectedWindowText2,'backgroundcolor',[.85 .85 .85]);  else set(data.handles_audioSelectedWindowText2,'backgroundcolor','none'); end
        if all(pos_audio(1:2)>data.handles_audioSelectedWindowText3_extent(1:2) & pos_audio(1:2)-data.handles_audioSelectedWindowText3_extent(1:2)<data.handles_audioSelectedWindowText3_extent(3:4)),   in_text=data.handles_audioSelectedWindowText3; set(data.handles_audioSelectedWindowText3,'backgroundcolor',[.85 .85 .85]);  else set(data.handles_audioSelectedWindowText3,'backgroundcolor','none'); end

        if in_ref % when mouse is on any plot
            if data.keydown_isshiftpressed, % snap-to-peak
                refTime=flvideo_findlocalmaximum(in_ref,refTime);
            elseif data.keydown_isaltpressed, % snap-to-boundary
                if in_ref==1&&~isempty(in_interval)
                    if pos_audio(1)-data.textgridLabels(data.textgridTier).intervals(1,in_interval) < data.textgridLabels(data.textgridTier).intervals(2,in_interval)-pos_audio(1), refTime=data.textgridLabels(data.textgridTier).intervals(1,in_interval);
                    else refTime=data.textgridLabels(data.textgridTier).intervals(2,in_interval);
                    end
                elseif in_ref>1&&isfield(data,'handles_boundaries')&&numel(data.handles_boundaries)>=in_ref-1&&~isempty(data.handles_boundaries{in_ref-1})
                    [nill,idx]=min(abs(refTime-data.handles_boundaries{in_ref-1}));
                    refTime=data.handles_boundaries{in_ref-1}(idx);
                end
            end

            % show timepoint line
            set(data.handles_audioCurrentPoint, 'xdata', [refTime, refTime, refTime, refTime], 'ydata', data.audioYLim([1 1 2 2]));
            if data.buttondown_selectingpoints==1, set(data.handles_audioCurrentPointText, 'string', sprintf(' t = %.3f s CLICK TO SELECT FIRST POINT',refTime), 'position', [refTime, data.audioYLim*[1;0]]);
            elseif data.buttondown_selectingpoints==2, set(data.handles_audioCurrentPointText, 'string', sprintf(' t = %.3f s CLICK TO SELECT SECOND POINT',refTime), 'position', [refTime, data.audioYLim*[1;0]]);
            elseif data.keydown_isctrlpressed, set(data.handles_audioCurrentPointText, 'string', ' CLICK&DRAG TO ZOOM', 'position', [refTime, data.audioYLim*[1;0]]);
            elseif data.keydown_isshiftpressed, set(data.handles_audioCurrentPointText, 'string', sprintf(' t = %.3f s CLOSEST PEAK',refTime), 'position', [refTime, data.audioYLim*[1;0]]);
            elseif data.keydown_isaltpressed, set(data.handles_audioCurrentPointText, 'string', sprintf(' t = %.3f s CLOSEST BOUNDARY',refTime), 'position', [refTime, data.audioYLim*[1;0]]);
            %elseif data.keydown_isshiftpressed&&in_ref==1, set(data.handles_audioCurrentPointText, 'string', 'audio signal local maximum', 'position', [refTime, data.audioYLim*[1;0]]);
            %elseif data.keydown_isshiftpressed&&in_ref>1, set(data.handles_audioCurrentPointText, 'string', sprintf('%s local maximum',data.allPlotMeasures{in_ref-1}), 'position', [refTime, data.audioYLim*[1;0]]);
            else set(data.handles_audioCurrentPointText, 'string', sprintf(' t = %.3f s',refTime), 'position', [refTime, data.audioYLim*[1;0]]);
            end
            if nplots>0
                set(data.handles_otherCurrentPoint1, 'xdata', [refTime, refTime, refTime, refTime], 'ydata', data.otherYLim([1 1 2 2]));
                set(data.handles_otherCurrentPoint2, 'xdata', [refTime, refTime, refTime, refTime], 'ydata', data.otherYLim([1 1 2 2]));
                set(data.handles_otherThreshold,'visible','off');
            end
            % highlights TextGrid label
            %if ~isempty(in_interval), set(data.handles_audioLabelsText(in_interval),'color',[0 0 0],'fontsize',ceil(1.1*data.handles_audioLabelsText_fontsize)); end
            if ~isempty(in_interval), set(data.handles_audioLabelsText(in_interval),'color',[0 0 0]); end
        else 
            set(data.handles_audioCurrentPoint, 'xdata', [], 'ydata', []);
            set(data.handles_audioCurrentPointText, 'string', '');
            if nplots>0
                set(data.handles_otherCurrentPoint1, 'xdata', [], 'ydata', []);
                set(data.handles_otherCurrentPoint2, 'xdata', [], 'ydata', []);
            end
        end

        switch(option) % click-and-drag to select & zoom in
            case 'down',
                if in_ref % started selecting window or selecting timepoint
                    data.buttondown_pos=p1(1);
                    %mdf=get(data.handles_hFig,'currentmodifier');
                    %if isequal(mdf,{'control'})||data.keydown_isctrlpressed % CTRL-click to zoom in/out
                    if data.keydown_isctrlpressed % CTRL-click to zoom in/out
                        data.buttondown_isctrlpressed=1;
                        data.buttondown_info=[max(0,2*data.XLim(1)-refTime) min(data.totalDuration,2*data.XLim(2)-refTime(1)); data.XLim; refTime-.001 refTime+.001]; 
                    elseif data.buttondown_selectingpoints==1
                        data.buttondown_selectingpoints=2;
                        data.buttondown_ispressed=1;
                        data.buttondown_info=refTime;
                    elseif data.buttondown_selectingpoints==2
                        data.buttondown_ispressed=2;
                    %elseif isequal(mdf,{'shift'})||data.keydown_isshiftpressed % SHIFT-click to snap-to-peak
                    %    data.buttondown_isshiftpressed=1;
                    %    data.buttondown_info=refTime;
                    else % click to select timepoint, select window, select text, select TextGrid label
                        data.buttondown_ispressed=1;
                        data.buttondown_info=refTime;
                    end
                end
            case 'up',
                if data.buttondown_ispressed>1 % finished selecting window
                    data.buttondown_ispressed=0;
                    data.buttondown_selectingpoints=0;
                    startTime = min(data.buttondown_info, refTime);
                    endTime = max(data.buttondown_info, refTime);
                    endTime = max(startTime + 0.001, endTime);
                    set(data.handles_audioSelectedWindow, 'xdata', [startTime, endTime, endTime, startTime], 'ydata', data.audioYLim([1 1 2 2]));
                    set(data.handles_otherSelectedWindow1, 'xdata', [startTime, endTime, endTime, startTime], 'ydata', data.otherYLim([1 1 2 2]));
                    set(data.handles_otherSelectedWindow2, 'xdata', [startTime, endTime, endTime, startTime], 'ydata', data.otherYLim([1 1 2 2]));
                    set(data.handles_audioSelectedWindowText1, 'string', sprintf('t = %.3f s ',startTime), 'position', [startTime, data.audioYLim*[1;0]]);
                    set(data.handles_audioSelectedWindowText2, 'string', sprintf(' t = %.3f s',endTime), 'position', [endTime, data.audioYLim*[1;0]]);
                    set(data.handles_audioSelectedWindowText3, 'string', sprintf('∆t = %d ms',round(1000*(endTime-startTime))), 'position', [endTime, data.audioYLim*[1;0]]);
                    set(data.handles_audioCurrentPointText,'string','');
                    data.zoomWindow = [startTime, endTime];
                    % enable selection-related buttons
                    if isfield(data, 'handles_playSelectionButton') && isvalid(data.handles_playSelectionButton), set(data.handles_playSelectionButton, 'Enable', 'on'); end
                    if isfield(data, 'handles_saveclipButton') && isvalid(data.handles_saveclipButton), set(data.handles_saveclipButton, 'Enable', 'on'); end
                    if isfield(data, 'handles_zoomButton') && isvalid(data.handles_zoomButton), set(data.handles_zoomButton, 'Enable', 'on'); end
                    zoomIn(true,true);
                elseif data.buttondown_selectingpoints % finished selecting first point
                    fprintf('Select a second point on the audio plot:\n');
                    data.buttondown_ispressed=2; % note: continue as if button still down
                elseif data.buttondown_isctrlpressed>0 % finished zooming in/out
                    data.buttondown_isctrlpressed=0;
                elseif ~isempty(in_text) % clicked on text
                    data.buttondown_ispressed=0;
                    copytoclipboard(in_text);
                elseif ~isempty(in_label) % clicked on TextGrid label
                    data.buttondown_ispressed=0;
                    startTime = data.textgridLabels(data.textgridTier).intervals(1,in_label);
                    endTime = data.textgridLabels(data.textgridTier).intervals(2,in_label);
                    set(data.handles_audioSelectedWindow, 'xdata', [startTime, endTime, endTime, startTime], 'ydata', data.audioYLim([1 1 2 2]));
                    set(data.handles_otherSelectedWindow1, 'xdata', [startTime, endTime, endTime, startTime], 'ydata', data.otherYLim([1 1 2 2]));
                    set(data.handles_otherSelectedWindow2, 'xdata', [startTime, endTime, endTime, startTime], 'ydata', data.otherYLim([1 1 2 2]));
                    set(data.handles_audioSelectedWindowText1, 'string', sprintf('t = %.3f s ',startTime), 'position', [startTime, data.audioYLim*[1;0]]);
                    set(data.handles_audioSelectedWindowText2, 'string', sprintf(' t = %.3f s',endTime), 'position', [endTime, data.audioYLim*[1;0]]);
                    set(data.handles_audioSelectedWindowText3, 'string', sprintf('∆t = %d ms',round(1000*(endTime-startTime))), 'position', [endTime, data.audioYLim*[1;0]]);
                    data.zoomWindow = [startTime, endTime];
                    % enable selection-related buttons
                    if isfield(data, 'handles_playSelectionButton') && isvalid(data.handles_playSelectionButton), set(data.handles_playSelectionButton, 'Enable', 'on'); end
                    if isfield(data, 'handles_saveclipButton') && isvalid(data.handles_saveclipButton), set(data.handles_saveclipButton, 'Enable', 'on'); end
                    if isfield(data, 'handles_zoomButton') && isvalid(data.handles_zoomButton), set(data.handles_zoomButton, 'Enable', 'on'); end
                    zoomIn(true,true);
                elseif in_ref % selected timepoint
                    data.buttondown_ispressed=0;
                    if data.buttondown_isshiftpressed>0 % snap-to-peak
                        refTime=flvideo_findlocalmaximum(in_ref,refTime);
                        data.buttondown_isshiftpressed=0;
                    end
                    thisFrame(refTime);
                else % clicked elsewhere
                    data.buttondown_ispressed=0;
                end
            case 'motion'
                if in_ref && data.buttondown_ispressed && (data.buttondown_ispressed>1 || abs(p1(1)-data.buttondown_pos)>16), % in the process of selecting window (16pixels minimum displacement)
                    data.buttondown_ispressed=2;
                    startTime = min(data.buttondown_info, refTime);
                    endTime = max(data.buttondown_info, refTime);
                    set(data.handles_audioSelectedWindow, 'xdata', [startTime, endTime, endTime, startTime], 'ydata', data.audioYLim([1 1 2 2]));
                    set(data.handles_otherSelectedWindow1, 'xdata', [startTime, endTime, endTime, startTime], 'ydata', data.otherYLim([1 1 2 2]));
                    set(data.handles_otherSelectedWindow2, 'xdata', [startTime, endTime, endTime, startTime], 'ydata', data.otherYLim([1 1 2 2]));
                    set(data.handles_audioSelectedWindowText1, 'string', sprintf('t = %.3f s ',startTime), 'position', [startTime, data.audioYLim*[1;0]]);
                    set(data.handles_audioSelectedWindowText2, 'string', sprintf(' t = %.3f s',endTime), 'position', [endTime, data.audioYLim*[1;0]]);
                    set(data.handles_audioSelectedWindowText3, 'string', sprintf('∆t = %d ms',round(1000*(endTime-startTime))), 'position', [endTime, data.audioYLim*[1;0]]);
                    if ~data.buttondown_selectingpoints, set(data.handles_audioCurrentPointText,'string',''); end
                    data.handles_audioSelectedWindowText1_extent=[];
                    data.handles_audioSelectedWindowText2_extent=[];
                    data.handles_audioSelectedWindowText3_extent=[];
                    currentFrame = max(1, min(data.numFrames, ceil(refTime * data.FrameRate)));
                    frame = getframeCache(currentFrame);
                    set(data.hVideo, 'CData', frame);
                elseif in_ref && data.buttondown_isctrlpressed, % in the process of zooming in/out
                    k=max(-1,min(1, (p1(1)-data.buttondown_pos)/500));
                    refTime0=mean(data.buttondown_info(3,:));
                    zoomXlim=interp1([-1;0;1], data.buttondown_info, k,'linear');
                    set(data.handles_audioCurrentPoint,'xdata',[],'ydata',[]);
                    set(data.handles_audioCurrentPointText,'string',sprintf(' %d%% zoom',round(100*(data.buttondown_info(2,2)-data.buttondown_info(2,1))/(zoomXlim(2)-zoomXlim(1)))));
                    zoomIn(zoomXlim);
                elseif in_ref && data.videodisplay>1 % videoframe follows mouse motion
                    data.currentFrame = max(1, min(data.numFrames, ceil(refTime * data.FrameRate)));
                    frame = getframeCache(data.currentFrame);
                    set(data.hVideo, 'CData', frame);
                    timeAtCurrentFrame = (data.currentFrame+[-1 -1 0 0]) / data.FrameRate;
                    set(data.handles_audioSelectedVideoframe, 'XData', timeAtCurrentFrame, 'YData', data.audioYLim([1 2 2 1]));
                    set(data.handles_otherSelecetedVideoframe1, 'XData', timeAtCurrentFrame, 'YData', data.otherYLim([1 2 2 1]));
                    set(data.handles_otherSelecetedVideoframe2, 'XData', timeAtCurrentFrame, 'YData', data.otherYLim([1 2 2 1]));
                end
        end
    end

end

function c=getfieldx(a,b)
str=regexp(b,'\.','split');
c=getfield(a,str{:});
end

function a=setfieldx(a,b,c)
str=regexp(b,'\.','split');
a=setfield(a,str{:},c);
end

function c=isfieldx(a,b)
str=regexp(b,'\.','split');
if numel(str)>1, c=isfield(getfield(a,str{1:end-1}),str{end});
else c=isfield(a,b);
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

function out=flvoice_readTextGrid(filename)
% reads Praat TextGrid file
%
s=fileread(filename);
s=regexprep(s,'\![^\n]*',''); % remove comments
s=regexprep(s,'\[\d*\]',''); % remove bracketed numbers
out=[];
nout=0;
while 1,
    [str,ok]=nextItem('IntervalTier');
    if ~ok, break; end
    nout=nout+1;
    [out(nout).label,ok]=nextItem('string'); % label
    [out(nout).t1,ok]=nextItem('number'); % time1
    [out(nout).t2,ok]=nextItem('number'); % time2
    [out(nout).n,ok]=nextItem('number');  % number of intervals
    for n1=1:out(nout).n
        [out(nout).interval(n1).t1,ok]=nextItem('number'); % time1
        [out(nout).interval(n1).t2,ok]=nextItem('number'); % time2
        [out(nout).interval(n1).label,ok]=nextItem('string');  % label
    end
end
    function [str,ok] = nextItem(style)
        str = [];
        ok = false;
        switch(style)
            case 'IntervalTier'
                idx=regexp(s, '\"IntervalTier\"','end','once');
                if ~isempty(idx),
                    str='IntervalTier';
                    s=s(idx+1:end);
                    ok=true;
                end
            case 'string'
                [idx1,idx2]=regexp(s, '\"(\"\"|[^\"])*\"','start','end','once');
                if ~isempty(idx1),
                    str=s(idx1+1:idx2-1);
                    s=s(idx2+1:end);
                    ok=true;
                end
            case 'number'
                [idx1,idx2]=regexp(s, '(\s|\n)[\d\.]+(\s|\n)','start','end','once');
                if ~isempty(idx1),
                    str=str2num(s(idx1+1:idx2-1));
                    s=s(idx2+1:end);
                    ok=true;
                end
        end
    end
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

function w=flvoice_hanning(n, normed)
if ~rem(n,2),%even
    w = .5*(1 - cos(2*pi*(1:n/2)'/(n+1))); 
    w=[w;flipud(w)];
else,%odd
   w = .5*(1 - cos(2*pi*(1:(n+1)/2)'/(n+1)));
   w = [w; flipud(w(1:end-1))];
end
if nargin>1&&~isempty(normed)&&normed>0, w=w/sum(w); end
end
function w=flvoice_hamming(n, normed)
if ~rem(n,2),%even
    w = .54 - .46*cos(2*pi*(1:n/2)'/(n+1)); 
    w=[w;flipud(w)];
else,%odd
   w = .54 - .46*cos(2*pi*(1:(n+1)/2)'/(n+1));
   w = [w; flipud(w(1:end-1))];
end
if nargin>1&&~isempty(normed)&&normed>0, w=w/sum(w); end
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