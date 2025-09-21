//+------------------------------------------------------------------+
//|                                          EA-HedgeLine_v2_Modular |
//|                    Sistema HedgeLine com Arquitetura Modular     |
//|                                  Copyright 2025, HedgeLine EA    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, HedgeLine EA"
#property link      "https://www.hedgeline.com"
#property version   "2.00"
#property strict

// Includes padrão do MT5
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Trade/DealInfo.mqh>

// Includes modulares do HedgeLine
#include <HedgeLine/SpreadManager.mqh>
#include <HedgeLine/StateManager.mqh>
#include <HedgeLine/OrderManager.mqh>
#include <HedgeLine/DistanceControl.mqh>

//+------------------------------------------------------------------+
//| Parâmetros de Entrada                                           |
//+------------------------------------------------------------------+
input group "=== Configurações Principais ==="
input double   InpLotSize              = 0.01;      // Volume (Lotes)
input bool     InpUseATR               = true;      // Usar ATR para Distâncias
input double   InpATRMultiplier        = 0.5;       // Multiplicador ATR
input int      InpATRPeriod            = 5;         // Período do ATR
input double   InpTPMultiplier         = 1.0;       // TP como % da distância
input double   InpSLMultiplier         = 0.5;       // SL como % da distância
input int      InpFixedDistance        = 100;       // Distância Fixa (pontos)
input int      InpFixedTP              = 100;       // TP Fixo (pontos)
input int      InpFixedSL              = 50;        // SL Fixo (pontos)

input group "=== Controle de Reversões ==="
input bool     InpUseReverse           = true;      // Usar Stop Reverse
input int      InpMaxReversals         = 3;         // Máximo de Reversões
input double   InpReversalLotMultiplier = 1.0;      // Multiplicador de Lote

input group "=== Gestão de Risco ==="
input double   InpMaxDailyLoss         = 50.0;      // Perda Máxima Diária ($)
input double   InpMaxDailyProfit       = 100.0;     // Lucro Máximo Diário ($)
input int      InpMaxDailyTrades       = 50;        // Máximo de Trades por Dia

input group "=== Filtros ==="
input bool     InpUseSpreadFilter      = true;      // Usar Filtro de Spread
input int      InpMaxSpread            = 100;       // Spread Máximo (pontos)
input bool     InpUseTimeFilter        = false;     // Usar Filtro de Horário
input string   InpStartTime            = "09:00";   // Horário de Início
input string   InpEndTime              = "17:00";   // Horário de Término

input group "=== Sistema ==="
input int      InpMagicNumber          = 20240101;  // Magic Number
input string   InpComment              = "HedgeLine"; // Comentário
input bool     InpDebugMode            = true;      // Modo Debug
input string   InpStateFile            = "HedgeLine_State.csv"; // Arquivo de Estado

//+------------------------------------------------------------------+
//| Objetos Globais dos Módulos                                     |
//+------------------------------------------------------------------+
CSpreadManager    spreadMgr;
CStateManager     stateMgr;
COrderManager     orderMgr;
CDistanceControl  distanceMgr;

// Objetos padrão
CTrade         trade;
CSymbolInfo    symbolInfo;

// Variáveis de controle
datetime       lastBarTime = 0;
bool           systemReady = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    // Log imediato para confirmar que iniciou
    Print("=== EA-HedgeLine v2 Modular INICIANDO ===");
    Print("Horário: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));

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
    Print("Inicializando SpreadManager...");
    spreadMgr.Init(InpUseSpreadFilter, InpMaxSpread, InpDebugMode);

    Print("Inicializando StateManager...");
    stateMgr.Init(InpStateFile, 5, InpDebugMode);  // Save a cada 5 minutos

    Print("Inicializando OrderManager...");
    orderMgr.Init(Symbol(), InpMagicNumber, InpDebugMode);

    // Inicializar controle de distância
    Print("Inicializando DistanceControl...");
    double minDist = InpUseATR ? 50 : InpFixedDistance;
    double maxDist = InpUseATR ? 500 : InpFixedDistance * 3;

    if(!distanceMgr.Init(Symbol(), Period(), InpATRPeriod,
                        InpATRMultiplier, minDist, maxDist, InpDebugMode)) {
        Print("ERRO: Não foi possível inicializar controle de distância");
        Print("Detalhes: Symbol=", Symbol(), " Period=", Period(),
              " ATRPeriod=", InpATRPeriod);
        return INIT_FAILED;
    }
    Print("DistanceControl inicializado com sucesso");

    // Carregar estado anterior se existir
    if(stateMgr.LoadState()) {
        Print("Estado anterior carregado com sucesso");
    }

    // Sistema pronto
    systemReady = true;
    Print("=== HedgeLine v2 Modular Iniciado ===");
    Print("Símbolo: ", Symbol());
    Print("Timeframe: ", EnumToString(Period()));
    Print("Spread Manager: ", InpUseSpreadFilter ? "Ativo" : "Inativo");
    Print("ATR: ", InpUseATR ? "Ativo" : "Fixo");
    Print("Debug Mode: ", InpDebugMode ? "ATIVO" : "Inativo");
    Print("Lote: ", InpLotSize);
    Print("Magic: ", InpMagicNumber);

    if(InpUseATR) {
        Print("ATR Config: Period=", InpATRPeriod, " Mult=", InpATRMultiplier);
    } else {
        Print("Distâncias Fixas: Dist=", InpFixedDistance, " SL=", InpFixedSL, " TP=", InpFixedTP);
    }

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    // Salvar estado final
    stateMgr.SaveState(true);

    // Fechar posições abertas
    if(orderMgr.HasPosition()) {
        orderMgr.CloseCurrentPosition();
    }

    // Cancelar ordens pendentes
    orderMgr.CancelAllPendingOrders();

    Print("=== HedgeLine v2 Finalizado ===");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    if(!systemReady) return;

    // Log do primeiro tick SEMPRE
    static bool firstTick = true;
    if(firstTick) {
        Print(">>> PRIMEIRO OnTick executado! EA está RODANDO!");
        Print(">>> Bid=", symbolInfo.Bid(), " Ask=", symbolInfo.Ask());
        firstTick = false;
    }

    // Log inicial para debug
    static int tickCount = 0;
    static datetime lastTickLog = 0;
    tickCount++;

    if(InpDebugMode && TimeCurrent() - lastTickLog > 60) {  // A cada minuto
        Print("OnTick executando (atualizado em 02:41 21/09/2025)... Ticks: ", tickCount);
        lastTickLog = TimeCurrent();
        tickCount = 0;
    }

    // Verificar novo dia
    if(stateMgr.CheckNewDay()) {
        OnNewDay();
    }

    // Verificar spread
    if(!spreadMgr.ValidateSpread()) {
        static datetime lastLog1 = 0;
        if(InpDebugMode && TimeCurrent() - lastLog1 > 300) {
            Print("❌ Bloqueado por spread alto");
            lastLog1 = TimeCurrent();
        }
        return;  // Spread muito alto, não operar
    }

    // Verificar filtro de tempo
    if(!CheckTimeFilter()) {
        static datetime lastLog2 = 0;
        if(InpDebugMode && TimeCurrent() - lastLog2 > 300) {
            Print("❌ Bloqueado por filtro de tempo");
            lastLog2 = TimeCurrent();
        }
        return;
    }

    // Verificar limites diários
    if(!CheckDailyLimits()) {
        static datetime lastLog3 = 0;
        if(InpDebugMode && TimeCurrent() - lastLog3 > 300) {
            Print("❌ Bloqueado por limites diários");
            lastLog3 = TimeCurrent();
        }
        return;
    }

    // Log de chegada em ProcessTrades
    static datetime lastProcessLog = 0;
    if(InpDebugMode && TimeCurrent() - lastProcessLog > 60) {
        Print("✓ Chegou em ProcessTrades!");
        lastProcessLog = TimeCurrent();
    }

    // Atualizar preço atual
    double currentBid = symbolInfo.Bid();
    double currentAsk = symbolInfo.Ask();

    // Verificar se preços são válidos
    if(currentBid <= 0 || currentAsk <= 0) {
        return;
    }

    // Processar posições e ordens
    ProcessTrades(currentBid, currentAsk);

    // Salvar estado periodicamente
    stateMgr.SaveState();
}

//+------------------------------------------------------------------+
//| Processar trades                                                |
//+------------------------------------------------------------------+
void ProcessTrades(double bidPrice, double askPrice) {
    // Verificar se tem posição aberta
    if(orderMgr.HasPosition()) {
        // Atualizar trailing stop se configurado
        // (pode ser adicionado depois)
        return;
    }

    // Debug: Log periódico
    static datetime lastDebugTime = 0;
    if(InpDebugMode && TimeCurrent() - lastDebugTime > 60) {  // A cada minuto
        Print("ProcessTrades: Bid=", DoubleToString(bidPrice, _Digits),
              " Ask=", DoubleToString(askPrice, _Digits));
        lastDebugTime = TimeCurrent();
    }

    // Calcular distâncias dinâmicas
    double distance, slDistance, tpDistance;

    if(InpUseATR) {
        distance = distanceMgr.CalculateDynamicDistance();
        slDistance = distance * InpSLMultiplier;
        tpDistance = distance * InpTPMultiplier;
    } else {
        distance = InpFixedDistance;
        slDistance = InpFixedSL;
        tpDistance = InpFixedTP;
    }

    // Debug das distâncias calculadas
    static datetime lastDistLog = 0;
    if(InpDebugMode && TimeCurrent() - lastDistLog > 60) {
        Print("Distâncias: Base=", DoubleToString(distance, 1),
              " SL=", DoubleToString(slDistance, 1),
              " TP=", DoubleToString(tpDistance, 1), " pontos");
        lastDistLog = TimeCurrent();
    }

    // Validar distância para spread atual
    double currentSpread = spreadMgr.GetRealSpread();
    if(!distanceMgr.ValidateDistanceForSpread(currentSpread)) {
        if(InpDebugMode) {
            static datetime lastWarn = 0;
            if(TimeCurrent() - lastWarn > 300) {  // A cada 5 minutos
                Print("Distância inválida para spread atual: ",
                      DoubleToString(currentSpread, 1), " pontos");
                lastWarn = TimeCurrent();
            }
        }
        return;
    }

    // Criar ou recriar ordens pendentes
    if(!orderMgr.RecreateOrdersAfterTP(bidPrice, askPrice, distance,
                                       slDistance, tpDistance, InpLotSize)) {
        bool created = orderMgr.CreatePendingOrders(bidPrice, askPrice, distance,
                                     slDistance, tpDistance, InpLotSize);
        if(InpDebugMode && created) {
            Print("✓ Ordens criadas - Distância: ", DoubleToString(distance, 1),
                  " pontos, SL: ", DoubleToString(slDistance, 1),
                  " pontos, TP: ", DoubleToString(tpDistance, 1), " pontos");
        }
    }

    // Atualizar estado
    SystemState state = stateMgr.GetState();
    ulong upperTicket, lowerTicket;
    orderMgr.GetOrdersInfo(upperTicket, lowerTicket);

    stateMgr.UpdateOrders(upperTicket, lowerTicket);
    stateMgr.UpdateLotSize(InpLotSize);
}

//+------------------------------------------------------------------+
//| Verificar filtro de tempo                                       |
//+------------------------------------------------------------------+
bool CheckTimeFilter() {
    if(!InpUseTimeFilter) return true;

    datetime currentTime = TimeCurrent();
    MqlDateTime dt;
    TimeToStruct(currentTime, dt);

    // Converter horários de string para minutos
    int startMinutes = (int)(StringToTime("1970.01.01 " + InpStartTime) / 60 % 1440);
    int endMinutes = (int)(StringToTime("1970.01.01 " + InpEndTime) / 60 % 1440);
    int currentMinutes = dt.hour * 60 + dt.min;

    // Verificar se está dentro do horário
    if(startMinutes < endMinutes) {
        return (currentMinutes >= startMinutes && currentMinutes <= endMinutes);
    } else {
        // Horário atravessa meia-noite
        return (currentMinutes >= startMinutes || currentMinutes <= endMinutes);
    }
}

//+------------------------------------------------------------------+
//| Verificar limites diários                                       |
//+------------------------------------------------------------------+
bool CheckDailyLimits() {
    SystemState state = stateMgr.GetState();

    // Verificar número máximo de trades
    if(state.dailyTrades >= InpMaxDailyTrades) {
        static datetime lastLog = 0;
        if(TimeCurrent() - lastLog > 3600) {  // Log a cada hora
            Print("Limite diário de trades atingido: ", state.dailyTrades);
            lastLog = TimeCurrent();
        }
        return false;
    }

    // Calcular P&L diário
    double dailyPL = CalculateDailyPL();

    // Verificar perda máxima
    if(dailyPL <= -InpMaxDailyLoss) {
        static datetime lastLog = 0;
        if(TimeCurrent() - lastLog > 3600) {
            Print("Perda máxima diária atingida: $", DoubleToString(dailyPL, 2));
            lastLog = TimeCurrent();
        }
        return false;
    }

    // Verificar lucro máximo
    if(dailyPL >= InpMaxDailyProfit) {
        static datetime lastLog = 0;
        if(TimeCurrent() - lastLog > 3600) {
            Print("Lucro máximo diário atingido: $", DoubleToString(dailyPL, 2));
            lastLog = TimeCurrent();
        }
        return false;
    }

    return true;
}

//+------------------------------------------------------------------+
//| Calcular P&L diário                                             |
//+------------------------------------------------------------------+
double CalculateDailyPL() {
    double dailyPL = 0;
    datetime todayStart = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));

    // Verificar histórico
    HistorySelect(todayStart, TimeCurrent());

    for(int i = 0; i < HistoryDealsTotal(); i++) {
        ulong ticket = HistoryDealGetTicket(i);
        if(ticket > 0) {
            if(HistoryDealGetString(ticket, DEAL_SYMBOL) == Symbol() &&
               HistoryDealGetInteger(ticket, DEAL_MAGIC) == InpMagicNumber &&
               HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT) {
                dailyPL += HistoryDealGetDouble(ticket, DEAL_PROFIT);
            }
        }
    }

    return dailyPL;
}

//+------------------------------------------------------------------+
//| Processar novo dia                                              |
//+------------------------------------------------------------------+
void OnNewDay() {
    // Resetar contadores diários
    stateMgr.UpdateDailyTrades(0);
    stateMgr.UpdateReversals(0, false);

    if(InpDebugMode) {
        Print("=== Novo dia iniciado ===");
    }
}

//+------------------------------------------------------------------+
//| Trade event                                                     |
//+------------------------------------------------------------------+
void OnTrade() {
    // Atualizar contadores quando houver trade
    SystemState state = stateMgr.GetState();

    // Verificar se houve nova posição
    if(orderMgr.HasPosition()) {
        stateMgr.IncrementDailyTrades();
        stateMgr.UpdateLastTradeTime(TimeCurrent());
    }

    // Verificar se posição foi fechada
    double lastProfit = orderMgr.GetLastClosedProfit();
    if(lastProfit != 0) {
        stateMgr.UpdateLastCloseProfit(lastProfit);

        // Se usar reversão e teve perda
        if(InpUseReverse && lastProfit < 0 && state.currentReversals < InpMaxReversals) {
            stateMgr.UpdateReversals(state.currentReversals + 1, true);
        } else if(lastProfit > 0) {
            // Resetar reversões em caso de lucro
            stateMgr.UpdateReversals(0, false);
        }
    }
}

//+------------------------------------------------------------------+
//| Timer event                                                      |
//+------------------------------------------------------------------+
void OnTimer() {
    // Pode ser usado para atualizações periódicas
}

//+------------------------------------------------------------------+
//| Chart event                                                      |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam) {
    // Pode ser usado para interface gráfica
}