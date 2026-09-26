// ============================================================================
// argus_check.svh -- reusable self-checking testbench helpers
//
// Include this in a testbench, declare `integer errors = 0;`, then use:
//   `CHECK(cond, "message")            -- fail if cond is false
//   `CHECK_EQ(got, exp, "message")     -- fail if got != exp, prints both
//   `FINISH_REPORT                     -- prints TEST PASSED / TEST FAILED
//
// The pass/fail markers are what the Makefile greps for.
// ============================================================================
`ifndef ARGUS_CHECK_SVH
`define ARGUS_CHECK_SVH

`define CHECK(cond, msg) \
    if (!(cond)) begin \
        $display("  FAIL: %s (t=%0t)", msg, $time); \
        errors = errors + 1; \
    end

`define CHECK_EQ(got, exp, msg) \
    if ((got) !== (exp)) begin \
        $display("  FAIL: %s : got=%0d exp=%0d (t=%0t)", msg, (got), (exp), $time); \
        errors = errors + 1; \
    end

`define FINISH_REPORT \
    if (errors == 0) $display("TEST PASSED"); \
    else             $display("TEST FAILED (%0d errors)", errors); \
    $finish;

`endif
