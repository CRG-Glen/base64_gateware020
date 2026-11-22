Base64 TG68: 22x EXPERIMENT, PLLs fed from the Amiga's 7 MHz clock
(branch exp-22x, build.py --pll7m). Not a release.

The same design as exp_22x (12x / 16x / 20x / 22x, speed 1.5), with one
difference: both of the FPGA's PLLs take the Amiga's own 7.09 MHz clock
as their input (x80 for 16x and 20x, x88 for 22x) instead of the board's
85.1 MHz 12x clock. 12x itself is still the board's clock. The PLL's
rated minimum input is 8 MHz, so 7.09 MHz is just below it: this build
answers whether that works on your board, and whether the speeds behave
any differently fed this way.

Timing: seed 12, 12x passes (+1.41 ns); the FPGA has to be this much
faster than its worst-case model:
  16x 1.16x   20x 1.45x   22x 1.60x
(better than exp_22x's seed: that is placement luck, not the clock input.)

Please test as exp_22x (its README has the order). Compare the two if
you can: does either lock or run better at 16x, 20x or 22x; does
"speed" report the 7 MHz sample differently. Its "rising-edge sample has
moved" line at 16x / 20x / 22x is the unused sample and harmless, as
before.

Files: base64_tg68_full_7m_plain.bit / _fast.bit, timing_full*.txt (12x,
16x, 20x, 22x), seeds.txt (all 16 seeds), speed (1.5).
