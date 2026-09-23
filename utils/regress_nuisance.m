function out = regress_nuisance(vols, regressors, mask_file, prefix)
% REGRESS_NUISANCE  Remove nuisance regressors from every voxel inside a mask.
%
%   out = regress_nuisance(vols, regressors, mask_file, prefix)
%
% Each voxel's time series y is fit by ordinary least squares to
% [1, regressors] and the fitted regressor component is subtracted (the
% voxel mean is kept). Voxels outside the mask are copied unchanged.
% Writes prefix-ed copies of vols and returns their names.
%
% Same model as controlling_motion_parameters_from_FMRI.m
% (Y. Iturria-Medina, Montreal Neurological Institute, 2016), vectorized.

V = spm_vol(vols);
n_time = numel(V);
mask = spm_read_vols(spm_vol(mask_file)) > 0;

% Time x voxels matrix of in-mask data
Y = zeros(n_time, nnz(mask));
for t = 1:n_time
    vol = spm_read_vols(V(t));
    Y(t,:) = vol(mask);
end

X = [ones(n_time,1), regressors];
beta = X \ Y;
Y = Y - regressors * beta(2:end,:);

out = with_prefix(vols, prefix);
for t = 1:n_time
    vol = spm_read_vols(V(t));
    vol(mask) = Y(t,:);
    Vo = V(t);
    Vo.fname = deblank(out(t,:));
    Vo.dt    = [spm_type('float32') 0];
    Vo.pinfo = [1; 0; 0];
    spm_write_vol(Vo, vol);
end
end
