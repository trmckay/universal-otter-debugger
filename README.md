# universal-otter-debugger

## About ##
This is an extension of another project of mine, a [debugger for RISC-V RV32I over USB UART](https://github.com/trmckay/riscv-uart-debugger/tree/dev). It is a module that translates generic debugger requests into specific signals for various architecures of Cal Poly's RISC-V implementation.

## Features ##
- Read/write registers
- Read/write memory
- Program the Otter without resynthesizing
- Breakpoints
- Pause/resume execution
- Configurable variables for commonly used values
- Communicates over the same microUSB used to program the board

```
 h                   : view this message
 p                   : pause execution
 r                   : resume execution
 pr <mem.bin>        : program with the specified binary file
 rst                 : reset execution
 st                  : request MCU status
 b <pc>              : add a breakpoint to the specified program counter
 d <num>             : delete the specified breakpoint
 bl                  : list breakpoints
 rr <num>            : read the data at the register
 rw <num> <data>     : write the data to the register
 mww <addr> <data>   : write a word (4 bytes) to the memory
 mrb <addr>          : read a byte from the memory
 mwb <addr> >data>   : write a byte to the memory
 ```

## Getting the files ##
Make sure to do a recursive clone, the client and most of the SystemVerilog code are in the submodules.

```
git clone --recursive https://github.com/trmckay/universal-otter-debugger.git
```

To compile all the SystemVerilog code into one file, ```otter_debugger_(version).sv```:
```
make module
```

## Installing the client ##

### From releases ###
Download the latest release, and keep the binary somewhere you can find it.

### Building from source (recommended) ###

You will need gcc, GNU make, glib, and readline.

For example, in Ubuntu:

```
sudo apt install gcc make libreadline-dev libglib2.0-dev
```

Next, install the client:
```
cd uart-db/client
make
sudo make install
```

Alternatively, there is a binary included in the releases.

## Implementing the module ##
Implementing the module for your Otter is very simple, as it uses standard Otter signals. In general, internal MCU signals should be used when ```db_active``` is low and debugger signals when it is high.

More detailed instructions are included the [documentation](doc/multicycle_instructions.pdf).

### Multicycle Otter ###

![mc_diagram](https://raw.githubusercontent.com/trmckay/universal-otter-debugger/master/doc/tex/figures/blackbox.png)

### Pipelined Otter ###
Instructions coming soon, see module.

## Client usage ##
Launch the tool with:
```
uart-db <device>
```
Or to autodetect ports, omit the device.

Your device is likely connected to ```/dev/ttyUSBX``` or ```/dev/ttySX```.
Once in the tool, type 'h' for more information.

You can add variables to ```~/.config/uart-db/config``` where the name comes first, followed by a space, then the value. Each name-value pair is separated by a newline. Values can be hex or decimal formatted. Example:
```
MY_DATA_ADDR 0x110C0000
A_GOOD_NUMBER 12
```
The file will be sourced when the program starts up.
