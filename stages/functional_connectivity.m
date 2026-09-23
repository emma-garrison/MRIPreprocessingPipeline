function W = functional_connectivity(signal, TR, band)

% FUNCTIONAL_CONNECTIVITY  
% 
% Signed Pearson correlation matrix of bandpass-filtered regional signals.
%
% W = functional_connectivity(signal, TR, band)
%
% signal is regions x time; band is [low high] in Hz (e.g. [0.01 0.08]).
% Requires the Signal Processing Toolbox (bandpass) and the Statistics and
% Machine Learning Toolbox (corr). Regions with no signal give NaN rows.

    filtered = bandpass(signal', band, 1/TR);    % filters each region (column)
    W = corr(filtered, 'type', 'Pearson');
    W(1:size(W,1)+1:end) = 0;
end
