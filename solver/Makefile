# SRC и BUILD переопределяются на ВМ, где исходник лежит рядом с Makefile.
CC     := mpicc
CFLAGS ?= -O3 -std=c11 -fopenmp -Wall -Wextra
SRC    ?= src/slae_solver.c
BUILD  ?= build

$(BUILD)/slae_solver: $(SRC)
	mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -o $@ $< -lm

.PHONY: clean
clean:
	rm -f $(BUILD)/slae_solver
