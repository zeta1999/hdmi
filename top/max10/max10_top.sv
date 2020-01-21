module max10_top (
    input wire CLK_50MHZ,
    input wire CLK_32KHZ,
    input wire RST,

    output wire CLK_50MHZ_ENABLE,
    output wire CLK_32KHZ_ENABLE,
    output wire [7:0] LED,

    output wire [2:0] tmds_p,
    output wire tmds_clock_p,
    output wire [2:0] tmds_n,
    output wire tmds_clock_n
);
assign CLK_50MHZ_ENABLE = 1'b1;
assign CLK_32KHZ_ENABLE = 1'b0;

wire clk_tmds;
wire clk_pixel;
wire clk_audio;
pll pll(.inclk0(CLK_50MHZ), .c0(clk_tmds), .c1(clk_pixel), .c2(clk_audio));

localparam AUDIO_BIT_WIDTH = 16;
logic [AUDIO_BIT_WIDTH-1:0] audio_in;
logic [AUDIO_BIT_WIDTH-1:0] audio_out;
sawtooth #(.BIT_WIDTH(AUDIO_BIT_WIDTH)) sawtooth (.clk_audio(clk_audio), .level(audio_in));

logic audio_clock_regeneration_sent = 1'b0;
logic audio_info_frame_sent = 1'b0;

logic [6:0] remaining = 1;
logic packet_enable;
logic [7:0] packet_type = 0;
buffer #(.CHANNELS(1), .BIT_WIDTH(AUDIO_BIT_WIDTH), .BUFFER_SIZE(128)) buffer (.clk_audio(clk_audio), .clk_pixel(clk_pixel), .packet_enable(packet_enable && remaining > 0 && audio_clock_regeneration_sent && audio_info_frame_sent), .audio_in('{audio_in}), .audio_out('{audio_out}), .remaining(remaining));


logic [23:0] rgb;
logic [AUDIO_BIT_WIDTH-1:0] audio_buffer;
wire [9:0] cx, cy;
hdmi #(.VIDEO_ID_CODE(3), .AUDIO_RATE(4'b0010), .AUDIO_BIT_WIDTH(AUDIO_BIT_WIDTH)) hdmi(.clk_tmds(clk_tmds), .clk_pixel(clk_pixel), .rgb(rgb), .audio_sample_word('{audio_buffer, audio_buffer}), .packet_type(packet_type), .tmds_p(tmds_p), .tmds_clock_p(tmds_clock_p), .tmds_n(tmds_n), .tmds_clock_n(tmds_clock_n), .cx(cx), .cy(cy), .packet_enable(packet_enable));

always @(posedge clk_pixel)
begin
    if (cx == 0 && cy == 0) // RESET
    begin
        audio_clock_regeneration_sent <= 1'b0;
        audio_info_frame_sent <= 1'b0;
    end
    if (packet_enable)
    begin
        if (!audio_clock_regeneration_sent)
        begin
            packet_type <= 8'd1;
            audio_clock_regeneration_sent <= 1'b1;
        end
        else if (!audio_info_frame_sent)
        begin
            packet_type <= 8'h84;
            audio_info_frame_sent <= 1'b1;
        end
        else if (remaining > 0)
        begin
            packet_type <= 8'd2;
            audio_buffer <= audio_out;
        end
        else
            packet_type <= 8'd0;
    end
end

// Overscan / border test (left = red, top = green, right = blue, bottom = blue, fill = black)
// always @(posedge clk_pixel)
    // rgb <= {cx == 138 ? ~8'd0 : 8'd0, cy == 45 ? ~8'd0 : 8'd0, cx == 857 || cy == 524 ? ~8'd0 : 8'd0};

logic [7:0] character = 8'h30;
logic [5:0] prevcy = 6'd0;
always @(posedge clk_pixel)
begin
    if (cy == 10'd0)
    begin
        character <= 8'h30;
        prevcy <= 6'd0;
    end
    else if (prevcy != cy[9:4])
    begin
        character <= character + 8'h01;
        prevcy <= cy[9:4];
    end
end

console console(.clk_pixel(clk_pixel), .character(character), .attribute({cx[9], cy[8:6], cx[8:5]}), .cx(cx), .cy(cy), .rgb(rgb));
endmodule
