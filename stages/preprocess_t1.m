function t1 = preprocess_t1(scan, out_dir, cfg)
% PREPROCESS_T1  Structural preprocessing of one T1-weighted image (SPM12).
%
%   1. Rigid alignment to the AC-PC line
%   2. Unified segmentation into gray matter, white matter and CSF
%      (Lorio/Draganski tissue probability maps)
%   3. Hard tissue masks: each voxel labelled by its most probable tissue
%   4. Atlas brought into native space by inverse normalization, resampled
%      onto the T1 grid and restricted to gray matter
%
% The T1 is copied into out_dir first, so the raw data is never modified.
% Returns a struct with the paths of everything later stages need.

nam = 'T1';
out_dir = fullfile(out_dir, scan.name);
file = @(prefix) fullfile(out_dir, [prefix nam '.nii']);

t1 = struct( ...
    'date',         scan.date, ...
    'image',        file(''), ...           % AC-PC aligned T1
    'gm',           file('c1'), ...         % gray matter probability
    'mask_gm',      file('mask_gm_'), ...
    'mask_wm',      file('mask_wm_'), ...
    'mask_csf',     file('mask_csf_'), ...
    'mask_brain',   file('mask_brain_'), ...
    'parcellation', file('parcellation_'));  % native-space atlas, GM only

if cfg.skip_existing && isfile(t1.parcellation), return, end
if ~isfolder(out_dir), mkdir(out_dir); end
copyfile(scan.path, t1.image);

align_to_acpc(t1.image, cfg.tpm);
segment(t1.image, cfg.tpm);                   % writes c1-c3 and y_/iy_ deformations
write_tissue_masks(file('c1'), file('c2'), file('c3'), t1);
native_space_atlas(cfg.atlas, file('iy_'), t1);
end

%% 1. AC-PC alignment ---------------------------------------------------------
function align_to_acpc(image, tpm_file)
% Coarse affine registration to the tissue priors, keeping only its rigid
% part, which is written into the image header. Two starting estimates
% (header origin vs. centre of the field of view) are tried and the better
% fit kept, as in SPM's spm_preproc_run.
V   = spm_vol(image);
tpm = spm_load_priors8(spm_vol(tpm_file));

V_centred = V;
V_centred.mat(1:3,4) = -V.mat(1:3,1:3) * ((V.dim(:) + 1) / 2);
[A_centred, ll_centred] = spm_maff8(V_centred, 8, 16, tpm, [], 'mni');
A_centred = A_centred * (V_centred.mat / V.mat);

[A_header, ll_header] = spm_maff8(V, 8, 16, tpm, [], 'mni');

if ll_centred > ll_header, A = A_centred; else, A = A_header; end
A = spm_maff8(V, 8, 16, tpm, A, 'mni');
A = spm_maff8(V, 8,  0, tpm, A, 'mni');

% Closest rigid-body transform to the affine (from SPM's comm_adjust)
[U, ~, W] = svd(A(1:3,1:3));
R = U * W';
R(:,4) = R * (A(1:3,1:3) \ A(1:3,4));
R(4,4) = 1;
spm_get_space(image, R * spm_get_space(image));
end

%% 2. Segmentation ------------------------------------------------------------
function segment(image, tpm_file)
n_gaussians = [1 1 2 3 4 2];
b = struct();
b.channel.vols     = {[image ',1']};
b.channel.biasreg  = 0.001;
b.channel.biasfwhm = 60;
b.channel.write    = [0 0];
for k = 1:6
    b.tissue(k).tpm    = {sprintf('%s,%d', tpm_file, k)};
    b.tissue(k).ngaus  = n_gaussians(k);
    b.tissue(k).native = [k <= 3, 0];       % write native-space c1, c2, c3 only
    b.tissue(k).warped = [0 0];
end
b.warp.mrf     = 1;
b.warp.cleanup = 1;
b.warp.reg     = [0 0.001 0.5 0.05 0.2];
b.warp.affreg  = 'mni';
b.warp.fwhm    = 0;
b.warp.samp    = 3;
b.warp.write   = [1 1];                     % inverse (iy_) and forward (y_) fields

matlabbatch{1}.spm.spatial.preproc = b;
spm_jobman('run', matlabbatch);
end

%% 3. Tissue masks ------------------------------------------------------------
function write_tissue_masks(gm_file, wm_file, csf_file, t1)
% Adapted from ProbMasks_mod.m (Y. Iturria-Medina & P. Valdes-Hernandez,
% Cuban Neuroscience Center, 2005).
V   = spm_vol(gm_file);
GM  = spm_read_vols(V);
WM  = spm_read_vols(spm_vol(wm_file));
CSF = spm_read_vols(spm_vol(csf_file));
other = 1 - (GM + WM + CSF);

gm  = imfill(GM  > WM & GM  > CSF & GM  > other, 'holes');
wm  = imfill(WM  > GM & WM  > CSF & WM  > other, 'holes');
csf =        CSF > GM & CSF > WM  & CSF > other;
brain = imfill(gm | wm | csf, 'holes');

write_mask(V, t1.mask_gm,    gm);
write_mask(V, t1.mask_wm,    wm);
write_mask(V, t1.mask_csf,   csf);
write_mask(V, t1.mask_brain, brain);
end

function write_mask(V, file, mask)
V.fname = file;
V.dt    = [spm_type('uint8') 0];
V.pinfo = [1; 0; 0];
spm_write_vol(V, double(mask));
end

%% 4. Native-space atlas ------------------------------------------------------
function native_space_atlas(atlas_file, inverse_deformation, t1)
out_dir = fileparts(t1.image);

% Warp the MNI atlas into native space (nearest neighbour keeps labels intact).
% SPM writes next to the input, so work on a copy in the output folder.
atlas_copy = fullfile(out_dir, 'atlas_mni.nii');
copyfile(atlas_file, atlas_copy);
w = struct();
w.subj.def        = {inverse_deformation};
w.subj.resample   = {[atlas_copy ',1']};
w.woptions.bb     = NaN(2,3);
w.woptions.vox    = [1 1 1];
w.woptions.interp = 0;
w.woptions.prefix = 'w';
matlabbatch{1}.spm.spatial.normalise.write = w;
spm_jobman('run', matlabbatch);
warped = fullfile(out_dir, 'watlas_mni.nii');

% Resample onto the exact T1 grid
spm_reslice({t1.gm; warped}, struct('interp', 0, 'which', 1, 'mean', 0, 'prefix', 'r'));
resliced = fullfile(out_dir, 'rwatlas_mni.nii');

% Keep only gray-matter voxels
V = spm_vol(resliced);
labels = round(spm_read_vols(V));
labels(spm_read_vols(spm_vol(t1.mask_gm)) == 0) = 0;
V.fname = t1.parcellation;
V.dt    = [spm_type('uint16') 0];
V.pinfo = [1; 0; 0];
spm_write_vol(V, labels);

delete(atlas_copy, warped, resliced);
end
