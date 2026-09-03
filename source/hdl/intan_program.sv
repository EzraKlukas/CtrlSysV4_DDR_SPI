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

    localparam INTAN_MASK = config_pkg::INTAN_MASK;

    function automatic logic [15:0] init_command(input int index);
        begin
            unique case (index)
                // Two startup reads flush the chip's unknown power-up state.
                0, 1: init_command = 16'hFF00;

                // Configure RAM registers 0 through 21 before calibration.
                2:  init_command = 16'h80DE;
                3:  init_command = 16'h8142;
                4:  init_command = 16'h8204;
                5:  init_command = 16'h8300;
                6:  init_command = 16'h8480;
                7:  init_command = 16'h8540;
                8:  init_command = 16'h8680;
                9:  init_command = 16'h8700;
                10: init_command = 16'h8816;
                11: init_command = 16'h8980;
                12: init_command = 16'h8A17;
                13: init_command = 16'h8B80;
                14: init_command = 16'h8C2C;
                15: init_command = 16'h8D86;
                16: init_command = 16'h8EFF;
                17: init_command = 16'h8FFF;
                18: init_command = 16'h90FF;
                19: init_command = 16'h91FF;
                20: init_command = 16'h92FF;
                21: init_command = 16'h93FF;
                22: init_command = 16'h94FF;
                23: init_command = 16'h95FF;

                // CALIBRATE must be followed by nine clock-generating dummy
                // commands.  The chip ignores those nine commands.
                24: init_command = 16'h5500;
                25, 26, 27, 28, 29, 30, 31, 32, 33: init_command = 16'hFF00;
                default: init_command = 16'h0000;
            endcase
        end
    endfunction

    function automatic logic [15:0] init_response(input int index);
        begin
            unique case (index)
                0, 1: init_response = 16'h0004;
                2: init_response = 16'hFFDE;
                3: init_response = 16'hFF42;
                4: init_response = 16'hFF04;
                5: init_response = 16'hFF00;
                6: init_response = 16'hFF80;
                7: init_response = 16'hFF40;
                8: init_response = 16'hFF80;
                9: init_response = 16'hFF00;
                10: init_response = 16'hFF16;
                11: init_response = 16'hFF80;
                12: init_response = 16'hFF17;
                13: init_response = 16'hFF80;
                14: init_response = 16'hFF2C;
                15: init_response = 16'hFF86;
                16, 17, 18, 19, 20, 21, 22, 23: init_response = 16'hFFFF;

                // Register 4 is configured as 0x80, so two's-complement mode
                // is disabled and calibration status has only its MSB set.
                // This is also the response produced during the nine ignored
                // dummy commands following CALIBRATE.
                24, 25, 26, 27, 28, 29, 30, 31, 32, 33: init_response = 16'h8000;
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
                expect_rx_ans_list_a[command_idx][sensor_idx] = INTAN_MASK[sensor_idx] ? 
                    BITS_PER_WORD'(init_response(command_idx)) : '0;
                expect_rx_ans_list_b[command_idx][sensor_idx] = INTAN_MASK[sensor_idx] ?
                    BITS_PER_WORD'(init_response(command_idx)) : '0;
            end
        end
    end

endmodule
