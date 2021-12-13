

VASM = vasm -Ftos -devpac
LZ4 = lz4.exe

all: ankha_in.prg

ankha_in.prg: ankham.s small
	$(VASM) -o ANKHA_IN.PRG ankham.s
	copy ANKHA_IN.PRG Q:\DEV\ANKHAI\ANKHA_IN.PRG

clean:
	del ankha_in.prg

	