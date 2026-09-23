# Connectome pipeline

MATLAB pipeline that preprocesses longitudinal T1-weighted, resting-state fMRI and
diffusion MRI, and builds binarized **functional** and **structural** networks for
every session on a common atlas (Schaefer 2018, 100 parcels, 7 networks).

All analysis happens in each subject's **native space**: the atlas is brought to the
subject by inverse normalization rather than the images being normalized to MNI.

## Pipeline

```
T1 ─► preprocess_t1 ─► tissue masks + native-space atlas ─┬─────────────────────────┐
                                                           │                         │
fMRI ─► preprocess_fmri ─► regional time series ─► functional_connectivity ─► binarize_top_density ─► functional network
                                                                                     │
DWI ──► preprocess_dwi ──► weighted structural connectome ──────────────────► binarize_top_density ─► structural network
```

| File | What it does |
|---|---|
| `run_pipeline.m` | Entry point. Loops over subjects and runs every stage. |
| `pipeline_config.m` | Every path and parameter. The only file you need to edit. |
| `read_sessions.m` | Reads the sessions CSV that lists every scan to process. |
| `sessions_example.csv` | Example sessions CSV. |
| `stages/preprocess_t1.m` | AC-PC alignment, segmentation, tissue masks, native-space atlas (SPM12) |
| `stages/preprocess_fmri.m` | fMRI preprocessing, ending in regional time series (SPM12) |
| `stages/functional_connectivity.m` | Bandpass filter + Pearson correlation matrix |
| `stages/preprocess_dwi.m` | Diffusion preprocessing, tractography, structural connectome (MRtrix3) |
| `utils/binarize_top_density.m` | Shared binarization: keep the top 20% of edges |
| `utils/` | Small helpers (resampling, nuisance regression, shell commands) |
| `external/cspm_lmgs.m` | LMGS global signal removal, P. Macey (unmodified) |

## Methods

### Functional
Functional images were preprocessed in MATLAB using SPM12. Preprocessing included
motion correction (SPM *realign*), coregistration to each session's T1-weighted
structural image via normalized mutual information, and reslicing to 2 mm isotropic
voxels. The first 10 volumes were discarded. Slice timing correction was omitted as
the dataset combines multiple acquisition protocols. Acquisition protocol was held
constant within each subject across all longitudinal timepoints. Regional time series
were extracted as gray matter–weighted means within each atlas parcel, registered to
native space via inverse normalization. The global signal was removed (Macey et al.,
2004), and the time series were regressed against motion parameters and mean white
matter/CSF signal, then bandpass filtered (0.01–0.08 Hz). Spatial normalization and
smoothing were omitted to preserve native-space anatomical specificity. The network
from the signed correlation matrix was binarized at 20% density, retaining only
positive connections.

| Methods step | Code |
|---|---|
| Discard first 10 volumes | `preprocess_fmri` step 1 (`cfg.fmri.n_dummy`) |
| Motion correction | `preprocess_fmri` step 2 (`spm_realign`) |
| Coregistration to T1 (NMI), 2 mm reslice | `preprocess_fmri` step 3 |
| Atlas in native space via inverse normalization | `preprocess_t1` step 4 |
| Global signal removal | `preprocess_fmri` step 4 (`cspm_lmgs`) |
| Motion + WM/CSF regression | `preprocess_fmri` step 5 (`regress_nuisance`) |
| Gray matter–weighted regional means | `preprocess_fmri` step 6 |
| Bandpass 0.01–0.08 Hz, correlation | `functional_connectivity` |
| 20% density, positive only | `binarize_top_density` |

### Structural
Diffusion MRI data were preprocessed following the MRtrix3 structural connectome
pipeline. Preprocessing included MP-PCA denoising, Gibbs ringing removal, motion and
eddy current correction (FSL *eddy* via *dwifslpreproc*, with reversed phase-encoding
correction applied where available), and bias field correction (ANTs N4). Fiber
orientation distributions were estimated via multi-tissue constrained spherical
deconvolution with Dhollander response functions, followed by global intensity
normalization. Five-tissue-type segmentation of the coregistered T1 image (FSL *FAST*
via *5ttgen*) was registered to diffusion space for anatomically-constrained
probabilistic tractography (*iFOD2*, 10 million streamlines, gray matter–white matter
interface seeding), with streamline weights assigned via *SIFT2*. Streamlines were
mapped to nodes defined by the atlas parcellation using *tck2connectome*, producing
structural connectomes with symmetric, zero-diagonal edges scaled by inverse node
volume. Acquisition protocol (single-shell or multiband multi-shell) was held constant
within each subject across timepoints. Adjacency matrices were binarized by retaining
the top 20% of edges by connection weight.

Each numbered step in `stages/preprocess_dwi.m` corresponds to one clause above.

## Requirements

- MATLAB (R2019b or later) with the Image Processing, Signal Processing, and
  Statistics and Machine Learning toolboxes
- [SPM12](https://www.fil.ion.ucl.ac.uk/spm/software/spm12/)
- [MRtrix3](https://www.mrtrix.org/), [FSL](https://fsl.fmrib.ox.ac.uk/) and
  [ANTs](https://github.com/ANTsX/ANTs) on the system PATH (diffusion stage only; Linux or macOS)
- Reference images, placed in `reference/` (or point `pipeline_config.m` elsewhere):
  - `Schaefer2018_100Parcels_7Networks_order_FSLMNI152_2mm.nii`
    ([CBIG repository](https://github.com/ThomasYeoLab/CBIG/tree/master/stable_projects/brain_parcellation/Schaefer2018_LocalGlobal))
  - `TPM_Lorio_Draganski.nii`, the enhanced tissue probability maps of Lorio et al. (2016)

## Input

The pipeline makes no assumptions about how your data is organized. Instead, list
every scan in a CSV file (see `sessions_example.csv`) with one row per scan:

| Column | Contents |
|---|---|
| `subject` | Subject ID |
| `modality` | `T1`, `fMRI` or `DWI` |
| `date` | Acquisition date, `YYYY-MM-DD` |
| `protocol` | `basic` or `multiband` for fMRI and DWI; blank for T1 |
| `path` | T1 and fMRI: NIfTI file (`.nii`). DWI: DICOM folder, or `.mif` with an embedded gradient table |

The protocol sets the fMRI repetition time (basic 3 s, multiband 0.607 s; see
`pipeline_config.m`). Each fMRI and DWI session is paired with the subject's T1
closest in date. Subjects with scans from both protocols in a modality are excluded
from that modality, and subjects with fewer than two sessions of a modality are
skipped for it.

## Outputs

```
<output_root>/<subject>/
  anat/T1_<date>/            aligned T1, c1–c3, masks, parcellation_T1.nii
  func/fMRI_<date>/          regional_timeseries.mat (regions x time, TR, motion)
  dwi/DWI_<date>/            MRtrix intermediates, connectome.csv
  networks/
    functional_<date>.mat    weighted, binary, density, date, protocol
    functional_<date>.txt    binary adjacency matrix (tab-delimited)
    structural_<date>.mat
    structural_<date>.txt
```

## Running

1. List your scans in a sessions CSV.
2. Edit `pipeline_config.m`.
3. Run `run_pipeline.m`.

Finished sessions are skipped on re-run (`cfg.skip_existing`), so the pipeline can be
stopped and restarted.

## References

- Ashburner et al. (2021). SPM12 Manual.
- Macey et al. (2004). A method for removal of global effects from fMRI time series. *NeuroImage* 22, 360–366.
- Tournier et al. (2019). MRtrix3. *NeuroImage* 202, 116137.
- Jeurissen et al. (2014). Multi-tissue constrained spherical deconvolution. *NeuroImage* 103, 411–426.
- Smith et al. (2012). Anatomically-constrained tractography. *NeuroImage* 62, 1924–1938.
- Smith et al. (2015). SIFT2. *NeuroImage* 119, 338–351.
- Schaefer et al. (2018). Local-global parcellation of the human cerebral cortex. *Cerebral Cortex* 28, 3095–3114.

Helper code adapted from Y. Iturria-Medina, P. Valdés-Hernández and Y. Alemán-Gómez
(Cuban Neuroscience Center / Montreal Neurological Institute).
#   M R I P r e p r o c e s s i n g P i p e l i n e  
 