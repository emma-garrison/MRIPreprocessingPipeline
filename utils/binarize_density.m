function A = binarize_density(W, density)
% BINARIZE_DENSITY  Binary network keeping the strongest edges.
%
%   A = binarize_density(W, density)
%
% W is a symmetric weighted matrix (correlations or streamline weights).
% The top `density` fraction of possible edges (N*(N-1)/2) by weight is set
% to 1; only positive weights can be kept. The diagonal is always 0.
% Used for both the functional and the structural networks.

N = size(W,1);
upper = triu(true(N), 1);
weights = sort(W(upper), 'descend');
threshold = weights(round(density * N*(N-1)/2));

A = double(W >= threshold & W > 0);
A(1:N+1:end) = 0;
end
