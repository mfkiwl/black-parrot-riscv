
`include "bp_common_defines.svh"
`include "bp_top_defines.svh"

module bp_nonsynth_host
 import bp_common_pkg::*;
 import bp_be_pkg::*;
 import bsg_noc_pkg::*;
 import bp_me_pkg::*;
 #(parameter bp_params_e bp_params_p = e_bp_default_cfg
   `declare_bp_proc_params(bp_params_p)
   `declare_bp_bedrock_if_widths(paddr_width_p, lce_id_width_p, cce_id_width_p, did_width_p, lce_assoc_p)

   , parameter icache_trace_p         = 0
   , parameter dcache_trace_p         = 0
   , parameter lce_trace_p            = 0
   , parameter cce_trace_p            = 0
   , parameter dram_trace_p           = 0
   , parameter vm_trace_p             = 0
   , parameter cmt_trace_p            = 0
   , parameter core_profile_p         = 0
   , parameter pc_gen_trace_p         = 0
   , parameter pc_profile_p           = 0
   , parameter br_profile_p           = 0
   , parameter cosim_p                = 0
   , parameter dev_trace_p            = 0
   )
  (input                                            clk_i
   , input                                          reset_i

   , input [mem_fwd_header_width_lp-1:0]            mem_fwd_header_i
   , input [bedrock_fill_width_p-1:0]               mem_fwd_data_i
   , input                                          mem_fwd_v_i
   , output logic                                   mem_fwd_ready_and_o

   , output logic [mem_rev_header_width_lp-1:0]     mem_rev_header_o
   , output logic [bedrock_fill_width_p-1:0]        mem_rev_data_o
   , output logic                                   mem_rev_v_o
   , input                                          mem_rev_ready_and_i
   );

  import "DPI-C" context function int getchar();

  integer tmp;
  integer stdout[num_core_p];
  integer stdout_global;
  integer signature;

  always_ff @(negedge reset_i)
    begin
      for (integer j = 0; j < num_core_p; j++)
        begin
          tmp = $fopen($sformatf("stdout_%0x.txt", j), "w");
          stdout[j] = tmp;
        end
      stdout_global = $fopen("stdout_global.txt", "w");
      signature = $fopen("DUT-blackparrot.signature", "w");
    end

  localparam bedrock_reg_els_lp = 8;
  logic putint_r_v_li, signature_r_v_li, paramrom_r_v_li, bootrom_r_v_li, finish_r_v_li, getchar_r_v_li, putchar_r_v_li, putch_core_r_v_li;
  logic putint_w_v_li, signature_w_v_li, paramrom_w_v_li, bootrom_w_v_li, finish_w_v_li, getchar_w_v_li, putchar_w_v_li, putch_core_w_v_li;
  logic [dev_addr_width_gp-1:0] addr_lo;
  logic [`BSG_WIDTH(`BSG_SAFE_CLOG2(dword_width_gp/8))-1:0] size_lo;
  logic [dword_width_gp-1:0] data_lo;
  logic [bedrock_reg_els_lp-1:0][dword_width_gp-1:0] data_li;
  bp_me_bedrock_register
   #(.bp_params_p(bp_params_p)
     ,.reg_data_width_p(dword_width_gp)
     ,.reg_addr_width_p(dev_addr_width_gp)
     ,.els_p(bedrock_reg_els_lp)
     ,.base_addr_p({putint_match_addr_gp, signature_match_addr_gp, paramrom_match_addr_gp, bootrom_match_addr_gp, finish_match_addr_gp, getchar_match_addr_gp, putchar_match_addr_gp, putch_core_match_addr_gp})
     )
   register
    (.*
     ,.r_v_o({putint_r_v_li, signature_r_v_li, paramrom_r_v_li, bootrom_r_v_li, finish_r_v_li, getchar_r_v_li, putchar_r_v_li, putch_core_r_v_li})
     ,.w_v_o({putint_w_v_li, signature_w_v_li, paramrom_w_v_li, bootrom_w_v_li, finish_w_v_li, getchar_w_v_li, putchar_w_v_li, putch_core_w_v_li})
     ,.addr_o(addr_lo)
     ,.size_o(size_lo)
     ,.data_o(data_lo)
     ,.data_i(data_li)
     );
  localparam byte_offset_width_lp = 3;
  localparam lg_num_core_lp = `BSG_SAFE_CLOG2(num_core_p);
  wire [lg_num_core_lp-1:0] addr_core_enc = addr_lo[byte_offset_width_lp+:lg_num_core_lp];

  `declare_bp_bedrock_if(paddr_width_p, lce_id_width_p, cce_id_width_p, did_width_p, lce_assoc_p);
  bp_bedrock_mem_fwd_header_s mem_fwd_header_li;
  assign mem_fwd_header_li = mem_fwd_header_i;
  wire [hio_width_p-1:0] hio_id = mem_fwd_header_li.addr[paddr_width_p-1-:hio_width_p];
  always_comb
    if (mem_fwd_v_i & (hio_id != '0))
      $display("[BSG-WARNING]: Accessing hio %0h. Sending loopback message!", hio_id);

  // for some reason, VCS doesn't like finish_w_v_li << addr_core_enc
  wire [num_core_p-1:0] finish_set = finish_w_v_li ? (1'b1 << addr_core_enc) : 1'b0;
  logic [num_core_p-1:0] finish_r;
  bsg_dff_reset_set_clear
   #(.width_p(num_core_p))
   finish_reg
    (.clk_i(clk_i)
     ,.reset_i(reset_i)
     ,.set_i(finish_set)
     ,.clear_i('0)
     ,.data_o(finish_r)
     );

  integer ret;
  logic [7:0] ch;
  always_ff @(negedge clk_i)
    begin
      if (putchar_w_v_li) begin
        $write("%c", data_lo[0+:8]);
        $fwrite(stdout_global, "%c", data_lo[0+:8]);
      end

      if (putch_core_w_v_li) begin
        $write("%c", data_lo[0+:8]);
        $fwrite(stdout[addr_core_enc], "%c", data_lo[0+:8]);
      end

      if (putint_w_v_li) begin
        $write("%x", data_lo[0+:dword_width_gp]);
      end

      if (getchar_r_v_li) begin
          ch <= getchar();
      end

      if (mem_fwd_ready_and_o & mem_fwd_v_i & (hio_id != '0))
        $error("Warning: Accesing illegal hio %0h. Sending loopback message!", hio_id);
      for (integer i = 0; i < num_core_p; i++)
        begin
          // PASS when returned value in finish packet is zero
          if (finish_set[i] & (data_lo[0+:8] == 8'(0)))
            $display("[BSG-INFO]: CORE%0x FINISH PASS", i);
          // FAIL when returned value in finish packet is non-zero
          if (finish_set[i] & (data_lo[0+:8] != 8'(0)))
            begin
              $display("[BSG-FAIL]: CORE%0x FINISH FAIL", i);
              $finish();
            end
            
        end

      if (signature_w_v_li)
        $fwrite(signature, "%8x\n", data_lo[0+:32]);

      if (putint_w_v_li) begin
        $write("%x", data_lo);
      end

      if (&finish_r)
        begin
          $display("[BSG-PASS]: All cores finished! Terminating...");
          $finish();
        end
    end

  final
    begin
      $fclose(signature);
      $fclose(stdout_global);
      for (integer j = 0; j < num_core_p; j++)
        $fclose(stdout[j]);
      $system("stty echo");
    end

  localparam param_els_lp = `BSG_CDIV($bits(proc_param_lp),word_width_gp);
  localparam lg_param_els_lp = `BSG_SAFE_CLOG2(param_els_lp);
  logic [lg_param_els_lp-1:0] paramrom_addr_li;
  logic [word_width_gp-1:0] paramrom_data_lo;
  // Reverse address to index in reverse struct order
  assign paramrom_addr_li = param_els_lp-1'b1-addr_lo[2+:lg_param_els_lp];
  bsg_rom_param
   #(.data_p(proc_param_lp)
     ,.data_width_p($bits(proc_param_lp))
     ,.width_p(word_width_gp)
     ,.els_p(param_els_lp)
     )
   param_rom
    (.addr_i(paramrom_addr_li)
     ,.data_o(paramrom_data_lo)
     );
  wire [bedrock_block_width_p-1:0] paramrom_final_lo = {bedrock_block_width_p/word_width_gp{paramrom_data_lo}};

  assign data_li[0] = '0;
  assign data_li[1] = '0;
  assign data_li[2] = ch;
  assign data_li[3] = finish_r;
  assign data_li[4] = '0;
  assign data_li[5] = paramrom_final_lo;

endmodule

