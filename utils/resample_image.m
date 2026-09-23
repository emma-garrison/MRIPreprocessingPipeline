function out_file = resample_image(in_file, voxel_size, order, out_file)
% RESAMPLE_IMAGE  Resample an image to isotropic voxels over the same field of view.
%   
% order: B-spline interpolation order (0 = nearest neighbour for masks/labels,
%   3 = cubic for continuous images).
% 
% Adapted from reslice_spacen.m in the original preprocessing code.

V   = spm_vol(in_file);
vx0 = sqrt(sum(V.mat(1:3,1:3).^2));
vx  = voxel_size * [1 1 1];

Vo = struct( ...
    'fname', out_file, ...
    'dim',   round(V.dim .* vx0 ./ vx), ...
    'dt',    [spm_type('float32') 0], ...
    'pinfo', [1; 0; 0], ...
    'mat',   V.mat / diag([vx0 1]) * diag([vx 1]), ...
    'descrip', sprintf('resampled to %g mm', voxel_size));

spline = [order order order 0 0 0];
C = spm_bsplinc(V, spline);
M = V.mat \ Vo.mat;                     % output voxel -> input voxel
[X, Y] = ndgrid(1:Vo.dim(1), 1:Vo.dim(2));
data = zeros(Vo.dim);
for z = 1:Vo.dim(3)
    data(:,:,z) = spm_bsplins(C, ...
        M(1,1)*X + M(1,2)*Y + M(1,3)*z + M(1,4), ...
        M(2,1)*X + M(2,2)*Y + M(2,3)*z + M(2,4), ...
        M(3,1)*X + M(3,2)*Y + M(3,3)*z + M(3,4), spline);
end
spm_write_vol(Vo, data);
end
