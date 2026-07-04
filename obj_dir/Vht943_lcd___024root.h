// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design internal header
// See Vht943_lcd.h for the primary calling header

#ifndef VERILATED_VHT943_LCD___024ROOT_H_
#define VERILATED_VHT943_LCD___024ROOT_H_  // guard

#include "verilated.h"


class Vht943_lcd__Syms;

class alignas(VL_CACHE_LINE_BYTES) Vht943_lcd___024root final {
  public:

    // DESIGN SPECIFIC STATE
    // Anonymous structures to workaround compiler member-count bugs
    struct {
        VL_IN8(clk,0,0);
        VL_IN8(rst,0,0);
        VL_IN8(profile,1,0);
        VL_OUT8(ram_addr,7,0);
        VL_IN8(ram_data,3,0);
        VL_OUT8(R,7,0);
        VL_OUT8(G,7,0);
        VL_OUT8(B,7,0);
        VL_OUT8(HSync,0,0);
        VL_OUT8(VSync,0,0);
        VL_OUT8(HBlank,0,0);
        VL_OUT8(VBlank,0,0);
        VL_OUT8(ce_pix,0,0);
        CData/*0:0*/ ht943_lcd__DOT__div2;
        CData/*0:0*/ ht943_lcd__DOT__pix_ce;
        CData/*1:0*/ ht943_lcd__DOT__h3;
        CData/*1:0*/ ht943_lcd__DOT__v3;
        CData/*6:0*/ ht943_lcd__DOT__cx;
        CData/*0:0*/ ht943_lcd__DOT__active_raw;
        CData/*0:0*/ ht943_lcd__DOT__bg2;
        CData/*0:0*/ ht943_lcd__DOT__dark;
        CData/*2:0*/ ht943_lcd__DOT__d_hsync;
        CData/*2:0*/ ht943_lcd__DOT__d_vsync;
        CData/*2:0*/ ht943_lcd__DOT__d_hblank;
        CData/*2:0*/ ht943_lcd__DOT__d_vblank;
        CData/*2:0*/ ht943_lcd__DOT__d_active;
        CData/*2:0*/ ht943_lcd__DOT__d_ce;
        CData/*0:0*/ __VstlFirstIteration;
        CData/*0:0*/ __VstlPhaseResult;
        CData/*0:0*/ __Vtrigprevexpr___TOP__clk__0;
        CData/*0:0*/ __Vtrigprevexpr___TOP__rst__0;
        CData/*1:0*/ __Vtrigprevexpr___TOP__profile__0;
        CData/*3:0*/ __Vtrigprevexpr___TOP__ram_data__0;
        CData/*0:0*/ __VicoDidInit;
        CData/*0:0*/ __VicoPhaseResult;
        CData/*0:0*/ __Vtrigprevexpr___TOP__clk__1;
        CData/*0:0*/ __VactPhaseResult;
        CData/*0:0*/ __VnbaPhaseResult;
        SData/*8:0*/ ht943_lcd__DOT__h_count;
        SData/*9:0*/ ht943_lcd__DOT__v_count;
        SData/*8:0*/ ht943_lcd__DOT__cy;
        SData/*15:0*/ ht943_lcd__DOT__pix_idx;
        SData/*9:0*/ ht943_lcd__DOT__pw0;
        SData/*9:0*/ ht943_lcd__DOT__pw1;
        SData/*9:0*/ ht943_lcd__DOT__pw2;
        SData/*9:0*/ ht943_lcd__DOT__pw3;
        SData/*9:0*/ ht943_lcd__DOT__pix_word;
        SData/*9:0*/ ht943_lcd__DOT__sw0;
        SData/*9:0*/ ht943_lcd__DOT__sw1;
        SData/*9:0*/ ht943_lcd__DOT__sw2;
        SData/*9:0*/ ht943_lcd__DOT__sw3;
        SData/*9:0*/ ht943_lcd__DOT__seg_word;
        SData/*8:0*/ ht943_lcd__DOT__hx1;
        SData/*8:0*/ ht943_lcd__DOT__hx2;
        SData/*9:0*/ ht943_lcd__DOT__hy1;
        SData/*9:0*/ ht943_lcd__DOT__hy2;
        SData/*9:0*/ ht943_lcd__DOT__dx;
        SData/*9:0*/ ht943_lcd__DOT__dy;
        SData/*9:0*/ ht943_lcd__DOT__wmt;
        SData/*9:0*/ ht943_lcd__DOT__hmt;
        IData/*31:0*/ __VactIterCount;
        QData/*53:0*/ ht943_lcd__DOT__gw0;
        QData/*53:0*/ ht943_lcd__DOT__gw1;
        QData/*53:0*/ ht943_lcd__DOT__gw2;
    };
    struct {
        QData/*53:0*/ ht943_lcd__DOT__gw3;
        QData/*53:0*/ ht943_lcd__DOT__geo_word;
        VlUnpacked<SData/*9:0*/, 33600> ht943_lcd__DOT__pixmap0;
        VlUnpacked<SData/*9:0*/, 33600> ht943_lcd__DOT__pixmap1;
        VlUnpacked<SData/*9:0*/, 33600> ht943_lcd__DOT__pixmap2;
        VlUnpacked<SData/*9:0*/, 33600> ht943_lcd__DOT__pixmap3;
        VlUnpacked<SData/*9:0*/, 512> ht943_lcd__DOT__segtab0;
        VlUnpacked<SData/*9:0*/, 512> ht943_lcd__DOT__segtab1;
        VlUnpacked<SData/*9:0*/, 512> ht943_lcd__DOT__segtab2;
        VlUnpacked<SData/*9:0*/, 512> ht943_lcd__DOT__segtab3;
        VlUnpacked<QData/*53:0*/, 512> ht943_lcd__DOT__geotab0;
        VlUnpacked<QData/*53:0*/, 512> ht943_lcd__DOT__geotab1;
        VlUnpacked<QData/*53:0*/, 512> ht943_lcd__DOT__geotab2;
        VlUnpacked<QData/*53:0*/, 512> ht943_lcd__DOT__geotab3;
        VlUnpacked<QData/*63:0*/, 1> __VstlTriggered;
        VlUnpacked<QData/*63:0*/, 2> __VicoTriggered;
        VlUnpacked<QData/*63:0*/, 1> __VactTriggered;
        VlUnpacked<QData/*63:0*/, 1> __VnbaTriggered;
    };

    // INTERNAL VARIABLES
    Vht943_lcd__Syms* vlSymsp;
    const char* vlNamep;

    // PARAMETERS
    static constexpr VlUnpacked<SData/*8:0*/, 4> ht943_lcd__DOT__PROFILE_FRAME_X0 = {{
        0U, 0U, 0U, 0U
    }};
    static constexpr VlUnpacked<SData/*9:0*/, 4> ht943_lcd__DOT__PROFILE_FRAME_Y0 = {{
        0x0062U, 0U, 0x0046U, 0U
    }};
    static constexpr VlUnpacked<SData/*8:0*/, 4> ht943_lcd__DOT__PROFILE_FRAME_X1 = {{
        0x00eaU, 0U, 0x0168U, 0U
    }};
    static constexpr VlUnpacked<SData/*9:0*/, 4> ht943_lcd__DOT__PROFILE_FRAME_Y1 = {{
        0x0348U, 0U, 0x0348U, 0U
    }};

    // CONSTRUCTORS
    Vht943_lcd___024root(Vht943_lcd__Syms* symsp, const char* namep);
    ~Vht943_lcd___024root();
    VL_UNCOPYABLE(Vht943_lcd___024root);

    // INTERNAL METHODS
    void __Vconfigure(bool first);
};


#endif  // guard
