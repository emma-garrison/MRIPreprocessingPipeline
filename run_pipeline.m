%% run_pipeline.m
% Preprocess T1, resting-state fMRI and diffusion MRI and build binarized
% functional and structural networks for every subject.
%
% List your scans in a sessions CSV, edit
% pipeline_config.m, then run this script. For each subject:
%   1. preprocess_t1            every T1: segmentation, masks, native-space atlas
%   2. preprocess_fmri          each fMRI session -> regional time series
%      functional_connectivity  -> signed correlation matrix
%   3. preprocess_dti           each diffusion session -> weighted structural connectome
%   4. binarize_top_density     both network types, top 20% of edges
%
% Each fMRI / DTI session uses the T1 acquired closest in time.
% Outputs go to <output_root>/<subject>/{anat,func,dti,networks}.

cfg = pipeline_config();
here = fileparts(mfilename('fullpath'));
addpath(cfg.paths.spm, here, fullfile(here, 'stages'), fullfile(here, 'utils'), fullfile(here, 'external'));
spm('defaults', 'fmri');
spm_jobman('initcfg');
if ~isempty(cfg.paths.extra_system_path)
    setenv('PATH', [strjoin(cfg.paths.extra_system_path, pathsep) pathsep getenv('PATH')]);
end

[subjects, all_sessions] = read_sessions(cfg.paths.sessions);
fprintf('Found %d subjects.\n', numel(subjects));

for i = 1:numel(subjects)
    id = subjects{i};
    fprintf('\n===== %s (%d/%d) =====\n', id, i, numel(subjects));
    out_dir = fullfile(cfg.paths.output_root, id);
    sessions = all_sessions(i);

    do_fmri = usable(sessions.fmri, cfg, id, 'fMRI');
    do_dti  = usable(sessions.dti,  cfg, id, 'DTI');
    if ~(do_fmri || do_dti), continue, end

    try
        % 1. Structural preprocessing
        t1 = struct([]);
        for s = sessions.t1
            t1 = [t1, preprocess_t1(s, fullfile(out_dir, 'anat'), cfg)]; %#ok<AGROW>
        end

        % 2. Functional networks
        if do_fmri
            for s = sessions.fmri
                ts = preprocess_fmri(s, closest_t1(t1, s.date), fullfile(out_dir, 'func', s.name), cfg);
                W  = functional_connectivity(ts.signal, ts.TR, cfg.fmri.band);
                save_network(fullfile(out_dir, 'networks', ['functional_' datestr(s.date, 'yyyy-mm-dd')]), W, s, cfg);
            end
        end

        % 3. Structural networks
        if do_dti
            for s = sessions.dti
                W = preprocess_dti(s, closest_t1(t1, s.date), fullfile(out_dir, 'dti', s.name), cfg);
                save_network(fullfile(out_dir, 'networks', ['structural_' datestr(s.date, 'yyyy-mm-dd')]), W, s, cfg);
            end
        end
    catch err
        fprintf(2, '%s failed: %s\n', id, err.message);
    end
end

%% ---------------------------------------------------------------------------
function ok = usable(scans, cfg, id, modality)
% A subject's scans of one modality are used only if they share one
% acquisition protocol and there are enough of them.
ok = false;
if numel(unique({scans.protocol})) > 1
    fprintf('%s: %s excluded (mixed acquisition protocols)\n', id, modality);
elseif numel(scans) < cfg.min_sessions
    fprintf('%s: %s skipped (%d sessions)\n', id, modality, numel(scans));
else
    ok = true;
end
end

function t = closest_t1(t1, date)
if isempty(t1), error('No T1 image available'); end
[~, k] = min(abs([t1.date] - date));
t = t1(k);
end

function save_network(file_base, W, scan, cfg)
% Save the weighted and binarized network (.mat) and the binary adjacency
% matrix as tab-delimited text.
if any(isnan(W(:)))
    warning('%s: NaNs in connectivity matrix, network not saved', file_base);
    return
end
net = struct();
net.weighted = W;
net.binary   = binarize_top_density(W, cfg.network_density);
net.density  = cfg.network_density;
net.date     = datestr(scan.date, 'yyyy-mm-dd');
net.protocol = scan.protocol;

folder = fileparts(file_base);
if ~isfolder(folder), mkdir(folder); end
save([file_base '.mat'], '-struct', 'net');
writematrix(net.binary, [file_base '.txt'], 'Delimiter', 'tab');
end
