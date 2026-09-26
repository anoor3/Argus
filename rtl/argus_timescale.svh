// Shared time unit/precision for all ARGUS modules.
// Included at the top of RTL and testbench files to silence mixed-timescale
// warnings and keep simulation timing consistent (1 ns unit, 1 ps precision).
`timescale 1ns/1ps
