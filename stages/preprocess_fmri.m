function ts = preprocess_fmri(scan, t1, out_dir, cfg)
% PREPROCESS_FMRI  Resting-state fMRI preprocessing (SPM12), ending in regional time series.
%
%   1. Discard the first cfg.fmri.n_dummy volumes
%   2. Motion correction (SPM realign)
%   3. Coregistration of the mean functional image to this session's T1
%      (normalized mutual information), reslicing all volumes to the T1
%      grid at 2 mm isotropic
%   4. Global signal removal (LMGS; Macey et al., 2004)
%   5. Nuisance regression: 6 motion parameters and their squares, mean
%      white matter signal, mean CSF signal
%   6. Regional time series: gray matter-weighted mean within each parcel
%      of the native-space atlas
%
% Slice timing correction, spatial normalization and smoothing are
% deliberately omitted. Bandpass filtering happens in
% functional_connectivity.m.
%
% Returns (and saves to out_dir/regional_timeseries.mat) a struct with
%   signal   regions x time matrix
%   TR       repetition time (s)
%   motion   realignment parameters (time x 6)
%   plus the scan's date and protocol.

out_file = fullfile(out_dir, 'regional_timeseries.mat');
if cfg.skip_existing && isfile(out_file)
    ts = load(out_file);
    return
end
if ~isfolder(out_dir), mkdir(out_dir); end
vol_dir = fullfile(out_dir, 'volumes');

%% 1. Split the 4D series into 3D volumes, dropping the dummy volumes
V = spm_vol(scan.path);
if numel(V) <= cfg.fmri.n_dummy + 1
    error('%s has only %d volumes', scan.path, numel(V));
end
if ~isfolder(vol_dir), mkdir(vol_dir); end
V = spm_file_split(V(cfg.fmri.n_dummy+1:end), vol_dir);
vols = char({V.fname});

%% 2. Motion correction: estimate realignment (stored in the headers) and
%     write a mean image for coregistration.
spm_realign(vols);
spm_reslice(vols, struct('which', 0, 'mean', 1));
motion     = load(with_prefix(vols(1,:), 'rp_', '.txt'));
mean_image = with_prefix(vols(1,:), 'mean');

%% 3. Coregister to the T1 and reslice to 2 mm
ref  = resample_t1_images(t1, cfg.fmri.voxel_size, out_dir);
vols = coregister(mean_image, vols, ref.t1);

%% 4. Global signal removal (writes 'd'-prefixed volumes)
cspm_lmgs({vols}, 1, 'd', 0, 0);
vols = with_prefix(vols, 'd');

%% 5. Nuisance regression
wm_csf = mean_signals(vols, {ref.mask_wm, ref.mask_csf});
vols = regress_nuisance(vols, [motion, motion.^2, wm_csf], ref.mask_brain, 'n');

%% 6. Regional time series
n_regions = max(spm_read_vols(spm_vol(cfg.atlas)), [], 'all');
ts = struct();
ts.signal   = regional_signal(vols, ref.parcellation, ref.gm, n_regions);
ts.TR       = cfg.fmri.TR.(scan.protocol);
ts.motion   = motion;
ts.date     = datestr(scan.date, 'yyyy-mm-dd');
ts.protocol = scan.protocol;
save(out_file, '-struct', 'ts');

if ~cfg.fmri.keep_volumes
    rmdir(vol_dir, 's');
end
end

%% ---------------------------------------------------------------------------
function ref = resample_t1_images(t1, voxel_size, out_dir)
% Put the T1 and everything derived from it on a common 2 mm grid.
% Continuous images use cubic B-splines; masks and labels use nearest neighbour.
r = @(file, order) resample_image(file, voxel_size, order, ...
        fullfile(out_dir, ['r' name_of(file)]));
ref.t1           = r(t1.image, 3);
ref.gm           = r(t1.gm, 3);
ref.mask_brain   = r(t1.mask_brain, 0);
ref.mask_wm      = r(t1.mask_wm, 0);
ref.mask_csf     = r(t1.mask_csf, 0);
ref.parcellation = r(t1.parcellation, 0);
end

function vols = coregister(mean_image, vols, ref_image)
% Estimate mean fMRI -> T1 and reslice all volumes onto the 2 mm T1 grid.
% Reslicing also applies the realignment stored in each volume's header.
c = struct();
c.ref    = {[ref_image ',1']};
c.source = {[mean_image ',1']};
c.other  = strcat(cellstr(vols), ',1');
c.eoptions.cost_fun = 'nmi';
c.eoptions.sep      = [4 2];
c.eoptions.tol      = [0.02 0.02 0.02 0.001 0.001 0.001 0.01 0.01 0.01 0.001 0.001 0.001];
c.eoptions.fwhm     = [7 7];
c.roptions.interp   = 4;
c.roptions.wrap     = [0 0 0];
c.roptions.mask     = 0;
c.roptions.prefix   = 'r';
matlabbatch{1}.spm.spatial.coreg.estwrite = c;
spm_jobman('run', matlabbatch);
vols = with_prefix(vols, 'r');
end

function signals = mean_signals(vols, mask_files)
% Mean signal within each mask at every time point (time x masks).
masks = cellfun(@(f) spm_read_vols(spm_vol(f)) > 0, mask_files, 'UniformOutput', false);
signals = zeros(size(vols,1), numel(masks));
for t = 1:size(vols,1)
    Y = spm_read_vols(spm_vol(deblank(vols(t,:))));
    for m = 1:numel(masks)
        signals(t,m) = mean(Y(masks{m}), 'omitnan');
    end
end
end

function signal = regional_signal(vols, parcellation_file, gm_file, n_regions)
% Gray matter-weighted mean of each parcel (regions x time). Parcels absent
% from this subject's parcellation stay zero.
labels = round(spm_read_vols(spm_vol(parcellation_file)));
gm     = spm_read_vols(spm_vol(gm_file));
voxels = arrayfun(@(r) find(labels == r), 1:n_regions, 'UniformOutput', false);

signal = zeros(n_regions, size(vols,1));
for t = 1:size(vols,1)
    Y = spm_read_vols(spm_vol(deblank(vols(t,:))));
    for r = 1:n_regions
        idx = voxels{r}(~isnan(Y(voxels{r})));   % a few edge voxels can be NaN after reslicing
        signal(r,t) = sum(Y(idx) .* gm(idx)) / (sum(gm(idx)) + eps);
    end
end
end

function name = name_of(file)
[~, n, e] = fileparts(file);
name = [n e];
end
