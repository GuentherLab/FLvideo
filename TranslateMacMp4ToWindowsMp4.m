% Prompt user to select one or more MP4 files
[fileNames, filePath] = uigetfile('*.mp4', 'Select Mac MP4 Files to Convert', 'MultiSelect', 'on');

% Check if the user selected files
if isequal(fileNames, 0)
    disp('No files selected. Exiting...');
    return;
end

% Ensure fileNames is a cell array for consistency
if ischar(fileNames)
    fileNames = {fileNames};
end

% Define the subdirectory for translated files
outputDir = fullfile(filePath, 'Translated');

% Create the subdirectory if it does not exist
if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end

% Process each selected file
for i = 1:length(fileNames)
    % Get the full path of the current input file
    inputFile = fullfile(filePath, fileNames{i});
    
    % Generate the output file name in the "Translated" subdirectory
    [~, name, ext] = fileparts(fileNames{i}); % Extract file name and extension
    
    % Remove "Copy of " from the beginning of the name, if present
    prefix = "Copy of ";
    if startsWith(name, prefix)
        name = erase(name, prefix);
    end
    
    % Output file path in the "Translated" subdirectory
    outputFile = fullfile(outputDir, [name, ext]);
    
    % FFmpeg command to convert the file
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
