`timescale 1ns / 1ps

module intan_program #(
    parameter int MAX_COMMANDS = 34,
    parameter int NUM_INTAN = config_pkg::NUM_INTAN,
    parameter int BITS_PER_WORD = config_pkg::INTAN_BITS_PER_WORD
) (
    output logic [6:0] init_list_len,
    output logic [MAX_COMMANDS-1:0][BITS_PER_WORD-1:0] init_cmd_list,
    output logic [MAX_COMMANDS-1:0][NUM_INTAN-1:0][BITS_PER_WORD-1:0] expect_rx_ans_list_a,
    output logic [MAX_COMMANDS-1:0][NUM_INTAN-1:0][BITS_PER_WORD-1:0] expect_rx_ans_list_b,

    output logic [6:0] acq_list_len,
    output logic [MAX_COMMANDS-1:0][BITS_PER_WORD-1:0] acq_cmd_list
);

    initial begin
        if (MAX_COMMANDS < 34) $error("intan_program requires MAX_COMMANDS >= 34");
        if (BITS_PER_WORD != 16) $error("intan_program requires 16-bit Intan words");
    end

    function automatic logic [15:0] init_command(input int index);
        begin
            unique case (index)
                0, 1, 2, 3, 4, 5, 6, 7, 8: init_command = 16'hFF00;
                9: init_command = 16'h5500;
                10: init_command = 16'h95FF;
                11: init_command = 16'h94FF;
                12: init_command = 16'h93FF;
                13: init_command = 16'h92FF;
                14: init_command = 16'h91FF;
                15: init_command = 16'h90FF;
                16: init_command = 16'h8FFF;
                17: init_command = 16'h8EFF;
                18: init_command = 16'h8D86;
                19: init_command = 16'h8C2C;
                20: init_command = 16'h8B80;
                21: init_command = 16'h8A17;
                22: init_command = 16'h8980;
                23: init_command = 16'h8816;
                24: init_command = 16'h8700;
                25: init_command = 16'h8680;
                26: init_command = 16'h8540;
                27: init_command = 16'h8480;
                28: init_command = 16'h8300;
                29: init_command = 16'h8204;
                30: init_command = 16'h8142;
                31: init_command = 16'h80DE;
                32, 33: init_command = 16'hFF00;
                default: init_command = 16'h0000;
            endcase
        end
    endfunction

    function automatic logic [15:0] init_response(input int index);
        begin
            unique case (index)
                0, 1, 2, 3, 4, 5, 6, 7, 8: init_response = 16'h0004;
                9: init_response = 16'h0000;
                10, 11, 12, 13, 14, 15, 16, 17: init_response = 16'hFFFF;
                18: init_response = 16'hFF86;
                19: init_response = 16'hFF2C;
                20: init_response = 16'hFF80;
                21: init_response = 16'hFF17;
                22: init_response = 16'hFF80;
                23: init_response = 16'hFF16;
                24: init_response = 16'hFF00;
                25: init_response = 16'hFF80;
                26: init_response = 16'hFF40;
                27: init_response = 16'hFF80;
                28: init_response = 16'hFF00;
                29: init_response = 16'hFF04;
                30: init_response = 16'hFF42;
                31: init_response = 16'hFFDE;
                32, 33: init_response = 16'h0004;
                default: init_response = 16'h0000;
            endcase
        end
    endfunction

    function automatic logic [15:0] acq_command(input int index);
        begin
            unique case (index)
                0: acq_command = 16'h0000;
                1: acq_command = 16'h0100;
                2: acq_command = 16'h0200;
                3: acq_command = 16'h0300;
                4: acq_command = 16'h0400;
                5: acq_command = 16'h0500;
                6: acq_command = 16'h0600;
                7: acq_command = 16'h0700;
                8: acq_command = 16'h0800;
                9: acq_command = 16'h0900;
                10: acq_command = 16'h0A00;
                11: acq_command = 16'h0B00;
                12: acq_command = 16'h0C00;
                13: acq_command = 16'h0D00;
                14: acq_command = 16'h0E00;
                15: acq_command = 16'h0F00;
                16: acq_command = 16'h1000;
                17: acq_command = 16'h1100;
                18: acq_command = 16'h1200;
                19: acq_command = 16'h1300;
                20: acq_command = 16'h1400;
                21: acq_command = 16'h1500;
                22: acq_command = 16'h1600;
                23: acq_command = 16'h1700;
                24: acq_command = 16'h1800;
                25: acq_command = 16'h1900;
                26: acq_command = 16'h1A00;
                27: acq_command = 16'h1B00;
                28: acq_command = 16'h1C00;
                29: acq_command = 16'h1D00;
                30: acq_command = 16'h1E00;
                31: acq_command = 16'h1F00;
                default: acq_command = 16'h0000;
            endcase
        end
    endfunction

    integer command_idx;
    integer sensor_idx;

    always_comb begin
        init_list_len = 7'd34;
        acq_list_len = 7'd32;
        init_cmd_list = '0;
        expect_rx_ans_list_a = '0;
        expect_rx_ans_list_b = '0;
        acq_cmd_list = '0;

        for (command_idx = 0; command_idx < MAX_COMMANDS; command_idx = command_idx + 1) begin
            init_cmd_list[command_idx] = BITS_PER_WORD'(init_command(command_idx));
            acq_cmd_list[command_idx]  = BITS_PER_WORD'(acq_command(command_idx));
            for (sensor_idx = 0; sensor_idx < NUM_INTAN; sensor_idx = sensor_idx + 1) begin
                expect_rx_ans_list_a[command_idx][sensor_idx] =
                    BITS_PER_WORD'(init_response(command_idx));
                expect_rx_ans_list_b[command_idx][sensor_idx] =
                    BITS_PER_WORD'(init_response(command_idx));
            end
        end
    end

endmodule
