%% h convergence test for Lippmann-Schwinger equation
%    O(h^2)


clear;
addpath(genpath('../../ifem/'));
addpath('../Methods/');
addpath('../NMLA/');
addpath('../Functions/')
addpath('../Plots_Prints/');
% addpath('/home/jun/Documents/MATLAB/Solutions_Lippmann_Schwinger');


%% Load source/wavespeed data
xs = -0.2; ys = -0.2;               % point source location
sigma = 0.15;
xHet = 0.2;   yHet = 0.2;

nu = @(x,y) 0.2*exp( -1/(2*sigma^2)*((x-xHet).^2 + (y-yHet).^2) )...
    .*Lippmann_Schwinger_window(sqrt((x-xHet).^2 + (y-yHet).^2), 0.22,0.16  );

speed = @(p) 1./sqrt(1 + nu( p(:,1), p(:,2) ));    % wave speed
speed_min = 1;


%% Set up
plt = 0;                   % show solution or not
fquadorder = 3;            % numerical quadrature order
Nray = 1;                  % one ray direction
sec_opt = 0;               % NMLA second order correction or not
epsilon = 1/(2*pi);        % cut-off parameter

high_omega = 100*pi;
low_omega = 2*sqrt(high_omega);


low_wpml = 0.18;
high_wpml = 0.065;

% wavelength
high_wl = 2*pi*speed_min./high_omega;
low_wl = 2*pi*speed_min./low_omega;

% mesh size
fh = 1/800;                 % fine mesh size
ch = 1/80;                  % coarse mesh size

sd = 1/2; md = 0.6; ld = 0.9;
Rest = 0.4654; ti = 1;

h = fh; h_c = ch;
tstart = tic;

%% Step 1: Solve the Hemholtz equation with the same source but with a relative low frequency sqrt(\omega) by Standard FEM, mesh size \omega*h = constant
fprintf(['-'*ones(1,80) '\n']);
fprintf('Step1: S-FEM, low frequency \n');
tic;
omega = low_omega(ti);              % low frequency
a = ld(ti);                         % large domain
wpml = low_wpml(ti);                % width of PML
sigmaMax = 25/wpml;                 % Maximun absorbtion
[lnode,lelem] = squaremesh([-a,a,-a,a],h);

% smooth part
A = assemble_Helmholtz_matrix_SFEM(lnode,lelem,omega,wpml,sigmaMax,speed,fquadorder);
b = assemble_RHS_SFEM_with_ST(lnode,lelem,xs,ys,omega,wpml,sigmaMax,epsilon,fquadorder);
[~,~,isBdNode] = findboundary(lelem);
freeNode = find(~isBdNode);
lN = size(lnode,1);        u_std = zeros(lN,1);
u_std(freeNode) = A(freeNode,freeNode)\b(freeNode);

% singular part
x = lnode(:,1); y = lnode(:,2);
rr = sqrt((x-xs).^2 + (y-ys).^2);
ub = 1i/4*besselh(0,1,omega*rr);
cf = cutoff(epsilon,2*epsilon,lnode,xs,ys);

% low frequency solution: smooth + singularity
u_low = u_std + ub.*cf;
toc;


%% Step 2: Use NMLA to find ray directions d_c with low frequency sqrt(\omega)
fprintf(['-'*ones(1,80) '\n']);
fprintf('Step2: NMLA, low frequency \n');
tic;

% compute numerical derivatives
[ux,uy] = num_derivative(u_low,h,2);

a = md(ti);
[mnode,melem] = squaremesh([-a,a,-a,a],h);
[cnode,celem] = squaremesh([-a,a,-a,a],h_c);
cN = size(cnode,1);
cnumray_angle = zeros(cN,Nray);

% NMLA
for i = 1:cN
    x0 = cnode(i,1);  y0 = cnode(i,2);
    r0 = sqrt((x0-xs)^2 + (y0-ys)^2);
    c0 = speed(cnode(i,:));
    if r0 > (2*epsilon - 3*h_c)
        [cnumray_angle(i)] = NMLA(x0,y0,c0,omega,Rest,lnode,lelem,u_low,ux,uy,[],1/5,Nray,'num',sec_opt,plt);
    else
        cnumray_angle(i) =  ex_ray([x0,y0],xs,ys,0);
    end
end
cnumray = exp(1i*cnumray_angle);
ray = interpolation(cnode,celem,mnode,cnumray);
ray = ray./abs(ray);

% analytical ray directions in the support of the cut-off dunction
exray = ex_ray(mnode,xs,ys,1);
x = mnode(:,1); y = mnode(:,2);
rr = sqrt((x-xs).^2 + (y-ys).^2);
ray(rr <= 2*epsilon) = exray(rr <= 2*epsilon);
%     figure(1); ray_field(ray,mnode,10,1/10);
toc;


%% Step 3: Solve the original Helmholtz equation by Ray-based FEM with ray directions d_c
fprintf(['-'*ones(1,80) '\n']);
fprintf('Step3: Ray-FEM, high frequency \n');
tic;
omega = high_omega(ti);
wpml = high_wpml(ti);                % width of PML
sigmaMax = 25/wpml;                 % Maximun absorbtion

% smooth part
option = 'homogeneous';
A = assemble_Helmholtz_matrix_RayFEM(mnode,melem,omega,wpml,sigmaMax,speed,ray,fquadorder);
b = assemble_RHS_RayFEM_with_ST(mnode,melem,xs,ys,omega,epsilon,wpml,sigmaMax,ray,speed,fquadorder,option);
uh = RayFEM_direct_solver(mnode,melem,A,b,omega,ray,speed);

% singularity part
ub = 1i/4*besselh(0,1,omega*rr);
cf = cutoff(epsilon,2*epsilon,mnode,xs,ys);

% smooth + singularity
uh1 = uh + ub.*cf;
toc;



%% Step 4: NMLA to find original ray directions d_o with wavenumber k
fprintf(['-'*ones(1,80) '\n']);
fprintf('Step4: NMLA, high frequency \n');
tic;

% compute numerical derivatives
[ux,uy] = num_derivative(uh1,h,2);

a = sd;
[node,elem] = squaremesh([-a,a,-a,a],h);
[cnode,celem] = squaremesh([-a,a,-a,a],h_c);
cN = size(cnode,1);
cnumray_angle = zeros(cN,Nray);

% NMLA
for i = 1:cN
    x0 = cnode(i,1);  y0 = cnode(i,2);
    r0 = sqrt((x0-xs)^2 + (y0-ys)^2);
    c0 = speed(cnode(i,:));
    if r0 > (2*epsilon - 3*h_c)
        [cnumray_angle(i)] = NMLA(x0,y0,c0,omega,Rest,mnode,melem,uh1,ux,uy,[],1/5,Nray,'num',sec_opt,plt);
    else
        cnumray_angle(i) =  ex_ray([x0,y0],xs,ys,0);
    end
end
cnumray = exp(1i*cnumray_angle);
toc;


%% h refinement
h_ray = 1./(10*round(32*high_omega/(2*pi*speed_min)/10));
[node_ray, elem_ray] = squaremesh([-a,a,-a,a],h_ray);
rray = interpolation(cnode,celem,node_ray,cnumray);


NPW = [4, 8, 16, 32];
fh = 1./(10*round(NPW*high_omega/(2*pi*speed_min)/10));

test_num = 4;

% error
max_err = 0*zeros(1,test_num);      % L_inf error of the numerical solution
rel_max_err = 0*zeros(1,test_num);  % relative L_inf error of the numerical solution
l2_err = 0*zeros(1,test_num);       % L_2 error of the numerical solution
rel_l2_err = 0*zeros(1,test_num);   % relative L_2 error of the numerical solution
ref_l2 = 0*zeros(1,test_num);       % reference l2 norm


for ti = 1: test_num
    h = fh(ti);
    [node,elem] = squaremesh([-a,a,-a,a],h);
    ray = interpolation(node_ray,elem_ray,node,rray);
    ray = ray./abs(ray);
    
    % analytical ray directions in the support of the cut-off dunction
    exray = ex_ray(node,xs,ys,1);
    x = node(:,1); y = node(:,2);
    rr = sqrt((x-xs).^2 + (y-ys).^2);
    ray(rr <= 2*epsilon) = exray(rr <= 2*epsilon);
    
   
    %% Step 5: Solve the original Helmholtz equation by Ray-based FEM with ray directions d_o
    fprintf([ '-'*ones(1,80) '\n']);
    fprintf('Step5: Ray-FEM, high frequency \n');
    tic;
    
    % Assembling
    omega = high_omega;
    wpml = high_wpml;                % width of PML
    sigmaMax = 25/wpml;                 % Maximun absorbtion
    
    option = 'homogeneous';
    A = assemble_Helmholtz_matrix_RayFEM(node,elem,omega,wpml,sigmaMax,speed,ray,fquadorder);
    b = assemble_RHS_RayFEM_with_ST(node,elem,xs,ys,omega,epsilon,wpml,sigmaMax,ray,speed,fquadorder,option);
    [~,v] = RayFEM_direct_solver(node,elem,A,b,omega,ray,speed);
    toc;
    
    
    %% Compute errors
    fprintf([ '-'*ones(1,80) '\n']);
    fprintf('Compute errors\n');
    tic;
    
    rh = 1/5000;
    [rnode,~] = squaremesh([-a,a,-a,a],rh); rn = round(sqrt(size(rnode,1)));
    uh = RayFEM_solution(node,elem,omega,speed,v,ray,rnode);
    
    % Reference solution
    load('/Solutions_Lippmann_Schwinger/point_source_k_120_jun_new_version.mat')
    x = rnode(:,1); y = rnode(:,2);
    rr = sqrt((x-xs).^2 + (y-ys).^2);
    
%     u = 1i/4*besselh(0,1,omega*rr);
    cf = cutoff(epsilon,2*epsilon,rnode,xs,ys);
    ur = (1-cf).*u;
    ur(rr<=epsilon) = 0;
    
    % Errors
    du = uh - ur;
    idx = find( ~( (x<=max(x)-wpml).*(x>= min(x)+wpml)...
        .*(y<= max(y)-wpml).*(y>= min(y)+wpml) ) ); % index on PML
    du(idx) = 0;  ur(idx) = 0;
    
    max_err(ti) = norm(du,inf);
    rel_max_err(ti) = norm(du,inf)/norm(ur,inf);
    l2_err(ti) = norm(du)*rh;
    ref_l2(ti) = norm(ur)*rh;
    rel_l2_err(ti) = l2_err(ti)/ref_l2(ti)
    
    toc;

    
end

totaltime = toc(tstart);
fprintf('\n\nTotal running time: % d minutes \n', totaltime/60);

figure(22);
show_convergence_rate(fh(1:test_num),rel_l2_err(1:test_num),'h','Rel L2 err');



% % Plots
% sh = 1/500;
% [snode,selem] = squaremesh([-a,a,-a,a],sh);
% sr = sqrt((snode(:,1)-xs).^2 + (snode(:,2)-ys).^2);
% sn = round(sqrt(size(snode,1))); idx = 1:sn; idx = 10*(idx-1) + 1;
% su1 = reshape(du,rn,rn); su1 = su1(idx,idx);
% su2 = reshape(ur,rn,rn); su2 = su2(idx,idx);
% figure(8);
% subplot(2,2,1);
% showsolution(snode,selem,real(su1(:))); colorbar;
% title('Ray-FEM solution error')
% subplot(2,2,2);
% showsolution(snode,selem,real(su1(:)),2); colorbar;
% title('Ray-FEM solution error')
% subplot(2,2,3);
% showsolution(snode,selem,real(su2(:))); colorbar;
% title('Reference solution')
% subplot(2,2,4);
% showsolution(snode,selem,real(su2(:)),2); colorbar;
% title('Reference solution')



%% print results
fprintf( ['\n' '-'*ones(1,80) '\n']);
fprintf( 'omega:                   ');
fprintf( '&  %.2e  ',high_omega );
fprintf( '\nomega/2pi:               ');
fprintf( '&  %.2e  ',high_omega/(2*pi) );
fprintf( '\n\nGrid size h:             ');
fprintf( '&  %.2e  ',fh);
fprintf( '\n1/h:                     ');
fprintf( '&  %.2e  ',1./fh);

fprintf( ['\n' '-'*ones(1,80) '\n']);

fprintf( '\n\nMax error:               ');
fprintf( '&  %1.2d  ',max_err);
fprintf( '\n\nRelative max error:      ');
fprintf( '&  %1.2d  ',rel_max_err);

fprintf( ['\n' '-'*ones(1,80) '\n']);

fprintf( '\n\nReference L2 norm:       ');
fprintf( '&  %1.2d  ',ref_l2);
fprintf( '\n\nL2 error:                ');
fprintf( '&  %1.2d  ',l2_err);
fprintf( '\n\nRelative L2 error:       ');
fprintf( '&  %1.2d  ',rel_l2_err);

fprintf( ['\n' '-'*ones(1,80) '\n']);




% --------------------------------------------------------------------------------
% omega:                   &  3.77e+02  
% omega/2pi:               &  6.00e+01  
% 
% Grid size h:             &  4.17e-03  &  2.08e-03  &  1.04e-03  &  5.21e-04  
% 1/h:                     &  2.40e+02  &  4.80e+02  &  9.60e+02  &  1.92e+03  
% --------------------------------------------------------------------------------
% 
% 
% Max error:               &  3.29e-04  &  1.16e-04  &  3.80e-05  &  1.69e-05  
% 
% Relative max error:      &  1.76e-02  &  6.18e-03  &  2.03e-03  &  9.05e-04  
% --------------------------------------------------------------------------------
% 
% 
% Reference L2 norm:       &  1.13e-02  &  1.13e-02  &  1.13e-02  &  1.13e-02  
% 
% L2 error:                &  6.56e-05  &  1.82e-05  &  5.68e-06  &  1.81e-06  
% 
% Relative L2 error:       &  5.81e-03  &  1.61e-03  &  5.03e-04  &  1.60e-04  
% --------------------------------------------------------------------------------


   
    
