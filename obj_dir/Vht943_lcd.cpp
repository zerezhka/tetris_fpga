// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Model implementation (design independent parts)

#include "Vht943_lcd__pch.h"

//============================================================
// Constructors

Vht943_lcd::Vht943_lcd(VerilatedContext* _vcontextp__, const char* _vcname__)
    : VerilatedModel{*_vcontextp__}
    , vlSymsp{new Vht943_lcd__Syms(contextp(), _vcname__, this)}
    , clk{vlSymsp->TOP.clk}
    , rst{vlSymsp->TOP.rst}
    , profile{vlSymsp->TOP.profile}
    , ram_addr{vlSymsp->TOP.ram_addr}
    , ram_data{vlSymsp->TOP.ram_data}
    , R{vlSymsp->TOP.R}
    , G{vlSymsp->TOP.G}
    , B{vlSymsp->TOP.B}
    , HSync{vlSymsp->TOP.HSync}
    , VSync{vlSymsp->TOP.VSync}
    , HBlank{vlSymsp->TOP.HBlank}
    , VBlank{vlSymsp->TOP.VBlank}
    , ce_pix{vlSymsp->TOP.ce_pix}
    , rootp{&(vlSymsp->TOP)}
{
    // Register model with the context
    contextp()->addModel(this);
}

Vht943_lcd::Vht943_lcd(const char* _vcname__)
    : Vht943_lcd(Verilated::threadContextp(), _vcname__)
{
}

//============================================================
// Destructor

Vht943_lcd::~Vht943_lcd() {
    delete vlSymsp;
}

//============================================================
// Evaluation function

#ifdef VL_DEBUG
void Vht943_lcd___024root___eval_debug_assertions(Vht943_lcd___024root* vlSelf);
#endif  // VL_DEBUG
void Vht943_lcd___024root___eval_static(Vht943_lcd___024root* vlSelf);
void Vht943_lcd___024root___eval_initial(Vht943_lcd___024root* vlSelf);
void Vht943_lcd___024root___eval_settle(Vht943_lcd___024root* vlSelf);
void Vht943_lcd___024root___eval(Vht943_lcd___024root* vlSelf);

void Vht943_lcd::eval_step() {
    VL_DEBUG_IF(VL_DBG_MSGF("+++++TOP Evaluate Vht943_lcd::eval_step\n"); );
#ifdef VL_DEBUG
    // Debug assertions
    Vht943_lcd___024root___eval_debug_assertions(&(vlSymsp->TOP));
#endif  // VL_DEBUG
    vlSymsp->__Vm_deleter.deleteAll();
    if (VL_UNLIKELY(!vlSymsp->__Vm_didInit)) {
        VL_DEBUG_IF(VL_DBG_MSGF("+ Initial\n"););
        Vht943_lcd___024root___eval_static(&(vlSymsp->TOP));
        Vht943_lcd___024root___eval_initial(&(vlSymsp->TOP));
        Vht943_lcd___024root___eval_settle(&(vlSymsp->TOP));
        vlSymsp->__Vm_didInit = true;
    }
    VL_DEBUG_IF(VL_DBG_MSGF("+ Eval\n"););
    Vht943_lcd___024root___eval(&(vlSymsp->TOP));
    // Evaluate cleanup
    Verilated::endOfEval(vlSymsp->__Vm_evalMsgQp);
}

//============================================================
// Events and timing
bool Vht943_lcd::eventsPending() { return false; }

uint64_t Vht943_lcd::nextTimeSlot() {
    VL_FATAL_MT(__FILE__, __LINE__, "", "No delays in the design");
    return 0;
}

//============================================================
// Utilities

const char* Vht943_lcd::name() const {
    return vlSymsp->name();
}

//============================================================
// Invoke final blocks

void Vht943_lcd___024root___eval_final(Vht943_lcd___024root* vlSelf);

VL_ATTR_COLD void Vht943_lcd::final() {
    contextp()->executingFinal(true);
    Vht943_lcd___024root___eval_final(&(vlSymsp->TOP));
    contextp()->executingFinal(false);
}

//============================================================
// Implementations of abstract methods from VerilatedModel

const char* Vht943_lcd::hierName() const { return vlSymsp->name(); }
const char* Vht943_lcd::modelName() const { return "Vht943_lcd"; }
unsigned Vht943_lcd::threads() const { return 1; }
void Vht943_lcd::prepareClone() const { contextp()->prepareClone(); }
void Vht943_lcd::atClone() const {
    contextp()->threadPoolpOnClone();
}
