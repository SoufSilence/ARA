// Copyright 2020 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// File:   simd_mul.sv
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Date:   12.02.2021
//
// Copyright (C) 2020 ETH Zurich, University of Bologna
// All rights reserved.
//
// Description:
// Ara's SIMD ALU, operating on elements 64-bit wide, and generating 64 bits per cycle.

module simd_alu import ara_pkg::*; import rvv_pkg::*; #(
    // Dependant parameters. DO NOT CHANGE!
    parameter int  unsigned DataWidth = $bits(elen_t),
    parameter int  unsigned StrbWidth = DataWidth/8,
    parameter type          strb_t    = logic [StrbWidth-1:0]
  ) (
    input  elen_t   operand_a_i,
    input  elen_t   operand_b_i,
    input  logic    valid_i,
    input  logic    vm_i,
    input  strb_t   mask_i,
    input  logic    narrowing_select_i,
    input  ara_op_e op_i,
    input  vew_e    vew_i,
    output elen_t   result_o
  );

  /*****************
   *  Definitions  *
   *****************/

  typedef union packed {
    logic [0:0][63:0] w64;
    logic [1:0][31:0] w32;
    logic [3:0][15:0] w16;
    logic [7:0][ 7:0] w8;
  } alu_operand_t;

  alu_operand_t opa, opb, res;
  assign opa      = operand_a_i;
  assign opb      = operand_b_i;
  assign result_o = res;

  /*****************
   *  Comparisons  *
   *****************/

  // Comparison instructions that use signed operands
  logic is_signed;
  assign is_signed = op_i inside {VMAX, VMIN, VMSLT, VMSLE, VMSGT};
  // Compare operands.
  // For vew_i = EW8, all bits are valid.
  // For vew_i = EW16, bits 0, 2, 4, and 6 are valid.
  // For vew_i = EW32, bits 0 and 4 are valid.
  // For vew_i = EW64, only bit 0 indicates the result of the comparison.
  logic [7:0] less;
  logic [7:0] equal;

  always_comb begin: p_comparison
    // Default assignment
    less  = '0;
    equal = '0;

    if (valid_i) begin
      unique case (vew_i)
        EW8 : for (int b = 0; b < 8; b++) less[1*b] = $signed({is_signed & opb.w8 [b][ 7], opb.w8 [b]}) < $signed({is_signed & opa.w8 [b][ 7], opa.w8 [b]});
        EW16: for (int b = 0; b < 4; b++) less[2*b] = $signed({is_signed & opb.w16[b][15], opb.w16[b]}) < $signed({is_signed & opa.w16[b][15], opa.w16[b]});
        EW32: for (int b = 0; b < 2; b++) less[4*b] = $signed({is_signed & opb.w32[b][31], opb.w32[b]}) < $signed({is_signed & opa.w32[b][31], opa.w32[b]});
        EW64: for (int b = 0; b < 1; b++) less[8*b] = $signed({is_signed & opb.w64[b][63], opb.w64[b]}) < $signed({is_signed & opa.w64[b][63], opa.w64[b]});
        default:;
      endcase

      unique case (vew_i)
        EW8 : for (int b = 0; b < 8; b++) equal[1*b] = opa.w8 [b] == opb.w8 [b];
        EW16: for (int b = 0; b < 4; b++) equal[2*b] = opa.w16[b] == opb.w16[b];
        EW32: for (int b = 0; b < 2; b++) equal[4*b] = opa.w32[b] == opb.w32[b];
        EW64: for (int b = 0; b < 1; b++) equal[8*b] = opa.w64[b] == opb.w64[b];
        default:;
      endcase
    end
  end: p_comparison

  /*********
   *  ALU  *
   *********/

  always_comb begin: p_alu
    // Default assignment
    res = '0;

    if (valid_i)
      unique case (op_i)
        // Logical operations
        VAND: res = operand_a_i & operand_b_i;
        VOR : res = operand_a_i | operand_b_i;
        VXOR: res = operand_a_i ^ operand_b_i;

        // Mask logical operations
        VMAND   : res = operand_a_i & operand_b_i;
        VMANDNOT: res = ~operand_a_i & operand_b_i;
        VMNAND  : res = ~(operand_a_i & operand_b_i);
        VMOR    : res = operand_a_i | operand_b_i;
        VMNOR   : res = ~(operand_a_i | operand_b_i);
        VMORNOT : res = ~operand_a_i | operand_b_i;
        VMXOR   : res = operand_a_i ^ operand_b_i;
        VMXNOR  : res = ~(operand_a_i ^ operand_b_i);

        // Arithmetic instructions
        VADD, VADC, VMADC: unique case (vew_i)
            EW8: for (int b = 0; b < 8; b++) begin
                automatic logic [8:0] sum = opa.w8[b] + opb.w8[b] + logic'(op_i inside {VADC, VMADC} && mask_i[1*b] && vm_i);
                res.w8[b]                 = (op_i == VMADC) ? {7'b0, sum[8]} : sum[7:0];
              end
            EW16: for (int b = 0; b < 4; b++) begin
                automatic logic [16:0] sum = opa.w16[b] + opb.w16[b] + logic'(op_i inside {VADC, VMADC} && mask_i[2*b] && vm_i);
                res.w16[b]                 = (op_i == VMADC) ? {15'b0, sum[16]} : sum[15:0];
              end
            EW32: for (int b = 0; b < 2; b++) begin
                automatic logic [32:0] sum = opa.w32[b] + opb.w32[b] + logic'(op_i inside {VADC, VMADC} && mask_i[4*b] && vm_i);
                res.w32[b]                 = (op_i == VMADC) ? {31'b0, sum[32]} : sum[31:0];
              end
            EW64: for (int b = 0; b < 1; b++) begin
                automatic logic [64:0] sum = opa.w64[b] + opb.w64[b] + logic'(op_i inside {VADC, VMADC} && mask_i[8*b] && vm_i);
                res.w64[b]                 = (op_i == VMADC) ? {63'b0, sum[64]} : sum[63:0];
              end
            default:;
          endcase
        VSUB, VSBC, VMSBC: unique case (vew_i)
            EW8: for (int b = 0; b < 8; b++) begin
                automatic logic [8:0] sub = $signed(opb.w8[b]) - $signed(opa.w8[b]) - $signed(logic'(op_i inside {VSBC, VMSBC} && mask_i[1*b] && vm_i));
                res.w8[b]                 = (op_i == VMSBC) ? {7'b0, sub[8]} : sub[7:0];
              end
            EW16: for (int b = 0; b < 4; b++) begin
                automatic logic [16:0] sub = $signed(opb.w16[b]) - $signed(opa.w16[b]) - $signed(logic'(op_i inside {VSBC, VMSBC} && mask_i[2*b] && vm_i));
                res.w16[b]                 = (op_i == VMSBC) ? {15'b0, sub[16]} : sub[15:0];
              end
            EW32: for (int b = 0; b < 2; b++) begin
                automatic logic [32:0] sub = $signed(opb.w32[b]) - $signed(opa.w32[b]) - $signed(logic'(op_i inside {VSBC, VMSBC} && mask_i[4*b] && vm_i));
                res.w32[b]                 = (op_i == VMSBC) ? {31'b0, sub[32]} : sub[31:0];
              end
            EW64: for (int b = 0; b < 1; b++) begin
                automatic logic [64:0] sub = $signed(opb.w64[b]) - $signed(opa.w64[b]) - $signed(logic'(op_i inside {VSBC, VMSBC} && mask_i[8*b] && vm_i));
                res.w64[b]                 = (op_i == VMSBC) ? {63'b0, sub[64]} : sub[63:0];
              end
            default:;
          endcase
        VRSUB: unique case (vew_i)
            EW8 : for (int b = 0; b < 8; b++) res.w8 [b] = opa.w8 [b] - opb.w8 [b];
            EW16: for (int b = 0; b < 4; b++) res.w16[b] = opa.w16[b] - opb.w16[b];
            EW32: for (int b = 0; b < 2; b++) res.w32[b] = opa.w32[b] - opb.w32[b];
            EW64: for (int b = 0; b < 1; b++) res.w64[b] = opa.w64[b] - opb.w64[b];
            default:;
          endcase

        // Shift instructions
        VSLL: unique case (vew_i)
            EW8 : for (int b = 0; b < 8; b++) res.w8 [b] = opb.w8 [b] << opa.w8 [b][2:0];
            EW16: for (int b = 0; b < 4; b++) res.w16[b] = opb.w16[b] << opa.w16[b][3:0];
            EW32: for (int b = 0; b < 2; b++) res.w32[b] = opb.w32[b] << opa.w32[b][4:0];
            EW64: for (int b = 0; b < 1; b++) res.w64[b] = opb.w64[b] << opa.w64[b][5:0];
            default:;
          endcase
        VSRL: unique case (vew_i)
            EW8 : for (int b = 0; b < 8; b++) res.w8 [b] = opb.w8 [b] >> opa.w8 [b][2:0];
            EW16: for (int b = 0; b < 4; b++) res.w16[b] = opb.w16[b] >> opa.w16[b][3:0];
            EW32: for (int b = 0; b < 2; b++) res.w32[b] = opb.w32[b] >> opa.w32[b][4:0];
            EW64: for (int b = 0; b < 1; b++) res.w64[b] = opb.w64[b] >> opa.w64[b][5:0];
            default:;
          endcase
        VSRA: unique case (vew_i)
            EW8 : for (int b = 0; b < 8; b++) res.w8 [b] = $signed(opb.w8 [b]) >>> opa.w8 [b][2:0];
            EW16: for (int b = 0; b < 4; b++) res.w16[b] = $signed(opb.w16[b]) >>> opa.w16[b][3:0];
            EW32: for (int b = 0; b < 2; b++) res.w32[b] = $signed(opb.w32[b]) >>> opa.w32[b][4:0];
            EW64: for (int b = 0; b < 1; b++) res.w64[b] = $signed(opb.w64[b]) >>> opa.w64[b][5:0];
            default:;
          endcase
        VNSRL: unique case (vew_i)
            EW8 : for (int b = 0; b < 4; b++) res.w8 [2*b + narrowing_select_i] = opb.w16[b] >> opa.w16[b][3:0];
            EW16: for (int b = 0; b < 2; b++) res.w16[2*b + narrowing_select_i] = opb.w32[b] >> opa.w32[b][4:0];
            EW32: for (int b = 0; b < 1; b++) res.w32[2*b + narrowing_select_i] = opb.w64[b] >> opa.w64[b][5:0];
            default:;
          endcase
        VNSRA: unique case (vew_i)
            EW8 : for (int b = 0; b < 4; b++) res.w8 [2*b + narrowing_select_i] = $signed(opb.w16[b]) >>> opa.w16[b][3:0];
            EW16: for (int b = 0; b < 2; b++) res.w16[2*b + narrowing_select_i] = $signed(opb.w32[b]) >>> opa.w32[b][4:0];
            EW32: for (int b = 0; b < 1; b++) res.w32[2*b + narrowing_select_i] = $signed(opb.w64[b]) >>> opa.w64[b][5:0];
            default:;
          endcase

        // Merge instructions
        VMERGE: unique case (vew_i)
            EW8 : for (int b = 0; b < 8; b++) res.w8 [b] = mask_i[b] ? opa.w8 [b] : opb.w8 [b];
            EW16: for (int b = 0; b < 4; b++) res.w16[b] = mask_i[2*b] ? opa.w16[b] : opb.w16[b];
            EW32: for (int b = 0; b < 2; b++) res.w32[b] = mask_i[4*b] ? opa.w32[b] : opb.w32[b];
            EW64: for (int b = 0; b < 1; b++) res.w64[b] = mask_i[8*b] ? opa.w64[b] : opb.w64[b];
            default:;
          endcase

        // Comparison instructions
        VMIN, VMINU, VMAX, VMAXU: unique case (vew_i)
            EW8 : for (int b = 0; b < 8; b++) res.w8 [b] = (less[1*b] ^ (op_i == VMAX || op_i == VMAXU)) ? opb.w8 [b] : opa.w8 [b];
            EW16: for (int b = 0; b < 4; b++) res.w16[b] = (less[2*b] ^ (op_i == VMAX || op_i == VMAXU)) ? opb.w16[b] : opa.w16[b];
            EW32: for (int b = 0; b < 2; b++) res.w32[b] = (less[4*b] ^ (op_i == VMAX || op_i == VMAXU)) ? opb.w32[b] : opa.w32[b];
            EW64: for (int b = 0; b < 1; b++) res.w64[b] = (less[8*b] ^ (op_i == VMAX || op_i == VMAXU)) ? opb.w64[b] : opa.w64[b];
            default:;
          endcase
        VMSEQ, VMSNE: unique case (vew_i)
            EW8 : for (int b = 0; b < 8; b++) res.w8 [b][0] = equal[1*b] ^ (op_i == VMSNE);
            EW16: for (int b = 0; b < 4; b++) res.w16[b][0] = equal[2*b] ^ (op_i == VMSNE);
            EW32: for (int b = 0; b < 2; b++) res.w32[b][0] = equal[4*b] ^ (op_i == VMSNE);
            EW64: for (int b = 0; b < 1; b++) res.w64[b][0] = equal[8*b] ^ (op_i == VMSNE);
            default:;
          endcase
        VMSLT, VMSLTU: unique case (vew_i)
            EW8 : for (int b = 0; b < 8; b++) res.w8 [b][0] = less[1*b];
            EW16: for (int b = 0; b < 4; b++) res.w16[b][0] = less[2*b];
            EW32: for (int b = 0; b < 2; b++) res.w32[b][0] = less[4*b];
            EW64: for (int b = 0; b < 1; b++) res.w64[b][0] = less[8*b];
            default:;
          endcase
        VMSLE, VMSLEU, VMSGT, VMSGTU: unique case (vew_i)
            EW8 : for (int b = 0; b < 8; b++) res.w8 [b][0] = (less[1*b] || equal[1*b]) ^ (op_i inside {VMSGT, VMSGTU});
            EW16: for (int b = 0; b < 4; b++) res.w16[b][0] = (less[2*b] || equal[2*b]) ^ (op_i inside {VMSGT, VMSGTU});
            EW32: for (int b = 0; b < 2; b++) res.w32[b][0] = (less[4*b] || equal[4*b]) ^ (op_i inside {VMSGT, VMSGTU});
            EW64: for (int b = 0; b < 1; b++) res.w64[b][0] = (less[8*b] || equal[8*b]) ^ (op_i inside {VMSGT, VMSGTU});
            default:;
          endcase

        default:;
      endcase
  end: p_alu

  /****************
   *  Assertions  *
   ****************/

  if (DataWidth != $bits(alu_operand_t))
    $error("[simd_valu] The SIMD vector ALU only works for a datapath 64-bit wide.");

endmodule : simd_alu
