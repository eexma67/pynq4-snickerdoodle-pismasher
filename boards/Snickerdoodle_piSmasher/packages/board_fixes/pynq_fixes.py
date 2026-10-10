# Board fixes applied to the installed PYNQ packages; run by qemu.sh.
# pynqmetadata rejects the slave-mode MDIO nets of gmii_to_rgmii
# (WrongPolarityConnection) and the whole overlay fails to load. Skip such a
# net instead; it is metadata only.
import importlib.util
p = importlib.util.find_spec("pynqmetadata.frontends.hwh_frontend").origin
s = open(p).read()
old = "                        signal.connect(dst_signal)\n"
new = ("                        try:\n"
       "                            signal.connect(dst_signal)\n"
       "                        except WrongPolarityConnection:\n"
       "                            pass\n")
if new not in s:
    assert s.count(old) == 1, "pynqmetadata call site changed"
    s = s.replace(old, new)
    s = s.replace("from ..errors import ExpectedSignalType,",
                  "from ..errors import WrongPolarityConnection, ExpectedSignalType,", 1)
    open(p, "w").write(s)
print("patched", p)

# PYNQ 4 reads each PL clock's achieved frequency, but the Zynq-7000 model
# lacks the parameter name for it, so every FCLK comes back as None.
p = importlib.util.find_spec("pynqmetadata.models.zynq_proc_sys_core").origin
s = open(p).read()
add = '''
    def clk_freq_param_name(self, clk_id: int) -> str:
        """Returns the name of the achieved PL clock frequency parameter."""
        return f"PCW_ACT_FPGA{clk_id}_PERIPHERAL_FREQMHZ"
'''
if "def clk_freq_param_name" not in s:
    open(p, "w").write(s.rstrip("\n") + "\n" + add)
print("patched", p)

# pynq.lib.Wifi(auto=True) writes both "auto wlan0" and "allow-hotplug wlan0".
# The WL1837's wlan0 appears late (firmware load), and with both stanzas
# networking.service and ifup@wlan0 race and tear the link down again a few
# seconds after it associates. Hotplug alone is enough.
p = importlib.util.find_spec("pynq.lib.wifi").origin
s = open(p).read()
old = '            net_iface_fh.write("auto " + self.wifi_port + "\\n")\n'
if old in s:
    open(p, "w").write(s.replace(old, ""))
print("patched", p)
