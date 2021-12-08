

VASM = vasm -Ftos -devpac
LZ4 = lz4.exe

all: ankha.tos

ankha.tos: ankham.s small
	$(VASM) -o ankham.tos ankham.s

clean:
	del ankham.tos

	