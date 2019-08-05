----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 04/05/2019 05:05:34 PM
-- Design Name: 
-- Module Name: sim_main - Behavioral
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
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
library UNISIM;
use UNISIM.VComponents.all;

entity main_sim is
end main_sim;

architecture Behavioral of main_sim is
    COMPONENT main
        Port (  LVDS_inA : in STD_LOGIC_VECTOR (2 downto 0);
            LVDS_inB : in STD_LOGIC_VECTOR (2 downto 0);
            LVDS_inC : in STD_LOGIC_VECTOR (2 downto 0);
            LVDS_inD : in STD_LOGIC_VECTOR (2 downto 0);
            LVDS_Ssync : in STD_LOGIC;      -- serializer sync
            LVDS_Vsync : in STD_LOGIC;      -- vertical sync - end of frame
            LVDS_Hsync : in STD_LOGIC;      -- horizontal sync - end of line
            LVDS_Pclk  : in STD_LOGIC;      -- pixel sync - next pixel
            clk_in     : in STD_LOGIC;      -- clock for running summer
            clk_uart     : in STD_LOGIC;      -- clock for running summer
            rst        : in STD_LOGIC;       -- resetting states
            tx         : out STD_LOGIC
            );
    END COMPONENT;
    constant SIZE_IN_BITS: integer := 10;   --2b is for 4x4 table, 3b is for 8x8 table                
    constant X_MAX: integer := 2**SIZE_IN_BITS;
    constant Y_MAX: integer := 2**SIZE_IN_BITS;

    type data_X is array(0 to X_MAX-1) of integer range 0 to 2147483647; -- have to be changed to double buffer for sending
    type data_Y is array(0 to Y_MAX-1) of integer range 0 to 2147483647;
    type double_data_X is array(0 to 2*(X_MAX)-1) of integer range 0 to 2147483647;
     --type state_modes is (INIT, GATHER_BIT, PIXEL_READY, CHANGE_LINE, FINISH_FRAME, DATA_READY);
    type state_modes is (INIT, GATHER_DATA, SUMMING, DATA_READY, CLEAR_MEM);
    type summer_states is (WAITING, LOWER_BUFFER, HIGHER_BUFFER);
    
    signal LVDS_inA : STD_LOGIC_VECTOR (2 downto 0) := "100";
    signal LVDS_inB : STD_LOGIC_VECTOR (2 downto 0) := "010";
    signal LVDS_inC : STD_LOGIC_VECTOR (2 downto 0) := "001";
    signal LVDS_inD : STD_LOGIC_VECTOR (2 downto 0) := "000";
    signal LVDS_Ssync : STD_LOGIC := '0';      -- serializer sync
    signal LVDS_Vsync : STD_LOGIC := '0';      -- vertical sync - end of frame
    signal LVDS_Hsync : STD_LOGIC := '0';      -- horizontal sync - end of line
    signal LVDS_Pclk  : STD_LOGIC := '0';      -- pixel sync - next pixel
    signal clk   : STD_LOGIC := '0';      -- clock for running summer
    signal clk_uart   : STD_LOGIC := '0';      -- clock for running summer
    signal rst        : STD_LOGIC := '0';       -- resetting states
    signal tx         : STD_LOGIC := '0';
    
    
    signal bit_count    : integer := 0;
    signal pixel_count  : integer := 0;
    signal line_count   : integer := 0;
    
begin
    uut: main port map(LVDS_inA, LVDS_inB, LVDS_inC, LVDS_inD, LVDS_Ssync, LVDS_Vsync, LVDS_Hsync, LVDS_Pclk, clk, clk_uart, rst, tx);  
    
    process
    begin
       LVDS_Ssync <= '0';
       wait for 25ns;
       LVDS_Ssync <= '1';
       wait for 25ns;
    end process;
    
    process
    begin
        wait until rising_edge(LVDS_Ssync);
        bit_count <= bit_count + 1;            
        if bit_count = 3 then
            LVDS_Pclk <= '1';
            bit_count <= 0;
        else            
            LVDS_Pclk <= '0';        
        end if; 
    end process;
    
    process
    begin
        wait until rising_edge(LVDS_Pclk);
        pixel_count <= pixel_count + 1;            
        if pixel_count = 255 then
            LVDS_Hsync <= '1';
            pixel_count <= 0;
        else            
            LVDS_Hsync <= '0';        
        end if;
    end process;
    
    process
    begin
        wait until rising_edge(LVDS_Hsync);
        line_count <= line_count + 1;            
        if line_count = 1023 then
            LVDS_Vsync <= '1';
            line_count <= 0;
        else            
            LVDS_Vsync <= '0';        
        end if;
    end process;
    
    process
    begin 
        clk <= '0';
        wait for 3ns;
        clk <= '1';
        wait for 3ns;
    end process;
    process
    begin 
        clk_uart <= '0';
        wait for 3ns;
        clk_uart <= '1';
        wait for 3ns;
    end process;
end Behavioral;
