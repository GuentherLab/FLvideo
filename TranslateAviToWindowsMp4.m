% Prompt user to select one or more AVI files
[fileNames, filePath] = uigetfile('*.avi', 'Select AVI Files to Convert', 'MultiSelect', 'on');
FilterFlag = questdlg('Created denoised version(s) using comb filter?', 'Confirmation', 'Yes', 'No', 'No');

% Check if the user selected files
if isequal(fileNames, 0)
    disp('No files selected. Exiting...');
    return;
end

% Ensure fileNames is a cell array for consistency
if ischar(fileNames)
    fileNames = {fileNames};
end

% Process each selected file
for i = 1:length(fileNames)
    % Get the full path of the current input file
    inputFile = fullfile(filePath, fileNames{i});
    
    % Generate the output file name
    [~, name, ~] = fileparts(fileNames{i});
    
    % Remove "Copy of " from the beginning of the name, if present
    prefix = "Copy of ";
    if startsWith(name, prefix)
        name = erase(name, prefix);
    end
    
    % Append the '.mp4' extension
    outputFile = fullfile(filePath, [name, '.mp4']);
    
    % FFmpeg command to convert AVI to MP4
    ffmpegCmd = sprintf('ffmpeg -i "%s" -c:a aac "%s"', inputFile, outputFile);
    disp(['Processing file: ', inputFile]);
    
    % Run the FFmpeg command
    status = system(ffmpegCmd);
    
    % Check if the command ran successfully
    if status == 0
        disp(['Conversion successful! File saved as: ', outputFile]);
    else
        disp(['FFmpeg command failed for file: ', inputFile]);
    end

    if FilterFlag == "Yes"
        disp('Creating denoised version')
        [path, name, ext] = fileparts(outputFile);
        FilteredOutputFile = fullfile(path, [name '_denoised' ext]);

        % Create mp4 video without sound 
        ffmpegCmd = sprintf('ffmpeg -i "%s" -c:v copy -an "%s"', outputFile, 'VidTemp.mp4');
        status = system(ffmpegCmd)
        
        % Read and filter audio signal
        [audioSignal, audioFs] = audioread(outputFile); % Read audio from the video
        filteredAudio=filterMRINoise(audioSignal, audioFs);
        audiowrite('AudTemp.mp3', filteredAudio, audioFs);
        cmd='ffmpeg';
        args=sprintf('-i "%s" -i "%s" -c:v copy "%s"','VidTemp.mp4','AudTemp.mp3', FilteredOutputFile);
        [ko,msg]=system(sprintf('%s %s', cmd, args));
        delete('VidTemp.mp4');
        delete('AudTemp.mp3');
    end
end

disp('All selected files have been processed.');

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

