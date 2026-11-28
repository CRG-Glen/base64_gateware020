Base64 TG68: STEP 26b DIAGNOSIS BUILD, fast branches behind a switch
(branch step26b-branch). Not a release.

The step26b_branch build did not boot on Glen's A500+ (black screen, red
LED: a bus cycle that nothing answered). The simulator cannot reproduce
it. This build has the same fast-branch logic, but OFF at power-on, with
a switch in the speed command (1.6, in this folder):

  speed BRANCH ON      fast branches on
  speed BRANCH OFF     off again (as v2.1)
  speed                (the usual report; BRANCH ON/OFF prints the state)

Please:
 1. Boot it, switch untouched (OFF). Does it boot and run as v2.1
    (Workbench, a quick SysInfo)?
      - No: the new logic breaks the build itself, not the branches.
 2. If it boots: in a Shell, "speed BRANCH ON". Then:
      - does the machine freeze at once, or keep running?
      - if it runs: SysInfo, Frontier CPU timedemo, a game; note what
        works and what freezes, and the LED colour if it hangs.
 3. Try ON at 12x first, then 20x / 22x.

The switch stays over a warm reset; a power cycle sets it OFF again.

Timing: seed 4 of 32 (11 pass, SDRAM pins included), 12x +1.65 ns;
16x 1.13x, 20x 1.42x, 22x 1.56x the worst-case model (v2.1: 1.21 / 1.51 /
1.66). SDRAM data pins 4.27 / 1.60 ns.
