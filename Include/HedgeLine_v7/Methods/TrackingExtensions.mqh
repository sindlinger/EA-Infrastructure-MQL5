//+------------------------------------------------------------------+
//|                                         TrackingExtensions.mqh   |
//|                   Extensões para TrackingManager v7              |
//|                                  Copyright 2025, HedgeLine EA    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, HedgeLine EA"
#property link      "https://www.hedgeline.com"
#property version   "1.00"

// Este arquivo adiciona métodos de compatibilidade sem modificar o original

//+------------------------------------------------------------------+
//| Funções auxiliares para compatibilidade                         |
//+------------------------------------------------------------------+

// Wrapper para OnPendingOrderPlacement
void TrackingOnPendingOrderPlacement(CTrackingManager &mgr, string orderType,
                                     double price, double volume,
                                     double tp, double sl, string comment) {
    // Se o TrackingManager original não tem este método,
    // apenas registrar no log
    if(mgr.m_config.debugMode) {
        Print("[TrackingExt] Ordem pendente: ", orderType,
              " Price=", DoubleToString(price, 5),
              " Vol=", DoubleToString(volume, 2));
    }
}

// Wrapper para OnOrderError
void TrackingOnOrderError(CTrackingManager &mgr, string orderType,
                          int errorCode, string errorDesc) {
    if(mgr.m_config.debugMode || mgr.m_config.writeToTerminal) {
        Print("[TrackingExt] ERRO: ", orderType,
              " - Código: ", errorCode, " - ", errorDesc);
    }
}

// Wrapper para OnPendingOrderSuccess
void TrackingOnPendingOrderSuccess(CTrackingManager &mgr, string orderType, ulong ticket) {
    mgr.RegisterOrder(ticket, "", false);  // false = ordem pendente

    if(mgr.m_config.debugMode) {
        Print("[TrackingExt] ", orderType, " sucesso - Ticket #", ticket);
    }
}

// Wrapper para GetDailyProfit
double TrackingGetDailyProfit(CTrackingManager &mgr) {
    double dailyProfit = 0.0;
    datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));

    // Calcular baseado nas posições existentes
    int total = PositionsTotal();
    for(int i = 0; i < total; i++) {
        CPositionInfo posInfo;
        if(posInfo.SelectByIndex(i)) {
            if(mgr.m_config.magicNumber == 0 || posInfo.Magic() == mgr.m_config.magicNumber) {
                if(mgr.m_config.symbol == "" || posInfo.Symbol() == mgr.m_config.symbol) {
                    dailyProfit += posInfo.Profit() + posInfo.Swap() + posInfo.Commission();
                }
            }
        }
    }

    return dailyProfit;
}

//+------------------------------------------------------------------+