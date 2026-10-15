%================================================================================
% This function calculates the IIR filter coefficients, the bit depth of this 
% filter, and calculates the stimulus signal.
%================================================================================
function IIR_calc_auto(build_path, varargs)
    %================================================================================
    %% Default parameters
    %================================================================================
    
    F_clk = 100e6; % Clock
    F_s = 100e6; % Sampling frequency
    filterType = 'lowpass'; % Filter Type
    filterApprox = 'butter'; % Design method ('butter' 'ellip', 'cheby1', 'cheby2')
    Fpass = 10e6; % Passband edge
    Fstop = 15e6; % Stopband edge
    Fpass1 = 10e6; % First Passband edge
    Fpass2 = 15e6; % Second Passband edge
    Fstop1 = 7e6; % First Stopband edge
    Fstop2 = 18e6; % Stopband edge
    Apass = 0.1; % Passband ripple in dB
    Astop = 60; % Stopband ripple in dB
    Apass1 = 0.1; % First Passband ripple in dB
    Apass2 = 0.1; % Second Passband ripple in dB
    Astop1 = 60; % First Stopband ripple in dB
    Astop2 = 60; % Second Stopband ripple in dB
    coeff_WL = 16; % Word lengths for coefficients
    in_WL = 16; % Word lengths for input signal
    in_FL = 15; % Fraction lengths for input signal
    out_WL = 16; % Word lengths for output signal
    s_in_WL = 16; % Section input word length
    s_out_WL = 16; % Section output word length
    state_WL = 16; % State word length
    state_FL = 15; % State fraction length
    out_file_a = build_path + "/a_coeffs.txt"; % Denominator coefficients file path
    out_file_b = build_path + "/b_coeffs.txt"; % Numerator coefficients file path
    out_file_scale = build_path + "/scale_coeffs.txt"; % Scale coefficients file path
    out_file_params = build_path + "/iir_params.vh"; % IIR parameters file path
    out_file_stimul = build_path + "/stimulus.txt"; % Stimulus file path
    num_format = 'hex'; % Coefficients representation format ('dec', 'hex', 'bin')

    if ~isfolder(build_path)
        mkdir(build_path); % Build directory
    end

    %================================================================================
    %% Checking command line arguments
    %================================================================================
    for i = 1:2:length(varargs)
        flag = varargs{i};
        if (i + 1 <= length(varargs))
            val = varargs{i + 1};
            switch flag
                case '-F_CLK'
                    F_clk = str2double(val);
                case '-F_S'
                    F_s = str2double(val);
                case '-FILTER_TYPE'
                    filterType = val;
                case '-FILTER_APPROX'
                    filterApprox = val;
                case '-F_PASS'
                    Fpass = str2double(val);
                case '-F_STOP'
                    Fstop = str2double(val);
                case '-F_PASS1'
                    Fpass1 = str2double(val);
                case '-F_PASS2'
                    Fpass2 = str2double(val);
                case '-F_STOP1'
                    Fstop1 = str2double(val);
                case '-F_STOP2'
                    Fstop2 = str2double(val);
                case '-A_PASS'
                    Apass = str2double(val);
                case '-A_STOP'
                    Astop = str2double(val);
                case '-A_PASS1'
                    Apass1 = str2double(val);
                case '-A_PASS2'
                    Apass2 = str2double(val);
                case '-A_STOP1'
                    Astop1 = str2double(val);
                case '-A_STOP2'
                    Astop2 = str2double(val);
                case '-IN_WL'
                    in_WL = str2double(val);
                case '-IN_FL'
                    in_FL = str2double(val);
                case '-H_WL'
                    coeff_WL = str2double(val);
                case '-OUT_WL'
                    out_WL = str2double(val);
                case '-SEC_IN_WL'
                    s_in_WL = str2double(val);
                case '-SEC_OUT_WL'
                    s_out_WL = str2double(val);
                case '-STATE_WL'
                    state_WL = str2double(val);
                case '-STATE_FL'
                    state_FL = str2double(val);
            end
        end
    end

    if (F_s > F_clk)
        error('[ERROR] F_clk must be greater than or equal to F_s');
    elseif (mod(F_clk, F_s) ~= 0)
        error('[ERROR] F_clk must be divisible by F_s');
    end
    
    %================================================================================
    %% Selecting a filter type
    %================================================================================
    switch filterType
        case 'lowpass'
            Fpass = Fpass;
            Fstop = Fstop;
            Apass = Apass;
            Astop = Astop;
        case 'highpass'
            Fpass = Fpass;
            Fstop = Fstop;
            Apass = Apass;
            Astop = Astop;
        case 'bandpass'
            Fpass = [Fpass1 Fpass2];
            Fstop = [Fstop1 Fstop2];
            Apass = Apass;
            Astop = [Astop1 Astop2];
        case 'bandstop'
            Fpass = [Fpass1 Fpass2];
            Fstop = [Fstop1 Fstop2];
            Apass = [Apass1, Apass2];
            Astop = Astop;
    end
    
    %================================================================================
    %% Calculation of filter coefficients
    %================================================================================
    Hd = IIR_Calculation(F_s, filterType, filterApprox, Fpass, Fstop, Apass, Astop);
    
    b = Hd.sosMatrix; % SOS Matrix (a and b coefficients)
    [num_sections, ~] = size(Hd.sosMatrix); % Number of sections
    N = num_sections * 2; % IIR Order
    
    B_sections = b(:, 1:3); % Numerator
    A_sections = b(:, 4:6); % Denominator
    a_coeffs = A_sections(:, 2:end); % Removal of the first coefficient (always 1)
    
    [h_dbl, f] = freqz(Hd.sosMatrix, 4096, F_s); % Magnitude response of digital filter (Double coefficients)
    h_dbl = h_dbl * prod(Hd.ScaleValues); % Scaling Magnitude response
    
    b_fix = fi(B_sections, true, coeff_WL); % Converting numerator coefficients to Fixed-Point
    a_fix = fi(a_coeffs, true, coeff_WL); % Converting denominator coefficients to Fixed-Point

    %================================================================================
    %% Calculation of bit depth
    %================================================================================
    coeff_b_FL = b_fix.FractionLength; % Determining the optimal length of the fractional part
    coeff_a_FL = a_fix.FractionLength; % Determining the optimal length of the fractional part
    
    scale = Hd.ScaleValues; % Scale coefficients
    if (scale(end) == 1) % The last coefficient is not taken into account when calculating bit bit depths if it equals 1
        scale_IL = ceil(log2(max(abs(scale(1:end - 1))))) + 1; % Scale integer bit depth
    else
        scale_IL = ceil(log2(max(abs(scale)))) + 1; % Scale integer bit depth
    end
    scale_FL = coeff_WL - scale_IL; % Scale fraction length
    
    mult_WL = state_WL + coeff_WL; % Product word length
    mult_a_FL = state_FL + coeff_a_FL; % Product denominator fraction length
    mult_b_FL = state_FL + coeff_b_FL; % Product numerator fraction length
    
    guard_bits_num = ceil(log2(size(double(b_fix), 2))); % Numerator guard bits
    guard_bits_Denom = ceil(log2(size(double(a_fix), 2))); % Denominator guard bits
    acc_a_FL = mult_a_FL; % Optimal fraction lengths for accumulators
    acc_b_FL = mult_b_FL; % Optimal fraction lengths for accumulators
    acc_WL = max([guard_bits_num guard_bits_Denom]) + mult_WL; % Accumulator word length
    acc_b_IL = mult_WL + guard_bits_num - acc_b_FL; % Accumulator Numerator integer bit depth
    
    s_out_IL = acc_b_IL; % Section output integer bit depth
    s_out_FL = s_out_WL - s_out_IL; % Section output fraction length
    
    s_in_FL = s_in_WL - ((s_out_WL + coeff_WL) - (s_out_FL + scale_FL)); % Section input fraction length
    
    s_out_out_delta_WL = s_out_WL - out_WL; % Section output and IIR output word length delta
    out_FL = s_out_FL - s_out_out_delta_WL; % Output fraction length
    
    %================================================================================
    %% Report
    %================================================================================
    fprintf('\n==================== IIR Parameters ====================\n')
    fprintf('Input Word length                  : %d\n', in_WL);
    fprintf('Input Fraction length              : %d\n', in_FL);
    fprintf('Output Word length                 : %d\n', out_WL);
    fprintf('Output Fraction length             : %d\n', out_FL);
    fprintf('Coeff Word length                  : %d\n', coeff_WL);
    fprintf('Coeff Num. Fraction length         : %d\n', coeff_b_FL);
    fprintf('Coeff Denom. Fraction length       : %d\n', coeff_a_FL);
    fprintf('Scale Values Fraction length       : %d\n', scale_FL);
    fprintf('Section Input Word length          : %d\n', s_in_WL);
    fprintf('Section Input Fraction length      : %d\n', s_in_FL);
    fprintf('Section Output Word length         : %d\n', s_out_WL);
    fprintf('Section Output Fraction length     : %d\n', s_out_FL);
    fprintf('State Word length                  : %d\n', state_WL);
    fprintf('State Fraction length              : %d\n', state_FL);
    fprintf('Product Word length                : %d\n', mult_WL);
    fprintf('Product Num. Fraction length       : %d\n', mult_b_FL);
    fprintf('Product Denom. Fraction length     : %d\n', mult_a_FL);
    fprintf('Accum. Word length                 : %d\n', acc_WL);
    fprintf('Accum. Num. Fraction length        : %d\n', acc_b_FL);
    fprintf('Accum. Denom. Fraction length      : %d\n', acc_a_FL);
    
    %================================================================================
    %% Output coefficients
    %================================================================================
    % Set the arithmetic property for IIR
    set(Hd, 'Arithmetic', 'fixed', ...
        'CoeffWordLength', coeff_WL, ...
        'CoeffAutoScale', false, ...
        'NumFracLength', coeff_b_FL, ...
        'DenFracLength', coeff_a_FL, ...
        'ScaleValueFracLength', scale_FL, ...
        'ProductMode', 'specifyprecision', ...
        'ProductWordLength', mult_WL, ...
        'NumProdFracLength', mult_b_FL, ...
        'DenProdFracLength', mult_a_FL, ...
        'AccumMode', 'specifyprecision', ...
        'AccumWordLength', acc_WL, ...
        'NumAccumFracLength', acc_b_FL, ...
        'DenAccumFracLength', acc_a_FL, ...
        'StateWordLength', state_WL, ...
        'StateFracLength', state_FL, ...
        'SectioninputWordLength', s_in_WL, ...
        'SectioninputAutoScale', false, ...
        'SectioninputFracLength', s_in_FL, ...
        'SectionoutputWordLength', s_out_WL, ...
        'SectionoutputAutoScale', false, ...
        'SectionoutputFracLength', s_out_FL, ...
        'InputWordLength', in_WL, ...
        'inputFracLength', in_FL, ...
        'OutputWordLength', out_WL, ...
        'OutputMode', 'SpecifyPrecision', ...
        'outputFracLength', out_FL, ...
        'signed',        true, ...
        'RoundMode',     'convergent', ...
        'OverflowMode',  'Wrap', ...
        'CastBeforeSum', true);

    b_fix_out = fi(reshape(b_fix', [], 1), true, coeff_WL, coeff_b_FL); % Numerator coefficients
    a_fix_out = fi(reshape(a_fix', [], 1), true, coeff_WL, coeff_a_FL); % Denominator coefficients
    if (scale(end) == 1)
        scale_fix = fi(scale(1:end - 1), true, coeff_WL, scale_FL);
        out_mult = 0; % Output multiplier disable
    else
        scale_fix = fi(scale, true, coeff_WL, scale_FL);
        out_mult = 1; % Output multiplier enable
    end
    
    [h_fix, ~] = freqz(double(Hd.sosMatrix), 4096, F_s); % Magnitude response of digital filter (Fixed-Point coefficients)
    h_fix = h_fix * prod(double(scale_fix)); % Scaling Magnitude response
    
    write_file(out_file_b, b_fix_out, num_format);
    write_file(out_file_a, a_fix_out, num_format);
    write_file(out_file_scale, scale_fix, num_format);
    
    %================================================================================
    %% Plotting magnitude response graphs
    %================================================================================
    figure('Visible', 'off');
    plot(f/1e6, 20 * log10(abs(h_dbl)), 'b', 'LineWidth', 1.5);
    hold on;
    plot(f/1e6, 20 * log10(abs(h_fix)), 'r--', 'LineWidth', 1.2);
    grid on;
    set(gcf, 'WindowState', 'maximized');
    
    title(sprintf('Magnitude Response (%s) | Order N = %d', filterType, N), 'FontSize', 12);
    xlabel('Frequency (MHz)');
    ylabel('Magnitude (dB)');
    legend({'Double Precision', 'Fixed-Point'}, 'Location', 'northeast');
    
    exportgraphics(gca, build_path + "/MagResponse.png")
    %================================================================================
    %% Stimulus signal generation
    %================================================================================
    f_sig = [Fpass/10 Fpass/2 Fpass Fpass * 2 Fpass * 2.5]; % Sin frequencies
    N_sine = 500; % Number of Sine Samples
    A = 0.9; % Amplitude
    noise_std = 0.03; % Standart Deviation of Noise
    
    noise = noise_std * randn(1, N_sine); % Noise signal
    
    %================================================================================
    %% Samples of different segments of sinusoids with noise
    %================================================================================
    t = (0:N_sine - 1) / F_s;
    for i = 1:5
        sine_wave(i,:) = A * sin(2 * pi * f_sig(i) * t) + noise;
    end
    
    %================================================================================
    %% Stimulus signal and writing its samples to a file
    %================================================================================
    sine_stimul = fi([sine_wave(1,:) sine_wave(2,:) sine_wave(3,:) sine_wave(4,:) sine_wave(5,:)], true, in_WL, in_FL);
    write_file(out_file_stimul, sine_stimul, 'dec');
    
    %================================================================================
    %% Writing parameters for RTL
    %================================================================================
    fid = fopen(out_file_params, 'w');
    fprintf(fid, 'localparam ORDER = %d;\n', N); % IIR order
    fprintf(fid, 'localparam INPUT_WL = %d;\n', in_WL); % Input word length
    fprintf(fid, 'localparam INPUT_FL = %d;\n', in_FL); % Input fraction length
    fprintf(fid, 'localparam COEFFICIENT_WL = %d;\n', coeff_WL); % Coeffs word length
    fprintf(fid, 'localparam COEFFICIENT_NUM_FL = %d;\n', coeff_b_FL); % Coeffs Num. fraction length
    fprintf(fid, 'localparam COEFFICIENT_DENOM_FL = %d;\n', coeff_a_FL); % Coeffs Denom. fraction length
    fprintf(fid, 'localparam COEFFICIENT_SCALE_FL = %d;\n', scale_FL); % Scale fraction length
    fprintf(fid, 'localparam SEC_INPUT_WL = %d;\n', s_in_WL); % Section input word length
    fprintf(fid, 'localparam SEC_INPUT_FL = %d;\n', s_in_FL); % Section input fraction length
    fprintf(fid, 'localparam SEC_OUTPUT_WL = %d;\n', s_out_WL); % Section output word length
    fprintf(fid, 'localparam SEC_OUTPUT_FL = %d;\n', s_out_FL); % Section output fraction length
    fprintf(fid, 'localparam PROD_WL = %d;\n', mult_WL); % Mults word length
    fprintf(fid, 'localparam PROD_NUM_FL = %d;\n', mult_b_FL); % Mult Num. fraction length
    fprintf(fid, 'localparam PROD_DENOM_FL = %d;\n', mult_a_FL); % Mult Denom. fraction length
    fprintf(fid, 'localparam ACCUM_WL = %d;\n', acc_WL); % Accumulators word length
    fprintf(fid, 'localparam ACCUM_NUM_FL = %d;\n', acc_b_FL); % Accumulator Num. fraction length
    fprintf(fid, 'localparam ACCUM_DENOM_FL = %d;\n', acc_a_FL); % Accumulator Denom. fraction length
    fprintf(fid, 'localparam OUTPUT_WL = %d;\n', out_WL); % Output word length
    fprintf(fid, 'localparam OUTPUT_FL = %d;\n', out_FL); % Output fraction length
    fprintf(fid, 'localparam STATE_IIR_WL = %d;\n', state_WL); % State word length
    fprintf(fid, 'localparam STATE_IIR_FL = %d;\n', state_FL); % State fraction length
    fprintf(fid, 'localparam OUT_MULTIPLIER = %d;\n', out_mult); % Output multiplier
    fprintf(fid, 'localparam F_CLK = %d;\n', F_clk); % Clock frequency
    fprintf(fid, 'localparam CLK_EN_DIV = %d;\n', F_clk/F_s); % Clock division factor for determining the clock enable frequency
    fprintf(fid, 'localparam SIN_NUM_SAMPLES = %d;', length(sine_stimul)); % Number of stimulus signal samples
    fclose(fid);
    
    %================================================================================
    %% Saving data for analysis
    %================================================================================
    save_data.F_clk = F_clk;
    save_data.F_s = F_s;
    save_data.Fpass = Fpass;
    save_data.Fstop = Fstop;
    save_data.filterType = char(filterType);
    save_data.filterApprox = char(filterApprox);
    save_data.Apass = Apass;
    save_data.Astop = Astop;
    save_data.in_WL = in_WL;
    save_data.in_FL = in_FL;
    save_data.coeff_WL = coeff_WL;
    save_data.coeff_b_FL = coeff_b_FL;
    save_data.coeff_a_FL = coeff_a_FL;
    save_data.out_WL = out_WL;
    save_data.out_FL = out_FL;
    save_data.scale_FL = scale_FL;
    save_data.s_in_WL = s_in_WL;
    save_data.s_in_FL = s_in_FL;
    save_data.s_out_WL = s_out_WL;
    save_data.s_out_FL = s_out_FL;
    save_data.mult_WL = mult_WL;
    save_data.mult_b_FL = mult_b_FL;
    save_data.mult_a_FL = mult_a_FL;
    save_data.acc_WL = acc_WL;
    save_data.acc_b_FL = acc_b_FL;
    save_data.acc_a_FL = acc_a_FL;
    save_data.state_WL = state_WL;
    save_data.state_FL = state_FL;

    save('../matlab/params.mat', '-struct', 'save_data');

end