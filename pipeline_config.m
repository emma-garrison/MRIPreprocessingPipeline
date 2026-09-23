function cfg = pipeline_config()
% PIPELINE_CONFIG  All paths and parameters for the connectome pipeline.
%
% Edit this file (or a copy of it) before running run_pipeline.m. Nothing
% else in the pipeline should need editing to move it to a new machine.

%% Input data ---------------------------------------------------------------
% Table listing every scan to process (see sessions_example.csv and README.md).
cfg.paths.sessions = '/path/to/sessions.csv';

% All pipeline outputs are written here, one folder per subject.
% Raw input data is never modified.
cfg.paths.output_root = '/path/to/derivatives';

%% Software -----------------------------------------------------------------
cfg.paths.spm      = '/path/to/spm12';
cfg.paths.pipeline = fileparts(mfilename('fullpath'));

% Folders prepended to the system PATH so MATLAB's system() calls can find
% MRtrix3, FSL and ANTs (e.g. {'/opt/mrtrix3/bin', '~/ANTs/bin'}).
% FSL must also be configured (FSLDIR, FSLOUTPUTTYPE) in the shell that
% launches MATLAB.
cfg.paths.extra_system_path = {};

%% Reference images ---------------------------------------------------------
% Parcellation in MNI space; brought into each subject's native space by
% inverse normalization. Labels must be integers 1..N.
cfg.atlas = fullfile(cfg.paths.pipeline, 'reference', ...
    'Schaefer2018_100Parcels_7Networks_order_FSLMNI152_2mm.nii');

% Tissue probability maps used for T1 segmentation (Lorio/Draganski TPMs).
cfg.tpm = fullfile(cfg.paths.pipeline, 'reference', 'TPM_Lorio_Draganski.nii');

%% Subject selection --------------------------------------------------------
% Subjects scanned with more than one acquisition protocol (basic and
% multiband) for a modality are excluded from that modality.
% Subjects with fewer sessions of a modality than this are skipped for it
% (longitudinal design).
cfg.min_sessions = 2;

%% fMRI ---------------------------------------------------------------------
cfg.fmri.TR.basic     = 3;       % seconds
cfg.fmri.TR.multiband = 0.607;   % seconds
cfg.fmri.n_dummy      = 10;      % initial volumes discarded (Chao-Gan et al., 2010)
cfg.fmri.voxel_size   = 2;       % isotropic reslice size (mm)
cfg.fmri.band         = [0.01 0.08];   % bandpass (Hz)
cfg.fmri.keep_volumes = false;   % keep the intermediate 3D volumes (large) for QC

%% Diffusion ----------------------------------------------------------------
cfg.dti.n_streamlines = 10e6;
cfg.dti.max_length    = 250;     % mm
cfg.dti.fod_cutoff    = 0.06;
cfg.dti.nthreads      = 8;

%% Networks -----------------------------------------------------------------
cfg.network_density = 0.20;      % fraction of possible edges kept when binarizing

%% Re-running ---------------------------------------------------------------
% Skip any session whose final output already exists.
cfg.skip_existing = true;
end
