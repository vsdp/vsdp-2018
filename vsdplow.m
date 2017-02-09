function [fL,y,dl,info] = vsdplow(A,b,c,K,x0,y,z0,xu,opts)
% VSDPLOW  Verified lower bound for semidefinite-quadratic-linear programming.
%
%   [fL,y,dl,info] = VSDPLOW(A,b,c,K,[],y0) Computes a verified lower bound of
%      the primal optimal value and a rigorous enclosure of dual strict feasible
%      (near optimal) solutions of a conic problem in the standard primal-dual
%      form.  This form and the block-diagonal format (A,b,c,K) is explained in
%      'mysdps.m'.
%
%         'y0'     A dual feasible (eps-optimal) solution of the same dimension
%                  as input b.  This solution can be computed using 'mysdps'.
%
%      The output is:
%
%         'fL'     Verified lower bound of the primal optimal value.
%
%         'y'      Rigorous enclosure of dual strict feasible solutions.
%
%         'dl'     Verified lower bounds of eigenvalues or spectral values of
%                  z = c-A'*y.
%
%         'info'   Struct containing further information.
%           - iter  The number of iterations.
%
%   VSDPLOW(A,b,c,K,x0,y0,z0) optionally provide the other approximate
%      solutions of 'mysdps' (x0 and z0).
%
%   VSDPLOW(A,b,c,K,[],y0,[],xu) optionally provide known finite upper bounds
%      of the eigenvalues or spectral values of the primal optimal solution x.
%      We recommend to use infinite bounds xu(j) instead of unreasonable large
%      bounds xu(j).  This improves the quality of the lower bound in many
%      cases, but may increase the computational time.
%
%   VSDPLOW(A,b,c,K,[],y0,[],[],opts) optionally provide a structure for
%      additional parameter settings, explained in vsdpinit.
%
%   See also mysdps, vsdpinit.

% Copyright 2004-2012 Christian Jansson (jansson@tuhh.de)

% check input
if nargin<6 || isempty(A) || isempty(b) || isempty(c) || isempty(K)
  error('VSDP:VSDPLOW','more input arguments are required');
elseif nargin<8
  xu = [];  opts = [];
elseif nargin<9
  opts = [];
end

%  Preliminary steps / Prealocations

% initial output
fL = -Inf;
dl = NaN;
info.iter = 0;

% rounding mode
rnd = getround();
setround(0);

% import data
[A,Arad,b,brad,c,crad,K,x0,y,z0] = import_vsdp(A,b,c,K,x0,y,z0);

% check if approximations are applicable
if isempty(y) || any(isnan(y))
  warning('VSDP:VSDPLOW','not applicable approximations given (NaN)');
  y = NaN;
  return;
elseif nargin<7 || any(isnan(x0)) || any(isnan(z0))
  x0 = [];  z0 = [];
end

% get problem data dimensions
dim3 = length(c);  % dimension
nc = K.l + length(K.q) + length(K.s);  % number of cone constraints

% variable declarations and allocations
I = [];  % basic indices
xu = xu(:);
if isempty(xu)
  xu = inf(K.f+nc,1);
elseif size(xu,1)~=K.f+nc
  error('VSDP:VSDPLOW','upper bound vector has wrong dimension');
end
xuf = xu(1:K.f);  xu(1:K.f) = [];
yrad = sparse(size(y,1),1);  % interval radius y

dl = -inf(nc,1);  % dual lower bounds / trace bounds
epsj = ones(nc,1);  % factor for perturbation amount
ceps = sparse(dim3,1);  % perturbation for c
pertS = cell(length(K.s),1);  % for diagonal perturbations of sdp blocks

% extract free part
Af = A(1:K.f,:);  Afrad = Arad(1:K.f,:);
cf = c(1:K.f);  cfrad = crad(1:K.f);

% create index vector for perturbation entries
pertI = ones(sum(K.s),1);
pertI(cumsum(K.s(1:end-1))+1) = 1 - K.s(1:end-1);
pertI = [ones(K.l+(~isempty(K.q)),1); K.q(1:end-1); cumsum(pertI)];
pertI(1) = K.f + 1;
pertI = cumsum(pertI);


% Algorithm with finite/infinite primal bounds xu
VSDP_OPTIONS = vsdpinit(opts);
% **** main loop ****
while (info.iter <= VSDP_OPTIONS.ITER_MAX)
  info.iter = info.iter + 1;
  setround(1);  % default for rigorous computation in steps 1-3
  
  % 1.step: defect computation, free variables handling
  if K.f>0 && max(xuf)==inf
    % solve dual linear constraints rigorously
    [y,I] = vuls([],[],struct('mid',Af,'rad',Afrad),...
      struct('mid',cf,'rad',cfrad),[],[],y,I,opts);
    if ~isstruct(y)
      disp('VSDPLOW: could not find solution of dual equations');
      break;
    else
      yrad = y.rad;
      y = y.mid;
    end
  end
  
  % compute rigorous enclosure for z = c - A*y  (with free variables)
  [z,zrad] = spdotK(c,1,A,-y,2);  % for point matrices
  zrad = zrad + crad;  % regard radii of other parameters
  if any(yrad)
    zrad = zrad + abs(A)*yrad;
  end
  if ~isempty(find(Arad,1))
    zrad = zrad + Arad*(abs(y)+yrad);
  end
  
  defect = 0;  % defect by free variables
  if K.f>0 && max(xuf)<inf  % upper bounds a-priory known
    defect = xuf' * (abs(z(1:K.f))+zrad(1:K.f));
  end
  
  % 2.step: verified lower bounds on cone eigenvalues
  if K.l>0  % bound for linear variables
    ind = K.f+1:K.f+K.l;
    zjn = zrad(ind) - z(ind);  % -inf(zl)
    % interprete all lp vars as one cone:
    %  if any element is negative all constraints close to zero will be
    %  perturbated
    zj1 = max(zjn);
    if zj1>0  % there is a negative bound
      ind = zjn > -zj1;
      zj1 = max((-1e-13)*min(zjn),zj1);
      zjn(ind) = min(zjn(ind)+zj1,1.05*zj1);
    end
    dl(1:K.l) = - zjn;
  end
  % eigenvalue bound for second-order cone variables
  ind = K.f + K.l;
  for j = 1:length(K.q)
    ind = ind(end)+2:ind(end)+K.q(j);
    zj1 = zrad(ind(1)-1) - z(ind(1)-1);  % -inf(zq(1))
    zjn = abs(z(ind)) + zrad(ind);  % sup(abs(zq(2:end)))
    zjn = sqrtsup(zjn'*zjn);  % sup(||zq(2:end)||)
    dl(K.l+j) = -(zj1+zjn);  % inf(zq(1)-||zq(2:end)||)
  end
  % eigenvalue bound for semidefinite cone
  blke = K.f + K.l + sum(K.q) + sum(K.s.*(K.s+1))/2;
  for j = length(K.s):-1:1
    ofs = K.l + length(K.q) + j;
    blks = blke - K.s(j)*(K.s(j)+1)/2 + 1;
    [lmin,dl(ofs),pertS{j}] = bnd4sd(struct('mid',z(blks:blke),...
      'rad',zrad(blks:blke)),1,VSDP_OPTIONS.FULL_EIGS_ENCLOSURE);
    if lmin>0
      dl(ofs) = lmin;
    end
    pertS{j} = epsj(ofs) * pertS{j}(:);
    blke = blks - 1;
  end
  
  % 3.step: cone feasibility check, computing lower bound
  dli = find(dl<0);
  if ~any(isinf(xu(dli)))
    % inf(min(dl,0)*xu + b'*y - defect)
    fL = -(sum(dl(dli)'*(-xu(dli))) + prodsup(-b',y,brad',yrad) + defect);
    y = midrad(full(y),full(yrad));
    setround(rnd);  % reset rounding mode
    return;
  end
  
  % 4.step: create some perturbed problem
  setround(0);  % no code for rigorous computations
  ind = 1:K.l+length(K.q);
  if isempty(ind)
    ceps = ceps + sparse(pertI,1,cat(1,pertS{:}),dim3,1);
  else
    ceps = ceps + sparse(pertI,1,cat(1,epsj(ind).*min(dl(ind),0),...
      pertS{:}),dim3,1);
  end
  if any(isinf(ceps)) || any(isnan(ceps))
    disp('VSDLOW: perturbation extended range');
    break;
  end
  epsj(dli) = epsj(dli) * (1 + VSDP_OPTIONS.ALPHA); % update perturbation factor
  
  % 5.step: solve the perturbed problem
  clear dli ind z zrad;  % free some memory before calling solver
  [~,x0,y,z0,INFO] = mysdps(A,b,c+ceps,K,x0,y,z0,opts);
  % if could not found solution or dual infeasible, break
  if isempty(y) || any(isnan(y)) || any(isinf(y)) || any(INFO(1)==[(1) 2 3])
    disp('VSDLOW: conic solver could not find solution for perturbed problem');
    break;
  end
end

% reset rounding mode
setround(rnd);

% write output
if (info.iter == VSDP_OPTIONS.ITER_MAX)
  disp('VSDPLOW: maximum number of iterations reached');
end
y = NaN; fL = -Inf; dl = NaN;

end
