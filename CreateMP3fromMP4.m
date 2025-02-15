% Prompt user to select one or more MP4 files
[fileNames, filePath] = uigetfile('*.mp4', 'Select MP4 Files', 'MultiSelect', 'on')

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
    [~, name, ~] = fileparts(fileNames{i});
    audioFile = fullfile(filePath, [name, '.mp3'])
    [audioSignal, audioFs] = audioread(inputFile); % Read audio from the video
    audiowrite(audioFile, audioSignal, audioFs)
end