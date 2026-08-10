`timescale 1ns / 1ps

module intan_program_tb;
    localparam int MAX_COMMANDS = 34;
    localparam int NUM_INTAN = config_pkg::NUM_INTAN;
    localparam int BITS_PER_WORD = config_pkg::INTAN_BITS_PER_WORD;

    logic [6:0] init_list_len;
    logic [MAX_COMMANDS-1:0][BITS_PER_WORD-1:0] init_cmd_list;
    logic [MAX_COMMANDS-1:0][NUM_INTAN-1:0][BITS_PER_WORD-1:0] expect_a;
    logic [MAX_COMMANDS-1:0][NUM_INTAN-1:0][BITS_PER_WORD-1:0] expect_b;
    logic [6:0] acq_list_len;
    logic [MAX_COMMANDS-1:0][BITS_PER_WORD-1:0] acq_cmd_list;

    intan_program #(
        .MAX_COMMANDS(MAX_COMMANDS),
        .NUM_INTAN(NUM_INTAN),
        .BITS_PER_WORD(BITS_PER_WORD)
    ) dut (
        .init_list_len(init_list_len),
        .init_cmd_list(init_cmd_list),
        .expect_rx_ans_list_a(expect_a),
        .expect_rx_ans_list_b(expect_b),
        .acq_list_len(acq_list_len),
        .acq_cmd_list(acq_cmd_list)
    );

    function automatic logic [15:0] expected_init_cmd(input int index);
        unique case (index)
            0: expected_init_cmd = 16'hFF00;
            1: expected_init_cmd = 16'hFF00;
            2: expected_init_cmd = 16'hFF00;
            3: expected_init_cmd = 16'hFF00;
            4: expected_init_cmd = 16'hFF00;
            5: expected_init_cmd = 16'hFF00;
            6: expected_init_cmd = 16'hFF00;
            7: expected_init_cmd = 16'hFF00;
            8: expected_init_cmd = 16'hFF00;
            9: expected_init_cmd = 16'h5500;
            10: expected_init_cmd = 16'h95FF;
            11: expected_init_cmd = 16'h94FF;
            12: expected_init_cmd = 16'h93FF;
            13: expected_init_cmd = 16'h92FF;
            14: expected_init_cmd = 16'h91FF;
            15: expected_init_cmd = 16'h90FF;
            16: expected_init_cmd = 16'h8FFF;
            17: expected_init_cmd = 16'h8EFF;
            18: expected_init_cmd = 16'h8D86;
            19: expected_init_cmd = 16'h8C2C;
            20: expected_init_cmd = 16'h8B80;
            21: expected_init_cmd = 16'h8A17;
            22: expected_init_cmd = 16'h8980;
            23: expected_init_cmd = 16'h8816;
            24: expected_init_cmd = 16'h8700;
            25: expected_init_cmd = 16'h8680;
            26: expected_init_cmd = 16'h8540;
            27: expected_init_cmd = 16'h8480;
            28: expected_init_cmd = 16'h8300;
            29: expected_init_cmd = 16'h8204;
            30: expected_init_cmd = 16'h8142;
            31: expected_init_cmd = 16'h80DE;
            32: expected_init_cmd = 16'hFF00;
            33: expected_init_cmd = 16'hFF00;
            default: expected_init_cmd = 16'h0000;
        endcase
    endfunction

    function automatic logic [15:0] expected_init_resp(input int index);
        unique case (index)
            0: expected_init_resp = 16'h0004;
            1: expected_init_resp = 16'h0004;
            2: expected_init_resp = 16'h0004;
            3: expected_init_resp = 16'h0004;
            4: expected_init_resp = 16'h0004;
            5: expected_init_resp = 16'h0004;
            6: expected_init_resp = 16'h0004;
            7: expected_init_resp = 16'h0004;
            8: expected_init_resp = 16'h0004;
            9: expected_init_resp = 16'h0000;
            10: expected_init_resp = 16'hFFFF;
            11: expected_init_resp = 16'hFFFF;
            12: expected_init_resp = 16'hFFFF;
            13: expected_init_resp = 16'hFFFF;
            14: expected_init_resp = 16'hFFFF;
            15: expected_init_resp = 16'hFFFF;
            16: expected_init_resp = 16'hFFFF;
            17: expected_init_resp = 16'hFFFF;
            18: expected_init_resp = 16'hFF86;
            19: expected_init_resp = 16'hFF2C;
            20: expected_init_resp = 16'hFF80;
            21: expected_init_resp = 16'hFF17;
            22: expected_init_resp = 16'hFF80;
            23: expected_init_resp = 16'hFF16;
            24: expected_init_resp = 16'hFF00;
            25: expected_init_resp = 16'hFF80;
            26: expected_init_resp = 16'hFF40;
            27: expected_init_resp = 16'hFF80;
            28: expected_init_resp = 16'hFF00;
            29: expected_init_resp = 16'hFF04;
            30: expected_init_resp = 16'hFF42;
            31: expected_init_resp = 16'hFFDE;
            32: expected_init_resp = 16'h0004;
            33: expected_init_resp = 16'h0004;
            default: expected_init_resp = 16'h0000;
        endcase
    endfunction

    function automatic logic [15:0] expected_acq_cmd(input int index);
        unique case (index)
            0: expected_acq_cmd = 16'h0000;
            1: expected_acq_cmd = 16'h0100;
            2: expected_acq_cmd = 16'h0200;
            3: expected_acq_cmd = 16'h0300;
            4: expected_acq_cmd = 16'h0400;
            5: expected_acq_cmd = 16'h0500;
            6: expected_acq_cmd = 16'h0600;
            7: expected_acq_cmd = 16'h0700;
            8: expected_acq_cmd = 16'h0800;
            9: expected_acq_cmd = 16'h0900;
            10: expected_acq_cmd = 16'h0A00;
            11: expected_acq_cmd = 16'h0B00;
            12: expected_acq_cmd = 16'h0C00;
            13: expected_acq_cmd = 16'h0D00;
            14: expected_acq_cmd = 16'h0E00;
            15: expected_acq_cmd = 16'h0F00;
            16: expected_acq_cmd = 16'h1000;
            17: expected_acq_cmd = 16'h1100;
            18: expected_acq_cmd = 16'h1200;
            19: expected_acq_cmd = 16'h1300;
            20: expected_acq_cmd = 16'h1400;
            21: expected_acq_cmd = 16'h1500;
            22: expected_acq_cmd = 16'h1600;
            23: expected_acq_cmd = 16'h1700;
            24: expected_acq_cmd = 16'h1800;
            25: expected_acq_cmd = 16'h1900;
            26: expected_acq_cmd = 16'h1A00;
            27: expected_acq_cmd = 16'h1B00;
            28: expected_acq_cmd = 16'h1C00;
            29: expected_acq_cmd = 16'h1D00;
            30: expected_acq_cmd = 16'h1E00;
            31: expected_acq_cmd = 16'h1F00;
            default: expected_acq_cmd = 16'h0000;
        endcase
    endfunction

    initial begin
        #1;

        if (init_list_len !== 7'd34) $fatal(1, "bad init_list_len: %0d", init_list_len);
        if (acq_list_len !== 7'd32) $fatal(1, "bad acq_list_len: %0d", acq_list_len);

        for (int index = 0; index < MAX_COMMANDS; index = index + 1) begin
            if (init_cmd_list[index] !== expected_init_cmd(index))
                $fatal(1, "init command %0d got 0x%04h expected 0x%04h",
                       index, init_cmd_list[index], expected_init_cmd(index));
            if (acq_cmd_list[index] !== expected_acq_cmd(index))
                $fatal(1, "acq command %0d got 0x%04h expected 0x%04h",
                       index, acq_cmd_list[index], expected_acq_cmd(index));

            for (int sensor = 0; sensor < NUM_INTAN; sensor = sensor + 1) begin
                if (expect_a[index][sensor] !== expected_init_resp(index))
                    $fatal(1, "A response command %0d sensor %0d got 0x%04h expected 0x%04h",
                           index, sensor, expect_a[index][sensor], expected_init_resp(index));
                if (expect_b[index][sensor] !== expected_init_resp(index))
                    $fatal(1, "B response command %0d sensor %0d got 0x%04h expected 0x%04h",
                           index, sensor, expect_b[index][sensor], expected_init_resp(index));
            end
        end

        $display("PASS intan_program_tb");
        $finish;
    end
endmodule
