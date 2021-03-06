function obj = from_2006_fmt (blk, A, C, b, X0, y0, Z0)
% FROM_2006_FMT  Import SDP problem data from VSDP 2006 format.
%
%   obj = vsdp.FROM_2006_FMT (blk, A, C, b, X0, y0, Z0)
%
%   The VSDP 2006 block-diagonal structure format is:
%
%      min  sum(j=1:n| <  C{j}, X{j}>)
%      s.t. sum(j=1:n| <A{i,j}, X{j}>) = b(i)  for i = 1:m
%           X{j} must be positive semidefinite for j = 1:n
%
%   The problem data of the block-diagonal structure:
%
%      'blk'  cell(n,2)
%      'A'    cell(m,n)
%      'C'    cell(n,1)
%      'b'  double(m,1)  Identical to current format.
%
%   The j-th block C{j} and the blocks A{i,j}, for i = 1:m, are real symmetric
%   matrices of common size s_j, and blk(j,:) = {'s'; s_j}.
%
%   The blocks C{j} and A{i,j} must be stored as individual matrices in dense
%   or sparse format.
%
%   The optional initial guess format is:
%
%      'X0'   cell(n,1)
%      'y0' double(m,1)  Identical to current format.
%      'Z0'   cell(n,1)
%
%   Example:
%
%       blk(1,:) = {'s'; 2};
%       A{1,1} = [0 1; 1 0];
%       A{2,1} = [1 1; 1 1];
%         C{1} = [1 0; 0 1];
%            b = [1; 2.0001];
%       obj = vsdp.FROM_2006_FMT (blk, A, C, b);
%
%   See also vsdp.

% Copyright 2004-2020 Christian Jansson (jansson@tuhh.de)

narginchk (4, 7);

% Translate cone structure.
if (~iscell (blk) || isempty (blk{1,2}))
  error ('VSDP:FROM_2006_FMT:badConeStructure', ...
    'from_2006_fmt: bad cone structure ''blk''.');
end
K.s = horzcat (blk{:,2});

% Need to transpose the input matrix 'A', number of constraints 'm' must be the
% second dimension.  Vectors 'b' and 'y0' have the same format in both VSDP
% versions.  The VSDP constructor cares for the condensed semidefinite
% variables.
obj = vsdp (vsdp.cell2mat (A'), b, vsdp.cell2mat (C(:)), K);


% Treat optional parameter of solution guess.
if (nargin < 5)
  return;
else
  X0 = vsdp.cell2mat (X0);
end
if (nargin < 6)
  y0 = [];
end
if (nargin < 7)
  Z0 = [];
else
  Z0 = vsdp.cell2mat (Z0);
end
obj.add_solution ('Initial', vsdp.svec (obj, X0), y0, vsdp.svec (obj, Z0));

end
