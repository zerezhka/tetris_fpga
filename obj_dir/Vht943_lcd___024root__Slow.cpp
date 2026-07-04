// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vht943_lcd.h for the primary calling header

#include "Vht943_lcd__pch.h"

// Parameter definitions for Vht943_lcd___024root
constexpr VlUnpacked<SData/*8:0*/, 4> Vht943_lcd___024root::ht943_lcd__DOT__PROFILE_FRAME_X0;
constexpr VlUnpacked<SData/*9:0*/, 4> Vht943_lcd___024root::ht943_lcd__DOT__PROFILE_FRAME_Y0;
constexpr VlUnpacked<SData/*8:0*/, 4> Vht943_lcd___024root::ht943_lcd__DOT__PROFILE_FRAME_X1;
constexpr VlUnpacked<SData/*9:0*/, 4> Vht943_lcd___024root::ht943_lcd__DOT__PROFILE_FRAME_Y1;


void Vht943_lcd___024root___ctor_var_reset(Vht943_lcd___024root* vlSelf);

Vht943_lcd___024root::Vht943_lcd___024root(Vht943_lcd__Syms* symsp, const char* namep)
 {
    vlSymsp = symsp;
    vlNamep = strdup(namep);
    // Reset structure values
    Vht943_lcd___024root___ctor_var_reset(this);
}

void Vht943_lcd___024root::__Vconfigure(bool first) {
    (void)first;  // Prevent unused variable warning
}

Vht943_lcd___024root::~Vht943_lcd___024root() {
    VL_DO_DANGLING(std::free(const_cast<char*>(vlNamep)), vlNamep);
}
