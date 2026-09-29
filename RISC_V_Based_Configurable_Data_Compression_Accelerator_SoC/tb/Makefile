# =============================================================================
# Makefile — VCS build and run for tb_axi_interconnect_wrap_2x7
#
# Run from:  <repo>/tb/
#
#   make          — compile + simulate (produces dump.fsdb)
#   make compile  — compile only
#   make sim      — simulate only (requires prior compile)
#   make waves    — open dump.fsdb in Verdi
#   make clean    — remove all generated artefacts
#   make help     — show copy-pasteable one-liners
#
# Prerequisites
#   • VCS   U-2023.03        at /home/student/snps_tools_target/vcs/U-2023.03
#   • Verdi U-2023.03-SP1    at /home/student/snps_tools_target/verdi/U-2023.03-SP1
#   Both paths are taken from the existing csrc/Makefile in this repo.
# =============================================================================

# ---------- tool homes (matched to existing csrc/Makefile) ------------------
VCS_HOME    := /home/student/snps_tools_target/vcs/U-2023.03
VERDI_HOME  := /home/student/snps_tools_target/verdi/U-2023.03-SP1

VCS         := $(VCS_HOME)/bin/vcs
VERDI       := $(VERDI_HOME)/bin/verdi

# ---------- FSDB PLI — exact paths from repo's csrc/Makefile SYSLIBS -------
# SYSLIBS in csrc/Makefile contains:
#   /home/student/snps_tools_target/verdi/U-2023.03-SP1/share/PLI/VCS/LINUX64/pli.a
NOVAS_TAB   := $(VERDI_HOME)/share/PLI/VCS/LINUX64/novas.tab
NOVAS_PLI   := $(VERDI_HOME)/share/PLI/VCS/LINUX64/pli.a

# ---------- filelist and output ---------------------------------------------
FILELIST    := run.f
SIMV        := simv
TOP         := tb_axi_interconnect_wrap_2x7
FSDB        := dump.fsdb

# ---------- VCS compile flags -----------------------------------------------
# -full64            64-bit binary (matches prior builds in this repo)
# -sverilog          enable SystemVerilog (for .sv TB/stub files)
# +v2k               Verilog-2001 compatibility for RTL .v files
# -timescale         fallback global timescale
# -kdb               Verdi KDB database for post-sim debug
# -debug_access+all  full signal accessibility (required for $fsdbDumpvars)
# -P novas.tab       register FSDB PLI tasks ($fsdbDumpfile etc.)
# pli.a              FSDB PLI static library (same as SYSLIBS in csrc/Makefile)
VCS_FLAGS   := \
    -full64 \
    -sverilog \
    +v2k \
    -timescale=1ns/1ps \
    -kdb \
    -debug_access+all \
    -P $(NOVAS_TAB) $(NOVAS_PLI) \
    -top $(TOP) \
    -l compile.log

# ---------- simulation flags ------------------------------------------------
SIM_FLAGS   := -l sim.log

# =============================================================================
.PHONY: all compile sim waves clean help

all: compile sim

# ---------- compile ----------------------------------------------------------
compile: $(SIMV)

$(SIMV): run.f $(wildcard ../rtl/*.v) $(wildcard ./*.sv)
	@echo ""
	@echo "=== COMPILE ==="
	@echo "$(VCS) -full64 -sverilog +v2k -timescale=1ns/1ps -kdb -debug_access+all \\"
	@echo "    -P $(NOVAS_TAB) \\"
	@echo "    $(NOVAS_PLI) \\"
	@echo "    -f $(FILELIST) -o $(SIMV)"
	@echo ""
	$(VCS) $(VCS_FLAGS) -f $(FILELIST) -o $(SIMV)
	@echo "=== Compile done — binary: $(SIMV) ==="

# ---------- simulate ---------------------------------------------------------
sim: $(SIMV)
	@echo ""
	@echo "=== SIMULATE ==="
	@echo "./$(SIMV) $(SIM_FLAGS)"
	@echo ""
	./$(SIMV) $(SIM_FLAGS)
	@echo ""
	@echo "=== Simulation done — waveform: $(FSDB) ==="
	@echo ""
	@echo "--- Tail of sim.log ---"
	@tail -25 sim.log
	@echo ""
	@echo "To view waveforms:"
	@echo "  verdi -ssf $(FSDB) &"

# ---------- open waveforms ---------------------------------------------------
waves:
	@echo "$(VERDI) -ssf $(FSDB) &"
	$(VERDI) -ssf $(FSDB) &

# ---------- clean ------------------------------------------------------------
clean:
	rm -rf $(SIMV) $(SIMV).daidir csrc \
	       compile.log sim.log ucli.key \
	       $(FSDB) *.fsdb.* \
	       novas_dump.log AN.DB vc_hdrs.h \
	       inter.vpd

# ---------- help / copy-pasteable one-liners --------------------------------
help:
	@echo ""
	@echo "========================================================"
	@echo " Copy-pasteable commands"
	@echo "========================================================"
	@echo ""
	@echo "1. Compile:"
	@echo ""
	@echo "   $(VCS) \\"
	@echo "       -full64 -sverilog +v2k -timescale=1ns/1ps \\"
	@echo "       -kdb -debug_access+all \\"
	@echo "       -P $(NOVAS_TAB) \\"
	@echo "       $(NOVAS_PLI) \\"
	@echo "       -f run.f -o simv"
	@echo ""
	@echo "2. Run simulation:"
	@echo ""
	@echo "   ./simv"
	@echo ""
	@echo "3. View waveforms in Verdi:"
	@echo ""
	@echo "   verdi -ssf dump.fsdb"
	@echo ""
	@echo "========================================================"
