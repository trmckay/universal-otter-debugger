# universal-otter-debugger
Implementation of the RISC-V UART Debugger for Cal Poly's Otter MCU

### Install the client ###

The best way is to build and install from source:

```
git clone --recursive git@github.com:trmckay/riscv-uart-debugger.git
cd riscv-uart-debugger/client
./INSTALL
```

### Usage ###
Launch the tool with:
```
uart-db <device>
```
Or to autodetect ports, omit the device.

Your device is likely connected to /dev/ttyUSBX or /dev/ttySX.
Once in the tool, type 'h' or 'help' for more information.

### Implementing module ###
See releases for detailed instructions.
