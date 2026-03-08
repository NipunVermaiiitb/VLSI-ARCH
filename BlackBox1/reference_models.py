"""
Python Reference Models for Stage 1 DPDAC FMA Unit
Mathematical verification models matching Verilog implementation
"""

import struct
import math
from typing import Tuple, List

# Precision encodings
HP = 0b000
BF16 = 0b001
TF32 = 0b010
SP = 0b011
DP = 0b100

class FloatFormatter:
    """Reference model for component_formatter.v"""
    
    @staticmethod
    def extract_ieee754_parts(value_64bit: int, prec: int, lane: int) -> Tuple[int, int, int]:
        """
        Extract sign, exponent, mantissa from 64-bit packed input
        Returns: (sign, exponent, mantissa_with_implicit_bit)
        """
        if prec == DP:
            # Lane 0 only for DP
            sign = (value_64bit >> 63) & 1
            exp = (value_64bit >> 52) & 0x7FF
            frac = value_64bit & 0xFFFFFFFFFFFFF
            # Add implicit bit if exponent is non-zero
            implicit = 1 if exp != 0 else 0
            mantissa = (implicit << 52) | frac
            return sign, exp, mantissa
        
        elif prec in [SP, TF32]:
            # All lanes used: two 28-bit groups (segments 3+2 and 1+0)
            if lane == 2:
                seg = (value_64bit >> 28) & 0xFFFFFFF
            elif lane == 0:
                seg = value_64bit & 0xFFFFFFF
            else:
                return 0, 0, 0
            
            # Extract SP format (1 sign + 8 exp + 23 frac = 32 bits in 28-bit segment)
            sign = (seg >> 27) & 1
            exp = (seg >> 19) & 0xFF
            
            if prec == TF32:
                # TF32: only bottom 10 bits of fraction
                frac = (seg >> 9) & 0x3FF
                implicit = 1 if exp != 0 else 0
                mantissa = (implicit << 10) | frac
            else:
                # SP: 23 bits of fraction
                frac = seg & 0x7FFFFF
                implicit = 1 if exp != 0 else 0
                mantissa = (implicit << 23) | frac
            
            return sign, exp, mantissa
        
        elif prec in [HP, BF16]:
            # Lanes 3, 2, 1, 0 (14-bit segments)
            shift = lane * 14
            seg = (value_64bit >> shift) & 0x3FFF
            
            if prec == HP:
                # HP: 1 sign + 5 exp + 10 frac
                sign = (seg >> 13) & 1
                exp = (seg >> 10) & 0x1F
                frac = seg & 0x3FF
                implicit = 1 if exp != 0 else 0
                mantissa = (implicit << 10) | frac
            else:
                # BF16: 1 sign + 8 exp + 7 frac (in 16 bits, top 14 bits used)
                sign = (seg >> 13) & 1
                exp = (seg >> 5) & 0xFF
                frac = seg & 0x1F
                implicit = 1 if exp != 0 else 0
                mantissa = (implicit << 7) | frac
            
            return sign, exp, mantissa
        
        return 0, 0, 0
    
    @staticmethod
    def format_to_unified(value_64bit: int, prec: int, valid: int) -> Tuple[List[int], List[int], List[int]]:
        """
        Format 64-bit input to unified 56-bit mantissa, 32-bit exponent, 4-bit sign
        Returns: (signs[4], exponents[4], mantissa_56bit)
        """
        signs = [0, 0, 0, 0]
        exps = [0, 0, 0, 0]
        mantissa = 0
        
        for lane in range(4):
            if not (valid & (1 << lane)):
                continue
            
            sign, exp, mant = FloatFormatter.extract_ieee754_parts(value_64bit, prec, lane)
            signs[lane] = sign
            exps[lane] = exp
            
            # Pack mantissa into 14-bit segments
            mantissa |= (mant << (lane * 14))
        
        return signs, exps, mantissa


class SignLogic:
    """Reference model for sign_logic.v"""
    
    @staticmethod
    def compute_product_signs(a_signs: List[int], b_signs: List[int], valid: int) -> int:
        """
        Compute per-lane product signs: sign[i] = a_sign[i] XOR b_sign[i]
        Returns 4-bit result masked by valid
        """
        result = 0
        for i in range(4):
            if valid & (1 << i):
                sign = a_signs[i] ^ b_signs[i]
                result |= (sign << i)
        return result & 0xF


class Mult14Booth:
    """Reference model for mult14_radix4_booth.v"""
    
    @staticmethod
    def multiply(a: int, b: int) -> int:
        """
        14-bit x 14-bit Booth multiplier
        Returns 28-bit product
        """
        # Simple reference: just use Python multiplication
        # Verilog uses Booth encoding, but result should match
        a = a & 0x3FFF
        b = b & 0x3FFF
        product = a * b
        return product & 0xFFFFFFF


class ExponentComparison:
    """Reference model for exponent_comparison.v"""
    
    CONST_DP_BASE = 2
    CONST_PD2_BASE = 2
    CONST_PD4_BASE = 2
    
    @staticmethod
    def compare(a_exps: List[int], b_exps: List[int], c_exps: List[int],
                prec: int, valid: int, para: int, cvt: int) -> Tuple[int, int]:
        """
        Compute exponent comparison and alignment shift counts
        Returns: (ExpDiff, MaxExp) as 32-bit packed values
        """
        # Compute product exponents per lane
        ab_exps = [a_exps[i] + b_exps[i] for i in range(4)]
        
        # Find max product exponent (considering Valid)
        exp_ab_max = 0
        for i in range(4):
            if valid & (1 << i):
                exp_ab_max = max(exp_ab_max, ab_exps[i])
        
        # Find max C exponent (considering Valid)
        exp_c_max = 0
        for i in range(4):
            if valid & (1 << i):
                exp_c_max = max(exp_c_max, c_exps[i])
        
        # Compute constant term based on mode
        if prec == DP:
            const_term = ExponentComparison.CONST_DP_BASE
        elif prec in [SP, TF32]:
            const_term = ExponentComparison.CONST_PD2_BASE
        else:
            const_term = ExponentComparison.CONST_PD4_BASE
        
        const_term += para + cvt
        
        # Compute ASCs for dual-path alignment
        # ASC = exp_ab_max - exp_c - const_term
        # For now, same ASC for both paths (can be different for C1/C0)
        asc_c1 = exp_ab_max - exp_c_max - const_term
        asc_c0 = exp_ab_max - exp_c_max - const_term
        
        # Saturate to 0 if negative
        asc_c1 = max(0, asc_c1)
        asc_c0 = max(0, asc_c0)
        
        # Pack outputs
        ExpDiff = ((asc_c1 & 0xFFFF) << 16) | (asc_c0 & 0xFFFF)
        MaxExp = ((exp_c_max & 0xFFFF) << 16) | (exp_ab_max & 0xFFFF)
        
        return ExpDiff, MaxExp


class AddendAlignmentShifter:
    """Reference model for addend_alignment_shifter.v"""
    
    @staticmethod
    def align(c_mantissa_56bit: int, exp_diff: int, prec: int) -> int:
        """
        Align C mantissa using dual shift counts
        Returns 163-bit aligned result
        """
        # Unpack ASCs
        asc_c1 = (exp_diff >> 16) & 0xFFFF
        asc_c0 = exp_diff & 0xFFFF
        
        # Clamp to 162
        asc_c1 = min(asc_c1, 162)
        asc_c0 = min(asc_c0, 162)
        
        # Create unified mantissa (163 bits total)
        man_c_unified = c_mantissa_56bit << 107
        
        # Split into high and low
        man_c_hi = (man_c_unified >> 81) & ((1 << 82) - 1)
        man_c_lo = man_c_unified & ((1 << 81) - 1)
        
        # Data pad for DP mode
        if prec == DP:
            data_pad = man_c_hi
        else:
            data_pad = 0
        
        # Dual shifters
        sht_rc1 = (man_c_hi << 81) >> asc_c1
        sht_rc0 = ((data_pad << 81) | man_c_lo) >> asc_c0
        
        # Merge
        aligned_c_hi = (sht_rc1 >> 81) & ((1 << 82) - 1)
        aligned_c_lo = sht_rc0 & ((1 << 81) - 1)
        aligned_c = (aligned_c_hi << 81) | aligned_c_lo
        
        return aligned_c & ((1 << 163) - 1)


class MultiplierArray:
    """Reference model for multiplier_array.v"""
    
    @staticmethod
    def multiply_array(a_mant: int, b_mant: int, prec: int, valid: int,
                       pd_mode: bool, pd2_mode: bool, pd4_mode: bool,
                       cnt0: int = 0) -> int:
        """
        Compute mantissa products using 16 booth cells
        Returns 112-bit packed products
        """
        # Extract lanes
        a_lanes = [(a_mant >> (i * 14)) & 0x3FFF for i in range(4)]
        b_lanes = [(b_mant >> (i * 14)) & 0x3FFF for i in range(4)]
        
        if pd4_mode:
            # Quad 14x14
            products = []
            for i in range(4):
                if valid & (1 << i):
                    prod = Mult14Booth.multiply(a_lanes[i], b_lanes[i])
                else:
                    prod = 0
                products.append(prod)
            
            # Pack
            result = 0
            for i in range(4):
                result |= (products[i] << (i * 28))
            return result
        
        elif pd2_mode:
            # Dual 28x28
            # High group (lanes 3,2)
            a_hi = (a_lanes[3] << 14) | a_lanes[2]
            b_hi = (b_lanes[3] << 14) | b_lanes[2]
            prod_hi = (a_hi * b_hi) if (valid & 0b1100) else 0
            
            # Low group (lanes 1,0)
            a_lo = (a_lanes[1] << 14) | a_lanes[0]
            b_lo = (b_lanes[1] << 14) | b_lanes[0]
            prod_lo = (a_lo * b_lo) if (valid & 0b0011) else 0
            
            result = (prod_hi << 56) | (prod_lo & ((1 << 56) - 1))
            return result
        
        elif pd_mode:
            # DP 56x56 (simplified - doesn't model 2-cycle behavior)
            a_full = a_mant & ((1 << 56) - 1)
            b_full = b_mant & ((1 << 56) - 1)
            prod = a_full * b_full
            return prod & ((1 << 112) - 1)
        
        return 0


def test_suite():
    """Run basic verification tests"""
    print("="*60)
    print("Python Reference Model Verification")
    print("="*60)
    
    # Test 1: Component Formatter - DP mode
    print("\n[Test 1] Component Formatter - DP Mode")
    dp_1_5 = 0x3FF8000000000000  # 1.5 in DP
    signs, exps, mant = FloatFormatter.format_to_unified(dp_1_5, DP, 0b1111)  # All lanes for DP
    print(f"  Input: 0x{dp_1_5:016X} (1.5)")
    print(f"  Sign: {signs[0]}, Exp: {exps[0]}, Mant: 0x{mant:014X}")
    assert signs[0] == 0, "Sign should be 0"
    assert exps[0] == 1023, f"Exponent should be 1023, got {exps[0]}"
    print("  ✓ PASS")
    
    # Test 2: Sign Logic
    print("\n[Test 2] Sign Logic")
    a_signs = [0, 1, 0, 1]
    b_signs = [0, 0, 1, 1]
    result = SignLogic.compute_product_signs(a_signs, b_signs, 0b1111)
    print(f"  A signs: {a_signs}, B signs: {b_signs}")
    print(f"  Product signs: {bin(result)}")
    assert result == 0b0110, f"Expected 0b0110, got {bin(result)}"
    print("  ✓ PASS")
    
    # Test 3: Booth Multiplier
    print("\n[Test 3] Booth Multiplier")
    a, b = 100, 50
    prod = Mult14Booth.multiply(a, b)
    print(f"  {a} × {b} = {prod}")
    assert prod == 5000, f"Expected 5000, got {prod}"
    print("  ✓ PASS")
    
    # Test 4: Exponent Comparison
    print("\n[Test 4] Exponent Comparison - DP Mode")
    a_exps = [1024, 0, 0, 0]
    b_exps = [1025, 0, 0, 0]
    c_exps = [1023, 0, 0, 0]
    exp_diff, max_exp = ExponentComparison.compare(
        a_exps, b_exps, c_exps, DP, 0b1111, 0, 0  # All lanes for DP
    )
    asc_c1 = (exp_diff >> 16) & 0xFFFF
    asc_c0 = exp_diff & 0xFFFF
    print(f"  AB_exp: {a_exps[0] + b_exps[0]}, C_exp: {c_exps[0]}")
    print(f"  ASC_C1: {asc_c1}, ASC_C0: {asc_c0}")
    assert asc_c1 == 1024, f"Expected ASC_C1=1024, got {asc_c1}"
    print("  ✓ PASS")
    
    # Test 5: Multiplier Array - PD4 Mode
    print("\n[Test 5] Multiplier Array - PD4 Mode")
    a_mant = (10 << 42) | (20 << 28) | (30 << 14) | 40
    b_mant = (5 << 42) | (6 << 28) | (7 << 14) | 8
    products = MultiplierArray.multiply_array(
        a_mant, b_mant, HP, 0b1111, False, False, True
    )
    p0 = products & 0xFFFFFFF
    p1 = (products >> 28) & 0xFFFFFFF
    p2 = (products >> 56) & 0xFFFFFFF
    p3 = (products >> 84) & 0xFFFFFFF
    print(f"  Lane products: {p3}, {p2}, {p1}, {p0}")
    print(f"  Expected: 50, 120, 210, 320")
    assert p0 == 320 and p1 == 210 and p2 == 120 and p3 == 50
    print("  ✓ PASS")
    
    print("\n" + "="*60)
    print("All reference model tests PASSED! ✓")
    print("="*60)


if __name__ == "__main__":
    test_suite()
