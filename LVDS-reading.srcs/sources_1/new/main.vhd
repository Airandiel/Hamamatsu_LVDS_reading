----------------------------------------------------------------------------------
-- Company: 
-- Engineer: Micha³ Porêbski
-- 
-- Create Date: 03/08/2019 06:14:42 PM
-- Design Name: 
-- Module Name: main - Behavioral
-- Project Name: Beam localizer
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity main is
    Port (  LVDS_inA    : in STD_LOGIC_VECTOR (2 downto 0);
            LVDS_inB    : in STD_LOGIC_VECTOR (2 downto 0);
            LVDS_inC    : in STD_LOGIC_VECTOR (2 downto 0);
            LVDS_inD    : in STD_LOGIC_VECTOR (2 downto 0);
            LVDS_Ssync  : in STD_LOGIC;      -- serializer sync
            LVDS_Vsync  : in STD_LOGIC;      -- vertical sync - end of frame
            LVDS_Hsync  : in STD_LOGIC;      -- horizontal sync - end of line
            LVDS_Pclk   : in STD_LOGIC;      -- pixel sync - next pixel
            clk_in      : in STD_LOGIC;      -- clock for running summer
            clk_uart      : in STD_LOGIC;      -- clock for running summer
            rst         : in STD_LOGIC;       -- resetting states
            tx          : out STD_LOGIC         --transmitt pin
            );
            
    constant SIZE_IN_BITS: integer  := 10;   --2b is for 4x4 table, 3b is for 8x8 table                
    constant X_MAX: integer         := 2**SIZE_IN_BITS;
    constant Y_MAX: integer         := 2**SIZE_IN_BITS;
    constant BUFFER_MAX: integer    := X_MAX / 2; -- end of the double index buffer, when twicely read from 4 segments
    constant half_period: time      := 1.5ns;

    type data_X is array(0 to X_MAX-1) of integer range 0 to 2147483647; -- have to be changed to double buffer for sending
    type data_Y is array(0 to Y_MAX-1) of integer range 0 to 2147483647;
    type double_data_X is array(0 to 2*(X_MAX)-1) of integer range 0 to 2147483647;
    type double_data_Y is array(0 to 2*(Y_MAX)-1) of integer range 0 to 2147483647;
    type uart_states is (WAITING, SENDING_AXIS_X, SENDING_AXIS_Y);
end main;

architecture Behavioral of main is
    signal index_Y : integer    := 0;

    signal run_summer: std_logic    := '0';       -- flag for running summing process 
    signal tempA, tempB, tempC, tempD: STD_LOGIC_VECTOR (23 downto 0); -- can be changed to double buffer when changed to processes
    signal pixel_buffer_part: std_logic;    -- which part of pixel buffer is written
    signal arr_x: double_data_X;                   -- stores summs of X axis
    signal arr_y: double_data_Y;                   -- stores summs of Y axis
    signal data_x_buffer_offset: integer    := 0;    --offset for double buffer X
    signal data_y_buffer_offset: integer    := 0;    --offset for double buffer Y
    signal send_x_offset: integer   := 0;             --offset for sending data X
    signal send_y_offset: integer   := 0;             --offset for sending data Y
    
    component uart is
        GENERIC(
        clk_freq	:	INTEGER		:= 50_000_000;	--frequency of system clock in Hertz
		baud_rate	:	INTEGER		:= 19_200;		--data link baud rate in bits/second
		os_rate		:	INTEGER		:= 16;			--oversampling rate to find center of receive bits (in samples per baud period)
		d_width		:	INTEGER		:= 32; 			--data bus width
		parity		:	INTEGER		:= 0;				--0 for no parity, 1 for parity
		parity_eo	:	STD_LOGIC	:= '0');			--'0' for even, '1' for odd parity
		
        PORT(
            clk		:	IN    STD_LOGIC;					          --system clock
            reset_n	:	IN    STD_LOGIC;							  --ascynchronous reset
            tx_ena	:	IN    STD_LOGIC;                              --initiate transmission
            tx_data	:	IN    STD_LOGIC_VECTOR(d_width-1 DOWNTO 0);   --data to transmit
            tx_busy	:	OUT   STD_LOGIC;                              --transmission in progress
            tx		:	OUT	  STD_LOGIC;	                          --transmit pin
            rx		:	IN	  STD_LOGIC;										--receive pin
		    rx_busy	:	OUT	STD_LOGIC;										--data reception in progress
		    rx_error:	OUT	STD_LOGIC;										--start, parity, or stop bit error detected
		    rx_data	:	OUT	STD_LOGIC_VECTOR(d_width-1 DOWNTO 0)	--data received);
		    );
    end component;
    
    constant clk_freq   : integer  := 50_000_000; 
    constant baud_rate  : integer  := 19_200; 
    constant os_rate    : integer  := 16; 
    constant d_width    : integer  := 32; 
    constant parity     : integer  := 0; 
    constant parity_eo  : std_logic  := '0'; 
    
    signal reset_n  : std_logic;
    signal tx_ena   : std_logic;
    signal tx_data  : STD_LOGIC_VECTOR(d_width-1 DOWNTO 0);
    signal tx_busy  : std_logic;
    
    signal rx		: STD_LOGIC := '0';										--receive pin
	signal rx_busy	: STD_LOGIC := '0';										--data reception in progress
    signal rx_error : STD_LOGIC := '0';										--start, parity, or stop bit error detected
	signal rx_data	: STD_LOGIC_VECTOR(d_width-1 DOWNTO 0);	--data received);
    
    signal run_uart : std_logic := '0';             --flag for running uart sending
    
    
begin    
    uart_com: uart 
    generic map(clk_freq, baud_rate, os_rate, d_width, parity, parity_eo)
    port map(
        clk => clk_uart,
        reset_n => reset_n,
        tx_ena => tx_ena,
        tx_data => tx_data,
        tx_busy => tx_busy,
        tx => tx,
        rx => rx,
        rx_busy => rx_busy,
        rx_error => rx_error,
        rx_data => rx_data);

    
    readPixelValue : process(LVDS_Ssync)
        variable index_bit : integer := 0;    -- index of read bit, will roll every 8 ticks
        variable which_half : integer := 0;
    begin
        if rising_edge(LVDS_Ssync) then -- next bit to read, for 12 bit pixel values
            tempA(which_half+index_bit) <= LVDS_inA(0);
            tempA(which_half+index_bit+4) <= LVDS_inA(1);
            tempA(which_half+index_bit+8) <= LVDS_inA(2);
            tempB(which_half+index_bit) <= LVDS_inB(0);
            tempB(which_half+index_bit+4) <= LVDS_inB(1);
            tempB(which_half+index_bit+8) <= LVDS_inB(2);
            tempC(which_half+index_bit) <= LVDS_inC(0);
            tempC(which_half+index_bit+4) <= LVDS_inC(1);
            tempC(which_half+index_bit+8) <= LVDS_inC(2);
            tempD(which_half+index_bit) <= LVDS_inD(0);
            tempD(which_half+index_bit+4) <= LVDS_inD(1);
            tempD(which_half+index_bit+8) <= LVDS_inD(2);
            index_bit := index_bit + 1;
            if index_bit = 4 and which_half = 0 then    -- if approaching the end of pixel and right half of pixel buffer
                which_half := 12;
                index_bit := 0;
                pixel_buffer_part <= '0'; -- lower parts of temps buffers are ready
            elsif index_bit = 4 and which_half = 12 then
                index_bit := 0;
                which_half := 0;
                pixel_buffer_part <= '1'; -- higher parts of temps buffers are ready
            end if;
        end if;
    end process;
    
    
    writeToBuffer: process(LVDS_Pclk, LVDS_Hsync)    
        variable index_X : integer := 0;    -- index in summing buffer
    
    begin
        if rising_edge(LVDS_Pclk) then     -- pixel change - write data to buffer
            if pixel_buffer_part = '0' then
                arr_x(data_x_buffer_offset+index_X) <= arr_x(data_x_buffer_offset+index_X) + to_integer(unsigned(tempA(11 downto 0)));   -- add to x axis summs
                arr_x(data_x_buffer_offset+index_X+256) <= arr_x(data_x_buffer_offset+index_X+256) + to_integer(unsigned(tempB(11 downto 0)));
                arr_x(data_x_buffer_offset+index_X+512) <= arr_x(data_x_buffer_offset+index_X+512) + to_integer(unsigned(tempC(11 downto 0)));
                arr_x(data_x_buffer_offset+index_X+768) <= arr_x(data_x_buffer_offset+index_X+768) + to_integer(unsigned(tempD(11 downto 0)));
                arr_y(data_y_buffer_offset+index_Y) <= arr_y(data_y_buffer_offset+index_Y) + (to_integer(unsigned(tempA(11 downto 0))) + 
                     to_integer(unsigned(tempB(11 downto 0))) + 
                     to_integer(unsigned(tempC(11 downto 0))) + 
                     to_integer(unsigned(tempD(11 downto 0))));   -- add to y axis summs                    
            else
                arr_x(data_x_buffer_offset+index_X) <= arr_x(data_x_buffer_offset+index_X) + to_integer(unsigned(tempA(23 downto 12)));   -- add to x axis summs
                arr_x(data_x_buffer_offset+index_X+256) <= arr_x(data_x_buffer_offset+index_X+256) + to_integer(unsigned(tempB(23 downto 12)));
                arr_x(data_x_buffer_offset+index_X+512) <= arr_x(data_x_buffer_offset+index_X+512) + to_integer(unsigned(tempC(23 downto 12)));
                arr_x(data_x_buffer_offset+index_X+768) <= arr_x(data_x_buffer_offset+index_X+768) + to_integer(unsigned(tempD(23 downto 12)));
                arr_y(data_y_buffer_offset+index_Y) <= arr_y(data_y_buffer_offset+index_Y) + (to_integer(unsigned(tempA(23 downto 12))) + 
                     to_integer(unsigned(tempB(23 downto 12))) + 
                     to_integer(unsigned(tempC(23 downto 12))) + 
                     to_integer(unsigned(tempD(23 downto 12))));   -- add to y axis summs
            end if;
            index_X := index_X + 1; -- increase x index of actual position in buffer
            if index_X > 255 then   -- control and reset when reaching the end of buffer
                index_X := 0;
            end if;    
        end if;
        if rising_edge(LVDS_Hsync) then -- just for certainty reset index of X axis when synchronisation signal appear
            index_X := 0;
        end if;
    end process;
    
    
    changeLine : process(LVDS_Hsync, LVDS_Vsync)
    begin
        if rising_edge(LVDS_Hsync) then     -- line change  
            index_Y <= index_Y + 1;         -- increase Y ind
        end if;
        if rising_edge(LVDS_Vsync) then     -- frame change, send to uart
            index_Y <= 0;       
            if data_y_buffer_offset = 0 then    -- select right part of buffer
                data_y_buffer_offset <= Y_MAX;
                data_x_buffer_offset <= X_MAX;
            else 
                data_y_buffer_offset <= 0;
                data_x_buffer_offset <= 0;
            end if;
            run_uart <= not run_uart;       -- turn on sending to UART
        end if;
    end process;
    
    sendUART : process(clk_in, run_uart) 
        variable index_in_buffer : integer := 0;
        variable buffer_part_X : integer := 0;
        variable buffer_part_Y : integer := 0;
        variable state: uart_states := WAITING;
        variable old_run_uart: std_logic := '0';
    begin
        case (state) is
            when WAITING =>
                if run_uart /= old_run_uart then
                    if data_x_buffer_offset = 0 then  
                        buffer_part_X := X_MAX;      
                        buffer_part_Y := Y_MAX;      
                    else 
                        buffer_part_X := 0;      
                        buffer_part_Y := 0;   
                    end if;
                    state := SENDING_AXIS_X;
                else
                    buffer_part_X := buffer_part_X;      
                    buffer_part_Y := buffer_part_Y;  
                    state := state;                    
                end if;
            when SENDING_AXIS_X =>
                if tx_busy = '0' then
                    tx_data <= std_logic_vector(to_unsigned(arr_x(buffer_part_X), tx_data'length));
                    tx_ena  <= '1';
                    buffer_part_X := buffer_part_X + 1;
                    if buffer_part_X = X_MAX or buffer_part_X = 2*X_MAX then                     
                        tx_ena  <= '0';
                        state := SENDING_AXIS_Y;   
                    end if;
                else               
                    tx_ena  <= '0'; -- when busy turn of enable
                end if;
            when SENDING_AXIS_Y =>
                if tx_busy = '0' then
                    tx_data <= std_logic_vector(to_unsigned(arr_y(buffer_part_Y), tx_data'length));
                    tx_ena  <= '1';
                    buffer_part_Y := buffer_part_Y + 1;
                    if buffer_part_Y = Y_MAX or buffer_part_Y = 2*Y_MAX then
                        tx_ena  <= '0'; -- when busy turn of enable
                        state := WAITING;
                    end if;
                else               
                    tx_ena  <= '0'; -- when busy turn of enable
                end if;
        end case;
        old_run_uart := run_uart;
    end process;
    
      
end Behavioral;