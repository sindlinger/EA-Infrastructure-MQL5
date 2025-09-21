//+------------------------------------------------------------------+
//|                                  EA-HedgeLine_v7.1_Modular       |
//|              Sistema HedgeLine v7.1 - Métodos em Arquivos        |
//|                                  Copyright 2025, HedgeLine EA    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, HedgeLine EA"
#property link      "https://www.hedgeline.com"
#property version   "7.10"
#property strict

//+------------------------------------------------------------------+
//| MUDANÇAS v7.1:                                                   |
//| - Métodos movidos para arquivos separados (.mqh)                |
//| - BaseMethod.mqh contém interfaces                               |
//| - HedgeLineMethod.mqh contém método HedgeLine                   |
//| - SupDemMethod.mqh contém método auxiliar S/R                   |
//| - Estrutura totalmente modular para fácil expansão              |
//+------------------------------------------------------------------+

// Includes padrão do MT5
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Trade/DealInfo.mqh>

// Includes modulares do HedgeLine v7 (diretório separado)
#include <HedgeLine_v7/TrackingManager_v7.mqh>  // Versão v7 com métodos adicionais
#include <HedgeLine_v7/SpreadManager_v7.mqh>    // Vers\u00e3o v7
#include <HedgeLine_v7/StateManager_v7.mqh>     // Versão v7
#include <HedgeLine_v7/OrderManager_v7.mqh>     // Versão v7 que usa TrackingManager_v7
#include <HedgeLine_v7/DistanceControl_v7.mqh>  // Versão v7
#include <HedgeLine_v7/PanelManager_v7.mqh>     // Versão v7
#include <HedgeLine_v7/ReversalManager_v7.mqh>  // Vers\u00e3o v7 que usa TrackingManager_v7

// NOVOS Includes de Métodos Modulares
#include <HedgeLine_v7/Methods/BaseMethod.mqh>      // Interfaces
#include <HedgeLine_v7/Methods/HedgeLineMethod.mqh> // Método HedgeLine
#include <HedgeLine_v7/Methods/SupDemMethod.mqh>    // Método Auxiliar S/R

//+------------------------------------------------------------------+
//| ENUMs para Métodos Modulares                                    |
//+------------------------------------------------------------------+
enum ENUM_MAIN_METHOD {
    METHOD_HEDGELINE,       // HedgeLine (Original)
    // METHOD_BREAKOUT,     // Futuro: Breakout Strategy
    // METHOD_SCALPER,      // Futuro: Scalping Strategy
    // METHOD_TREND,        // Futuro: Trend Following
};

enum ENUM_AUX_METHOD {
    AUX_NONE,              // Nenhum
    AUX_SUPDEM_VOLBASED,   // Suporte/Resistência Volume-Based
    // AUX_PIVOTS,         // Futuro: Pivot Points
    // AUX_FIBONACCI,      // Futuro: Fibonacci Levels
};

//+------------------------------------------------------------------+
//| Parâmetros de Entrada                                           |
//+------------------------------------------------------------------+
input group "=== SELEÇÃO DE MÉTODOS ==="
input ENUM_MAIN_METHOD InpMainMethod   = METHOD_HEDGELINE;    // 📊 Método Principal de Trading
input ENUM_AUX_METHOD  InpAuxMethod1   = AUX_NONE;            // 🔧 Método Auxiliar 1

input group "=== Configurações Principais ==="
input double   InpLotSize              = 0.01;      // Volume (Lotes)

input group "=== TP/SL Dinâmico com ATR ==="
input bool     InpUseDynamicTPSL       = true;      // ⭐ Usar TP/SL Dinâmico baseado em ATR
input double   InpDynamicTPMultiplier  = 2.5;       // Multiplicador ATR para TP
input double   InpDynamicSLMultiplier  = 1.2;       // Multiplicador ATR para SL
input double   InpMinRiskRewardRatio   = 1.5;       // Risk/Reward Mínimo
input int      InpMinTP                = 20;        // TP Mínimo em pontos
input int      InpMaxTP                = 200;       // TP Máximo em pontos
input int      InpMinSL                = 15;        // SL Mínimo em pontos
input int      InpMaxSL                = 100;       // SL Máximo em pontos

input group "=== Configurações ATR ==="
input bool     InpUseATR               = true;      // Usar ATR para Distâncias
input double   InpATRMultiplier        = 1.5;       // Multiplicador ATR
input int      InpATRPeriod            = 14;        // Período do ATR

input group "=== TP/SL Fixo ==="
input int      InpFixedDistance        = 100;       // Distância Fixa (pontos)
input int      InpFixedTP              = 70;        // TP Fixo (pontos)
input int      InpFixedSL              = 50;        // SL Fixo (pontos)

input group "=== Configurações SupDem (Auxiliar) ==="
input bool     InpUseSupDemFilter      = true;      // Usar filtro de Suporte/Resistência
input int      InpSupDemPeriod         = 50;        // Período para análise S/R
input double   InpSupDemStrength       = 2.0;       // Força mínima do nível (1-5)
input double   InpSupDemDistance       = 20;        // Distância mínima do nível (pontos)

input group "=== Controle de Reversões ==="
input bool     InpUseReverse           = true;      // Usar Stop Reverse
input int      InpMaxReversals         = 1;         // Máximo de Reversões
input double   InpReversalLotMultiplier = 1.0;      // Multiplicador de Lote

input group "=== Gestão de Risco ==="
input double   InpMaxDailyLoss         = 50.0;      // Perda Máxima Diária ($)
input double   InpMaxDailyProfit       = 100.0;     // Lucro Máximo Diário ($)
input int      InpMaxDailyTrades       = 100;       // Máximo de Trades por Dia

input group "=== Filtros ==="
input bool     InpUseSpreadFilter      = true;      // Usar Filtro de Spread
input int      InpMaxSpread            = 100;       // Spread Máximo (pontos)
input bool     InpUseTimeFilter        = false;     // Usar Filtro de Horário
input string   InpStartTime            = "09:00";   // Horário de Início
input string   InpEndTime              = "17:00";   // Horário de Término

input group "=== Sistema ==="
input int      InpMagicNumber          = 20240101;  // Magic Number
input string   InpComment              = "HedgeLine_v7.1"; // Comentário
input string   InpStateFile            = "HedgeLine_State.csv"; // Arquivo de Estado
input string   InpTrackingFile         = "HedgeLine_Tracking.csv"; // Arquivo de Rastreamento

input group "=== Debug ==="
input bool     InpDebugMain            = true;      // Debug EA Principal
input bool     InpDebugMethod          = true;      // Debug Métodos de Trading
input bool     InpDebugAuxiliar        = true;      // Debug Métodos Auxiliares
input bool     InpDebugDynamic         = true;      // Debug TP/SL Dinâmico
input bool     InpShowPanel            = true;      // Mostrar Painel

input group "=== Fechamento de Fim de Dia ==="
input bool     InpCloseAllEndDay       = true;      // Fechar todas as ordens no fim do dia
input string   InpCloseTime            = "23:50";   // Horário para fechar ordens

//+------------------------------------------------------------------+
//| Objetos Globais                                                 |
//+------------------------------------------------------------------+
CTrackingManager  trackingMgr;
CSpreadManager    spreadMgr;
CStateManager     stateMgr;
COrderManager     orderMgr;
CDistanceControl  distanceMgr;
CPanelManager     panelMgr;
CReversalManager  reversalMgr;

CTrade         trade;
CSymbolInfo    symbolInfo;

// Variáveis de controle
datetime       lastBarTime = 0;
bool           systemReady = false;
int            tickCounter = 0;

// Variáveis para métodos
double         currentATR = 0;
double         lastCalculatedTP = 0;
double         lastCalculatedSL = 0;

// Ponteiros para Métodos
IMainMethod* mainMethod = NULL;
IAuxMethod* auxMethod1 = NULL;

//+------------------------------------------------------------------+
//| Inicializar Métodos Selecionados                                |
//+------------------------------------------------------------------+
bool InitializeMethods() {
    // Inicializar método principal
    switch(InpMainMethod) {
        case METHOD_HEDGELINE:
            mainMethod = new CHedgeLineMethod();
            break;
        // Futuros métodos podem ser adicionados aqui
        default:
            Print("❌ Método principal inválido!");
            return false;
    }

    if(mainMethod != NULL) {
        if(!mainMethod.Init(Symbol(), Period(), InpDebugMethod)) {
            Print("❌ Falha ao inicializar método principal");
            return false;
        }

        // Configurar Distance Manager no método
        mainMethod.SetDistanceManager(GetPointer(distanceMgr));

        Print("✅ Método Principal: ", mainMethod.GetMethodName());
    }

    // Inicializar método auxiliar 1
    switch(InpAuxMethod1) {
        case AUX_NONE:
            Print("ℹ️ Método Auxiliar 1: Nenhum");
            break;

        case AUX_SUPDEM_VOLBASED: {
            auxMethod1 = new CSupDemVolBased();

            // Configurar parâmetros
            // Em MQL5 não há dynamic_cast, então fazer cast direto
            CSupDemVolBased* supdem = (CSupDemVolBased*)auxMethod1;
            if(supdem != NULL) {
                supdem.SetParameters(InpSupDemPeriod, InpSupDemStrength,
                                    InpSupDemDistance, InpUseSupDemFilter);
            }

            if(auxMethod1.Init(Symbol(), Period(), InpDebugAuxiliar)) {
                Print("✅ Método Auxiliar 1: ", auxMethod1.GetMethodName());
            }
            break;
        }
    }

    return true;
}

//+------------------------------------------------------------------+
//| Calcular TP/SL Dinâmicos                                        |
//+------------------------------------------------------------------+
void CalculateDynamicTPSL(double &tpPoints, double &slPoints) {
    double atrArray[];
    ArraySetAsSeries(atrArray, true);
    int atrHandle = iATR(Symbol(), Period(), InpATRPeriod);

    if(atrHandle != INVALID_HANDLE) {
        if(CopyBuffer(atrHandle, 0, 0, 1, atrArray) > 0) {
            currentATR = atrArray[0];
            double point = symbolInfo.Point();
            double atrInPoints = currentATR / point;

            if(InpUseDynamicTPSL) {
                double calculatedTP = atrInPoints * InpDynamicTPMultiplier;
                double calculatedSL = atrInPoints * InpDynamicSLMultiplier;

                if(calculatedTP < calculatedSL * InpMinRiskRewardRatio) {
                    calculatedTP = calculatedSL * InpMinRiskRewardRatio;
                }

                tpPoints = MathMax(InpMinTP, MathMin(InpMaxTP, calculatedTP));
                slPoints = MathMax(InpMinSL, MathMin(InpMaxSL, calculatedSL));

                lastCalculatedTP = tpPoints;
                lastCalculatedSL = slPoints;

                if(InpDebugDynamic) {
                    Print("📊 TP/SL DINÂMICO:");
                    Print("  ATR: ", DoubleToString(currentATR, 5));
                    Print("  TP: ", tpPoints, " SL: ", slPoints);
                    Print("  Risk/Reward: 1:", DoubleToString(tpPoints/slPoints, 2));
                }
            } else {
                tpPoints = InpFixedTP;
                slPoints = InpFixedSL;
            }
        } else {
            tpPoints = InpFixedTP;
            slPoints = InpFixedSL;
        }
        IndicatorRelease(atrHandle);
    } else {
        tpPoints = InpFixedTP;
        slPoints = InpFixedSL;
    }
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    Print("=== EA-HedgeLine v7.1 MODULAR INICIANDO ===");
    Print("⚙️ Métodos em Arquivos Separados");

    // Inicializar símbolo
    if(!symbolInfo.Name(Symbol())) {
        Print("ERRO: Não foi possível inicializar símbolo");
        return INIT_FAILED;
    }

    // Configurar trade
    trade.SetExpertMagicNumber(InpMagicNumber);
    trade.SetDeviationInPoints(10);
    trade.SetTypeFilling(ORDER_FILLING_IOC);

    // Inicializar módulos do sistema
    Print("Inicializando módulos do sistema...");

    // TrackingManager
    if(!trackingMgr.Init(InpTrackingFile, InpDebugMain, true, true, InpMagicNumber, Symbol())) {
        Print("ERRO: TrackingManager");
        return INIT_FAILED;
    }

    // Outros módulos
    spreadMgr.Init(InpUseSpreadFilter, InpMaxSpread, false);
    stateMgr.Init(InpStateFile, 5, false);
    stateMgr.ResetState();
    orderMgr.Init(Symbol(), InpMagicNumber, false, &trackingMgr);

    double minDist = InpUseATR ? 50 : InpFixedDistance;
    double maxDist = InpUseATR ? 500 : InpFixedDistance * 3;
    if(!distanceMgr.Init(Symbol(), Period(), InpATRPeriod, InpATRMultiplier, minDist, maxDist, false)) {
        Print("ERRO: DistanceControl");
        return INIT_FAILED;
    }

    reversalMgr.Init(Symbol(), InpUseReverse, InpMaxReversals, InpReversalLotMultiplier,
                     InpMagicNumber, InpComment, false, GetPointer(trackingMgr));

    panelMgr.Init(Symbol(), InpMagicNumber, InpShowPanel, InpDebugMain);
    panelMgr.ConnectModules(GetPointer(trackingMgr), GetPointer(reversalMgr));
    panelMgr.Update();  // UpdateState não existe, usar Update

    // INICIALIZAR MÉTODOS
    if(!InitializeMethods()) {
        return INIT_FAILED;
    }

    systemReady = true;
    Print("=== Sistema v7.1 Modular PRONTO ===");

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    Print("=== EA-HedgeLine v7.1 ENCERRANDO ===");

    // Limpar métodos
    if(mainMethod != NULL) {
        delete mainMethod;
        mainMethod = NULL;
    }
    if(auxMethod1 != NULL) {
        delete auxMethod1;
        auxMethod1 = NULL;
    }

    stateMgr.SaveState(true);
    trackingMgr.Deinit();
    panelMgr.Destroy();  // RemovePanel não existe, usar Destroy

    Print("=== Sistema encerrado ===");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    if(!systemReady) return;

    tickCounter++;

    // Processar método principal
    if(mainMethod != NULL) {
        mainMethod.OnTick();
    }

    // Verificação periódica de reversões
    if(tickCounter % 10 == 0 && InpUseReverse) {
        static datetime lastPeriodicCheck = 0;
        if(TimeCurrent() - lastPeriodicCheck > 5) {
            bool periodicReversal = reversalMgr.CheckRecentStopLossesAndReverse();
            if(periodicReversal) {
                ReversalState revState = reversalMgr.GetState();
                stateMgr.UpdateReversals(revState.currentReversals, revState.inReversal);
            }
            lastPeriodicCheck = TimeCurrent();
        }
    }

    // Verificar nova barra
    datetime currentBarTime = iTime(Symbol(), Period(), 0);
    if(currentBarTime == lastBarTime) return;
    lastBarTime = currentBarTime;

    // Verificações de sistema
    CheckEndOfDayClose();

    SystemState currentState = stateMgr.GetState();

    // Verificar limites
    double dailyProfit = trackingMgr.GetDailyProfit();
    if(dailyProfit <= -InpMaxDailyLoss ||
       dailyProfit >= InpMaxDailyProfit ||
       currentState.dailyTrades >= InpMaxDailyTrades) {
        return;
    }

    // Verificar horário
    if(InpUseTimeFilter && !IsWithinTradingTime()) return;

    // Verificar spread
    if(!spreadMgr.ValidateSpread()) return;  // CheckSpread n\u00e3o existe, usar ValidateSpread

    // NOVA LÓGICA PER-SIDE: Não bloquear se temos ordens/posições
    // Apenas atualizar o painel se já temos algo
    if(orderMgr.HasBuySideOrders() || orderMgr.HasSellSideOrders()) {
        if(tickCounter % 10 == 0) {
            panelMgr.Update();  // UpdateState não existe, usar Update
        }
    }

    // PROCESSAR SINAL DO MÉTODO PRINCIPAL (agora sempre processa, a lógica per-side está no OrderManager)
    ProcessMethodSignal();

    // Atualizar painel
    if(tickCounter % 10 == 0) {
        panelMgr.Update();  // UpdateState não existe, usar Update
    }
}

//+------------------------------------------------------------------+
//| Processar Sinal do Método Principal                             |
//+------------------------------------------------------------------+
void ProcessMethodSignal() {
    if(mainMethod == NULL) return;

    // Obter sinal do método principal
    TradingSignal signal = mainMethod.GetSignal();

    if(!signal.hasSignal) {
        if(InpDebugMethod && signal.reason != "") {
            Print("📊 Sem sinal: ", signal.reason);
        }
        return;
    }

    // Aplicar filtro do método auxiliar
    if(auxMethod1 != NULL) {
        auxMethod1.FilterSignal(signal);

        if(InpDebugAuxiliar) {
            Print("🔧 Sinal filtrado por ", auxMethod1.GetMethodName());
            Print("  Confiança ajustada: ", signal.confidence, "%");
        }
    }

    // Se for método HedgeLine, usar lógica original de ordens pendentes
    if(InpMainMethod == METHOD_HEDGELINE) {
        ProcessHedgeLineEntry();
    }
    // Futuros métodos usarão a estrutura TradingSignal diretamente
}

//+------------------------------------------------------------------+
//| Processar Entrada HedgeLine (Original)                          |
//+------------------------------------------------------------------+
void ProcessHedgeLineEntry() {
    double distance = InpUseATR ? distanceMgr.CalculateDynamicDistance() : InpFixedDistance;

    double tpPoints, slPoints;
    CalculateDynamicTPSL(tpPoints, slPoints);

    double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);

    if(InpDebugMain) {
        Print("\n=== PROCESSANDO HEDGELINE ===");
        Print("  Distance: ", distance);
        Print("  TP: ", tpPoints, " SL: ", slPoints);
        Print("  Bid: ", bid, " Ask: ", ask);
    }

    // Usar o OrderManager com a nova lógica per-side
    // O OrderManager agora verifica cada lado independentemente
    bool success = orderMgr.CreatePendingOrders(bid, ask, distance, slPoints, tpPoints, InpLotSize);

    if(success) {
        // distanceMgr.RegisterTrade(); // Method not available in current DistanceControl
        stateMgr.IncrementDailyTrades();
        stateMgr.UpdateReversals(0, false);

        if(InpDebugMain) {
            Print("✅ Ordens criadas com sucesso (lógica per-side)");
        }
    } else {
        if(InpDebugMain) {
            Print("⚠️ Nenhuma ordem criada (ambos os lados já têm ordens/posições)");
        }
    }
}

//+------------------------------------------------------------------+
//| OnTrade function                                                |
//+------------------------------------------------------------------+
void OnTrade() {
    if(!systemReady) return;

    // Processar método
    if(mainMethod != NULL) {
        mainMethod.OnTrade();
    }

    // Lógica padrão de processamento
    ENUM_POSITION_TYPE posType = orderMgr.GetCurrentPositionType();
    reversalMgr.UpdateLastPositionType(posType);
    reversalMgr.UpdateCurrentLotSize(InpLotSize);

    ulong lastDeal = HistoryDealGetTicket(HistoryDealsTotal() - 1);
    if(lastDeal > 0) {
        HistoryDealSelect(lastDeal);
        double lastProfit = HistoryDealGetDouble(lastDeal, DEAL_PROFIT);
        double lastSwap = HistoryDealGetDouble(lastDeal, DEAL_SWAP);
        double lastCommission = HistoryDealGetDouble(lastDeal, DEAL_COMMISSION);
        double totalResult = lastProfit + lastSwap + lastCommission;

        ENUM_DEAL_REASON reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(lastDeal, DEAL_REASON);

        if(reason == DEAL_REASON_SL && InpUseReverse) {
            bool reversalExecuted = reversalMgr.ProcessTradeEvent();
            if(reversalExecuted) {
                ReversalState revState = reversalMgr.GetState();
                stateMgr.UpdateReversals(revState.currentReversals, revState.inReversal);
            }
        }
        else if(lastProfit > 0 || reason == DEAL_REASON_TP) {
            reversalMgr.ResetReversals();
            stateMgr.UpdateReversals(0, false);
        }

        stateMgr.UpdateLastCloseProfit(totalResult);
    }

    if(InpUseReverse) {
        bool additionalReversal = reversalMgr.CheckRecentStopLossesAndReverse();
        if(additionalReversal) {
            ReversalState revState = reversalMgr.GetState();
            stateMgr.UpdateReversals(revState.currentReversals, revState.inReversal);
        }
    }

    if(orderMgr.HasPosition()) {
        orderMgr.DeleteAllOrders();
    }

    panelMgr.Update();  // UpdateState não existe, usar Update
}

//+------------------------------------------------------------------+
//| OnChartEvent function                                            |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
    // panelMgr.OnChartEvent não existe - remover chamada
    if(id == CHARTEVENT_KEYDOWN && lparam == 'P') {
        panelMgr.ToggleVisibility();  // TogglePanel não existe, usar ToggleVisibility
    }
}

//+------------------------------------------------------------------+
//| Funções Auxiliares                                              |
//+------------------------------------------------------------------+
bool IsWithinTradingTime() {
    MqlDateTime now;
    TimeToStruct(TimeCurrent(), now);
    string currentTime = StringFormat("%02d:%02d", now.hour, now.min);
    return (currentTime >= InpStartTime && currentTime <= InpEndTime);
}

void CheckEndOfDayClose() {
    if(!InpCloseAllEndDay) return;
    MqlDateTime now;
    TimeToStruct(TimeCurrent(), now);
    string currentTime = StringFormat("%02d:%02d", now.hour, now.min);
    if(currentTime >= InpCloseTime) {
        orderMgr.CloseAllPositions();
        orderMgr.DeleteAllOrders();
    }
}

//+------------------------------------------------------------------+