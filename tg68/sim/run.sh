#!/bin/sh
# Run the test benches (Linux, needs verilator >= 5 and m68k binutils:
#   apt install verilator binutils-m68k-linux-gnu).
#   sim/run.sh bus       adapter + kernel on a model 68000 bus
#   sim/run.sh top       whole top level on a model motherboard
#   sim/run.sh fastmem   whole top level with fast RAM + SDRAM model
#   sim/run.sh bench copy|read|scatter   fast RAM throughput
#   sim/run.sh bench c|coff              compiled C from fast RAM (caches on|off)
#   sim/run.sh bench op                  clocks and kernel steps per instruction
# BENCH_ASD="--defsym SPEED18=1" sim/run.sh bench copy|read|scatter|c   at 20x (SPEED16 too: 16x)
#   (exp-22x: --defsym SPEED18=1 --defsym SPEED22=1: at 22x)
#   sim/run.sh bench sd                  SD controller, SPI loopback
#   sim/run.sh isa      step 26a: every instruction against isa_ref.hex (the
#                       v2.1 core's results); ISA_REF=1 writes the reference
#                       (on the v2.1 core: CORE=tg68_020_v21 VLFLAGS=-DISA_V21),
#                       ISA_ARGS="--n 5 --seed 2" passes gen_isa.py options
# CORE=tg68_020_b0_nobf_smul sim/run.sh bus   tests another core variant
# PERF=0 sim/run.sh ...      without the step 18 performance counters (the
#                            normal build); default PERF=1, as build.py --perf
set -e
cd "$(dirname "$0")"
R=../rtl
CORE=${CORE:-tg68_020_b1}   # step 19: the barrel shifter core (CORE=tg68_020_b0: the bit-by-bit one)
AS="m68k-linux-gnu-as -m68020"; LD="m68k-linux-gnu-ld -Ttext=0"; OC="m68k-linux-gnu-objcopy -O binary"
mem() { python3 -I -c "
d=open('$1','rb').read(); d+=bytes(8192-len(d))
open('$2','w').write('\n'.join('%02x%02x'%(d[i],d[i+1]) for i in range(0,8192,2))+'\n')"; }
VL="verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style -O2 --top-module tb $VLFLAGS"
PSRC=; PASD=
if [ "${PERF:-1}" = 1 ]; then VL="$VL -DTG68_PERF"; PSRC=$R/base64_tg68/perf_cnt.v; PASD="--defsym PERF=1"; fi
SLAVES="$R/base64_fx68k/autoconfig_zii.v $R/base64_fx68k/fastmem_zii.v $R/base64_fx68k/turbomem_zii.v \
 $R/base64_fx68k/sd_subsystem.v $R/base64_fx68k/sdcard.v $R/base64_fx68k/sdram_ctrl.v $R/base64_fx68k/fifo.v \
 $R/base64_fx68k/shifter.v $R/base64_fx68k/rx_cpu_buf.v $R/base64_fx68k/tx_cpu_buf.v"
cp $R/base64_fx68k/turbomem.mem $R/base64_fx68k/sfsd.mem .
case "${1:-bus}" in
bus)
  $AS -o t.o test020.s && $LD -o t.elf t.o 2>/dev/null && $OC t.elf t.bin && mem t.bin rom.mem
  $VL tb_tg68_bus.sv $R/base64_tg68/tg68_bus.v $R/tg68/$CORE.v -o tb_bus > build_bus.log 2>&1
  ./obj_dir/tb_bus ;;
isa)
  python3 -I gen_isa.py ${ISA_ARGS}
  rm -f isa.bin isa_out.hex isa_steps.txt
  { $AS -o isa.o isa_test.s && $LD -o isa.elf isa.o 2>/dev/null && $OC isa.elf isa.bin; } || { echo "FAIL: isa_test.s does not assemble"; exit 1; }
  python3 -I -c "
d=open('isa.bin','rb').read(); d+=bytes(len(d)%2)
open('isa.mem','w').write('\n'.join('%02x%02x'%(d[i],d[i+1]) for i in range(0,len(d),2))+'\n')"
  $VL tb_isa.sv $R/base64_tg68/tg68_bus.v $R/tg68/$CORE.v -o tb_isa > build_isa.log 2>&1
  ./obj_dir/tb_isa
  if [ "${ISA_REF:-0}" = 1 ]; then cp isa_out.hex isa_ref.hex; cp isa_steps.txt isa_ref_steps.txt; echo "wrote isa_ref.hex (core $CORE)"
  else python3 -I isa_cmp.py; fi ;;
top)
  $AS -o tt.o test_top.s && $LD -o tt.elf tt.o 2>/dev/null && $OC tt.elf tt.bin && mem tt.bin rom_top.mem
  $VL tb_top.sv $R/base64_tg68/base64_tg68_top.sv $R/base64_tg68/clkgen.v $R/base64_tg68/tg68_bus.v $R/tg68/$CORE.v $SLAVES $PSRC -o tb_top > build_top.log 2>&1
  ./obj_dir/tb_top ;;
fastmem)
  $AS --defsym FASTMEM=1 $PASD -o tf.o test_top.s && $LD -o tf.elf tf.o 2>/dev/null && $OC tf.elf tf.bin && mem tf.bin rom_top_fm.mem
  $VL -DFASTMEM tb_top.sv sdram_model_checked.v $R/base64_tg68/base64_tg68_top.sv $R/base64_tg68/clkgen.v $R/base64_tg68/tg68_bus.v $R/tg68/$CORE.v $SLAVES $PSRC -o tb_fm > build_fm.log 2>&1
  ./obj_dir/tb_fm ;;
bench)
  # run.sh bench [copy|read|scatter]: fast RAM throughput, timed 2nd pass
  case "${2:-copy}" in
    copy) SRC=test_mem.s; D=-DBENCH_COPY ;; read) SRC=test_rd.s; D= ;; scatter) SRC=test_rnd.s; D= ;;
    sd) SRC=test_sd.s; D=-DSDTEST ;;
    # the read loop with the caches off: every instruction fetch and data
    # read goes to the SDRAM (step 10: instruction prefetch)
    readoff) SRC=test_rd.s; D=; ASD="--defsym NOCACHE=1" ;;
    # a loop in chip RAM writing chip RAM (step 11: chip code cache, posted writes)
    chip) SRC=test_chip.s; D=-DBENCH_CHIP ;;
    # write bursts (step 12: Chip RAM write buffer, fast RAM write queue)
    wrchip) SRC=test_wr.s; D=-DBENCH_WRCHIP ;;
    wrfast) SRC=test_wr.s; D=-DBENCH_WRFAST; ASD="--defsym FAST=1" ;;
    wrmix) SRC=test_wr.s; D=-DBENCH_WRCHIP; ASD="--defsym MIX=1" ;;
    # compiled C (step 15): bench_c.c, built with gcc -O2 -m68020 (needs
    # gcc-m68k-linux-gnu), run from fast RAM with its stack there
    # what single instructions cost (clocks and kernel steps), from fast
    # RAM with the caches on: gen_op.py writes the program and the table
    op) python3 -I gen_op.py asm; SRC=test_op.s; D= ;;
    c|coff) SRC=test_c.s; D=-DBENCH_C; [ "$2" = coff ] && ASD="--defsym NOCACHE=1"
       m68k-linux-gnu-gcc -m68020 -O2 -fomit-frame-pointer -ffreestanding -fno-builtin -fno-pic -fno-pie \
         -fno-tree-loop-distribute-patterns -fno-asynchronous-unwind-tables -c -o bc.o bench_c.c
       m68k-linux-gnu-ld -T bench_c.ld -o bc.elf bc.o 2>/dev/null && m68k-linux-gnu-objcopy -O binary bc.elf cimg.bin ;;
  esac
  $AS $ASD $BENCH_ASD -o tm.o $SRC && $LD -o tm.elf tm.o 2>/dev/null && $OC tm.elf tm.bin && mem tm.bin rom_mem.mem
  $VL -DFASTMEM -DMEMBENCH $D tb_top.sv sdram_model_checked.v $R/base64_tg68/base64_tg68_top.sv $R/base64_tg68/clkgen.v $R/base64_tg68/tg68_bus.v $R/tg68/$CORE.v $SLAVES $PSRC -o tb_bench > build_bench.log 2>&1
  if [ "$2" = op ]; then ./obj_dir/tb_bench > op.log; grep -v "^OPMARK\|^per cycle\|^AS->DTACK\|^1 KB" op.log; python3 -I gen_op.py report < op.log
  else ./obj_dir/tb_bench | grep -v "^per cycle\|^AS->DTACK"; fi ;;
esac
