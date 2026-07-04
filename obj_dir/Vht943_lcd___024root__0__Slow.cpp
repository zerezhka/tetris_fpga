// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vht943_lcd.h for the primary calling header

#include "Vht943_lcd__pch.h"

VL_ATTR_COLD void Vht943_lcd___024root___eval_static(Vht943_lcd___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vht943_lcd___024root___eval_static\n"); );
    Vht943_lcd__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.__Vtrigprevexpr___TOP__clk__0 = vlSelfRef.clk;
    vlSelfRef.__Vtrigprevexpr___TOP__rst__0 = vlSelfRef.rst;
    vlSelfRef.__Vtrigprevexpr___TOP__profile__0 = vlSelfRef.profile;
    vlSelfRef.__Vtrigprevexpr___TOP__ram_data__0 = vlSelfRef.ram_data;
    vlSelfRef.__Vtrigprevexpr___TOP__clk__1 = vlSelfRef.clk;
}

VL_ATTR_COLD void Vht943_lcd___024root___eval_initial(Vht943_lcd___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vht943_lcd___024root___eval_initial\n"); );
    Vht943_lcd__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    {
        // Inlined CFunc: _eval_initial__TOP
        VL_READMEM_N(true, 10, 33600, 0, "rtl/assets/E88_8in1_pix.hex"s
                     ,  &(vlSelfRef.ht943_lcd__DOT__pixmap0)
                     , 0, ~0ULL);
        VL_READMEM_N(true, 10, 33600, 0, "rtl/assets/KeychainPinBall_pix.hex"s
                     ,  &(vlSelfRef.ht943_lcd__DOT__pixmap1)
                     , 0, ~0ULL);
        VL_READMEM_N(true, 10, 33600, 0, "rtl/assets/Keychain55in1_pix.hex"s
                     ,  &(vlSelfRef.ht943_lcd__DOT__pixmap2)
                     , 0, ~0ULL);
        VL_READMEM_N(true, 10, 33600, 0, "rtl/assets/SpaceIntruderTK150I_pix.hex"s
                     ,  &(vlSelfRef.ht943_lcd__DOT__pixmap3)
                     , 0, ~0ULL);
        VL_READMEM_N(true, 10, 512, 0, "rtl/assets/E88_8in1_seg.hex"s
                     ,  &(vlSelfRef.ht943_lcd__DOT__segtab0)
                     , 0, ~0ULL);
        VL_READMEM_N(true, 10, 512, 0, "rtl/assets/KeychainPinBall_seg.hex"s
                     ,  &(vlSelfRef.ht943_lcd__DOT__segtab1)
                     , 0, ~0ULL);
        VL_READMEM_N(true, 10, 512, 0, "rtl/assets/Keychain55in1_seg.hex"s
                     ,  &(vlSelfRef.ht943_lcd__DOT__segtab2)
                     , 0, ~0ULL);
        VL_READMEM_N(true, 10, 512, 0, "rtl/assets/SpaceIntruderTK150I_seg.hex"s
                     ,  &(vlSelfRef.ht943_lcd__DOT__segtab3)
                     , 0, ~0ULL);
        VL_READMEM_N(true, 54, 512, 0, "rtl/assets/E88_8in1_geo.hex"s
                     ,  &(vlSelfRef.ht943_lcd__DOT__geotab0)
                     , 0, ~0ULL);
        VL_READMEM_N(true, 54, 512, 0, "rtl/assets/KeychainPinBall_geo.hex"s
                     ,  &(vlSelfRef.ht943_lcd__DOT__geotab1)
                     , 0, ~0ULL);
        VL_READMEM_N(true, 54, 512, 0, "rtl/assets/Keychain55in1_geo.hex"s
                     ,  &(vlSelfRef.ht943_lcd__DOT__geotab2)
                     , 0, ~0ULL);
        VL_READMEM_N(true, 54, 512, 0, "rtl/assets/SpaceIntruderTK150I_geo.hex"s
                     ,  &(vlSelfRef.ht943_lcd__DOT__geotab3)
                     , 0, ~0ULL);
    }
}

VL_ATTR_COLD void Vht943_lcd___024root___eval_final(Vht943_lcd___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vht943_lcd___024root___eval_final\n"); );
    Vht943_lcd__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
}

#ifdef VL_DEBUG
VL_ATTR_COLD void Vht943_lcd___024root___dump_triggers__stl(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag);
#endif  // VL_DEBUG
VL_ATTR_COLD bool Vht943_lcd___024root___eval_phase__stl(Vht943_lcd___024root* vlSelf);

VL_ATTR_COLD void Vht943_lcd___024root___eval_settle(Vht943_lcd___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vht943_lcd___024root___eval_settle\n"); );
    Vht943_lcd__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    IData/*31:0*/ __VstlIterCount;
    // Body
    __VstlIterCount = 0U;
    vlSelfRef.__VstlFirstIteration = 1U;
    do {
        if (VL_UNLIKELY(((0x00002710U < __VstlIterCount)))) {
#ifdef VL_DEBUG
            Vht943_lcd___024root___dump_triggers__stl(vlSelfRef.__VstlTriggered, "stl"s);
#endif
            VL_FATAL_MT("rtl/ht943_lcd.sv", 34, "", "DIDNOTCONVERGE: Settle region did not converge after '--converge-limit' of 10000 tries");
        }
        __VstlIterCount = ((IData)(1U) + __VstlIterCount);
        vlSelfRef.__VstlPhaseResult = Vht943_lcd___024root___eval_phase__stl(vlSelf);
        vlSelfRef.__VstlFirstIteration = 0U;
    } while (vlSelfRef.__VstlPhaseResult);
}

VL_ATTR_COLD bool Vht943_lcd___024root___trigger_anySet__stl(const VlUnpacked<QData/*63:0*/, 1> &in);

#ifdef VL_DEBUG
VL_ATTR_COLD void Vht943_lcd___024root___dump_triggers__stl(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vht943_lcd___024root___dump_triggers__stl\n"); );
    // Body
    if ((1U & (~ (IData)(Vht943_lcd___024root___trigger_anySet__stl(triggers))))) {
        VL_DBG_MSGS("         No '" + tag + "' region triggers active\n");
    }
    if ((1U & (IData)(triggers[0U]))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 0 is active: Internal 'stl' trigger - first iteration\n");
    }
}
#endif  // VL_DEBUG

VL_ATTR_COLD bool Vht943_lcd___024root___trigger_anySet__stl(const VlUnpacked<QData/*63:0*/, 1> &in) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vht943_lcd___024root___trigger_anySet__stl\n"); );
    // Locals
    IData/*31:0*/ n;
    // Body
    n = 0U;
    do {
        if (in[n]) {
            return (1U);
        }
        n = ((IData)(1U) + n);
    } while ((1U > n));
    return (0U);
}

VL_ATTR_COLD void Vht943_lcd___024root___stl_sequent__TOP__0(Vht943_lcd___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vht943_lcd___024root___stl_sequent__TOP__0\n"); );
    Vht943_lcd__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.HSync = (1U & ((IData)(vlSelfRef.ht943_lcd__DOT__d_hsync) 
                             >> 2U));
    vlSelfRef.VSync = (1U & ((IData)(vlSelfRef.ht943_lcd__DOT__d_vsync) 
                             >> 2U));
    vlSelfRef.HBlank = (1U & ((IData)(vlSelfRef.ht943_lcd__DOT__d_hblank) 
                              >> 2U));
    vlSelfRef.VBlank = (1U & ((IData)(vlSelfRef.ht943_lcd__DOT__d_vblank) 
                              >> 2U));
    vlSelfRef.ce_pix = (1U & ((IData)(vlSelfRef.ht943_lcd__DOT__d_ce) 
                              >> 2U));
    vlSelfRef.R = (((IData)(vlSelfRef.ht943_lcd__DOT__dark)
                     ? 0x18U : 0xc8U) & (- (IData)(
                                                   (1U 
                                                    & ((IData)(vlSelfRef.ht943_lcd__DOT__d_active) 
                                                       >> 2U)))));
    vlSelfRef.G = (((IData)(vlSelfRef.ht943_lcd__DOT__dark)
                     ? 0x20U : 0xd4U) & (- (IData)(
                                                   (1U 
                                                    & ((IData)(vlSelfRef.ht943_lcd__DOT__d_active) 
                                                       >> 2U)))));
    vlSelfRef.B = (((IData)(vlSelfRef.ht943_lcd__DOT__dark)
                     ? 0x18U : 0xb4U) & (- (IData)(
                                                   (1U 
                                                    & ((IData)(vlSelfRef.ht943_lcd__DOT__d_active) 
                                                       >> 2U)))));
    if ((0U == (IData)(vlSelfRef.profile))) {
        vlSelfRef.ht943_lcd__DOT__pix_word = vlSelfRef.ht943_lcd__DOT__pw0;
        vlSelfRef.ht943_lcd__DOT__seg_word = vlSelfRef.ht943_lcd__DOT__sw0;
        vlSelfRef.ht943_lcd__DOT__geo_word = vlSelfRef.ht943_lcd__DOT__gw0;
    } else if ((1U == (IData)(vlSelfRef.profile))) {
        vlSelfRef.ht943_lcd__DOT__pix_word = vlSelfRef.ht943_lcd__DOT__pw1;
        vlSelfRef.ht943_lcd__DOT__seg_word = vlSelfRef.ht943_lcd__DOT__sw1;
        vlSelfRef.ht943_lcd__DOT__geo_word = vlSelfRef.ht943_lcd__DOT__gw1;
    } else if ((2U == (IData)(vlSelfRef.profile))) {
        vlSelfRef.ht943_lcd__DOT__pix_word = vlSelfRef.ht943_lcd__DOT__pw2;
        vlSelfRef.ht943_lcd__DOT__seg_word = vlSelfRef.ht943_lcd__DOT__sw2;
        vlSelfRef.ht943_lcd__DOT__geo_word = vlSelfRef.ht943_lcd__DOT__gw2;
    } else {
        vlSelfRef.ht943_lcd__DOT__pix_word = vlSelfRef.ht943_lcd__DOT__pw3;
        vlSelfRef.ht943_lcd__DOT__seg_word = vlSelfRef.ht943_lcd__DOT__sw3;
        vlSelfRef.ht943_lcd__DOT__geo_word = vlSelfRef.ht943_lcd__DOT__gw3;
    }
    vlSelfRef.ht943_lcd__DOT__active_raw = ((0x0168U 
                                             > (IData)(vlSelfRef.ht943_lcd__DOT__h_count)) 
                                            & (0x0348U 
                                               > (IData)(vlSelfRef.ht943_lcd__DOT__v_count)));
    vlSelfRef.ht943_lcd__DOT__pix_idx = (0x0000ffffU 
                                         & ((((IData)(0x00000078U) 
                                              * (IData)(vlSelfRef.ht943_lcd__DOT__cy)) 
                                             + (IData)(vlSelfRef.ht943_lcd__DOT__cx)) 
                                            & (- (IData)((IData)(vlSelfRef.ht943_lcd__DOT__active_raw)))));
    vlSelfRef.ram_addr = (0x000000ffU & ((IData)(vlSelfRef.ht943_lcd__DOT__seg_word) 
                                         >> 2U));
    vlSelfRef.ht943_lcd__DOT__wmt = (0x000003ffU & 
                                     ((0x000001ffU 
                                       & (IData)((vlSelfRef.ht943_lcd__DOT__geo_word 
                                                  >> 0x00000019U))) 
                                      - (0x0000000fU 
                                         & (IData)(
                                                   (vlSelfRef.ht943_lcd__DOT__geo_word 
                                                    >> 0x0000000cU)))));
    vlSelfRef.ht943_lcd__DOT__hmt = (0x000003ffU & 
                                     ((0x000001ffU 
                                       & (IData)((vlSelfRef.ht943_lcd__DOT__geo_word 
                                                  >> 0x00000010U))) 
                                      - (0x0000000fU 
                                         & (IData)(
                                                   (vlSelfRef.ht943_lcd__DOT__geo_word 
                                                    >> 8U)))));
    vlSelfRef.ht943_lcd__DOT__dx = (0x000003ffU & ((IData)(vlSelfRef.ht943_lcd__DOT__hx2) 
                                                   - 
                                                   (0x000001ffU 
                                                    & (IData)(
                                                              (vlSelfRef.ht943_lcd__DOT__geo_word 
                                                               >> 0x0000002cU)))));
    vlSelfRef.ht943_lcd__DOT__dy = (0x000003ffU & ((IData)(vlSelfRef.ht943_lcd__DOT__hy2) 
                                                   - (IData)(
                                                             (vlSelfRef.ht943_lcd__DOT__geo_word 
                                                              >> 0x00000022U))));
}

VL_ATTR_COLD bool Vht943_lcd___024root___eval_phase__stl(Vht943_lcd___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vht943_lcd___024root___eval_phase__stl\n"); );
    Vht943_lcd__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    CData/*0:0*/ __VstlExecute;
    // Body
    {
        // Inlined CFunc: _eval_triggers_vec__stl
        vlSelfRef.__VstlTriggered[0U] = ((0xfffffffffffffffeULL 
                                          & vlSelfRef.__VstlTriggered[0U]) 
                                         | (IData)((IData)(vlSelfRef.__VstlFirstIteration)));
    }
#ifdef VL_DEBUG
    if (VL_UNLIKELY(vlSymsp->_vm_contextp__->debug())) {
        Vht943_lcd___024root___dump_triggers__stl(vlSelfRef.__VstlTriggered, "stl"s);
    }
#endif
    __VstlExecute = Vht943_lcd___024root___trigger_anySet__stl(vlSelfRef.__VstlTriggered);
    if (__VstlExecute) {
        {
            // Inlined CFunc: _eval_stl
            if ((1ULL & vlSelfRef.__VstlTriggered[0U])) {
                Vht943_lcd___024root___stl_sequent__TOP__0(vlSelf);
            }
        }
    }
    return (__VstlExecute);
}

bool Vht943_lcd___024root___trigger_anySet__ico(const VlUnpacked<QData/*63:0*/, 2> &in);

#ifdef VL_DEBUG
VL_ATTR_COLD void Vht943_lcd___024root___dump_triggers__ico(const VlUnpacked<QData/*63:0*/, 2> &triggers, const std::string &tag) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vht943_lcd___024root___dump_triggers__ico\n"); );
    // Body
    if ((1U & (~ (IData)(Vht943_lcd___024root___trigger_anySet__ico(triggers))))) {
        VL_DBG_MSGS("         No '" + tag + "' region triggers active\n");
    }
    if ((1U & (IData)(triggers[0U]))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 0 is active: @( clk)\n");
    }
    if ((1U & (IData)((triggers[0U] >> 1U)))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 1 is active: @( rst)\n");
    }
    if ((1U & (IData)((triggers[0U] >> 2U)))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 2 is active: @( profile)\n");
    }
    if ((1U & (IData)((triggers[0U] >> 3U)))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 3 is active: @( ram_data)\n");
    }
    if ((1U & (IData)(triggers[1U]))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 64 is active: Internal 'ico' trigger - first iteration\n");
    }
}
#endif  // VL_DEBUG

bool Vht943_lcd___024root___trigger_anySet__act(const VlUnpacked<QData/*63:0*/, 1> &in);

#ifdef VL_DEBUG
VL_ATTR_COLD void Vht943_lcd___024root___dump_triggers__act(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vht943_lcd___024root___dump_triggers__act\n"); );
    // Body
    if ((1U & (~ (IData)(Vht943_lcd___024root___trigger_anySet__act(triggers))))) {
        VL_DBG_MSGS("         No '" + tag + "' region triggers active\n");
    }
    if ((1U & (IData)(triggers[0U]))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 0 is active: @(posedge clk)\n");
    }
}
#endif  // VL_DEBUG

VL_ATTR_COLD void Vht943_lcd___024root___ctor_var_reset(Vht943_lcd___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vht943_lcd___024root___ctor_var_reset\n"); );
    Vht943_lcd__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    const uint64_t __VscopeHash = VL_MURMUR64_HASH(vlSelf->vlNamep);
    vlSelf->clk = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 16707436170211756652ull);
    vlSelf->rst = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 18209466448985614591ull);
    vlSelf->profile = VL_SCOPED_RAND_RESET_I(2, __VscopeHash, 7251410618025197833ull);
    vlSelf->ram_addr = VL_SCOPED_RAND_RESET_I(8, __VscopeHash, 10009909287601691191ull);
    vlSelf->ram_data = VL_SCOPED_RAND_RESET_I(4, __VscopeHash, 9092177012760777380ull);
    vlSelf->R = VL_SCOPED_RAND_RESET_I(8, __VscopeHash, 12290980237632234855ull);
    vlSelf->G = VL_SCOPED_RAND_RESET_I(8, __VscopeHash, 9148987913859918431ull);
    vlSelf->B = VL_SCOPED_RAND_RESET_I(8, __VscopeHash, 149303876845869574ull);
    vlSelf->HSync = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 6896655602068565636ull);
    vlSelf->VSync = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 1468081538417712294ull);
    vlSelf->HBlank = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 11498850426090054997ull);
    vlSelf->VBlank = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 16624563863309448368ull);
    vlSelf->ce_pix = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 5281599081232318353ull);
    vlSelf->ht943_lcd__DOT__h_count = VL_SCOPED_RAND_RESET_I(9, __VscopeHash, 7351813754464011496ull);
    vlSelf->ht943_lcd__DOT__v_count = VL_SCOPED_RAND_RESET_I(10, __VscopeHash, 15289739028462588820ull);
    vlSelf->ht943_lcd__DOT__div2 = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 16548816879167908870ull);
    vlSelf->ht943_lcd__DOT__pix_ce = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 4412180611813474681ull);
    vlSelf->ht943_lcd__DOT__h3 = VL_SCOPED_RAND_RESET_I(2, __VscopeHash, 15652104765070405627ull);
    vlSelf->ht943_lcd__DOT__v3 = VL_SCOPED_RAND_RESET_I(2, __VscopeHash, 12782062879249197481ull);
    vlSelf->ht943_lcd__DOT__cx = VL_SCOPED_RAND_RESET_I(7, __VscopeHash, 5540934201973416541ull);
    vlSelf->ht943_lcd__DOT__cy = VL_SCOPED_RAND_RESET_I(9, __VscopeHash, 15030712983996132533ull);
    vlSelf->ht943_lcd__DOT__active_raw = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 12123736817811913743ull);
    for (int __Vi0 = 0; __Vi0 < 33600; ++__Vi0) {
        vlSelf->ht943_lcd__DOT__pixmap0[__Vi0] = VL_SCOPED_RAND_RESET_I(10, __VscopeHash, 6582904514573381757ull);
    }
    for (int __Vi0 = 0; __Vi0 < 33600; ++__Vi0) {
        vlSelf->ht943_lcd__DOT__pixmap1[__Vi0] = VL_SCOPED_RAND_RESET_I(10, __VscopeHash, 2537479288119813420ull);
    }
    for (int __Vi0 = 0; __Vi0 < 33600; ++__Vi0) {
        vlSelf->ht943_lcd__DOT__pixmap2[__Vi0] = VL_SCOPED_RAND_RESET_I(10, __VscopeHash, 3480618605850952483ull);
    }
    for (int __Vi0 = 0; __Vi0 < 33600; ++__Vi0) {
        vlSelf->ht943_lcd__DOT__pixmap3[__Vi0] = VL_SCOPED_RAND_RESET_I(10, __VscopeHash, 563796844008898786ull);
    }
    for (int __Vi0 = 0; __Vi0 < 512; ++__Vi0) {
        vlSelf->ht943_lcd__DOT__segtab0[__Vi0] = VL_SCOPED_RAND_RESET_I(10, __VscopeHash, 16678891693648588408ull);
    }
    for (int __Vi0 = 0; __Vi0 < 512; ++__Vi0) {
        vlSelf->ht943_lcd__DOT__segtab1[__Vi0] = VL_SCOPED_RAND_RESET_I(10, __VscopeHash, 1962940291058219246ull);
    }
    for (int __Vi0 = 0; __Vi0 < 512; ++__Vi0) {
        vlSelf->ht943_lcd__DOT__segtab2[__Vi0] = VL_SCOPED_RAND_RESET_I(10, __VscopeHash, 14294749620911990088ull);
    }
    for (int __Vi0 = 0; __Vi0 < 512; ++__Vi0) {
        vlSelf->ht943_lcd__DOT__segtab3[__Vi0] = VL_SCOPED_RAND_RESET_I(10, __VscopeHash, 1656515728926292236ull);
    }
    for (int __Vi0 = 0; __Vi0 < 512; ++__Vi0) {
        vlSelf->ht943_lcd__DOT__geotab0[__Vi0] = VL_SCOPED_RAND_RESET_Q(54, __VscopeHash, 1819948116298013294ull);
    }
    for (int __Vi0 = 0; __Vi0 < 512; ++__Vi0) {
        vlSelf->ht943_lcd__DOT__geotab1[__Vi0] = VL_SCOPED_RAND_RESET_Q(54, __VscopeHash, 15601976974726583593ull);
    }
    for (int __Vi0 = 0; __Vi0 < 512; ++__Vi0) {
        vlSelf->ht943_lcd__DOT__geotab2[__Vi0] = VL_SCOPED_RAND_RESET_Q(54, __VscopeHash, 7304604642739961408ull);
    }
    for (int __Vi0 = 0; __Vi0 < 512; ++__Vi0) {
        vlSelf->ht943_lcd__DOT__geotab3[__Vi0] = VL_SCOPED_RAND_RESET_Q(54, __VscopeHash, 6083303325871907018ull);
    }
    vlSelf->ht943_lcd__DOT__pix_idx = VL_SCOPED_RAND_RESET_I(16, __VscopeHash, 12427035296822988610ull);
    vlSelf->ht943_lcd__DOT__pw0 = VL_SCOPED_RAND_RESET_I(10, __VscopeHash, 18233462156416885684ull);
    vlSelf->ht943_lcd__DOT__pw1 = VL_SCOPED_RAND_RESET_I(10, __VscopeHash, 2229566874083196214ull);
    vlSelf->ht943_lcd__DOT__pw2 = VL_SCOPED_RAND_RESET_I(10, __VscopeHash, 3812110023473788230ull);
    vlSelf->ht943_lcd__DOT__pw3 = VL_SCOPED_RAND_RESET_I(10, __VscopeHash, 5524949959772387198ull);
    vlSelf->ht943_lcd__DOT__pix_word = VL_SCOPED_RAND_RESET_I(10, __VscopeHash, 10600082930685708631ull);
    vlSelf->ht943_lcd__DOT__sw0 = VL_SCOPED_RAND_RESET_I(10, __VscopeHash, 5061980689173247852ull);
    vlSelf->ht943_lcd__DOT__sw1 = VL_SCOPED_RAND_RESET_I(10, __VscopeHash, 297931426232000374ull);
    vlSelf->ht943_lcd__DOT__sw2 = VL_SCOPED_RAND_RESET_I(10, __VscopeHash, 2319815783344580613ull);
    vlSelf->ht943_lcd__DOT__sw3 = VL_SCOPED_RAND_RESET_I(10, __VscopeHash, 12734416122786148361ull);
    vlSelf->ht943_lcd__DOT__gw0 = VL_SCOPED_RAND_RESET_Q(54, __VscopeHash, 7137450488898494347ull);
    vlSelf->ht943_lcd__DOT__gw1 = VL_SCOPED_RAND_RESET_Q(54, __VscopeHash, 5560850904573293309ull);
    vlSelf->ht943_lcd__DOT__gw2 = VL_SCOPED_RAND_RESET_Q(54, __VscopeHash, 16533816140396859070ull);
    vlSelf->ht943_lcd__DOT__gw3 = VL_SCOPED_RAND_RESET_Q(54, __VscopeHash, 3573750532164192457ull);
    vlSelf->ht943_lcd__DOT__seg_word = VL_SCOPED_RAND_RESET_I(10, __VscopeHash, 15558604633769179314ull);
    vlSelf->ht943_lcd__DOT__geo_word = VL_SCOPED_RAND_RESET_Q(54, __VscopeHash, 13917130938770683986ull);
    vlSelf->ht943_lcd__DOT__hx1 = VL_SCOPED_RAND_RESET_I(9, __VscopeHash, 5412896638689379366ull);
    vlSelf->ht943_lcd__DOT__hx2 = VL_SCOPED_RAND_RESET_I(9, __VscopeHash, 6285291844380402122ull);
    vlSelf->ht943_lcd__DOT__hy1 = VL_SCOPED_RAND_RESET_I(10, __VscopeHash, 2329609949944051626ull);
    vlSelf->ht943_lcd__DOT__hy2 = VL_SCOPED_RAND_RESET_I(10, __VscopeHash, 15337425657516415876ull);
    vlSelf->ht943_lcd__DOT__bg2 = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 833243185426334967ull);
    vlSelf->ht943_lcd__DOT__dx = VL_SCOPED_RAND_RESET_I(10, __VscopeHash, 5052954081028015279ull);
    vlSelf->ht943_lcd__DOT__dy = VL_SCOPED_RAND_RESET_I(10, __VscopeHash, 2196971355150329074ull);
    vlSelf->ht943_lcd__DOT__wmt = VL_SCOPED_RAND_RESET_I(10, __VscopeHash, 3513826197399807240ull);
    vlSelf->ht943_lcd__DOT__hmt = VL_SCOPED_RAND_RESET_I(10, __VscopeHash, 1044042245736451029ull);
    vlSelf->ht943_lcd__DOT__dark = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 17559947196149128098ull);
    vlSelf->ht943_lcd__DOT__d_hsync = VL_SCOPED_RAND_RESET_I(3, __VscopeHash, 12965709237850391583ull);
    vlSelf->ht943_lcd__DOT__d_vsync = VL_SCOPED_RAND_RESET_I(3, __VscopeHash, 1049044502920858544ull);
    vlSelf->ht943_lcd__DOT__d_hblank = VL_SCOPED_RAND_RESET_I(3, __VscopeHash, 6298241340608500116ull);
    vlSelf->ht943_lcd__DOT__d_vblank = VL_SCOPED_RAND_RESET_I(3, __VscopeHash, 9730801752971319743ull);
    vlSelf->ht943_lcd__DOT__d_active = VL_SCOPED_RAND_RESET_I(3, __VscopeHash, 5988049361647396960ull);
    vlSelf->ht943_lcd__DOT__d_ce = VL_SCOPED_RAND_RESET_I(3, __VscopeHash, 17251294453728929610ull);
    for (int __Vi0 = 0; __Vi0 < 1; ++__Vi0) {
        vlSelf->__VstlTriggered[__Vi0] = 0;
    }
    for (int __Vi0 = 0; __Vi0 < 2; ++__Vi0) {
        vlSelf->__VicoTriggered[__Vi0] = 0;
    }
    vlSelf->__Vtrigprevexpr___TOP__clk__0 = 0;
    vlSelf->__Vtrigprevexpr___TOP__rst__0 = 0;
    vlSelf->__Vtrigprevexpr___TOP__profile__0 = 0;
    vlSelf->__Vtrigprevexpr___TOP__ram_data__0 = 0;
    vlSelf->__VicoDidInit = 0;
    for (int __Vi0 = 0; __Vi0 < 1; ++__Vi0) {
        vlSelf->__VactTriggered[__Vi0] = 0;
    }
    vlSelf->__Vtrigprevexpr___TOP__clk__1 = 0;
    for (int __Vi0 = 0; __Vi0 < 1; ++__Vi0) {
        vlSelf->__VnbaTriggered[__Vi0] = 0;
    }
}
