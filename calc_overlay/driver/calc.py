"""PYNQ driver for the calc_axi hardware calculator (+, -, *, /).

Usage on the board:

    from calc import CalcOverlay
    ol = CalcOverlay("calc.bit")
    ol.calc.add(7, 5)        # 12
    ol.calc.div(-7, 2)       # CalcResult(value=-3, remainder=-1, ...)
"""

from dataclasses import dataclass

from pynq import DefaultIP, Overlay

CTRL, OPCODE, A, B, RES_LO, RES_HI = 0x00, 0x04, 0x08, 0x0C, 0x10, 0x14
BUSY, DONE, DIV_BY_ZERO, OVERFLOW = 0x1, 0x2, 0x4, 0x8
OPS = {"+": 0, "-": 1, "*": 2, "/": 3}

INT32_MIN, INT32_MAX = -(1 << 31), (1 << 31) - 1


def _to_u32(x):
    if not INT32_MIN <= x <= INT32_MAX:
        raise ValueError(f"{x} does not fit in a signed 32-bit integer")
    return x & 0xFFFFFFFF


def _to_s32(x):
    return x - (1 << 32) if x & 0x80000000 else x


@dataclass
class CalcResult:
    value: int           # sum, difference, full 64-bit product, or quotient
    remainder: int       # division only, else 0
    overflow: bool       # value does not fit in 32 bits (add/sub/mul) or INT_MIN / -1
    div_by_zero: bool

    def __int__(self):
        return self.value


class Calculator(DefaultIP):
    """Driver bound to every calc_axi instance in an overlay."""

    bindto = ["xilinx.com:module_ref:calc_axi:1.0"]

    def compute(self, a, op, b, timeout=1000):
        """Run one operation in hardware; op is one of '+', '-', '*', '/'."""
        self.write(OPCODE, OPS[op])
        self.write(A, _to_u32(a))
        self.write(B, _to_u32(b))
        self.write(CTRL, 1)
        for _ in range(timeout):
            status = self.read(CTRL)
            if status & DONE and not status & BUSY:
                break
        else:
            raise TimeoutError("calculator did not finish")

        lo, hi = self.read(RES_LO), self.read(RES_HI)
        if op == "*":
            value, remainder = _to_s32(hi) * (1 << 32) + lo, 0
        elif op == "/":
            value, remainder = _to_s32(lo), _to_s32(hi)
        else:
            value, remainder = _to_s32(lo), 0
        return CalcResult(value, remainder, bool(status & OVERFLOW),
                          bool(status & DIV_BY_ZERO))

    def add(self, a, b):
        return self.compute(a, "+", b).value

    def sub(self, a, b):
        return self.compute(a, "-", b).value

    def mul(self, a, b):
        return self.compute(a, "*", b).value

    def div(self, a, b):
        r = self.compute(a, "/", b)
        if r.div_by_zero:
            raise ZeroDivisionError("hardware division by zero")
        return r

    def eval(self, expr):
        """Evaluate a single 'a <op> b' string, e.g. '12 * -3'."""
        for op in OPS:
            left, sep, right = expr.partition(f" {op} ")
            if sep:
                return self.compute(int(left), op, int(right))
        raise ValueError("expected 'a <op> b' with spaces around the operator")


class CalcOverlay(Overlay):
    """The calc overlay; the calculator is available as .calc."""

    def __init__(self, bitfile="calc.bit", **kwargs):
        super().__init__(bitfile, **kwargs)
        self.calc = self.calc_0
