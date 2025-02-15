% Prompt user to select files
[filenames, pathname] = uigetfile({'*.*'}, 'Select Files', 'MultiSelect', 'on');

% Ensure filenames is a cell array even if only one file is selected
if ischar(filenames)
    filenames = {filenames};
end

% Create Annotation folder if it doesn't exist
annotationFolder = fullfile(pathname, 'Annotation');
if ~exist(annotationFolder, 'dir')
    mkdir(annotationFolder);
end

% Loop through each selected file
for f = 1:length(filenames)
    originalFile = filenames{f};
    [~, name, ext] = fileparts(originalFile);
    
    % Create 21 copies with the required naming format
    for i = 1:21
        prefix = sprintf('S%02d_', i);
        newFilename = [prefix name '_denoised' ext];
        newFilePath = fullfile(annotationFolder, newFilename);
        
        % Copy the original file with the new name
        copyfile(fullfile(pathname, originalFile), newFilePath);
        
        % Create the corresponding empty .TextGrid file
        textGridFilename = [prefix name '_denoised.TextGrid'];
        textGridPath = fullfile(annotationFolder, textGridFilename);
        fclose(fopen(textGridPath, 'w')); % Create an empty file
    end
end

fprintf('Files have been successfully copied and .TextGrid files created.\n');
