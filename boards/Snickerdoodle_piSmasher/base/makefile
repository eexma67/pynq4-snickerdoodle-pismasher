# PYNQ base overlay for snickerdoodle black + piSmasher 4.1.
#
# The block design and constraints are krtkl's, downloaded from
# github.com/krtkl/piSmasher-testing at a pinned commit (not redistributed here).

KRTKL_URL := https://raw.githubusercontent.com/krtkl/piSmasher-testing/a33972af7e26959b170dbe8dce213a1e4280a9a3/piSmasher_4.1

all: base.bit

src/krtkl_hdmi_pass_through_2018.2.tcl:
	curl -fsSL -o $@ $(KRTKL_URL)/hdmi-pass-through/hdmi-pass-through.srcs/sources_1/bd/base/hw_handoff/base_bd.tcl
	echo "59abb136b00284ea7c943f7030c9634a  $@" | md5sum -c -

src/piSmasher_4.1.xdc:
	curl -fsSL -o $@ $(KRTKL_URL)/constraints.xdc
	echo "9e2de2cadf06e30068e5374c9afed14e  $@" | md5sum -c -

src/base_bd.tcl: src/convert_bd.py src/krtkl_hdmi_pass_through_2018.2.tcl
	python3 -I src/convert_bd.py src/krtkl_hdmi_pass_through_2018.2.tcl $@

base.bit: build_base.tcl src/base_bd.tcl src/piSmasher_4.1.xdc
	vivado -mode batch -source build_base.tcl -notrace

clean:
	rm -rf build base.bit base.hwh base.xsa *.jou *.log .Xil

distclean: clean
	rm -f src/base_bd.tcl src/krtkl_hdmi_pass_through_2018.2.tcl src/piSmasher_4.1.xdc
