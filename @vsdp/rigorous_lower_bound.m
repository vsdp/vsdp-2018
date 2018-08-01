function obj = rigorous_lower_bound (obj, xbnd)
% RIGOROUS_LOWER_BOUND  Rigorous lower bound for conic programming.
%
%   obj.rigorous_lower_bound()  Compute a rigorous lower bound of the primal
%      optimal value  c'*x  and a rigorous enclosure of a dual strict feasible
%      (near optimal) solution of a VSDP object 'obj'.
%
%   obj.rigorous_lower_bound(xbnd)  Optionally a priori known finite upper
%      bounds on the primal optimal solution 'x' can be provided to speed up
%      the computation time.  It is recommend to prefer infinite or no bounds
%      at all instead of unreasonable large bounds.  This improves the quality
%      of the lower bound in many cases, but may increase the computational
%      time.
%
%      The individual upper bounds 'xbnd(j)' depends on the cone:
%
%      - For each free and linear (LP) variable a scalar, such that
%
%                               x(j) <= xbnd(j) <= inf  j = 1:(K.f + K.l).
%
%      - For each second order cone (SOCP) variable a scalar, such that
%
%          x(j,1) - norm(x(j,2:end)) <= xbnd(j) <= inf  j = 1:length(K.q).
%
%      - For each semidefinite (SDP) matrix variable X(j) a scalar, such that
%
%                     max(eig(X(j))) <= xbnd(j) <= inf  j = 1:length(K.s).
%
%      Thus 'n = K.f + K.l + length(K.q) + length (K.s)' is the total number of
%      required bounds, which may be infinite.
%
%   See also vsdp, vsdp.rigorous_upper_bound.
%

% Copyright 2004-2018 Christian Jansson (jansson@tuhh.de)

% Check, if primal upper bounds are given, otherwise use default upper bounds.
num_of_bounds = obj.K.f + obj.K.l + length (obj.K.q) + length (obj.K.s);
if (nargin < 2)
  xbnd = inf (num_of_bounds, 1);
else
  xbnd = xbnd(:);
  if (length (xbnd) ~= num_of_bounds)
    error ('VSDP:rigorous_lower_bound:badXBND', ...
      ['rigorous_lower_bound: The length of the upper bound vector ', ...
      '''xbnd'' must be %d, but is %d.'], num_of_bounds, length (xbnd));
  end
end

% If the problem was not approximately solved before, do it now.
if (isempty (obj.solutions('Approximate solution')))
  warning ('VSDP:rigorous_lower_bound:noApproximateSolution', ...
    ['rigorous_lower_bound: The conic problem has no approximate ', ...
    'solution yet, which is now computed using ''%s''.'], obj.options.SOLVER);
  obj.solve (obj.options.SOLVER, 'Approximate solution');
end
y = intval (obj.solutions('Approximate solution').y);

% Bound and pertubation parameter.  alpha = obj.options.ALPHA
%
%  epsilon = epsilon + (alpha.^k) .* dl_,  where dl_ < 0.
%
dl        = vsdp_indexable (zeros (num_of_bounds, 1), obj);
k         = zeros (num_of_bounds, 1);
epsilon   = zeros (num_of_bounds, 1);  % factor for perturbation
c_epsilon = zeros (obj.n, 1);          % 'epsilon' translated to 'c' via 'vidx'.

% Index vector for perturbation.  In case of semidefinite programs, only
% the diagonal elements have to be perturbed.  Those are easily obtained:
vidx = vsdp.sindex (obj);          % Get only diagonal entries of SDP cones.
vidx(1:(obj.K.f + obj.K.l)) = true;  % Copy free and linear part directly.
if (~isempty (obj.K.q))
  % In case of second-order cones, only the first element is pertubed.
  vidx(obj.K.idx.q(:,1)) = true;
end
% And another index vector for semidefinite block perturbation.  This one maps a
% single epsilon(j) to the diagonal of the SDP block j.
%
%                 [1  ]   [epsilon_1]
%    sdp_matrix = [  1] * [epsilon_2],  for  obj.K.s = [1, 2]
%                 [  1]
n = sum (obj.K.s);
cols = zeros (n, 1);
cols(cumsum ([1; obj.K.s(1:end-1)])) = 1;
sdp_matrix = sparse (1:n, cumsum (cols), 1);

% Algorithm for both finite and infinite upper bounds 'xbnd'.
rlb = tic;
iter = 0;
while (iter <= obj.options.ITER_MAX)
  % If infinite upper bounds for free variables are given.  Ensure, that
  % the approximate dual solution 'y' solves the free variable part, see
  %
  %   https://vsdp.github.io/references.html#Anjos2007
  %
  % for details.
  if (any (isinf (xbnd(1:obj.K.f))))
    % Compute rigorous enclosure for underdetermined linear interval system of
    % dimension (K.f x m):
    %
    %    At.f * y = c.f
    %
    y = vsdp.verify_uls (obj, obj.At(1:obj.K.f,:), obj.c(1:obj.K.f), mid (y));
    if (~isintval (y) || any (isnan (y)))
      error ('VSDP:rigorous_lower_bound:noBoundsForFreeVariables', ...
        ['rigorous_lower_bound: Could not find a rigorous solution of the ', ...
        'linear  system of free variables.']);
    end
  end
  
  % Step 1: Compute rigorous enclosure [d] for  c - At*y.
  d = vsdp_indexable (obj.c - obj.At * y, obj);
  
  % Step 2: Rigorous lower bounds on cone eigenvalues
  %
  % Free variables: if infinite upper bounds for free variables are given, we
  %                 ensured above, that the solution is contained, thus we
  %                 assume no defect!
  if (any (isinf (xbnd(1:obj.K.f))))
    dl.f = zeros (obj.K.f, 1);
  else
    dl.f = mag (d.f);
  end
  
  % LP cone variables.
  dl.l = inf_ (d.l);
  
  % Second-order cone variables.
  offset = obj.K.f + obj.K.l;
  for j = 1:length (obj.K.q)
    dq = d.q(j);
    dl(j + offset,1) = inf_ (dq(1) - norm (dq(2:end)));
  end
  
  % SDP cone variables.
  offset = offset + length(obj.K.q);
  for j = 1:length(obj.K.s)
    E_ = inf_ (vsdp.verify_eigsym (vsdp.smat ([], d.s(j), 1)));
    % Weight the smallest eigenvalue lower bound E_ by the number of negative
    % eigenvalues.
    dl(j + offset) = min (E_) * sum (E_ < 0);
  end
  
  % Step 3: Cone feasibility check and lower bound computation:
  %
  % If all  d = c - A' * y  lie in each cone, then all lower bounds are
  % non-negative, e.g. 'dl >= 0'.  If there are cone violations 'dl(dl < 0)'
  % and there exist a finite upper bound 'xbnd(dl < 0)' on 'x' for each
  % violated constraint, the correction term 'defect' has to be added.
  idx = (dl.value < 0);
  
  if (~any (idx) || (~any (isinf (xbnd(idx)))))
    % If there are no violations, 'defect = 0' and 'y' is dual feasible.
    if (~any (idx))
      defect = 0;
    else
      defect = dl.value(idx)' * intval (xbnd(idx));
    end
    fL = inf_ (obj.b' * y + defect);
    solver_info.termination = 'Normal termination';
    break;  % SUCCESS
  end
  
  % Step 4: Perturb midpoint problem, such that
  %
  %    P(epsilon) = (mid([A]), mid([b]), mid([c]) + c_epsilon)
  %
  k      (idx) = k      (idx) + 1;
  epsilon(idx) = epsilon(idx) - (obj.options.ALPHA .^ k (idx)) .* dl(idx);
  if (~all (isfinite (epsilon)))
    error ('VSDP:rigorous_lower_bound:infinitePertubation', ...
      'rigorous_lower_bound: Perturbation exceeds finite range.');
  end
  c_epsilon(vidx) = [epsilon(1:(obj.K.f + obj.K.l + length (obj.K.q))); ...
    sdp_matrix * epsilon((end - length (obj.K.s) + 1):end)];
  
  % Display short pertubation statistic.
  iter = iter + 1;
  if (obj.options.VERBOSE_OUTPUT)
    fprintf ('\n\n');
    fprintf ('--------------------------------------------------\n');
    fprintf ('  VSDP.RIGOROUS_LOWER_BOUND  (iteration %d)\n', iter);
    fprintf ('--------------------------------------------------\n');
    fprintf ('  Violated cones   (dl < 0): %d\n',      sum (idx));
    fprintf ('  Max. violation    min(dl): %+.2e\n',   min (dl.value));
    fprintf ('  Pertubation  max(epsilon): %+.2e\n\n', max (epsilon));
    fprintf ('  Solve pertubed problem using ''%s''.\n', obj.options.SOLVER);
    fprintf ('--------------------------------------------------\n\n');
  end
  
  % Step 5: Solve perturbed problem%
  %
  % Set pertubation parameters.
  obj.pertubation.b = [];
  obj.pertubation.c = c_epsilon;
  
  obj.solve (obj.options.SOLVER, 'Rigorous lower bound');
  sol = obj.solutions('Rigorous lower bound');
  if ((~strcmp (sol.solver_info.termination, 'Normal termination')) ...
      || isempty (sol.y) || any (isnan (sol.y)) || any (isinf (sol.y)))
    error ('VSDP:rigorous_lower_bound:unsolveablePertubation', ...
      ['rigorous_lower_bound: Conic solver could not find a solution ', ...
      'for perturbed problem']);
  end
  % Store last successful solver info and new dual solution.
  solver_info = sol.solver_info;
  y = intval (sol.y);
end

% Append number of iterations to solver info.
solver_info.elapsed_time = toc(rlb);
solver_info.iter = iter;
obj.add_solution ('Rigorous lower bound', [], y, dl.value, [fL, nan], ...
  solver_info);

end
