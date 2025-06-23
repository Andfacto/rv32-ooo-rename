module rename(
    input  logic        clk_i,
    input  logic        rst_ni,
    input  br_result_t  br_result_i,
    input  p_reg_t      p_commit_i,
    input  dinstr_t     dinstr_i,
    output rinstr_t     rinstr_o,
    output logic        rn_full_o
    );

    localparam int ARCH_REGS = 32;
    localparam int PHYS_REGS = 64;

    // State
    logic [5:0] arch2phys      [ARCH_REGS-1:0];
    logic [5:0] arch2phys_bkup [ARCH_REGS-1:0];
    logic       phys_ready     [PHYS_REGS-1:0];
    logic       phys_used      [PHYS_REGS-1:0];
    logic       branch_active;

    // Free physical register finder
    logic       found_free;
    logic [5:0] free_preg;

    always_comb begin
        found_free = 1'b0;
        free_preg  = 6'b0;
        for(int i = 1; i < PHYS_REGS; i++) begin
            if (!phys_used[i]) begin
                found_free = 1'b1;
                free_preg  = i[5:0];
                break;
            end
        end
    end

    //OUTPUT LOGIC
    always_comb begin
        rinstr_o = 0;

        rinstr_o.valid = dinstr_i.valid;

        //rs1
        if(dinstr_i.rs1.valid) begin
            rinstr_o.rs1.valid = 1'b1;
            rinstr_o.rs1.idx   = arch2phys[dinstr_i.rs1.idx];
            rinstr_o.rs1.ready = phys_ready[arch2phys[dinstr_i.rs1.idx]];
        end

        //rs2
        if(dinstr_i.rs2.valid) begin
            rinstr_o.rs2.valid = 1'b1;
            rinstr_o.rs2.idx   = arch2phys[dinstr_i.rs2.idx];
            rinstr_o.rs2.ready = phys_ready[arch2phys[dinstr_i.rs2.idx]];
        end

        //rd
        if(dinstr_i.rd.valid) begin
            rinstr_o.rd.valid = 1'b1;

            if(dinstr_i.rd.idx == 5'd0) begin
                rinstr_o.rd.idx   = 6'd0;
                rinstr_o.rd.ready = 1'b1;
            end else if (found_free) begin
                rinstr_o.rd.idx   = free_preg;
                rinstr_o.rd.ready = 1'b0;
            end else begin
                rinstr_o.rd.idx   = 6'd0;
                rinstr_o.rd.ready = 1'b0;
            end
        end
    end

    //STALL LOGIC
    always_comb begin
        rn_full_o = 1'b0;

        if(dinstr_i.valid) begin
            if(dinstr_i.is_branch && branch_active) begin
                rn_full_o = 1'b1;
            end else if(dinstr_i.rd.valid && dinstr_i.rd.idx != 5'd0 && !found_free) begin
                rn_full_o = 1'b1;
            end
        end
    end

    //SEQUENTIAL STATE UPDATE
    always_ff@(posedge clk_i) begin
        if(!rst_ni) begin
			for(int i = 0; i < ARCH_REGS; i++) begin
				arch2phys[i]      <= i[5:0];
				arch2phys_bkup[i] <= i[5:0];
			end
            for(int i = 0; i < PHYS_REGS; i++) begin
                phys_used[i]  <= (i < ARCH_REGS);
                phys_ready[i] <= 1'b1;
            end
            branch_active <= 1'b0;
        end else begin
            // Flush mapping if branch mispredicted
            if(br_result_i.valid && !br_result_i.hit) begin
                for (int i = 0; i < ARCH_REGS; i++) begin
                    arch2phys[i] <= arch2phys_bkup[i];
                end
                branch_active <= 1'b0;
            end

            //If branch correct clear flag
            if(br_result_i.valid && br_result_i.hit) begin
                branch_active <= 1'b0;
            end

            //Commit handling
            if(p_commit_i.valid) begin
                phys_ready[p_commit_i.idx] <= 1'b1;
                phys_used[p_commit_i.idx]  <= 1'b0;
            end

            //Rename update
            if(dinstr_i.valid && !rn_full_o) begin
                // Branch backup
                if(dinstr_i.is_branch) begin
                    for(int i = 0; i < ARCH_REGS; i++) begin
                        arch2phys_bkup[i] <= arch2phys[i];
                    end
                    branch_active <= 1'b1;
                end

                //Destination update
                if(dinstr_i.rd.valid && dinstr_i.rd.idx != 5'd0 && found_free) begin
                    arch2phys[dinstr_i.rd.idx] <= free_preg;
                    phys_used[free_preg]       <= 1'b1;
                    phys_ready[free_preg]      <= 1'b0;
                end
            end
        end
    end

endmodule

