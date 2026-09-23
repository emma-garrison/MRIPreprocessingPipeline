function out = with_prefix(files, prefix, new_ext)
% WITH_PREFIX  Add a prefix to the file name(s) in a char array, SPM style.
%   with_prefix('/a/vol_001.nii', 'r')          -> '/a/rvol_001.nii'
%   with_prefix('/a/vol_001.nii', 'rp_', '.txt') -> '/a/rp_vol_001.txt'
out = cell(size(files,1), 1);
for i = 1:size(files,1)
    [p, n, e] = fileparts(deblank(files(i,:)));
    if nargin > 2, e = new_ext; end
    out{i} = fullfile(p, [prefix n e]);
end
out = char(out);
end
