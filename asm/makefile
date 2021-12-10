

VASM = vasm -Ftos -devpac
LZ4 = lz4.exe

all: ankha_in.prg

ankha_in.prg: ankham.s small
	$(VASM) -o ankha_in.tos ankham.s

clean:
	del ankha_in.prg

	