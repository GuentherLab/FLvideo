function FLvideo_realign(files,varargin)
% FLVIDEO_REALIGN
% Corrects possible temporal misalignment between video frames and audio in rtMRI video files
%
% FLvideo_realign(videoFile)
% Creates a new version of the same video file (named realigned_[ORIGINALVIDEOFILENAME]) with possible audio delay corrected
% INPUTS:
%     videoFile     : input video filename (if this input is a list / cell array FLvideo_realign will process separately each file in this list)
% OUTPUTS:
%     Corrected video file saved at realigned_[FILENAME].mp4   (this file is not created when 'save' is set to false)
%     Optimal delay value saved at realigned_[FILENAME].json   (this file is not created when 'save' is set to false)
%     Optimization details saved at realigned_[FILENAME].jpg   (this file is not created when 'print' is set to false)
%
% FLvideo_realign(videoFile, optionName1, optionValue1, optionName2, optionValue2, ...)
% Specifies additional options as option-name and option-value pairs. Valid option names are:
%    tau            : extent of delay search in #-of-videoframes units (default -100:100)
%    regularization : regularization towards apriori delay distribution (standard deviation of apriori distribution of expected delay values - in #-of-videoframes units) (default 50)
%    splithalf      : set to true to split original video in two parts and evaluate delay separately in each part (default false)
%    disp           : set to false to skip displaying image of delay optimization results (default true)
%    print          : set to false to skip creation of .jpg image with display of delay optimization results (default true)
%    save           : set to false to skip creation of audio-delay-corrected video file (default true)
%    delay          : set to value of audio delay (in seconds); this will skip the 4optimization procedure and use the user-entered delay value instead when creating the audio-delay-corrected output file (default [])
%
% e.g. 
% FLvideo_realign('S13_vol_8115-0010_movie.mp4', 'print', true);
%


options=struct(...
    'tau',-100:100,...      % extent of delay search (in #-of-videoframes units)
    'regularization',50,... % regularization towards apriori delay distribution (std of normal distribution with mean zero modeling expected delay values - in #-of-videoframes units)
    'width',30:-1:1,...     % multi-scale search pattern (size of smoothing kernel at each scale level - in #-of-videoframes units)
    'splithalf',false,...
    'print',true,...
    'disp',true,...
    'delay',[],...
    'save',true);
for n=1:2:numel(varargin)-1, toptions=fieldnames(options); assert(isfield(options,lower(varargin{n})),'unrecognized option %s (valid options %s)',varargin{n},sprintf('%s ',toptions{:})); options.(lower(varargin{n}))=varargin{n+1}; end

if isempty(files), return; end
if options.print, options.disp=true; end
if ischar(files), files={files}; end
[nill,fname,nill]=cellfun(@fileparts,files,'UniformOutput',false);
fname=regexprep(fname,'_',' ');

if options.splithalf, HIDX=0:2;
else HIDX=0;
end
if options.disp, hfig=figure; end

IDX=1:numel(files);
TALL=[];
for idx=IDX
    videoFile=files{idx};
    [outputPath,outputName,outputExt]=fileparts(videoFile);
    [audioSignal, audioFs] = audioread(videoFile); % Read audio from the video
    audioSignal=audioSignal(:,1); % mono audio track


    % Create a VideoReader object
    v = VideoReader(videoFile);

    % Check video properties
    if options.disp
        disp(['Duration: ', num2str(v.Duration), ' seconds (',num2str(v.numFrames), ' frames)']);
        disp(['Video Frame Rate: ', num2str(v.FrameRate), ' fps']);
        disp(['Video Resolution: ', num2str(v.Width), 'x', num2str(v.Height)]);
        disp(['Audio Sample Rate: ', num2str(audioFs)]);
        try, disp(['Audio Format: ', v.AudioFormat]); end % Audio information, if available
    end

    % Get total frames of video
    numFrames = v.NumFrames; %floor(v.Duration * v.FrameRate); % NOTE: v.Duration is not an integer multiple of 1/FrameRate
    FrameRate = v.FrameRate; %numFrames/v.Duration;

    totalDuration = max(length(audioSignal)/audioFs, v.Duration);
    XLim = [0 totalDuration];

    % Preload frames into cache
    timeCache = [];
    frameCache = cell(1, numFrames);
    for i = 1:numFrames
        frameCache{i} = read(v, i);
        timeCache(i)=v.CurrentTime;
    end
    videoSignal=cat(4,frameCache{:});
    t1=numel(audioSignal)/audioFs;
    t2=size(videoSignal,4)/FrameRate;
    clear dV dA;
    for k=1:size(videoSignal,4)-1
        % video diff
        dV(k) = mean(mean(mean(abs(videoSignal(:,:,:,k+1)-videoSignal(:,:,:,k)).^2)));
        % audio diff
        t1 = round(k/FrameRate*audioFs+(-3/FrameRate*audioFs:0/FrameRate*audioFs)); t1=max(t1,1-t1); t1=min(t1,2*numel(audioSignal)+1-t1); s1 = audioSignal(t1).*hanning(numel(t1));
        t2 = round(k/FrameRate*audioFs+(-0/FrameRate*audioFs:3/FrameRate*audioFs)); t2=max(t2,1-t2); t2=min(t2,2*numel(audioSignal)+1-t2); s2 = audioSignal(t2).*hanning(numel(t2));
        %t1 = round(k/FrameRate*audioFs+(-4/FrameRate*audioFs:-2/FrameRate*audioFs)); t1=max(t1,1-t1); t1=min(t1,2*numel(audioSignal)+1-t1); s1 = audioSignal(t1).*hanning(numel(t1));
        %t2 = round(k/FrameRate*audioFs+(2/FrameRate*audioFs:4/FrameRate*audioFs)); t2=max(t2,1-t2); t2=min(t2,2*numel(audioSignal)+1-t2); s2 = audioSignal(t2).*hanning(numel(t2));
        dA(k) = mean(abs( (abs(fft(s1)))-(abs(fft(s2))) ).^2);
    end

    k=cumsum(sqrt(dA));
    kHALF=sum(k<=k(end)/2);
    if options.disp
        hax1=subplot(211,'parent',hfig); plot((0:numel(audioSignal)-1)/audioFs,audioSignal,'parent',hax1); axis(hax1,'tight'); xlabel(hax1,'time (s)');
        hright=patch([kHALF/FrameRate kHALF/FrameRate get(gca,'xlim')*[0;1]*[1 1]], get(gca,'ylim')*[1 0 0 1;0 1 1 0],'w','facealpha',.9,'edgecolor','none','parent',hax1);
        hleft=patch([0 0 kHALF/FrameRate kHALF/FrameRate], get(gca,'ylim')*[1 0 0 1;0 1 1 0],'w','facealpha',.9,'edgecolor','none','parent',hax1);
        hax2=subplot(212,'parent',hfig);
        xlabel(hax2,'Audio delay (s)');
    end

    %w=ones(numel(dA),1);
    %%w=sin(linspace(0,pi,numel(dA))');
    %dA=.01+w'.*dA;
    %dV=.01+w'.*dV;

    for hidx=HIDX
        TAU=options.tau;
        OPTIMTAU=find(TAU==0);
        for width=options.width, 
            da=dA;
            dv=dV;
            switch(hidx)
                case 0, % entire signal
                    if options.disp, set(hleft,'visible','off');set(hright,'visible','off'); end
                case 1, % first half
                    if options.disp, set(hleft,'visible','off');set(hright,'visible','on'); end
                    da=da(1:kHALF);
                    dv=dv(1:kHALF);
                case 2, % second half
                    if options.disp, set(hleft,'visible','on');set(hright,'visible','off'); end
                    da=da(kHALF+1:end);
                    dv=dv(kHALF+1:end);
            end
            da=tanh(.25*(da-prctile(da,50))/(prctile(da,75)-prctile(da,25)));
            dv=tanh(.25*(dv-prctile(dv,50))/(prctile(dv,75)-prctile(dv,25)));
            da = convn(da,hanning(width)','same');
            dv = convn(dv,hanning(width)','same');
            r=[];
            for n=1:numel(TAU)
                tda=da(max(1,min(numel(da), (1:numel(da))+TAU(n))))'; % note: positive TAU means video movement precedes audio movement, negative TAU means audio movement precedes video movement
                tdv=dv';
                r(n)=corr(tda,tdv);
            end
            if ~isempty(options.regularization)&&options.regularization~=0
                r=r.*exp(-.5*abs(TAU).^2/options.regularization^2);
            end
            if isempty(OPTIMTAU), [nill,OPTIMTAU]=max(r);
            elseif r(min(numel(r),OPTIMTAU+1))>r(OPTIMTAU)&&r(min(numel(r),OPTIMTAU+1))>=r(max(1,OPTIMTAU-1))>r(OPTIMTAU), OPTIMTAU=OPTIMTAU+1;
            elseif r(max(1,OPTIMTAU-1))>r(OPTIMTAU), OPTIMTAU=OPTIMTAU-1;
            end
            if options.disp, 
                plot(TAU/FrameRate,r); hold(hax2,'on'); plot(TAU(OPTIMTAU)/FrameRate,r(OPTIMTAU),'.','parent',hax2);
                drawnow
            end
        end
        if OPTIMTAU>1&&OPTIMTAU<numel(r)
            [rmax,ridx]=parabmax(r(OPTIMTAU-2:OPTIMTAU+2));
            OPTIMDELAY=interp1(1:numel(TAU),TAU,OPTIMTAU+ridx-3)/FrameRate;
        else OPTIMDELAY=TAU(OPTIMTAU)/FrameRate; rmax=r(OPTIMTAU);
        end
        if options.disp, 
            plot(OPTIMDELAY,rmax,'o','parent',hax2); 
            hold(hax2,'off'); grid(hax2,'on'); xline(hax2,OPTIMDELAY);
            if options.splithalf&&hidx==1, title(hax2,sprintf('%s (first half) delay = %dms',fname{idx},round(1000*OPTIMDELAY)));
            elseif options.splithalf&&hidx==2, title(hax2,sprintf('%s (second half) delay = %dms',fname{idx},round(1000*OPTIMDELAY)));
            else title(hax2,sprintf('%s tau = %dms',fname{idx},round(1000*OPTIMDELAY)));
            end
            axis(hax2,'tight');
            fprintf('%s, %f\n',regexprep(videoFile,'.*[\\\/]',''),OPTIMDELAY);
        end        
        if options.print
            if options.splithalf&&hidx==1, print(hfig,'-djpeg90','-r600','-opengl',fullfile(outputPath,['realigned_',outputName,'_half1.jpg']));
            elseif options.splithalf&&hidx==2, print(hfig,'-djpeg90','-r600','-opengl',fullfile(outputPath,['realigned_',outputName,'_half2.jpg']));
            else print(hfig,'-djpeg90','-r600','-opengl',fullfile(outputPath,['realigned_',outputName,'.jpg']));
            end
        end

        TALL=[TALL; OPTIMDELAY];
    end

    if options.save
        if ~isempty(options.delay), OPTIMDELAY=optims.delay; end
        outputSignal=audioSignal(max(1,round(OPTIMDELAY*audioFs):numel(audioSignal)));
        outputFile=fullfile(outputPath,['realigned_',outputName,'.mp4']);
        tempfile='FLvideo_realign_temporalfile_video.mp4';
        if exist(outputFile,'file'), delete(outputFile); end
        % Write video
        writer = VideoWriter(tempfile,'MPEG-4');
        writer.FrameRate=FrameRate;
        open(writer);
        for i = 1:numFrames
            frame = frameCache{i};
            if rem(size(frame,1),8), frame=cat(1,frame,frame(end+zeros(1,8-rem(size(frame,1),8)),:,:)); end
            if rem(size(frame,2),8), frame=cat(2,frame,frame(:,end+zeros(1,8-rem(size(frame,1),8)),:)); end
            writeVideo(writer, frame);
        end
        close(writer);
        % Write separate audio track and merge
        SampleRate=audioFs;
        if ~ismember(SampleRate,[44100,48000]) % resample audio to 44100 or 48000 for compatibility across platforms
            if ismember(SampleRate,[11025, 22050]), SampleRate=44100;
            else SampleRate=48000;
            end
            disp(['Clip audio resampled from ', num2str(audioFs), 'Hz to ',num2str(SampleRate),'Hz']);
            audioClip=interpft(outputSignal,round(length(outputSignal)*SampleRate/audioFs));
        end
        audiowrite('FLvideo_realign_temporalfile_audio.mp4', audioClip, SampleRate);
        if ispc
            args_ffmpeg=sprintf('-i "%s" -i "%s" -c:v copy -c:a copy "%s"', fullfile(pwd,'FLvideo_realign_temporalfile_video.mp4'),fullfile(pwd,'/FLvideo_realign_temporalfile_audio.mp4'), outputFile);
            args_vlc=sprintf('-I dummy "%s" --input-slave="%s" --sout "#gather:std{access=file,mux=mp4,dst=%s}" vlc://quit', fullfile(pwd,'FLvideo_realign_temporalfile_video.mp4'),fullfile(pwd,'/FLvideo_realign_temporalfile_audio.mp4'), outputFile);
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
                fprintf('Audio delayed by %dms\n', round(1000*OPTIMDELAY));
                fprintf('Clip saved to: %s\n', outputFile);
            else
                disp('Sorry, unable to find FFMPEG or VLC on your system. Please install FFMPEG and add its location to your system PATH');
            end
        else
            args_ffmpeg=sprintf('-i ''%s'' -i ''%s'' -c:v copy -c:a copy ''%s''', fullfile(pwd,'FLvideo_realign_temporalfile_video.mp4'),fullfile(pwd,'/FLvideo_realign_temporalfile_audio.mp4'), outputFile);
            args_vlc=sprintf('-I dummy ''%s'' --input-slave=''%s'' --sout "#gather:std{access=file,mux=mp4,dst=%s}" vlc://quit', fullfile(pwd,'FLvideo_realign_temporalfile_video.mp4'),fullfile(pwd,'/FLvideo_realign_temporalfile_audio.mp4'), outputFile);
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
                fprintf('Audio delayed by %dms\n', round(1000*OPTIMDELAY));
                fprintf('Clip saved to: %s\n', outputFile);
            else
                if ismac, disp('Sorry, unable to find FFMPEG or VLC on your system. Please install FFMPEG and add it to the Applications folder');
                else disp('Sorry, unable to find FFMPEG or VLC on your system. Please install FFMPEG and add it to the /usr/local/bin/ folder');
                end
            end
        end
        fh=fopen(fullfile(outputPath,['realigned_',outputName,'.json']),'wt');
        fprintf(fh,'{\n');
        fprintf(fh,'  "delay": %.3f\n',OPTIMDELAY);
        fprintf(fh,'}\n');
        fclose(fh);
    end
end
end

function w=hanning(n);
if ~rem(n,2),%even
    w = .5*(1 - cos(2*pi*(1:n/2)'/(n+1))); 
    w=[w;flipud(w)];
else,%odd
   w = .5*(1 - cos(2*pi*(1:(n+1)/2)'/(n+1)));
   w = [w; flipud(w(1:end-1))];
end
end



