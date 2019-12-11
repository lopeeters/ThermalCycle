function [ETA, DATEN, DATEX, DAT, MASSFLOW, COMBUSTION, Cp_g, FIG] = ...
    GT(P_e,options,display)
% GT Gas turbine modelisation
% GT(P_e,options,display) compute the thermodynamics states for a Gas
% turbine based on several inputs (given in OPTION) and based on a given 
% electricity production P_e. It returns the main results. It can as well
% plots graphs if input argument DISPLAY = true (<=> DISPLAY=1)
%
% INPUTS (some inputs can be dependent on others => only one of these 2 can
%         be activated) Refer to Fig 3.1 from reference book (in english)
% P_E = electrical power output target [kW]
% OPTIONS is a structure containing :
%   -options.k_mec [-] : Shaft losses 
%   -options.T_0   [°C] : Reference temperature
%   -options.T_ext [°C] : External temperature
%   -options.r     [-] : Compression ratio
%   -options.k_cc  [-] : Coefficient of pressure losses due to combustion
%                        chamber
%   -options.T_3   [°C] : Temperature after combustion (before turbine)
%   -option.eta_PiC[-] : Intern polytropic efficiency (Rendement
%                        polytropique interne) for compression
%   -option.eta_PiT[-] : Intern polytropic efficiency (Rendement
%                        polytropique interne) for expansion
%DISPLAY = 1 or 0. If 1, then the code should plot graphics. If 0, then the
%          do not plot.
%
%OUPUTS : 
% ETA is a vector with :
%   -eta(1) : eta_cyclen, cycle energy efficiency
%   -eta(2) : eta_toten, overall energy efficiency
%   -eta(3) : eta_cyclex, cycle exegy efficiency
%   -eta(4) : eta_totex, overall exergie efficiency
%   -eta(5) : eta_rotex, compressor-turbine exergy efficiency
%   -eta(6) : eta_combex, Combustion exergy efficiency
%   FYI : eta(i) \in [0;1] [-]
% DATEN is a vector with : 
%   -daten(1) : perte_mec [kW]
%   -daten(2) : perte_ech [kW]
% DATEX is a vector with :
%   -datex(1) : perte_mec [kW]
%   -datex(2) : perte_rotex [kW]
%   -datex(3) : perte_combex [kW]
%   -datex(4) : perte_echex  [kW]
% DAT is a matrix containing :
% dat = {T_1       , T_2       , T_3       , T_4; [°C]
%        p_1       , p_2       , p_3       , p_4; [bar]
%        h_1       , h_2       , h_3       , h_4; [kJ/kg]
%        s_1       , s_2       , s_3       , s_4; [kJ/kg/K]
%        e_1       , e_2       , e_3       , e_4;};[kJ/kg]
% MASSFLOW is a vector containing : 
%   -massflow(1) = m_a, air massflow [kg/s]
%   -massflow(2) = m_c, combustible massflow [kg/s] 
%   -massflow(3) = m_f, exhaust gas massflow [kg/s]
% 
% COMBUSTION is a structure with :
%   -combustion.LHV    : the Lower Heat Value of the fuel [kJ/kg]
%   -combustion.e_c    : the combustible exergie         [kJ/kg]
%   -combustion.lambda : the air excess                   [-]
%   -combustion.Cp_g   : heat capacity of exhaust gas at 400 K [kJ/kg/K]
%   -combustion.fum  : is a vector of the exhaust gas composition :
%       -fum(1) = m_O2f  : massflow of O2 in exhaust gas [kg/s]
%       -fum(2) = m_N2f  : massflow of N2 in exhaust gas [kg/s]
%       -fum(3) = m_CO2f : massflow of CO2 in exhaust gas [kg/s]
%       -fum(4) = m_H2Of : massflow of H2O in exhaust gas [kg/s] 
%
% FIG is a vector of all the figure you plot. Before each figure, define a
% figure environment such as:  
%  "FIG(1) = figure;
%  plot(x,y1);
%  [...]
%   FIG(2) = figure;
%  plot(x,y2);
%  [...]"
%  Your vector FIG will contain all the figure plot during the run of this
%  code (whatever the size of FIG).
%


%% Parameters Verification

if nargin < 3
   display = 1;
   if nargin < 2
       options = struct();
       if nargin < 1
           P_e = 230e3; % 100[MW]
       end
   end
end

if isfield(options,'T_0') == 0
    T_0 = 273.15;
else
    T_0 = options.T_0 +273.15;
end

if isfield(options,'T_ext') == 0
    T_ext = 15 +273.15;
else
    T_ext = options.T_ext +273.15;
end

if isfield(options,'r') == 0
    r = 18;
else
    r = options.r;
end

if isfield(options,'T_3') == 0
    T_3 = 1400 +273.15;
else
    T_3 = options.T_3 +273.15;
end

if isfield(options,'eta_PiC') == 0
    eta_PiC = .9;
else
    eta_PiC = options.eta_PiC;
end

if isfield(options,'eta_PiT') == 0
    eta_PiT = .9;
else
    eta_PiT = options.eta_PiT;
end

if isfield(options,'k_cc') == 0
    k_cc = .95;
else
    k_cc = options.k_cc;
end

if isfield(options,'k_mec') == 0
    k_mec = .015;
else
    k_mec = options.k_mec;
end

%% Other parameters

M_O2  = 31.99800e-3; % [kg/mol]
M_N2  = 28.01400e-3;
M_CO2 = 44.00800e-3;
M_H2O = 18.01494e-3;
M_air = .21*M_O2 + .79*M_N2;

p_ext = 100e3; % [Pa]

R = 8.314472; % The ideal gas's constant [J/mol/K]
R_O2  = R / M_O2; % [J/(kg*K)]
R_N2  = R / M_N2; % [J/(kg*K)]
R_CO2 = R / M_CO2; % [J/(kg*K)]
R_H2O = R / M_H2O; % [J/(kg*K)]
R_air = 287.058; % [J/(kg*K)]

    function [X] = Cp_CO2(T)
        T(T<300) = 300; T(T>5000) = 5000;
        X = janaf('CO2',T) *1e3;
    end

    function [X] = Cp_H2O(T)
        T(T<300) = 300; T(T>5000) = 5000;
        X = janaf('H2O',T) *1e3;
    end

    function [X] = Cp_O2(T)
        T(T<300) = 300; T(T>5000) = 5000;
        X = janaf('O2',T) *1e3;
    end

    function [X] = Cp_N2(T)
        T(T<300) = 300; T(T>5000) = 5000;
        X = janaf('N2',T) *1e3;
    end

    function [X] = Cp_air(T)
        T(T<300) = 300; T(T>5000) = 5000;
        X = .21*janaf('O2',T) + .79*janaf('N2',T) *1e3;
    end

%% Calculations of all states such that
% 1 -> 2 : polytropic compression
% 2 -> 3 : isobaric warming
% 3 -> 4 : polytropic relaxation
% 4 -> 1 : isobaric coolingw
%
% In the combustion chamber where the compressed air is coming at (T_2,
% p_2,h_2,s_2,e_2) at a certain flow m_a, we inject CH_4 (T_c,m_c)
% so that the following transformation can happen to create energy :
% CH_yO_x + w*(O_2 + 3.76*N_2) -> CO_2 + a*O_2 + b*H_2O + 3.76*w*N_2

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% FIRST  STATE %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

p_1 = p_ext;
T_1 = T_ext;
h_1 = 1.006e3 * (T_1 - T_0);
s_1 = 0.054e3;
e_1 = 0;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% SECOND STATE %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

p_2 = p_1 *r;

function [T,Cp_moy] = Compression(ratio)
    T = 1674; T_it = 0;
    while abs(T-T_it) > 1e-5
        T_it = T;
        Cp_moy = integral(@Cp_air,T_1,T)/(T-T_1);
        T = T_1 * ratio ^(287.058/Cp_moy/eta_PiC); % cf. eq 3.19-3.22
    end
end

[T_2,Cp_moy] = Compression(r);
h_2 = h_1 + Cp_moy*(T_2 - T_1);
s_2 = s_1 + Cp_moy*log(T_2/T_1) - R_air*log(r);
e_2 = (h_2-h_1) - T_0*(s_2-s_1);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% THIRD  STATE %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% COMBUSTION %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

p_3 = p_2 *k_cc;
x = 0; y = 4; LHV = 51.5e6;
Cp_c = 35.639; % Mass heat of methane at standart temperature [J/(mol*K)]
M_c  = (12.01+1.01*y+16*x)*1e-3; % Molar mass of methane [kg/mol]

%syms lam
a = @(lam) (lam-1)*(1+y/4-x/2); b = y/2;
w = @(lam) lam*(1+y/4-x/2); % Stoechiometric coefficients

%LHV = (-74.9e3 + 10*Cp_c) + (393.52e3 + integral(@Cp_O2,298,T_3)*M_CO2)...
%    + b*(+285.10e3 + integral(@Cp_H2O,298,T_3)*M_H2O);
LHV = (-74.9e3 + 393.52e3 + b*241.80e3)/M_c; % [J/kg]

t = 273:int16(T_3);
fun = @(lam) (T_3 -273.15) * (mean(Cp_CO2(t))*M_CO2 + b*mean(Cp_H2O(t))*M_H2O ...
    + a(lam)*mean(Cp_O2(t))*M_O2 + 3.76*w(lam)*mean(Cp_N2(t))*M_N2) ...
    - (T_2 -273.15) * w(lam)*integral(@Cp_air,T_0,T_2)/(T_2-T_0)*M_air/.21 ...
    - 25*Cp_c - LHV*M_c; % Bilan d'enthalpie sur la combustion
%lambda = double(solve(fun == 0, lam)); % Exces d'air [mol_air/mol_c]
lambda = fsolve(fun,1);

a = double(a(lambda)); w = double(w(lambda)); % [mol]

comp_f_tot = M_CO2 + b*M_H2O + a*M_O2 + 3.76*w*M_N2; % [kg]
comp_f_CO2 = M_CO2 / comp_f_tot; % [-]
comp_f_H2O = b*M_H2O / comp_f_tot; % [-]
comp_f_O2  = a*M_O2 / comp_f_tot; % [-]
comp_f_N2  = 3.76*w*M_N2 / comp_f_tot; % [-]
R_f = R / comp_f_tot * (1+b+a+3.76*w); % [J/(kg*K)]

    function [X] = Cp_f(T)
        T(T<300) = 300;
        T(T>5000) = 5000;

        X = comp_f_CO2*janaf('CO2',T) + comp_f_H2O*janaf('H2O',T) + ...
            comp_f_O2*janaf('O2',T) + comp_f_N2*janaf('N2',T); % [J/(kg*K)]
        X = X *1e3;
    end

m_a1 = (1+y/4-x/2) * (M_air/.21)/M_c; % [mol]
m_ac = lambda * m_a1 ; % [-]
m_ag = (1 + 1/m_ac)^(-1); % [-]
Q_comb = LHV / m_ac;

%h_3 = h_2 + integral(@Cp_air,T_2,T_3);
h_3 = (Q_comb + h_2) * m_ag;
%s_3 = mean(Cp_air(273:int16(T_3))) * log(T_3/T_0) - R_air * log(p_3/p_ext);
%s_3 = s_2 + Q_comb * log(T_3/T_2) / (T_3 - T_2);
integral(@Cp_f,273.15,393.15)
s_3 = s_2 + integral(@Cp_f,T_2,T_3)*log(T_3/T_2)/(T_3-T_2) - R_f*log(k_cc);
e_3 = (h_3-h_1) - T_0*(s_3-s_1);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% FOURTH STATE %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

p_4 = p_ext;

function [T,Cp_moy] = Detente(ratio)
    T = 1000; T_it = 0;
    while abs(T - T_it) > 1e-5
        T_it = T;
        Cp_moy = integral(@Cp_f,T_3,T)/(T-T_3);
        T = T_3 * ratio^(R_f/Cp_moy*eta_PiT);
    end
end

[T_4,Cp_moy] = Detente(1/k_cc/r)
h_4 = h_3 + Cp_moy * (T_4 - T_3);
%s_4 = s_3 + Cp_moy*log(T_4/T_3) - R_f*log(p_4/p_3);
s_4 = s_1 + integral(@Cp_f,T_1,T_4)*log(T_4/T_1)/(T_4-T_1);
e_4 = (h_4-h_1) - T_0*(s_4-s_1);


%% WORK, MASS FLOW AND EFFICIENCY

eta_mec = 1 - k_mec*((h_3-h_4)/m_ag + (h_2-h_1))/((h_3-h_4)/m_ag - (h_2-h_1));
W_m = (h_3 - h_4)/m_ag - (h_2 - h_1); % [J/kg_air]
P_m = P_e*1e3 / eta_mec; % [W]

A = [(h_1-h_2), 0, (h_3-h_4);
     -1, lambda*m_a1, 0;
     (1 + lambda*m_a1), 0, -lambda*m_a1];
b = [P_m;0;0];
m = A\b;

m_a = m(1);%P_m / W_m;  % [kg/s]
m_c = m(2);%m_a / m_ac; % [kg/s]
m_g = m(3);%m_a / m_ag; % [kg/s]

m_CO2f = comp_f_CO2 * m_g;
m_H2Of = comp_f_H2O * m_g;
m_O2f  = comp_f_O2  * m_g;
m_N2f  = comp_f_N2  * m_g;

PCS = 55695e3;
e_c = PCS + 15 * (Cp_c/M_c + comp_f_O2*Cp_O2(288) - comp_f_CO2*Cp_CO2(288) - comp_f_H2O*Cp_H2O(288)) ...
    - 288.15 * (183.1/M_c + Cp_c/M_c*log(288.15/273.15)) ...
    - 288.15 * (202.8/M_O2 + Cp_O2(288)*log(288.15/273.15) - R_O2*log(.2064)) * comp_f_O2 ...
    + 288.15 * (210.4/M_CO2 + Cp_CO2(288)*log(288.15/273.15) - R_CO2*log(.0003)) * comp_f_CO2 ...
    + 288.15 * (69.5/M_H2O + Cp_H2O(288)*log(288.15/273.15)) * comp_f_H2O;

P_prim = m_c * LHV;

eta_cyclen = W_m / Q_comb;
eta_toten  = eta_mec * eta_cyclen;
eta_cyclex = P_m / (m_g*e_3 - m_a*e_2);
eta_totex  = P_m*eta_mec / (m_c*e_c);
eta_rotex  = P_m / (m_g*(e_3 - e_4) - m_a*(e_2 - e_1));
eta_combex = (m_g*e_3 - m_a*e_2) / (m_c*e_c);

P_1 = (h_1 * m_a) *1e-6;
P_2 = (h_2 * m_a) *1e-6;
P_3 = (h_3 * 450) *1e-6;
P_4 = (h_4 * 450) *1e-6;

perte_mecen  = (P_m - P_e*1e3) *1e-6;
perte_echen  = m_g * (h_4-h_1) *1e-6;

perte_mecex  = perte_mecen;
perte_rotex  = (m_g*(e_3 - e_4) - m_a*(e_2 - e_1) - P_m) *1e-6;
perte_combex = m_c*e_c * (1-eta_combex) *1e-6;
perte_echex  = m_g * (e_4-e_1) *1e-6;


%% RESULTS

ETA = [eta_cyclen,eta_toten,eta_cyclex,eta_totex,eta_rotex,eta_combex];
% [%]

DATEN = [perte_mecen, perte_echen]; % [kW]

DATEX = [perte_mecex, perte_rotex, perte_combex, perte_echex]; % [kW]

DAT = [T_1-273.15, T_2-273.15, T_3-273.15, T_4-273.15;... [°C]
       p_1 *1e-5,  p_2 *1e-5,  p_3 *1e-5,  p_4 *1e-5;...  [bar]
       h_1 *1e-3,  h_2 *1e-3,  h_3 *1e-3,  h_4 *1e-3;...  [kJ/kg]
       s_1 *1e-3,  s_2 *1e-3,  s_3 *1e-3,  s_4 *1e-3;...  [kJ/(kg*K)]
       e_1 *1e-3,  e_2 *1e-3,  e_3 *1e-3,  e_4 *1e-3];   % [kJ/kg]

MASSFLOW = [m_a, m_c, m_g]; % [kg/s]

COMBUSTION = struct();
COMBUSTION.LHV    = LHV; % [kJ/kg]
COMBUSTION.e_c    = e_c *1e-3; % [kJ/kg]
COMBUSTION.lambda = lambda; % [mol_air/mol_c]
COMBUSTION.Cp_g   = Cp_f(400) *1e-3; % [kJ/(kg*K)]
COMBUSTION.fum    = [m_O2f, m_N2f, m_CO2f, m_H2Of]; % [kg/s]

%% FIGURES

FIG = [];

if display
    samp = 20;
    p_12 = linspace(p_1,p_2,samp); T_12 = zeros(1,samp); h_12 = zeros(1,samp); s_12 = zeros(1,samp);
    p_23 = linspace(p_2,p_3,samp); T_23 = linspace(T_2,T_3,samp); h_23 = zeros(1,samp); s_23 = zeros(1,samp);
    p_34 = linspace(p_1,p_2,samp); T_34 = zeros(1,samp); h_34 = zeros(1,samp); s_34 = zeros(1,samp);
    T_41 = linspace(T_4,T_1,samp); h_41 = zeros(1,samp); s_41 = zeros(1,samp);
    for i = 1:samp
        [T_12(i),Cp] = Compression(p_12(i)/p_1);
        h_12(i) = h_1 + Cp*(T_12(i) - T_1); % formule enthalpie
        s_12(i) = s_1 + (1-eta_PiC) * Cp*log(T_12(i)/T_1); % cf. eq 3.15

        Cp = integral(@Cp_air,T_2,T_23(i))*(1-i/samp) + integral(@Cp_f,T_2,T_23(i))*i/samp;
        h_23(i) = h_2 + Cp*(T_23(i) - T_2);
        s_3 = s_2 + Cp*log(T_23(i)/T_2)/(T_23(i)-T_2) - (R_air*(1-i/samp)+R_f*i/samp)*log(p_23(i)/p_2);

        [T_34(i),Cp] = Detente(p_34(i)/p_3);
        h_34(i) = h_3 + Cp*(T_34(i) - T_3); % formule enthalpie
        s_34(i) = s_3 - (1-eta_PiT)/eta_PiT * Cp*log(T_34(i)/T_3); % cf. eq 3.16

        Cp = integral(@Cp_air,T_1,T_41(i))*i/samp + integral(@Cp_f,T_1,T_41(i))*(1-i/samp);
        h_41(i) = h_1 + Cp*(T_41(i) - T_1);
        s_41(i) = s_1 + Cp*log(T_41(i)/T_1) /(T_41(i) - T_1);
    end
    T_12 = T_12-273.15; T_23 = T_23-273.15; T_34 = T_34-273.15; T_41 = T_41-273.15;
    figure;
    plot([s_12,s_23,s_34,s_41],[T_12,T_23,T_34,T_41]);

    FIG(1) = figure;
    labels = {'1','2','3','4'};
    X = DAT(4,:); Y = DAT(3,:);
    p = plot(X,Y,'b',[DAT(4,4) DAT(4,1)],[DAT(3,4) DAT(3,1)],'b');
    p(1).Marker = 'o';
    p(1).MarkerFaceColor = p(1).Color;
    text(X,Y,labels,'FontSize',12,'VerticalAlignment','bottom','HorizontalAlignment','right')
    title('H-S Graph');
    axis([0 2 0 1800]);
    ylabel('Enthalpy [kJ/kg]');
    xlabel('Entropy [kJ/kg.K]')
    
    FIG(2) = figure;
    labels = {'1','2','3','4'};
    X = DAT(4,:); Y = DAT(1,:)+273.15;
    p = plot(X,Y,'b',[DAT(4,4) DAT(4,1)],[DAT(1,4)+273.15 DAT(1,1)+273.15],'b');
    p(1).Marker = 'o';
    p(1).MarkerFaceColor = p(1).Color;
    text(X,Y,labels,'FontSize',12,'VerticalAlignment','bottom','HorizontalAlignment','right')
    title('T-S Graph');
    axis([0 2 0 1800]);
    ylabel('Temperature [K]');
    xlabel('Entropy [kJ/kg.K]');
    
    FIG(3) = figure;
    X = [P_e*1e-3 DATEX(2) DATEX(4) DATEX(1) DATEX(3)];
    labels = {sprintf('Effective  Power \n (%g MW)', P_e*1e-3),...
             sprintf('Turbine & Compressor \n Irreversibilities \n (%g MW)', perte_rotex),...
             sprintf('Exhaust  Loss \n (%g MW)', perte_echex),...
             sprintf('Mechanical \n Losses \n (%g MW)', perte_mecex),...
             sprintf('Combustion \n Irreversibility \n (%g MW)', perte_combex)};
    pie(X,labels);
    title(sprintf('Primary Exergy Flux (%g MW)', P_prim/10^6));
end
end
