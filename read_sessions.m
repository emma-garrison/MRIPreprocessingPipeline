function [subjects, sessions] = read_sessions(csv_file)
% READ_SESSIONS  Read the table listing every scan to process.
%
% The CSV has one row per scan and the columns
%   subject   subject ID
%   modality  T1, fMRI or DWI
%   date      acquisition date, YYYY-MM-DD
%   protocol  basic or multiband (fMRI and DWI; blank for T1)
%   path      T1 / fMRI: NIfTI file (.nii)
%             DTI: DICOM folder or .mif with an embedded gradient table
%
% Returns the list of subject IDs and a matching array of structs with
% fields t1, fmri and dti. Each is an array of scans sorted by date, with
% fields path, name, date (MATLAB datenum) and protocol.

opts = detectImportOptions(csv_file, 'Delimiter', ',');
opts = setvartype(opts, 'string');
T = readtable(csv_file, opts);

subjects = unique(T.subject)';
for i = numel(subjects):-1:1
    rows = T(T.subject == subjects(i), :);
    sessions(i).t1   = scans_of(rows, 'T1');
    sessions(i).fmri = scans_of(rows, 'fMRI');
    sessions(i).dwi  = scans_of(rows, 'DTI');
end
subjects = cellstr(subjects);
end

function scans = scans_of(rows, modality)
rows = rows(strcmpi(rows.modality, modality), :);
scans = struct('path', {}, 'name', {}, 'date', {}, 'protocol', {});
for r = 1:height(rows)
    scans(end+1) = struct( ...
        'path',     char(rows.path(r)), ...
        'name',     sprintf('%s_%s', modality, rows.date(r)), ...
        'date',     datenum(char(rows.date(r)), 'yyyy-mm-dd'), ...
        'protocol', char(lower(rows.protocol(r)))); %#ok<AGROW>
end
[~, order] = sort([scans.date]);
scans = scans(order);
end
