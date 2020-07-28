
//  integer file, r;
//  reg [80*8:1] command;
//  reg [31:0] data1;
//  reg [31:0] data2;
//
//    file = $fopen("dma_transaction_for_queue_notify.txt","r");
//    if (file == 0)
//    begin
//        $display("Failed to open dma_transaction_for_queue_notify playback file!");
//    end
//    
//    while (!$feof(file))
//    begin
//        r = $fscanf(file, " %s %h %h\n", command, data1, data2);
//        case (command)
//        "rd":
//        begin
//            debug_trace_rd(data1+32'h`PCIE_BAR_MAP, data2);
//            $display("dma_rd mem[%8h] = %8h", data1, data2);
//        end
//        "wr":
//        begin
//            debug_trace_wr(data1+32'h`PCIE_BAR_MAP,data2);
//            $display("dma_wr mem[%8h] = %8h", data1+32'h`PCIE_BAR_MAP, data2);
//        end
//        default:
//            $display("Trace Playback Unknown command '%0s'", command);
//        endcase
//    end
//
//    $fclose(file);

  reg [63   :0] data1;
  reg [256-1:0] data2;

  `define CSR_PATH test_top.DUT.shell_region_i.FIM.FIU.feature_ram.virtio_csr_0.inst
  
  reg [15:0] virt_queue_num = 0;
  reg [15:0] virt_queue_sel = 0;
  reg [63:0] virt_queue_phy = 0;
  reg [15:0] curr_avail_idx[3];
  reg [15:0] next_avail_idx[3];
  reg [15:0] num_avail_entry;
  reg [15:0] desc_idx = 0;
  reg [16*8-1:0] desc_entry = 0;
  reg [63:0] desc_entry_phy = 0;
  reg [31:0] desc_entry_len = 0;
  reg [15:0] desc_entry_flg = 0;
  reg [15:0] desc_entry_nxt = 0;
  reg [31:0] desc_chain_len= 0;

  reg queue_notify_set[3];
  reg queue_notify_clr[3];
  reg [2:0] queue_notify_pending;

  // reset
  always begin
    @(posedge `CSR_PATH.csr_drv_ok);
    curr_avail_idx[0] = 0;
    curr_avail_idx[1] = 0;
    curr_avail_idx[2] = 0;
    next_avail_idx[0] = 0;
    next_avail_idx[1] = 0;
    next_avail_idx[2] = 0;
  end

  // make a record of pending notification
  always @(posedge `CSR_PATH.clk) begin
    for (int i = 0; i < 3; i++) begin
      if (queue_notify_set[i])
        queue_notify_pending[i] = 1'b1;
      else if (queue_notify_clr[i])
        queue_notify_pending[i] = 1'b0;
      else if (`CSR_PATH.csr_rst)
        queue_notify_pending[i] = 1'b0;
    end 
  end

  // handling notification
  always begin
    @(posedge `CSR_PATH.csr_access_10B2);
    if (`CSR_PATH.csr_drv_ok) begin

      repeat(2) @(posedge `CSR_PATH.clk);
      virt_queue_num = `CSR_PATH.csr_reg_10B2;

      queue_notify_set[virt_queue_num] = 1;
      @(posedge `CSR_PATH.clk);
      queue_notify_set[virt_queue_num] = 0;

    end  
  end

  // process notified virtqueue
  always begin
    @(posedge `CSR_PATH.clk);
    if (queue_notify_pending != 3'b000) begin

      virt_queue_sel = queue_notify_pending[0]? 0:
                      (queue_notify_pending[1]? 1:
                      (queue_notify_pending[2]? 2:
                                                0));
      // get Virtqueue physical address
      virt_queue_phy = {20'h00000, `CSR_PATH.csr_reg_08B4[virt_queue_sel][31:0], 12'h000};
  
      queue_notify_clr[virt_queue_sel] = 1;
      @(posedge `CSR_PATH.clk);
      queue_notify_clr[virt_queue_sel] = 0;


      // read available ring flags+index(tail), 2B+2B
      data1 = virt_queue_phy+(0+16*256)+0;
      debug_trace_rd(data1, data2);                                                   $display("1");
      next_avail_idx[virt_queue_sel]  = data2[31:16]; 
      num_avail_entry = (next_avail_idx[virt_queue_sel] > curr_avail_idx[virt_queue_sel])?
                        (next_avail_idx[virt_queue_sel] - curr_avail_idx[virt_queue_sel]):
                  (256 + next_avail_idx[virt_queue_sel] - curr_avail_idx[virt_queue_sel]);
      
      for (int i = 0; i < num_avail_entry; i++) begin
        // read available ring entry, num*2B
        data1 = virt_queue_phy+(0+16*256)+4+(curr_avail_idx[virt_queue_sel]+i)*2;     // TODO: readback alignment
        debug_trace_rd(data1, data2);                                                 $display("2, %d", i);
        desc_idx = data2[15:0];
      
        // read the whole decriptor chain, following the NEXT flag+next
        desc_entry_flg = 16'h1; 
        desc_entry_nxt = desc_idx;
	desc_chain_len = 0;
        while (desc_entry_flg[0]) begin
          // read descriptor, num*chain_entry*16B
          data1 = virt_queue_phy+(0)+desc_entry_nxt*16;
          debug_trace_rd(data1, data2);                                               $display("3, %d, %d", i, desc_entry_nxt);
          //2.4.5 The Virtqueue Descriptor Table
          desc_entry = (desc_entry_nxt[0] == 0)? data2[127:0]: data2[255:128];
	  desc_entry_phy = desc_entry[ 63:  0];
	  desc_entry_len = desc_entry[ 95: 64];
          desc_entry_flg = desc_entry[111: 96];
          desc_entry_nxt = desc_entry[127:112];
	  desc_chain_len = desc_chain_len + desc_entry_len;
	  // TODO: read/write buffer
        end
      
        // write used ring entry, len+id, num*8B
        data1 = virt_queue_phy+(0+16*256+1*4096)+4+(curr_avail_idx[virt_queue_sel]+i)*8;  // TODO: write data alignment, overwrite
        data2 = {64'd0, 64'd0, 64'd0, {desc_chain_len, {16'd0, desc_idx}}};
        debug_trace_wr(data1, data2);                                                 $display("4, %d", i);
      end
      
      // write used ring flags+index(), 2B+2B
      data1 = virt_queue_phy+(0+16*256+1*4096)+0;                                         // TODO: write data alignment, overwrite
      data2 = {64'd0, 64'd0, 64'd0, {32'd0, {next_avail_idx[virt_queue_sel], 16'd0}}};
      debug_trace_wr(data1, data2);                                                   $display("5");


      // update current available index
      curr_avail_idx[virt_queue_sel]  = next_avail_idx[virt_queue_sel];
     

      //// read used ring flags+index(tail)
      //    debug_trace_rd(virt_queue_phy+(0+16*256+1*4096)+0, data2);
      //// read 8 used ring id, from 4(head)
      //for (int i = 0; i < 8* 8/4; i++) begin
      //    debug_trace_rd(virt_queue_phy+(1*16*256+1*4096)+4+i*4, data2);
      //end

    end
  end


