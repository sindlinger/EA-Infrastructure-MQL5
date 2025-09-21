//+------------------------------------------------------------------+
//|                                          EA-HedgeLine_v3_Modular |
//|                    Sistema HedgeLine v3 - Debug Individual       |
//|                                  Copyright 2025, HedgeLine EA    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, HedgeLine EA"
#property link      "https://www.hedgeline.com"
#property version   "3.00"
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
input string   InpStateFile            = "HedgeLine_State.csv"; // Arquivo de Estado

input group "=== Debug Individual por Módulo ==="
input bool     InpDebugMain            = true;      // Debug EA Principal
input bool     InpDebugSpread          = true;      // Debug SpreadManager
input bool     InpDebugState           = true;      // Debug StateManager
input bool     InpDebugOrder           = true;      // Debug OrderManager
input bool     InpDebugDistance        = true;      // Debug DistanceControl
input bool     InpDebugTicks           = false;     // Debug Contador de Ticks

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
int            debugFileHandle = INVALID_HANDLE;  // Handle para arquivo de debug

//+------------------------------------------------------------------+
//| Função para escrever log em arquivo                             |
//+------------------------------------------------------------------+
void LogToFile(string message) {
    if(debugFileHandle != INVALID_HANDLE) {
        FileWrite(debugFileHandle, TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), " | ", message);
        FileFlush(debugFileHandle);
    }
    // Também imprimir no log normal se debug ativo
    if(InpDebugMain) {
        Print(message);
    }
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    // Abrir arquivo de debug
    string debugFileName = "HedgeLine_Debug_" + Symbol() + ".log";
    debugFileHandle = FileOpen(debugFileName, FILE_WRITE|FILE_TXT|FILE_COMMON);

    // Log de início
    Print("=== EA-HedgeLine v3 Modular INICIANDO ===");
    Print("Horário: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));

    LogToFile("=== EA-HedgeLine v3 Debug INICIANDO ===");
    LogToFile("Símbolo: " + Symbol());
    LogToFile("Timeframe: " + IntegerToString(Period()));

    // Inicializar símbolo
    if(!symbolInfo.Name(Symbol())) {
        Print("ERRO: Não foi possível inicializar símbolo");
        return INIT_FAILED;
    }

    // Configurar trade
    trade.SetExpertMagicNumber(InpMagicNumber);
    trade.SetDeviationInPoints(10);
    trade.SetTypeFilling(ORDER_FILLING_IOC);

    // Inicializar módulos com debug individual
    if(InpDebugMain) Print("Inicializando módulos...");

    // SpreadManager
    spreadMgr.Init(InpUseSpreadFilter, InpMaxSpread, InpDebugSpread);
    if(InpDebugMain) Print("SpreadManager inicializado");

    // StateManager
    stateMgr.Init(InpStateFile, 5, InpDebugState);  // Save a cada 5 minutos
    stateMgr.ResetState();  // FORÇAR reset para garantir sistema ativo
    if(InpDebugMain) Print("StateManager inicializado e estado RESETADO");

    // OrderManager
    orderMgr.Init(Symbol(), InpMagicNumber, InpDebugOrder);
    if(InpDebugMain) Print("OrderManager inicializado");

    // DistanceControl
    double minDist = InpUseATR ? 50 : InpFixedDistance;
    double maxDist = InpUseATR ? 500 : InpFixedDistance * 3;

    if(!distanceMgr.Init(Symbol(), Period(), InpATRPeriod,
                        InpATRMultiplier, minDist, maxDist, InpDebugDistance)) {
        Print("ERRO: Não foi possível inicializar controle de distância");
        if(InpDebugMain) {
            Print("Detalhes: Symbol=", Symbol(), " Period=", Period(),
                  " ATRPeriod=", InpATRPeriod);
        }
        return INIT_FAILED;
    }
    if(InpDebugMain) Print("DistanceControl inicializado");

    // Carregar estado anterior se existir
    if(stateMgr.LoadState()) {
        if(InpDebugMain) Print("Estado anterior carregado");
    }

    // Sistema pronto
    systemReady = true;
    Print("=== HedgeLine v3 Modular Iniciado ===");
    Print("Símbolo: ", Symbol());
    Print("Timeframe: ", EnumToString(Period()));
    Print("Filtros: Spread=", InpUseSpreadFilter, " Time=", InpUseTimeFilter);

    // Mostrar status de debug
    if(InpDebugMain || InpDebugSpread || InpDebugState || InpDebugOrder || InpDebugDistance) {
        Print("Debug ativo: Main=", InpDebugMain,
              " Spread=", InpDebugSpread,
              " State=", InpDebugState,
              " Order=", InpDebugOrder,
              " Distance=", InpDebugDistance);
    }

    if(InpUseATR) {
        Print("Usando ATR: Period=", InpATRPeriod, " Mult=", InpATRMultiplier);
    } else {
        Print("Distâncias Fixas: Dist=", InpFixedDistance, " SL=", InpFixedSL, " TP=", InpFixedTP);
    }

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    LogToFile("=== EA FINALIZANDO - Reason: " + IntegerToString(reason) + " ===");

    // Salvar estado final
    stateMgr.SaveState(true);

    // Fechar arquivo de debug
    if(debugFileHandle != INVALID_HANDLE) {
        FileClose(debugFileHandle);
        debugFileHandle = INVALID_HANDLE;
    }

    // Fechar posições abertas
    if(orderMgr.HasPosition()) {
        orderMgr.CloseCurrentPosition();
    }

    // Cancelar ordens pendentes
    orderMgr.CancelAllPendingOrders();

    Print("=== HedgeLine v3 Finalizado ===");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    // Incrementar contador de OnTick
    stateMgr.IncrementOnTickCalls();

    // Debug entrada em OnTick
    static int onTickEntryCount = 0;
    if(++onTickEntryCount % 100 == 0 && InpDebugMain) {
        LogToFile(StringFormat("→ OnTick entrada #%d - systemReady=%s",
                              onTickEntryCount, (systemReady ? "true" : "false")));
    }

    if(!systemReady) {
        static int blockedCount = 0;
        if(++blockedCount % 100 == 0 && InpDebugMain) {
            LogToFile(StringFormat("❌ OnTick BLOQUEADO por systemReady=false (#%d)", blockedCount));
        }
        return;
    }

    static int totalTicks = 0;
    totalTicks++;

    // Log do primeiro tick
    static bool firstTick = true;
    if(firstTick) {
        LogToFile(">>> Primeiro OnTick VÁLIDO executado! systemReady=true");
        Print(">>> Primeiro OnTick executado!");
        // Refresh antes de mostrar preços
        if(symbolInfo.RefreshRates()) {
            Print(">>> Bid=", symbolInfo.Bid(), " Ask=", symbolInfo.Ask());
        } else {
            Print(">>> ERRO: Não foi possível obter preços iniciais!");
        }
        firstTick = false;
    }

    // Salvar estado a cada 100 ticks
    if(totalTicks % 100 == 0) {
        stateMgr.SaveState(true);  // Forçar salvamento
        LogToFile(StringFormat("Estado salvo - Tick #%d", totalTicks));
    }

    // Debug detalhado do fluxo
    static datetime lastFlowLog = 0;
    if(InpDebugMain && TimeCurrent() - lastFlowLog > 30) {
        SystemState state = stateMgr.GetState();
        double spread = spreadMgr.GetRealSpread();
        Print("=== DEBUG FLUXO OnTick ===");
        Print("1. Sistema Ativo: ", state.systemActive);
        Print("2. Spread atual: ", DoubleToString(spread, 1), " / ", InpMaxSpread, " pontos");
        Print("3. Filtro tempo: ", (InpUseTimeFilter ? "ATIVO" : "DESATIVADO"));
        Print("4. Trades hoje: ", state.dailyTrades, " / ", InpMaxDailyTrades);
        Print("5. Tem posição: ", (orderMgr.HasPosition() ? "SIM" : "NÃO"));
        Print("6. Tem ordens pendentes: ", (orderMgr.HasPendingOrders() ? "SIM" : "NÃO"));
        lastFlowLog = TimeCurrent();
    }

    // Contador de ticks (opcional)
    static int tickCount = 0;
    static datetime lastTickLog = 0;
    tickCount++;

    if(InpDebugTicks && TimeCurrent() - lastTickLog > 60) {  // A cada minuto
        Print("OnTick: ", tickCount, " ticks no último minuto");
        lastTickLog = TimeCurrent();
        tickCount = 0;
    }

    // Verificar novo dia
    if(stateMgr.CheckNewDay()) {
        OnNewDay();
    }

    // Verificar spread
    if(!spreadMgr.ValidateSpread()) {
        stateMgr.UpdateBlockReason("SpreadAlto");
        static datetime lastLog1 = 0;
        if(TimeCurrent() - lastLog1 > 60) {  // A cada minuto para debug
            double currentSpread = spreadMgr.GetRealSpread();
            string msg = StringFormat("⚠️ BLOQUEIO: Spread muito alto - %.1f pontos (limite: %d)",
                                    currentSpread, InpMaxSpread);
            LogToFile(msg);
            lastLog1 = TimeCurrent();
        }
        return;
    }

    // Debug - passou pelo spread
    stateMgr.IncrementSpreadCheckPassed();
    static int spreadPassCount = 0;
    if(++spreadPassCount % 50 == 0 && InpDebugMain) {
        LogToFile(StringFormat("✓ Spread OK - passou %d vezes", spreadPassCount));
    }

    // Debug - antes do filtro de tempo
    static int timeCheckCount = 0;
    if(++timeCheckCount % 50 == 0 && InpDebugMain) {
        LogToFile(StringFormat("→ Verificando filtro de tempo (#%d) - InpUseTimeFilter=%s",
                              timeCheckCount, (InpUseTimeFilter ? "true" : "false")));
    }

    // Verificar filtro de tempo
    if(!CheckTimeFilter()) {
        stateMgr.UpdateBlockReason("TimeFilter");
        static datetime lastLog2 = 0;
        if(TimeCurrent() - lastLog2 > 60) {  // A cada minuto para debug
            datetime currentTime = TimeCurrent();
            MqlDateTime dt;
            TimeToStruct(currentTime, dt);
            string msg = StringFormat("⚠️ BLOQUEIO: Fora do horário - %02d:%02d (Período: %s - %s)",
                                    dt.hour, dt.min, InpStartTime, InpEndTime);
            LogToFile(msg);
            Print("⚠️ Fora do horário de operação - Hora atual: ",
                  dt.hour, ":", dt.min,
                  " (Filtro: ", (InpUseTimeFilter ? "ATIVO" : "DESATIVADO"),
                  " Período: ", InpStartTime, " - ", InpEndTime, ")");
            lastLog2 = TimeCurrent();
        }
        return;
    }

    // Debug - passou pelo filtro de tempo
    stateMgr.IncrementTimeFilterPassed();
    static int timePassCount = 0;
    if(++timePassCount % 50 == 0 && InpDebugMain) {
        LogToFile(StringFormat("✓ Filtro tempo OK - passou %d vezes", timePassCount));
    }

    // Debug - antes dos limites diários
    static int dailyCheckCount = 0;
    if(++dailyCheckCount % 50 == 0 && InpDebugMain) {
        SystemState state = stateMgr.GetState();
        LogToFile(StringFormat("→ Verificando limites diários (#%d) - Trades hoje: %d/%d",
                              dailyCheckCount, state.dailyTrades, InpMaxDailyTrades));
    }

    // Verificar limites diários
    if(!CheckDailyLimits()) {
        stateMgr.UpdateBlockReason("DailyLimit");
        static datetime lastLog3 = 0;
        if(TimeCurrent() - lastLog3 > 60) {  // A cada minuto para debug
            SystemState state = stateMgr.GetState();
            string msg = StringFormat("⚠️ BLOQUEIO: Limite diário - %d trades de %d permitidos",
                                    state.dailyTrades, InpMaxDailyTrades);
            LogToFile(msg);
            lastLog3 = TimeCurrent();
        }
        return;
    }

    // Debug - passou pelos limites diários
    stateMgr.IncrementDailyLimitsPassed();
    static int dailyPassCount = 0;
    if(++dailyPassCount % 50 == 0 && InpDebugMain) {
        LogToFile(StringFormat("✓ Limites diários OK - passou %d vezes", dailyPassCount));
    }

    // Debug: confirmação de que chegou em ProcessTrades
    if(InpDebugMain) {
        static datetime lastProcessLog = 0;
        if(TimeCurrent() - lastProcessLog > 30) {  // A cada 30 segundos para debug
            SystemState state = stateMgr.GetState();
            Print("✓ Chegou em ProcessTrades - Spread OK, Time OK, Limites OK");
            Print("   Estado: Active=", state.systemActive,
                  " DailyTrades=", state.dailyTrades,
                  " HasPosition=", orderMgr.HasPosition());
            lastProcessLog = TimeCurrent();
        }
    }

    // Atualizar preço atual - IMPORTANTE: Refresh antes de obter preços!
    if(!symbolInfo.RefreshRates()) {
        if(InpDebugMain) {
            static int refreshFailCount = 0;
            if(++refreshFailCount % 100 == 0) {
                LogToFile(StringFormat("❌ Falha ao atualizar preços (#%d)", refreshFailCount));
            }
        }
        return;
    }

    double currentBid = symbolInfo.Bid();
    double currentAsk = symbolInfo.Ask();

    // Debug dos preços
    static int priceCheckCount = 0;
    if(++priceCheckCount % 50 == 0 && InpDebugMain) {
        LogToFile(StringFormat("→ Preços: Bid=%.5f Ask=%.5f (#%d)",
                              currentBid, currentAsk, priceCheckCount));
    }

    // Verificar se preços são válidos
    if(currentBid <= 0 || currentAsk <= 0) {
        stateMgr.UpdateBlockReason("InvalidPrice");
        stateMgr.IncrementBlockedByPrice();
        static int invalidPriceCount = 0;
        if(++invalidPriceCount % 10 == 0 && InpDebugMain) {
            LogToFile(StringFormat("❌ BLOQUEIO: Preços inválidos - Bid=%.5f Ask=%.5f (#%d)",
                                  currentBid, currentAsk, invalidPriceCount));
        }
        return;
    }

    // Debug - chegou até ProcessTrades
    static int beforeProcessCount = 0;
    if(++beforeProcessCount % 50 == 0 && InpDebugMain) {
        LogToFile(StringFormat("✓ Pronto para ProcessTrades - todos os checks OK (#%d)",
                              beforeProcessCount));
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
    static int processCount = 0;
    processCount++;

    // Incrementar contador no StateManager
    stateMgr.IncrementProcessTrades();

    // Log de entrada em ProcessTrades
    if(InpDebugMain) {
        static int logCount = 0;
        if(++logCount % 10 == 0) {
            LogToFile(StringFormat("→ ProcessTrades #%d - Bid=%.5f Ask=%.5f",
                                 processCount, bidPrice, askPrice));
        }
    }

    // Verificar status de posições e ordens
    bool hasPos = orderMgr.HasPosition();
    bool hasOrders = orderMgr.HasPendingOrders();

    // Debug detalhado do status
    if(InpDebugMain) {
        static int statusCount = 0;
        if(++statusCount % 20 == 0) {
            LogToFile(StringFormat("   Status: HasPosition=%s, HasPendingOrders=%s (#%d)",
                                 (hasPos ? "SIM" : "NÃO"),
                                 (hasOrders ? "SIM" : "NÃO"),
                                 statusCount));
        }
    }

    // Verificar se tem posição aberta
    if(hasPos) {
        stateMgr.IncrementBlockedByPosition();
        static datetime lastPosLog = 0;
        if(TimeCurrent() - lastPosLog > 300 && InpDebugMain) {  // A cada 5 minutos
            LogToFile("⚠️ BLOQUEIO: Tem posição aberta - não criar ordens");
            lastPosLog = TimeCurrent();
        }
        stateMgr.UpdateBlockReason("HasPosition");
        return;
    }

    // Debug de preços
    if(InpDebugMain) {
        static datetime lastPriceLog = 0;
        if(TimeCurrent() - lastPriceLog > 60) {
            Print("ProcessTrades: Bid=", DoubleToString(bidPrice, _Digits),
                  " Ask=", DoubleToString(askPrice, _Digits));
            lastPriceLog = TimeCurrent();
        }
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

    // Debug das distâncias
    if(InpDebugMain || InpDebugDistance) {
        static datetime lastDistLog = 0;
        if(TimeCurrent() - lastDistLog > 60) {
            Print("Distâncias: Base=", DoubleToString(distance, 1),
                  " SL=", DoubleToString(slDistance, 1),
                  " TP=", DoubleToString(tpDistance, 1), " pontos");
            lastDistLog = TimeCurrent();
        }
    }

    // Validar distância para spread atual
    double currentSpread = spreadMgr.GetRealSpread();
    if(!distanceMgr.ValidateDistanceForSpread(currentSpread)) {
        stateMgr.IncrementBlockedByDistance();
        stateMgr.UpdateBlockReason("DistanceTooSmall");
        if(InpDebugMain) {
            static datetime lastWarn = 0;
            if(TimeCurrent() - lastWarn > 300) {
                LogToFile(StringFormat("⚠️ BLOQUEIO: Distância muito pequena para spread: %.1f pontos",
                                      currentSpread));
                Print("⚠️ Distância muito pequena para spread: ",
                      DoubleToString(currentSpread, 1), " pontos");
                lastWarn = TimeCurrent();
            }
        }
        return;
    }

    // Debug - passou pela validação de distância
    if(InpDebugMain) {
        static int distPassCount = 0;
        if(++distPassCount % 20 == 0) {
            LogToFile(StringFormat("✓ Distância OK para spread %.1f (#%d)",
                                  currentSpread, distPassCount));
        }
    }

    // Criar ou recriar ordens pendentes
    stateMgr.IncrementOrderCheckCalls();
    if(InpDebugMain || InpDebugOrder) {
        static int checkOrderCount = 0;
        if(++checkOrderCount % 10 == 0) {
            string msg = StringFormat("→ Verificando ordens (#%d) - HasPos: %s, HasOrders: %s",
                                    checkOrderCount,
                                    (hasPos ? "SIM" : "NÃO"),
                                    (hasOrders ? "SIM" : "NÃO"));
            LogToFile(msg);
        }
    }

    if(!orderMgr.RecreateOrdersAfterTP(bidPrice, askPrice, distance,
                                       slDistance, tpDistance, InpLotSize)) {
        if(InpDebugMain || InpDebugOrder) {
            LogToFile(StringFormat(">>> Tentando criar ordens - Dist: %.1f, SL: %.1f, TP: %.1f",
                                 distance, slDistance, tpDistance));
        }

        // Incrementar tentativas
        stateMgr.IncrementCreateOrderAttempts();

        bool created = orderMgr.CreatePendingOrders(bidPrice, askPrice, distance,
                                     slDistance, tpDistance, InpLotSize);

        if(created) {
            string msg = StringFormat("✅ ORDENS CRIADAS! Dist: %.1f pts, SL: %.1f pts, TP: %.1f pts",
                                    distance, slDistance, tpDistance);
            LogToFile(msg);
        } else {
            LogToFile("❌ FALHA ao criar ordens pendentes");
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
        if(InpDebugMain) {
            static datetime lastLog = 0;
            if(TimeCurrent() - lastLog > 3600) {  // A cada hora
                Print("Limite diário de trades atingido: ", state.dailyTrades);
                lastLog = TimeCurrent();
            }
        }
        return false;
    }

    // Calcular P&L diário
    double dailyPL = CalculateDailyPL();

    // Verificar perda máxima
    if(dailyPL <= -InpMaxDailyLoss) {
        if(InpDebugMain) {
            static datetime lastLog = 0;
            if(TimeCurrent() - lastLog > 3600) {
                Print("Perda máxima diária atingida: $", DoubleToString(dailyPL, 2));
                lastLog = TimeCurrent();
            }
        }
        return false;
    }

    // Verificar lucro máximo
    if(dailyPL >= InpMaxDailyProfit) {
        if(InpDebugMain) {
            static datetime lastLog = 0;
            if(TimeCurrent() - lastLog > 3600) {
                Print("Lucro máximo diário atingido: $", DoubleToString(dailyPL, 2));
                lastLog = TimeCurrent();
            }
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

    if(InpDebugMain || InpDebugState) {
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
            if(InpDebugMain) {
                Print("Reversão ", state.currentReversals + 1, " de ", InpMaxReversals);
            }
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