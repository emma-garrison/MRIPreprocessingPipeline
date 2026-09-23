function output = run_cmd(varargin)
% RUN_CMD  Run a shell command built with sprintf; stop the pipeline if it fails.
%   run_cmd('mrconvert "%s" "%s"', in_file, out_file)
cmd = sprintf(varargin{:});
fprintf('>> %s\n', cmd);
[status, output] = system(cmd);
if status ~= 0
    error('Command failed (exit code %d):\n%s\n%s', status, cmd, output);
end
end
