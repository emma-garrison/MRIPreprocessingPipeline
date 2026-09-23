function W = preprocess_dti(scan, t1, out_dir, cfg)
% PREPROCESS_DTI  Diffusion preprocessing and structural connectome (MRtrix3).
%
%   1. MP-PCA denoising, Gibbs ringing removal
%   2. Motion and eddy current correction (FSL eddy via dwifslpreproc, using
%      reversed phase-encoding data where the image headers provide it)
%   3. Bias field correction (ANTs N4) and brain mask
%   4. Multi-tissue CSD with Dhollander response functions, followed by
%      global intensity normalization (mtnormalise)
%   5. Five-tissue-type segmentation of the T1 (FSL via 5ttgen), rigidly
%      registered to diffusion space together with the atlas parcellation
%   6. Anatomically-constrained probabilistic tractography (iFOD2, seeded at
%      the gray matter-white matter interface) with SIFT2 streamline weights
%   7. Connectome: symmetric, zero diagonal, scaled by inverse node volume
%
% Returns the weighted connectome (regions x regions), also saved to
% out_dir/connectome.csv. Needs MRtrix3, FSL and ANTs on the system PATH.

out_file = fullfile(out_dir, 'connectome.csv');
if cfg.skip_existing && isfile(out_file)
    W = readmatrix(out_file);
    return
end
if ~isfolder(out_dir), mkdir(out_dir); end
f = @(name) fullfile(out_dir, name);
threads = cfg.dti.nthreads;

%% 1-3. Preprocessing
run_cmd('dwidenoise "%s" "%s" -noise "%s"', scan.path, f('dti_denoised.mif'), f('noise.mif'));
run_cmd('mrdegibbs "%s" "%s"', f('dti_denoised.mif'), f('dti_degibbs.mif'));
run_cmd(['dwifslpreproc "%s" "%s" -rpe_header -nthreads %d ' ...
         '-eddy_options " --slm=linear --data_is_shelled"'], ...
        f('dti_degibbs.mif'), f('dti_preproc.mif'), threads);
run_cmd('dwibiascorrect ants "%s" "%s" -bias "%s"', f('dti_preproc.mif'), f('dti.mif'), f('bias.mif'));
run_cmd('dwi2mask "%s" "%s"', f('dti.mif'), f('mask.mif'));

%% 4. Fiber orientation distributions
run_cmd('dwi2response dhollander "%s" "%s" "%s" "%s"', ...
        f('dti.mif'), f('wm_response.txt'), f('gm_response.txt'), f('csf_response.txt'));

% Single-shell data can only support two tissues (WM + CSF); multi-shell data supports three.
if n_shells(f('dti.mif')) > 1
    tissues = {'wm', 'gm', 'csf'};
else
    tissues = {'wm', 'csf'};
end
fod_args  = cellfun(@(t) sprintf('"%s" "%s"', f([t '_response.txt']), f([t '_fod.mif'])),  tissues, 'UniformOutput', false);
norm_args = cellfun(@(t) sprintf('"%s" "%s"', f([t '_fod.mif']),      f([t '_fod_norm.mif'])), tissues, 'UniformOutput', false);
run_cmd('dwi2fod msmt_csd "%s" %s -mask "%s"', f('dti.mif'), strjoin(fod_args), f('mask.mif'));
run_cmd('mtnormalise %s -mask "%s"', strjoin(norm_args), f('mask.mif'));

%% 5. Tissue segmentation and registration to diffusion space
run_cmd('5ttgen fsl "%s" "%s"', t1.image, f('5tt_T1space.mif'));

% Rigid registration of the mean b=0 image to the T1 (FSL flirt)
run_cmd('dwiextract "%s" - -bzero | mrmath - mean "%s" -axis 3', f('dti.mif'), f('mean_b0.nii.gz'));
run_cmd('mrconvert "%s" "%s" -coord 3 0', f('5tt_T1space.mif'), f('5tt_vol0.nii.gz'));
run_cmd('flirt -in "%s" -ref "%s" -interp nearestneighbour -dof 6 -omat "%s"', ...
        f('mean_b0.nii.gz'), f('5tt_vol0.nii.gz'), f('diff2struct_fsl.mat'));
run_cmd('transformconvert "%s" "%s" "%s" flirt_import "%s"', ...
        f('diff2struct_fsl.mat'), f('mean_b0.nii.gz'), f('5tt_vol0.nii.gz'), f('diff2struct.txt'));

% Move the 5TT image and the atlas parcellation (both in T1 space) into diffusion space
run_cmd('mrtransform "%s" -linear "%s" -inverse "%s"', f('5tt_T1space.mif'), f('diff2struct.txt'), f('5tt.mif'));
run_cmd('mrconvert "%s" "%s" -datatype uint32', t1.parcellation, f('parcels_T1space.mif'));
run_cmd('mrtransform "%s" -linear "%s" -inverse "%s"', f('parcels_T1space.mif'), f('diff2struct.txt'), f('parcels.mif'));
run_cmd('5tt2gmwmi "%s" "%s"', f('5tt.mif'), f('gmwm_interface.mif'));

%% 6. Tractography
run_cmd(['tckgen "%s" "%s" -algorithm iFOD2 -act "%s" -backtrack -seed_gmwmi "%s" ' ...
         '-select %d -maxlength %g -cutoff %g -nthreads %d'], ...
        f('wm_fod_norm.mif'), f('tracks.tck'), f('5tt.mif'), f('gmwm_interface.mif'), ...
        cfg.dti.n_streamlines, cfg.dti.max_length, cfg.dti.fod_cutoff, threads);
run_cmd('tcksift2 "%s" "%s" "%s" -act "%s" -nthreads %d', ...
        f('tracks.tck'), f('wm_fod_norm.mif'), f('sift2_weights.txt'), f('5tt.mif'), threads);

%% 7. Connectome
run_cmd(['tck2connectome "%s" "%s" "%s" -tck_weights_in "%s" ' ...
         '-symmetric -zero_diagonal -scale_invnodevol -out_assignments "%s"'], ...
        f('tracks.tck'), f('parcels.mif'), out_file, f('sift2_weights.txt'), f('assignments.csv'));
W = readmatrix(out_file);
end

function n = n_shells(dti_file)
% Number of non-zero b-value shells in a DWI series.
b = str2num(run_cmd('mrinfo "%s" -shell_bvalues', dti_file)); %#ok<ST2NM>
n = nnz(b > 50);
end
