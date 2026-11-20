# Makefile para compilar plugins PS4 GoldHEN
# Uso: make (compila tudo) | make clean | make psn_bypass.prx

CC = clang
CFLAGS = -target x86_64-pc-freebsd12-ps4 -fPIC -shared -O2 -nostdlib -ffreestanding
INCLUDES = -I$(PS4SDK)/include
LIBS = -L$(PS4SDK)/lib
LDFLAGS = -nostdlib -ffreestanding

# Arquivos fonte
SRCS = psn_bypass.c gta5_online_bypass.c
PRXS = psn_bypass.prx gta5_online_bypass.prx

all: $(PRXS)

psn_bypass.prx: psn_bypass.c
	$(CC) $(CFLAGS) $(INCLUDES) $(LIBS) -o $@ $<

gta5_online_bypass.prx: gta5_online_bypass.c
	$(CC) $(CFLAGS) $(INCLUDES) $(LIBS) -o $@ $<

clean:
	rm -f $(PRXS)

.PHONY: all clean