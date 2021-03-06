function b = assemble_RHS_SFEM_with_ST(node,elem,xs,ys,omega,wpml,sigmaMax,epsilon,fquadorder,option)
%% Function to assemble the right hand side :
%         -\Delta u - (omega/c)^2 u = f               in D
%                                 u = 0               on \partial D
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% INPUT:
%
%   node: N x 2 matrix that contains the physical position of each node
%         node(:,1) provides the x coordinate
%         node(:,2) provides the y coordinate
%
%   elem: NT x 3 matrix that contains the indices of the nodes for each
%         triangle element
%
%   source: function handle defining the source
%
%   fquadorder: The order of numerical quadrature
%
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% OUTPUT:
%
%   b: N x 1 Galerking projection of the source
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% fprintf('Assembling the right-hand side \n');

%% FEM set up
N = size(node,1);        % number of grid points
NT = size(elem,1);       % number of triangle elements

xmax = max(node(:,1));
xmin = min(node(:,1));
ymax = max(node(:,2));
ymin = min(node(:,2));
h = (xmax - xmin)/(round(sqrt(N)) - 1);


%% PML set up
sigmaPML_x = @(x)sigmaMax*( (x-xmin-wpml).^2.*(x < xmin + wpml) + ...
    (x-(xmax-wpml)).^2.*(x > xmax - wpml))/wpml^2;
sigmaPML_y = @(y) sigmaMax*( (y-ymin-wpml).^2.*(y < ymin + wpml) ...
    + (y-(ymax-wpml)).^2.*(y > ymax - wpml))/wpml^2;
s_xy = @(x,y) ((1+1i*sigmaPML_x(x)/omega).*(1+1i*sigmaPML_y(y)/omega));    %% 1/(s1*s2)


%% Numerical Quadrature
[lambda,weight] = quadpts(fquadorder);
phi = lambda;           % linear bases
nQuad = size(lambda,1);


%% Compute geometric quantities and gradient of local basis
[~,area] = gradbasis(node,elem);

%% Assemble right-hand side

bt = zeros(NT,3);       % the right hand side

if nargin < 10
    option = 'homogeneous';
end

%% Babich pre-processing
Bx = []; By = []; phase = [];  amplitude = [];
if  iscell(option) && strcmp(option{1}, 'Babich')
    %% load Babich data
    high_omega = option{4};
    [Bh0,Bx0,By0,D1,D2,tao,tao2x,tao2y] = load_Babich_data(high_omega, option{2});
    
    a = 1/2;
    CompressRatio = round(Bh0/(h/4));
    Bh = 1/round( 1/(Bh0/CompressRatio) );
    Bx = -a: Bh : a;  By = -a: Bh : a;
    [BX0, BY0] = meshgrid(Bx0, By0);
    [BX, BY] = meshgrid(Bx, By);
    
    
    %% refined amplitude
    DD1 = interp2(BX0,BY0,D1,BX,BY,'spline');
    DD2 = interp2(BX0,BY0,D2,BX,BY,'spline');
    
    % gradient
    [D1x,D1y] = num_derivative(D1,Bh0,4);
    [D2x,D2y] = num_derivative(D2,Bh0,4);
    DD1x = interp2(BX0,BY0,D1x,BX,BY,'spline');
    DD1y = interp2(BX0,BY0,D1y,BX,BY,'spline');
    DD2x = interp2(BX0,BY0,D2x,BX,BY,'spline');
    DD2y = interp2(BX0,BY0,D2y,BX,BY,'spline');
    amplitude = [DD1(:), DD1x(:), DD1y(:), DD2(:), DD2x(:), DD2y(:)];
    
    
    %% refined phase
    if strcmp(option{3}, 'numerical_phase')
        ttao = interp2(BX0,BY0,tao,BX,BY,'spline');
        mid = round(size(tao,1)/2);
        taox = tao2x ./ (2*tao);   taox(mid, mid) = 0;
        taoy = tao2y ./ (2*tao);   taoy(mid, mid) = 0;
        ttaox = interp2(BX0,BY0,taox,BX,BY,'spline'); % refined phase
        ttaoy = interp2(BX0,BY0,taoy,BX,BY,'spline'); % refined phase
        phase = [ttao(:), ttaox(:), ttaoy(:)];
    end
    
end

%% assembling
for p = 1:nQuad
    % quadrature points in the x-y coordinate
    pxy = lambda(p,1)*node(elem(:,1),:) ...
        + lambda(p,2)*node(elem(:,2),:) ...
        + lambda(p,3)*node(elem(:,3),:);
    sxy = s_xy(pxy(:,1),pxy(:,2));
    
    [ub, ub_g1, ub_g2] = Babich_expansion(xs,ys,pxy,omega,option,Bx,By,phase,amplitude);
    fp = singularity_RHS(epsilon,xs,ys,pxy,ub,ub_g1,ub_g2).*sxy;
    
    for i = 1:3
        bt(:,i) = bt(:,i) + weight(p)*phi(p,i)*fp;
    end
end

bt = bt.*repmat(area,1,3);
b = accumarray(elem(:),bt(:),[N 1]);

clear fp pxy;
clear bt area;