//+------------------------------------------------------------------+
//|                                          EA-HedgeLine_v6         |
//|                Sistema HedgeLine v6 - TP/SL Dinâmicos com ATR    |
//|                                  Copyright 2025, HedgeLine EA    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, HedgeLine EA"
#property link      "https://www.hedgeline.com"
#property version   "6.00"
#property strict

//+------------------------------------------------------------------+
//| MUDANÇAS v6:                                                     |
//| - TP/SL DINÂMICOS baseados em ATR (adaptativo à volatilidade)   |
//| - Modo híbrido: pode usar fixo ou dinâmico                      |
//| - Multiplicadores separados para TP e SL                        |
//| - Limites mínimos e máximos de segurança                        |
//| - Risk/Reward ratio inteligente                                 |
//| - Ajuste automático em alta/baixa volatilidade                  |
//+------------------------------------------------------------------+

// Includes padrão do MT5
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Trade/DealInfo.mqh>

// Includes modulares do HedgeLine
#include <HedgeLine/TrackingManager.mqh>
#include <HedgeLine/SpreadManager.mqh>
#include <HedgeLine/StateManager.mqh>
#include <HedgeLine/OrderManager.mqh>
#include <HedgeLine/DistanceControl.mqh>
#include <HedgeLine/PanelManager.mqh>
#include <HedgeLine/ReversalManager.mqh>

//+------------------------------------------------------------------+
//| Parâmetros de Entrada                                           |
//+------------------------------------------------------------------+
input group "=== Configurações Principais ==="
input double   InpLotSize              = 0.01;      // Volume (Lotes)

input group "=== TP/SL Dinâmico com ATR (NOVO v6) ==="
input bool     InpUseDynamicTPSL       = true;      // ⭐ Usar TP/SL Dinâmico baseado em ATR
input double   InpDynamicTPMultiplier  = 2.5;       // Multiplicador ATR para TP (2.0-4.0 recomendado)
input double   InpDynamicSLMultiplier  = 1.2;       // Multiplicador ATR para SL (1.0-2.0 recomendado)
input double   InpMinRiskRewardRatio   = 1.5;       // Risk/Reward Mínimo (TP deve ser X vezes o SL)
input int      InpMinTP                = 20;        // TP Mínimo em pontos
input int      InpMaxTP                = 200;       // TP Máximo em pontos
input int      InpMinSL                = 15;        // SL Mínimo em pontos
input int      InpMaxSL                = 100;       // SL Máximo em pontos

input group "=== Configurações ATR ==="
input bool     InpUseATR               = true;      // Usar ATR para Distâncias de Entrada
input double   InpATRMultiplier        = 1.5;       // Multiplicador ATR para Distância
input int      InpATRPeriod            = 14;        // Período do ATR

input group "=== TP/SL Fixo (usado quando Dinâmico está OFF) ==="
input int      InpFixedDistance        = 100;       // Distância Fixa (pontos)
input int      InpFixedTP              = 70;        // TP Fixo (pontos)
input int      InpFixedSL              = 50;        // SL Fixo (pontos)
input double   InpTPMultiplier         = 1.0;       // TP como % da distância (modo antigo)
input double   InpSLMultiplier         = 0.5;       // SL como % da distância (modo antigo)

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
input string   InpComment              = "HedgeLine_v6"; // Comentário
input string   InpStateFile            = "HedgeLine_State.csv"; // Arquivo de Estado
input string   InpTrackingFile         = "HedgeLine_Tracking.csv"; // Arquivo de Rastreamento

input group "=== Debug Individual por Módulo ==="
input bool     InpDebugMain            = true;      // Debug EA Principal
input bool     InpDebugSpread          = false;     // Debug SpreadManager
input bool     InpDebugState           = false;     // Debug StateManager
input bool     InpDebugOrder           = true;      // Debug OrderManager
input bool     InpDebugDistance        = true;      // Debug DistanceControl
input bool     InpDebugDynamic         = true;      // ⭐ Debug TP/SL Dinâmico
input bool     InpDebugTicks           = false;     // Debug Contador de Ticks

// Painel
input bool     InpShowPanel            = true;      // Mostrar Painel (tecla P para alternar)

// Fechamento de fim de dia
input group "=== Fechamento de Fim de Dia ==="
input bool     InpCloseAllEndDay       = true;      // Fechar todas as ordens no fim do dia
input string   InpCloseTime            = "23:50";   // Horário para fechar ordens (HH:MM)

//+------------------------------------------------------------------+
//| Objetos Globais dos Módulos                                     |
//+------------------------------------------------------------------+
CTrackingManager  trackingMgr;
CSpreadManager    spreadMgr;
CStateManager     stateMgr;
COrderManager     orderMgr;
CDistanceControl  distanceMgr;
CPanelManager     panelMgr;
CReversalManager  reversalMgr;

// Objetos padrão
CTrade         trade;
CSymbolInfo    symbolInfo;

// Variáveis de controle
datetime       lastBarTime = 0;
bool           systemReady = false;
int            debugFileHandle = INVALID_HANDLE;
int            tickCounter = 0;

// Variáveis para ATR e cálculos dinâmicos
double         currentATR = 0;
double         lastCalculatedTP = 0;
double         lastCalculatedSL = 0;

//+------------------------------------------------------------------+
//| Função para calcular TP/SL Dinâmicos baseados em ATR            |
//+------------------------------------------------------------------+
void CalculateDynamicTPSL(double &tpPoints, double &slPoints) {
    // Calcular ATR atual
    double atrArray[];
    ArraySetAsSeries(atrArray, true);
    int atrHandle = iATR(Symbol(), Period(), InpATRPeriod);

    if(atrHandle != INVALID_HANDLE) {
        if(CopyBuffer(atrHandle, 0, 0, 1, atrArray) > 0) {
            currentATR = atrArray[0];

            // Converter ATR para pontos
            double point = symbolInfo.Point();
            double atrInPoints = currentATR / point;

            if(InpUseDynamicTPSL) {
                // MODO DINÂMICO: Calcular TP e SL baseados em ATR
                double calculatedTP = atrInPoints * InpDynamicTPMultiplier;
                double calculatedSL = atrInPoints * InpDynamicSLMultiplier;

                // Aplicar Risk/Reward ratio mínimo
                if(calculatedTP < calculatedSL * InpMinRiskRewardRatio) {
                    calculatedTP = calculatedSL * InpMinRiskRewardRatio;
                    if(InpDebugDynamic) {
                        Print("⚠️ TP ajustado para manter Risk/Reward ", InpMinRiskRewardRatio, ":1");
                    }
                }

                // Aplicar limites de segurança
                tpPoints = MathMax(InpMinTP, MathMin(InpMaxTP, calculatedTP));
                slPoints = MathMax(InpMinSL, MathMin(InpMaxSL, calculatedSL));

                // Salvar para debug
                lastCalculatedTP = tpPoints;
                lastCalculatedSL = slPoints;

                if(InpDebugDynamic) {
                    Print("📊 TP/SL DINÂMICO CALCULADO:");
                    Print("  ATR atual: ", DoubleToString(currentATR, 5));
                    Print("  ATR em pontos: ", DoubleToString(atrInPoints, 1));
                    Print("  TP calculado: ", DoubleToString(calculatedTP, 1), " → Final: ", DoubleToString(tpPoints, 1));
                    Print("  SL calculado: ", DoubleToString(calculatedSL, 1), " → Final: ", DoubleToString(slPoints, 1));
                    Print("  Risk/Reward: 1:", DoubleToString(tpPoints/slPoints, 2));

                    // Indicar se houve limitação
                    if(calculatedTP != tpPoints || calculatedSL != slPoints) {
                        Print("  ⚠️ Valores limitados pelos parâmetros de segurança!");
                    }

                    // Análise de volatilidade
                    string volatility = "";
                    if(atrInPoints < 30) volatility = "BAIXA 🟢";
                    else if(atrInPoints < 60) volatility = "MÉDIA 🟡";
                    else volatility = "ALTA 🔴";
                    Print("  Volatilidade: ", volatility);
                }
            } else {
                // MODO FIXO: Usar valores fixos configurados
                tpPoints = InpFixedTP;
                slPoints = InpFixedSL;

                if(InpDebugDynamic) {
                    Print("📊 Usando TP/SL FIXO (modo dinâmico desativado)");
                    Print("  TP: ", tpPoints, " pontos");
                    Print("  SL: ", slPoints, " pontos");
                }
            }
        } else {
            // Fallback para valores fixos se ATR falhar
            tpPoints = InpFixedTP;
            slPoints = InpFixedSL;

            if(InpDebugDynamic) {
                Print("⚠️ Erro ao obter ATR - usando valores fixos");
            }
        }

        IndicatorRelease(atrHandle);
    } else {
        // Fallback para valores fixos
        tpPoints = InpFixedTP;
        slPoints = InpFixedSL;
    }
}

//+------------------------------------------------------------------+
//| Função para escrever log em arquivo                             |
//+------------------------------------------------------------------+
void LogToFile(string message) {
    if(debugFileHandle != INVALID_HANDLE) {
        FileWrite(debugFileHandle, TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), " | ", message);
        FileFlush(debugFileHandle);
    }
    if(InpDebugMain) {
        Print(message);
    }
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    // Abrir arquivo de debug
    string debugFileName = "HedgeLine_v6_Debug_" + Symbol() + ".log";
    debugFileHandle = FileOpen(debugFileName, FILE_WRITE|FILE_TXT|FILE_COMMON);

    // Log de início
    Print("=== EA-HedgeLine v6 com TP/SL DINÂMICOS INICIANDO ===");
    Print("Horário: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
    Print("⭐ NOVO: TP/SL adaptativo baseado em ATR!");

    if(InpUseDynamicTPSL) {
        Print("✅ MODO DINÂMICO ATIVADO");
        Print("  TP = ATR × ", InpDynamicTPMultiplier);
        Print("  SL = ATR × ", InpDynamicSLMultiplier);
        Print("  Risk/Reward mínimo: 1:", InpMinRiskRewardRatio);
        Print("  Limites TP: ", InpMinTP, "-", InpMaxTP, " pontos");
        Print("  Limites SL: ", InpMinSL, "-", InpMaxSL, " pontos");
    } else {
        Print("📌 MODO FIXO (tradicional)");
        Print("  TP fixo: ", InpFixedTP, " pontos");
        Print("  SL fixo: ", InpFixedSL, " pontos");
    }

    LogToFile("=== EA-HedgeLine v6 Debug INICIANDO ===");
    LogToFile("Símbolo: " + Symbol());
    LogToFile("Timeframe: " + IntegerToString(Period()));
    LogToFile("Modo TP/SL: " + (InpUseDynamicTPSL ? "DINÂMICO" : "FIXO"));

    // Inicializar símbolo
    if(!symbolInfo.Name(Symbol())) {
        Print("ERRO: Não foi possível inicializar símbolo");
        return INIT_FAILED;
    }

    // Configurar trade
    trade.SetExpertMagicNumber(InpMagicNumber);
    trade.SetDeviationInPoints(10);
    trade.SetTypeFilling(ORDER_FILLING_IOC);

    // Inicializar módulos
    if(InpDebugMain) Print("Inicializando módulos...");

    // TrackingManager
    Print("★★★ INICIALIZANDO TRACKINGMANAGER ★★★");
    if(!trackingMgr.Init(InpTrackingFile, InpDebugMain, true, true, InpMagicNumber, Symbol())) {
        Print("ERRO: Não foi possível inicializar TrackingManager");
        return INIT_FAILED;
    }
    Print("✓ TrackingManager INICIALIZADO COM SUCESSO");

    // SpreadManager
    spreadMgr.Init(InpUseSpreadFilter, InpMaxSpread, InpDebugSpread);
    if(InpDebugMain) Print("SpreadManager inicializado");

    // StateManager
    stateMgr.Init(InpStateFile, 5, InpDebugState);
    stateMgr.ResetState();
    if(InpDebugMain) Print("StateManager inicializado e estado RESETADO");

    // OrderManager
    orderMgr.Init(Symbol(), InpMagicNumber, InpDebugOrder, &trackingMgr);
    if(InpDebugMain) Print("OrderManager inicializado com TrackingManager");

    // DistanceControl
    double minDist = InpUseATR ? 50 : InpFixedDistance;
    double maxDist = InpUseATR ? 500 : InpFixedDistance * 3;

    if(!distanceMgr.Init(Symbol(), Period(), InpATRPeriod,
                        InpATRMultiplier, minDist, maxDist, InpDebugDistance)) {
        Print("ERRO: Não foi possível inicializar controle de distância");
        return INIT_FAILED;
    }
    if(InpDebugMain) Print("DistanceControl inicializado");

    // ReversalManager
    reversalMgr.Init(Symbol(), InpUseReverse, InpMaxReversals, InpReversalLotMultiplier,
                     InpMagicNumber, InpComment, InpDebugMain, &trackingMgr);
    if(InpDebugMain) Print("ReversalManager inicializado com TrackingManager");

    // PanelManager - INICIALIZAR E CONECTAR
    panelMgr.Init(InpShowPanel, InpDebugMain);
    if(InpDebugMain) Print("PanelManager inicializado");

    // Conectar módulos ao PanelManager
    panelMgr.ConnectModules(&trackingMgr, &reversalMgr);
    if(InpDebugMain) Print("★ Módulos conectados ao PanelManager");

    // Atualizar painel inicial
    panelMgr.UpdateState(stateMgr.GetState());
    if(InpDebugMain) Print("PanelManager: estado inicial atualizado");

    systemReady = true;
    Print("=== Sistema HedgeLine v6 PRONTO ===");

    // Teste inicial do cálculo dinâmico
    if(InpUseDynamicTPSL && InpDebugDynamic) {
        Print("\n🔬 TESTE INICIAL DO SISTEMA DINÂMICO:");
        double testTP, testSL;
        CalculateDynamicTPSL(testTP, testSL);
    }

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    Print("=== EA-HedgeLine v6 ENCERRANDO ===");
    Print("Motivo: ", reason);

    // Salvar estado final
    stateMgr.SaveToFile(InpStateFile);

    // Finalizar TrackingManager
    trackingMgr.Deinit();

    // Remover painel
    panelMgr.RemovePanel();

    // Fechar arquivo de debug
    if(debugFileHandle != INVALID_HANDLE) {
        FileClose(debugFileHandle);
    }

    Print("=== Sistema encerrado ===");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    if(!systemReady) return;

    tickCounter++;

    // Debug de ticks
    if(InpDebugTicks && tickCounter % 100 == 0) {
        Print("Tick #", tickCounter, " - Horário: ", TimeToString(TimeCurrent(), TIME_SECONDS));
    }

    // Verificação periódica de reversões
    if(tickCounter % 10 == 0 && InpUseReverse) {
        static datetime lastPeriodicCheck = 0;
        if(TimeCurrent() - lastPeriodicCheck > 5) {
            bool periodicReversal = reversalMgr.CheckRecentStopLossesAndReverse();
            if(periodicReversal && InpDebugMain) {
                Print("✓ [ONTICK] Reversão executada via verificação periódica!");
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

    // Verificar fechamento de fim de dia
    CheckEndOfDayClose();

    // Verificar estado do sistema
    HedgeLineState currentState = stateMgr.GetState();

    // Verificar limites diários
    if(currentState.dailyProfit <= -InpMaxDailyLoss) {
        if(InpDebugMain) Print("Limite de perda diária atingido");
        return;
    }

    if(currentState.dailyProfit >= InpMaxDailyProfit) {
        if(InpDebugMain) Print("Limite de lucro diário atingido");
        return;
    }

    if(currentState.dailyTrades >= InpMaxDailyTrades) {
        if(InpDebugMain) Print("Limite de trades diários atingido");
        return;
    }

    // Verificar horário de negociação
    if(InpUseTimeFilter) {
        if(!IsWithinTradingTime()) {
            if(InpDebugMain && tickCounter % 1000 == 0) {
                Print("Fora do horário de negociação");
            }
            return;
        }
    }

    // Verificar spread
    if(!spreadMgr.CheckSpread()) {
        if(InpDebugSpread) Print("Spread muito alto");
        return;
    }

    // Verificar posições abertas
    if(orderMgr.HasOpenPosition()) {
        if(InpDebugMain && tickCounter % 100 == 0) {
            Print("Já existe posição aberta");
        }

        // Atualizar painel mesmo com posição aberta
        if(tickCounter % 10 == 0) {
            panelMgr.UpdateState(currentState);
        }
        return;
    }

    // Processar sinal de entrada
    ProcessEntry();

    // Atualizar painel a cada 10 ticks
    if(tickCounter % 10 == 0) {
        panelMgr.UpdateState(currentState);
    }
}

//+------------------------------------------------------------------+
//| Processar entrada de trade                                      |
//+------------------------------------------------------------------+
void ProcessEntry() {
    // Verificar distância do último trade
    if(!distanceMgr.CheckDistance()) {
        if(InpDebugDistance) {
            double currentDist = distanceMgr.GetCurrentDistance();
            double minDist = distanceMgr.GetMinDistance();
            Print("Distância insuficiente: ",
                  DoubleToString(currentDist, 1), " < ",
                  DoubleToString(minDist, 1), " pontos");
        }
        return;
    }

    // Obter distância calculada
    double distance = InpUseATR ? distanceMgr.GetATRDistance() : InpFixedDistance;

    // ⭐ NOVO v6: Calcular TP/SL dinâmicos
    double tpPoints, slPoints;
    CalculateDynamicTPSL(tpPoints, slPoints);

    // Calcular níveis baseados na distância
    double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);

    // Níveis de entrada pendente
    double buyStopPrice = NormalizeDouble(ask + distance * point, symbolInfo.Digits());
    double sellStopPrice = NormalizeDouble(bid - distance * point, symbolInfo.Digits());

    // Verificar se os preços são válidos
    if(buyStopPrice <= ask || sellStopPrice >= bid) {
        if(InpDebugMain) {
            Print("ERRO: Preços de entrada inválidos");
            Print("BuyStop: ", buyStopPrice, " Ask: ", ask);
            Print("SellStop: ", sellStopPrice, " Bid: ", bid);
        }
        return;
    }

    // TP e SL usando valores dinâmicos ou fixos
    double buyTP = NormalizeDouble(buyStopPrice + tpPoints * point, symbolInfo.Digits());
    double buySL = NormalizeDouble(buyStopPrice - slPoints * point, symbolInfo.Digits());

    double sellTP = NormalizeDouble(sellStopPrice - tpPoints * point, symbolInfo.Digits());
    double sellSL = NormalizeDouble(sellStopPrice + slPoints * point, symbolInfo.Digits());

    if(InpDebugMain) {
        Print("\n=== ABRINDO NOVAS ORDENS PENDENTES v6 ===");
        Print("Distância: ", DoubleToString(distance, 1), " pontos");

        if(InpUseDynamicTPSL) {
            Print("⭐ TP/SL DINÂMICO:");
            Print("  ATR atual: ", DoubleToString(currentATR, 5));
            Print("  TP: ", DoubleToString(tpPoints, 1), " pontos (ATR×", InpDynamicTPMultiplier, ")");
            Print("  SL: ", DoubleToString(slPoints, 1), " pontos (ATR×", InpDynamicSLMultiplier, ")");
            Print("  Risk/Reward: 1:", DoubleToString(tpPoints/slPoints, 2));
        } else {
            Print("📌 TP/SL FIXO:");
            Print("  TP: ", DoubleToString(tpPoints, 1), " pontos");
            Print("  SL: ", DoubleToString(slPoints, 1), " pontos");
        }

        Print("BUY STOP: Preço=", buyStopPrice, " TP=", buyTP, " SL=", buySL);
        Print("SELL STOP: Preço=", sellStopPrice, " TP=", sellTP, " SL=", sellSL);
    }

    // Criar comentário único para rastreamento
    string timestamp = IntegerToString(GetTickCount());
    string buyComment = InpComment + "_BUY_" + timestamp;
    string sellComment = InpComment + "_SELL_" + timestamp;

    // Atualizar TrackingManager ANTES de abrir ordens
    trackingMgr.OnPendingOrderPlacement("BUYSTOP", buyStopPrice, InpLotSize, buyTP, buySL, buyComment);
    trackingMgr.OnPendingOrderPlacement("SELLSTOP", sellStopPrice, InpLotSize, sellTP, sellSL, sellComment);

    // Colocar ordem BUY STOP
    trade.BuyStop(InpLotSize, buyStopPrice, Symbol(), buySL, buyTP,
                  ORDER_TIME_DAY, 0, buyComment);

    if(trade.ResultRetcode() != TRADE_RETCODE_DONE) {
        Print("ERRO ao colocar BUY STOP: ", trade.ResultRetcodeDescription());
        trackingMgr.OnOrderError("BUYSTOP", trade.ResultRetcode(), trade.ResultRetcodeDescription());
    } else {
        if(InpDebugMain) Print("✓ BUY STOP colocada com sucesso");
        // Rastrear ticket da ordem pendente
        trackingMgr.OnPendingOrderSuccess("BUYSTOP", trade.ResultOrder());
    }

    // Colocar ordem SELL STOP
    trade.SellStop(InpLotSize, sellStopPrice, Symbol(), sellSL, sellTP,
                   ORDER_TIME_DAY, 0, sellComment);

    if(trade.ResultRetcode() != TRADE_RETCODE_DONE) {
        Print("ERRO ao colocar SELL STOP: ", trade.ResultRetcodeDescription());
        trackingMgr.OnOrderError("SELLSTOP", trade.ResultRetcode(), trade.ResultRetcodeDescription());
    } else {
        if(InpDebugMain) Print("✓ SELL STOP colocada com sucesso");
        // Rastrear ticket da ordem pendente
        trackingMgr.OnPendingOrderSuccess("SELLSTOP", trade.ResultOrder());
    }

    // Registrar último trade
    distanceMgr.RegisterTrade();

    // Incrementar contador de trades diários
    stateMgr.UpdateDailyTrades(1);
    stateMgr.UpdateReversals(0, false);

    if(InpDebugMain) {
        Print("=== Ordens pendentes colocadas ===");
        if(InpUseDynamicTPSL) {
            Print("⭐ Usando TP/SL dinâmicos baseados na volatilidade atual");
        }
    }
}

//+------------------------------------------------------------------+
//| OnTrade function                                                |
//+------------------------------------------------------------------+
void OnTrade() {
    if(!systemReady) return;

    // Atualizar tipo da posição para ReversalManager
    ENUM_POSITION_TYPE posType = orderMgr.GetCurrentPositionType();
    reversalMgr.UpdateLastPositionType(posType);

    // Atualizar lote atual
    reversalMgr.UpdateCurrentLotSize(InpLotSize);

    if(InpDebugMain && posType != -1) {
        Print("Posição ABERTA detectada - Tipo: ", EnumToString(posType));
        Print("Lote configurado no ReversalManager: ", DoubleToString(InpLotSize, 2));
    }

    // Processar último deal
    ulong lastDeal = HistoryDealGetTicket(HistoryDealsTotal() - 1);
    if(lastDeal > 0) {
        HistoryDealSelect(lastDeal);

        double lastProfit = HistoryDealGetDouble(lastDeal, DEAL_PROFIT);
        double lastSwap = HistoryDealGetDouble(lastDeal, DEAL_SWAP);
        double lastCommission = HistoryDealGetDouble(lastDeal, DEAL_COMMISSION);
        double totalResult = lastProfit + lastSwap + lastCommission;

        ENUM_DEAL_REASON reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(lastDeal, DEAL_REASON);

        if(InpDebugMain) {
            Print("Deal #", lastDeal, " processado - Lucro: ", totalResult,
                  " Razão: ", EnumToString(reason));
        }

        // Se foi stop loss, verificar reversão
        if(reason == DEAL_REASON_SL && InpUseReverse) {
            Print("★★★ [ONTRADE] STOP LOSS DETECTADO! ★★★");
            Print("  Processando reversão via ReversalManager...");

            ReversalState currentState = reversalMgr.GetState();
            ReversalConfig currentConfig = reversalMgr.GetConfig();
            Print("  Estado Atual:");
            Print("    currentReversals: ", currentState.currentReversals);
            Print("    maxReversals: ", currentConfig.maxReversals);

            bool reversalExecuted = reversalMgr.ProcessTradeEvent();
            Print("← ProcessTradeEvent() retornou: ", (reversalExecuted ? "SUCCESS" : "FAILED"));

            if(reversalExecuted) {
                ReversalState revState = reversalMgr.GetState();
                stateMgr.UpdateReversals(revState.currentReversals, revState.inReversal);

                Print("✓ REVERSÃO EXECUTADA COM SUCESSO!");
                Print("  Reversão #", revState.currentReversals, "/", currentConfig.maxReversals);
            } else {
                Print("✖ REVERSÃO NÃO EXECUTADA");
            }
        }
        // Se foi take profit ou lucro, resetar reversões
        else if(lastProfit > 0 || reason == DEAL_REASON_TP) {
            reversalMgr.ResetReversals();
            stateMgr.UpdateReversals(0, false);

            if(InpDebugMain) {
                Print("✓ Trade lucrativo - Contador de reversões resetado");
            }
        }

        // Atualizar estado
        stateMgr.UpdateProfit(totalResult);
    }

    // Verificação adicional de stop losses recentes
    if(InpUseReverse) {
        bool additionalReversal = reversalMgr.CheckRecentStopLossesAndReverse();
        if(additionalReversal) {
            Print("✓ [ONTRADE] Reversão executada via verificação adicional!");
            ReversalState revState = reversalMgr.GetState();
            stateMgr.UpdateReversals(revState.currentReversals, revState.inReversal);
        }
    }

    // Cancelar ordens pendentes opostas se uma foi ativada
    if(orderMgr.HasOpenPosition()) {
        orderMgr.CancelPendingOrders();
        if(InpDebugMain) Print("Ordens pendentes opostas canceladas");
    }

    // Atualizar painel
    HedgeLineState currentState = stateMgr.GetState();
    panelMgr.UpdateState(currentState);
}

//+------------------------------------------------------------------+
//| OnChartEvent function                                            |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam) {
    // Processar eventos do painel
    panelMgr.OnChartEvent(id, lparam, dparam, sparam);

    // Tecla P para toggle do painel
    if(id == CHARTEVENT_KEYDOWN && lparam == 'P') {
        panelMgr.TogglePanel();
    }
}

//+------------------------------------------------------------------+
//| Verificar se está dentro do horário de negociação               |
//+------------------------------------------------------------------+
bool IsWithinTradingTime() {
    MqlDateTime now;
    TimeToStruct(TimeCurrent(), now);

    string currentTime = StringFormat("%02d:%02d", now.hour, now.min);

    return (currentTime >= InpStartTime && currentTime <= InpEndTime);
}

//+------------------------------------------------------------------+
//| Verificar fechamento de fim de dia                              |
//+------------------------------------------------------------------+
void CheckEndOfDayClose() {
    if(!InpCloseAllEndDay) return;

    MqlDateTime now;
    TimeToStruct(TimeCurrent(), now);

    string currentTime = StringFormat("%02d:%02d", now.hour, now.min);

    if(currentTime >= InpCloseTime) {
        // Fechar todas as posições
        orderMgr.CloseAllPositions();

        // Cancelar ordens pendentes
        orderMgr.CancelPendingOrders();

        if(InpDebugMain) {
            Print("=== Fechamento de fim de dia executado às ", currentTime, " ===");
        }
    }
}

//+------------------------------------------------------------------+