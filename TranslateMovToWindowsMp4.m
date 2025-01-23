% Prompt user to select one or more MOV files
[fileNames, filePath] = uigetfile('*.mov', 'Select MOV Files to Convert', 'MultiSelect', 'on');

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
    
    % FFmpeg command to convert MOV to MP4
    ffmpegCmd = sprintf('ffmpeg -i "%s" -c:a copy "%s"', inputFile, outputFile);
    disp(['Processing file: ', inputFile]);
    
    % Run the FFmpeg command
    status = system(ffmpegCmd);
    
    % Check if the command ran successfully
    if status == 0
        disp(['Conversion successful! File saved as: ', outputFile]);
    else
        disp(['FFmpeg command failed for file: ', inputFile]);
    end
end

disp('All selected files have been processed.');
