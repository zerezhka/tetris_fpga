// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Symbol table internal header
//
// Internal details; most calling programs do not need this header,
// unless using verilator public meta comments.

#ifndef VERILATED_VHT943_LCD__SYMS_H_
#define VERILATED_VHT943_LCD__SYMS_H_  // guard

#include "verilated.h"

// INCLUDE MODEL CLASS

#include "Vht943_lcd.h"

// INCLUDE MODULE CLASSES
#include "Vht943_lcd___024root.h"

// SYMS CLASS (contains all model state)
class alignas(VL_CACHE_LINE_BYTES) Vht943_lcd__Syms final : public VerilatedSyms {
  public:
    // INTERNAL STATE
    Vht943_lcd* const __Vm_modelp;
    VlDeleter __Vm_deleter;
    bool __Vm_didInit = false;

    // MODULE INSTANCE STATE
    Vht943_lcd___024root           TOP;

    // CONSTRUCTORS
    Vht943_lcd__Syms(VerilatedContext* contextp, const char* namep, Vht943_lcd* modelp);
    ~Vht943_lcd__Syms();

    // METHODS
    const char* name() const { return TOP.vlNamep; }
};

#endif  // guard
