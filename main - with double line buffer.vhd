----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 03/08/2019 06:14:42 PM
-- Design Name: 
-- Module Name: main - Behavioral
-- Project Name: 
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
    Port (  LVDS_inA : in STD_LOGIC_VECTOR (2 downto 0);
            LVDS_inB : in STD_LOGIC_VECTOR (2 downto 0);
            LVDS_inC : in STD_LOGIC_VECTOR (2 downto 0);
            LVDS_inD : in STD_LOGIC_VECTOR (2 downto 0);
            LVDS_Ssync : in STD_LOGIC;      -- serializer sync
            LVDS_Vsync : in STD_LOGIC;      -- vertical sync - end of frame
            LVDS_Hsync : in STD_LOGIC;      -- horizontal sync - end of line
            LVDS_Pclk  : in STD_LOGIC;      -- pixel sync - next pixel
            clk_summ   : in STD_LOGIC;      -- clock for running summer
            rst        : in STD_LOGIC       -- resetting states
            );
            
    constant SIZE_IN_BITS: integer := 10;   --2b is for 4x4 table, 3b is for 8x8 table                
    constant X_MAX: integer := 2**SIZE_IN_BITS;
    constant Y_MAX: integer := 2**SIZE_IN_BITS;
    constant BUFFER_MAX: integer := X_MAX / 2; -- end of the double index buffer, when twicely read from 4 segments

    type data_X is array(0 to X_MAX-1) of integer range 0 to 2147483647; -- have to be changed to double buffer for sending
    type data_Y is array(0 to Y_MAX-1) of integer range 0 to 2147483647;
    type double_data_X is array(0 to 2*(X_MAX)-1) of integer range 0 to 2147483647;
     --type state_modes is (INIT, GATHER_BIT, PIXEL_READY, CHANGE_LINE, FINISH_FRAME, DATA_READY);
    type state_modes is (INIT, GATHER_DATA, SUMMING, DATA_READY, CLEAR_MEM);
    type summer_states is (WAITING, LOWER_BUFFER, HIGHER_BUFFER);
end main;

architecture Behavioral of main is
    signal index_Y : integer := 0;

    -- signal temp1: std_logic_vector(7 downto 0);
    -- signal to_be_divided: std_logic_vector(15 downto 0);
    signal double_line_buffer: double_data_X;
    signal run_summer: std_logic := '0';       -- flag for running summing process 
    signal tempA, tempB, tempC, tempD: STD_LOGIC_VECTOR (23 downto 0); -- can be changed to double buffer when changed to processes
    signal pixel_buffer_part: std_logic;    -- which part of pixel buffer is written
    signal index_buffer: integer := 0 ;     -- index in buffer, will roll when exceed buffer size - when we have reading from 4 segments

begin    

    reading : process(rst)
    begin
--        if rst = '1' then
--            --index_Y <= 0;
            
--            index_buffer <= 0;               
--        end if;
    end process;
    
    readPixelValue : process(LVDS_Ssync)
        variable index_bit : integer := 0;    -- index of read bit, will roll every 8 ticks
        
    begin
        if rising_edge(LVDS_Ssync) then -- next bit to read, for 12 but pixel values
            tempA(index_bit) <= LVDS_inA(0);
            tempA(index_bit+4) <= LVDS_inA(1);
            tempA(index_bit+8) <= LVDS_inA(2);
            tempB(index_bit) <= LVDS_inB(0);
            tempB(index_bit+4) <= LVDS_inB(1);
            tempB(index_bit+8) <= LVDS_inB(2);
            tempC(index_bit) <= LVDS_inC(0);
            tempC(index_bit+4) <= LVDS_inC(1);
            tempC(index_bit+8) <= LVDS_inC(2);
            tempD(index_bit) <= LVDS_inD(0);
            tempD(index_bit+4) <= LVDS_inD(1);
            tempD(index_bit+8) <= LVDS_inD(2);
            index_bit := index_bit + 1;
            if index_bit = 4 then 
                pixel_buffer_part <= '0'; -- lower parts of temps buffers are ready
            elsif index_bit = 8 then
                index_bit := 0;
                pixel_buffer_part <= '1'; -- higher parts of temps buffers are ready
            end if;
        end if;
    end process;
    
    writeToBuffer: process(LVDS_Pclk)
    
    begin
        if rising_edge(LVDS_Pclk) then     -- pixel change - write data to buffer
            if pixel_buffer_part = '0' then
                double_line_buffer(index_buffer) <= to_integer(unsigned(tempA(11 downto 0)));
                double_line_buffer(index_buffer+256) <= to_integer(unsigned(tempB(11 downto 0)));
                double_line_buffer(index_buffer+512) <= to_integer(unsigned(tempC(11 downto 0)));
                double_line_buffer(index_buffer+768) <= to_integer(unsigned(tempD(11 downto 0)));            
            else
                double_line_buffer(index_buffer) <= to_integer(unsigned(tempA(23 downto 12)));
                double_line_buffer(index_buffer+256) <= to_integer(unsigned(tempB(23 downto 12)));
                double_line_buffer(index_buffer+512) <= to_integer(unsigned(tempC(23 downto 12)));
                double_line_buffer(index_buffer+768) <= to_integer(unsigned(tempD(23 downto 12)));
            end if;
            index_buffer <= index_buffer + 1; -- will roll when exceed             
            if index_buffer = BUFFER_MAX then
                index_buffer <= 0;
            end if;
        end if;
    end process;
    
--    changeFrame : process(LVDS_Vsync)
--    begin
--        if rising_edge(LVDS_Vsync) then     -- frame change 
--            index_Y <= 0;       
--        end if;
--    end process;
    
    changeLine : process(LVDS_Hsync, LVDS_Vsync)
    begin
        if rising_edge(LVDS_Hsync) then     -- line change                 
            run_summer <= '1';
            index_Y <= index_Y + 1;         -- increase Y ind
        end if;
        if rising_edge(LVDS_Vsync) then     -- frame change 
            index_Y <= 0;       
        end if;
    end process;
    
    summmer : process(run_summer, clk_summ)     -- not sure how to make it safer 
        variable state: summer_states;
        variable index: integer range 0 to 1023;    -- index of x axis
        variable arr_x: data_X;
        variable arr_y: data_Y;
    begin
        case (state) is
            when WAITING =>
                index := 0;
                if rising_edge(run_summer) then
                    if index_buffer < 255 then 
                        state := HIGHER_BUFFER; --buffer from 1024 to 2047   
                    else                
                        state := LOWER_BUFFER; -- buffer from 0 to 1023
                    end if;
                end if;
            when LOWER_BUFFER=>
                arr_x(index) := arr_x(index) + double_line_buffer(index);   -- add to x axis summs
                arr_y(index_Y) := arr_y(index_Y) + double_line_buffer(index);   -- add to y axis summs
                index := index + 1;     -- increase x index of actual position in buffer
                if index = 0 then
                    state := WAITING;
                end if;
            when HIGHER_BUFFER =>
                arr_x(index) := arr_x(index) + double_line_buffer(index + X_MAX);   -- add to x axis summs
                arr_y(index_Y) := arr_y(index_Y) + double_line_buffer(index + X_MAX);   -- add to y axis summs
                index := index + 1;     -- increase x index of actual position in buffer
                if index = 0 then
                    state := WAITING;
                end if;
        end case;
    end process;
      
end Behavioral;
-- zrobiæ to forem, procesem, który jest clockowany, a mo¿e procedur¹ w osobnym procesie