// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vht943_lcd.h for the primary calling header

#include "Vht943_lcd__pch.h"

bool Vht943_lcd___024root___trigger_anySet__ico(const VlUnpacked<QData/*63:0*/, 2> &in) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vht943_lcd___024root___trigger_anySet__ico\n"); );
    // Locals
    IData/*31:0*/ n;
    // Body
    n = 0U;
    do {
        if (in[n]) {
            return (1U);
        }
        n = ((IData)(1U) + n);
    } while ((2U > n));
    return (0U);
}

#ifdef VL_DEBUG
VL_ATTR_COLD void Vht943_lcd___024root___dump_triggers__ico(const VlUnpacked<QData/*63:0*/, 2> &triggers, const std::string &tag);
#endif  // VL_DEBUG

bool Vht943_lcd___024root___eval_phase__ico(Vht943_lcd___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vht943_lcd___024root___eval_phase__ico\n"); );
    Vht943_lcd__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    CData/*0:0*/ __VicoExecute;
    // Body
    {
        // Inlined CFunc: _eval_triggers_vec__ico
        vlSelfRef.__VicoTriggered[0U] = (QData)((IData)(
                                                        (((((IData)(vlSelfRef.ram_data) 
                                                            != (IData)(vlSelfRef.__Vtrigprevexpr___TOP__ram_data__0)) 
                                                           << 3U) 
                                                          | (((IData)(vlSelfRef.profile) 
                                                              != (IData)(vlSelfRef.__Vtrigprevexpr___TOP__profile__0)) 
                                                             << 2U)) 
                                                         | ((((IData)(vlSelfRef.rst) 
                                                              != (IData)(vlSelfRef.__Vtrigprevexpr___TOP__rst__0)) 
                                                             << 1U) 
                                                            | ((IData)(vlSelfRef.clk) 
                                                               != (IData)(vlSelfRef.__Vtrigprevexpr___TOP__clk__0))))));
        vlSelfRef.__Vtrigprevexpr___TOP__clk__0 = vlSelfRef.clk;
        vlSelfRef.__Vtrigprevexpr___TOP__rst__0 = vlSelfRef.rst;
        vlSelfRef.__Vtrigprevexpr___TOP__profile__0 
            = vlSelfRef.profile;
        vlSelfRef.__Vtrigprevexpr___TOP__ram_data__0 
            = vlSelfRef.ram_data;
        if (VL_UNLIKELY(((1U & (~ (IData)(vlSelfRef.__VicoDidInit)))))) {
            vlSelfRef.__VicoDidInit = 1U;
            vlSelfRef.__VicoTriggered[0U] = (1ULL | vlSelfRef.__VicoTriggered[0U]);
            vlSelfRef.__VicoTriggered[0U] = (2ULL | vlSelfRef.__VicoTriggered[0U]);
            vlSelfRef.__VicoTriggered[0U] = (4ULL | vlSelfRef.__VicoTriggered[0U]);
            vlSelfRef.__VicoTriggered[0U] = (8ULL | vlSelfRef.__VicoTriggered[0U]);
        }
    }
#ifdef VL_DEBUG
    if (VL_UNLIKELY(vlSymsp->_vm_contextp__->debug())) {
        Vht943_lcd___024root___dump_triggers__ico(vlSelfRef.__VicoTriggered, "ico"s);
    }
#endif
    __VicoExecute = Vht943_lcd___024root___trigger_anySet__ico(vlSelfRef.__VicoTriggered);
    if (__VicoExecute) {
        {
            // Inlined CFunc: _eval_ico
            if ((4ULL & vlSelfRef.__VicoTriggered[0U])) {
                {
                    // Inlined CFunc: _ico_sequent__TOP__0
                    if ((0U == (IData)(vlSelfRef.profile))) {
                        vlSelfRef.ht943_lcd__DOT__pix_word 
                            = vlSelfRef.ht943_lcd__DOT__pw0;
                        vlSelfRef.ht943_lcd__DOT__seg_word 
                            = vlSelfRef.ht943_lcd__DOT__sw0;
                        vlSelfRef.ht943_lcd__DOT__geo_word 
                            = vlSelfRef.ht943_lcd__DOT__gw0;
                    } else if ((1U == (IData)(vlSelfRef.profile))) {
                        vlSelfRef.ht943_lcd__DOT__pix_word 
                            = vlSelfRef.ht943_lcd__DOT__pw1;
                        vlSelfRef.ht943_lcd__DOT__seg_word 
                            = vlSelfRef.ht943_lcd__DOT__sw1;
                        vlSelfRef.ht943_lcd__DOT__geo_word 
                            = vlSelfRef.ht943_lcd__DOT__gw1;
                    } else if ((2U == (IData)(vlSelfRef.profile))) {
                        vlSelfRef.ht943_lcd__DOT__pix_word 
                            = vlSelfRef.ht943_lcd__DOT__pw2;
                        vlSelfRef.ht943_lcd__DOT__seg_word 
                            = vlSelfRef.ht943_lcd__DOT__sw2;
                        vlSelfRef.ht943_lcd__DOT__geo_word 
                            = vlSelfRef.ht943_lcd__DOT__gw2;
                    } else {
                        vlSelfRef.ht943_lcd__DOT__pix_word 
                            = vlSelfRef.ht943_lcd__DOT__pw3;
                        vlSelfRef.ht943_lcd__DOT__seg_word 
                            = vlSelfRef.ht943_lcd__DOT__sw3;
                        vlSelfRef.ht943_lcd__DOT__geo_word 
                            = vlSelfRef.ht943_lcd__DOT__gw3;
                    }
                    vlSelfRef.ram_addr = (0x000000ffU 
                                          & ((IData)(vlSelfRef.ht943_lcd__DOT__seg_word) 
                                             >> 2U));
                    vlSelfRef.ht943_lcd__DOT__wmt = 
                        (0x000003ffU & ((0x000001ffU 
                                         & (IData)(
                                                   (vlSelfRef.ht943_lcd__DOT__geo_word 
                                                    >> 0x00000019U))) 
                                        - (0x0000000fU 
                                           & (IData)(
                                                     (vlSelfRef.ht943_lcd__DOT__geo_word 
                                                      >> 0x0000000cU)))));
                    vlSelfRef.ht943_lcd__DOT__hmt = 
                        (0x000003ffU & ((0x000001ffU 
                                         & (IData)(
                                                   (vlSelfRef.ht943_lcd__DOT__geo_word 
                                                    >> 0x00000010U))) 
                                        - (0x0000000fU 
                                           & (IData)(
                                                     (vlSelfRef.ht943_lcd__DOT__geo_word 
                                                      >> 8U)))));
                    vlSelfRef.ht943_lcd__DOT__dx = 
                        (0x000003ffU & ((IData)(vlSelfRef.ht943_lcd__DOT__hx2) 
                                        - (0x000001ffU 
                                           & (IData)(
                                                     (vlSelfRef.ht943_lcd__DOT__geo_word 
                                                      >> 0x0000002cU)))));
                    vlSelfRef.ht943_lcd__DOT__dy = 
                        (0x000003ffU & ((IData)(vlSelfRef.ht943_lcd__DOT__hy2) 
                                        - (IData)((vlSelfRef.ht943_lcd__DOT__geo_word 
                                                   >> 0x00000022U))));
                }
            }
        }
    }
    return (__VicoExecute);
}

bool Vht943_lcd___024root___trigger_anySet__act(const VlUnpacked<QData/*63:0*/, 1> &in) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vht943_lcd___024root___trigger_anySet__act\n"); );
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

void Vht943_lcd___024root___nba_sequent__TOP__0(Vht943_lcd___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vht943_lcd___024root___nba_sequent__TOP__0\n"); );
    Vht943_lcd__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    CData/*0:0*/ __Vdly__ht943_lcd__DOT__div2;
    __Vdly__ht943_lcd__DOT__div2 = 0;
    SData/*8:0*/ __Vdly__ht943_lcd__DOT__h_count;
    __Vdly__ht943_lcd__DOT__h_count = 0;
    SData/*9:0*/ __Vdly__ht943_lcd__DOT__v_count;
    __Vdly__ht943_lcd__DOT__v_count = 0;
    CData/*1:0*/ __Vdly__ht943_lcd__DOT__h3;
    __Vdly__ht943_lcd__DOT__h3 = 0;
    CData/*1:0*/ __Vdly__ht943_lcd__DOT__v3;
    __Vdly__ht943_lcd__DOT__v3 = 0;
    CData/*6:0*/ __Vdly__ht943_lcd__DOT__cx;
    __Vdly__ht943_lcd__DOT__cx = 0;
    SData/*8:0*/ __Vdly__ht943_lcd__DOT__cy;
    __Vdly__ht943_lcd__DOT__cy = 0;
    // Body
    __Vdly__ht943_lcd__DOT__div2 = vlSelfRef.ht943_lcd__DOT__div2;
    __Vdly__ht943_lcd__DOT__h3 = vlSelfRef.ht943_lcd__DOT__h3;
    __Vdly__ht943_lcd__DOT__v3 = vlSelfRef.ht943_lcd__DOT__v3;
    __Vdly__ht943_lcd__DOT__cx = vlSelfRef.ht943_lcd__DOT__cx;
    __Vdly__ht943_lcd__DOT__cy = vlSelfRef.ht943_lcd__DOT__cy;
    __Vdly__ht943_lcd__DOT__h_count = vlSelfRef.ht943_lcd__DOT__h_count;
    __Vdly__ht943_lcd__DOT__v_count = vlSelfRef.ht943_lcd__DOT__v_count;
    vlSelfRef.ht943_lcd__DOT__d_hsync = ((6U & ((IData)(vlSelfRef.ht943_lcd__DOT__d_hsync) 
                                                << 1U)) 
                                         | ((0x0188U 
                                             <= (IData)(vlSelfRef.ht943_lcd__DOT__h_count)) 
                                            & (0x01a8U 
                                               > (IData)(vlSelfRef.ht943_lcd__DOT__h_count))));
    vlSelfRef.ht943_lcd__DOT__d_vsync = ((6U & ((IData)(vlSelfRef.ht943_lcd__DOT__d_vsync) 
                                                << 1U)) 
                                         | ((0x0350U 
                                             <= (IData)(vlSelfRef.ht943_lcd__DOT__v_count)) 
                                            & (0x0354U 
                                               > (IData)(vlSelfRef.ht943_lcd__DOT__v_count))));
    vlSelfRef.ht943_lcd__DOT__d_hblank = ((6U & ((IData)(vlSelfRef.ht943_lcd__DOT__d_hblank) 
                                                 << 1U)) 
                                          | (0x0168U 
                                             <= (IData)(vlSelfRef.ht943_lcd__DOT__h_count)));
    vlSelfRef.ht943_lcd__DOT__d_vblank = ((6U & ((IData)(vlSelfRef.ht943_lcd__DOT__d_vblank) 
                                                 << 1U)) 
                                          | (0x0348U 
                                             <= (IData)(vlSelfRef.ht943_lcd__DOT__v_count)));
    vlSelfRef.ht943_lcd__DOT__d_ce = ((6U & ((IData)(vlSelfRef.ht943_lcd__DOT__d_ce) 
                                             << 1U)) 
                                      | (IData)(vlSelfRef.ht943_lcd__DOT__pix_ce));
    vlSelfRef.ht943_lcd__DOT__d_active = ((6U & ((IData)(vlSelfRef.ht943_lcd__DOT__d_active) 
                                                 << 1U)) 
                                          | (IData)(vlSelfRef.ht943_lcd__DOT__active_raw));
    if (vlSelfRef.rst) {
        __Vdly__ht943_lcd__DOT__h_count = 0U;
        __Vdly__ht943_lcd__DOT__v_count = 0U;
        __Vdly__ht943_lcd__DOT__h3 = 0U;
        __Vdly__ht943_lcd__DOT__v3 = 0U;
        __Vdly__ht943_lcd__DOT__cx = 0U;
        __Vdly__ht943_lcd__DOT__cy = 0U;
        __Vdly__ht943_lcd__DOT__div2 = 0U;
        vlSelfRef.ht943_lcd__DOT__pix_ce = 0U;
    } else {
        if (vlSelfRef.ht943_lcd__DOT__pix_ce) {
            if ((0x01dfU == (IData)(vlSelfRef.ht943_lcd__DOT__h_count))) {
                if ((0x036aU == (IData)(vlSelfRef.ht943_lcd__DOT__v_count))) {
                    __Vdly__ht943_lcd__DOT__v_count = 0U;
                    __Vdly__ht943_lcd__DOT__v3 = 0U;
                    __Vdly__ht943_lcd__DOT__cy = 0U;
                } else {
                    __Vdly__ht943_lcd__DOT__v_count 
                        = (0x000003ffU & ((IData)(1U) 
                                          + (IData)(vlSelfRef.ht943_lcd__DOT__v_count)));
                    if ((0x0347U > (IData)(vlSelfRef.ht943_lcd__DOT__v_count))) {
                        if ((2U == (IData)(vlSelfRef.ht943_lcd__DOT__v3))) {
                            __Vdly__ht943_lcd__DOT__cy 
                                = (0x000001ffU & ((IData)(1U) 
                                                  + (IData)(vlSelfRef.ht943_lcd__DOT__cy)));
                            __Vdly__ht943_lcd__DOT__v3 = 0U;
                        } else {
                            __Vdly__ht943_lcd__DOT__v3 
                                = (3U & ((IData)(1U) 
                                         + (IData)(vlSelfRef.ht943_lcd__DOT__v3)));
                        }
                    }
                }
                __Vdly__ht943_lcd__DOT__h_count = 0U;
                __Vdly__ht943_lcd__DOT__h3 = 0U;
                __Vdly__ht943_lcd__DOT__cx = 0U;
            } else {
                __Vdly__ht943_lcd__DOT__h_count = (0x000001ffU 
                                                   & ((IData)(1U) 
                                                      + (IData)(vlSelfRef.ht943_lcd__DOT__h_count)));
                if ((0x0167U > (IData)(vlSelfRef.ht943_lcd__DOT__h_count))) {
                    if ((2U == (IData)(vlSelfRef.ht943_lcd__DOT__h3))) {
                        __Vdly__ht943_lcd__DOT__cx 
                            = (0x0000007fU & ((IData)(1U) 
                                              + (IData)(vlSelfRef.ht943_lcd__DOT__cx)));
                        __Vdly__ht943_lcd__DOT__h3 = 0U;
                    } else {
                        __Vdly__ht943_lcd__DOT__h3 
                            = (3U & ((IData)(1U) + (IData)(vlSelfRef.ht943_lcd__DOT__h3)));
                    }
                }
            }
        }
        __Vdly__ht943_lcd__DOT__div2 = (1U & (~ (IData)(vlSelfRef.ht943_lcd__DOT__div2)));
        vlSelfRef.ht943_lcd__DOT__pix_ce = vlSelfRef.ht943_lcd__DOT__div2;
    }
    if ((0x833fU >= (IData)(vlSelfRef.ht943_lcd__DOT__pix_idx))) {
        vlSelfRef.ht943_lcd__DOT__pw0 = vlSelfRef.ht943_lcd__DOT__pixmap0
            [vlSelfRef.ht943_lcd__DOT__pix_idx];
        vlSelfRef.ht943_lcd__DOT__pw3 = vlSelfRef.ht943_lcd__DOT__pixmap3
            [vlSelfRef.ht943_lcd__DOT__pix_idx];
        vlSelfRef.ht943_lcd__DOT__pw1 = vlSelfRef.ht943_lcd__DOT__pixmap1
            [vlSelfRef.ht943_lcd__DOT__pix_idx];
        vlSelfRef.ht943_lcd__DOT__pw2 = vlSelfRef.ht943_lcd__DOT__pixmap2
            [vlSelfRef.ht943_lcd__DOT__pix_idx];
    } else {
        vlSelfRef.ht943_lcd__DOT__pw0 = 0U;
        vlSelfRef.ht943_lcd__DOT__pw3 = 0U;
        vlSelfRef.ht943_lcd__DOT__pw1 = 0U;
        vlSelfRef.ht943_lcd__DOT__pw2 = 0U;
    }
    vlSelfRef.ht943_lcd__DOT__sw0 = vlSelfRef.ht943_lcd__DOT__segtab0
        [(0x000001ffU & (IData)(vlSelfRef.ht943_lcd__DOT__pix_word))];
    vlSelfRef.ht943_lcd__DOT__sw3 = vlSelfRef.ht943_lcd__DOT__segtab3
        [(0x000001ffU & (IData)(vlSelfRef.ht943_lcd__DOT__pix_word))];
    vlSelfRef.ht943_lcd__DOT__sw1 = vlSelfRef.ht943_lcd__DOT__segtab1
        [(0x000001ffU & (IData)(vlSelfRef.ht943_lcd__DOT__pix_word))];
    vlSelfRef.ht943_lcd__DOT__sw2 = vlSelfRef.ht943_lcd__DOT__segtab2
        [(0x000001ffU & (IData)(vlSelfRef.ht943_lcd__DOT__pix_word))];
    vlSelfRef.ht943_lcd__DOT__gw0 = vlSelfRef.ht943_lcd__DOT__geotab0
        [(0x000001ffU & (IData)(vlSelfRef.ht943_lcd__DOT__pix_word))];
    vlSelfRef.ht943_lcd__DOT__gw1 = vlSelfRef.ht943_lcd__DOT__geotab1
        [(0x000001ffU & (IData)(vlSelfRef.ht943_lcd__DOT__pix_word))];
    vlSelfRef.ht943_lcd__DOT__gw2 = vlSelfRef.ht943_lcd__DOT__geotab2
        [(0x000001ffU & (IData)(vlSelfRef.ht943_lcd__DOT__pix_word))];
    vlSelfRef.ht943_lcd__DOT__gw3 = vlSelfRef.ht943_lcd__DOT__geotab3
        [(0x000001ffU & (IData)(vlSelfRef.ht943_lcd__DOT__pix_word))];
    vlSelfRef.ht943_lcd__DOT__dark = (1U & (((~ ((vlSelfRef.ht943_lcd__DOT__PROFILE_FRAME_X0
                                                  [vlSelfRef.profile] 
                                                  == vlSelfRef.ht943_lcd__DOT__PROFILE_FRAME_X1
                                                  [vlSelfRef.profile]) 
                                                 | (((IData)(vlSelfRef.ht943_lcd__DOT__hx2) 
                                                     >= 
                                                     ((IData)(3U) 
                                                      + vlSelfRef.ht943_lcd__DOT__PROFILE_FRAME_X0
                                                      [vlSelfRef.profile])) 
                                                    & (((IData)(vlSelfRef.ht943_lcd__DOT__hx2) 
                                                        < 
                                                        (vlSelfRef.ht943_lcd__DOT__PROFILE_FRAME_X1
                                                         [vlSelfRef.profile] 
                                                         - (IData)(3U))) 
                                                       & (((IData)(vlSelfRef.ht943_lcd__DOT__hy2) 
                                                           >= 
                                                           ((IData)(3U) 
                                                            + vlSelfRef.ht943_lcd__DOT__PROFILE_FRAME_Y0
                                                            [vlSelfRef.profile])) 
                                                          & ((IData)(vlSelfRef.ht943_lcd__DOT__hy2) 
                                                             < 
                                                             (vlSelfRef.ht943_lcd__DOT__PROFILE_FRAME_Y1
                                                              [vlSelfRef.profile] 
                                                              - (IData)(3U)))))))) 
                                             & (((IData)(vlSelfRef.ht943_lcd__DOT__hx2) 
                                                 >= vlSelfRef.ht943_lcd__DOT__PROFILE_FRAME_X0
                                                 [vlSelfRef.profile]) 
                                                & (((IData)(vlSelfRef.ht943_lcd__DOT__hx2) 
                                                    < vlSelfRef.ht943_lcd__DOT__PROFILE_FRAME_X1
                                                    [vlSelfRef.profile]) 
                                                   & (((IData)(vlSelfRef.ht943_lcd__DOT__hy2) 
                                                       >= vlSelfRef.ht943_lcd__DOT__PROFILE_FRAME_Y0
                                                       [vlSelfRef.profile]) 
                                                      & ((IData)(vlSelfRef.ht943_lcd__DOT__hy2) 
                                                         < vlSelfRef.ht943_lcd__DOT__PROFILE_FRAME_Y1
                                                         [vlSelfRef.profile]))))) 
                                            | (((~ (IData)(vlSelfRef.ht943_lcd__DOT__bg2)) 
                                                & ((IData)(vlSelfRef.ram_data) 
                                                   >> 
                                                   (3U 
                                                    & (IData)(vlSelfRef.ht943_lcd__DOT__seg_word)))) 
                                               & ((~ (IData)(
                                                             (vlSelfRef.ht943_lcd__DOT__geo_word 
                                                              >> 0x00000035U))) 
                                                  | (((((IData)(vlSelfRef.ht943_lcd__DOT__dx) 
                                                        >= 
                                                        (0x000003ffU 
                                                         & ((0x0000000fU 
                                                             & (IData)(
                                                                       (vlSelfRef.ht943_lcd__DOT__geo_word 
                                                                        >> 4U))) 
                                                            + 
                                                            (0x0000000fU 
                                                             & (IData)(
                                                                       (vlSelfRef.ht943_lcd__DOT__geo_word 
                                                                        >> 0x0000000cU)))))) 
                                                       & (((IData)(vlSelfRef.ht943_lcd__DOT__dy) 
                                                           >= 
                                                           (0x000003ffU 
                                                            & ((0x0000000fU 
                                                                & (IData)(vlSelfRef.ht943_lcd__DOT__geo_word)) 
                                                               + 
                                                               (0x0000000fU 
                                                                & (IData)(
                                                                          (vlSelfRef.ht943_lcd__DOT__geo_word 
                                                                           >> 8U)))))) 
                                                          & (((IData)(vlSelfRef.ht943_lcd__DOT__dx) 
                                                              < 
                                                              (0x000003ffU 
                                                               & ((IData)(vlSelfRef.ht943_lcd__DOT__wmt) 
                                                                  - 
                                                                  (0x0000000fU 
                                                                   & (IData)(
                                                                             (vlSelfRef.ht943_lcd__DOT__geo_word 
                                                                              >> 4U)))))) 
                                                             & ((IData)(vlSelfRef.ht943_lcd__DOT__dy) 
                                                                < 
                                                                (0x000003ffU 
                                                                 & ((IData)(vlSelfRef.ht943_lcd__DOT__hmt) 
                                                                    - 
                                                                    (0x0000000fU 
                                                                     & (IData)(vlSelfRef.ht943_lcd__DOT__geo_word)))))))) 
                                                      | (((IData)(vlSelfRef.ht943_lcd__DOT__dx) 
                                                          < 
                                                          (0x0000000fU 
                                                           & (IData)(
                                                                     (vlSelfRef.ht943_lcd__DOT__geo_word 
                                                                      >> 0x0000000cU)))) 
                                                         | (((IData)(vlSelfRef.ht943_lcd__DOT__dy) 
                                                             < 
                                                             (0x0000000fU 
                                                              & (IData)(
                                                                        (vlSelfRef.ht943_lcd__DOT__geo_word 
                                                                         >> 8U)))) 
                                                            | (((IData)(vlSelfRef.ht943_lcd__DOT__dx) 
                                                                >= (IData)(vlSelfRef.ht943_lcd__DOT__wmt)) 
                                                               | ((IData)(vlSelfRef.ht943_lcd__DOT__dy) 
                                                                  >= (IData)(vlSelfRef.ht943_lcd__DOT__hmt)))))) 
                                                     & (((IData)(vlSelfRef.ht943_lcd__DOT__hx2) 
                                                         >= 
                                                         (0x000001ffU 
                                                          & (IData)(
                                                                    (vlSelfRef.ht943_lcd__DOT__geo_word 
                                                                     >> 0x0000002cU)))) 
                                                        & (((IData)(vlSelfRef.ht943_lcd__DOT__dx) 
                                                            < 
                                                            (0x000001ffU 
                                                             & (IData)(
                                                                       (vlSelfRef.ht943_lcd__DOT__geo_word 
                                                                        >> 0x00000019U)))) 
                                                           & (((IData)(vlSelfRef.ht943_lcd__DOT__hy2) 
                                                               >= 
                                                               (0x000003ffU 
                                                                & (IData)(
                                                                          (vlSelfRef.ht943_lcd__DOT__geo_word 
                                                                           >> 0x00000022U)))) 
                                                              & ((IData)(vlSelfRef.ht943_lcd__DOT__dy) 
                                                                 < 
                                                                 (0x000001ffU 
                                                                  & (IData)(
                                                                            (vlSelfRef.ht943_lcd__DOT__geo_word 
                                                                             >> 0x00000010U))))))))))));
    vlSelfRef.ht943_lcd__DOT__h3 = __Vdly__ht943_lcd__DOT__h3;
    vlSelfRef.ht943_lcd__DOT__v3 = __Vdly__ht943_lcd__DOT__v3;
    vlSelfRef.ht943_lcd__DOT__cx = __Vdly__ht943_lcd__DOT__cx;
    vlSelfRef.ht943_lcd__DOT__cy = __Vdly__ht943_lcd__DOT__cy;
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
    vlSelfRef.ht943_lcd__DOT__bg2 = (1U & ((IData)(vlSelfRef.ht943_lcd__DOT__pix_word) 
                                           >> 9U));
    if ((0U == (IData)(vlSelfRef.profile))) {
        vlSelfRef.ht943_lcd__DOT__seg_word = vlSelfRef.ht943_lcd__DOT__sw0;
        vlSelfRef.ht943_lcd__DOT__geo_word = vlSelfRef.ht943_lcd__DOT__gw0;
        vlSelfRef.ht943_lcd__DOT__pix_word = vlSelfRef.ht943_lcd__DOT__pw0;
    } else if ((1U == (IData)(vlSelfRef.profile))) {
        vlSelfRef.ht943_lcd__DOT__seg_word = vlSelfRef.ht943_lcd__DOT__sw1;
        vlSelfRef.ht943_lcd__DOT__geo_word = vlSelfRef.ht943_lcd__DOT__gw1;
        vlSelfRef.ht943_lcd__DOT__pix_word = vlSelfRef.ht943_lcd__DOT__pw1;
    } else if ((2U == (IData)(vlSelfRef.profile))) {
        vlSelfRef.ht943_lcd__DOT__seg_word = vlSelfRef.ht943_lcd__DOT__sw2;
        vlSelfRef.ht943_lcd__DOT__geo_word = vlSelfRef.ht943_lcd__DOT__gw2;
        vlSelfRef.ht943_lcd__DOT__pix_word = vlSelfRef.ht943_lcd__DOT__pw2;
    } else {
        vlSelfRef.ht943_lcd__DOT__seg_word = vlSelfRef.ht943_lcd__DOT__sw3;
        vlSelfRef.ht943_lcd__DOT__geo_word = vlSelfRef.ht943_lcd__DOT__gw3;
        vlSelfRef.ht943_lcd__DOT__pix_word = vlSelfRef.ht943_lcd__DOT__pw3;
    }
    vlSelfRef.ht943_lcd__DOT__hx2 = vlSelfRef.ht943_lcd__DOT__hx1;
    vlSelfRef.ht943_lcd__DOT__hy2 = vlSelfRef.ht943_lcd__DOT__hy1;
    vlSelfRef.ht943_lcd__DOT__div2 = __Vdly__ht943_lcd__DOT__div2;
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
    vlSelfRef.ht943_lcd__DOT__hx1 = vlSelfRef.ht943_lcd__DOT__h_count;
    vlSelfRef.ht943_lcd__DOT__dy = (0x000003ffU & ((IData)(vlSelfRef.ht943_lcd__DOT__hy2) 
                                                   - (IData)(
                                                             (vlSelfRef.ht943_lcd__DOT__geo_word 
                                                              >> 0x00000022U))));
    vlSelfRef.ht943_lcd__DOT__hy1 = vlSelfRef.ht943_lcd__DOT__v_count;
    vlSelfRef.ht943_lcd__DOT__h_count = __Vdly__ht943_lcd__DOT__h_count;
    vlSelfRef.ht943_lcd__DOT__v_count = __Vdly__ht943_lcd__DOT__v_count;
    vlSelfRef.ht943_lcd__DOT__active_raw = ((0x0168U 
                                             > (IData)(vlSelfRef.ht943_lcd__DOT__h_count)) 
                                            & (0x0348U 
                                               > (IData)(vlSelfRef.ht943_lcd__DOT__v_count)));
    vlSelfRef.ht943_lcd__DOT__pix_idx = (0x0000ffffU 
                                         & ((((IData)(0x00000078U) 
                                              * (IData)(vlSelfRef.ht943_lcd__DOT__cy)) 
                                             + (IData)(vlSelfRef.ht943_lcd__DOT__cx)) 
                                            & (- (IData)((IData)(vlSelfRef.ht943_lcd__DOT__active_raw)))));
}

void Vht943_lcd___024root___trigger_orInto__act_vec_vec(VlUnpacked<QData/*63:0*/, 1> &out, const VlUnpacked<QData/*63:0*/, 1> &in) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vht943_lcd___024root___trigger_orInto__act_vec_vec\n"); );
    // Locals
    IData/*31:0*/ n;
    // Body
    n = 0U;
    do {
        out[n] = (out[n] | in[n]);
        n = ((IData)(1U) + n);
    } while ((0U >= n));
}

#ifdef VL_DEBUG
VL_ATTR_COLD void Vht943_lcd___024root___dump_triggers__act(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag);
#endif  // VL_DEBUG

bool Vht943_lcd___024root___eval_phase__act(Vht943_lcd___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vht943_lcd___024root___eval_phase__act\n"); );
    Vht943_lcd__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    {
        // Inlined CFunc: _eval_triggers_vec__act
        vlSelfRef.__VactTriggered[0U] = (QData)((IData)(
                                                        ((IData)(vlSelfRef.clk) 
                                                         & (~ (IData)(vlSelfRef.__Vtrigprevexpr___TOP__clk__1)))));
        vlSelfRef.__Vtrigprevexpr___TOP__clk__1 = vlSelfRef.clk;
    }
#ifdef VL_DEBUG
    if (VL_UNLIKELY(vlSymsp->_vm_contextp__->debug())) {
        Vht943_lcd___024root___dump_triggers__act(vlSelfRef.__VactTriggered, "act"s);
    }
#endif
    Vht943_lcd___024root___trigger_orInto__act_vec_vec(vlSelfRef.__VnbaTriggered, vlSelfRef.__VactTriggered);
    return (0U);
}

void Vht943_lcd___024root___trigger_clear__act(VlUnpacked<QData/*63:0*/, 1> &out) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vht943_lcd___024root___trigger_clear__act\n"); );
    // Locals
    IData/*31:0*/ n;
    // Body
    n = 0U;
    do {
        out[n] = 0ULL;
        n = ((IData)(1U) + n);
    } while ((1U > n));
}

bool Vht943_lcd___024root___eval_phase__nba(Vht943_lcd___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vht943_lcd___024root___eval_phase__nba\n"); );
    Vht943_lcd__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    CData/*0:0*/ __VnbaExecute;
    // Body
    __VnbaExecute = Vht943_lcd___024root___trigger_anySet__act(vlSelfRef.__VnbaTriggered);
    if (__VnbaExecute) {
        {
            // Inlined CFunc: _eval_nba
            if ((1ULL & vlSelfRef.__VnbaTriggered[0U])) {
                Vht943_lcd___024root___nba_sequent__TOP__0(vlSelf);
            }
        }
        Vht943_lcd___024root___trigger_clear__act(vlSelfRef.__VnbaTriggered);
    }
    return (__VnbaExecute);
}

void Vht943_lcd___024root___eval(Vht943_lcd___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vht943_lcd___024root___eval\n"); );
    Vht943_lcd__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    IData/*31:0*/ __VicoIterCount;
    IData/*31:0*/ __VnbaIterCount;
    // Body
    __VicoIterCount = 0U;
    do {
        if (VL_UNLIKELY(((0x00002710U < __VicoIterCount)))) {
#ifdef VL_DEBUG
            Vht943_lcd___024root___dump_triggers__ico(vlSelfRef.__VicoTriggered, "ico"s);
#endif
            VL_FATAL_MT("rtl/ht943_lcd.sv", 34, "", "DIDNOTCONVERGE: Input combinational region did not converge after '--converge-limit' of 10000 tries");
        }
        __VicoIterCount = ((IData)(1U) + __VicoIterCount);
        vlSelfRef.__VicoPhaseResult = Vht943_lcd___024root___eval_phase__ico(vlSelf);
    } while (vlSelfRef.__VicoPhaseResult);
    __VnbaIterCount = 0U;
    do {
        if (VL_UNLIKELY(((0x00002710U < __VnbaIterCount)))) {
#ifdef VL_DEBUG
            Vht943_lcd___024root___dump_triggers__act(vlSelfRef.__VnbaTriggered, "nba"s);
#endif
            VL_FATAL_MT("rtl/ht943_lcd.sv", 34, "", "DIDNOTCONVERGE: NBA region did not converge after '--converge-limit' of 10000 tries");
        }
        __VnbaIterCount = ((IData)(1U) + __VnbaIterCount);
        vlSelfRef.__VactIterCount = 0U;
        do {
            if (VL_UNLIKELY(((0x00002710U < vlSelfRef.__VactIterCount)))) {
#ifdef VL_DEBUG
                Vht943_lcd___024root___dump_triggers__act(vlSelfRef.__VactTriggered, "act"s);
#endif
                VL_FATAL_MT("rtl/ht943_lcd.sv", 34, "", "DIDNOTCONVERGE: Active region did not converge after '--converge-limit' of 10000 tries");
            }
            vlSelfRef.__VactIterCount = ((IData)(1U) 
                                         + vlSelfRef.__VactIterCount);
            vlSelfRef.__VactPhaseResult = Vht943_lcd___024root___eval_phase__act(vlSelf);
        } while (vlSelfRef.__VactPhaseResult);
        vlSelfRef.__VnbaPhaseResult = Vht943_lcd___024root___eval_phase__nba(vlSelf);
    } while (vlSelfRef.__VnbaPhaseResult);
}

#ifdef VL_DEBUG
void Vht943_lcd___024root___eval_debug_assertions(Vht943_lcd___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vht943_lcd___024root___eval_debug_assertions\n"); );
    Vht943_lcd__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if (VL_UNLIKELY(((vlSelfRef.clk & 0xfeU)))) {
        Verilated::overWidthError("clk");
    }
    if (VL_UNLIKELY(((vlSelfRef.rst & 0xfeU)))) {
        Verilated::overWidthError("rst");
    }
    if (VL_UNLIKELY(((vlSelfRef.profile & 0xfcU)))) {
        Verilated::overWidthError("profile");
    }
    if (VL_UNLIKELY(((vlSelfRef.ram_data & 0xf0U)))) {
        Verilated::overWidthError("ram_data");
    }
}
#endif  // VL_DEBUG
