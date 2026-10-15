//=====================================================================================
// 		Second-Order Section, Direct Form II
//
//			Parameters:
//				OUT_WL - output word length
//				OUT_FL - output fraction length
//				SEC_IN_WL - section input word length
//				SEC_IN_FL - section input fraction length
//				SEC_OUT_WL - section output word length
//				SEC_OUT_FL - section output fraction length
//				STATE_WL - state word length
//				STATE_FL - state fraction length
//				COEFF_WL - coefficients word length
//				COEFF_NUM_FL - numerator fraction length
//				COEFF_DENOM_FL - denominator fraction length
//				SCALE_FL - scale values fraction length
//				MULT_WL - product word length
//				MULT_NUM_FL - product numerator fraction length
//				MULT_DENOM_FL - product denominator fraction length
//				ACC_WL - accumulator word length
//				ACC_NUM_FL - accumulator numerator fraction length
//				ACC_DENOM_FL - accumlulator denominator fraction length
//				ROUND_MODE - rounding method (0 - Truncation, 1 - Nearest 2 - Convergent)
//				LAST_SEC - IIR last section (0 - No, 1 - Yes)
//				OUT_MULT - activation of the output multiplier (0 - No, 1 - Yes)
//
//			Control Signals:
//				clk - clock signal
//				rst_n – reset (Active-Low)
//				valid_in - input data valid
//
//			Data:
//				b0 - numerator b0
//				b1 - numerator b1
//				b2 - numerator b2
//				a1 - denomenator a1
//				a2 - denomenator a2
//				data_in - input data
//				data_out - output data
//=====================================================================================

module iir_sos_df2
#(
	parameter OUT_WL = 16, // Output word length
	parameter OUT_FL = 10, // Output fraction length
	parameter SEC_IN_WL = 16, // Section input word length
	parameter SEC_IN_FL = 12, // Section input fraction length
	parameter SEC_OUT_WL = 16, // Section output word length
	parameter SEC_OUT_FL = 10, // Section output fraction length
	parameter STATE_WL = 16, // State word length
	parameter STATE_FL = 15, // State fraction length
	parameter COEFF_WL = 16, // Coefficients word length
	parameter COEFF_NUM_FL = 13, // Numerator fraction length
	parameter COEFF_DENOM_FL = 14, // Denominator fraction length
	parameter MULT_WL = 32, // Product word length
	parameter MULT_NUM_FL = 28, // Product Numerator fraction length
	parameter MULT_DENOM_FL = 29, // Product Denominator fraction length
	parameter ACC_WL = 34, // Accumulator word length
	parameter ACC_NUM_FL = 28, // Accumulator Numerator fraction length
	parameter ACC_DENOM_FL = 29, // Accumlulator Denominator fraction length
	parameter ROUND_MODE = 2, // Rounding method
	parameter LAST_SEC = 0, // IIR last section
	parameter OUT_MULT = 0 // Activation of the output multiplier
)
(
	input clk, // Clock
	input rst_n, // Reset
	input valid_in, // Input data valid 
	input signed [COEFF_WL - 1:0] b0, // Numerator b0
	input signed [COEFF_WL - 1:0] b1, // Numerator b1
	input signed [COEFF_WL - 1:0] b2, // Numerator b2
	input signed [COEFF_WL - 1:0] a1, // Denominator a1
	input signed [COEFF_WL - 1:0] a2, // Denominator a2
	input signed [SEC_IN_WL - 1:0] data_in, // Input data
	output logic signed [(LAST_SEC && !OUT_MULT ? OUT_WL : SEC_OUT_WL) - 1:0] data_out // Output data
);

logic signed [STATE_WL - 1:0] w0, w1, w2; // State delay lines
(* multstyle = "dsp" *) logic signed [MULT_WL - 1:0] a1_w1_prod, a2_w2_prod; // Feedback products
logic signed [ACC_WL - 1:0] acc_den; // Feedback accumulator
(* multstyle = "dsp" *) logic signed [MULT_WL - 1:0] b0_w0_prod, b1_w1_prod, b2_w2_prod; // Feedforward products
logic signed [ACC_WL - 1:0] acc_num; // Feedforward accumulator

//=====================================================================================
// Section Feedback products
//=====================================================================================
assign a1_w1_prod = w1 * a1;
assign a2_w2_prod = w2 * a2;

//=====================================================================================
// Section Feedback accumulator
//=====================================================================================
assign acc_den = (data_in << MULT_DENOM_FL - SEC_IN_FL) - a1_w1_prod - a2_w2_prod; // The fraction length of the input data is adjusted to match the fraction length of the products

//=====================================================================================
// Rounding of data for input to the state delay line
//=====================================================================================
fp_resize_round #(.IN_WL(ACC_WL), .IN_FL(ACC_DENOM_FL), .OUT_WL(STATE_WL), .OUT_FL(STATE_FL), .ROUND_MODE(ROUND_MODE), .SATURATE(0)) w0_round
(
	.data_in(acc_den),
	.data_out(w0)
);

//=====================================================================================
// State delay line
//=====================================================================================
always_ff @ (posedge clk, negedge rst_n) begin
	if (!rst_n) begin
		w1 <= {STATE_WL{1'b0}};
		w2 <= {STATE_WL{1'b0}};
	end
	else begin
		if (valid_in) begin
			w1 <= w0;
			w2 <= w1;
		end
	end
end

//=====================================================================================
// Section Feedforward products
//=====================================================================================
always_ff @ (posedge clk, negedge rst_n) begin
	if (!rst_n) begin
		b0_w0_prod <= {MULT_WL{1'b0}};
		b1_w1_prod <= {MULT_WL{1'b0}};
		b2_w2_prod <= {MULT_WL{1'b0}};
	end
	else begin
		if (valid_in) begin
			b0_w0_prod <= b0 * w0;
			b1_w1_prod <= b1 * w1;
			b2_w2_prod <= b2 * w2;
		end
	end
end

//=====================================================================================
// Section Feedforward accumulator
//=====================================================================================
assign acc_num = b0_w0_prod + b1_w1_prod + b2_w2_prod;

//=====================================================================================
// Processing of section output data
//=====================================================================================
generate
	logic signed [(LAST_SEC && !OUT_MULT ? OUT_WL : SEC_OUT_WL) - 1:0] data_out_rounded; // Rounded data
	logic signed [(LAST_SEC && !OUT_MULT ? OUT_WL : SEC_OUT_WL) - 1:0] data_out_temp; // Temporary data storage

//=====================================================================================
// All IIR sections except the last one
//=====================================================================================
	if (!LAST_SEC) begin	: g_other_sec
//-------------------------------------------------------------------------------------
// Rounding of output data	to section output lengths
		fp_resize_round #(.IN_WL(ACC_WL), .IN_FL(ACC_NUM_FL), .OUT_WL(SEC_OUT_WL), .OUT_FL(SEC_OUT_FL), .ROUND_MODE(ROUND_MODE), .SATURATE(0)) w0_round
		(
			.data_in(acc_num),
			.data_out(data_out_rounded)
		);
//-------------------------------------------------------------------------------------
// Output register		
		always_ff @ (posedge clk, negedge rst_n) begin
			if (!rst_n) begin
				data_out_temp <= {SEC_OUT_WL{1'b0}};
			end
			else begin
				if (valid_in) begin
					data_out_temp <= data_out_rounded;
				end
			end
		end
		
		assign data_out = data_out_temp;
	end
//=====================================================================================
// Last IIR section
//=====================================================================================
	else begin : g_last_sec
//=====================================================================================
// Output scaling
//=====================================================================================
		if (OUT_MULT) begin : g_out_scale
//-------------------------------------------------------------------------------------
// Rounding of output data	to section output lengths		
			fp_resize_round #(.IN_WL(ACC_WL), .IN_FL(ACC_NUM_FL), .OUT_WL(SEC_OUT_WL), .OUT_FL(SEC_OUT_FL), .ROUND_MODE(ROUND_MODE), .SATURATE(0)) w0_round
			(
				.data_in(acc_num),
				.data_out(data_out_rounded)
			);
			
			assign data_out = data_out_rounded;
		end
//=====================================================================================
// Without output scaling
//=====================================================================================
		else begin : g_out_not_scale
//-------------------------------------------------------------------------------------
// Rounding of output data	to IIR output lengths
			fp_resize_round #(.IN_WL(ACC_WL), .IN_FL(ACC_NUM_FL), .OUT_WL(OUT_WL), .OUT_FL(OUT_FL), .ROUND_MODE(ROUND_MODE), .SATURATE(0)) w0_round
			(
				.data_in(acc_num),
				.data_out(data_out_rounded)
			);
//-------------------------------------------------------------------------------------
// Output register			
			always_ff @ (posedge clk, negedge rst_n) begin
				if (!rst_n) begin
					data_out_temp <= {OUT_WL{1'b0}};
				end
				else begin
					if (valid_in) begin
						data_out_temp <= data_out_rounded;
					end
				end
			end
			
			assign data_out = data_out_temp;
		end
	end
endgenerate

endmodule